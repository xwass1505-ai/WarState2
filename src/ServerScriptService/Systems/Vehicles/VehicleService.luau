-- VehicleService: civilian traffic + the movement / routing foundation for future vehicles
-- (trucks, tanks, IFV, military vehicles leave the plot through its exit: routeToCentral).
--
-- CIVILIAN TRAFFIC (every Traffic.IntervalSeconds = 60 s, server side):
--   H = completed houses, cars = ceil(H / 2) (max Traffic.MaxCarsPerWave), started from ~half of
--   the houses. Route: House -> nearest road tile -> real road graph (BFS) -> tile next to a
--   Shop / Gas Station / Office -> the car disappears. No destination / no path = no car.
-- Movement: one anchored Root per car, TweenService per straight stretch (collinear tiles merged),
-- so a car drives along the roads (never teleports) and the server does no per-frame work.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = Shared:WaitForChild("Config")
local Modules = Shared:WaitForChild("Modules")
local GameConfig = require(Config:WaitForChild("GameConfig"))
local BuildingConfig = require(Config:WaitForChild("BuildingConfig"))
local Constants = require(Shared:WaitForChild("Constants"):WaitForChild("Constants"))
local RoadGraph = require(Modules:WaitForChild("RoadGraph"))
local TrafficRules = require(Modules:WaitForChild("TrafficRules"))
local VehicleModels = require(Modules:WaitForChild("VehicleModels"))

local VehicleService = {}
VehicleService.Name = "VehicleService"
VehicleService.Status = "IMPLEMENTED"
VehicleService.Active = true
VehicleService.VehicleClasses = {
	{ Id = "Car", Category = "Civilian", Status = "IMPLEMENTED" },
	{ Id = "FreightTrain", Category = "Logistics", Status = "IMPLEMENTED" },
	{ Id = "Truck", Category = "Logistics", Status = "PLANNED" },
	{ Id = "Tank", Category = "Military", Status = "PLANNED" },
	{ Id = "IFV", Category = "Military", Status = "PLANNED" },
	{ Id = "MilitaryVehicle", Category = "Military", Status = "PLANNED" },
}

local TRAFFIC = GameConfig.Traffic
local services
local defsById = {}
for _, def in ipairs(BuildingConfig.Buildings) do
	defsById[def.Id] = def
end
local activeCars = {} -- [Player] = count
local lastWave = {} -- [Player] = { houses, cars }
local rng = Random.new()

-- Moves a rigged model (VehicleModels) through world points at `speed` studs/s. Parents it to
-- `folder` when it starts (after delaySeconds) and destroys it at the end. onDone(arrived) optional.
function VehicleService.drive(model: Model, folder: Instance, points, speed: number, delaySeconds: number, onDone)
	local root = model.PrimaryPart
	local finished = false
	local function finish(arrived: boolean)
		if finished then
			return
		end
		finished = true
		model:Destroy()
		if onDone then
			onDone(arrived)
		end
	end
	if not root or #points < 2 then
		finish(false)
		return
	end
	local index = 1
	local function step()
		if not model.Parent or not folder.Parent then
			finish(false)
			return
		end
		index += 1
		if index > #points then
			finish(true)
			return
		end
		local from = root.Position
		local to = points[index]
		local delta = to - from
		local distance = delta.Magnitude
		if distance < 0.01 then
			step()
			return
		end
		root.CFrame = CFrame.lookAt(from, to)
		local tween = TweenService:Create(root, TweenInfo.new(distance / speed, Enum.EasingStyle.Linear), {
			CFrame = CFrame.lookAt(to, to + delta.Unit),
		})
		tween.Completed:Connect(step)
		tween:Play()
	end
	task.delay(delaySeconds, function()
		if not folder.Parent then
			finish(false)
			return
		end
		local first, second = points[1], points[2]
		if (second - first).Magnitude > 0.01 then
			root.CFrame = CFrame.lookAt(first, second)
		else
			root.CFrame = CFrame.new(first)
		end
		model.Parent = folder
		step()
	end)
	task.delay(delaySeconds + TRAFFIC.CarLifetimeSeconds * 4, function()
		finish(false) -- safety net: nothing lives forever
	end)
end

-- Road path (RoadIds) -> world waypoints on the right-hand lane.
function VehicleService.laneWaypoints(bounds, segmentsById, path)
	local centers = {}
	for _, roadId in ipairs(path) do
		local p = segmentsById[roadId].Position
		table.insert(centers, { X = bounds.minX + p.X, Z = bounds.minZ + p.Z })
	end
	centers = TrafficRules.simplify(centers)
	local y = bounds.surfaceY + 0.09
	local points = {}
	if #centers == 1 then
		local c = centers[1]
		table.insert(points, Vector3.new(c.X - 0.6, y, c.Z))
		table.insert(points, Vector3.new(c.X + 0.6, y, c.Z))
		return points
	end
	local lane = TRAFFIC.LaneOffset
	for i = 1, #centers - 1 do
		local a, b = centers[i], centers[i + 1]
		local dir = Vector3.new(b.X - a.X, 0, b.Z - a.Z).Unit
		local right = dir:Cross(Vector3.new(0, 1, 0)) * lane
		table.insert(points, Vector3.new(a.X, y, a.Z) + right)
		table.insert(points, Vector3.new(b.X, y, b.Z) + right)
	end
	return points
end

local function spawnTrip(player, bounds, folder, segmentsById, trip, order)
	local points = VehicleService.laneWaypoints(bounds, segmentsById, trip.path)
	local car = VehicleModels.car(rng:NextInteger(1, #VehicleModels.CarColors))
	car.Name = "Car_" .. tostring(trip.origin.Id)
	car:SetAttribute(Constants.Attributes.Kind, Constants.Kinds.Vehicle)
	car:SetAttribute("From", trip.origin.Id)
	car:SetAttribute("To", trip.destination.Id)
	activeCars[player] = (activeCars[player] or 0) + 1
	VehicleService.drive(car, folder, points, TRAFFIC.CarSpeed, order * 0.7, function()
		activeCars[player] = math.max(0, (activeCars[player] or 1) - 1)
	end)
end

-- One traffic wave for a player. Returns cars spawned.
function VehicleService.trafficWave(player: Player): number
	local country = services.DataService.getCountry(player)
	local bounds = services.WorldService.getBounds(player)
	local folder = services.WorldService.getPlotFolder(player, "Vehicles")
	if not country or not bounds or not folder then
		return 0
	end
	local segmentsById = services.RoadService.getSegmentsById(player)
	local trips, houses = TrafficRules.planTrips(country.Buildings, defsById, segmentsById, rng)
	lastWave[player] = { Houses = houses, Cars = #trips, Planned = TrafficRules.carCount(houses) }
	for i, trip in ipairs(trips) do
		spawnTrip(player, bounds, folder, segmentsById, trip, i - 1)
	end
	return #trips
end

function VehicleService.getTrafficStats(player: Player)
	local wave = lastWave[player] or { Houses = 0, Cars = 0, Planned = 0 }
	return { ActiveCars = activeCars[player] or 0, LastWaveCars = wave.Cars, LastWaveHouses = wave.Houses }
end

-- Returns world waypoints { Vector3, ... } from a road tile to the central island, or nil + reason.
-- Route: PLAYER PLOT (road graph) -> EXIT tile -> bridge -> MAIN MAP -> CENTRAL ISLAND.
function VehicleService.routeToCentral(player: Player, fromRoadId: string)
	local bounds = services.WorldService.getBounds(player)
	local exit = services.WorldService.getExit(player)
	if not bounds or not exit then
		return nil, "No plot"
	end
	local segmentsById = services.RoadService.getSegmentsById(player)
	local path = RoadGraph.pathToExit(segmentsById, fromRoadId)
	if not path then
		return nil, "Road is not connected to the plot exit"
	end
	local waypoints = {}
	for _, roadId in ipairs(path) do
		local segment = segmentsById[roadId]
		table.insert(waypoints, Vector3.new(bounds.minX + segment.Position.X, bounds.surfaceY, bounds.minZ + segment.Position.Z))
	end
	for i, point in ipairs(exit.waypoints) do
		if i > 1 then
			table.insert(waypoints, Vector3.new(point.X, bounds.surfaceY, point.Z))
		end
	end
	return waypoints, nil
end

-- True when at least one road tile of the player touches the exit.
function VehicleService.hasExitAccess(player: Player): boolean
	for _, segment in pairs(services.RoadService.getSegmentsById(player)) do
		if segment.ExitConnected then
			return true
		end
	end
	return false
end

function VehicleService.init(allServices)
	services = allServices
end

function VehicleService.start()
	task.spawn(function()
		while true do
			task.wait(TRAFFIC.IntervalSeconds)
			for _, player in ipairs(Players:GetPlayers()) do
				if services.WorldService.getPlotIndex(player) then
					local ok, err = pcall(VehicleService.trafficWave, player)
					if not ok then
						warn("[VehicleService] " .. tostring(err))
					end
				end
			end
		end
	end)
	Players.PlayerRemoving:Connect(function(player)
		activeCars[player] = nil
		lastWave[player] = nil
	end)
end

return VehicleService
