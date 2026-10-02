-- EconomyRules: pure economy math shared by EconomyService, the Build menu and the self-test.
-- 1 cycle = GameConfig.Economy.CycleSeconds (30 s). Every cycle (server side):
--   Income (Shops, Offices, Gas Stations, other businesses) - Expenses (every building + road/rail upkeep) = Net
-- Business income is scaled by customers: efficiency = min(1, Population / total Customers),
-- so spamming shops without citizens does not create money. A business whose water or power is RED
-- earns only Economy.UtilityPenalty of its income. Unfinished buildings neither earn nor cost.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config")
local GameConfig = require(Config:WaitForChild("GameConfig"))

local EconomyRules = {}

local COMPLETED = "COMPLETED"
local ECON = GameConfig.Economy

-- Population unlock (numbers live in BuildingConfig.PopulationRequired).
function EconomyRules.isUnlocked(def, population: number?): boolean
	return (population or 0) >= (def.PopulationRequired or 0)
end

function EconomyRules.unlockText(def): string
	return string.format("Population %d required", def.PopulationRequired or 0)
end

-- Cost check for a { Treasury = n, Steel = n, ... } table. Returns ok, missingKey.
function EconomyRules.canAfford(country, cost, multiplier: number?): (boolean, string?)
	if type(cost) ~= "table" then
		return true, nil
	end
	local m = multiplier or 1
	for key, amount in pairs(cost) do
		if type(amount) == "number" and amount > 0 and (country[key] or 0) < amount * m then
			return false, key
		end
	end
	return true, nil
end

local function utilityOk(record): boolean
	return record.WaterStatus ~= "RED" and record.PowerStatus ~= "RED"
end

-- Returns a breakdown table for one cycle (does not modify the country):
-- { income, expense, net, businessIncome, fuelIncome, buildingExpense, roadExpense, railExpense,
--   customers, efficiency, fuelSold }
function EconomyRules.computeCycle(country, defsById, roadTiles: number, railTiles: number)
	local result = {
		income = 0,
		expense = 0,
		net = 0,
		businessIncome = 0,
		fuelIncome = 0,
		buildingExpense = 0,
		roadExpense = 0,
		railExpense = 0,
		customers = 0,
		efficiency = 1,
		fuelSold = 0,
	}
	local businesses = {}
	for _, record in pairs(country.Buildings or {}) do
		local def = defsById[record.Type]
		if def and record.State == COMPLETED then
			result.buildingExpense += def.ExpensePerCycle or 0
			if (def.IncomePerCycle or 0) > 0 then
				table.insert(businesses, { record = record, def = def })
				result.customers += def.Customers or 0
			end
		end
	end
	table.sort(businesses, function(a, b)
		return (tonumber(string.match(a.record.Id or "", "%d+")) or 0) < (tonumber(string.match(b.record.Id or "", "%d+")) or 0)
	end)
	if result.customers > 0 then
		result.efficiency = math.clamp((country.Population or 0) / result.customers, 0, 1)
	end
	local fuel = country.Fuel or 0
	local gross = 0
	for _, entry in ipairs(businesses) do
		local value = entry.def.IncomePerCycle * result.efficiency
		if not utilityOk(entry.record) then
			value *= ECON.UtilityPenalty
		end
		gross += value
		local sale = entry.def.FuelSale
		if sale and utilityOk(entry.record) and fuel >= (sale.Fuel or 1) and result.efficiency > 0 then
			fuel -= sale.Fuel or 1
			result.fuelSold += sale.Fuel or 1
			result.fuelIncome += sale.Income or 0
		end
	end
	result.businessIncome = math.floor(gross + 0.5)
	result.roadExpense = math.floor((roadTiles or 0) / math.max(1, ECON.RoadTilesPerExpense))
	result.railExpense = math.floor((railTiles or 0) / math.max(1, ECON.RailTilesPerExpense))
	result.income = result.businessIncome + result.fuelIncome
	result.expense = result.buildingExpense + result.roadExpense + result.railExpense
	result.net = result.income - result.expense
	return result
end

-- Applies a computed cycle to the country (Treasury + Economy record). Returns the new treasury.
function EconomyRules.applyCycle(country, result)
	country.Fuel = math.max(0, (country.Fuel or 0) - result.fuelSold)
	local treasury = (country.Treasury or 0) + result.net
	if not ECON.AllowDebt then
		treasury = math.max(0, treasury)
	end
	country.Treasury = treasury
	country.Economy = country.Economy or {}
	local e = country.Economy
	e.Cycle = (e.Cycle or 0) + 1
	e.LastIncome = result.income
	e.LastExpense = result.expense
	e.LastNet = result.net
	return treasury
end

return EconomyRules
