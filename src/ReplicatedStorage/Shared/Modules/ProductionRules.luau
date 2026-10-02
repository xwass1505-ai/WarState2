-- ProductionRules: pure resource-chain logic (no Instances), used by ProductionService.
-- Chains (BuildingConfig.Production):
--   Coal Mine -> Coal | Iron Mine -> Iron Ore | Oil Well -> Crude Oil ("Oil")
--   Crude Oil -> Oil Refinery -> Fuel | Coal + Iron Ore -> Steel Factory -> Steel
--   Steel -> Workshop -> Supplies | Steel + Fuel -> Factory -> Supplies
-- A producer works only when COMPLETED, not RED on water/power, and all inputs are in stock.
-- Output is capped by storage: Resources.BaseStorage + StorageCapacity of completed Warehouses.
-- Producers inside the radius of a rail-connected Railway Station get Railway.RailBonus extra output.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config")
local GameConfig = require(Config:WaitForChild("GameConfig"))

local ProductionRules = {}

ProductionRules.Keys = GameConfig.Resources.Keys
local COMPLETED = "COMPLETED"

local function idNumber(id: string): number
	return tonumber(string.match(id or "", "%d+")) or 0
end

function ProductionRules.storageCapacity(country, defsById): number
	local capacity = GameConfig.Resources.BaseStorage
	for _, record in pairs(country.Buildings or {}) do
		local def = defsById[record.Type]
		if def and record.State == COMPLETED and (def.StorageCapacity or 0) > 0 then
			capacity += def.StorageCapacity
		end
	end
	return capacity
end

-- Producers sorted so raw producers (no inputs) run before processing chains.
function ProductionRules.producers(country, defsById)
	local list = {}
	for _, record in pairs(country.Buildings or {}) do
		local def = defsById[record.Type]
		if def and def.Production and record.State == COMPLETED then
			local inputs = 0
			for _ in pairs(def.Production.Inputs or {}) do
				inputs += 1
			end
			table.insert(list, { record = record, def = def, tier = inputs })
		end
	end
	table.sort(list, function(a, b)
		if a.tier ~= b.tier then
			return a.tier < b.tier
		end
		return idNumber(a.record.Id) < idNumber(b.record.Id)
	end)
	return list
end

-- railBoosted: { [recordId] = true } for producers near a connected station (optional).
-- Mutates the country stock. Returns report = { produced = {key=n}, consumed = {key=n}, active, idle, capacity }
function ProductionRules.runCycle(country, defsById, railBoosted)
	local capacity = ProductionRules.storageCapacity(country, defsById)
	local report = { produced = {}, consumed = {}, active = 0, idle = 0, capacity = capacity, idleReasons = {} }
	local bonus = GameConfig.Railway.RailBonus or 0
	for _, entry in ipairs(ProductionRules.producers(country, defsById)) do
		local record, spec = entry.record, entry.def.Production
		local reason = nil
		if record.WaterStatus == "RED" or record.PowerStatus == "RED" then
			reason = "No water/power"
		else
			for key, amount in pairs(spec.Inputs or {}) do
				if (country[key] or 0) < amount then
					reason = "Needs " .. key
					break
				end
			end
		end
		local room = false
		if not reason then
			for key in pairs(spec.Outputs or {}) do
				if (country[key] or 0) < capacity then
					room = true
				end
			end
			if not room then
				reason = "Storage full"
			end
		end
		if reason then
			report.idle += 1
			report.idleReasons[record.Id] = reason
			record.ProductionStatus = reason
		else
			report.active += 1
			record.ProductionStatus = "OK"
			for key, amount in pairs(spec.Inputs or {}) do
				country[key] = (country[key] or 0) - amount
				report.consumed[key] = (report.consumed[key] or 0) + amount
			end
			local multiplier = (railBoosted and railBoosted[record.Id]) and (1 + bonus) or 1
			for key, amount in pairs(spec.Outputs or {}) do
				local add = math.floor(amount * multiplier + 0.0001)
				local before = country[key] or 0
				local after = math.min(capacity, before + add)
				country[key] = after
				report.produced[key] = (report.produced[key] or 0) + (after - before)
			end
		end
	end
	return report
end

-- Resource upkeep (e.g. Substation Fuel, military Supplies). Buildings that cannot pay go offline
-- (record.UpkeepOffline = true). Returns changed (online/offline state flipped).
function ProductionRules.payUpkeep(country, defsById): boolean
	local changed = false
	local list = {}
	for _, record in pairs(country.Buildings or {}) do
		table.insert(list, record)
	end
	table.sort(list, function(a, b)
		return idNumber(a.Id) < idNumber(b.Id)
	end)
	for _, record in ipairs(list) do
		local def = defsById[record.Type]
		if def and record.State == COMPLETED then
			local upkeep = def.Upkeep or (def.Power and def.Power.Upkeep) or nil
			if upkeep then
				local affordable = true
				for key, amount in pairs(upkeep) do
					if amount > 0 and (country[key] or 0) < amount then
						affordable = false
					end
				end
				if affordable then
					for key, amount in pairs(upkeep) do
						if amount > 0 then
							country[key] = (country[key] or 0) - amount
						end
					end
				end
				local offline = not affordable
				if offline ~= (record.UpkeepOffline == true) then
					changed = true
				end
				record.UpkeepOffline = offline or nil
				if def.Power and (def.Power.Production or 0) > 0 then
					record.PowerOffline = offline or nil
				end
			end
		end
	end
	return changed
end

return ProductionRules
