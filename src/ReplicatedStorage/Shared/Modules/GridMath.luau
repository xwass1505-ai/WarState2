--!strict
-- GridMath: pure geometry helpers shared by client preview and server validation.
-- Coordinates are world X/Z on the flat territory plane.

local GridMath = {}

GridMath.DirectionOrder = { "N", "E", "S", "W" }

-- Grid direction offsets. N points to -Z (Roblox forward), E to +X.
GridMath.DirectionOffset = {
	N = { 0, -1 },
	E = { 1, 0 },
	S = { 0, 1 },
	W = { -1, 0 },
}

GridMath.Opposite = { N = "S", S = "N", E = "W", W = "E" }

function GridMath.normalizeRotation(step: number): number
	return ((math.floor(step) % 4) + 4) % 4
end

-- Rotate a direction clockwise (seen from above) by `step` quarter turns.
function GridMath.rotateDirection(dir: string, step: number): string
	local index = table.find(GridMath.DirectionOrder, dir)
	assert(index, "Unknown direction " .. tostring(dir))
	local rotated = ((index - 1 + GridMath.normalizeRotation(step)) % 4) + 1
	return GridMath.DirectionOrder[rotated]
end

-- Yaw (radians) used for models so that visuals match rotateDirection.
function GridMath.yawForRotation(step: number): number
	return -math.rad(GridMath.normalizeRotation(step) * 90)
end

function GridMath.rotatedSize(width: number, depth: number, step: number): (number, number)
	if GridMath.normalizeRotation(step) % 2 == 1 then
		return depth, width
	end
	return width, depth
end

export type Rect = { minX: number, maxX: number, minZ: number, maxZ: number }

function GridMath.rect(centerX: number, centerZ: number, width: number, depth: number): Rect
	return {
		minX = centerX - width / 2,
		maxX = centerX + width / 2,
		minZ = centerZ - depth / 2,
		maxZ = centerZ + depth / 2,
	}
end

function GridMath.rectsOverlap(a: Rect, b: Rect, tolerance: number?): boolean
	local tol = tolerance or 0
	return a.minX < b.maxX - tol and a.maxX > b.minX + tol and a.minZ < b.maxZ - tol and a.maxZ > b.minZ + tol
end

function GridMath.rectInside(inner: Rect, outer: Rect, tolerance: number?): boolean
	local tol = tolerance or 0
	return inner.minX >= outer.minX - tol
		and inner.maxX <= outer.maxX + tol
		and inner.minZ >= outer.minZ - tol
		and inner.maxZ <= outer.maxZ + tol
end

function GridMath.pointRectDistance(x: number, z: number, r: Rect): number
	local dx = math.max(r.minX - x, 0, x - r.maxX)
	local dz = math.max(r.minZ - z, 0, z - r.maxZ)
	return math.sqrt(dx * dx + dz * dz)
end

-- Shortest distance between two rects (0 when they touch or overlap).
function GridMath.rectDistance(a: Rect, b: Rect): number
	local dx = math.max(b.minX - a.maxX, 0, a.minX - b.maxX)
	local dz = math.max(b.minZ - a.maxZ, 0, a.minZ - b.maxZ)
	return math.sqrt(dx * dx + dz * dz)
end

-- Snap a footprint so that its edges line up with the grid measured from (originX, originZ).
function GridMath.snapFootprint(
	x: number,
	z: number,
	width: number,
	depth: number,
	grid: number,
	originX: number,
	originZ: number
): (number, number)
	local minX = originX + math.floor((x - width / 2 - originX) / grid + 0.5) * grid
	local minZ = originZ + math.floor((z - depth / 2 - originZ) / grid + 0.5) * grid
	return minX + width / 2, minZ + depth / 2
end

-- Integer cell index containing a coordinate.
function GridMath.cellIndex(value: number, cellSize: number, origin: number): number
	return math.floor((value - origin) / cellSize)
end

function GridMath.cellCenter(index: number, cellSize: number, origin: number): number
	return origin + (index + 0.5) * cellSize
end

function GridMath.cellKey(ix: number, iz: number): string
	return tostring(ix) .. ":" .. tostring(iz)
end

return GridMath
