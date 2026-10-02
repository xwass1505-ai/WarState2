-- EconomyService: IMPLEMENTED. Server-side economy cycle, 1 cycle = GameConfig.Economy.CycleSeconds (30 s).
-- Every cycle, for every player that owns a plot:
--   1. ProductionService.cycle  (resource chains)
--   2. ProductionRules.payUpkeep (Fuel / Supplies upkeep; unpaid sources go offline) -> PowerService
--   3. Income - Expenses = Net  -> Treasury (EconomyRules; saved with the country)
--   4. ResearchService.cycle    (research points)
-- The next cycle time is published as ReplicatedStorage attribute EconomyNextCycleAt (server time)
-- so the HUD can show a live countdown without extra remotes.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = Shared:WaitForChild("Config")
local GameConfig = require(Config:WaitForChild("GameConfig"))
local BuildingConfig = require(Config:WaitForChild("BuildingConfig"))
local Constants = require(Shared:WaitForChild("Constants"):WaitForChild("Constants"))
local EconomyRules = require(Shared:WaitForChild("Modules"):WaitForChild("EconomyRules"))
local ProductionRules = require(Shared:WaitForChild("Modules"):WaitForChild("ProductionRules"))

local EconomyService = {}
EconomyService.Name = "EconomyService"
EconomyService.Status = "IMPLEMENTED"
EconomyService.Active = true
EconomyService.Description = "30-second economy cycles: income - expenses = net change, production, upkeep, research."
EconomyService.CycleSeconds = GameConfig.Economy.CycleSeconds

local services
local defsById = {}
for _, def in ipairs(BuildingConfig.Buildings) do
	defsById[def.Id] = def
end

-- Preview of the current cycle (used by the snapshot / stats; never changes the country).
function EconomyService.preview(player: Player, country)
	local roads = services.RoadService.count(player)
	local rails = services.RailService and services.RailService.count(player) or 0
	return EconomyRules.computeCycle(country, defsById, roads, rails)
end

function EconomyService.runCycle(player: Player)
	local country = services.DataService.getCountry(player)
	if not country or not services.WorldService.getPlotIndex(player) then
		return nil
	end
	services.ProductionService.cycle(player, country)
	if ProductionRules.payUpkeep(country, defsById) then
		services.PowerService.afterUpkeep(player)
	end
	local result = EconomyService.preview(player, country)
	EconomyRules.applyCycle(country, result)
	services.ResearchService.cycle(player, country)
	services.DataService.markDirty(player)
	services.CountryService.push(player)
	return result
end

function EconomyService.nextCycleAt(): number
	return ReplicatedStorage:GetAttribute(Constants.EconomyAttributes.NextCycleAt) or 0
end

function EconomyService.init(allServices)
	services = allServices
end

function EconomyService.start()
	local seconds = GameConfig.Economy.CycleSeconds
	ReplicatedStorage:SetAttribute(Constants.EconomyAttributes.CycleSeconds, seconds)
	task.spawn(function()
		while true do
			ReplicatedStorage:SetAttribute(Constants.EconomyAttributes.NextCycleAt, Workspace:GetServerTimeNow() + seconds)
			task.wait(seconds)
			for _, player in ipairs(Players:GetPlayers()) do
				local ok, err = pcall(EconomyService.runCycle, player)
				if not ok then
					warn("[EconomyService] " .. tostring(err))
				end
			end
		end
	end)
end

return EconomyService
