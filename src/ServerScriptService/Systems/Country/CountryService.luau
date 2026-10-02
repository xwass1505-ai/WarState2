-- CountryService: slot selection, country creation (server-validated), plot claiming and
-- state replication. Flow: MAIN MENU -> CREATE COUNTRY -> COUNTRY SETUP -> PLOT SELECTION -> GAME.
-- Creating or loading a country NEVER assigns a plot: the player must claim a free one.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TextService = game:GetService("TextService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = Shared:WaitForChild("Config")
local GameConfig = require(Config:WaitForChild("GameConfig"))
local TechnologyConfig = require(Config:WaitForChild("TechnologyConfig"))
local Constants = require(Shared:WaitForChild("Constants"):WaitForChild("Constants"))
local Countries = require(Shared:WaitForChild("Modules"):WaitForChild("Countries"))
local DefaultCountry = require(Shared:WaitForChild("Modules"):WaitForChild("DefaultCountry"))

local CountryService = {}
CountryService.Name = "CountryService"

local services
local remotes
local pushQueued = {}
local busy = {}

local techById = {}
for _, branch in ipairs(TechnologyConfig.Branches) do
	techById[branch.Id] = branch
end

local function cleanName(raw)
	if type(raw) ~= "string" then
		return nil, "Enter a country name"
	end
	local name = string.gsub(raw, "%s+", " ")
	name = string.match(name, "^%s*(.-)%s*$") or ""
	local length = utf8.len(name) or #name
	if length < GameConfig.CountryName.MinLength then
		return nil, "Name is too short"
	end
	if length > GameConfig.CountryName.MaxLength then
		return nil, "Name is too long"
	end
	if not string.match(name, "^[%w %-'%.]+$") then
		return nil, "Use letters, numbers, spaces, - ' ."
	end
	return name, nil
end

local function filterName(player, name)
	local ok, result = pcall(function()
		local filtered = TextService:FilterStringAsync(name, player.UserId, Enum.TextFilterContext.PublicChat)
		return filtered:GetNonChatStringForBroadcastAsync()
	end)
	if ok then
		if result ~= name then
			return nil, "That name is not allowed"
		end
		return name, nil
	end
	if RunService:IsStudio() then
		-- Text filtering is not always available in Studio; allow the already-sanitized name.
		return name, nil
	end
	return nil, "Name check failed. Try again."
end

local function snapshot(player)
	local session = services.DataService.getSession(player)
	local country = session and session.country
	if not country then
		return { Active = false, Persistent = session and session.persistent or false }
	end
	local plotIndex = services.WorldService.getPlotIndex(player)
	local built = services.StatsService.build(country, player)
	local branch = techById[country.TechnologyBranch or ""]
	return {
		Active = true,
		NeedsPlot = plotIndex == nil,
		Persistent = session.persistent,
		SlotIndex = session.activeSlot,
		Name = country.Name,
		FlagId = country.FlagId,
		Continent = country.Continent,
		TechnologyBranch = country.TechnologyBranch,
		TechnologyName = branch and branch.DisplayName or country.TechnologyBranch,
		Treasury = math.floor(country.Treasury or 0),
		Coal = country.Coal or 0,
		IronOre = country.IronOre or 0,
		Oil = country.Oil,
		Fuel = country.Fuel,
		Steel = country.Steel,
		Supplies = country.Supplies,
		Population = country.Population,
		Workers = country.Workers,
		HousingCapacity = country.HousingCapacity,
		BuildingCount = built.Stats.Buildings,
		UnderConstruction = built.Stats.UnderConstruction,
		RoadCount = built.Stats.Roads,
		PlotIndex = plotIndex,
		LastPlotIndex = country.LastPlotIndex,
		Stats = built.Stats,
		Water = built.Water,
		Power = built.Power,
		WaterList = built.WaterList,
		PowerList = built.PowerList,
		ExtraRoads = built.ExtraRoads,
		Overview = built.Overview,
		Transport = built.Transport,
		Resources = built.Resources,
		StorageCapacity = built.StorageCapacity,
		Research = built.Research,
		Economy = {
			Cycle = built.Overview.Cycle,
			Income = built.Overview.Income,
			Expenses = built.Overview.Expenses,
			Net = built.Overview.Net,
			LastNet = built.Overview.LastNet,
		},
	}
end
CountryService.snapshot = snapshot

-- Replicate the authoritative state (throttled to one push per frame).
function CountryService.push(player: Player)
	if pushQueued[player] then
		return
	end
	pushQueued[player] = true
	task.defer(function()
		pushQueued[player] = nil
		if player.Parent then
			remotes[Constants.Remotes.StateChanged]:FireClient(player, snapshot(player))
		end
	end)
end

function CountryService.notify(player: Player, message: string, kind: string?)
	remotes[Constants.Remotes.Notify]:FireClient(player, { Text = message, Kind = kind or "info" })
end

local function guard(player, fn)
	if busy[player] then
		return { ok = false, error = "Please wait" }
	end
	busy[player] = true
	local ok, result = pcall(fn)
	busy[player] = nil
	if not ok then
		warn("[CountryService] " .. tostring(result))
		return { ok = false, error = "Server error" }
	end
	return result
end

-- Activates the country in the session. The player then picks a plot (ClaimPlot).
local function activateCountry(player, index, country)
	services.DataService.setActive(player, index, country)
	services.PopulationService.recalculate(country)
	services.DataService.saveActive(player)
	CountryService.push(player)
	return { ok = true, needsPlot = true, state = snapshot(player), plots = services.WorldService.listPlots() }
end

local function handleGetProfile(player)
	local session = services.DataService.loadSession(player)
	return {
		ok = true,
		slots = services.DataService.getSlotSummaries(player),
		persistent = session.persistent,
		activeSlot = session.activeSlot,
	}
end

local function validSlotIndex(index)
	return type(index) == "number" and index == math.floor(index) and index >= 1 and index <= GameConfig.SlotCount
end

local function handleCreate(player, index, payload)
	return guard(player, function()
		if not validSlotIndex(index) then
			return { ok = false, error = "Invalid slot" }
		end
		if not services.DataService.isSlotUnlocked(index) then
			return { ok = false, error = "This slot is locked" }
		end
		local session = services.DataService.loadSession(player)
		if session.activeSlot then
			return { ok = false, error = "Leave your current state first" }
		end
		if session.profile.Summaries["Slot" .. index] ~= nil then
			return { ok = false, error = "Slot already has a state" }
		end
		if type(payload) ~= "table" then
			return { ok = false, error = "Invalid request" }
		end
		local name, nameError = cleanName(payload.Name)
		if not name then
			return { ok = false, error = nameError }
		end
		name, nameError = filterName(player, name)
		if not name then
			return { ok = false, error = nameError }
		end
		local flag = type(payload.FlagId) == "string" and Countries.get(payload.FlagId) or nil
		if not flag then
			return { ok = false, error = "Select a flag" }
		end
		if payload.Continent ~= flag.Continent then
			return { ok = false, error = "Flag does not match continent" }
		end
		local branch = type(payload.TechnologyBranch) == "string" and techById[payload.TechnologyBranch] or nil
		if not branch or branch.Active ~= true then
			return { ok = false, error = "Select a technology branch" }
		end
		local country = DefaultCountry.new(index, name, flag.Id, flag.Continent, branch.Id)
		return activateCountry(player, index, country)
	end)
end

local function handleLoad(player, index)
	return guard(player, function()
		if not validSlotIndex(index) or not services.DataService.isSlotUnlocked(index) then
			return { ok = false, error = "Invalid slot" }
		end
		local session = services.DataService.loadSession(player)
		if session.activeSlot then
			return { ok = false, error = "Leave your current state first" }
		end
		local country, err = services.DataService.loadSlot(player, index)
		if not country then
			return { ok = false, error = err }
		end
		return activateCountry(player, index, country)
	end)
end

local function handleClaimPlot(player, plotIndex)
	return guard(player, function()
		local session = services.DataService.getSession(player)
		local country = session and session.country
		if not country then
			return { ok = false, error = "Create or load a country first" }
		end
		if services.WorldService.getPlotIndex(player) then
			return { ok = false, error = "You already own a plot" }
		end
		local ok, err = services.WorldService.claim(player, plotIndex, country)
		if not ok then
			return { ok = false, error = err, plots = services.WorldService.listPlots() }
		end
		country.LastPlotIndex = plotIndex
		services.RoadService.loadCountry(player, country)
		services.RailService.loadCountry(player, country)
		services.BuildingService.loadCountry(player, country)
		services.PopulationService.recalculate(country)
		services.WaterService.recompute(player)
		services.PowerService.recompute(player)
		services.WorldService.teleportToPlot(player)
		session.dirty = true
		services.DataService.saveActive(player)
		CountryService.push(player)
		return { ok = true, state = snapshot(player) }
	end)
end

local function handleLeave(player)
	return guard(player, function()
		local session = services.DataService.getSession(player)
		if not session or not session.activeSlot then
			return { ok = true }
		end
		session.dirty = true
		services.DataService.saveActive(player)
		services.ConstructionService.clearPlayer(player)
		services.RoadService.clearPlayer(player)
		services.RailService.clearPlayer(player)
		services.BuildingService.clearPlayer(player)
		services.WorldService.release(player)
		services.WorldService.teleportToLobby(player)
		services.DataService.clearActive(player)
		CountryService.push(player)
		return { ok = true }
	end)
end

local function handleDelete(player, index)
	return guard(player, function()
		if not validSlotIndex(index) then
			return { ok = false, error = "Invalid slot" }
		end
		local ok, err = services.DataService.deleteSlot(player, index)
		return { ok = ok, error = err }
	end)
end

local function handleSave(player)
	return guard(player, function()
		local session = services.DataService.getSession(player)
		if not session or not session.activeSlot then
			return { ok = false, error = "No active state" }
		end
		session.dirty = true
		local ok = services.DataService.saveActive(player)
		if not session.persistent then
			return { ok = ok, persistent = false }
		end
		return { ok = ok, persistent = true, error = (not ok) and "Save failed" or nil }
	end)
end

function CountryService.init(allServices)
	services = allServices
	remotes = allServices.Remotes
end

function CountryService.start()
	remotes[Constants.Remotes.GetProfile].OnServerInvoke = handleGetProfile
	remotes[Constants.Remotes.CreateCountry].OnServerInvoke = handleCreate
	remotes[Constants.Remotes.LoadSlot].OnServerInvoke = handleLoad
	remotes[Constants.Remotes.ClaimPlot].OnServerInvoke = handleClaimPlot
	remotes[Constants.Remotes.LeaveState].OnServerInvoke = handleLeave
	remotes[Constants.Remotes.DeleteSlot].OnServerInvoke = handleDelete
	remotes[Constants.Remotes.SaveNow].OnServerInvoke = handleSave

	Players.PlayerRemoving:Connect(function(player)
		pushQueued[player] = nil
		busy[player] = nil
	end)
end

return CountryService
