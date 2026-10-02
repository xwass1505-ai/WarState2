-- PlacementController: client-side build preview only (server is the authority).
-- Modes:
--   Road      : hold LMB / finger, drag, release. A transparent preview follows the cursor while
--               held (grid snap + dominant direction + per-tile validation), release sends ONE
--               PlaceRoadLine request. A single click never builds a road by itself.
--   Building  : snapped preview + radius ring for water/power sources, click / Place to request.
--   Demolish  : hover highlights your own building or road tile, click to request removal.
-- Validation uses the SAME PlacementRules as the server. Work happens only while a mode is
-- active and only when the hovered grid cell changes (no heavy per-frame recomputation).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = Shared:WaitForChild("Config")
local Modules = Shared:WaitForChild("Modules")
local BuildingConfig = require(Config:WaitForChild("BuildingConfig"))
local PlacementConfig = require(Config:WaitForChild("PlacementConfig"))
local Constants = require(Shared:WaitForChild("Constants"):WaitForChild("Constants"))
local GridMath = require(Modules:WaitForChild("GridMath"))
local PlacementRules = require(Modules:WaitForChild("PlacementRules"))
local BuildingModels = require(Modules:WaitForChild("BuildingModels"))
local RoadModels = require(Modules:WaitForChild("RoadModels"))
local Plots = require(Modules:WaitForChild("Plots"))

local player = Players.LocalPlayer
local Remotes = ReplicatedStorage:WaitForChild("Remotes")

local PlacementController = {}

local defsById = {}
for _, def in ipairs(BuildingConfig.Buildings) do
	defsById[def.Id] = def
end

local function rgb(t)
	return Color3.fromRGB(t[1], t[2], t[3])
end
local VALID_COLOR = rgb(PlacementConfig.PreviewValidColor)
local INVALID_COLOR = rgb(PlacementConfig.PreviewInvalidColor)
local EXISTING_COLOR = Color3.fromRGB(200, 214, 230)

local active = nil
local connections = {}
local listeners = {}
local aimScreen = nil -- Vector2 (touch aim point) or nil for mouse
local requesting = false
local ctxCache = nil
local ctxDirty = true

local previewFolder = nil
local tilePool = {}

local function emit()
	local status = PlacementController.getStatus()
	for _, fn in ipairs(listeners) do
		task.spawn(fn, status)
	end
end

function PlacementController.onStatus(fn)
	table.insert(listeners, fn)
end

function PlacementController.getStatus()
	if not active then
		return { Active = false }
	end
	local variantName = nil
	if active.kind == "Building" then
		variantName = defsById[active.id].Variants[active.variantIndex]
	end
	return {
		Active = true,
		Kind = active.kind,
		Id = active.id,
		Variant = variantName,
		Valid = active.valid,
		Reason = active.reason,
		Rotation = active.rotation,
		Tiles = active.tiles,
		Dragging = active.dragging == true,
		TargetLabel = active.targetLabel,
		HasAim = active.info ~= nil,
	}
end

local function plotBounds()
	local index = player:GetAttribute(Constants.Attributes.PlotIndex)
	if not index then
		return nil
	end
	return Plots.getBounds(index)
end

local function plotFolder(kind: string, bounds)
	local root = Workspace:FindFirstChild(kind)
	return root and root:FindFirstChild("Plot_" .. bounds.index) or nil
end

local function rectOf(model)
	local minX = model:GetAttribute("RectMinX")
	if minX == nil then
		return nil
	end
	return {
		minX = minX,
		maxX = model:GetAttribute("RectMaxX"),
		minZ = model:GetAttribute("RectMinZ"),
		maxZ = model:GetAttribute("RectMaxZ"),
	}
end

-- Validation context from replicated world models (server-created, attribute-tagged).
-- Cached and rebuilt only when the player's plot folders change.
local function buildContext(bounds)
	if ctxCache and not ctxDirty and ctxCache.plot.index == bounds.index then
		return ctxCache
	end
	local ctx = { plot = bounds, buildingRects = {}, roadCells = {}, buildingModels = {}, roadModels = {} }
	local bFolder = plotFolder("Buildings", bounds)
	local rFolder = plotFolder("Roads", bounds)
	if bFolder then
		for _, model in ipairs(bFolder:GetChildren()) do
			local rect = rectOf(model)
			if rect then
				table.insert(ctx.buildingRects, rect)
				table.insert(ctx.buildingModels, { model = model, rect = rect })
			end
		end
	end
	if rFolder then
		for _, model in ipairs(rFolder:GetChildren()) do
			local rect = rectOf(model)
			local ix, iz = model:GetAttribute("Ix"), model:GetAttribute("Iz")
			if rect and ix ~= nil and iz ~= nil then
				local key = GridMath.cellKey(ix, iz)
				ctx.roadCells[key] = rect
				ctx.roadModels[key] = model
			end
		end
	end
	ctxCache = ctx
	ctxDirty = false
	return ctx
end

local function watchFolders(bounds)
	for _, kind in ipairs({ "Buildings", "Roads" }) do
		local folder = plotFolder(kind, bounds)
		if folder then
			table.insert(connections, folder.ChildAdded:Connect(function()
				ctxDirty = true
				if active then
					active.lastKey = nil
				end
			end))
			table.insert(connections, folder.ChildRemoved:Connect(function()
				ctxDirty = true
				if active then
					active.lastKey = nil
				end
			end))
		end
	end
end

-- Preview helpers ----------------------------------------------------------------------------
local function ensurePreviewFolder()
	if previewFolder and previewFolder.Parent then
		return previewFolder
	end
	previewFolder = Instance.new("Folder")
	previewFolder.Name = "WarStatePreview"
	previewFolder.Parent = Workspace.CurrentCamera
	return previewFolder
end

local function hideTiles(from: number)
	for i = from, #tilePool do
		tilePool[i].Parent = nil
	end
end

local function showTiles(tiles, surfaceY: number)
	local folder = ensurePreviewFolder()
	for i, tile in ipairs(tiles) do
		local p = tilePool[i]
		if not p then
			p = RoadModels.previewTile()
			tilePool[i] = p
		end
		p.CFrame = CFrame.new(tile.centerX, surfaceY + 0.07, tile.centerZ)
		if tile.existing then
			p.Color = EXISTING_COLOR
			p.Transparency = 0.7
		else
			p.Color = tile.valid and VALID_COLOR or INVALID_COLOR
			p.Transparency = PlacementConfig.PreviewTransparency
		end
		p.Parent = folder
	end
	hideTiles(#tiles + 1)
end

local function setModelTransparency(model)
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") then
			local base = d:GetAttribute("BaseTransparency") or 0
			d.Transparency = math.max(base, PlacementConfig.PreviewTransparency)
		end
	end
end

local function destroyPreview()
	if active then
		for _, key in ipairs({ "model", "highlight", "ring", "targetHighlight" }) do
			if active[key] then
				active[key]:Destroy()
				active[key] = nil
			end
		end
	end
	hideTiles(1)
end

local function createBuildingPreview()
	destroyPreview()
	local def = defsById[active.id]
	local model = BuildingModels.build(def, def.Variants[active.variantIndex])
	model.Name = "PlacementPreview"
	local highlight = Instance.new("Highlight")
	highlight.Name = "InvalidHighlight"
	highlight.FillColor = INVALID_COLOR
	highlight.OutlineColor = INVALID_COLOR
	highlight.FillTransparency = 0.55
	highlight.OutlineTransparency = 0.4
	highlight.DepthMode = Enum.HighlightDepthMode.Occluded
	highlight.Enabled = false
	highlight.Adornee = model
	highlight.Parent = model
	active.model = model
	active.highlight = highlight
	setModelTransparency(model)
	model.Parent = ensurePreviewFolder()
	-- Coverage ring for water / power sources.
	local radius = (def.Water and def.Water.Radius) or (def.Power and def.Power.Radius)
	if radius and radius > 0 then
		local ring = Instance.new("Part")
		ring.Name = "RadiusRing"
		ring.Shape = Enum.PartType.Cylinder
		ring.Size = Vector3.new(0.05, radius * 2, radius * 2)
		ring.Anchored = true
		ring.CanCollide = false
		ring.CanQuery = false
		ring.CanTouch = false
		ring.CastShadow = false
		ring.Material = Enum.Material.SmoothPlastic
		ring.Color = (def.Water and (def.Water.Radius or 0) > 0) and Color3.fromRGB(120, 186, 245) or Color3.fromRGB(245, 200, 90)
		ring.Transparency = 0.82
		ring.Parent = ensurePreviewFolder()
		active.ring = ring
	end
end

local function raycastGround(screenPoint: Vector2)
	local camera = Workspace.CurrentCamera
	local map = Workspace:FindFirstChild("Map")
	if not camera or not map then
		return nil
	end
	local ray = camera:ViewportPointToRay(screenPoint.X, screenPoint.Y)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = { map }
	local result = Workspace:Raycast(ray.Origin, ray.Direction * PlacementConfig.MaxPlacementRayDistance, params)
	return result and result.Position or nil
end

local function currentScreenPoint(): Vector2?
	if aimScreen then
		return aimScreen
	end
	if UserInputService.MouseEnabled then
		return UserInputService:GetMouseLocation()
	end
	return nil
end

-- Mode updates -------------------------------------------------------------------------------
local function updateRoad(bounds, hit)
	local ctx = buildContext(bounds)
	local startX, startZ = hit.X, hit.Z
	if active.dragging and active.dragStart then
		startX, startZ = active.dragStart.X, active.dragStart.Z
	end
	local cells = PlacementRules.roadLine(startX, startZ, hit.X, hit.Z, bounds)
	local ok, reason, tiles, newCount = PlacementRules.validateRoadLine(cells, ctx)
	active.valid = ok
	active.reason = ok and nil or reason
	active.tiles = newCount
	active.lineEnd = { X = hit.X, Z = hit.Z }
	showTiles(tiles, bounds.surfaceY)
	if not active.dragging and ok then
		active.reason = nil
	end
end

local function updateBuilding(bounds, hit)
	local ctx = buildContext(bounds)
	local ok, reason, info = PlacementRules.validateBuilding(defsById[active.id], hit.X, hit.Z, active.rotation, ctx)
	active.info = info
	active.valid = ok
	active.reason = reason
	if info and active.model then
		active.model.Parent = ensurePreviewFolder()
		active.model:PivotTo(
			CFrame.new(info.centerX, bounds.surfaceY + 0.02, info.centerZ)
				* CFrame.Angles(0, GridMath.yawForRotation(active.rotation), 0)
		)
		if active.highlight then
			active.highlight.Enabled = not ok
		end
		if active.ring then
			active.ring.CFrame = CFrame.new(info.centerX, bounds.surfaceY + 0.06, info.centerZ) * CFrame.Angles(0, 0, math.rad(90))
		end
	end
end

local function labelFor(model): string
	local kind = model:GetAttribute(Constants.Attributes.Kind)
	if kind == "Road" then
		return "Road tile"
	end
	local def = defsById[model:GetAttribute(Constants.Attributes.TypeId) or ""]
	return def and def.DisplayName or "Building"
end

local function updateDemolish(bounds, hit)
	local ctx = buildContext(bounds)
	local target = nil
	for _, entry in ipairs(ctx.buildingModels) do
		local r = entry.rect
		if hit.X >= r.minX and hit.X <= r.maxX and hit.Z >= r.minZ and hit.Z <= r.maxZ then
			target = entry.model
			break
		end
	end
	if not target then
		local ix, iz = PlacementRules.snapRoad(hit.X, hit.Z, bounds)
		target = ctx.roadModels[GridMath.cellKey(ix, iz)]
	end
	if target ~= active.target then
		if active.targetHighlight then
			active.targetHighlight:Destroy()
			active.targetHighlight = nil
		end
		active.target = target
		if target then
			local h = Instance.new("Highlight")
			h.FillColor = INVALID_COLOR
			h.OutlineColor = INVALID_COLOR
			h.FillTransparency = 0.5
			h.OutlineTransparency = 0.2
			h.DepthMode = Enum.HighlightDepthMode.Occluded
			h.Adornee = target
			h.Parent = ensurePreviewFolder()
			active.targetHighlight = h
		end
	end
	active.valid = target ~= nil
	active.reason = target and nil or "Point at your building or road"
	active.targetLabel = target and ("Remove " .. labelFor(target)) or nil
end

local function update()
	if not active then
		return
	end
	local bounds = plotBounds()
	local screenPoint = currentScreenPoint()
	local hit = (bounds and screenPoint) and raycastGround(screenPoint) or nil
	if not hit then
		if active.valid ~= false or active.reason ~= "Aim at your plot" then
			active.valid = false
			active.reason = "Aim at your plot"
			active.info = nil
			if active.model then
				active.model.Parent = nil
			end
			if not active.dragging then
				hideTiles(1)
			end
			emit()
		end
		return
	end
	-- Only recompute when the snapped cell (or rotation / drag state) changes.
	local grid = active.kind == "Road" and PlacementConfig.RoadTileSize or PlacementConfig.GridSize
	local key = string.format(
		"%d:%d:%d:%s",
		math.floor((hit.X - bounds.minX) / grid),
		math.floor((hit.Z - bounds.minZ) / grid),
		active.rotation,
		tostring(active.dragging)
	)
	if key == active.lastKey and not ctxDirty then
		return
	end
	active.lastKey = key
	active.lastHit = hit
	if active.kind == "Road" then
		updateRoad(bounds, hit)
	elseif active.kind == "Building" then
		updateBuilding(bounds, hit)
	else
		updateDemolish(bounds, hit)
	end
	emit()
end

local function notifyResult(success: boolean, message: string)
	for _, fn in ipairs(PlacementController.resultListeners) do
		task.spawn(fn, success, message)
	end
end

local function invoke(remoteName: string, request, callback)
	requesting = true
	task.spawn(function()
		local remote = Remotes:WaitForChild(remoteName)
		local ok, result = pcall(function()
			return remote:InvokeServer(request)
		end)
		requesting = false
		local success = ok and type(result) == "table" and result.ok == true
		local message = success and "OK" or ((ok and type(result) == "table" and result.error) or "Request failed")
		notifyResult(success, message)
		if callback then
			callback(success, message, result)
		end
		ctxDirty = true
		if active then
			active.lastKey = nil
		end
	end)
end

-- Road drag release: build the previewed line.
local function finishRoadDrag()
	if not active or active.kind ~= "Road" or not active.dragging then
		return
	end
	active.dragging = false
	local start, finish = active.dragStart, active.lineEnd
	active.dragStart = nil
	active.lastKey = nil
	if not start or not finish or not active.valid or requesting then
		hideTiles(1)
		if active.reason then
			notifyResult(false, active.reason)
		end
		emit()
		return
	end
	invoke(Constants.Remotes.PlaceRoadLine, { StartX = start.X, StartZ = start.Z, EndX = finish.X, EndZ = finish.Z })
	hideTiles(1)
	emit()
end

function PlacementController.isActive(): boolean
	return active ~= nil
end

function PlacementController.start(kind: string, id: string?)
	PlacementController.cancel()
	local bounds = plotBounds()
	active = {
		kind = kind,
		id = id,
		variantIndex = 1,
		rotation = 0,
		valid = false,
		reason = "Aim at your plot",
	}
	aimScreen = nil
	ctxDirty = true
	if kind == "Building" then
		createBuildingPreview()
	end
	if bounds then
		watchFolders(bounds)
	end
	table.insert(connections, RunService.RenderStepped:Connect(update))
	table.insert(connections, UserInputService.InputBegan:Connect(function(input, processed)
		if processed or not active then
			return
		end
		if input.KeyCode == Enum.KeyCode.R then
			PlacementController.rotate()
		elseif input.KeyCode == Enum.KeyCode.Q or input.KeyCode == Enum.KeyCode.Escape then
			PlacementController.cancel()
		elseif input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			if input.UserInputType == Enum.UserInputType.Touch then
				aimScreen = Vector2.new(input.Position.X, input.Position.Y)
			else
				aimScreen = nil
			end
			if active.kind == "Road" then
				local b = plotBounds()
				local point = currentScreenPoint()
				local hit = (b and point) and raycastGround(point) or nil
				if hit then
					active.dragging = true
					active.dragStart = { X = hit.X, Z = hit.Z }
					active.lastKey = nil
				end
			elseif input.UserInputType == Enum.UserInputType.MouseButton1 then
				PlacementController.confirm()
			end
		end
	end))
	table.insert(connections, UserInputService.InputChanged:Connect(function(input)
		if active and active.dragging and input.UserInputType == Enum.UserInputType.Touch then
			aimScreen = Vector2.new(input.Position.X, input.Position.Y)
		end
	end))
	table.insert(connections, UserInputService.InputEnded:Connect(function(input)
		if not active then
			return
		end
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			if active.kind == "Road" and active.dragging then
				update()
				finishRoadDrag()
			end
		end
	end))
	table.insert(connections, UserInputService.TouchTapInWorld:Connect(function(position, processed)
		if not processed and active and active.kind ~= "Road" then
			aimScreen = position
		end
	end))
	emit()
end

function PlacementController.rotate()
	if not active or active.kind ~= "Building" then
		return
	end
	active.rotation = (active.rotation + 1) % 4
	active.lastKey = nil
	emit()
end

function PlacementController.cycleVariant()
	if not active or active.kind ~= "Building" then
		return
	end
	local def = defsById[active.id]
	active.variantIndex = (active.variantIndex % #def.Variants) + 1
	createBuildingPreview()
	active.lastKey = nil
	emit()
end

function PlacementController.cancel()
	for _, c in ipairs(connections) do
		c:Disconnect()
	end
	connections = {}
	destroyPreview()
	local wasActive = active ~= nil
	active = nil
	aimScreen = nil
	if wasActive then
		emit()
	end
end

-- Building / demolish confirm (roads are built on drag release). The server is the authority.
function PlacementController.confirm(callback)
	if not active or requesting then
		return
	end
	if active.kind == "Road" then
		return
	end
	if not active.valid then
		notifyResult(false, active.reason or "Invalid placement")
		emit()
		return
	end
	if active.kind == "Demolish" then
		local target = active.target
		if not target then
			return
		end
		local kind = target:GetAttribute(Constants.Attributes.Kind)
		invoke(Constants.Remotes.Demolish, { Kind = kind, Id = target.Name }, callback)
		return
	end
	if not active.info then
		return
	end
	local def = defsById[active.id]
	invoke(Constants.Remotes.PlaceBuilding, {
		Type = active.id,
		Variant = def.Variants[active.variantIndex],
		X = active.info.centerX,
		Z = active.info.centerZ,
		Rotation = active.rotation,
	}, callback)
end

PlacementController.resultListeners = {}
function PlacementController.onResult(fn)
	table.insert(PlacementController.resultListeners, fn)
end

return PlacementController
