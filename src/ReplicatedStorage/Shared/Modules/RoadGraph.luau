-- RoadGraph: pure road-network logic (no Instances).
-- Only ONE road type exists (Straight Road). Junction shapes are derived automatically:
-- every tile connects to all 4-adjacent road tiles, so curbs disappear where a branch joins.
--
-- Segment record fields (saved): RoadId, Type, Rotation, Ix, Iz, Position {X, Z} (plot-local)
-- Derived fields (recomputed): Neighbours, Adjacent, Connected, Openings ("NS", "NES", ...), ExitConnected
-- Neighbours are true bidirectional edges, ready for vehicle pathfinding (trucks, tanks, IFV...).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local RoadConfig = require(Shared:WaitForChild("Config"):WaitForChild("RoadConfig"))
local GridMath = require(Shared:WaitForChild("Modules"):WaitForChild("GridMath"))

local RoadGraph = {}

local typeById = {}
for _, roadType in ipairs(RoadConfig.Types) do
	typeById[roadType.Id] = roadType
end

RoadGraph.DefaultType = RoadConfig.Types[1].Id

function RoadGraph.getType(typeId: string)
	return typeById[typeId]
end

-- Static openings of a type after rotation (used for isolated tiles / legacy data).
function RoadGraph.openings(typeId: string, rotation: number)
	local roadType = typeById[typeId] or typeById[RoadGraph.DefaultType]
	local result = {}
	if not roadType then
		return result
	end
	for _, dir in ipairs(roadType.Openings) do
		result[GridMath.rotateDirection(dir, rotation)] = true
	end
	return result
end

function RoadGraph.openingsToString(set): string
	local s = ""
	for _, dir in ipairs(GridMath.DirectionOrder) do
		if set[dir] then
			s ..= dir
		end
	end
	return s
end

function RoadGraph.stringToOpenings(s: string?)
	local set = {}
	for _, dir in ipairs(GridMath.DirectionOrder) do
		if s and string.find(s, dir, 1, true) then
			set[dir] = true
		end
	end
	return set
end

-- exit (optional) = { key = "ix:iz", side = "N"|"E"|"S"|"W" } from Plots.getExit
local function refreshSegment(segmentsByCell, segment, exit)
	local neighbours = {}
	local adjacent = {}
	local open = {}
	local count = 0
	for _, dir in ipairs(GridMath.DirectionOrder) do
		local offset = GridMath.DirectionOffset[dir]
		local other = segmentsByCell[GridMath.cellKey(segment.Ix + offset[1], segment.Iz + offset[2])]
		if other then
			table.insert(adjacent, other.RoadId)
			if RoadConfig.AutoConnect ~= false then
				table.insert(neighbours, other.RoadId)
				open[dir] = true
				count += 1
			else
				local mine = RoadGraph.openings(segment.Type, segment.Rotation)
				local theirs = RoadGraph.openings(other.Type, other.Rotation)
				if mine[dir] and theirs[GridMath.Opposite[dir]] then
					table.insert(neighbours, other.RoadId)
					open[dir] = true
					count += 1
				end
			end
		end
	end
	local exitConnected = exit ~= nil and exit.key == GridMath.cellKey(segment.Ix, segment.Iz)
	if exitConnected then
		open[exit.side] = true
		count += 1
	end
	if count == 0 then
		open = RoadGraph.openings(segment.Type, segment.Rotation)
	elseif count == 1 then
		-- Dead end keeps a straight look (open on both ends, curbs along the sides).
		for dir in pairs(open) do
			open[GridMath.Opposite[dir]] = true
		end
	end
	local before = segment.Openings
	segment.Neighbours = neighbours
	segment.Adjacent = adjacent
	segment.Connected = #neighbours > 0 or exitConnected
	segment.ExitConnected = exitConnected
	segment.Openings = RoadGraph.openingsToString(open)
	return before ~= segment.Openings
end

-- Recompute a segment and its four adjacent cells after a change.
-- Returns the list of segments whose visual openings changed (they must be rebuilt).
function RoadGraph.updateAround(segmentsByCell, ix: number, iz: number, exit)
	local changed = {}
	local center = segmentsByCell[GridMath.cellKey(ix, iz)]
	if center then
		refreshSegment(segmentsByCell, center, exit)
		table.insert(changed, center)
	end
	for _, dir in ipairs(GridMath.DirectionOrder) do
		local offset = GridMath.DirectionOffset[dir]
		local other = segmentsByCell[GridMath.cellKey(ix + offset[1], iz + offset[2])]
		if other and refreshSegment(segmentsByCell, other, exit) then
			table.insert(changed, other)
		end
	end
	return changed
end

function RoadGraph.recomputeAll(segmentsByCell, exit)
	for _, segment in pairs(segmentsByCell) do
		refreshSegment(segmentsByCell, segment, exit)
	end
end

-- Breadth-first count of the network reachable from a RoadId.
function RoadGraph.networkSize(segmentsById, startId: string): number
	local visited = { [startId] = true }
	local queue = { startId }
	local head = 1
	local count = 0
	while head <= #queue do
		local id = queue[head]
		head += 1
		local segment = segmentsById[id]
		if segment then
			count += 1
			for _, n in ipairs(segment.Neighbours or {}) do
				if not visited[n] then
					visited[n] = true
					table.insert(queue, n)
				end
			end
		end
	end
	return count
end

-- BFS shortest path (in tiles). goal = RoadId or predicate(segment) -> boolean.
-- Returns { RoadId, ... } from start to goal, or nil.
function RoadGraph.findPath(segmentsById, startId: string, goal)
	if not segmentsById[startId] then
		return nil
	end
	local isGoal
	if type(goal) == "function" then
		isGoal = goal
	else
		isGoal = function(segment)
			return segment.RoadId == goal
		end
	end
	local parent = { [startId] = false }
	local queue = { startId }
	local head = 1
	while head <= #queue do
		local id = queue[head]
		head += 1
		local segment = segmentsById[id]
		if segment and isGoal(segment) then
			local path = {}
			local cursor = id
			while cursor do
				table.insert(path, 1, cursor)
				cursor = parent[cursor]
			end
			return path
		end
		if segment then
			for _, n in ipairs(segment.Neighbours or {}) do
				if parent[n] == nil then
					parent[n] = id
					table.insert(queue, n)
				end
			end
		end
	end
	return nil
end

-- Path from a road tile to the plot exit (PLAYER PLOT -> EXIT). nil when not reachable.
function RoadGraph.pathToExit(segmentsById, startId: string)
	return RoadGraph.findPath(segmentsById, startId, function(segment)
		return segment.ExitConnected == true
	end)
end

return RoadGraph
