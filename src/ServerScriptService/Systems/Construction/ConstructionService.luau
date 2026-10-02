-- ConstructionService: PLANNED -> UNDER_CONSTRUCTION -> COMPLETED over time (server authority).
-- Visuals: planned = faint ghost; under construction = parts become solid from the ground up.
-- The progress bar itself is drawn on the CLIENT (Controllers/ConstructionBars) from model
-- attributes (State, BuildTime, CompleteAt = server time), so it animates smoothly without
-- server ticks. Construction advances only while the owner is in the session (progress is saved).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = Shared:WaitForChild("Config")
local GameConfig = require(Config:WaitForChild("GameConfig"))
local BuildingConfig = require(Config:WaitForChild("BuildingConfig"))
local Constants = require(Shared:WaitForChild("Constants"):WaitForChild("Constants"))

local ConstructionService = {}
ConstructionService.Name = "ConstructionService"

local services
local tracked = {} -- [Player] = { [Id] = { record, model, parts } }

local defsById = {}
for _, def in ipairs(BuildingConfig.Buildings) do
	defsById[def.Id] = def
end

local GHOST = GameConfig.Construction.GhostTransparency

local function collectParts(model)
	local parts = {}
	local pivotY = model:GetPivot().Position.Y
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") and d.Name ~= "Root" then
			local base = d:GetAttribute("BaseTransparency") or 0
			local bottom = d.Position.Y - d.Size.Y / 2 - pivotY
			table.insert(parts, { part = d, base = base, bottom = bottom })
		end
	end
	return parts
end

local function setTiming(entry)
	local record = entry.record
	local model = entry.model
	local def = defsById[record.Type]
	local now = Workspace:GetServerTimeNow()
	model:SetAttribute("State", record.State)
	model:SetAttribute("BuildTime", def.BuildTimeSeconds)
	if record.State == Constants.BuildState.Planned then
		local plannedLeft = math.max(0, GameConfig.Construction.PlannedSeconds - record.PlannedElapsed)
		model:SetAttribute("CompleteAt", now + plannedLeft + def.BuildTimeSeconds)
	elseif record.State == Constants.BuildState.UnderConstruction then
		model:SetAttribute("CompleteAt", now + math.max(0, def.BuildTimeSeconds - record.Progress))
	else
		model:SetAttribute("CompleteAt", now)
	end
end

local function applyVisual(entry)
	local record = entry.record
	local model = entry.model
	local def = defsById[record.Type]
	if record.State == Constants.BuildState.Completed then
		for _, info in ipairs(entry.parts) do
			info.part.Transparency = info.base
		end
		model:SetAttribute("Progress", 1)
		return
	end
	local fraction = 0
	if record.State == Constants.BuildState.UnderConstruction then
		fraction = math.clamp(record.Progress / def.BuildTimeSeconds, 0, 1)
	end
	model:SetAttribute("Progress", fraction)
	local height = model:GetAttribute("VisualHeight") or 2
	local revealHeight = fraction * height
	for _, info in ipairs(entry.parts) do
		local target
		if record.State == Constants.BuildState.UnderConstruction and info.bottom <= revealHeight then
			target = info.base
		else
			target = math.max(info.base, GHOST)
		end
		if info.part.Transparency ~= target then
			info.part.Transparency = target
		end
	end
end

function ConstructionService.track(player: Player, record, model)
	tracked[player] = tracked[player] or {}
	local entry = { record = record, model = model, parts = collectParts(model) }
	setTiming(entry)
	applyVisual(entry)
	if record.State ~= Constants.BuildState.Completed then
		tracked[player][record.Id] = entry
	end
end

function ConstructionService.untrack(player: Player, id: string)
	local entries = tracked[player]
	if entries then
		entries[id] = nil
	end
end

function ConstructionService.clearPlayer(player: Player)
	tracked[player] = nil
end

local function step(dt: number)
	for player, entries in pairs(tracked) do
		local completedAny = false
		local anyActive = false
		local transitioned = false
		for id, entry in pairs(entries) do
			local record = entry.record
			local def = defsById[record.Type]
			if record.State == Constants.BuildState.Planned then
				anyActive = true
				record.PlannedElapsed += dt
				if record.PlannedElapsed >= GameConfig.Construction.PlannedSeconds then
					record.State = Constants.BuildState.UnderConstruction
					transitioned = true
					setTiming(entry)
				end
				applyVisual(entry)
			elseif record.State == Constants.BuildState.UnderConstruction then
				anyActive = true
				record.Progress = math.min(record.Progress + dt, def.BuildTimeSeconds)
				if record.Progress >= def.BuildTimeSeconds then
					record.State = Constants.BuildState.Completed
					completedAny = true
					setTiming(entry)
					services.CountryService.notify(player, def.DisplayName .. " completed", "success")
				end
				applyVisual(entry)
			end
			if record.State == Constants.BuildState.Completed then
				entries[id] = nil
			end
		end
		if anyActive then
			services.DataService.markDirty(player)
		end
		if completedAny then
			services.BuildingService.onBuildingsChanged(player)
		elseif transitioned then
			services.CountryService.push(player)
		end
	end
end

function ConstructionService.init(allServices)
	services = allServices
end

function ConstructionService.start()
	task.spawn(function()
		local interval = GameConfig.Construction.TickSeconds
		local last = os.clock()
		while true do
			task.wait(interval)
			local now = os.clock()
			local dt = now - last
			last = now
			local ok, err = pcall(step, dt)
			if not ok then
				warn("[ConstructionService] " .. tostring(err))
			end
		end
	end)
	Players.PlayerRemoving:Connect(function(player)
		tracked[player] = nil
	end)
end

return ConstructionService
