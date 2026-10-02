-- UIKit: tiny UI toolkit (instance factory, theme, motion helpers).
-- Style: white / light blue / light gray, compact, clean. Built-in Gotham fonts only.
-- Motion: fade + slide + scale on open/close, hover lift, press squish. TweenService only
-- (no RenderStepped loops).

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Theme = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"):WaitForChild("ThemeConfig"))

local UIKit = {}
UIKit.Theme = Theme
local C = Theme.Colors

function UIKit.new(className: string, props, children)
	local inst = Instance.new(className)
	local parent = nil
	for key, value in pairs(props or {}) do
		if key == "Parent" then
			parent = value
		else
			inst[key] = value
		end
	end
	for _, child in ipairs(children or {}) do
		child.Parent = inst
	end
	if parent then
		inst.Parent = parent
	end
	return inst
end

function UIKit.tween(inst: Instance, duration: number, props, style, direction)
	local info = TweenInfo.new(duration, style or Theme.Motion.Style, direction or Theme.Motion.Direction)
	local tween = TweenService:Create(inst, info, props)
	tween:Play()
	return tween
end

function UIKit.corner(parent: Instance, radius: number?)
	local c = Instance.new("UICorner")
	if radius == nil or radius >= 999 then
		c.CornerRadius = UDim.new(1, 0)
	else
		c.CornerRadius = UDim.new(0, radius)
	end
	c.Parent = parent
	return c
end

function UIKit.stroke(parent: Instance, color: Color3?, thickness: number?, transparency: number?)
	local s = Instance.new("UIStroke")
	s.Color = color or C.Stroke
	s.Thickness = thickness or 1
	s.Transparency = transparency or 0
	s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	s.Parent = parent
	return s
end

function UIKit.padding(parent: Instance, all: number, horizontal: number?)
	local p = Instance.new("UIPadding")
	local h = horizontal or all
	p.PaddingTop = UDim.new(0, all)
	p.PaddingBottom = UDim.new(0, all)
	p.PaddingLeft = UDim.new(0, h)
	p.PaddingRight = UDim.new(0, h)
	p.Parent = parent
	return p
end

function UIKit.list(parent: Instance, direction, spacing: number, hAlign, vAlign)
	local l = Instance.new("UIListLayout")
	l.FillDirection = direction or Enum.FillDirection.Vertical
	l.Padding = UDim.new(0, spacing or 6)
	l.SortOrder = Enum.SortOrder.LayoutOrder
	l.HorizontalAlignment = hAlign or Enum.HorizontalAlignment.Left
	l.VerticalAlignment = vAlign or Enum.VerticalAlignment.Top
	l.Parent = parent
	return l
end

function UIKit.gradient(parent: Instance, top: Color3, bottom: Color3, rotation: number?)
	local g = Instance.new("UIGradient")
	g.Color = ColorSequence.new(top, bottom)
	g.Rotation = rotation or 90
	g.Parent = parent
	return g
end

function UIKit.label(props)
	local defaults = {
		BackgroundTransparency = 1,
		Font = Theme.Fonts.Medium,
		TextSize = Theme.TextSize.Body,
		TextColor3 = C.Text,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Center,
		Size = UDim2.new(1, 0, 0, 20),
		Text = "",
		TextTruncate = Enum.TextTruncate.AtEnd,
	}
	for k, v in pairs(props or {}) do
		defaults[k] = v
	end
	return UIKit.new("TextLabel", defaults)
end

-- Compact panel with white background, soft stroke and rounded corners.
-- props.Canvas = true creates a CanvasGroup so the whole panel can fade in/out.
function UIKit.panel(props)
	local canvas = props and props.Canvas
	local defaults = {
		BackgroundColor3 = C.Background,
		BorderSizePixel = 0,
		Size = UDim2.fromOffset(320, 200),
	}
	for k, v in pairs(props or {}) do
		if k ~= "Canvas" and k ~= "Radius" then
			defaults[k] = v
		end
	end
	local frame = UIKit.new(canvas and "CanvasGroup" or "Frame", defaults)
	UIKit.corner(frame, (props and props.Radius) or Theme.Radius.Medium)
	UIKit.stroke(frame, C.Stroke, 1, 0)
	return frame
end

-- Button with hover / press / selection feedback.
-- style: "primary" | "secondary" | "ghost" | "danger" | "soft"
function UIKit.button(props)
	local style = props.Style or "secondary"
	local palette = {
		primary = { bg = C.Accent, hover = C.AccentDark, text = C.TextOnAccent },
		secondary = { bg = C.Surface, hover = C.SurfaceAlt, text = C.Text },
		ghost = { bg = C.Background, hover = C.Surface, text = C.Text },
		soft = { bg = C.AccentSoft, hover = Color3.fromRGB(206, 229, 251), text = C.AccentDark },
		danger = { bg = C.DangerSoft, hover = Color3.fromRGB(248, 214, 214), text = C.Danger },
	}
	local colors = palette[style] or palette.secondary
	local button = UIKit.new("TextButton", {
		Name = props.Name or "Button",
		AutoButtonColor = false,
		BackgroundColor3 = colors.bg,
		BorderSizePixel = 0,
		Size = props.Size or UDim2.fromOffset(120, 36),
		Position = props.Position,
		AnchorPoint = props.AnchorPoint,
		LayoutOrder = props.LayoutOrder or 0,
		Font = props.Font or Theme.Fonts.Bold,
		TextSize = props.TextSize or Theme.TextSize.Body,
		TextColor3 = colors.text,
		Text = props.Text or "",
		TextWrapped = true,
		Parent = props.Parent,
	})
	UIKit.corner(button, props.Radius or Theme.Radius.Small)
	local stroke = nil
	if style ~= "primary" then
		stroke = UIKit.stroke(button, C.Stroke, 1, 0)
	end
	local scale = Instance.new("UIScale")
	scale.Name = "PressScale"
	scale.Parent = button

	local state = { selected = false, disabled = false, hovering = false }

	local function restColor()
		if state.disabled then
			return C.Disabled
		end
		if state.selected then
			return C.AccentSoft
		end
		return colors.bg
	end

	button.MouseEnter:Connect(function()
		state.hovering = true
		if not state.disabled then
			UIKit.tween(scale, Theme.Motion.Fast, { Scale = 1.03 })
			if not state.selected then
				UIKit.tween(button, Theme.Motion.Fast, { BackgroundColor3 = colors.hover })
			end
			if stroke then
				UIKit.tween(stroke, Theme.Motion.Fast, { Color = C.Accent })
			end
		end
	end)
	button.MouseLeave:Connect(function()
		state.hovering = false
		UIKit.tween(button, Theme.Motion.Fast, { BackgroundColor3 = restColor() })
		UIKit.tween(scale, Theme.Motion.Fast, { Scale = 1 })
		if stroke then
			UIKit.tween(stroke, Theme.Motion.Fast, { Color = state.selected and C.Accent or C.Stroke })
		end
	end)
	button.MouseButton1Down:Connect(function()
		if not state.disabled then
			UIKit.tween(scale, 0.08, { Scale = 0.95 })
		end
	end)
	button.MouseButton1Up:Connect(function()
		UIKit.tween(scale, Theme.Motion.Fast, { Scale = state.hovering and 1.03 or 1 }, Enum.EasingStyle.Back)
	end)
	button.Activated:Connect(function()
		if not state.disabled and props.OnClick then
			props.OnClick(button)
		end
	end)

	local api = { Instance = button, Stroke = stroke }
	function api.setSelected(selected: boolean)
		state.selected = selected
		UIKit.tween(button, Theme.Motion.Normal, { BackgroundColor3 = restColor() })
		if stroke then
			UIKit.tween(stroke, Theme.Motion.Normal, { Color = selected and C.Accent or C.Stroke })
		end
	end
	function api.setDisabled(disabled: boolean)
		state.disabled = disabled
		button.TextColor3 = disabled and C.TextMuted or colors.text
		button.BackgroundColor3 = restColor()
	end
	function api.setText(text: string)
		button.Text = text
	end
	function api.isDisabled(): boolean
		return state.disabled
	end
	return api
end

-- Motion helpers ------------------------------------------------------------------------------
-- Only one UIScale per object is honoured, so motion reuses FitScale when present and
-- animates relative to its "BaseScale" attribute. A token prevents a late close() from hiding
-- a panel that was re-opened in the meantime.
local function getScale(frame: GuiObject)
	local scale = frame:FindFirstChild("FitScale") or frame:FindFirstChild("MotionScale")
	if not scale then
		scale = Instance.new("UIScale")
		scale.Name = "MotionScale"
		scale.Parent = frame
	end
	return scale, (frame:GetAttribute("BaseScale") or 1)
end

local function nextToken(frame: GuiObject): number
	local token = (frame:GetAttribute("MotionToken") or 0) + 1
	frame:SetAttribute("MotionToken", token)
	return token
end

-- opts = { x = number?, y = number?, duration = number? } slide offset in pixels.
function UIKit.open(frame: GuiObject, fromOffsetY: number?, fromOffsetX: number?)
	nextToken(frame)
	local target = frame:GetAttribute("RestPosition")
	if not target then
		target = frame.Position
		frame:SetAttribute("RestPosition", target)
	end
	local scale, base = getScale(frame)
	scale.Scale = base * 0.97
	frame.Position = target + UDim2.fromOffset(fromOffsetX or 0, fromOffsetY or 10)
	if frame:IsA("CanvasGroup") then
		frame.GroupTransparency = 1
		UIKit.tween(frame, Theme.Motion.Normal, { GroupTransparency = 0 })
	end
	frame.Visible = true
	UIKit.tween(scale, Theme.Motion.Normal, { Scale = base })
	UIKit.tween(frame, Theme.Motion.Normal, { Position = target })
end

function UIKit.close(frame: GuiObject, toOffsetY: number?, onDone, toOffsetX: number?)
	if not frame.Visible then
		if onDone then
			onDone()
		end
		return
	end
	local token = nextToken(frame)
	local target = frame:GetAttribute("RestPosition") or frame.Position
	local scale, base = getScale(frame)
	UIKit.tween(scale, Theme.Motion.Fast, { Scale = base * 0.97 })
	if frame:IsA("CanvasGroup") then
		UIKit.tween(frame, Theme.Motion.Fast, { GroupTransparency = 1 })
	end
	local tween = UIKit.tween(frame, Theme.Motion.Fast, { Position = target + UDim2.fromOffset(toOffsetX or 0, toOffsetY or 10) })
	tween.Completed:Connect(function()
		if frame:GetAttribute("MotionToken") ~= token then
			return -- re-opened meanwhile
		end
		frame.Visible = false
		frame.Position = target
		scale.Scale = base
		if onDone then
			onDone()
		end
	end)
end

-- Fade a CanvasGroup (or any GuiObject) in/out without movement.
function UIKit.fade(frame: GuiObject, visible: boolean, duration: number?)
	local token = nextToken(frame)
	local d = duration or Theme.Motion.Normal
	if visible then
		frame.Visible = true
		if frame:IsA("CanvasGroup") then
			frame.GroupTransparency = 1
			UIKit.tween(frame, d, { GroupTransparency = 0 })
		end
	else
		if not frame:IsA("CanvasGroup") then
			frame.Visible = false
			return
		end
		UIKit.tween(frame, d, { GroupTransparency = 1 }).Completed:Connect(function()
			if frame:GetAttribute("MotionToken") == token then
				frame.Visible = false
			end
		end)
	end
end

-- Horizontal ScrollingFrame that also scrolls with the mouse wheel (PC) and touch (mobile).
function UIKit.hScroll(props)
	local frame = UIKit.new("ScrollingFrame", {
		Name = props.Name or "HScroll",
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Size = props.Size,
		Position = props.Position or UDim2.new(),
		ScrollingDirection = Enum.ScrollingDirection.X,
		AutomaticCanvasSize = Enum.AutomaticSize.X,
		CanvasSize = UDim2.new(),
		ScrollBarThickness = 3,
		ScrollBarImageColor3 = C.GrayDark,
		ElasticBehavior = Enum.ElasticBehavior.WhenScrollable,
		LayoutOrder = props.LayoutOrder or 0,
		Parent = props.Parent,
	})
	UIKit.list(frame, Enum.FillDirection.Horizontal, props.Spacing or 6, nil, Enum.VerticalAlignment.Center)
	local hovering = false
	frame.MouseEnter:Connect(function()
		hovering = true
	end)
	frame.MouseLeave:Connect(function()
		hovering = false
	end)
	local connection
	connection = UserInputService.InputChanged:Connect(function(input)
		if not frame.Parent then
			connection:Disconnect()
			return
		end
		if hovering and frame.Visible and input.UserInputType == Enum.UserInputType.MouseWheel then
			local maxX = math.max(0, frame.AbsoluteCanvasSize.X - frame.AbsoluteWindowSize.X)
			local x = math.clamp(frame.CanvasPosition.X - input.Position.Z * 60, 0, maxX)
			UIKit.tween(frame, Theme.Motion.Fast, { CanvasPosition = Vector2.new(x, 0) })
		end
	end)
	return frame
end

function UIKit.vScroll(props)
	local frame = UIKit.new("ScrollingFrame", {
		Name = props.Name or "VScroll",
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Size = props.Size,
		Position = props.Position or UDim2.new(),
		ScrollingDirection = Enum.ScrollingDirection.Y,
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		CanvasSize = UDim2.new(),
		ScrollBarThickness = 3,
		ScrollBarImageColor3 = C.GrayDark,
		LayoutOrder = props.LayoutOrder or 0,
		Parent = props.Parent,
	})
	return frame
end

-- Flag display: real asset if FlagAsset is set, otherwise emoji fallback text.
function UIKit.flag(parent: Instance, entry, size: number)
	local holder = UIKit.new("Frame", {
		Name = "Flag",
		BackgroundColor3 = C.SurfaceAlt,
		BorderSizePixel = 0,
		Size = UDim2.fromOffset(size * 1.4, size),
		Parent = parent,
	})
	UIKit.corner(holder, 4)
	if entry and type(entry.FlagAsset) == "string" and entry.FlagAsset ~= "" then
		UIKit.new("ImageLabel", {
			BackgroundTransparency = 1,
			Size = UDim2.fromScale(1, 1),
			Image = entry.FlagAsset,
			ScaleType = Enum.ScaleType.Crop,
			Parent = holder,
		})
	else
		UIKit.new("TextLabel", {
			BackgroundTransparency = 1,
			Size = UDim2.fromScale(1, 1),
			Text = entry and entry.EmojiFallback or "?",
			TextScaled = true,
			Font = Theme.Fonts.Regular,
			TextColor3 = C.Text,
			Parent = holder,
		})
	end
	return holder
end

-- Hammer icon drawn with frames (no external image assets). CanvasGroup so it can rotate as one.
function UIKit.hammerIcon(parent: Instance, size: number, color: Color3?)
	local col = color or C.AccentDark
	local holder = UIKit.new("CanvasGroup", {
		Name = "HammerIcon",
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(size, size),
		Parent = parent,
	})
	local handle = UIKit.new("Frame", {
		Name = "Handle",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.44, 0.56),
		Size = UDim2.new(0, math.max(2, size * 0.16), 0, size * 0.82),
		BackgroundColor3 = col,
		BorderSizePixel = 0,
		Rotation = 45,
		Parent = holder,
	})
	UIKit.corner(handle, 999)
	local head = UIKit.new("Frame", {
		Name = "Head",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.64, 0.36),
		Size = UDim2.new(0, size * 0.62, 0, size * 0.3),
		BackgroundColor3 = col,
		BorderSizePixel = 0,
		Rotation = 45,
		Parent = holder,
	})
	UIKit.corner(head, math.floor(size * 0.08))
	local shine = UIKit.new("Frame", {
		Name = "Shine",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.3),
		Size = UDim2.new(0.8, 0, 0, math.max(1, size * 0.06)),
		BackgroundColor3 = Color3.new(1, 1, 1),
		BackgroundTransparency = 0.45,
		BorderSizePixel = 0,
		Parent = head,
	})
	UIKit.corner(shine, 999)
	return holder
end

-- Bar-chart icon for the STATS button.
function UIKit.statsIcon(parent: Instance, size: number, color: Color3?)
	local col = color or C.AccentDark
	local holder = UIKit.new("CanvasGroup", {
		Name = "StatsIcon",
		BackgroundTransparency = 1,
		Size = UDim2.fromOffset(size, size),
		Parent = parent,
	})
	local heights = { 0.45, 0.8, 0.6 }
	for i, h in ipairs(heights) do
		local bar = UIKit.new("Frame", {
			AnchorPoint = Vector2.new(0, 1),
			Position = UDim2.new((i - 1) * 0.34 + 0.04, 0, 0.92, 0),
			Size = UDim2.new(0.24, 0, h, 0),
			BackgroundColor3 = col,
			BorderSizePixel = 0,
			Parent = holder,
		})
		UIKit.corner(bar, 2)
	end
	return holder
end

function UIKit.statusDot(parent: Instance, color: Color3, size: number?)
	local s = size or 8
	local dot = UIKit.new("Frame", {
		Name = "Dot",
		BackgroundColor3 = color,
		BorderSizePixel = 0,
		Size = UDim2.fromOffset(s, s),
		Parent = parent,
	})
	UIKit.corner(dot, 999)
	return dot
end

function UIKit.statusColor(status: string?): Color3
	if status == "GREEN" then
		return C.StatusGreen
	elseif status == "RED" then
		return C.StatusRed
	end
	return C.StatusGrey
end

-- Scale a centered dialog down on small screens (mobile) so it never covers the whole screen.
function UIKit.autoScale(frame: GuiObject, designWidth: number, designHeight: number)
	local scale = Instance.new("UIScale")
	scale.Name = "FitScale"
	scale.Parent = frame
	local function update()
		local camera = Workspace.CurrentCamera
		if not camera then
			return
		end
		local viewport = camera.ViewportSize
		local s = math.max(math.min((viewport.X - 24) / designWidth, (viewport.Y - 96) / designHeight, 1), 0.55)
		frame:SetAttribute("BaseScale", s)
		scale.Scale = s
	end
	update()
	local camera = Workspace.CurrentCamera
	if camera then
		camera:GetPropertyChangedSignal("ViewportSize"):Connect(update)
	end
	return scale
end

return UIKit
