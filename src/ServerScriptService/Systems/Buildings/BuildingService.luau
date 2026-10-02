-- BuildingService: server-authoritative building placement and demolition.
-- Client sends {Type, Variant, X, Z, Rotation}; the server snaps and validates against the
-- player's OWN plot (territory, overlap, road access within PlacementConfig.MaxRoadDistance,
-- resources) and creates a PLANNED building that ConstructionService builds over time.
-- Demolish requests are only accepted for records that exist in the requester's own country,
-- so nobody can build, delete or modify anything on another player's plot.
-- v0.4: the server also checks the POPULATION UNLOCK (BuildingConfig.PopulationRequired) and the full
-- cost table (Treasury + resources). Rail track tiles are part of the blocked footprints.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = Shared:WaitForChild("Config")
local Modules = Shared:WaitForChild("Modules")
local BuildingConfig = require(Config:WaitForChild("BuildingConfig"))
local PlacementConfig = require(Config:WaitForChild("PlacementConfig"))
local Constants = require(Shared:WaitForChild("Constants"):WaitForChild("Constants"))
local GridMath = require(Modules:WaitForChild("GridMath"))
local PlacementRules = require(Modules:WaitForChild("PlacementRules"))
local BuildingModels = require(Modules:WaitForChild("BuildingModels"))
local EconomyRules = require(Modules:WaitForChild("EconomyRules"))
require(Modules:WaitForChild("ExtraModels")) -- registers the v0.4 building variants

local BuildingService = {}
BuildingService.Name = "BuildingService"

local services
local remotes
local runtime = {} -- [Player] = { models = {Id -> Model}, rects = {Id -> Rect} }
local lastRequest = {}

local defsById = {}
for _, def in ipairs(BuildingConfig.Buildings) do
	defsById[def.Id] = def
end
BuildingService.DefsById = defsById

function BuildingService.getDef(typeId: string)
	return defsById[typeId]
end

local function getRuntime(player)
	local r = runtime[player]
	if not r then
		r = { models = {}, rects = {} }
		runtime[player] = r
	end
	return r
end

local function worldRect(record, bounds)
	local def = defsById[record.Type]
	local width, depth = GridMath.rotatedSize(def.Footprint[1], def.Footprint[2], record.Rotation)
	return GridMath.rect(bounds.minX + record.X, bounds.minZ + record.Z, width, depth)
end

local function spawnModel(player, record)
	local folder = services.WorldService.getPlotFolder(player, "Buildings")
	local bounds = services.WorldService.getBounds(player)
	local def = defsById[record.Type]
	if not folder or not bounds or not def then
		return nil
	end
	local r = getRuntime(player)
	local old = r.models[record.Id]
	if old then
		old:Destroy()
	end
	local model = BuildingModels.build(def, record.Variant)
	model.Name = record.Id
	local wx, wz = bounds.minX + record.X, bounds.minZ + record.Z
	model:PivotTo(CFrame.new(wx, bounds.surfaceY, wz) * CFrame.Angles(0, GridMath.yawForRotation(record.Rotation), 0))
	local rect = worldRect(record, bounds)
	model:SetAttribute(Constants.Attributes.Kind, "Building")
	model:SetAttribute(Constants.Attributes.TypeId, record.Type)
	model:SetAttribute(Constants.Attributes.OwnerUserId, player.UserId)
	model:SetAttribute("Variant", record.Variant)
	model:SetAttribute("RectMinX", rect.minX)
	model:SetAttribute("RectMaxX", rect.maxX)
	model:SetAttribute("RectMinZ", rect.minZ)
	model:SetAttribute("RectMaxZ", rect.maxZ)
	model:SetAttribute("State", record.State)
	model:SetAttribute("BuildTime", def.BuildTimeSeconds)
	model:SetAttribute("WaterStatus", record.WaterStatus or "GREY")
	model:SetAttribute("PowerStatus", record.PowerStatus or "GREY")
	model.Parent = folder
	r.models[record.Id] = model
	r.rects[record.Id] = rect
	return model
end

function BuildingService.getModel(player: Player, id: string)
	local r = runtime[player]
	return r and r.models[id] or nil
end

-- Footprints that block placement: buildings + rail track tiles (world space).
function BuildingService.getBuildingRects(player: Player, excludeRails: boolean?)
	local result = {}
	local r = runtime[player]
	if r then
		for _, rect in pairs(r.rects) do
			table.insert(result, rect)
		end
	end
	if not excludeRails and services.RailService then
		for _, rect in pairs(services.RailService.getRailRects(player)) do
			table.insert(result, rect)
		end
	end
	return result
end

-- Called whenever buildings are added/removed/completed: recompute water + power coverage,
-- housing capacity, then replicate. Event-driven (never a per-frame recalculation).
function BuildingService.onBuildingsChanged(player: Player)
	local country = services.DataService.getCountry(player)
	if not country then
		return
	end
	services.PopulationService.recalculate(country)
	services.WaterService.recompute(player)
	services.PowerService.recompute(player)
	services.DataService.markDirty(player)
	services.CountryService.push(player)
end

-- Mirror utility statuses onto the models (used by client overlays).
function BuildingService.refreshUtilityAttributes(player: Player)
	local country = services.DataService.getCountry(player)
	local r = runtime[player]
	if not country or not r then
		return
	end
	for id, model in pairs(r.models) do
		local record = country.Buildings[id]
		if record then
			model:SetAttribute("WaterStatus", record.WaterStatus or "GREY")
			model:SetAttribute("PowerStatus", record.PowerStatus or "GREY")
		end
	end
end

function BuildingService.loadCountry(player: Player, country)
	BuildingService.clearPlayer(player)
	for _, record in pairs(country.Buildings) do
		if defsById[record.Type] and BuildingModels.hasVariant(record.Variant) then
			local model = spawnModel(player, record)
			if model then
				services.ConstructionService.track(player, record, model)
			end
		else
			warn("[BuildingService] Skipping unknown saved building " .. tostring(record.Type))
		end
	end
end

function BuildingService.clearPlayer(player: Player)
	local r = runtime[player]
	if r then
		for _, model in pairs(r.models) do
			model:Destroy()
		end
	end
	runtime[player] = nil
end

local function validNumber(v): boolean
	return type(v) == "number" and v == v and v > -1e6 and v < 1e6
end

local function handlePlace(player, request)
	local now = os.clock()
	if lastRequest[player] and now - lastRequest[player] < PlacementConfig.RequestCooldown then
		return { ok = false, error = "Too fast" }
	end
	lastRequest[player] = now

	local country = services.DataService.getCountry(player)
	local bounds = services.WorldService.getBounds(player)
	if not country or not bounds then
		return { ok = false, error = "Choose a plot first" }
	end
	if type(request) ~= "table" or not validNumber(request.X) or not validNumber(request.Z) then
		return { ok = false, error = "Invalid request" }
	end
	local def = type(request.Type) == "string" and defsById[request.Type] or nil
	if not def or def.Active ~= true then
		return { ok = false, error = "Unknown building" }
	end
	local variant = request.Variant
	if type(variant) ~= "string" or not table.find(def.Variants, variant) then
		variant = def.Variants[1]
	end
	local rotation = GridMath.normalizeRotation(validNumber(request.Rotation) and request.Rotation or 0)

	local ctx = {
		plot = bounds,
		buildingRects = BuildingService.getBuildingRects(player),
		roadCells = services.RoadService.getRoadCells(player),
	}
	local ok, reason, info = PlacementRules.validateBuilding(def, request.X, request.Z, rotation, ctx)
	if not ok then
		return { ok = false, error = reason }
	end
	if not EconomyRules.isUnlocked(def, country.Population) then
		return { ok = false, error = EconomyRules.unlockText(def) }
	end
	local affordable, costError = services.ResourceService.canAfford(country, def.Cost)
	if not affordable then
		return { ok = false, error = costError }
	end
	services.ResourceService.charge(country, def.Cost)

	local id = "B" .. tostring(country.NextBuildingId)
	country.NextBuildingId += 1
	local record = {
		Id = id,
		Type = def.Id,
		Variant = variant,
		X = info.centerX - bounds.minX,
		Z = info.centerZ - bounds.minZ,
		Rotation = rotation,
		State = Constants.BuildState.Planned,
		PlannedElapsed = 0,
		Progress = 0,
		CreatedAt = os.time(),
		WaterRequired = def.Water and def.Water.Required or 0,
		WaterSupplied = 0,
		WaterStatus = "GREY",
		PowerRequired = def.Power and def.Power.Required or 0,
		PowerSupplied = 0,
		PowerStatus = "GREY",
	}
	country.Buildings[id] = record
	local model = spawnModel(player, record)
	if model then
		services.ConstructionService.track(player, record, model)
	end
	BuildingService.onBuildingsChanged(player)
	return { ok = true, buildingId = id }
end

-- Demolish one building owned by the player. Returns ok, error.
function BuildingService.demolish(player: Player, id: any): (boolean, string?)
	local country = services.DataService.getCountry(player)
	if not country or type(id) ~= "string" then
		return false, "Nothing to demolish"
	end
	local record = country.Buildings[id]
	if not record then
		return false, "Not your building"
	end
	country.Buildings[id] = nil
	local def = defsById[record.Type]
	if def and record.State ~= Constants.BuildState.Completed then
		services.ResourceService.refund(country, def.Cost, 0.5) -- cancelled construction: half back
	end
	services.ConstructionService.untrack(player, id)
	local r = runtime[player]
	if r then
		local model = r.models[id]
		if model then
			model:Destroy()
		end
		r.models[id] = nil
		r.rects[id] = nil
	end
	BuildingService.onBuildingsChanged(player)
	return true, nil
end

local function handleDemolish(player, request)
	local now = os.clock()
	if lastRequest[player] and now - lastRequest[player] < PlacementConfig.RequestCooldown then
		return { ok = false, error = "Too fast" }
	end
	lastRequest[player] = now
	if type(request) ~= "table" or type(request.Id) ~= "string" then
		return { ok = false, error = "Invalid request" }
	end
	if not services.WorldService.getPlotIndex(player) then
		return { ok = false, error = "Choose a plot first" }
	end
	local ok, err
	if request.Kind == "Road" then
		ok, err = services.RoadService.demolish(player, request.Id)
	elseif request.Kind == "Building" then
		ok, err = BuildingService.demolish(player, request.Id)
	elseif request.Kind == "Rail" then
		ok, err = services.RailService.demolish(player, request.Id)
	else
		return { ok = false, error = "Invalid request" }
	end
	return { ok = ok, error = err }
end

function BuildingService.init(allServices)
	services = allServices
	remotes = allServices.Remotes
end

function BuildingService.start()
	remotes[Constants.Remotes.PlaceBuilding].OnServerInvoke = handlePlace
	remotes[Constants.Remotes.Demolish].OnServerInvoke = handleDemolish
	Players.PlayerRemoving:Connect(function(player)
		BuildingService.clearPlayer(player)
		lastRequest[player] = nil
	end)
end

return BuildingService
