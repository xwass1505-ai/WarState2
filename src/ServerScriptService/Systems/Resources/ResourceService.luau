-- ResourceService: Treasury + national resource stock (Coal, Iron Ore, Crude Oil, Fuel, Steel, Supplies).
-- A new country starts with ZERO of everything; nothing is ever granted automatically.
-- Costs are defined in config (Cost = { Treasury = n, Steel = n }) and checked here on the SERVER.
-- Income/expenses are applied by EconomyService every cycle; production by ProductionService.
-- Basic Straight Road, Small House, Water Tower, Wind Generator and Corner Shop cost 0 so a country
-- that starts at Treasury 0 / Population 0 can always bootstrap (no deadlock, no granted money).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(Shared:WaitForChild("Config"):WaitForChild("GameConfig"))
local EconomyRules = require(Shared:WaitForChild("Modules"):WaitForChild("EconomyRules"))

local ResourceService = {}
ResourceService.Name = "ResourceService"
ResourceService.Status = "IMPLEMENTED"
ResourceService.ResourceKeys = { "Treasury" }
for _, key in ipairs(GameConfig.Resources.Keys) do
	table.insert(ResourceService.ResourceKeys, key)
end
ResourceService.Active = GameConfig.Economy.ChargeCosts == true

local services

function ResourceService.get(player: Player)
	local country = services.DataService.getCountry(player)
	if not country then
		return nil
	end
	local result = {}
	for _, key in ipairs(ResourceService.ResourceKeys) do
		result[key] = country[key] or 0
	end
	return result
end

local function label(key: string): string
	return GameConfig.Resources.DisplayNames[key] or key
end

-- cost = { Treasury = 10, Steel = 2 } (optional multiplier for road / rail lines)
function ResourceService.canAfford(country, cost, multiplier: number?): (boolean, string?)
	if not ResourceService.Active then
		return true, nil
	end
	local ok, missing = EconomyRules.canAfford(country, cost, multiplier)
	if not ok then
		return false, "Not enough " .. label(missing or "Treasury")
	end
	return true, nil
end

function ResourceService.charge(country, cost, multiplier: number?)
	if not ResourceService.Active or type(cost) ~= "table" then
		return
	end
	local m = multiplier or 1
	for key, amount in pairs(cost) do
		if type(amount) == "number" and amount > 0 then
			country[key] = (country[key] or 0) - amount * m
		end
	end
end

-- Refund part of a cost (used when demolishing an unfinished building).
function ResourceService.refund(country, cost, fraction: number)
	if not ResourceService.Active or type(cost) ~= "table" then
		return
	end
	for key, amount in pairs(cost) do
		if type(amount) == "number" and amount > 0 then
			country[key] = (country[key] or 0) + math.floor(amount * fraction)
		end
	end
end

function ResourceService.init(allServices)
	services = allServices
end

function ResourceService.start() end

return ResourceService
