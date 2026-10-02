-- ClientMain: the single client entry point.
-- Flow: MAIN MENU -> CREATE COUNTRY -> COUNTRY SETUP -> PLOT SELECTION -> GAME.
-- Client responsibilities: input, UI, preview. Everything permanent is requested from the server.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterGui = game:GetService("StarterGui")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local mainUI = playerGui:WaitForChild("MainUI")

mainUI.ResetOnSpawn = false
mainUI.IgnoreGuiInset = false
mainUI.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
mainUI.DisplayOrder = 10
pcall(function()
	mainUI.ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets
end)

-- Full-screen backdrop for the menus (drawn below MainUI, covers the whole screen).
local backdropGui = playerGui:FindFirstChild("WarStateBackdrop")
if not backdropGui then
	backdropGui = Instance.new("ScreenGui")
	backdropGui.Name = "WarStateBackdrop"
	backdropGui.ResetOnSpawn = false
	backdropGui.IgnoreGuiInset = true
	backdropGui.DisplayOrder = 5
	backdropGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	pcall(function()
		backdropGui.ScreenInsets = Enum.ScreenInsets.None
	end)
	backdropGui.Parent = playerGui
end

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Constants = require(Shared:WaitForChild("Constants"):WaitForChild("Constants"))
local Remotes = ReplicatedStorage:WaitForChild("Remotes")

local Controllers = script.Parent:WaitForChild("Controllers")
local ClientState = require(Controllers:WaitForChild("ClientState"))
local PlacementController = require(Controllers:WaitForChild("PlacementController"))
local ConstructionBars = require(Controllers:WaitForChild("ConstructionBars"))

local Screens = mainUI:WaitForChild("Screens")
local Toast = require(Screens:WaitForChild("Toast"))
local MainMenu = require(Screens:WaitForChild("MainMenu"))
local CreateStateScreen = require(Screens:WaitForChild("CreateStateScreen"))
local PlotScreen = require(Screens:WaitForChild("PlotScreen"))
local HUD = require(Screens:WaitForChild("HUD"))
local BuildMenu = require(Screens:WaitForChild("BuildMenu"))
local PlacementBar = require(Screens:WaitForChild("PlacementBar"))
local StatsPanel = require(Screens:WaitForChild("StatsPanel"))

local function remote(name: string)
	return Remotes:WaitForChild(name)
end

local function invoke(name: string, ...)
	local args = table.pack(...)
	local ok, result = pcall(function()
		return remote(name):InvokeServer(table.unpack(args, 1, args.n))
	end)
	if not ok then
		return { ok = false, error = "Connection problem" }
	end
	if type(result) ~= "table" then
		return { ok = false, error = "Unexpected server response" }
	end
	return result
end

player.CameraMaxZoomDistance = math.max(player.CameraMaxZoomDistance, 220)

local toast = Toast.new(mainUI)
local mainMenu, createScreen, plotScreen, hud, buildMenu, placementBar, statsPanel

local function showMainMenu()
	local profile = invoke(Constants.Remotes.GetProfile)
	if not profile.ok then
		toast:show(profile.error or "Could not load slots", "error")
		task.delay(2, showMainMenu)
		return
	end
	hud:hide()
	statsPanel.panel.Visible = false
	mainMenu:show(profile)
end

local function showPlotSelection(plots, preferred)
	mainMenu:showBackdrop()
	if not plots then
		local result = invoke(Constants.Remotes.GetPlots)
		plots = result.plots or {}
	end
	plotScreen:show(plots, preferred)
end

-- Country created or loaded: continue to PLOT SELECTION (no automatic plot).
local function afterCountryReady(result)
	if not result.ok then
		toast:show(result.error or "Could not open country", "error")
		return false
	end
	if result.state then
		ClientState.set(result.state)
	end
	mainMenu:hideContent()
	showPlotSelection(result.plots, result.state and result.state.LastPlotIndex)
	return true
end

local function enterGame(result)
	if result.state then
		ClientState.set(result.state)
	end
	mainMenu:hide()
	hud:show()
	hud:update(ClientState.snapshot)
	statsPanel:update(ClientState.snapshot)
	toast:show("Welcome to " .. tostring(ClientState.snapshot.Name or "your state"), "success")
end

mainMenu = MainMenu.new(backdropGui, mainUI, {
	onCreate = function(index)
		mainMenu:hideContent()
		createScreen:show(index)
	end,
	onPlay = function(index)
		afterCountryReady(invoke(Constants.Remotes.LoadSlot, index))
	end,
	onDelete = function(index)
		local result = invoke(Constants.Remotes.DeleteSlot, index)
		if result.ok then
			toast:show("Slot " .. index .. " deleted")
		else
			toast:show(result.error or "Delete failed", "error")
		end
		showMainMenu()
	end,
})

createScreen = CreateStateScreen.new(mainUI, {
	onSubmit = function(index, payload)
		local result = invoke(Constants.Remotes.CreateCountry, index, payload)
		if result.ok then
			afterCountryReady(result)
		end
		return result
	end,
	onCancel = function()
		showMainMenu()
	end,
})

plotScreen = PlotScreen.new(mainUI, {
	onClaim = function(plotIndex)
		local result = invoke(Constants.Remotes.ClaimPlot, plotIndex)
		if result.ok then
			enterGame(result)
		end
		return result
	end,
	onBack = function()
		plotScreen:hide()
		invoke(Constants.Remotes.LeaveState)
		ClientState.set({ Active = false })
		showMainMenu()
	end,
})

local function exitPlacement()
	PlacementController.cancel()
	placementBar:hide()
	hud:setHammerVisible(true)
end

buildMenu = BuildMenu.new(mainUI, {
	onSelect = function(kind, id)
		hud:setHammerVisible(false)
		PlacementController.start(kind, id)
		placementBar:show()
	end,
	onClose = function()
		hud:setHammerVisible(true)
	end,
})

placementBar = PlacementBar.new(mainUI, {
	onStyle = function()
		PlacementController.cycleVariant()
	end,
	onRotate = function()
		PlacementController.rotate()
	end,
	onPlace = function()
		PlacementController.confirm()
	end,
	onDone = function()
		local wasDemolish = PlacementController.getStatus().Kind == "Demolish"
		exitPlacement()
		if not wasDemolish then
			buildMenu:show()
			hud:setHammerVisible(false)
		end
	end,
})

statsPanel = StatsPanel.new(mainUI)

hud = HUD.new(mainUI, {
	onOpenBuild = function()
		hud:setHammerVisible(false)
		buildMenu:show()
	end,
	onDemolish = function()
		hud:setHammerVisible(false)
		PlacementController.start("Demolish", nil)
		placementBar:show()
	end,
	onStats = function()
		statsPanel:toggle()
	end,
	onSave = function()
		local result = invoke(Constants.Remotes.SaveNow)
		if result.ok and result.persistent then
			toast:show("Saved", "success")
		elseif result.ok then
			toast:show("Saving is off in this session", "error")
		else
			toast:show(result.error or "Save failed", "error")
		end
	end,
	onChangeSlot = function()
		exitPlacement()
		buildMenu.panel.Visible = false
		statsPanel.panel.Visible = false
		local result = invoke(Constants.Remotes.LeaveState)
		if result.ok then
			ClientState.set({ Active = false })
			showMainMenu()
		else
			toast:show(result.error or "Could not leave", "error")
		end
	end,
})

PlacementController.onStatus(function(status)
	if status.Active then
		placementBar:update(status)
	else
		placementBar:hide()
		if not buildMenu:isOpen() and ClientState.snapshot.Active and not ClientState.snapshot.NeedsPlot then
			hud:setHammerVisible(true)
		end
	end
end)

PlacementController.onResult(function(success, message)
	if not success then
		toast:show(message, "error")
	end
end)

remote(Constants.Remotes.StateChanged).OnClientEvent:Connect(function(snapshot)
	ClientState.set(snapshot)
end)

remote(Constants.Remotes.PlotsChanged).OnClientEvent:Connect(function(plots)
	if plotScreen:isOpen() then
		plotScreen:setPlots(plots)
	end
end)

remote(Constants.Remotes.Notify).OnClientEvent:Connect(function(payload)
	if type(payload) == "table" and type(payload.Text) == "string" then
		toast:show(payload.Text, payload.Kind)
	end
end)

ClientState.onChanged(function(snapshot)
	if snapshot.Active and not snapshot.NeedsPlot then
		hud:update(snapshot)
		statsPanel:update(snapshot)
	end
end)

pcall(function()
	StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Backpack, false)
end)

ConstructionBars.start()
showMainMenu()
