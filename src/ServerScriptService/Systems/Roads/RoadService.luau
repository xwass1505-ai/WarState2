-- RoadService: server-authoritative road placement, demolition and the road graph.
-- One road type (Straight Road). Roads are drawn by DRAG: the client sends start/end points,
-- the server snaps the line to the grid + dominant axis, validates every tile against the
-- player's OWN plot, and builds it. Junction curbs are rebuilt automatically (RoadGraph).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = Shared:WaitForChild("Config")
local Modules = Shared:WaitForChild("Modules")
local RoadConfig = require(Config:WaitForChild("RoadConfig"))
local PlacementConfig = require(Config:WaitForChild("PlacementConfig"))
local Constants = require(Shared:WaitForChild("Constants"):WaitForChild("Constants"))
local GridMath = require(Modules:WaitForChild("GridMath"))
local PlacementRules = require(Modules:WaitForChild("PlacementRules"))
local RoadGraph = require(Modules:WaitForChild("RoadGraph"))
local RoadModels = require(Modules:WaitForChild("RoadModels"))

local RoadService = {}
RoadService.Name = "RoadService"

local services
local remotes
local runtime = {} -- [Player] = { cells = {key -> segment}, models = {RoadId -> Model}, byId = {RoadId -> segment} }
local lastRequest = {}

local ROAD_TYPE = RoadConfig.Types[1]

local function getRuntime(player)
	local r = runtime[player]
	if not r then
		r = { cells = {}, models = {}, byId = {} }
		runtime[player] = r
	end
	return r
end

local function exitInfo(player)
	local exit = services.WorldService.getExit(player)
	if not exit then
		return nil
	end
	return { key = exit.key, side = exit.side }
end

local function spawnModel(player, segment)
	local folder = services.WorldService.getPlotFolder(player, "Roads")
	local bounds = services.WorldService.getBounds(player)
	if not folder or not bounds then
		return
	end
	local r = getRuntime(player)
	local old = r.models[segment.RoadId]
	if old then
		old:Destroy()
	end
	local model = RoadModels.build(segment.Type, segment.Openings)
	model.Name = segment.RoadId
	local wx, wz = bounds.minX + segment.Position.X, bounds.minZ + segment.Position.Z
	model:PivotTo(CFrame.new(wx, bounds.surfaceY, wz))
	local size = PlacementConfig.RoadTileSize
	model:SetAttribute(Constants.Attributes.Kind, "Road")
	model:SetAttribute(Constants.Attributes.TypeId, segment.Type)
	model:SetAttribute("Ix", segment.Ix)
	model:SetAttribute("Iz", segment.Iz)
	model:SetAttribute("Rotation", segment.Rotation)
	model:SetAttribute("Openings", segment.Openings)
	model:SetAttribute("RectMinX", wx - size / 2)
	model:SetAttribute("RectMaxX", wx + size / 2)
	model:SetAttribute("RectMinZ", wz - size / 2)
	model:SetAttribute("RectMaxZ", wz + size / 2)
	model:SetAttribute("Connected", segment.Connected == true)
	model:SetAttribute("ExitConnected", segment.ExitConnected == true)
	model.Parent = folder
	r.models[segment.RoadId] = model
end

-- World-space rects of all road tiles, keyed by cell (used by placement validation).
function RoadService.getRoadCells(player: Player)
	local result = {}
	local r = runtime[player]
	local bounds = services.WorldService.getBounds(player)
	if not r or not bounds then
		return result
	end
	for key, segment in pairs(r.cells) do
		local _, _, rect = PlacementRules.roadCellCenter(segment.Ix, segment.Iz, bounds)
		result[key] = rect
	end
	return result
end

function RoadService.getSegments(player: Player)
	local r = runtime[player]
	return r and r.cells or {}
end

function RoadService.getSegmentsById(player: Player)
	local r = runtime[player]
	return r and r.byId or {}
end

function RoadService.count(player: Player): number
	local r = runtime[player]
	local n = 0
	if r then
		for _ in pairs(r.cells) do
			n += 1
		end
	end
	return n
end

function RoadService.loadCountry(player: Player, country)
	RoadService.clearPlayer(player)
	local r = getRuntime(player)
	for id, segment in pairs(country.Roads) do
		segment.RoadId = segment.RoadId or id
		if RoadGraph.getType(segment.Type) == nil then
			segment.Type = ROAD_TYPE.Id
		end
		local key = GridMath.cellKey(segment.Ix, segment.Iz)
		if r.cells[key] then
			-- Duplicate tile in an old save: keep the first one.
			country.Roads[id] = nil
		else
			r.cells[key] = segment
			r.byId[segment.RoadId] = segment
		end
	end
	RoadGraph.recomputeAll(r.cells, exitInfo(player))
	for _, segment in pairs(r.cells) do
		spawnModel(player, segment)
	end
end

function RoadService.clearPlayer(player: Player)
	local r = runtime[player]
	if r then
		for _, model in pairs(r.models) do
			model:Destroy()
		end
	end
	runtime[player] = nil
end

local function rateLimited(player): boolean
	local now = os.clock()
	if lastRequest[player] and now - lastRequest[player] < PlacementConfig.RequestCooldown then
		return true
	end
	lastRequest[player] = now
	return false
end

local function validNumber(v): boolean
	return type(v) == "number" and v == v and v > -1e6 and v < 1e6
end

-- Core placement shared by PlaceRoad (single tile) and PlaceRoadLine (drag).
local function placeLine(player, startX, startZ, endX, endZ)
	local country = services.DataService.getCountry(player)
	local bounds = services.WorldService.getBounds(player)
	if not country or not bounds then
		return { ok = false, error = "Choose a plot first" }
	end
	local cells, axis = PlacementRules.roadLine(startX, startZ, endX, endZ, bounds)
	local ctx = {
		plot = bounds,
		buildingRects = services.BuildingService.getBuildingRects(player),
		roadCells = RoadService.getRoadCells(player),
	}
	local ok, reason, tiles, newCount = PlacementRules.validateRoadLine(cells, ctx)
	if not ok then
		return { ok = false, error = reason }
	end
	local affordable, costError = services.ResourceService.canAfford(country, ROAD_TYPE.Cost, newCount)
	if not affordable then
		return { ok = false, error = costError }
	end
	services.ResourceService.charge(country, ROAD_TYPE.Cost, newCount)

	local r = getRuntime(player)
	local exit = exitInfo(player)
	local rebuild = {}
	local placedIds = {}
	for _, tile in ipairs(tiles) do
		if not tile.existing then
			local roadId = "R" .. tostring(country.NextRoadId)
			country.NextRoadId += 1
			local segment = {
				RoadId = roadId,
				Type = ROAD_TYPE.Id,
				Rotation = axis,
				Ix = tile.ix,
				Iz = tile.iz,
				Position = { X = tile.centerX - bounds.minX, Z = tile.centerZ - bounds.minZ },
				Neighbours = {},
				Adjacent = {},
				Connected = false,
			}
			country.Roads[roadId] = segment
			r.cells[GridMath.cellKey(tile.ix, tile.iz)] = segment
			r.byId[roadId] = segment
			table.insert(placedIds, roadId)
		end
	end
	for _, tile in ipairs(tiles) do
		for _, segment in ipairs(RoadGraph.updateAround(r.cells, tile.ix, tile.iz, exit)) do
			rebuild[segment.RoadId] = segment
		end
	end
	for _, segment in pairs(rebuild) do
		spawnModel(player, segment)
	end
	services.DataService.markDirty(player)
	services.CountryService.push(player)
	return { ok = true, placed = #placedIds, roadIds = placedIds }
end

local function handlePlace(player, request)
	if rateLimited(player) then
		return { ok = false, error = "Too fast" }
	end
	if type(request) ~= "table" or not validNumber(request.X) or not validNumber(request.Z) then
		return { ok = false, error = "Invalid request" }
	end
	if request.Type ~= nil and request.Type ~= ROAD_TYPE.Id then
		return { ok = false, error = "Unknown road type" }
	end
	return placeLine(player, request.X, request.Z, request.X, request.Z)
end

local function handlePlaceLine(player, request)
	if rateLimited(player) then
		return { ok = false, error = "Too fast" }
	end
	if type(request) ~= "table" then
		return { ok = false, error = "Invalid request" }
	end
	for _, key in ipairs({ "StartX", "StartZ", "EndX", "EndZ" }) do
		if not validNumber(request[key]) then
			return { ok = false, error = "Invalid request" }
		end
	end
	return placeLine(player, request.StartX, request.StartZ, request.EndX, request.EndZ)
end

-- Demolish one road tile owned by the player. Returns ok, error.
function RoadService.demolish(player: Player, roadId: any): (boolean, string?)
	local country = services.DataService.getCountry(player)
	local r = runtime[player]
	if not country or not r or type(roadId) ~= "string" then
		return false, "Nothing to demolish"
	end
	local segment = r.byId[roadId]
	if not segment or country.Roads[roadId] == nil then
		return false, "Not your road"
	end
	country.Roads[roadId] = nil
	r.byId[roadId] = nil
	r.cells[GridMath.cellKey(segment.Ix, segment.Iz)] = nil
	local model = r.models[roadId]
	if model then
		model:Destroy()
	end
	r.models[roadId] = nil
	for _, other in ipairs(RoadGraph.updateAround(r.cells, segment.Ix, segment.Iz, exitInfo(player))) do
		spawnModel(player, other)
	end
	services.DataService.markDirty(player)
	services.CountryService.push(player)
	return true, nil
end

function RoadService.init(allServices)
	services = allServices
	remotes = allServices.Remotes
end

function RoadService.start()
	remotes[Constants.Remotes.PlaceRoad].OnServerInvoke = handlePlace
	remotes[Constants.Remotes.PlaceRoadLine].OnServerInvoke = handlePlaceLine
	Players.PlayerRemoving:Connect(function(player)
		RoadService.clearPlayer(player)
		lastRequest[player] = nil
	end)
end

return RoadService
