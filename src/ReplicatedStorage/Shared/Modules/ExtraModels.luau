-- ExtraModels: procedural low-part models for the v0.4 buildings (apartments, gas station, mines,
-- oil well, refinery, steel factory, warehouse, railway station, military and research buildings).
-- Same conventions as BuildingModels: design units (4 units = 1 stud at ModelScale 0.25), model faces +Z,
-- every part non-colliding, BaseTransparency attribute for the construction reveal.
-- Variants are registered into BuildingModels.Variants (the same table BuildingModels.build reads),
-- so requiring this module once (server: BuildingService, client: ClientMain) makes them buildable.

local BuildingModels = require(script.Parent:WaitForChild("BuildingModels"))

local ExtraModels = {}

local RAD90 = math.rad(90)
local P = BuildingModels.Palette

local K = {
	Concrete = Color3.fromRGB(196, 198, 196),
	Asphalt = Color3.fromRGB(96, 100, 106),
	Coal = Color3.fromRGB(46, 48, 52),
	Rust = Color3.fromRGB(158, 92, 64),
	Olive = Color3.fromRGB(112, 124, 86),
	OliveDark = Color3.fromRGB(84, 94, 66),
	Khaki = Color3.fromRGB(176, 164, 122),
	Camo = Color3.fromRGB(96, 110, 82),
	Red = Color3.fromRGB(206, 78, 72),
	Yellow = Color3.fromRGB(240, 200, 70),
	Purple = Color3.fromRGB(146, 120, 226),
	Teal = Color3.fromRGB(96, 186, 186),
	Navy = Color3.fromRGB(66, 86, 126),
	Green = Color3.fromRGB(96, 170, 110),
	Orange = Color3.fromRGB(232, 146, 72),
	Sand = Color3.fromRGB(214, 196, 150),
}
ExtraModels.Colors = K

local function part(model, name, size, cframe, color, material, transparency)
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.CFrame = cframe
	p.Color = color
	p.Material = material or Enum.Material.SmoothPlastic
	p.Anchored = true
	p.CanCollide = false
	p.CanTouch = false
	p.CanQuery = false
	p.CastShadow = true
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Transparency = transparency or 0
	p:SetAttribute("BaseTransparency", p.Transparency)
	p.Parent = model
	return p
end

local function box(m, name, sx, sy, sz, x, y, z, color, material)
	return part(m, name, Vector3.new(sx, sy, sz), CFrame.new(x, y, z), color, material)
end

-- Vertical cylinder standing on y0 with the given height.
local function cyl(m, name, diameter, height, x, y0, z, color)
	local p = part(m, name, Vector3.new(height, diameter, diameter), CFrame.new(x, y0 + height / 2, z) * CFrame.Angles(0, 0, RAD90), color)
	p.Shape = Enum.PartType.Cylinder
	return p
end

-- Horizontal cylinder along X (alongX) or Z.
local function hcyl(m, name, diameter, length, x, y, z, color, alongX)
	local cf = CFrame.new(x, y, z)
	if not alongX then
		cf = cf * CFrame.Angles(0, RAD90, 0)
	end
	local p = part(m, name, Vector3.new(length, diameter, diameter), cf, color)
	p.Shape = Enum.PartType.Cylinder
	return p
end

local function ball(m, name, diameter, x, y, z, color)
	local p = part(m, name, Vector3.new(diameter, diameter, diameter), CFrame.new(x, y, z), color)
	p.Shape = Enum.PartType.Ball
	return p
end

local function pad(m, w, d, color)
	box(m, "Pad", w, 0.3, d, 0, 0.15, 0, color or P.Foundation)
end

local function hall(m, name, x, z, w, d, h, wall, roof)
	box(m, name, w, h, d, x, 0.3 + h / 2, z, wall)
	box(m, name .. "Roof", w + 0.4, 0.35, d + 0.4, x, 0.3 + h + 0.17, z, roof)
end

local function windows(m, x, z, w, h, floors, frontZ, glass)
	for f = 1, floors do
		local y = 1.6 + (f - 1) * (h / floors)
		box(m, "Windows", w * 0.82, 0.9, 0.12, x, y, frontZ, glass)
	end
end

local function door(m, x, frontZ, color)
	box(m, "Door", 1.3, 2.2, 0.14, x, 1.4, frontZ, color or P.Charcoal)
end

local function flagPole(m, x, z, h, color)
	box(m, "Pole", 0.2, h, 0.2, x, h / 2, z, P.White)
	box(m, "Flag", 1.4, 0.8, 0.08, x + 0.75, h - 0.5, z, color)
end

-- APARTMENTS (12 x 12)
local function apartment(m, wall, accent)
	pad(m, 11.6, 11.6)
	hall(m, "BlockA", -2.4, -1.0, 6.4, 8.6, 13.6, wall, P.Charcoal)
	hall(m, "BlockB", 3.2, 0.4, 4.6, 7.4, 9.4, wall:Lerp(P.White, 0.25), P.Charcoal)
	for f = 0, 3 do
		box(m, "WinA", 5.2, 1.0, 0.12, -2.4, 2.0 + f * 3.2, 3.28, P.Glass)
		box(m, "Balcony", 2.0, 0.25, 0.8, -2.4, 1.4 + f * 3.2, 3.6, accent)
	end
	for f = 0, 2 do
		box(m, "WinB", 3.6, 1.0, 0.12, 3.2, 2.0 + f * 3.0, 4.16, P.Glass)
	end
	door(m, 3.2, 4.18, accent)
	box(m, "RoofUnit", 1.8, 1.0, 1.6, -3.2, 14.9, -2.6, P.Steel)
end

-- GAS STATION (12 x 8)
local function gasStation(m, canopy, accent)
	pad(m, 11.6, 7.6, K.Asphalt)
	for _, p in ipairs({ { -4.2, -1.2 }, { 0.6, -1.2 }, { -4.2, 2.4 }, { 0.6, 2.4 } }) do
		box(m, "Post", 0.35, 4.2, 0.35, p[1], 2.4, p[2], P.White)
	end
	box(m, "Canopy", 6.8, 0.5, 5.2, -1.8, 4.75, 0.6, canopy)
	box(m, "CanopyStripe", 6.9, 0.2, 5.3, -1.8, 4.45, 0.6, accent)
	for _, x in ipairs({ -3.0, -0.6 }) do
		box(m, "Pump", 0.8, 1.6, 0.6, x, 1.1, 0.6, P.White)
		box(m, "PumpTop", 0.85, 0.3, 0.65, x, 2.05, 0.6, accent)
	end
	hall(m, "Kiosk", 3.8, -0.8, 3.4, 4.8, 3.2, P.White, accent)
	box(m, "KioskWindow", 2.6, 1.2, 0.12, 3.8, 1.9, 1.66, P.Glass)
	box(m, "Sign", 0.3, 4.6, 1.4, 5.3, 2.6, 3.0, accent)
end

-- MINES (12 x 12): headframe, winding house, ore pile
local function mine(m, ore, accent)
	pad(m, 11.6, 11.6, K.Sand)
	for _, x in ipairs({ -3.6, -1.2 }) do
		box(m, "Leg", 0.4, 9.0, 0.4, x, 4.8, -2.4, P.SteelDark)
		box(m, "Leg2", 0.4, 9.0, 0.4, x, 4.8, 0.0, P.SteelDark)
	end
	box(m, "HeadTop", 3.2, 0.5, 3.0, -2.4, 9.4, -1.2, accent)
	hcyl(m, "Wheel", 2.0, 0.3, -2.4, 10.4, -1.2, P.Steel, true)
	hall(m, "WindingHouse", 2.8, -2.6, 5.0, 4.6, 3.6, P.Beige, P.RoofBrown)
	box(m, "Doors", 2.4, 2.2, 0.12, 2.8, 1.4, -0.28, P.Wood)
	part(m, "OrePile", Vector3.new(4.6, 2.4, 4.0), CFrame.new(2.0, 0.6, 3.2) * CFrame.Angles(0, math.rad(20), math.rad(8)), ore)
	box(m, "Cart", 1.6, 0.9, 1.0, -2.8, 0.75, 3.4, P.SteelDark)
	box(m, "Track", 0.25, 0.1, 6.0, -2.8, 0.35, 2.2, P.Charcoal)
end

-- OIL WELL (8 x 8): pumpjack + tank
local function oilWell(m, frame, accent)
	pad(m, 7.6, 7.6, K.Sand)
	box(m, "Base", 5.2, 0.5, 1.6, -0.6, 0.55, -1.2, P.SteelDark)
	box(m, "Samson", 0.4, 3.6, 1.2, -0.6, 2.6, -1.2, frame)
	part(m, "Beam", Vector3.new(5.6, 0.45, 0.45), CFrame.new(-0.6, 4.4, -1.2) * CFrame.Angles(0, 0, math.rad(8)), accent)
	box(m, "Head", 0.6, 1.6, 0.7, -3.4, 3.7, -1.2, accent)
	box(m, "Counterweight", 1.0, 1.0, 1.0, 1.8, 3.6, -1.2, P.Charcoal)
	box(m, "Rod", 0.15, 3.0, 0.15, -3.4, 1.6, -1.2, P.Steel)
	cyl(m, "Tank", 2.6, 2.6, 2.0, 0.3, 2.2, K.Orange:Lerp(frame, 0.4))
	box(m, "Pipe", 3.6, 0.2, 0.2, 0.2, 0.6, 1.0, P.Steel)
end

-- OIL REFINERY (16 x 12)
local function refinery(m, tank, accent)
	pad(m, 15.6, 11.6, K.Concrete)
	cyl(m, "Column", 1.6, 12.0, -5.2, 0.3, -3.2, P.Steel)
	cyl(m, "Column2", 1.3, 9.0, -3.0, 0.3, -3.6, P.Steel)
	box(m, "ColumnBand", 1.8, 0.3, 1.8, -5.2, 8.0, -3.2, accent)
	for i, x in ipairs({ 1.4, 5.0 }) do
		cyl(m, "Tank" .. i, 3.2, 2.8, x, 0.3, -2.6, tank)
		cyl(m, "TankTop" .. i, 3.3, 0.25, x, 3.1, -2.6, accent)
	end
	hall(m, "Control", 3.0, 3.2, 5.0, 3.6, 3.0, P.White, P.Charcoal)
	box(m, "ControlGlass", 4.0, 1.0, 0.12, 3.0, 2.0, 5.02, P.Glass)
	hcyl(m, "PipeRack", 0.4, 9.0, -1.2, 2.2, 0.6, P.SteelDark, true)
	hcyl(m, "PipeRack2", 0.4, 9.0, -1.2, 2.8, 0.6, accent, true)
	cyl(m, "Flare", 0.5, 10.0, -6.6, 0.3, 4.4, P.SteelDark)
	ball(m, "Flame", 0.9, -6.6, 10.6, 4.4, K.Orange)
end

-- STEEL FACTORY (16 x 12)
local function steelMill(m, wall, accent)
	pad(m, 15.6, 11.6, K.Concrete)
	hall(m, "Hall", -1.6, 0.4, 10.4, 9.0, 6.4, wall, P.SteelDark)
	box(m, "Band", 10.5, 0.6, 9.1, -1.6, 4.6, 0.4, accent)
	box(m, "Door", 3.6, 3.6, 0.12, -2.6, 2.1, 4.96, P.Steel)
	cyl(m, "Furnace", 3.0, 8.6, 5.4, 0.3, -2.4, K.Rust)
	cyl(m, "FurnaceTop", 2.0, 2.4, 5.4, 8.9, -2.4, P.Charcoal)
	for i, x in ipairs({ -5.0, -2.2 }) do
		cyl(m, "Stack" .. i, 1.1, 5.0, x, 6.9, -2.6, P.Brick)
	end
	part(m, "Slag", Vector3.new(2.6, 1.4, 2.2), CFrame.new(5.4, 0.6, 3.6) * CFrame.Angles(0, math.rad(25), 0), K.Coal)
end

-- WAREHOUSE (12 x 8)
local function warehouse(m, wall, roof)
	pad(m, 11.6, 7.6)
	box(m, "Hall", 10.6, 4.6, 6.4, 0, 2.6, -0.2, wall)
	hcyl(m, "Vault", 6.6, 10.8, 0, 4.9, -0.2, roof, true)
	for _, x in ipairs({ -2.8, 2.8 }) do
		box(m, "Door", 2.6, 2.8, 0.12, x, 1.7, 3.02, P.Steel)
	end
	box(m, "Crates", 1.2, 1.0, 1.2, 4.6, 0.8, 3.3, P.Wood)
	box(m, "Pallet", 1.6, 0.4, 1.0, -4.6, 0.5, 3.4, P.Wood)
end

-- RAILWAY STATION (12 x 8)
local function station(m, wall, roof)
	pad(m, 11.6, 7.6, K.Concrete)
	box(m, "Platform", 11.2, 0.8, 2.6, 0, 0.7, -2.4, P.Foundation)
	box(m, "Edge", 11.2, 0.1, 0.3, 0, 1.15, -3.55, K.Yellow)
	for _, x in ipairs({ -4.4, 0, 4.4 }) do
		box(m, "Post", 0.3, 3.0, 0.3, x, 2.6, -2.0, P.White)
	end
	box(m, "Canopy", 11.0, 0.3, 2.8, 0, 4.2, -2.4, roof)
	hall(m, "Hall", 0, 1.6, 7.6, 4.0, 4.2, wall, roof)
	box(m, "Clock", 1.2, 1.2, 0.15, 0, 3.6, 3.66, P.White)
	door(m, -2.0, 3.66, roof)
	box(m, "Windows", 2.6, 1.2, 0.12, 2.0, 2.2, 3.66, P.Glass)
end

-- MILITARY -----------------------------------------------------------------------------------
local function militaryFactory(m, wall, accent)
	pad(m, 15.6, 11.6, K.Concrete)
	hall(m, "Hall", -1.0, -0.6, 12.0, 9.0, 6.0, wall, K.OliveDark)
	for i = 0, 3 do
		part(m, "Saw", Vector3.new(3.0, 0.25, 3.6), CFrame.new(-5.5 + i * 3.0, 7.0, -0.6) * CFrame.Angles(math.rad(28), 0, 0), P.SteelDark)
	end
	box(m, "Band", 12.1, 0.6, 9.1, -1.0, 4.2, -0.6, accent)
	box(m, "Gate", 4.4, 4.0, 0.12, -1.0, 2.3, 3.96, P.Steel)
	cyl(m, "Stack", 1.2, 9.0, 6.4, 0.3, -3.6, P.Brick)
	box(m, "Crate", 1.6, 1.2, 1.6, 6.2, 0.9, 3.6, K.Olive)
end

local function vehicleFactory(m, wall, accent, tracked)
	local d = tracked and 15.6 or 11.6
	pad(m, 15.6, d, K.Concrete)
	hcyl(m, "Hangar", 8.0, 12.0, -1.2, 0.3, -1.0, wall, false)
	box(m, "Floor", 8.0, 0.4, 12.0, -1.2, 0.5, -1.0, K.Concrete)
	box(m, "Door", 5.0, 3.4, 0.12, -1.2, 2.0, 5.02, accent)
	hall(m, "Office", 5.4, -2.0, 3.8, 5.6, 3.4, P.White, K.OliveDark)
	-- a parked vehicle on the apron
	local vz = tracked and 6.4 or 4.2
	box(m, "Hull", 2.8, 0.9, 1.6, 4.6, 0.9, vz, K.Olive)
	box(m, "Turret", tracked and 1.4 or 1.0, 0.6, 1.1, 4.4, 1.65, vz, K.OliveDark)
	if tracked then
		box(m, "Barrel", 2.2, 0.25, 0.25, 3.1, 1.7, vz, K.OliveDark)
	end
end

local function barracks(m, wall, roof)
	pad(m, 11.6, 11.6, K.Sand)
	hall(m, "Block1", -1.6, -3.0, 8.4, 3.6, 3.2, wall, roof)
	hall(m, "Block2", -1.6, 1.4, 8.4, 3.6, 3.2, wall, roof)
	for _, z in ipairs({ -1.18, 3.22 }) do
		box(m, "Windows", 6.8, 0.9, 0.12, -1.6, 2.0, z, P.Glass)
	end
	box(m, "Yard", 3.0, 0.1, 10.6, 4.2, 0.36, 0, K.Asphalt)
	flagPole(m, 4.4, 4.6, 7.0, K.Red)
end

local function artillery(m, sand, gun)
	pad(m, 11.6, 11.6, K.Sand)
	for i = 0, 7 do
		local a = math.rad(i * 45)
		part(m, "Sandbag", Vector3.new(3.0, 1.2, 1.0), CFrame.new(math.cos(a) * 3.6, 0.9, math.sin(a) * 3.6) * CFrame.Angles(0, -a + RAD90, 0), sand)
	end
	box(m, "Mount", 2.0, 1.0, 2.0, 0, 0.8, 0, gun)
	box(m, "Shield", 1.8, 1.2, 0.3, 0, 1.8, 0.6, gun)
	part(m, "Barrel", Vector3.new(0.4, 0.4, 5.0), CFrame.new(0, 2.6, 2.4) * CFrame.Angles(math.rad(-20), 0, 0), gun)
	box(m, "Ammo", 1.4, 0.8, 1.0, -4.2, 0.7, -4.2, K.OliveDark)
end

local function airDefense(m, base, accent)
	pad(m, 7.6, 7.6, K.Sand)
	box(m, "Platform", 4.0, 0.8, 4.0, 0, 0.7, 0, base)
	box(m, "Turret", 2.2, 1.4, 2.2, 0, 1.8, 0, accent)
	for _, x in ipairs({ -0.5, 0.5 }) do
		part(m, "Gun", Vector3.new(0.25, 0.25, 3.6), CFrame.new(x, 3.2, 1.2) * CFrame.Angles(math.rad(-40), 0, 0), P.Charcoal)
	end
	box(m, "RadarPole", 0.25, 2.6, 0.25, -2.6, 1.6, -2.6, P.Steel)
	part(m, "Radar", Vector3.new(1.8, 1.0, 0.2), CFrame.new(-2.6, 3.2, -2.6) * CFrame.Angles(math.rad(-20), math.rad(45), 0), P.White)
end

local function samSite(m, base, accent)
	pad(m, 11.6, 11.6, K.Sand)
	for i, x in ipairs({ -3.0, 3.0 }) do
		box(m, "Launcher" .. i, 2.4, 0.9, 3.4, x, 0.75, 0.6, base)
		for j = -1, 1, 2 do
			part(m, "Missile", Vector3.new(0.5, 0.5, 4.2), CFrame.new(x + j * 0.45, 2.2, 0.4) * CFrame.Angles(math.rad(-35), 0, 0), P.White)
		end
	end
	box(m, "RadarTruck", 2.2, 1.4, 3.6, 0, 0.9, -3.8, K.OliveDark)
	part(m, "RadarPanel", Vector3.new(2.8, 2.0, 0.25), CFrame.new(0, 3.0, -3.8) * CFrame.Angles(math.rad(-15), 0, 0), accent)
end

local function missileFacility(m, wall, accent)
	pad(m, 15.6, 11.6, K.Concrete)
	for i, x in ipairs({ -5.0, -1.6 }) do
		cyl(m, "Silo" .. i, 2.6, 0.5, x, 0.3, -2.4, P.SteelDark)
		cyl(m, "Hatch" .. i, 2.0, 0.2, x, 0.8, -2.4, accent)
	end
	hall(m, "Command", 4.2, -1.2, 6.0, 6.4, 3.8, wall, K.OliveDark)
	box(m, "Bunker", 6.4, 0.6, 2.8, -3.2, 0.6, 3.2, K.Concrete)
	part(m, "Missile", Vector3.new(0.7, 0.7, 6.4), CFrame.new(4.0, 1.2, 4.2) * CFrame.Angles(0, RAD90, 0), P.White)
	box(m, "Nose", 0.7, 0.7, 0.9, 7.4, 1.2, 4.2, accent)
end

local function uavFacility(m, wall, accent)
	pad(m, 11.6, 11.6, K.Concrete)
	box(m, "Runway", 2.6, 0.12, 11.0, 4.2, 0.36, 0, K.Asphalt)
	box(m, "Stripe", 0.25, 0.14, 9.0, 4.2, 0.4, 0, P.White)
	hcyl(m, "Hangar", 5.0, 6.0, -2.4, 0.3, -1.6, wall, false)
	box(m, "Door", 3.6, 2.2, 0.12, -2.4, 1.4, 1.42, accent)
	box(m, "DroneBody", 0.5, 0.35, 2.0, 4.2, 0.8, 3.2, P.White)
	box(m, "DroneWing", 3.4, 0.12, 0.6, 4.2, 0.9, 3.0, P.White)
	box(m, "Antenna", 0.2, 4.0, 0.2, -5.0, 2.3, 4.8, P.Steel)
end

local function airBase(m, wall, accent)
	pad(m, 15.6, 15.6, K.Concrete)
	box(m, "Runway", 3.6, 0.12, 15.2, 5.4, 0.36, 0, K.Asphalt)
	box(m, "Centerline", 0.3, 0.14, 13.0, 5.4, 0.4, 0, P.White)
	hcyl(m, "Hangar", 7.0, 8.0, -3.0, 0.3, -2.4, wall, false)
	box(m, "Door", 5.0, 3.0, 0.12, -3.0, 1.8, 1.62, accent)
	hall(m, "Tower", -4.6, 5.2, 2.4, 2.4, 6.0, P.White, P.Charcoal)
	box(m, "TowerGlass", 2.6, 1.0, 2.6, -4.6, 5.8, 5.2, P.Glass)
	box(m, "Fuselage", 0.8, 0.6, 4.0, 5.4, 0.9, 4.6, K.Navy:Lerp(P.White, 0.4))
	box(m, "Wings", 4.2, 0.15, 1.2, 5.4, 1.0, 4.8, K.Navy:Lerp(P.White, 0.4))
end

local function militaryWarehouse(m, wall, accent)
	pad(m, 11.6, 7.6, K.Sand)
	hcyl(m, "Bunker", 6.0, 10.6, 0, 0.3, -0.4, wall, true)
	box(m, "Floor", 10.6, 0.4, 6.0, 0, 0.5, -0.4, K.Concrete)
	box(m, "Door", 3.0, 2.2, 0.12, 0, 1.4, 2.62, accent)
	box(m, "Crates", 1.6, 1.0, 1.0, 4.4, 0.8, 3.2, K.Olive)
	box(m, "Crates2", 1.0, 0.8, 1.0, -4.4, 0.7, 3.2, K.OliveDark)
end

-- RESEARCH ------------------------------------------------------------------------------------
local function researchCenter(m, wall, accent)
	pad(m, 11.6, 11.6)
	hall(m, "Main", -1.2, 0.4, 8.0, 7.6, 5.6, wall, P.Charcoal)
	box(m, "Glass", 6.8, 3.6, 0.12, -1.2, 3.0, 4.22, P.Glass)
	ball(m, "Dome", 3.6, 3.8, 3.2, -3.2, P.White)
	cyl(m, "DomeBase", 3.8, 2.6, 3.8, 0.3, -3.2, wall)
	box(m, "Slit", 0.5, 1.6, 3.0, 3.8, 4.0, -3.2, accent)
	door(m, -1.2, 4.24, accent)
end

local function lab(m, wall, accent)
	pad(m, 11.6, 7.6)
	hall(m, "Lab", -1.0, -0.2, 8.6, 5.6, 4.2, wall, P.Charcoal)
	box(m, "Glass", 7.0, 1.2, 0.12, -1.0, 2.4, 2.62, P.Glass)
	box(m, "Stripe", 8.7, 0.4, 5.7, -1.0, 3.8, -0.2, accent)
	box(m, "Mast", 0.25, 5.0, 0.25, 4.6, 2.8, -2.4, P.Steel)
	ball(m, "Beacon", 0.6, 4.6, 5.5, -2.4, accent)
	door(m, -3.6, 2.64, accent)
end

local function institute(m, wall, accent)
	pad(m, 11.6, 11.6)
	hall(m, "Wing", -2.6, -0.6, 5.6, 9.4, 7.0, wall, P.Charcoal)
	hall(m, "Annex", 2.8, 1.0, 5.0, 6.0, 4.4, wall:Lerp(P.White, 0.3), P.Charcoal)
	for f = 0, 1 do
		box(m, "Windows", 4.6, 1.0, 0.12, -2.6, 2.2 + f * 3.0, 4.22, P.Glass)
	end
	box(m, "AnnexGlass", 4.0, 1.2, 0.12, 2.8, 2.4, 4.02, P.Glass)
	box(m, "Gear", 1.6, 1.6, 0.3, -2.6, 6.2, 4.3, accent)
	door(m, 2.8, 4.04, accent)
end

local function radarLab(m, wall, accent)
	pad(m, 11.6, 7.6)
	hall(m, "Lab", -2.0, 0.2, 6.6, 5.6, 3.8, wall, P.Charcoal)
	box(m, "Glass", 5.2, 1.2, 0.12, -2.0, 2.2, 3.02, P.Glass)
	cyl(m, "Tower", 1.4, 5.0, 3.6, 0.3, -0.6, P.Steel)
	ball(m, "Radome", 3.0, 3.6, 6.6, -0.6, P.White)
	box(m, "Band", 3.1, 0.3, 3.1, 3.6, 6.0, -0.6, accent)
	door(m, -4.0, 3.04, accent)
end

local function vehicleResearch(m, wall, accent)
	pad(m, 15.6, 11.6, K.Concrete)
	hall(m, "Lab", -3.8, -1.6, 7.4, 7.4, 4.6, wall, P.Charcoal)
	box(m, "Glass", 6.0, 1.2, 0.12, -3.8, 2.6, 2.12, P.Glass)
	box(m, "TestTrack", 6.0, 0.12, 10.6, 4.4, 0.36, 0, K.Asphalt)
	box(m, "Ramp", 2.4, 1.0, 2.6, 4.4, 0.6, -2.4, K.Concrete)
	box(m, "Prototype", 1.6, 0.8, 2.6, 4.4, 0.85, 3.0, accent)
	door(m, -5.6, 2.14, accent)
end

local function aircraftResearch(m, wall, accent)
	pad(m, 15.6, 11.6, K.Concrete)
	hall(m, "Lab", -4.2, 1.6, 6.6, 7.0, 4.4, wall, P.Charcoal)
	hcyl(m, "WindTunnel", 3.0, 11.0, 1.4, 2.2, -3.4, P.Steel, true)
	hcyl(m, "Intake", 4.0, 1.0, 6.6, 2.2, -3.4, accent, true)
	box(m, "Glass", 5.4, 1.2, 0.12, -4.2, 2.6, 5.12, P.Glass)
	box(m, "Fuselage", 0.8, 0.6, 3.2, 4.4, 0.8, 2.6, P.White)
	box(m, "Wings", 3.6, 0.15, 1.0, 4.4, 0.9, 2.6, accent)
end

local Variants = BuildingModels.Variants

local function register(prefix: string, builder, palettes)
	for i, letter in ipairs({ "A", "B", "C", "D" }) do
		local p = palettes[i]
		Variants[prefix .. "_" .. letter] = function(m)
			builder(m, p[1], p[2], p[3])
		end
	end
end

-- Explicit variant list (tests/test_config.py checks every BuildingConfig variant is defined).
Variants.Apartment_A = function(m) apartment(m, P.Cream, P.LightBlue) end
Variants.Apartment_B = function(m) apartment(m, P.Sky, P.White) end
Variants.Apartment_C = function(m) apartment(m, P.Beige, P.Terracotta) end
Variants.Apartment_D = function(m) apartment(m, P.White, P.Mint) end
Variants.GasStation_A = function(m) gasStation(m, P.White, K.Red) end
Variants.GasStation_B = function(m) gasStation(m, P.White, K.Green) end
Variants.GasStation_C = function(m) gasStation(m, P.LightBlue, P.White) end
Variants.GasStation_D = function(m) gasStation(m, P.White, K.Orange) end
Variants.CoalMine_A = function(m) mine(m, K.Coal, P.Warning) end
Variants.CoalMine_B = function(m) mine(m, K.Coal, P.Steel) end
Variants.CoalMine_C = function(m) mine(m, K.Coal, K.Red) end
Variants.CoalMine_D = function(m) mine(m, K.Coal, P.LightBlue) end
Variants.IronMine_A = function(m) mine(m, K.Rust, P.Warning) end
Variants.IronMine_B = function(m) mine(m, K.Rust, P.Steel) end
Variants.IronMine_C = function(m) mine(m, K.Rust, K.Navy) end
Variants.IronMine_D = function(m) mine(m, K.Rust, P.Mint) end
Variants.OilWell_A = function(m) oilWell(m, P.SteelDark, P.Warning) end
Variants.OilWell_B = function(m) oilWell(m, P.Steel, K.Red) end
Variants.OilWell_C = function(m) oilWell(m, P.SteelDark, P.LightBlue) end
Variants.OilWell_D = function(m) oilWell(m, P.Charcoal, K.Orange) end
Variants.OilRefinery_A = function(m) refinery(m, P.White, K.Red) end
Variants.OilRefinery_B = function(m) refinery(m, P.Steel, P.Warning) end
Variants.OilRefinery_C = function(m) refinery(m, P.White, P.LightBlue) end
Variants.OilRefinery_D = function(m) refinery(m, P.Sky, K.Orange) end
Variants.SteelMill_A = function(m) steelMill(m, P.Steel, K.Orange) end
Variants.SteelMill_B = function(m) steelMill(m, P.Beige, P.Terracotta) end
Variants.SteelMill_C = function(m) steelMill(m, P.White, K.Navy) end
Variants.SteelMill_D = function(m) steelMill(m, P.Sand, P.Slate) end
Variants.Warehouse_A = function(m) warehouse(m, P.Steel, P.SteelDark) end
Variants.Warehouse_B = function(m) warehouse(m, P.Beige, P.RoofBrown) end
Variants.Warehouse_C = function(m) warehouse(m, P.White, P.LightBlue) end
Variants.Warehouse_D = function(m) warehouse(m, P.Sky, P.Slate) end
Variants.RailwayStation_A = function(m) station(m, P.Cream, P.Terracotta) end
Variants.RailwayStation_B = function(m) station(m, P.White, P.Slate) end
Variants.RailwayStation_C = function(m) station(m, P.Sky, P.Charcoal) end
Variants.RailwayStation_D = function(m) station(m, P.Beige, K.Green) end
Variants.MilitaryFactory_A = function(m) militaryFactory(m, K.Khaki, K.Olive) end
Variants.MilitaryFactory_B = function(m) militaryFactory(m, P.Steel, K.Camo) end
Variants.MilitaryFactory_C = function(m) militaryFactory(m, K.Sand, K.Red) end
Variants.MilitaryFactory_D = function(m) militaryFactory(m, P.Beige, K.OliveDark) end
Variants.VehicleFactory_A = function(m) vehicleFactory(m, K.Khaki, K.Olive, false) end
Variants.VehicleFactory_B = function(m) vehicleFactory(m, P.Steel, K.Camo, false) end
Variants.VehicleFactory_C = function(m) vehicleFactory(m, K.Sand, K.Red, false) end
Variants.VehicleFactory_D = function(m) vehicleFactory(m, P.Beige, K.OliveDark, false) end
Variants.TankFactory_A = function(m) vehicleFactory(m, K.Olive, K.Khaki, true) end
Variants.TankFactory_B = function(m) vehicleFactory(m, K.Camo, P.Steel, true) end
Variants.TankFactory_C = function(m) vehicleFactory(m, K.OliveDark, K.Red, true) end
Variants.TankFactory_D = function(m) vehicleFactory(m, P.SteelDark, K.Sand, true) end
Variants.Barracks_A = function(m) barracks(m, K.Khaki, K.OliveDark) end
Variants.Barracks_B = function(m) barracks(m, P.Beige, K.Camo) end
Variants.Barracks_C = function(m) barracks(m, K.Sand, P.Slate) end
Variants.Barracks_D = function(m) barracks(m, P.White, K.Olive) end
Variants.ArtilleryBase_A = function(m) artillery(m, K.Khaki, K.Olive) end
Variants.ArtilleryBase_B = function(m) artillery(m, K.Sand, K.Camo) end
Variants.ArtilleryBase_C = function(m) artillery(m, P.Beige, K.OliveDark) end
Variants.ArtilleryBase_D = function(m) artillery(m, K.Khaki, P.SteelDark) end
Variants.AirDefense_A = function(m) airDefense(m, K.Olive, K.OliveDark) end
Variants.AirDefense_B = function(m) airDefense(m, K.Camo, K.Olive) end
Variants.AirDefense_C = function(m) airDefense(m, P.SteelDark, K.Khaki) end
Variants.AirDefense_D = function(m) airDefense(m, K.Khaki, K.Camo) end
Variants.SAMSite_A = function(m) samSite(m, K.Olive, P.White) end
Variants.SAMSite_B = function(m) samSite(m, K.Camo, K.Khaki) end
Variants.SAMSite_C = function(m) samSite(m, P.SteelDark, P.White) end
Variants.SAMSite_D = function(m) samSite(m, K.OliveDark, K.Sand) end
Variants.MissileFacility_A = function(m) missileFacility(m, K.Khaki, K.Red) end
Variants.MissileFacility_B = function(m) missileFacility(m, P.Steel, P.Warning) end
Variants.MissileFacility_C = function(m) missileFacility(m, K.Sand, K.Navy) end
Variants.MissileFacility_D = function(m) missileFacility(m, P.Beige, K.Red) end
Variants.UAVFacility_A = function(m) uavFacility(m, K.Olive, P.White) end
Variants.UAVFacility_B = function(m) uavFacility(m, P.Steel, K.Camo) end
Variants.UAVFacility_C = function(m) uavFacility(m, K.Khaki, K.Navy) end
Variants.UAVFacility_D = function(m) uavFacility(m, K.Camo, K.Sand) end
Variants.AirBase_A = function(m) airBase(m, P.Steel, K.Olive) end
Variants.AirBase_B = function(m) airBase(m, K.Khaki, K.Camo) end
Variants.AirBase_C = function(m) airBase(m, P.White, K.Navy) end
Variants.AirBase_D = function(m) airBase(m, K.Olive, K.Sand) end
Variants.MilitaryWarehouse_A = function(m) militaryWarehouse(m, K.Olive, K.Khaki) end
Variants.MilitaryWarehouse_B = function(m) militaryWarehouse(m, K.Camo, P.Steel) end
Variants.MilitaryWarehouse_C = function(m) militaryWarehouse(m, K.Khaki, K.OliveDark) end
Variants.MilitaryWarehouse_D = function(m) militaryWarehouse(m, P.SteelDark, K.Sand) end
Variants.ResearchCenter_A = function(m) researchCenter(m, P.White, K.Purple) end
Variants.ResearchCenter_B = function(m) researchCenter(m, P.Sky, K.Navy) end
Variants.ResearchCenter_C = function(m) researchCenter(m, P.Cream, K.Teal) end
Variants.ResearchCenter_D = function(m) researchCenter(m, P.White, P.LightBlue) end
Variants.TechnologyLab_A = function(m) lab(m, P.White, K.Purple) end
Variants.TechnologyLab_B = function(m) lab(m, P.Sky, K.Teal) end
Variants.TechnologyLab_C = function(m) lab(m, P.Cream, K.Navy) end
Variants.TechnologyLab_D = function(m) lab(m, P.White, P.Coral) end
Variants.EngineeringInstitute_A = function(m) institute(m, P.Beige, K.Purple) end
Variants.EngineeringInstitute_B = function(m) institute(m, P.White, K.Orange) end
Variants.EngineeringInstitute_C = function(m) institute(m, P.Sky, K.Navy) end
Variants.EngineeringInstitute_D = function(m) institute(m, P.Cream, K.Teal) end
Variants.MilitaryResearch_A = function(m) institute(m, K.Khaki, K.Purple) end
Variants.MilitaryResearch_B = function(m) institute(m, K.Sand, K.Red) end
Variants.MilitaryResearch_C = function(m) institute(m, P.Steel, K.Olive) end
Variants.MilitaryResearch_D = function(m) institute(m, P.Beige, K.Navy) end
Variants.ElectronicsLab_A = function(m) radarLab(m, P.White, K.Purple) end
Variants.ElectronicsLab_B = function(m) radarLab(m, P.Sky, K.Teal) end
Variants.ElectronicsLab_C = function(m) radarLab(m, P.Cream, K.Navy) end
Variants.ElectronicsLab_D = function(m) radarLab(m, P.Steel, K.Orange) end
Variants.VehicleResearch_A = function(m) vehicleResearch(m, P.White, K.Purple) end
Variants.VehicleResearch_B = function(m) vehicleResearch(m, P.Sky, K.Olive) end
Variants.VehicleResearch_C = function(m) vehicleResearch(m, P.Cream, K.Red) end
Variants.VehicleResearch_D = function(m) vehicleResearch(m, P.Steel, K.Teal) end
Variants.AircraftResearch_A = function(m) aircraftResearch(m, P.White, K.Purple) end
Variants.AircraftResearch_B = function(m) aircraftResearch(m, P.Sky, K.Navy) end
Variants.AircraftResearch_C = function(m) aircraftResearch(m, P.Cream, K.Teal) end
Variants.AircraftResearch_D = function(m) aircraftResearch(m, P.Steel, K.Orange) end

ExtraModels.register = register
ExtraModels.Loaded = true

return ExtraModels
