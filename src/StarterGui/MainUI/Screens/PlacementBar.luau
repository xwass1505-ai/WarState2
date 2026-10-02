-- PlacementBar: bottom-center controls while building (works on PC and mobile).
-- Road mode: hold + drag hint and live tile count. Building mode: Style / Rotate / Place / Done.
-- Demolish mode: hint + Done. Validity: neutral text when valid, subtle red reason when invalid.

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local UIKit = require(script.Parent.Parent:WaitForChild("Components"):WaitForChild("UIKit"))
local Config = ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config")
local BuildingConfig = require(Config:WaitForChild("BuildingConfig"))
local RoadConfig = require(Config:WaitForChild("RoadConfig"))
local GameConfig = require(Config:WaitForChild("GameConfig"))

local C = UIKit.Theme.Colors
local T = UIKit.Theme

local PlacementBar = {}
PlacementBar.__index = PlacementBar

local DESIGN_W, DESIGN_H = 460, 96

local function displayName(kind, id)
	if kind == "Demolish" then
		return "Demolish"
	elseif kind == "Rail" then
		return GameConfig.Railway.Track.DisplayName
	end
	local list = kind == "Road" and RoadConfig.Types or BuildingConfig.Buildings
	for _, entry in ipairs(list) do
		if entry.Id == id then
			return entry.DisplayName
		end
	end
	return id
end

function PlacementBar.new(root: ScreenGui, callbacks)
	callbacks = callbacks or {}
	local self = setmetatable({}, PlacementBar)
	self.panel = UIKit.panel({
		Name = "PlacementBar",
		Canvas = true,
		Radius = T.Radius.Large,
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -14),
		Size = UDim2.fromOffset(DESIGN_W, DESIGN_H),
		Visible = false,
		Parent = root,
	})
	UIKit.autoScale(self.panel, DESIGN_W, DESIGN_H + 40)
	UIKit.padding(self.panel, 10, 14)
	self.title = UIKit.label({
		Text = "",
		Font = T.Fonts.Bold,
		TextSize = T.TextSize.Small,
		Size = UDim2.new(0.45, 0, 0, 18),
		Parent = self.panel,
	})
	self.status = UIKit.label({
		Text = "",
		TextSize = T.TextSize.Small,
		TextColor3 = C.TextMuted,
		TextXAlignment = Enum.TextXAlignment.Right,
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.fromScale(1, 0),
		Size = UDim2.new(0.55, 0, 0, 18),
		Parent = self.panel,
	})
	self.hint = UIKit.label({
		Text = "",
		TextSize = T.TextSize.Tiny,
		TextColor3 = C.TextMuted,
		Position = UDim2.fromOffset(0, 18),
		Size = UDim2.new(1, 0, 0, 14),
		Parent = self.panel,
	})
	local row = UIKit.new("Frame", {
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(0, 36),
		Size = UDim2.new(1, 0, 0, 40),
		Parent = self.panel,
	})
	UIKit.list(row, Enum.FillDirection.Horizontal, 6, Enum.HorizontalAlignment.Center, Enum.VerticalAlignment.Center)
	self.styleButton = UIKit.button({
		Text = "Style A",
		TextSize = T.TextSize.Small,
		Size = UDim2.fromOffset(84, 36),
		Radius = 999,
		LayoutOrder = 1,
		Parent = row,
		OnClick = callbacks.onStyle,
	})
	self.rotateButton = UIKit.button({
		Text = "Rotate (R)",
		TextSize = T.TextSize.Small,
		Size = UDim2.fromOffset(96, 36),
		Radius = 999,
		LayoutOrder = 2,
		Parent = row,
		OnClick = callbacks.onRotate,
	})
	self.placeButton = UIKit.button({
		Text = "Place",
		Style = "primary",
		TextSize = T.TextSize.Small,
		Size = UDim2.fromOffset(110, 36),
		Radius = 999,
		LayoutOrder = 3,
		Parent = row,
		OnClick = callbacks.onPlace,
	})
	UIKit.button({
		Text = "Done (Q)",
		TextSize = T.TextSize.Small,
		Size = UDim2.fromOffset(90, 36),
		Radius = 999,
		LayoutOrder = 4,
		Parent = row,
		OnClick = callbacks.onDone,
	})
	return self
end

function PlacementBar:update(status)
	if not status.Active then
		return
	end
	local kind = status.Kind
	self.title.Text = displayName(kind, status.Id)
	self.styleButton.Instance.Visible = kind == "Building"
	self.rotateButton.Instance.Visible = kind == "Building"
	self.placeButton.Instance.Visible = kind == "Building"
	if kind == "Road" then
		self.hint.Text = "Hold left mouse (or finger) and drag · release to build"
	elseif kind == "Rail" then
		self.hint.Text = "Hold and drag to lay track · release to build · stations connect tracks"
	elseif kind == "Demolish" then
		self.hint.Text = "Click one of your buildings, road or rail tiles to remove it"
	else
		self.hint.Text = "Click to place · R rotate · Q done"
	end
	if status.Variant then
		local letter = string.match(status.Variant, "_(%w+)$") or "A"
		self.styleButton.setText("Style " .. letter)
	end
	if status.Valid then
		if (kind == "Road" or kind == "Rail") and status.Tiles then
			self.status.Text = string.format("%d new tile%s", status.Tiles, status.Tiles == 1 and "" or "s")
		elseif kind == "Demolish" then
			self.status.Text = status.TargetLabel or "Ready"
		else
			self.status.Text = "Ready to place"
		end
		self.status.TextColor3 = C.TextMuted
	else
		self.status.Text = status.Reason or "Invalid placement"
		self.status.TextColor3 = C.Danger
	end
	self.placeButton.setDisabled(not status.Valid)
end

function PlacementBar:show()
	UIKit.open(self.panel, 16)
end

function PlacementBar:hide()
	UIKit.close(self.panel, 16)
end

return PlacementBar
