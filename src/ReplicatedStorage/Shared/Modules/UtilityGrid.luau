-- UtilityGrid: pure coverage/allocation logic shared by WaterService and PowerService (no Instances).
--
-- A source (completed building with def[kind].Production > 0) supplies consumers whose centers are
-- within def[kind].Radius studs. Consumers are served in a stable order (oldest building first) from
-- the nearest sources with remaining capacity. An optional storage pool (water) covers the rest,
-- but only for consumers that are inside the radius of at least one source.
--
-- Status: GREEN = fully supplied, RED = shortage / no coverage, GREY = not required or not built yet.

local UtilityGrid = {}

UtilityGrid.Status = { Green = "GREEN", Red = "RED", Grey = "GREY" }

local COMPLETED = "COMPLETED"

local function idNumber(id: string): number
	return tonumber(string.match(id or "", "%d+")) or 0
end

local function sortedRecords(buildings)
	local list = {}
	for _, record in pairs(buildings) do
		table.insert(list, record)
	end
	table.sort(list, function(a, b)
		return idNumber(a.Id) < idNumber(b.Id)
	end)
	return list
end
UtilityGrid.sortedRecords = sortedRecords

local function distance(a, b): number
	local dx, dz = (a.X or 0) - (b.X or 0), (a.Z or 0) - (b.Z or 0)
	return math.sqrt(dx * dx + dz * dz)
end

-- buildings: { [Id] = record }, defsById: { [TypeId] = def }, kind: "Water" | "Power"
-- options: { pool = number? } (units available from storage this cycle)
-- Returns result = {
--     production, demand, supplied, fromProduction, fromPool, sources, consumers,
--     covered, uncovered, perRecord = { [Id] = { Required, Supplied, Status, Pending } }
-- }
function UtilityGrid.compute(buildings, defsById, kind: string, options)
	local pool = (options and options.pool) or 0
	local result = {
		production = 0,
		demand = 0,
		supplied = 0,
		fromProduction = 0,
		fromPool = 0,
		sources = 0,
		consumers = 0,
		covered = 0,
		uncovered = 0,
		perRecord = {},
	}
	local list = sortedRecords(buildings)
	local sources = {}
	for _, record in ipairs(list) do
		local def = defsById[record.Type]
		local spec = def and def[kind]
		if spec and record.State == COMPLETED and (spec.Production or 0) > 0 and not record[kind .. "Offline"] then
			table.insert(sources, { record = record, remaining = spec.Production, radius = spec.Radius or 0 })
			result.production += spec.Production
			result.sources += 1
		end
	end
	for _, record in ipairs(list) do
		local def = defsById[record.Type]
		local spec = def and def[kind]
		local required = spec and spec.Required or 0
		local entry = { Required = required, Supplied = 0, Status = UtilityGrid.Status.Grey, Pending = false }
		if required > 0 and record.State ~= COMPLETED then
			entry.Pending = true
		elseif required > 0 then
			result.consumers += 1
			result.demand += required
			local candidates = {}
			for _, source in ipairs(sources) do
				local d = distance(record, source.record)
				if d <= source.radius then
					table.insert(candidates, { source = source, d = d })
				end
			end
			table.sort(candidates, function(a, b)
				return a.d < b.d
			end)
			local need = required
			for _, c in ipairs(candidates) do
				if need <= 0 then
					break
				end
				local take = math.min(need, c.source.remaining)
				if take > 0 then
					c.source.remaining -= take
					need -= take
					result.fromProduction += take
				end
			end
			if need > 0 and #candidates > 0 and pool > 0 then
				local take = math.min(need, pool)
				pool -= take
				need -= take
				result.fromPool += take
			end
			if #candidates > 0 then
				result.covered += 1
			else
				result.uncovered += 1
			end
			entry.Supplied = required - need
			result.supplied += entry.Supplied
			entry.Status = need <= 0 and UtilityGrid.Status.Green or UtilityGrid.Status.Red
		end
		result.perRecord[record.Id] = entry
	end
	return result
end

-- Writes the result into the records (WaterRequired / WaterSupplied / WaterStatus etc.).
-- Returns true if any record changed.
function UtilityGrid.apply(buildings, kind: string, result): boolean
	local changed = false
	for id, entry in pairs(result.perRecord) do
		local record = buildings[id]
		if record then
			local status = entry.Status
			if record[kind .. "Status"] ~= status or record[kind .. "Supplied"] ~= entry.Supplied or record[kind .. "Required"] ~= entry.Required then
				changed = true
			end
			record[kind .. "Required"] = entry.Required
			record[kind .. "Supplied"] = entry.Supplied
			record[kind .. "Status"] = status
		end
	end
	return changed
end

-- Total storage capacity of completed sources (water towers).
function UtilityGrid.capacity(buildings, defsById, kind: string): number
	local total = 0
	for _, record in pairs(buildings) do
		local def = defsById[record.Type]
		local spec = def and def[kind]
		if spec and record.State == COMPLETED and (spec.Capacity or 0) > 0 then
			total += spec.Capacity
		end
	end
	return total
end

return UtilityGrid
