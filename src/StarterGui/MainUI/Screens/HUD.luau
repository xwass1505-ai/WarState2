-- HUD: TOP bar = FLAG · COUNTRY NAME · POPULATION · TREASURY (net per cycle) · TECHNOLOGY BRANCH ·
-- CYCLE · NEXT CYCLE timer (+ water warning / saving-off chips). BOTTOM CENTER compact BUILD button
-- (hammer icon, hover + press animation) with a Build / Demolish popover. RIGHT side STATS button.
-- The countdown reads the server cycle time (ReplicatedStorage attribute) twice a second; no
-- per-frame loops. Respects the Roblox Core UI safe inset (ScreenGui.ScreenInsets).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local UIKit = require(script.Parent.Parent:WaitForChild("Components"):WaitForChild("UIKit"))
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Countries = require(Shared:WaitForChild("Modules"):WaitForChild("Countries"))
local Constants = require(Shared:WaitForChild("Constants"):WaitForChild("Constants"))

local C = UIKit.Theme.Colors
local T = UIKit.Theme

local HUD = {}
HUD.__index = HUD

-- Pill button with an icon + caption, hover lift and press squish.
local function iconButton(props)
	local button = UIKit.new("TextButton", {
		Name = props.Name,
		AutoButtonColor = false,
		BackgroundColor3 = C.Background,
		BorderSizePixel = 0,
		AnchorPoint = props.AnchorPoint,
		Position = props.Position,
		Size = props.Size,
		Text = "",
		Visible = false,
		Parent = props.Parent,
	})
	UIKit.corner(button, 999)
	local stroke = UIKit.stroke(button, C.Stroke, 1.5)
	UIKit.gradient(button, C.Background, C.AccentSoft, 90)
	local scale = Instance.new("UIScale")
	scale.Name = "PressScale"
	scale.Parent = button
	local icon = props.Icon(button)
	local caption = UIKit.label({
		Name = "Caption",
		Text = props.Text,
		Font = T.Fonts.Bold,
		TextSize = T.TextSize.Small,
		TextColor3 = C.AccentDark,
		Parent = button,
	})
	if props.Vertical then
		icon.AnchorPoint = Vector2.new(0.5, 0)
		icon.Position = UDim2.new(0.5, 0, 0, 9)
		caption.TextXAlignment = Enum.TextXAlignment.Center
		caption.TextSize = T.TextSize.Tiny
		caption.Position = UDim2.new(0, 0, 1, -22)
		caption.Size = UDim2.new(1, 0, 0, 14)
	else
		icon.AnchorPoint = Vector2.new(0, 0.5)
		icon.Position = UDim2.new(0, 14, 0.5, 0)
		caption.Position = UDim2.fromOffset(40, 0)
		caption.Size = UDim2.new(1, -48, 1, 0)
	end
	local hovering = false
	button.MouseEnter:Connect(function()
		hovering = true
		UIKit.tween(scale, T.Motion.Fast, { Scale = 1.05 })
		UIKit.tween(stroke, T.Motion.Fast, { Color = C.Accent })
		UIKit.tween(icon, T.Motion.Normal, { Rotation = props.HoverRotation or 0 }, Enum.EasingStyle.Back)
	end)
	button.MouseLeave:Connect(function()
		hovering = false
		UIKit.tween(scale, T.Motion.Fast, { Scale = 1 })
		UIKit.tween(stroke, T.Motion.Fast, { Color = C.Stroke })
		UIKit.tween(icon, T.Motion.Normal, { Rotation = 0 })
	end)
	button.MouseButton1Down:Connect(function()
		UIKit.tween(scale, 0.08, { Scale = 0.92 })
	end)
	button.MouseButton1Up:Connect(function()
		UIKit.tween(scale, T.Motion.Normal, { Scale = hovering and 1.05 or 1 }, Enum.EasingStyle.Back)
	end)
	button.Activated:Connect(function()
		scale.Scale = 0.92
		UIKit.tween(scale, T.Motion.Normal, { Scale = 1 }, Enum.EasingStyle.Back)
		props.OnClick()
	end)
	return button
end

local function divider(parent, order)
	return UIKit.new("Frame", {
		BackgroundColor3 = C.Stroke,
		BorderSizePixel = 0,
		Size = UDim2.fromOffset(1, 24),
		LayoutOrder = order,
		Parent = parent,
	})
end

-- Caption over value (e.g. TREASURY / $1,250).
local function stat(parent, caption: string, order: number, minWidth: number?)
	local holder = UIKit.new("Frame", {
		Name = caption,
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(minWidth or 60, 34),
		AutomaticSize = Enum.AutomaticSize.X,
		LayoutOrder = order,
		Parent = parent,
	})
	UIKit.label({
		Name = "Caption",
		Text = caption,
		Font = T.Fonts.Bold,
		TextSize = 10,
		TextColor3 = C.TextMuted,
		AutomaticSize = Enum.AutomaticSize.X,
		Size = UDim2.fromOffset(0, 12),
		Parent = holder,
	})
	local value = UIKit.label({
		Name = "Value",
		Text = "-",
		Font = T.Fonts.Bold,
		TextSize = T.TextSize.Small,
		TextColor3 = C.Text,
		Position = UDim2.fromOffset(0, 13),
		AutomaticSize = Enum.AutomaticSize.X,
		Size = UDim2.fromOffset(0, 20),
		Parent = holder,
	})
	return value
end

local function money(n: number): string
	local negative = n < 0
	local s = tostring(math.floor(math.abs(n)))
	local formatted = string.reverse((string.gsub(string.reverse(s), "(%d%d%d)", "%1,")))
	if string.sub(formatted, 1, 1) == "," then
		formatted = string.sub(formatted, 2)
	end
	return (negative and "-$" or "$") .. formatted
end
HUD.money = money

function HUD.new(root: ScreenGui, callbacks)
	local self = setmetatable({}, HUD)
	self.callbacks = callbacks

	self.top = UIKit.new("CanvasGroup", {
		Name = "TopBar",
		BackgroundColor3 = C.Background,
		BorderSizePixel = 0,
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 8),
		Size = UDim2.fromOffset(0, 46),
		AutomaticSize = Enum.AutomaticSize.X,
		Visible = false,
		Parent = root,
	})
	UIKit.corner(self.top, 14)
	UIKit.stroke(self.top, C.Stroke)
	UIKit.gradient(self.top, C.Background, C.Surface, 90)
	UIKit.padding(self.top, 5, 10)
	UIKit.list(self.top, Enum.FillDirection.Horizontal, 10, Enum.HorizontalAlignment.Center, Enum.VerticalAlignment.Center)

	self.menuButton = UIKit.button({
		Name = "Menu",
		Text = "Menu",
		TextSize = T.TextSize.Small,
		Size = UDim2.fromOffset(56, 30),
		Radius = 999,
		LayoutOrder = 1,
		Parent = self.top,
		OnClick = function()
			self:toggleMenu()
		end,
	})
	self.flagHolder = UIKit.new("Frame", {
		Name = "FlagHolder",
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(32, 23),
		LayoutOrder = 2,
		Parent = self.top,
	})
	self.nameLabel = stat(self.top, "COUNTRY", 3, 70)
	divider(self.top, 4)
	self.popLabel = stat(self.top, "POPULATION", 5, 70)
	self.treasuryLabel = stat(self.top, "TREASURY", 6, 80)
	self.netLabel = UIKit.label({
		Name = "Net",
		Text = "",
		Font = T.Fonts.Bold,
		TextSize = T.TextSize.Tiny,
		TextColor3 = C.Success,
		AutomaticSize = Enum.AutomaticSize.X,
		Size = UDim2.fromOffset(0, 34),
		LayoutOrder = 7,
		Parent = self.top,
	})
	divider(self.top, 8)
	self.techLabel = stat(self.top, "TECHNOLOGY", 9, 70)
	self.cycleLabel = stat(self.top, "CYCLE", 10, 40)
	self.timerLabel = stat(self.top, "NEXT CYCLE", 11, 64)
	self.timerTrack = UIKit.new("Frame", {
		Name = "TimerTrack",
		BackgroundColor3 = C.Gray,
		BorderSizePixel = 0,
		Size = UDim2.fromOffset(46, 4),
		LayoutOrder = 12,
		Parent = self.top,
	})
	UIKit.corner(self.timerTrack, 999)
	self.timerFill = UIKit.new("Frame", {
		BackgroundColor3 = C.Accent,
		BorderSizePixel = 0,
		Size = UDim2.fromScale(0, 1),
		Parent = self.timerTrack,
	})
	UIKit.corner(self.timerFill, 999)
	self.stageChip = UIKit.label({
		Name = "ShortageChip",
		Text = "",
		Font = T.Fonts.Bold,
		TextColor3 = C.Warning,
		TextSize = T.TextSize.Tiny,
		AutomaticSize = Enum.AutomaticSize.X,
		Size = UDim2.fromOffset(0, 30),
		LayoutOrder = 13,
		Visible = false,
		Parent = self.top,
	})
	self.saveChip = UIKit.label({
		Text = "Saving off",
		TextColor3 = C.Danger,
		TextSize = T.TextSize.Tiny,
		AutomaticSize = Enum.AutomaticSize.X,
		Size = UDim2.fromOffset(0, 30),
		LayoutOrder = 14,
		Visible = false,
		Parent = self.top,
	})

	-- Menu popover
	self.menu = UIKit.panel({
		Name = "MenuPopover",
		Canvas = true,
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 62),
		Size = UDim2.fromOffset(190, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		Visible = false,
		Parent = root,
	})
	UIKit.padding(self.menu, 8)
	UIKit.list(self.menu, Enum.FillDirection.Vertical, 6)
	UIKit.button({
		Text = "Save now",
		TextSize = T.TextSize.Small,
		Size = UDim2.new(1, 0, 0, 32),
		LayoutOrder = 1,
		Parent = self.menu,
		OnClick = function()
			self:closeMenu()
			self.callbacks.onSave()
		end,
	})
	UIKit.button({
		Text = "Main menu",
		TextSize = T.TextSize.Small,
		Size = UDim2.new(1, 0, 0, 32),
		LayoutOrder = 2,
		Parent = self.menu,
		OnClick = function()
			self:closeMenu()
			self.callbacks.onChangeSlot()
		end,
	})

	-- BOTTOM CENTER build button
	self.hammer = iconButton({
		Name = "BuildButton",
		Text = "BUILD",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -16),
		Size = UDim2.fromOffset(112, 42),
		HoverRotation = -18,
		Parent = root,
		Icon = function(parent)
			return UIKit.hammerIcon(parent, 20, C.AccentDark)
		end,
		OnClick = function()
			self:toggleTools()
		end,
	})

	-- Tool popover: BUILD / DEMOLISH
	self.tools = UIKit.panel({
		Name = "BuildTools",
		Canvas = true,
		Radius = 999,
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -66),
		Size = UDim2.fromOffset(0, 44),
		AutomaticSize = Enum.AutomaticSize.X,
		Visible = false,
		Parent = root,
	})
	UIKit.padding(self.tools, 5)
	UIKit.list(self.tools, Enum.FillDirection.Horizontal, 6, nil, Enum.VerticalAlignment.Center)
	UIKit.button({
		Text = "Build",
		Style = "primary",
		TextSize = T.TextSize.Small,
		Size = UDim2.fromOffset(92, 34),
		Radius = 999,
		LayoutOrder = 1,
		Parent = self.tools,
		OnClick = function()
			self:closeTools()
			self.callbacks.onOpenBuild()
		end,
	})
	UIKit.button({
		Text = "Demolish",
		Style = "danger",
		TextSize = T.TextSize.Small,
		Size = UDim2.fromOffset(92, 34),
		Radius = 999,
		LayoutOrder = 2,
		Parent = self.tools,
		OnClick = function()
			self:closeTools()
			self.callbacks.onDemolish()
		end,
	})

	-- RIGHT side STATS button
	self.statsButton = iconButton({
		Name = "StatsButton",
		Text = "STATS",
		Vertical = true,
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -12, 0.5, 0),
		Size = UDim2.fromOffset(54, 58),
		HoverRotation = 0,
		Parent = root,
		Icon = function(parent)
			return UIKit.statsIcon(parent, 20, C.AccentDark)
		end,
		OnClick = function()
			self.callbacks.onStats()
		end,
	})

	-- Cycle countdown (2x per second while the HUD is visible).
	task.spawn(function()
		while true do
			task.wait(0.5)
			if self.top.Visible then
				self:updateTimer()
			end
		end
	end)
	return self
end

function HUD:updateTimer()
	local nextAt = ReplicatedStorage:GetAttribute(Constants.EconomyAttributes.NextCycleAt)
	local length = ReplicatedStorage:GetAttribute(Constants.EconomyAttributes.CycleSeconds) or 30
	if type(nextAt) ~= "number" then
		self.timerLabel.Text = "--"
		return
	end
	local left = math.max(0, nextAt - Workspace:GetServerTimeNow())
	self.timerLabel.Text = string.format("0:%02d", math.clamp(math.ceil(left), 0, 59))
	local fraction = 1 - math.clamp(left / math.max(1, length), 0, 1)
	UIKit.tween(self.timerFill, 0.45, { Size = UDim2.fromScale(fraction, 1) }, Enum.EasingStyle.Linear)
end

function HUD:toggleTools()
	if self.tools.Visible then
		self:closeTools()
	else
		self:closeMenu()
		UIKit.open(self.tools, 8)
	end
end

function HUD:closeTools()
	UIKit.close(self.tools, 8)
end

function HUD:toggleMenu()
	if self.menu.Visible then
		self:closeMenu()
	else
		UIKit.open(self.menu, -6)
	end
end

function HUD:closeMenu()
	UIKit.close(self.menu, -6)
end

function HUD:setHammerVisible(visible: boolean)
	self.hammer.Visible = visible
	if not visible then
		self.tools.Visible = false
	end
end

function HUD:show()
	UIKit.open(self.top, -10)
	self.hammer.Visible = true
	self.statsButton.Visible = true
	local base = UDim2.new(0.5, 0, 1, -16)
	self.hammer.Position = base + UDim2.fromOffset(0, 60)
	UIKit.tween(self.hammer, T.Motion.Slow, { Position = base }, Enum.EasingStyle.Back)
	local statsBase = UDim2.new(1, -12, 0.5, 0)
	self.statsButton.Position = statsBase + UDim2.fromOffset(80, 0)
	UIKit.tween(self.statsButton, T.Motion.Slow, { Position = statsBase }, Enum.EasingStyle.Back)
	self:updateTimer()
end

function HUD:hide()
	self.top.Visible = false
	self.menu.Visible = false
	self.tools.Visible = false
	self.hammer.Visible = false
	self.statsButton.Visible = false
end

local STAGE_TEXT = {
	WARNING = "Water warning",
	PROLONGED_SHORTAGE = "Water shortage",
	POPULATION_PROBLEMS = "Water crisis",
	GRADUAL_POPULATION_DECREASE = "Population falling",
}

local function flash(label: TextLabel, color: Color3)
	label.TextColor3 = color
	UIKit.tween(label, T.Motion.Slow, { TextColor3 = C.Text })
end

function HUD:update(state)
	if not state or not state.Active then
		return
	end
	if self.lastFlag ~= state.FlagId then
		self.lastFlag = state.FlagId
		for _, child in ipairs(self.flagHolder:GetChildren()) do
			child:Destroy()
		end
		local flag = UIKit.flag(self.flagHolder, Countries.get(state.FlagId or ""), 22)
		flag.Size = UDim2.fromScale(1, 1)
	end
	self.nameLabel.Text = state.Name or ""
	local population = state.Population or 0
	self.popLabel.Text = string.format("%d / %d", population, state.HousingCapacity or 0)
	if self.lastPopulation ~= nil and population ~= self.lastPopulation then
		flash(self.popLabel, population > self.lastPopulation and C.Success or C.Danger)
	end
	self.lastPopulation = population
	local treasury = state.Treasury or 0
	self.treasuryLabel.Text = money(treasury)
	if self.lastTreasury ~= nil and treasury ~= self.lastTreasury then
		flash(self.treasuryLabel, treasury > self.lastTreasury and C.Success or C.Danger)
	end
	if treasury < 0 then
		self.treasuryLabel.TextColor3 = C.Danger
	end
	self.lastTreasury = treasury
	local economy = state.Economy or {}
	local net = economy.Net or 0
	self.netLabel.Text = string.format("%s%s / cycle", net >= 0 and "+" or "-", money(math.abs(net)))
	self.netLabel.TextColor3 = net >= 0 and C.Success or C.Danger
	self.techLabel.Text = state.TechnologyName or state.TechnologyBranch or "-"
	self.cycleLabel.Text = "#" .. tostring((economy.Cycle or 0) + 1)
	self.saveChip.Visible = state.Persistent == false
	local stage = state.Water and state.Water.Stage
	local text = stage and STAGE_TEXT[stage]
	self.stageChip.Visible = text ~= nil
	self.stageChip.Text = text or ""
	self.stageChip.TextColor3 = (stage == "WARNING") and C.Warning or C.Danger
end

return HUD
