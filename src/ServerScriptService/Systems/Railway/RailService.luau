-- RailService: IMPLEMENTED. Rail Track (drag-built 2-stud tiles), Railway Station connectivity and
-- Freight Trains. Server authority: the client only sends start/end points (PlaceRailLine);
-- the server snaps, validates against the requester's OWN plot (no roads / buildings under the
-- track), charges Railway.Track.Cost per new tile and saves country.Railway.Tracks.
--
-- Freight trains (every Railway.IntervalSeconds): for each pair of completed Railway Stations that are
-- linked by track (RailGraph waypoint path), a locomotive + up to Railway.MaxWagons wagons runs from one
-- station to the other carrying the national stock (Coal, Iron Ore, Crude Oil, Steel, Fuel, Supplies;
-- up to WagonCapacity each). Arrival pays FreightIncomePerWagon per loaded wagon. Producers inside
-- StationRadius of a linked station get Railway.RailBonus extra output (ProductionService).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = Shared:WaitForChild("Config")
local Modules = Shared:WaitForChild("Modules")
local GameConfig = require(Config:WaitForChild("GameConfig"))
local BuildingConfig = require(Config:WaitForChild("BuildingConfig"))
local PlacementConfig = require(Config:WaitForChild("PlacementConfig"))
local Constants = require(Shared:WaitForChild("Constants"):WaitForChild("Constants"))
local GridMath = require(Modules:WaitForChild("GridMath"))
local PlacementRules = require(Modules:WaitForChild("PlacementRules"))
local RailGraph = require(Modules:WaitForChild("RailGraph"))
local TrafficRules = require(Modules:WaitForChild("TrafficRules"))
local VehicleModels = require(Modules:WaitForChild("VehicleModels"))

local RailService = {}
RailService.Name = "RailService"
RailService.Status = "IMPLEMENTED"

local RAIL = GameConfig.Railway
local TILE = PlacementConfig.RoadTileSize
local services
local remotes
local runtime = {} -- [Player] = { cells = {key -> track}, byId = {TrackId -> track}, models = {TrackId -> Model} }
local trains = {} -- [Player] = { active = n, routeIndex = n, delivered = n, trips = n }
local lastRequest = {}

local defsById = {}
for _, def in ipairs(BuildingConfig.Buildings) do
	defsById[def.Id] = def
end

local function getRuntime(player)
	local r = runtime[player]
	if not r then
		r = { cells = {}, byId = {}, models = {} }
		runtime[player] = r
	end
	return r
end

local function trainState(player)
	local t = trains[player]
	if not t then
		t = { active = 0, routeIndex = 0, trips = 0 }
		trains[player] = t
	end
	return t
end

local function railData(country)
	country.Railway = country.Railway or {}
	country.Railway.Tracks = country.Railway.Tracks or {}
	country.Railway.NextTrackId = country.Railway.NextTrackId or 1
	country.Railway.Delivered = country.Railway.Delivered or 0
	return country.Railway
end

local function spawnModel(player, track)
	local folder = services.WorldService.getPlotFolder(player, "Buildings")
	local bounds = services.WorldService.getBounds(player)
	if not folder or not bounds then
		return
	end
	local r = getRuntime(player)
	local old = r.models[track.TrackId]
	if old then
		old:Destroy()
	end
	local model = VehicleModels.railTile(RailGraph.openings(r.cells, track.Ix, track.Iz, track.Rotation))
	model.Name = track.TrackId
	local cx, cz = RailGraph.center(track.Ix, track.Iz)
	local wx, wz = bounds.minX + cx, bounds.minZ + cz
	model:PivotTo(CFrame.new(wx, bounds.surfaceY, wz))
	model:SetAttribute(Constants.Attributes.Kind, Constants.Kinds.Rail)
	model:SetAttribute(Constants.Attributes.TypeId, RAIL.Track.Id)
	model:SetAttribute(Constants.Attributes.OwnerUserId, player.UserId)
	model:SetAttribute("Ix", track.Ix)
	model:SetAttribute("Iz", track.Iz)
	model:SetAttribute("RectMinX", wx - TILE / 2)
	model:SetAttribute("RectMaxX", wx + TILE / 2)
	model:SetAttribute("RectMinZ", wz - TILE / 2)
	model:SetAttribute("RectMaxZ", wz + TILE / 2)
	model.Parent = folder
	r.models[track.TrackId] = model
end

local function rebuildAround(player, ix, iz)
	local r = getRuntime(player)
	for _, offset in ipairs({ { 0, 0 }, { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } }) do
		local track = r.cells[GridMath.cellKey(ix + offset[1], iz + offset[2])]
		if track then
			spawnModel(player, track)
		end
	end
end

-- World rects of the player's track tiles (blocked area for buildings / roads).
function RailService.getRailRects(player: Player)
	local result = {}
	local r = runtime[player]
	local bounds = services.WorldService.getBounds(player)
	if not r or not bounds then
		return result
	end
	for key, track in pairs(r.cells) do
		local _, _, rect = PlacementRules.roadCellCenter(track.Ix, track.Iz, bounds)
		result[key] = rect
	end
	return result
end

function RailService.count(player: Player): number
	local n = 0
	local r = runtime[player]
	if r then
		for _ in pairs(r.cells) do
			n += 1
		end
	end
	return n
end

function RailService.getCells(player: Player)
	local r = runtime[player]
	return r and r.cells or {}
end

function RailService.loadCountry(player: Player, country)
	RailService.clearPlayer(player)
	local data = railData(country)
	local r = getRuntime(player)
	for id, track in pairs(data.Tracks) do
		track.TrackId = track.TrackId or id
		local key = GridMath.cellKey(track.Ix, track.Iz)
		if r.cells[key] then
			data.Tracks[id] = nil
		else
			r.cells[key] = track
			r.byId[track.TrackId] = track
		end
	end
	for _, track in pairs(r.cells) do
		spawnModel(player, track)
	end
end

function RailService.clearPlayer(player: Player)
	local r = runtime[player]
	if r then
		for _, model in pairs(r.models) do
			model:Destroy()
		end
	end
	runtime[player] = nil
	trains[player] = nil
end

local function validNumber(v): boolean
	return type(v) == "number" and v == v and v > -1e6 and v < 1e6
end

local function placeLine(player, startX, startZ, endX, endZ)
	local country = services.DataService.getCountry(player)
	local bounds = services.WorldService.getBounds(player)
	if not country or not bounds then
		return { ok = false, error = "Choose a plot first" }
	end
	local data = railData(country)
	local cells, axis = PlacementRules.roadLine(startX, startZ, endX, endZ, bounds)
	local ctx = {
		plot = bounds,
		buildingRects = services.BuildingService.getBuildingRects(player, true),
		roadCells = services.RoadService.getRoadCells(player),
		railCells = RailService.getRailRects(player),
	}
	local ok, reason, tiles, newCount = PlacementRules.validateRailLine(cells, ctx)
	if not ok then
		return { ok = false, error = reason }
	end
	local affordable, costError = services.ResourceService.canAfford(country, RAIL.Track.Cost, newCount)
	if not affordable then
		return { ok = false, error = costError }
	end
	services.ResourceService.charge(country, RAIL.Track.Cost, newCount)
	local r = getRuntime(player)
	local placed = {}
	for _, tile in ipairs(tiles) do
		if not tile.existing then
			local id = "T" .. tostring(data.NextTrackId)
			data.NextTrackId += 1
			local track = { TrackId = id, Ix = tile.ix, Iz = tile.iz, Rotation = axis }
			data.Tracks[id] = track
			r.cells[GridMath.cellKey(tile.ix, tile.iz)] = track
			r.byId[id] = track
			table.insert(placed, id)
		end
	end
	for _, tile in ipairs(tiles) do
		rebuildAround(player, tile.ix, tile.iz)
	end
	services.DataService.markDirty(player)
	services.CountryService.push(player)
	return { ok = true, placed = #placed, trackIds = placed }
end

local function handlePlaceLine(player, request)
	local now = os.clock()
	if lastRequest[player] and now - lastRequest[player] < PlacementConfig.RequestCooldown then
		return { ok = false, error = "Too fast" }
	end
	lastRequest[player] = now
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

-- Demolish one track tile owned by the player. Returns ok, error.
function RailService.demolish(player: Player, trackId: any): (boolean, string?)
	local country = services.DataService.getCountry(player)
	local r = runtime[player]
	if not country or not r or type(trackId) ~= "string" then
		return false, "Nothing to demolish"
	end
	local data = railData(country)
	local track = r.byId[trackId]
	if not track or data.Tracks[trackId] == nil then
		return false, "Not your track"
	end
	data.Tracks[trackId] = nil
	r.byId[trackId] = nil
	r.cells[GridMath.cellKey(track.Ix, track.Iz)] = nil
	local model = r.models[trackId]
	if model then
		model:Destroy()
	end
	r.models[trackId] = nil
	rebuildAround(player, track.Ix, track.Iz)
	services.DataService.markDirty(player)
	services.CountryService.push(player)
	return true, nil
end

-- Station entries { record, rect (plot-local) } of completed Railway Stations.
local function stationsOf(country)
	local list = {}
	for _, record in pairs(country.Buildings or {}) do
		local def = defsById[record.Type]
		if def and def.RailStation and record.State == Constants.BuildState.Completed then
			table.insert(list, { record = record, rect = TrafficRules.localRect(record, def) })
		end
	end
	return list
end

function RailService.routes(player: Player, country)
	return RailGraph.routes(stationsOf(country), RailService.getCells(player))
end

-- Producers within StationRadius of a linked station: { [recordId] = true }.
function RailService.boostedProducers(player: Player, country)
	local boosted = {}
	local routes = RailService.routes(player, country)
	if #routes == 0 then
		return boosted
	end
	local linked = RailGraph.linkedStationIds(routes)
	for _, record in pairs(country.Buildings) do
		local def = defsById[record.Type]
		if def and def.Production then
			for stationId in pairs(linked) do
				local station = country.Buildings[stationId]
				if station then
					local dx, dz = record.X - station.X, record.Z - station.Z
					if math.sqrt(dx * dx + dz * dz) <= RAIL.StationRadius then
						boosted[record.Id] = true
						break
					end
				end
			end
		end
	end
	return boosted
end

-- Cargo manifest from the national stock: up to MaxWagons loaded wagons.
function RailService.manifest(country)
	local list = {}
	for _, key in ipairs(RAIL.Cargo) do
		local amount = math.floor(country[key] or 0)
		if amount > 0 then
			table.insert(list, { Cargo = key, Amount = math.min(RAIL.WagonCapacity, amount) })
		end
	end
	table.sort(list, function(a, b)
		return a.Amount > b.Amount
	end)
	local wagons = {}
	for i = 1, math.min(RAIL.MaxWagons, #list) do
		table.insert(wagons, list[i])
	end
	return wagons
end

local function runTrain(player)
	local country = services.DataService.getCountry(player)
	local bounds = services.WorldService.getBounds(player)
	local folder = services.WorldService.getPlotFolder(player, "Vehicles")
	if not country or not bounds or not folder then
		return false
	end
	local routes = RailService.routes(player, country)
	if #routes == 0 then
		return false
	end
	local state = trainState(player)
	if state.active > 0 then
		return false -- one train per plot at a time (cheap)
	end
	state.routeIndex = state.routeIndex % #routes + 1
	local route = routes[state.routeIndex]
	local path = table.clone(route.path)
	if state.trips % 2 == 1 then
		local reversed = {}
		for i = #path, 1, -1 do
			table.insert(reversed, path[i])
		end
		path = reversed
	end
	state.trips += 1
	local cells = RailService.getCells(player)
	local centers = {}
	for _, key in ipairs(path) do
		local track = cells[key]
		local cx, cz = RailGraph.center(track.Ix, track.Iz)
		table.insert(centers, { X = bounds.minX + cx, Z = bounds.minZ + cz })
	end
	centers = TrafficRules.simplify(centers)
	if #centers == 1 then
		local c = centers[1]
		centers = { { X = c.X, Z = c.Z - 0.9 }, { X = c.X, Z = c.Z + 0.9 } }
	end
	local y = bounds.surfaceY + 0.22
	local points = {}
	for _, c in ipairs(centers) do
		table.insert(points, Vector3.new(c.X, y, c.Z))
	end
	local wagons = RailService.manifest(country)
	local speed = RAIL.TrainSpeed
	local spacingDelay = RAIL.WagonSpacing / speed
	state.active = 1 + #wagons
	local function arrived(isLoco, loaded)
		state.active = math.max(0, state.active - 1)
		if loaded and services.DataService.getCountry(player) == country then
			local data = railData(country)
			data.Delivered += loaded.Amount
			country.Treasury = (country.Treasury or 0) + RAIL.FreightIncomePerWagon
			services.DataService.markDirty(player)
			services.CountryService.push(player)
		end
		if isLoco then
			services.CountryService.notify(player, "Freight train arrived", "info")
		end
	end
	local loco = VehicleModels.locomotive()
	loco:SetAttribute(Constants.Attributes.Kind, Constants.Kinds.Vehicle)
	services.VehicleService.drive(loco, folder, points, speed, 0, function(ok)
		arrived(true, nil)
		return ok
	end)
	for i, wagon in ipairs(wagons) do
		local model = VehicleModels.wagon(wagon.Cargo)
		model:SetAttribute(Constants.Attributes.Kind, Constants.Kinds.Vehicle)
		model:SetAttribute("Cargo", wagon.Cargo)
		model:SetAttribute("Amount", wagon.Amount)
		services.VehicleService.drive(model, folder, points, speed, spacingDelay * i, function(ok)
			arrived(false, ok and wagon or nil)
		end)
	end
	return true
end

function RailService.getStats(player: Player, country)
	local routes = country and RailService.routes(player, country) or {}
	local stations = country and #stationsOf(country) or 0
	local state = trains[player]
	return {
		Tracks = RailService.count(player),
		Stations = stations,
		Routes = #routes,
		ActiveTrains = (state and state.active > 0) and 1 or 0,
		Trips = state and state.trips or 0,
		Delivered = country and country.Railway and country.Railway.Delivered or 0,
	}
end

function RailService.init(allServices)
	services = allServices
	remotes = allServices.Remotes
end

function RailService.start()
	remotes[Constants.Remotes.PlaceRailLine].OnServerInvoke = handlePlaceLine
	task.spawn(function()
		while true do
			task.wait(RAIL.IntervalSeconds)
			for _, player in ipairs(Players:GetPlayers()) do
				if services.WorldService.getPlotIndex(player) then
					local ok, err = pcall(runTrain, player)
					if not ok then
						warn("[RailService] " .. tostring(err))
					end
				end
			end
		end
	end)
	Players.PlayerRemoving:Connect(function(player)
		RailService.clearPlayer(player)
		lastRequest[player] = nil
	end)
end

return RailService
