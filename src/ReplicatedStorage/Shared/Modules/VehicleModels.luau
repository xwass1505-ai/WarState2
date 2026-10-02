-- VehicleModels: small low-part models for civilian cars, freight trains and rail track tiles.
-- Sizes are in studs (roads are 2-stud tiles with a 1.6-stud carriageway).
-- Moving models: one anchored, invisible Root (PrimaryPart) + welded, massless visual parts, so the
-- server moves the whole vehicle by tweening Root.CFrame (TweenService, no per-frame scripts).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local PlacementConfig = require(Shared:WaitForChild("Config"):WaitForChild("PlacementConfig"))

local VehicleModels = {}

local CAR_COLORS = {
	Color3.fromRGB(232, 92, 84),
	Color3.fromRGB(84, 146, 228),
	Color3.fromRGB(244, 244, 240),
	Color3.fromRGB(246, 196, 72),
	Color3.fromRGB(96, 178, 120),
	Color3.fromRGB(70, 76, 88),
}
VehicleModels.CarColors = CAR_COLORS

local GLASS = Color3.fromRGB(150, 190, 220)
local TIRE = Color3.fromRGB(40, 42, 46)

local function part(model, name, size, cframe, color, shape)
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.CFrame = cframe
	p.Color = color
	p.Material = Enum.Material.SmoothPlastic
	p.Anchored = true
	p.CanCollide = false
	p.CanTouch = false
	p.CanQuery = false
	p.CastShadow = false
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	if shape then
		p.Shape = shape
	end
	p.Parent = model
	return p
end

local function newRoot(model, size)
	local root = part(model, "Root", size, CFrame.new(), Color3.new(1, 1, 1))
	root.Transparency = 1
	model.PrimaryPart = root
	return root
end

-- Turns every non-root part into a massless, welded passenger of the anchored Root.
function VehicleModels.rig(model: Model)
	local root = model.PrimaryPart
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") and d ~= root then
			local weld = Instance.new("WeldConstraint")
			weld.Part0 = root
			weld.Part1 = d
			weld.Parent = d
			d.Massless = true
			d.Anchored = false
		end
	end
	return model
end

local function wheel(model, x, z)
	part(model, "Wheel", Vector3.new(0.12, 0.26, 0.26), CFrame.new(x, 0.13, z) * CFrame.Angles(0, 0, 0), TIRE, Enum.PartType.Cylinder)
end

-- Compact car, about 1.0 x 0.5 studs, facing -Z (CFrame.lookAt forward).
function VehicleModels.car(colorIndex: number?)
	local color = CAR_COLORS[((colorIndex or 1) - 1) % #CAR_COLORS + 1]
	local model = Instance.new("Model")
	model.Name = "Car"
	newRoot(model, Vector3.new(0.5, 0.1, 1.0))
	part(model, "Body", Vector3.new(0.5, 0.22, 1.0), CFrame.new(0, 0.24, 0), color)
	part(model, "Cabin", Vector3.new(0.44, 0.18, 0.5), CFrame.new(0, 0.44, 0.05), color:Lerp(Color3.new(1, 1, 1), 0.15))
	part(model, "Windshield", Vector3.new(0.4, 0.14, 0.04), CFrame.new(0, 0.44, -0.21), GLASS)
	for _, x in ipairs({ -0.24, 0.24 }) do
		wheel(model, x, -0.32)
		wheel(model, x, 0.32)
	end
	return VehicleModels.rig(model)
end

-- Freight locomotive (~1.7 x 0.8), facing -Z.
function VehicleModels.locomotive()
	local model = Instance.new("Model")
	model.Name = "Locomotive"
	newRoot(model, Vector3.new(0.8, 0.1, 1.7))
	local body = Color3.fromRGB(206, 78, 72)
	part(model, "Chassis", Vector3.new(0.76, 0.18, 1.7), CFrame.new(0, 0.2, 0), Color3.fromRGB(60, 64, 70))
	part(model, "Hood", Vector3.new(0.64, 0.42, 1.1), CFrame.new(0, 0.5, 0.25), body)
	part(model, "Cab", Vector3.new(0.72, 0.62, 0.5), CFrame.new(0, 0.6, -0.55), body)
	part(model, "CabGlass", Vector3.new(0.6, 0.18, 0.04), CFrame.new(0, 0.75, -0.81), GLASS)
	part(model, "Stripe", Vector3.new(0.78, 0.06, 1.72), CFrame.new(0, 0.32, 0), Color3.fromRGB(246, 246, 240))
	return VehicleModels.rig(model)
end

-- Freight wagon (~1.6 x 0.76). cargo = resource key (changes the load colour).
local CARGO_COLORS = {
	Coal = Color3.fromRGB(46, 48, 52),
	IronOre = Color3.fromRGB(158, 92, 64),
	Oil = Color3.fromRGB(30, 30, 34),
	Fuel = Color3.fromRGB(232, 146, 72),
	Steel = Color3.fromRGB(168, 176, 186),
	Supplies = Color3.fromRGB(158, 114, 78),
}
VehicleModels.CargoColors = CARGO_COLORS

function VehicleModels.wagon(cargo: string?)
	local model = Instance.new("Model")
	model.Name = "Wagon"
	newRoot(model, Vector3.new(0.76, 0.1, 1.6))
	part(model, "Chassis", Vector3.new(0.72, 0.16, 1.6), CFrame.new(0, 0.18, 0), Color3.fromRGB(60, 64, 70))
	local load = CARGO_COLORS[cargo or ""] or Color3.fromRGB(150, 150, 150)
	if cargo == "Oil" or cargo == "Fuel" then
		part(model, "Tank", Vector3.new(1.4, 0.56, 0.56), CFrame.new(0, 0.55, 0) * CFrame.Angles(0, math.rad(90), 0), Color3.fromRGB(226, 228, 230), Enum.PartType.Cylinder)
		part(model, "Band", Vector3.new(0.6, 0.58, 0.2), CFrame.new(0, 0.55, 0), load)
	else
		part(model, "Hopper", Vector3.new(0.7, 0.36, 1.5), CFrame.new(0, 0.45, 0), Color3.fromRGB(96, 110, 126))
		part(model, "Load", Vector3.new(0.6, 0.12, 1.36), CFrame.new(0, 0.66, 0), load)
	end
	return VehicleModels.rig(model)
end

-- Static rail track tile at the origin. openings: "NS", "EW" or any mix (junctions / crossings).
function VehicleModels.railTile(openings: string?)
	local tile = PlacementConfig.RoadTileSize
	local model = Instance.new("Model")
	model.Name = "RailTrack"
	newRoot(model, Vector3.new(tile, 0.05, tile))
	local gravel = Color3.fromRGB(150, 146, 140)
	local sleeper = Color3.fromRGB(122, 92, 66)
	local rail = Color3.fromRGB(110, 116, 126)
	part(model, "Ballast", Vector3.new(tile - 0.1, 0.08, tile - 0.1), CFrame.new(0, 0.04, 0), gravel)
	local s = openings or "NS"
	local ns = string.find(s, "N", 1, true) ~= nil or string.find(s, "S", 1, true) ~= nil
	local ew = string.find(s, "E", 1, true) ~= nil or string.find(s, "W", 1, true) ~= nil
	if not ns and not ew then
		ns = true
	end
	if ns then
		for _, z in ipairs({ -0.66, 0, 0.66 }) do
			part(model, "Sleeper", Vector3.new(1.1, 0.06, 0.22), CFrame.new(0, 0.11, z), sleeper)
		end
		for _, x in ipairs({ -0.3, 0.3 }) do
			part(model, "Rail", Vector3.new(0.08, 0.08, tile), CFrame.new(x, 0.18, 0), rail)
		end
	end
	if ew then
		for _, x in ipairs({ -0.66, 0, 0.66 }) do
			part(model, "SleeperX", Vector3.new(0.22, 0.06, 1.1), CFrame.new(x, 0.11, 0), sleeper)
		end
		for _, z in ipairs({ -0.3, 0.3 }) do
			part(model, "RailX", Vector3.new(tile, 0.08, 0.08), CFrame.new(0, 0.19, z), rail)
		end
	end
	return model
end

return VehicleModels
