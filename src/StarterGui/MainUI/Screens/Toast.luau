-- Toast: compact notifications under the top-center HUD.
-- Slide down + fade in, auto dismiss with slide up + fade out. Max 3 visible.

local UIKit = require(script.Parent.Parent:WaitForChild("Components"):WaitForChild("UIKit"))
local C = UIKit.Theme.Colors
local T = UIKit.Theme

local Toast = {}
Toast.__index = Toast

function Toast.new(root: ScreenGui)
	local self = setmetatable({}, Toast)
	self.container = UIKit.new("Frame", {
		Name = "Toasts",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 56),
		Size = UDim2.fromOffset(360, 130),
		Parent = root,
	})
	UIKit.list(self.container, Enum.FillDirection.Vertical, 6, Enum.HorizontalAlignment.Center)
	self.order = 0
	return self
end

function Toast:show(text: string, kind: string?)
	local accent = C.Accent
	if kind == "error" then
		accent = C.Danger
	elseif kind == "success" then
		accent = C.Success
	elseif kind == "warning" then
		accent = C.Warning
	end
	self.order += 1
	local item = UIKit.new("CanvasGroup", {
		Name = "Toast",
		BackgroundColor3 = C.Background,
		BorderSizePixel = 0,
		AutomaticSize = Enum.AutomaticSize.X,
		Size = UDim2.fromOffset(0, 32),
		LayoutOrder = self.order,
		GroupTransparency = 1,
		Parent = self.container,
	})
	UIKit.corner(item, 999)
	UIKit.stroke(item, C.Stroke)
	UIKit.padding(item, 0, 14)
	UIKit.list(item, Enum.FillDirection.Horizontal, 8, Enum.HorizontalAlignment.Center, Enum.VerticalAlignment.Center)
	local dot = UIKit.statusDot(item, accent, 8)
	dot.LayoutOrder = 1
	UIKit.label({
		Text = text,
		TextColor3 = C.Text,
		Font = T.Fonts.Medium,
		TextSize = T.TextSize.Small,
		AutomaticSize = Enum.AutomaticSize.X,
		Size = UDim2.fromOffset(0, 32),
		TextXAlignment = Enum.TextXAlignment.Center,
		LayoutOrder = 2,
		Parent = item,
	})
	local scale = Instance.new("UIScale")
	scale.Scale = 0.9
	scale.Parent = item
	UIKit.tween(item, 0.2, { GroupTransparency = 0 })
	UIKit.tween(scale, 0.25, { Scale = 1 }, Enum.EasingStyle.Back)
	task.delay(2.6, function()
		if item.Parent then
			UIKit.tween(scale, 0.2, { Scale = 0.94 })
			UIKit.tween(item, 0.22, { GroupTransparency = 1 }).Completed:Connect(function()
				item:Destroy()
			end)
		end
	end)
	local items = {}
	for _, child in ipairs(self.container:GetChildren()) do
		if child:IsA("CanvasGroup") then
			table.insert(items, child)
		end
	end
	table.sort(items, function(a, b)
		return a.LayoutOrder < b.LayoutOrder
	end)
	while #items > 3 do
		table.remove(items, 1):Destroy()
	end
end

return Toast
