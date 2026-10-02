-- RailGraph: pure railway network logic (no Instances).
-- Tracks are 2-stud grid tiles (same grid as roads) saved as country.Railway.Tracks[TrackId] =
-- { TrackId, Ix, Iz, Rotation }. Tiles connect to their 4-adjacent track tiles.
-- A Railway Station is "connected" when a track tile touches its footprint. Freight trains run along
-- the BFS waypoint path between two connected stations (station A track -> ... -> station B track).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local PlacementConfig = require(Shared:WaitForChild("Config"):WaitForChild("PlacementConfig"))
local GridMath = require(Shared:WaitForChild("Modules"):WaitForChild("GridMath"))

local RailGraph = {}

local TILE = PlacementConfig.RoadTileSize

local function idNumber(id: string): number
	return tonumber(string.match(id or "", "%d+")) or 0
end

function RailGraph.cellsOf(tracks)
	local cells = {}
	for _, track in pairs(tracks or {}) do
		cells[GridMath.cellKey(track.Ix, track.Iz)] = track
	end
	return cells
end

-- Openings ("NS", "EW", "NESW" ...) of a tile from its neighbours (isolated tile keeps its axis).
function RailGraph.openings(cells, ix: number, iz: number, rotation: number?): string
	local s = ""
	for _, dir in ipairs(GridMath.DirectionOrder) do
		local o = GridMath.DirectionOffset[dir]
		if cells[GridMath.cellKey(ix + o[1], iz + o[2])] then
			s ..= dir
		end
	end
	if s == "" then
		return (rotation == 1) and "EW" or "NS"
	end
	if s == "N" or s == "S" then
		return "NS"
	elseif s == "E" or s == "W" then
		return "EW"
	end
	return s
end

-- Plot-local center of a track tile.
function RailGraph.center(ix: number, iz: number): (number, number)
	return (ix + 0.5) * TILE, (iz + 0.5) * TILE
end

-- Track tiles touching (edge distance <= 0.05) a plot-local footprint rect.
function RailGraph.tilesTouching(rect, cells)
	local list = {}
	for key, track in pairs(cells) do
		local cx, cz = RailGraph.center(track.Ix, track.Iz)
		local tile = GridMath.rect(cx, cz, TILE, TILE)
		if GridMath.rectDistance(rect, tile) <= 0.05 then
			table.insert(list, key)
		end
	end
	table.sort(list)
	return list
end

-- BFS over track cells from any start key to any goal key. Returns { key, ... } or nil.
function RailGraph.findPath(cells, startKeys, goalKeys)
	local goals = {}
	for _, k in ipairs(goalKeys) do
		goals[k] = true
	end
	local parent = {}
	local queue = {}
	for _, k in ipairs(startKeys) do
		if cells[k] and parent[k] == nil then
			parent[k] = false
			table.insert(queue, k)
		end
	end
	local head = 1
	while head <= #queue do
		local key = queue[head]
		head += 1
		if goals[key] then
			local path = {}
			local cursor = key
			while cursor do
				table.insert(path, 1, cursor)
				cursor = parent[cursor]
			end
			return path
		end
		local track = cells[key]
		for _, dir in ipairs(GridMath.DirectionOrder) do
			local o = GridMath.DirectionOffset[dir]
			local n = GridMath.cellKey(track.Ix + o[1], track.Iz + o[2])
			if cells[n] and parent[n] == nil then
				parent[n] = key
				table.insert(queue, n)
			end
		end
	end
	return nil
end

-- stations: list of { record = BuildingRecord, rect = plot-local Rect }.
-- Returns connected station entries (sorted by id) each with .tiles = { key, ... }.
function RailGraph.connectedStations(stations, cells)
	local result = {}
	for _, s in ipairs(stations) do
		local tiles = RailGraph.tilesTouching(s.rect, cells)
		if #tiles > 0 then
			table.insert(result, { record = s.record, rect = s.rect, tiles = tiles })
		end
	end
	table.sort(result, function(a, b)
		return idNumber(a.record.Id) < idNumber(b.record.Id)
	end)
	return result
end

-- All station pairs that are linked by track. Returns { { from, to, path }, ... }.
function RailGraph.routes(stations, cells)
	local connected = RailGraph.connectedStations(stations, cells)
	local routes = {}
	for i = 1, #connected do
		for j = i + 1, #connected do
			local path = RailGraph.findPath(cells, connected[i].tiles, connected[j].tiles)
			if path then
				table.insert(routes, { from = connected[i], to = connected[j], path = path })
			end
		end
	end
	return routes
end

-- Station entries that take part in at least one route (used for the production rail bonus).
function RailGraph.linkedStationIds(routes)
	local ids = {}
	for _, route in ipairs(routes) do
		ids[route.from.record.Id] = true
		ids[route.to.record.Id] = true
	end
	return ids
end

return RailGraph
