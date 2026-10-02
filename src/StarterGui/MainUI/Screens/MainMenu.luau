-- MainMenu: the title screen. Big "WAR STATE" typography on a white -> light blue backdrop,
-- soft floating shapes (looping tweens, no per-frame code), and the 3 save slot cards.
-- The backdrop stays visible behind COUNTRY SETUP and PLOT SELECTION, then fades into the game.

local UIKit = require(script.Parent.Parent:WaitForChild("Components"):WaitForChild("UIKit"))
local SlotScreen = require(script.Parent:WaitForChild("SlotScreen"))

local TweenService = game:GetService("TweenService")

local C = UIKit.Theme.Colors
local T = UIKit.Theme

local MainMenu = {}
MainMenu.__index = MainMenu

local DESIGN_W, DESIGN_H = 420, 470

local function floatTween(inst: Instance, props, duration: number)
	local info = TweenInfo.new(duration, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true)
	local tween = TweenService:Create(inst, info, props)
	tween:Play()
	return tween
end

function MainMenu.new(backdropGui: ScreenGui, root: ScreenGui, callbacks)
	local self = setmetatable({}, MainMenu)
	self.callbacks = callbacks
	self.loops = {}

	-- Backdrop (full screen, below the UI) ---------------------------------------------------
	self.backdrop = UIKit.new("CanvasGroup", {
		Name = "MenuBackdrop",
		BackgroundColor3 = C.Background,
		BorderSizePixel = 0,
		Size = UDim2.fromScale(1, 1),
		Visible = false,
		Parent = backdropGui,
	})
	UIKit.gradient(self.backdrop, C.SkyTop, C.SkyBottom, 90)
	local shapes = {
		{ 0.12, 0.2, 260, 0.82 },
		{ 0.88, 0.28, 320, 0.86 },
		{ 0.78, 0.86, 380, 0.88 },
		{ 0.2, 0.84, 220, 0.84 },
	}
	self.shapes = {}
	for i, s in ipairs(shapes) do
		local circle = UIKit.new("Frame", {
			Name = "Shape" .. i,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(s[1], s[2]),
			Size = UDim2.fromOffset(s[3], s[3]),
			BackgroundColor3 = C.Accent,
			BackgroundTransparency = s[4],
			BorderSizePixel = 0,
			Parent = self.backdrop,
		})
		UIKit.corner(circle, 999)
		table.insert(self.shapes, { frame = circle, base = circle.Position, index = i })
	end
	-- A thin horizon line with small "islands" for a hint of the map.
	local horizon = UIKit.new("Frame", {
		Name = "Horizon",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, 0),
		Size = UDim2.new(1, 0, 0.16, 0),
		BackgroundColor3 = C.Accent,
		BackgroundTransparency = 0.9,
		BorderSizePixel = 0,
		Parent = self.backdrop,
	})
	for i, x in ipairs({ 0.18, 0.34, 0.5, 0.66, 0.82 }) do
		local w = (i == 3) and 150 or 60
		local island = UIKit.new("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(x, 0.5),
			Size = UDim2.fromOffset(w, 14),
			BackgroundColor3 = C.Background,
			BackgroundTransparency = 0.35,
			BorderSizePixel = 0,
			Parent = horizon,
		})
		UIKit.corner(island, 999)
	end

	-- Foreground content ---------------------------------------------------------------------
	self.content = UIKit.new("CanvasGroup", {
		Name = "MainMenu",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(DESIGN_W, DESIGN_H),
		Visible = false,
		Parent = root,
	})
	UIKit.autoScale(self.content, DESIGN_W, DESIGN_H)

	self.title = UIKit.label({
		Name = "Title",
		Text = "WAR STATE",
		Font = T.Fonts.Title,
		TextSize = T.TextSize.Hero,
		TextColor3 = C.Text,
		TextXAlignment = Enum.TextXAlignment.Center,
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 0),
		Size = UDim2.new(1, 0, 0, 70),
		Parent = self.content,
	})
	self.titleBase = self.title.Position
	self.underline = UIKit.new("Frame", {
		Name = "Underline",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 74),
		Size = UDim2.fromOffset(0, 4),
		BackgroundColor3 = C.Accent,
		BorderSizePixel = 0,
		Parent = self.content,
	})
	UIKit.corner(self.underline, 999)
	self.subtitle = UIKit.label({
		Text = "Build a nation from zero",
		Font = T.Fonts.Medium,
		TextSize = T.TextSize.Body,
		TextColor3 = C.TextMuted,
		TextXAlignment = Enum.TextXAlignment.Center,
		Position = UDim2.fromOffset(0, 86),
		Size = UDim2.new(1, 0, 0, 20),
		Parent = self.content,
	})

	self.slotHolder = UIKit.new("Frame", {
		Name = "SlotHolder",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 128),
		Size = UDim2.fromOffset(380, 300),
		Parent = self.content,
	})
	self.slots = SlotScreen.new(self.slotHolder, callbacks)

	self.footer = UIKit.label({
		Text = "Phase 2 · City builder foundation",
		TextSize = T.TextSize.Tiny,
		TextColor3 = C.TextMuted,
		TextXAlignment = Enum.TextXAlignment.Center,
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.fromScale(0, 1),
		Size = UDim2.new(1, 0, 0, 16),
		Parent = self.content,
	})
	return self
end

function MainMenu:startLoops()
	self:stopLoops()
	table.insert(self.loops, floatTween(self.title, { Position = self.titleBase + UDim2.fromOffset(0, -3) }, 2.8))
	for _, s in ipairs(self.shapes) do
		local dy = (s.index % 2 == 0) and 14 or -14
		table.insert(self.loops, floatTween(s.frame, { Position = s.base + UDim2.fromOffset(dy * 0.6, dy) }, 6 + s.index))
	end
end

function MainMenu:stopLoops()
	for _, tween in ipairs(self.loops) do
		tween:Cancel()
	end
	self.loops = {}
	self.title.Position = self.titleBase
	for _, s in ipairs(self.shapes) do
		s.frame.Position = s.base
	end
end

function MainMenu:showBackdrop()
	if not self.backdrop.Visible then
		UIKit.fade(self.backdrop, true, T.Motion.Slow)
	end
end

-- Full title screen with slots.
function MainMenu:show(profile)
	self:showBackdrop()
	self.slots:render(profile)
	self.content.Visible = true
	self.content.GroupTransparency = 1
	UIKit.tween(self.content, T.Motion.Slow, { GroupTransparency = 0 })
	-- Title reveal: slide + fade, underline grows, slots slide in slightly later.
	self.title.TextTransparency = 1
	self.title.Position = self.titleBase + UDim2.fromOffset(0, 14)
	UIKit.tween(self.title, T.Motion.Hero, { TextTransparency = 0, Position = self.titleBase })
	self.underline.Size = UDim2.fromOffset(0, 4)
	task.delay(0.25, function()
		UIKit.tween(self.underline, T.Motion.Hero, { Size = UDim2.fromOffset(120, 4) })
	end)
	self.subtitle.TextTransparency = 1
	task.delay(0.35, function()
		UIKit.tween(self.subtitle, T.Motion.Slow, { TextTransparency = 0 })
	end)
	self.slots:reveal(0.45)
	task.delay(T.Motion.Hero, function()
		if self.content.Visible then
			self:startLoops()
		end
	end)
end

-- Keep only the backdrop (used behind COUNTRY SETUP / PLOT SELECTION).
function MainMenu:hideContent()
	self:stopLoops()
	UIKit.fade(self.content, false, T.Motion.Fast)
end

-- Fade everything out (entering the game).
function MainMenu:hide()
	self:stopLoops()
	UIKit.fade(self.content, false, T.Motion.Fast)
	UIKit.fade(self.backdrop, false, T.Motion.Slow)
end

return MainMenu
