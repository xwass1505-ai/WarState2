-- PowerService: server-side electricity system.
-- Sources: Wind Generator (small: cheap, low production, small radius) and Substation /
-- Advanced Power Source (expensive, high production, large radius, higher resource upkeep).
-- Every building record gets PowerRequired / PowerSupplied / PowerStatus
-- (GREEN supplied, RED insufficient / no electricity, GREY not required).
-- Coverage is recomputed on events only (build / demolish / completion / load / upkeep change).
-- Future sources (power plants) only need a BuildingConfig entry with Power.Production + Radius.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = Shared:WaitForChild("Config")
local BuildingConfig = require(Config:WaitForChild("BuildingConfig"))
local UtilityGrid = require(Shared:WaitForChild("Modules"):WaitForChild("UtilityGrid"))

local PowerService = {}
PowerService.Name = "PowerService"
PowerService.Kind = "Power"

local services
local defsById = {}
for _, def in ipairs(BuildingConfig.Buildings) do
	defsById[def.Id] = def
end

local function infra(country)
	country.Infrastructure = country.Infrastructure or {}
	local i = country.Infrastructure
	i.Power = i.Power or { Production = 0, Demand = 0 }
	return i
end

function PowerService.recompute(player: Player): boolean
	local country = services.DataService.getCountry(player)
	if not country then
		return false
	end
	local i = infra(country)
	local result = UtilityGrid.compute(country.Buildings, defsById, "Power")
	local changed = UtilityGrid.apply(country.Buildings, "Power", result)
	i.Power.Production = result.production
	i.Power.Demand = result.demand
	i.Power.Supplied = result.supplied
	services.BuildingService.refreshUtilityAttributes(player)
	return changed
end

-- Upkeep (e.g. Substation Fuel) is paid once per economy cycle by EconomyService through
-- ProductionRules.payUpkeep; a source that cannot pay goes offline (record.PowerOffline) and this
-- recompute moves its consumers to RED until the upkeep can be paid again.
function PowerService.afterUpkeep(player: Player)
	PowerService.recompute(player)
end

function PowerService.init(allServices)
	services = allServices
end

function PowerService.start() end

return PowerService
