-- ConstructionBars: client-side construction progress bars above buildings.
--   Building...      12s
--   ████████░░
-- Reads server attributes on building models (State, BuildTime, CompleteAt = server time) and
-- animates the fill with ONE linear tween per state change (smooth, no per-frame work).
-- A single light loop (5x per second) updates the seconds text. On completion the bar fills,
-- shows "Done" and fades out smoothly.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = Shared:WaitForChild("Config")
local Theme = require(Config:WaitForChild("ThemeConfig"))
local GameConfig = require(Config:WaitForChild("GameConfig"))

local ConstructionBars = {}

local C = Theme.Colors
local player = Players.LocalPlayer
local bars = {} -- [Model] = entry
local started = false

local function tween(inst, duration, props, style)
	local t = TweenService:Create(inst, TweenInfo.new(duration, style or Enum.EasingStyle.Quint, Enum.EasingDirection.Out), props)
	t:Play()
	return t
end

local function remaining(model): number
	local completeAt = model:GetAttribute("CompleteAt") or 0
	return math.max(0, completeAt - Workspace:GetServerTimeNow())
end

local function createBar(model: Model)
	local root = model.PrimaryPart or model:FindFirstChild("Root")
	if not root then
		return nil
	end
	local gui = Instance.new("BillboardGui")
	gui.Name = "ConstructionBar_" .. model.Name
	gui.Size = UDim2.fromOffset(104, 34)
	gui.StudsOffsetWorldSpace = Vector3.new(0, (model:GetAttribute("VisualHeight") or 2) + 0.9, 0)
	gui.MaxDistance = GameConfig.Construction.ProgressBarMaxDistance
	gui.AlwaysOnTop = true
	gui.LightInfluence = 0
	gui.ResetOnSpawn = false
	gui.Adornee = root

	local card = Instance.new("CanvasGroup")
	card.Name = "Card"
	card.BackgroundTransparency = 1
	card.Size = UDim2.fromScale(1, 1)
	card.GroupTransparency = 1
	card.Parent = gui

	local status = Instance.new("TextLabel")
	status.Name = "Status"
	status.BackgroundTransparency = 1
	status.Size = UDim2.new(0.7, 0, 0, 14)
	status.Font = Theme.Fonts.Bold
	status.TextSize = 11
	status.TextColor3 = C.Text
	status.TextStrokeColor3 = C.Background
	status.TextStrokeTransparency = 0.4
	status.TextXAlignment = Enum.TextXAlignment.Left
	status.Text = "Building..."
	status.Parent = card

	local timeLabel = Instance.new("TextLabel")
	timeLabel.Name = "Time"
	timeLabel.BackgroundTransparency = 1
	timeLabel.AnchorPoint = Vector2.new(1, 0)
	timeLabel.Position = UDim2.fromScale(1, 0)
	timeLabel.Size = UDim2.new(0.3, 0, 0, 14)
	timeLabel.Font = Theme.Fonts.Bold
	timeLabel.TextSize = 11
	timeLabel.TextColor3 = C.AccentDark
	timeLabel.TextStrokeColor3 = C.Background
	timeLabel.TextStrokeTransparency = 0.4
	timeLabel.TextXAlignment = Enum.TextXAlignment.Right
	timeLabel.Text = ""
	timeLabel.Parent = card

	local track = Instance.new("Frame")
	track.Name = "Track"
	track.Position = UDim2.fromOffset(0, 18)
	track.Size = UDim2.new(1, 0, 0, 10)
	track.BackgroundColor3 = C.Background
	track.BorderSizePixel = 0
	track.Parent = card
	local trackCorner = Instance.new("UICorner")
	trackCorner.CornerRadius = UDim.new(1, 0)
	trackCorner.Parent = track
	local stroke = Instance.new("UIStroke")
	stroke.Color = C.Stroke
	stroke.Thickness = 1
	stroke.Parent = track

	local fill = Instance.new("Frame")
	fill.Name = "Fill"
	fill.Size = UDim2.fromScale(0, 1)
	fill.BackgroundColor3 = C.Accent
	fill.BorderSizePixel = 0
	fill.Parent = track
	local fillCorner = Instance.new("UICorner")
	fillCorner.CornerRadius = UDim.new(1, 0)
	fillCorner.Parent = fill
	local gradient = Instance.new("UIGradient")
	gradient.Color = ColorSequence.new(C.Accent, C.AccentDark)
	gradient.Parent = fill

	gui.Parent = player:WaitForChild("PlayerGui")
	tween(card, 0.25, { GroupTransparency = 0 })
	return { gui = gui, card = card, fill = fill, status = status, time = timeLabel, model = model, connections = {} }
end

local function removeBar(model: Model, animated: boolean)
	local entry = bars[model]
	if not entry then
		return
	end
	bars[model] = nil
	for _, c in ipairs(entry.connections) do
		c:Disconnect()
	end
	if entry.fillTween then
		entry.fillTween:Cancel()
	end
	if animated and entry.gui.Parent then
		entry.status.Text = "Done"
		entry.time.Text = ""
		tween(entry.fill, 0.2, { Size = UDim2.fromScale(1, 1) })
		task.delay(0.35, function()
			tween(entry.card, 0.45, { GroupTransparency = 1 }).Completed:Connect(function()
				entry.gui:Destroy()
			end)
		end)
	else
		entry.gui:Destroy()
	end
end

local function refresh(entry)
	local model = entry.model
	local state = model:GetAttribute("State")
	if state == "COMPLETED" then
		removeBar(model, true)
		return
	end
	local total = model:GetAttribute("BuildTime") or 1
	local left = remaining(model)
	if entry.fillTween then
		entry.fillTween:Cancel()
		entry.fillTween = nil
	end
	if state == "PLANNED" then
		entry.status.Text = "Preparing..."
		entry.fill.Size = UDim2.fromScale(0, 1)
	else
		entry.status.Text = "Building..."
		local fraction = math.clamp(1 - left / total, 0, 1)
		entry.fill.Size = UDim2.fromScale(fraction, 1)
		if left > 0 then
			entry.fillTween = tween(entry.fill, left, { Size = UDim2.fromScale(1, 1) }, Enum.EasingStyle.Linear)
		end
	end
end

local function track(model: Instance)
	if not model:IsA("Model") or model:GetAttribute("Kind") ~= "Building" or bars[model] then
		return
	end
	local state = model:GetAttribute("State")
	if state == nil or state == "COMPLETED" then
		-- Listen in case construction data arrives later.
		local c
		c = model:GetAttributeChangedSignal("State"):Connect(function()
			if model:GetAttribute("State") ~= "COMPLETED" and not bars[model] then
				c:Disconnect()
				track(model)
			end
		end)
		return
	end
	local entry = createBar(model)
	if not entry then
		return
	end
	bars[model] = entry
	table.insert(entry.connections, model:GetAttributeChangedSignal("State"):Connect(function()
		refresh(entry)
	end))
	table.insert(entry.connections, model:GetAttributeChangedSignal("CompleteAt"):Connect(function()
		refresh(entry)
	end))
	table.insert(entry.connections, model.AncestryChanged:Connect(function()
		if not model:IsDescendantOf(Workspace) then
			removeBar(model, false)
		end
	end))
	refresh(entry)
end

function ConstructionBars.start()
	if started then
		return
	end
	started = true
	local buildings = Workspace:WaitForChild("Buildings")
	buildings.DescendantAdded:Connect(function(inst)
		if inst:IsA("Model") and inst.Parent and inst.Parent:IsA("Folder") then
			task.defer(track, inst)
		end
	end)
	for _, inst in ipairs(buildings:GetDescendants()) do
		track(inst)
	end
	task.spawn(function()
		while true do
			task.wait(0.2)
			for model, entry in pairs(bars) do
				if model:GetAttribute("State") == "UNDER_CONSTRUCTION" or model:GetAttribute("State") == "PLANNED" then
					local left = math.ceil(remaining(model))
					entry.time.Text = left > 0 and (tostring(left) .. "s") or ""
				end
			end
		end
	end)
end

return ConstructionBars
