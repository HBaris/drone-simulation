--!strict
-- WaypointEditor.client.luau
-- Clean Client Controller coordinating 3D Waypoint interactions, UI events, and Swarm commands.

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local DroneConfig = require(ReplicatedStorage:WaitForChild("DroneConfig"))
local FlightMath = require(ReplicatedStorage:WaitForChild("FlightMath"))
local EditorUI = require(script.Parent:WaitForChild("ui"):WaitForChild("EditorUI"))
local PathVisualizer = require(script.Parent:WaitForChild("visuals"):WaitForChild("PathVisualizer"))

local player = Players.LocalPlayer
local mouse = player:GetMouse()
local playerGui = player:WaitForChild("PlayerGui")

-- Remotes
local Network = ReplicatedStorage:WaitForChild("DroneNetwork")
local StartFlightEvent = Network:WaitForChild("StartFlight") :: RemoteEvent
local StopFlightEvent = Network:WaitForChild("StopFlight") :: RemoteEvent
local SetFormationEvent = Network:WaitForChild("SetFormation") :: RemoteEvent
local ExportFunction = Network:WaitForChild("ExportMissionData") :: RemoteFunction

-- State
local waypoints: { FlightMath.Waypoint } = {}
local visualState = PathVisualizer.new()
local editorMode = "WAYPOINTS" -- "WAYPOINTS" or "SWARM"
local swarmDroneCount = 50

-- Initialize UI
local ui = EditorUI.create(playerGui)

-- Tab Switchers
ui.BtnTabWaypoints.MouseButton1Click:Connect(function()
	editorMode = "WAYPOINTS"
	ui.WaypointFrame.Visible = true
	ui.SwarmFrame.Visible = false
	ui.BtnTabWaypoints.BackgroundColor3 = Color3.fromRGB(0, 180, 100)
	ui.BtnTabWaypoints.TextColor3 = Color3.new(1, 1, 1)
	ui.BtnTabSwarm.BackgroundColor3 = Color3.fromRGB(40, 45, 55)
	ui.BtnTabSwarm.TextColor3 = Color3.fromRGB(180, 180, 180)
end)

ui.BtnTabSwarm.MouseButton1Click:Connect(function()
	editorMode = "SWARM"
	ui.WaypointFrame.Visible = false
	ui.SwarmFrame.Visible = true
	ui.BtnTabSwarm.BackgroundColor3 = Color3.fromRGB(0, 180, 100)
	ui.BtnTabSwarm.TextColor3 = Color3.new(1, 1, 1)
	ui.BtnTabWaypoints.BackgroundColor3 = Color3.fromRGB(40, 45, 55)
	ui.BtnTabWaypoints.TextColor3 = Color3.fromRGB(180, 180, 180)
end)

-- Drone Count Buttons
for count, btn in pairs(ui.CountButtons) do
	btn.MouseButton1Click:Connect(function()
		swarmDroneCount = count
		ui.DroneCountLabel.Text = "Aktif Drone Sayısı: " .. count
	end)
end

-- Mouse Click to Place Waypoints
UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if gameProcessed or editorMode ~= "WAYPOINTS" then
		return
	end

	if input.UserInputType == Enum.UserInputType.MouseButton1 then
		local hit = mouse.Hit
		if hit then
			local wpPos = Vector3.new(hit.Position.X, hit.Position.Y + DroneConfig.FLIGHT.TAKEOFF_ALTITUDE, hit.Position.Z)
			local index = #waypoints + 1

			table.insert(waypoints, {
				Position = wpPos,
				Altitude = DroneConfig.FLIGHT.TAKEOFF_ALTITUDE,
			})

			PathVisualizer.addMarker(visualState, wpPos, index)
			PathVisualizer.redrawTrajectory(visualState, waypoints)
		end
	end
end)

-- Waypoint Flight Controls
ui.BtnStart.MouseButton1Click:Connect(function()
	if #waypoints >= 2 then
		StartFlightEvent:FireServer(waypoints)
	end
end)

ui.BtnStop.MouseButton1Click:Connect(function()
	StopFlightEvent:FireServer()
end)

ui.BtnClear.MouseButton1Click:Connect(function()
	StopFlightEvent:FireServer()
	PathVisualizer.clearAll(visualState)
	table.clear(waypoints)
end)

-- Swarm Formation Controls
ui.BtnFormHeart.MouseButton1Click:Connect(function()
	SetFormationEvent:FireServer("Heart", swarmDroneCount, 1.5)
end)

ui.BtnFormSphere.MouseButton1Click:Connect(function()
	SetFormationEvent:FireServer("Sphere", swarmDroneCount, 1.0)
end)

ui.BtnFormHelix.MouseButton1Click:Connect(function()
	SetFormationEvent:FireServer("Helix", swarmDroneCount, 1.0)
end)

ui.BtnFormCircle.MouseButton1Click:Connect(function()
	SetFormationEvent:FireServer("Circle", swarmDroneCount, 1.0)
end)

ui.BtnFormGrid.MouseButton1Click:Connect(function()
	SetFormationEvent:FireServer("Grid", swarmDroneCount, 1.0)
end)

-- Mission Exporter Modals
ui.BtnExportJSON.MouseButton1Click:Connect(function()
	local jsonString = ExportFunction:InvokeServer("JSON")
	EditorUI.showExportModal(ui.ScreenGui, jsonString, "JSON")
end)

ui.BtnExportCSV.MouseButton1Click:Connect(function()
	local csvString = ExportFunction:InvokeServer("CSV")
	EditorUI.showExportModal(ui.ScreenGui, csvString, "CSV")
end)

print("[WaypointEditor] Controller initialized with modular UI and Visualizer.")
