-- ProductionService: IMPLEMENTED. Industry chains run once per economy cycle (called by EconomyService).
--   Coal Mine -> Coal, Iron Mine -> Iron Ore, Oil Well -> Crude Oil,
--   Crude Oil -> Oil Refinery -> Fuel, Coal + Iron Ore -> Steel Factory -> Steel,
--   Steel -> Workshop -> Supplies, Steel + Fuel -> Factory -> Supplies.
-- Stock lives on the country (ResourceService keys); Warehouses raise the storage cap.
-- Producers near a rail-connected Railway Station get the Railway.RailBonus (RailService).
-- Pure rules: Shared/Modules/ProductionRules (also used by the runtime self-test).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local BuildingConfig = require(Shared:WaitForChild("Config"):WaitForChild("BuildingConfig"))
local ProductionRules = require(Shared:WaitForChild("Modules"):WaitForChild("ProductionRules"))

local ProductionService = {}
ProductionService.Name = "ProductionService"
ProductionService.Status = "IMPLEMENTED"
ProductionService.Active = true
ProductionService.Description = "Resource chains: mines, oil wells, refinery, steel factory, workshops, warehouses."

local services
local defsById = {}
for _, def in ipairs(BuildingConfig.Buildings) do
	defsById[def.Id] = def
end
local lastReports = {} -- [Player] = report

-- One production step for the player's country. Returns the report.
function ProductionService.cycle(player: Player, country)
	local boosted = services.RailService and services.RailService.boostedProducers(player, country) or {}
	local report = ProductionRules.runCycle(country, defsById, boosted)
	country.Production = {
		Produced = report.produced,
		Consumed = report.consumed,
		Active = report.active,
		Idle = report.idle,
		Capacity = report.capacity,
	}
	lastReports[player] = report
	return report
end

function ProductionService.capacity(country): number
	return ProductionRules.storageCapacity(country, defsById)
end

function ProductionService.getReport(player: Player)
	return lastReports[player]
end

function ProductionService.init(allServices)
	services = allServices
end

function ProductionService.start()
	game:GetService("Players").PlayerRemoving:Connect(function(player)
		lastReports[player] = nil
	end)
end

return ProductionService
