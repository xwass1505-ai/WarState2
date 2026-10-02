-- DataService: server-authoritative save/load with 3 independent slots.
-- Profile key : "profile_<userId>" -> slot summaries (for the slot screen)
-- Slot keys   : "slot_<userId>_<index>" -> full country data, one key per slot (independent)
-- Saved per slot: country info, resources, population, buildings (incl. water/power status),
-- roads (road graph), infrastructure (water storage, power, shortage stage), last plot.
-- Old saves are migrated by DefaultCountry.migrate (safe defaults, nothing granted).
-- If DataStores are unavailable (e.g. Studio without API access) the session runs in MEMORY mode
-- and never writes, so a failed load can never overwrite real data.

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(Shared:WaitForChild("Config"):WaitForChild("GameConfig"))
local DefaultCountry = require(Shared:WaitForChild("Modules"):WaitForChild("DefaultCountry"))

local DataService = {}
DataService.Name = "DataService"

local store = nil
local storeError = nil
local sessions = {} -- [Player] = session
local memoryStore = {} -- used only in memory mode, lost on server shutdown

local function profileKey(userId: number): string
	return "profile_" .. tostring(userId)
end

local function slotKey(userId: number, index: number): string
	return "slot_" .. tostring(userId) .. "_" .. tostring(index)
end

local function withRetries(label: string, fn)
	local lastError = nil
	for attempt = 1, GameConfig.DataStoreRetries do
		local ok, result = pcall(fn)
		if ok then
			return true, result
		end
		lastError = result
		warn(string.format("[DataService] %s failed (attempt %d): %s", label, attempt, tostring(result)))
		local message = tostring(result)
		if string.find(message, "StudioAccessToApisNotAllowed", 1, true) or string.find(message, "API access", 1, true) then
			break -- Studio without API access: retrying cannot succeed
		end
		task.wait(attempt)
	end
	return false, lastError
end

local function newProfile()
	return { SchemaVersion = GameConfig.SchemaVersion, Summaries = {} }
end

function DataService.init(_services)
	local ok, result = pcall(function()
		return DataStoreService:GetDataStore(GameConfig.DataStoreName)
	end)
	if ok then
		store = result
	else
		storeError = tostring(result)
		warn("[DataService] DataStore unavailable, using MEMORY mode: " .. storeError)
	end
end

function DataService.start()
	task.spawn(function()
		while true do
			task.wait(GameConfig.AutosaveSeconds)
			for player in pairs(sessions) do
				task.spawn(DataService.saveActive, player)
			end
		end
	end)
	game:BindToClose(function()
		local pending = 0
		for player in pairs(sessions) do
			pending += 1
			task.spawn(function()
				DataService.saveActive(player)
				pending -= 1
			end)
		end
		local deadline = os.clock() + 25
		while pending > 0 and os.clock() < deadline do
			task.wait(0.1)
		end
	end)
end

-- Loads (or creates) the player's session. Returns session.
function DataService.loadSession(player: Player)
	if sessions[player] then
		return sessions[player]
	end
	local session = {
		player = player,
		persistent = store ~= nil,
		persistenceReason = storeError,
		profile = newProfile(),
		activeSlot = nil,
		country = nil,
		dirty = false,
	}
	if store then
		local ok, data = withRetries("Load profile", function()
			return store:GetAsync(profileKey(player.UserId))
		end)
		if ok then
			if type(data) == "table" then
				session.profile = data
				session.profile.Summaries = session.profile.Summaries or {}
			end
		else
			session.persistent = false
			session.persistenceReason = "Profile load failed: " .. tostring(data)
		end
	else
		session.profile = memoryStore[profileKey(player.UserId)] or newProfile()
	end
	sessions[player] = session
	return session
end

function DataService.getSession(player: Player)
	return sessions[player]
end

function DataService.isSlotUnlocked(index: number): boolean
	local slot = GameConfig.Slots[index]
	return slot ~= nil and slot.Unlocked == true
end

function DataService.getSlotSummaries(player: Player)
	local session = DataService.loadSession(player)
	local result = {}
	for index = 1, GameConfig.SlotCount do
		local summary = session.profile.Summaries["Slot" .. index]
		table.insert(result, {
			Index = index,
			Locked = not DataService.isSlotUnlocked(index),
			Empty = summary == nil,
			Name = summary and summary.Name or nil,
			FlagId = summary and summary.FlagId or nil,
			TechnologyBranch = summary and summary.TechnologyBranch or nil,
			Population = summary and summary.Population or nil,
			LastPlotIndex = summary and summary.LastPlotIndex or nil,
		})
	end
	return result
end

local function summarize(country)
	return {
		Name = country.Name,
		FlagId = country.FlagId,
		TechnologyBranch = country.TechnologyBranch,
		Population = country.Population,
		LastPlotIndex = country.LastPlotIndex,
		UpdatedAt = os.time(),
	}
end

local function writeProfile(session)
	local key = profileKey(session.player.UserId)
	if not session.persistent then
		memoryStore[key] = session.profile
		return true
	end
	return withRetries("Save profile", function()
		store:UpdateAsync(key, function()
			return session.profile
		end)
	end)
end

-- Loads the full country for a slot. Returns country or nil, error.
function DataService.loadSlot(player: Player, index: number)
	local session = DataService.loadSession(player)
	if session.profile.Summaries["Slot" .. index] == nil then
		return nil, "Slot is empty"
	end
	local key = slotKey(player.UserId, index)
	local data
	if session.persistent then
		local ok, result = withRetries("Load slot", function()
			return store:GetAsync(key)
		end)
		if not ok then
			return nil, "Could not load save data. Try again."
		end
		data = result
	else
		data = memoryStore[key] and DefaultCountry.deepCopy(memoryStore[key]) or nil
	end
	if type(data) ~= "table" then
		return nil, "Save data missing"
	end
	return DefaultCountry.migrate(data), nil
end

function DataService.setActive(player: Player, index: number, country)
	local session = DataService.loadSession(player)
	session.activeSlot = index
	session.country = country
	session.dirty = true
	session.profile.Summaries["Slot" .. index] = summarize(country)
end

function DataService.clearActive(player: Player)
	local session = sessions[player]
	if session then
		session.activeSlot = nil
		session.country = nil
		session.dirty = false
	end
end

function DataService.getCountry(player: Player)
	local session = sessions[player]
	return session and session.country or nil
end

function DataService.markDirty(player: Player)
	local session = sessions[player]
	if session then
		session.dirty = true
	end
end

-- Saves the active slot and the profile summary.
function DataService.saveActive(player: Player): boolean
	local session = sessions[player]
	if not session or not session.country or not session.activeSlot then
		return true
	end
	if not session.dirty then
		return true
	end
	local index = session.activeSlot
	local country = session.country
	session.profile.Summaries["Slot" .. index] = summarize(country)
	local key = slotKey(player.UserId, index)
	if not session.persistent then
		memoryStore[key] = DefaultCountry.deepCopy(country)
		memoryStore[profileKey(player.UserId)] = session.profile
		session.dirty = false
		return true
	end
	local ok = withRetries("Save slot", function()
		store:UpdateAsync(key, function()
			return country
		end)
	end)
	if ok then
		ok = writeProfile(session)
	end
	if ok then
		session.dirty = false
	end
	return ok
end

function DataService.deleteSlot(player: Player, index: number): (boolean, string?)
	local session = DataService.loadSession(player)
	if session.activeSlot == index then
		return false, "Leave the state before deleting it"
	end
	local key = slotKey(player.UserId, index)
	if session.persistent then
		local ok = withRetries("Delete slot", function()
			store:RemoveAsync(key)
		end)
		if not ok then
			return false, "Delete failed. Try again."
		end
	else
		memoryStore[key] = nil
	end
	session.profile.Summaries["Slot" .. index] = nil
	writeProfile(session)
	return true, nil
end

function DataService.releaseSession(player: Player)
	DataService.saveActive(player)
	sessions[player] = nil
end

Players.PlayerRemoving:Connect(function(player)
	-- WorldService/other systems clean up first via their own handlers; saving happens here.
	DataService.releaseSession(player)
end)

return DataService
