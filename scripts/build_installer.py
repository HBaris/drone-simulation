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
    "-- Auto-generated installer for Drone Simulation System",
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

installer_lines.append('print("[DroneInstaller] ✅ Installation Complete! Ready for simulation.")')

output_path = os.path.join(base_dir, "scripts", "InstallToStudio.luau")
with open(output_path, "w", encoding="utf-8") as f:
    f.write("\n".join(installer_lines))

print(f"Generated {output_path} successfully!")
