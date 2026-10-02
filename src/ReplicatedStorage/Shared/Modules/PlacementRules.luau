-- PlacementRules: shared placement validation.
-- The client uses it for the live preview, the SERVER uses the same rules as the authority.
--
-- ctx = {
--     plot = Plots bounds (the requesting player's OWN plot),
--     buildingRects = { Rect, ... }, -- world-space footprints of existing buildings
--     roadCells = { ["ix:iz"] = Rect, ... } -- world-space rects of existing road tiles
--     railCells = { ["ix:iz"] = Rect, ... } -- (rail drag only) existing rail track tiles
-- }
-- Rail tiles are also part of buildingRects for building / road validation (nothing overlaps a track).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = Shared:WaitForChild("Config")
local PlacementConfig = require(Config:WaitForChild("PlacementConfig"))
local GridMath = require(Shared:WaitForChild("Modules"):WaitForChild("GridMath"))

local PlacementRules = {}

PlacementRules.Reasons = {
	Ok = "OK",
	OutsideTerritory = "Outside your plot",
	OverlapBuilding = "Overlaps a building",
	OverlapRoad = "Overlaps a road",
	RoadOccupied = "Road already here",
	TooFarFromRoad = "Too far from road",
	NoRoads = "Build a road first",
	UnknownType = "Unknown type",
	RoadTooLong = "Road is too long",
	NotEnoughTreasury = "Not enough treasury",
	RailOccupied = "Track already here",
	OverlapRail = "Overlaps a rail track",
	CrossesRoad = "Rails cannot cross roads",
}

function PlacementRules.plotRect(plot)
	return { minX = plot.minX, maxX = plot.maxX, minZ = plot.minZ, maxZ = plot.maxZ }
end

-- Snap a world point to a building footprint. Returns centerX, centerZ, rect, width, depth.
function PlacementRules.snapBuilding(def, worldX: number, worldZ: number, rotation: number, plot)
	local width, depth = GridMath.rotatedSize(def.Footprint[1], def.Footprint[2], rotation)
	local cx, cz =
		GridMath.snapFootprint(worldX, worldZ, width, depth, PlacementConfig.GridSize, plot.minX, plot.minZ)
	return cx, cz, GridMath.rect(cx, cz, width, depth), width, depth
end

-- Snap a world point to a road tile. Returns ix, iz, centerX, centerZ, rect.
function PlacementRules.snapRoad(worldX: number, worldZ: number, plot)
	local size = PlacementConfig.RoadTileSize
	local ix = GridMath.cellIndex(worldX, size, plot.minX)
	local iz = GridMath.cellIndex(worldZ, size, plot.minZ)
	return ix, iz, PlacementRules.roadCellCenter(ix, iz, plot)
end

function PlacementRules.roadCellCenter(ix: number, iz: number, plot)
	local size = PlacementConfig.RoadTileSize
	local cx = GridMath.cellCenter(ix, size, plot.minX)
	local cz = GridMath.cellCenter(iz, size, plot.minZ)
	return cx, cz, GridMath.rect(cx, cz, size, size)
end

-- Distance from a point to the nearest road tile. Returns math.huge when no roads exist.
function PlacementRules.nearestRoadDistance(x: number, z: number, roadCells): number
	local best = math.huge
	for _, rect in pairs(roadCells) do
		local d = GridMath.pointRectDistance(x, z, rect)
		if d < best then
			best = d
		end
	end
	return best
end

-- Distance from a footprint edge to the nearest road tile (buildings face the road).
function PlacementRules.nearestRoadEdgeDistance(rect, roadCells): number
	local best = math.huge
	for _, roadRect in pairs(roadCells) do
		local d = GridMath.rectDistance(rect, roadRect)
		if d < best then
			best = d
		end
	end
	return best
end

-- Returns ok, reason, info
function PlacementRules.validateBuilding(def, worldX: number, worldZ: number, rotation: number, ctx)
	if not def then
		return false, PlacementRules.Reasons.UnknownType, nil
	end
	local tol = PlacementConfig.OverlapTolerance
	local cx, cz, rect = PlacementRules.snapBuilding(def, worldX, worldZ, rotation, ctx.plot)
	local info = { centerX = cx, centerZ = cz, rect = rect, roadDistance = math.huge }

	if not GridMath.rectInside(rect, PlacementRules.plotRect(ctx.plot), tol) then
		return false, PlacementRules.Reasons.OutsideTerritory, info
	end
	for _, other in ipairs(ctx.buildingRects) do
		if GridMath.rectsOverlap(rect, other, tol) then
			return false, PlacementRules.Reasons.OverlapBuilding, info
		end
	end
	for _, roadRect in pairs(ctx.roadCells) do
		if GridMath.rectsOverlap(rect, roadRect, tol) then
			return false, PlacementRules.Reasons.OverlapRoad, info
		end
	end
	if PlacementConfig.RequireRoadAccess then
		if next(ctx.roadCells) == nil then
			return false, PlacementRules.Reasons.NoRoads, info
		end
		local distance = PlacementRules.nearestRoadEdgeDistance(rect, ctx.roadCells)
		info.roadDistance = distance
		if distance > PlacementConfig.MaxRoadDistance then
			return false, PlacementRules.Reasons.TooFarFromRoad, info
		end
	end
	return true, PlacementRules.Reasons.Ok, info
end

-- Single road tile validation (kept for the PlaceRoad remote and tests).
function PlacementRules.validateRoad(worldX: number, worldZ: number, ctx)
	local tol = PlacementConfig.OverlapTolerance
	local ix, iz, cx, cz, rect = PlacementRules.snapRoad(worldX, worldZ, ctx.plot)
	local info = { ix = ix, iz = iz, centerX = cx, centerZ = cz, rect = rect }
	if not GridMath.rectInside(rect, PlacementRules.plotRect(ctx.plot), tol) then
		return false, PlacementRules.Reasons.OutsideTerritory, info
	end
	if ctx.roadCells[GridMath.cellKey(ix, iz)] then
		return false, PlacementRules.Reasons.RoadOccupied, info
	end
	for _, other in ipairs(ctx.buildingRects) do
		if GridMath.rectsOverlap(rect, other, tol) then
			return false, PlacementRules.Reasons.OverlapBuilding, info
		end
	end
	return true, PlacementRules.Reasons.Ok, info
end

-- Cells of a straight drag from A to B, snapped to the dominant axis (grid + direction).
-- Returns cells { {ix, iz}, ... }, axis (0 = along Z / N-S, 1 = along X / E-W), fullLength.
function PlacementRules.roadLine(startX: number, startZ: number, endX: number, endZ: number, plot)
	local size = PlacementConfig.RoadTileSize
	local ix0 = GridMath.cellIndex(startX, size, plot.minX)
	local iz0 = GridMath.cellIndex(startZ, size, plot.minZ)
	local ix1 = GridMath.cellIndex(endX, size, plot.minX)
	local iz1 = GridMath.cellIndex(endZ, size, plot.minZ)
	local dx, dz = ix1 - ix0, iz1 - iz0
	local cells = {}
	local axis
	if math.abs(dx) >= math.abs(dz) then
		axis = 1
		local stepX = dx >= 0 and 1 or -1
		for i = 0, math.abs(dx) do
			table.insert(cells, { ix0 + i * stepX, iz0 })
		end
	else
		axis = 0
		local stepZ = dz >= 0 and 1 or -1
		for i = 0, math.abs(dz) do
			table.insert(cells, { ix0, iz0 + i * stepZ })
		end
	end
	if #cells == 1 then
		axis = 0
	end
	return cells, axis, #cells
end

-- Validates a drag line. Existing road tiles on the line are allowed (they become junctions)
-- and are skipped. Returns ok, reason, tiles, newCount where each tile =
-- { ix, iz, centerX, centerZ, rect, valid, existing, reason }.
function PlacementRules.validateRoadLine(cells, ctx)
	local tol = PlacementConfig.OverlapTolerance
	local plotRect = PlacementRules.plotRect(ctx.plot)
	local tiles = {}
	local firstReason = nil
	local newCount = 0
	if #cells > PlacementConfig.MaxRoadDragTiles then
		return false, PlacementRules.Reasons.RoadTooLong, tiles, 0
	end
	for _, cell in ipairs(cells) do
		local ix, iz = cell[1], cell[2]
		local cx, cz, rect = PlacementRules.roadCellCenter(ix, iz, ctx.plot)
		local tile = { ix = ix, iz = iz, centerX = cx, centerZ = cz, rect = rect, valid = true, existing = false }
		if not GridMath.rectInside(rect, plotRect, tol) then
			tile.valid = false
			tile.reason = PlacementRules.Reasons.OutsideTerritory
		elseif ctx.roadCells[GridMath.cellKey(ix, iz)] then
			tile.existing = true
		else
			for _, other in ipairs(ctx.buildingRects) do
				if GridMath.rectsOverlap(rect, other, tol) then
					tile.valid = false
					tile.reason = PlacementRules.Reasons.OverlapBuilding
					break
				end
			end
		end
		if tile.valid and not tile.existing then
			newCount += 1
		end
		if not tile.valid and firstReason == nil then
			firstReason = tile.reason
		end
		table.insert(tiles, tile)
	end
	if firstReason then
		return false, firstReason, tiles, newCount
	end
	if newCount == 0 then
		return false, PlacementRules.Reasons.RoadOccupied, tiles, 0
	end
	return true, PlacementRules.Reasons.Ok, tiles, newCount
end

-- Rail drag line (same grid as roads). Existing track tiles become junctions; roads and buildings
-- block the line. ctx.buildingRects must NOT contain the rail tiles themselves.
function PlacementRules.validateRailLine(cells, ctx)
	local roadAsBlocked = {}
	for _, rect in ipairs(ctx.buildingRects) do
		table.insert(roadAsBlocked, rect)
	end
	local blockers = { plot = ctx.plot, roadCells = ctx.railCells or {}, buildingRects = roadAsBlocked }
	local ok, reason, tiles, newCount = PlacementRules.validateRoadLine(cells, blockers)
	-- Roads are checked separately so the reason is clear.
	local firstReason = nil
	for _, tile in ipairs(tiles) do
		if tile.valid and not tile.existing and ctx.roadCells[GridMath.cellKey(tile.ix, tile.iz)] then
			tile.valid = false
			tile.reason = PlacementRules.Reasons.CrossesRoad
			newCount -= 1
		end
		if not tile.valid and firstReason == nil then
			firstReason = tile.reason
		end
	end
	if firstReason then
		return false, firstReason, tiles, newCount
	end
	if not ok and reason == PlacementRules.Reasons.RoadOccupied then
		return false, PlacementRules.Reasons.RailOccupied, tiles, 0
	end
	return ok, reason, tiles, newCount
end

return PlacementRules
