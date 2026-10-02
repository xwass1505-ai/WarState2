-- Plots: geometry of the 6 player plots (islands around the central island) and their exits.
-- Building and road positions are saved in plot-LOCAL coordinates, so a country can be loaded
-- onto any free plot in a later session.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config")
local GameConfig = require(Config:WaitForChild("GameConfig"))
local PlacementConfig = require(Config:WaitForChild("PlacementConfig"))

local Plots = {}

local SIDE_VECTOR = {
	N = { 0, -1 },
	E = { 1, 0 },
	S = { 0, 1 },
	W = { -1, 0 },
}
Plots.SideVector = SIDE_VECTOR

local function plotConfig(index: number)
	return GameConfig.Map.Plots[index]
end

function Plots.isValidIndex(index: any): boolean
	return type(index) == "number" and index == math.floor(index) and index >= 1 and index <= Plots.maxPlots()
end

function Plots.getBounds(index: number)
	local cfg = plotConfig(index)
	assert(cfg, "Unknown plot " .. tostring(index))
	local t = GameConfig.Territory
	local half = t.Size / 2
	return {
		index = index,
		centerX = cfg.CenterX,
		centerZ = cfg.CenterZ,
		minX = cfg.CenterX - half,
		maxX = cfg.CenterX + half,
		minZ = cfg.CenterZ - half,
		maxZ = cfg.CenterZ + half,
		size = t.Size,
		surfaceY = t.SurfaceY,
		exitSide = cfg.ExitSide,
	}
end

function Plots.toWorld(bounds, localX: number, localZ: number): (number, number)
	return bounds.minX + localX, bounds.minZ + localZ
end

function Plots.toLocal(bounds, worldX: number, worldZ: number): (number, number)
	return worldX - bounds.minX, worldZ - bounds.minZ
end

function Plots.maxPlots(): number
	return math.min(#GameConfig.Map.Plots, GameConfig.Territory.MaxPlots)
end

-- Returns the plot index containing a world point (buildable area only), or nil.
function Plots.plotAt(worldX: number, worldZ: number): number?
	for index = 1, Plots.maxPlots() do
		local b = Plots.getBounds(index)
		if worldX >= b.minX and worldX <= b.maxX and worldZ >= b.minZ and worldZ <= b.maxZ then
			return index
		end
	end
	return nil
end

-- Exit of a plot: the road tile on the plot edge that faces the central island, plus the
-- bridge waypoints PLOT -> EXIT -> MAIN MAP -> CENTRAL ISLAND (used by future vehicles).
function Plots.getExit(index: number)
	local b = Plots.getBounds(index)
	local tile = PlacementConfig.RoadTileSize
	local tiles = math.floor(b.size / tile)
	local mid = math.floor(tiles / 2)
	local side = b.exitSide
	local ix, iz
	if side == "N" then
		ix, iz = mid, 0
	elseif side == "S" then
		ix, iz = mid, tiles - 1
	elseif side == "E" then
		ix, iz = tiles - 1, mid
	else
		ix, iz = 0, mid
	end
	local tileX = b.minX + (ix + 0.5) * tile
	local tileZ = b.minZ + (iz + 0.5) * tile
	local v = SIDE_VECTOR[side]
	local rim = GameConfig.Territory.RimWidth
	local half = b.size / 2
	local edgeX, edgeZ = b.centerX + v[1] * half, b.centerZ + v[2] * half
	if v[1] == 0 then
		edgeX = tileX
	else
		edgeZ = tileZ
	end
	local rimX, rimZ = edgeX + v[1] * rim, edgeZ + v[2] * rim

	local central = GameConfig.Map.CentralIsland
	local ch = central.Size / 2
	local landX, landZ = rimX, rimZ
	if side == "S" then
		landZ = central.CenterZ - ch + central.BeachWidth
	elseif side == "N" then
		landZ = central.CenterZ + ch - central.BeachWidth
	elseif side == "E" then
		landX = central.CenterX - ch + central.BeachWidth
	else
		landX = central.CenterX + ch - central.BeachWidth
	end
	return {
		plotIndex = index,
		side = side,
		ix = ix,
		iz = iz,
		key = tostring(ix) .. ":" .. tostring(iz),
		tileX = tileX,
		tileZ = tileZ,
		edgeX = edgeX,
		edgeZ = edgeZ,
		bridgeStartX = rimX,
		bridgeStartZ = rimZ,
		bridgeEndX = landX,
		bridgeEndZ = landZ,
		waypoints = {
			{ X = tileX, Z = tileZ },
			{ X = edgeX, Z = edgeZ },
			{ X = rimX, Z = rimZ },
			{ X = landX, Z = landZ },
			{ X = central.CenterX, Z = central.CenterZ },
		},
	}
end

return Plots
