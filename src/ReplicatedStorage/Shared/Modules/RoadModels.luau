-- RoadModels: procedural Straight Road tile, small, clean and gray, with low curbs on both sides.
-- Openings ("NS", "NES", ...) come from RoadGraph: curbs are only built on CLOSED sides,
-- so a branch to the left/right removes the curb at the joint (no curb through a junction).
-- Inner corner posts are added where two open sides meet, so junction curbs look finished.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local RoadConfig = require(Shared:WaitForChild("Config"):WaitForChild("RoadConfig"))

local RoadModels = {}

local function rgb(t)
	return Color3.fromRGB(t[1], t[2], t[3])
end

local ASPHALT = rgb(RoadConfig.Colors.Asphalt)
local CURB = rgb(RoadConfig.Colors.Curb)
local MARKING = rgb(RoadConfig.Colors.Marking)

local function part(model, name, size, position, color, material)
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.CFrame = CFrame.new(position)
	p.Color = color
	p.Material = material or Enum.Material.SmoothPlastic
	p.Anchored = true
	p.CanCollide = false
	p.CanTouch = false
	p.CanQuery = false
	p.CastShadow = false
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p:SetAttribute("BaseTransparency", 0)
	p.Parent = model
	return p
end

local OFFSET = {
	N = { 0, -1 },
	E = { 1, 0 },
	S = { 0, 1 },
	W = { -1, 0 },
}

local function openSet(openings: string?)
	local set = {}
	local s = openings or "NS"
	for _, dir in ipairs({ "N", "E", "S", "W" }) do
		if string.find(s, dir, 1, true) then
			set[dir] = true
		end
	end
	return set
end

-- Builds a tile at the origin in WORLD orientation (no rotation needed, openings are world sides).
-- typeId is kept for API compatibility; only "Straight" exists.
function RoadModels.build(typeId: string?, openings: string?)
	local size = RoadConfig.TileSize
	local half = size / 2
	local curbW = RoadConfig.CurbWidth
	local curbH = RoadConfig.CurbHeight
	local asphaltH = RoadConfig.AsphaltHeight
	local open = openSet(openings)

	local model = Instance.new("Model")
	model.Name = "Road_" .. tostring(typeId or "Straight")

	local root = part(model, "Root", Vector3.new(size, 0.05, size), Vector3.new(0, 0.025, 0), ASPHALT)
	root.Transparency = 1
	root:SetAttribute("BaseTransparency", 1)
	model.PrimaryPart = root

	part(model, "Asphalt", Vector3.new(size, asphaltH, size), Vector3.new(0, asphaltH / 2, 0), ASPHALT, Enum.Material.Concrete)

	-- Curbs along closed sides.
	for dir, o in pairs(OFFSET) do
		if not open[dir] then
			local pos = Vector3.new(o[1] * (half - curbW / 2), asphaltH + curbH / 2, o[2] * (half - curbW / 2))
			local curbSize
			if o[1] == 0 then
				curbSize = Vector3.new(size, curbH, curbW)
			else
				curbSize = Vector3.new(curbW, curbH, size)
			end
			part(model, "Curb" .. dir, curbSize, pos, CURB)
		end
	end
	-- Inner corner posts where two OPEN sides meet (junction corners).
	local corners = { { "N", "E" }, { "E", "S" }, { "S", "W" }, { "W", "N" } }
	for _, pair in ipairs(corners) do
		if open[pair[1]] and open[pair[2]] then
			local a, b = OFFSET[pair[1]], OFFSET[pair[2]]
			local cx = (a[1] + b[1]) * (half - curbW / 2)
			local cz = (a[2] + b[2]) * (half - curbW / 2)
			part(model, "Post" .. pair[1] .. pair[2], Vector3.new(curbW, curbH, curbW), Vector3.new(cx, asphaltH + curbH / 2, cz), CURB)
		end
	end
	-- Center dash along each open axis (subtle, flat).
	local nsOpen = open.N or open.S
	local ewOpen = open.E or open.W
	local count = 0
	for _ in pairs(open) do
		count += 1
	end
	if count <= 2 then
		if nsOpen and not ewOpen then
			part(model, "Dash", Vector3.new(0.08, 0.02, size * 0.45), Vector3.new(0, asphaltH + 0.01, 0), MARKING)
		elseif ewOpen and not nsOpen then
			part(model, "Dash", Vector3.new(size * 0.45, 0.02, 0.08), Vector3.new(0, asphaltH + 0.01, 0), MARKING)
		end
	end
	return model
end

-- Lightweight flat tile used for the drag preview (one part, no curbs).
function RoadModels.previewTile(): Part
	local size = RoadConfig.TileSize
	local p = Instance.new("Part")
	p.Name = "RoadPreviewTile"
	p.Size = Vector3.new(size - 0.08, 0.12, size - 0.08)
	p.Anchored = true
	p.CanCollide = false
	p.CanTouch = false
	p.CanQuery = false
	p.CastShadow = false
	p.Material = Enum.Material.SmoothPlastic
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	return p
end

return RoadModels
