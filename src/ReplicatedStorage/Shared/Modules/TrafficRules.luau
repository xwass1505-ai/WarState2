-- TrafficRules: pure civilian-traffic planning (no Instances), used by VehicleService.
-- Every Traffic.IntervalSeconds (60 s): H = completed houses, cars = ceil(H / 2), capped by
-- Traffic.MaxCarsPerWave. Cars start from about half of the houses (each origin house is used once),
-- drive House -> road network -> Shop / Gas Station / Office -> disappear.
-- No destination (or no road path) = no car. Paths follow the real road graph (RoadGraph.findPath).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local GameConfig = require(Shared:WaitForChild("Config"):WaitForChild("GameConfig"))
local PlacementConfig = require(Shared:WaitForChild("Config"):WaitForChild("PlacementConfig"))
local GridMath = require(Shared:WaitForChild("Modules"):WaitForChild("GridMath"))
local RoadGraph = require(Shared:WaitForChild("Modules"):WaitForChild("RoadGraph"))

local TrafficRules = {}

local COMPLETED = "COMPLETED"

function TrafficRules.carCount(houses: number): number
	if houses <= 0 then
		return 0
	end
	return math.min(math.ceil(houses / 2), GameConfig.Traffic.MaxCarsPerWave)
end

local function idNumber(id: string): number
	return tonumber(string.match(id or "", "%d+")) or 0
end

-- Splits completed buildings into houses and traffic destinations (sorted by id).
function TrafficRules.classify(buildings, defsById)
	local houses, destinations = {}, {}
	for _, record in pairs(buildings or {}) do
		local def = defsById[record.Type]
		if def and record.State == COMPLETED then
			if (def.HousingCapacity or 0) > 0 then
				table.insert(houses, record)
			elseif def.TrafficDestination then
				table.insert(destinations, record)
			end
		end
	end
	local function byId(a, b)
		return idNumber(a.Id) < idNumber(b.Id)
	end
	table.sort(houses, byId)
	table.sort(destinations, byId)
	return houses, destinations
end

-- Picks `count` distinct origin houses (deterministic for a given rng).
function TrafficRules.pickOrigins(houses, count: number, rng)
	local pool = table.clone(houses)
	local picked = {}
	for _ = 1, math.min(count, #pool) do
		local index = rng and rng:NextInteger(1, #pool) or 1
		table.insert(picked, table.remove(pool, index))
	end
	return picked
end

-- Footprint rect (plot-local) of a record.
function TrafficRules.localRect(record, def)
	local w, d = GridMath.rotatedSize(def.Footprint[1], def.Footprint[2], record.Rotation or 0)
	return GridMath.rect(record.X, record.Z, w, d)
end

-- Nearest road segment to a plot-local rect within MaxRoadDistance (+1 tile slack). segmentsById: RoadGraph data.
function TrafficRules.nearestRoad(rect, segmentsById)
	local best, bestDistance = nil, math.huge
	local half = PlacementConfig.RoadTileSize / 2
	for id, segment in pairs(segmentsById) do
		local p = segment.Position
		local tile = GridMath.rect(p.X, p.Z, half * 2, half * 2)
		local d = GridMath.rectDistance(rect, tile)
		if d < bestDistance or (d == bestDistance and best and idNumber(id) < idNumber(best)) then
			best, bestDistance = id, d
		end
	end
	if bestDistance > PlacementConfig.MaxRoadDistance + PlacementConfig.RoadTileSize then
		return nil
	end
	return best
end

-- Plans trips. Returns list of { origin = record, destination = record, path = { RoadId, ... } }.
function TrafficRules.planTrips(buildings, defsById, segmentsById, rng)
	local houses, destinations = TrafficRules.classify(buildings, defsById)
	local trips = {}
	if #destinations == 0 or next(segmentsById) == nil then
		return trips, #houses
	end
	local destRoads = {}
	for _, dest in ipairs(destinations) do
		local roadId = TrafficRules.nearestRoad(TrafficRules.localRect(dest, defsById[dest.Type]), segmentsById)
		if roadId then
			table.insert(destRoads, { record = dest, roadId = roadId })
		end
	end
	if #destRoads == 0 then
		return trips, #houses
	end
	local origins = TrafficRules.pickOrigins(houses, TrafficRules.carCount(#houses), rng)
	for _, house in ipairs(origins) do
		local startId = TrafficRules.nearestRoad(TrafficRules.localRect(house, defsById[house.Type]), segmentsById)
		if startId then
			local goal = destRoads[rng and rng:NextInteger(1, #destRoads) or 1]
			local path = RoadGraph.findPath(segmentsById, startId, goal.roadId)
			if path and #path >= 1 then
				table.insert(trips, { origin = house, destination = goal.record, path = path })
			end
		end
	end
	return trips, #houses
end

-- Removes collinear middle points: { Vector-like {X, Z} } -> fewer waypoints (fewer tweens).
function TrafficRules.simplify(points)
	if #points <= 2 then
		return points
	end
	local result = { points[1] }
	for i = 2, #points - 1 do
		local a, b, c = result[#result], points[i], points[i + 1]
		local dx1, dz1 = b.X - a.X, b.Z - a.Z
		local dx2, dz2 = c.X - b.X, c.Z - b.Z
		if math.abs(dx1 * dz2 - dz1 * dx2) > 1e-6 then
			table.insert(result, b)
		end
	end
	table.insert(result, points[#points])
	return result
end

return TrafficRules
