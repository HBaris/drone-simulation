import os
import json

base_dir = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
src_dir = os.path.join(base_dir, "src")

manifest = [
    {
        "type": "ModuleScript",
        "name": "DroneConfig",
        "parent": 'game:GetService("ReplicatedStorage")',
        "file": os.path.join(src_dir, "shared", "DroneConfig.luau")
    },
    {
        "type": "ModuleScript",
        "name": "FlightMath",
        "parent": 'game:GetService("ReplicatedStorage")',
        "file": os.path.join(src_dir, "shared", "FlightMath.luau")
    },
    {
        "type": "ModuleScript",
        "name": "FormationGenerator",
        "parent": 'game:GetService("ReplicatedStorage")',
        "file": os.path.join(src_dir, "shared", "FormationGenerator.luau")
    },
    {
        "type": "ModuleScript",
        "name": "DataExporter",
        "parent": 'game:GetService("ReplicatedStorage")',
        "file": os.path.join(src_dir, "shared", "DataExporter.luau")
    },
    {
        "type": "ModuleScript",
        "name": "FlightPackage",
        "parent": 'game:GetService("ReplicatedStorage")',
        "file": os.path.join(src_dir, "shared", "FlightPackage.luau")
    },
    {
        "type": "ModuleScript",
        "name": "DroneHealthModel",
        "parent": 'game:GetService("ReplicatedStorage")',
        "file": os.path.join(src_dir, 'shared', 'DroneHealthModel.luau')
    },
    {
        "type": "ModuleScript",
        "name": "WindModel",
        "parent": 'game:GetService("ReplicatedStorage")',
        "file": os.path.join(src_dir, "shared", "WindModel.luau")
    },
    {
        "type": "Folder",
        "name": "MapData",
        "parent": 'game:GetService("ServerStorage")',
    },
    {
        "type": "ModuleScript",
        "name": "OsmMapBuilder",
        "parent": 'game:GetService("ServerStorage"):WaitForChild("MapData")',
        "file": os.path.join(base_dir, "scripts", "maps", "OsmMapBuilder.luau")
    },
    {
        "type": "ModuleScript",
        "name": "Bahcelievler",
        "parent": 'game:GetService("ServerStorage"):WaitForChild("MapData")',
        "file": os.path.join(base_dir, "scripts", "maps", "Bahcelievler.luau")
    },
    {
        "type": "Folder",
        "name": "DroneSystem",
        "parent": 'game:GetService("ServerScriptService")',
    },
    {
        "type": "ModuleScript",
        "name": "DroneSpawner",
        "parent": 'game:GetService("ServerScriptService"):WaitForChild("DroneSystem")',
        "file": os.path.join(src_dir, "server", "DroneSpawner.luau")
    },
    {
        "type": "Script",
        "name": "FlightManager",
        "parent": 'game:GetService("ServerScriptService"):WaitForChild("DroneSystem")',
        "file": os.path.join(src_dir, "server", "FlightManager.server.luau")
    },
    {
        "type": "Script",
        "name": "WeatherService",
        "parent": 'game:GetService("ServerScriptService"):WaitForChild("DroneSystem")',
        "file": os.path.join(src_dir, "server", "WeatherService.server.luau")
    },
    {
        "type": "Script",
        "name": "BridgeLink",
        "parent": 'game:GetService("ServerScriptService"):WaitForChild("DroneSystem")',
        "file": os.path.join(src_dir, "server", "BridgeLink.server.luau")
    },
    {
        "type": "Folder",
        "name": "DroneClient",
        "parent": 'game:GetService("StarterPlayer"):WaitForChild("StarterPlayerScripts")',
    },
    {
        "type": "Folder",
        "name": "ui",
        "parent": 'game:GetService("StarterPlayer"):WaitForChild("StarterPlayerScripts"):WaitForChild("DroneClient")',
    },
    {
        "type": "ModuleScript",
        "name": "EditorUI",
        "parent": 'game:GetService("StarterPlayer"):WaitForChild("StarterPlayerScripts"):WaitForChild("DroneClient"):WaitForChild("ui")',
        "file": os.path.join(src_dir, "client", "ui", "EditorUI.luau")
    },
    {
        "type": "ModuleScript",
        "name": "FPVOverlay",
        "parent": 'game:GetService("StarterPlayer"):WaitForChild("StarterPlayerScripts"):WaitForChild("DroneClient"):WaitForChild("ui")',
        "file": os.path.join(src_dir, "client", "ui", "FPVOverlay.luau")
    },
    {
        "type": "ModuleScript",
        "name": "HealthPanel",
        "parent": 'game:GetService("StarterPlayer"):WaitForChild("StarterPlayerScripts"):WaitForChild("DroneClient"):WaitForChild("ui")',
        "file": os.path.join(src_dir, 'client', 'ui', 'HealthPanel.luau')
    },
    {
        "type": "Folder",
        "name": "visuals",
        "parent": 'game:GetService("StarterPlayer"):WaitForChild("StarterPlayerScripts"):WaitForChild("DroneClient")',
    },
    {
        "type": "ModuleScript",
        "name": "PathVisualizer",
        "parent": 'game:GetService("StarterPlayer"):WaitForChild("StarterPlayerScripts"):WaitForChild("DroneClient"):WaitForChild("visuals")',
        "file": os.path.join(src_dir, "client", "visuals", "PathVisualizer.luau")
    },
    {
        "type": "Folder",
        "name": "controllers",
        "parent": 'game:GetService("StarterPlayer"):WaitForChild("StarterPlayerScripts"):WaitForChild("DroneClient")',
    },
    {
        "type": "ModuleScript",
        "name": "Autopilot",
        "parent": 'game:GetService("StarterPlayer"):WaitForChild("StarterPlayerScripts"):WaitForChild("DroneClient"):WaitForChild("controllers")',
        "file": os.path.join(src_dir, 'client', 'controllers', 'Autopilot.luau')
    },
    {
        "type": "ModuleScript",
        "name": "DronePhysics",
        "parent": 'game:GetService("StarterPlayer"):WaitForChild("StarterPlayerScripts"):WaitForChild("DroneClient"):WaitForChild("controllers")',
        "file": os.path.join(src_dir, 'client', 'controllers', 'DronePhysics.luau')
    },
    {
        "type": "ModuleScript",
        "name": "FlightEnvironment",
        "parent": 'game:GetService("StarterPlayer"):WaitForChild("StarterPlayerScripts"):WaitForChild("DroneClient"):WaitForChild("controllers")',
        "file": os.path.join(src_dir, 'client', 'controllers', 'FlightEnvironment.luau')
    },
    {
        "type": "ModuleScript",
        "name": "BridgeClient",
        "parent": 'game:GetService("StarterPlayer"):WaitForChild("StarterPlayerScripts"):WaitForChild("DroneClient"):WaitForChild("controllers")',
        "file": os.path.join(src_dir, "client", "controllers", "BridgeClient.luau")
    },
    {
        "type": "ModuleScript",
        "name": "FlightRecorder",
        "parent": 'game:GetService("StarterPlayer"):WaitForChild("StarterPlayerScripts"):WaitForChild("DroneClient"):WaitForChild("controllers")',
        "file": os.path.join(src_dir, "client", "controllers", "FlightRecorder.luau")
    },
    {
        "type": "LocalScript",
        "name": "DronePilotController",
        "parent": 'game:GetService("StarterPlayer"):WaitForChild("StarterPlayerScripts"):WaitForChild("DroneClient"):WaitForChild("controllers")',
        "file": os.path.join(src_dir, "client", "controllers", "DronePilotController.client.luau")
    },
    {
        "type": "LocalScript",
        "name": "WaypointEditor",
        "parent": 'game:GetService("StarterPlayer"):WaitForChild("StarterPlayerScripts"):WaitForChild("DroneClient")',
        "file": os.path.join(src_dir, "client", "WaypointEditor.client.luau")
    },
    {
        "type": "LocalScript",
        "name": "DroneHUD",
        "parent": 'game:GetService("StarterPlayer"):WaitForChild("StarterPlayerScripts"):WaitForChild("DroneClient")',
        "file": os.path.join(src_dir, "client", "DroneHUD.client.luau")
    }
]

installer_lines = [
    "--!strict",
    "-- InstallToStudio.luau",
    "-- Auto-generated installer for Drone Simulation System with Istanbul & FPV flight",
    'print("[DroneInstaller] Installing Drone Simulation System...")',
    "",
]

for item in manifest:
    item_type = item["type"]
    name = item["name"]
    parent_expr = item["parent"]

    if item_type == "Folder":
        installer_lines.append(f'do')
        installer_lines.append(f'    local parent = {parent_expr}')
        installer_lines.append(f'    local existing = parent:FindFirstChild("{name}")')
        installer_lines.append(f'    if not existing then')
        installer_lines.append(f'        local f = Instance.new("Folder")')
        installer_lines.append(f'        f.Name = "{name}"')
        installer_lines.append(f'        f.Parent = parent')
        installer_lines.append(f'    end')
        installer_lines.append(f'end')
        installer_lines.append("")
    else:
        with open(item["file"], "r", encoding="utf-8") as f:
            code_content = f.read()

        installer_lines.append(f'do')
        installer_lines.append(f'    local parent = {parent_expr}')
        installer_lines.append(f'    local existing = parent:FindFirstChild("{name}")')
        installer_lines.append(f'    if existing then existing:Destroy() end')
        installer_lines.append(f'    local s = Instance.new("{item_type}")')
        installer_lines.append(f'    s.Name = "{name}"')
        installer_lines.append(f'    s.Source = {json.dumps(code_content)}')
        installer_lines.append(f'    s.Parent = parent')
        installer_lines.append(f'    print("[DroneInstaller] Installed {name} ({item_type})")')
        installer_lines.append(f'end')
        installer_lines.append("")

# DroneConfig.ACTIVE_SITE = "BAHCELIEVLER" launches from this map, so build it right away
installer_lines.append('do')
installer_lines.append('    local mapData = game:GetService("ServerStorage"):WaitForChild("MapData")')
installer_lines.append('    require(mapData.OsmMapBuilder).build(require(mapData.Bahcelievler), Vector3.new(6000, 0, 0))')
installer_lines.append('    print("[DroneInstaller] Built Workspace.Map_Bahcelievler (OpenStreetMap)")')
installer_lines.append('end')
installer_lines.append("")
installer_lines.append('print("[DroneInstaller] ✅ Installation Complete! Ready for simulation.")')

output_path = os.path.join(base_dir, "scripts", "InstallToStudio.luau")
with open(output_path, "w", encoding="utf-8") as f:
    f.write("\n".join(installer_lines))

print(f"Generated {output_path} successfully!")
