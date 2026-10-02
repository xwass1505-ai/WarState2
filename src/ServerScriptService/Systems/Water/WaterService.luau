-- WaterService: server-side water system.
-- Water Tower: Production (units per utility tick), Capacity (storage buffer), Radius (studs).
-- Buildings inside a tower's radius receive water (UtilityGrid). Every building record gets
-- WaterRequired / WaterSupplied / WaterStatus (GREEN supplied, RED shortage, GREY not required).
-- Coverage is recomputed on events (build / demolish / completion / load); the periodic tick only
-- updates storage and the gradual shortage stages:
-- NORMAL -> WARNING -> PROLONGED_SHORTAGE -> POPULATION_PROBLEMS -> GRADUAL_POPULATION_DECREASE

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = Shared:WaitForChild("Config")
local GameConfig = require(Config:WaitForChild("GameConfig"))
local BuildingConfig = require(Config:WaitForChild("BuildingConfig"))
local Constants = require(Shared:WaitForChild("Constants"):WaitForChild("Constants"))
local UtilityGrid = require(Shared:WaitForChild("Modules"):WaitForChild("UtilityGrid"))

local WaterService = {}
WaterService.Name = "WaterService"
WaterService.Kind = "Water"

local services
local defsById = {}
for _, def in ipairs(BuildingConfig.Buildings) do
	defsById[def.Id] = def
end

local SHORTAGE = GameConfig.Utilities.Shortage
local Stage = Constants.ShortageStage

local STAGE_MESSAGES = {
	[Stage.Warning] = { "Water shortage: build a Water Tower near your buildings", "error" },
	[Stage.Prolonged] = { "Prolonged water shortage: population growth stopped", "error" },
	[Stage.Problems] = { "Water shortage is causing population problems", "error" },
	[Stage.Decrease] = { "Population is decreasing because of the water shortage", "error" },
	[Stage.Normal] = { "Water supply restored", "success" },
}

function WaterService.stageFor(seconds: number): string
	if seconds <= 0 then
		return Stage.Normal
	elseif seconds < SHORTAGE.ProlongedSeconds then
		return Stage.Warning
	elseif seconds < SHORTAGE.ProblemsSeconds then
		return Stage.Prolonged
	elseif seconds < SHORTAGE.DecreaseSeconds then
		return Stage.Problems
	end
	return Stage.Decrease
end

function WaterService.stageIndex(stage: string): number
	return table.find(Constants.ShortageOrder, stage) or 1
end

local function infra(country)
	country.Infrastructure = country.Infrastructure or {}
	local i = country.Infrastructure
	i.Water = i.Water or { Stored = 0, Production = 0, Demand = 0 }
	i.Shortage = i.Shortage or { Stage = Stage.Normal, Seconds = 0 }
	return i
end

-- Housing capacity of completed residential buildings that are RED on water.
function WaterService.affectedHousing(country): number
	local affected = 0
	for _, record in pairs(country.Buildings) do
		local def = defsById[record.Type]
		if def and (def.HousingCapacity or 0) > 0 and record.State == Constants.BuildState.Completed and record.WaterStatus == "RED" then
			affected += def.HousingCapacity
		end
	end
	return affected
end

-- Event-driven coverage recompute (no storage consumption). Returns true if anything changed.
function WaterService.recompute(player: Player): boolean
	local country = services.DataService.getCountry(player)
	if not country then
		return false
	end
	local i = infra(country)
	local capacity = UtilityGrid.capacity(country.Buildings, defsById, "Water")
	i.Water.Stored = math.clamp(i.Water.Stored or 0, 0, capacity)
	i.Water.Capacity = capacity
	local result = UtilityGrid.compute(country.Buildings, defsById, "Water", { pool = i.Water.Stored })
	local changed = UtilityGrid.apply(country.Buildings, "Water", result)
	i.Water.Production = result.production
	i.Water.Demand = result.demand
	i.Water.Supplied = result.supplied
	services.BuildingService.refreshUtilityAttributes(player)
	return changed
end

-- Pure shortage step (used by the tick and by the runtime self-test).
-- Returns previousStage, newStage, populationChanged
function WaterService.shortageStep(country, dt: number)
	local i = infra(country)
	local previous = i.Shortage.Stage or Stage.Normal
	local affected = WaterService.affectedHousing(country)
	if affected > 0 then
		i.Shortage.Seconds = (i.Shortage.Seconds or 0) + dt
	else
		i.Shortage.Seconds = math.max(0, (i.Shortage.Seconds or 0) - dt * SHORTAGE.RecoveryMultiplier)
	end
	i.Shortage.Stage = WaterService.stageFor(i.Shortage.Seconds)
	local populationChanged = false
	if i.Shortage.Stage == Stage.Decrease and affected > 0 and country.Population > 0 then
		local floorPopulation = math.max(0, country.HousingCapacity - affected)
		if country.Population > floorPopulation then
			local loss = math.max(1, math.floor(math.min(country.Population, affected) * SHORTAGE.DecreaseFraction))
			country.Population = math.max(floorPopulation, country.Population - loss)
			country.Workers = math.floor(country.Population * GameConfig.Population.WorkerRatio)
			populationChanged = true
		end
	end
	return previous, i.Shortage.Stage, populationChanged
end

local function tickPlayer(player: Player, dt: number)
	local country = services.DataService.getCountry(player)
	if not country or not services.WorldService.getPlotIndex(player) then
		return
	end
	local i = infra(country)
	local capacity = UtilityGrid.capacity(country.Buildings, defsById, "Water")
	local stored = math.clamp(i.Water.Stored or 0, 0, capacity)
	local result = UtilityGrid.compute(country.Buildings, defsById, "Water", { pool = stored })
	local changed = UtilityGrid.apply(country.Buildings, "Water", result)
	local surplus = math.max(0, result.production - result.fromProduction)
	local newStored = math.clamp(stored - result.fromPool + surplus, 0, capacity)
	if newStored ~= i.Water.Stored then
		changed = true
	end
	i.Water.Stored = newStored
	i.Water.Capacity = capacity
	i.Water.Production = result.production
	i.Water.Demand = result.demand
	i.Water.Supplied = result.supplied

	local previous, stage, populationChanged = WaterService.shortageStep(country, dt)
	if previous ~= stage then
		changed = true
		local message = STAGE_MESSAGES[stage]
		local escalated = WaterService.stageIndex(stage) > WaterService.stageIndex(previous)
		if message and (escalated or stage == Stage.Normal) then
			services.CountryService.notify(player, message[1], message[2])
		end
	end
	if changed or populationChanged then
		services.BuildingService.refreshUtilityAttributes(player)
		services.DataService.markDirty(player)
		services.CountryService.push(player)
	end
end

function WaterService.init(allServices)
	services = allServices
end

function WaterService.start()
	task.spawn(function()
		local interval = GameConfig.Utilities.TickSeconds
		while true do
			task.wait(interval)
			for _, player in ipairs(Players:GetPlayers()) do
				local ok, err = pcall(tickPlayer, player, interval)
				if not ok then
					warn("[WaterService] " .. tostring(err))
				end
			end
		end
	end)
end

return WaterService
