import json
import re
import unittest

from tests._common import ROOT, SRC, read

REQUIRED_FILES = [
    "default.project.json",
    "build_war_state.py",
    "tools/countries.py",
    "tools/rojo_build.py",
    "tools/gen_static_map.py",
    "tools/required_build_paths.txt",
    "src/ServerScriptService/ServerMain.server.luau",
    "src/ServerScriptService/Systems/Data/DataService.luau",
    "src/ServerScriptService/Systems/Country/CountryService.luau",
    "src/ServerScriptService/Systems/World/WorldService.luau",
    "src/ServerScriptService/Systems/Buildings/BuildingService.luau",
    "src/ServerScriptService/Systems/Construction/ConstructionService.luau",
    "src/ServerScriptService/Systems/Population/PopulationService.luau",
    "src/ServerScriptService/Systems/Roads/RoadService.luau",
    "src/ServerScriptService/Systems/Resources/ResourceService.luau",
    "src/ServerScriptService/Systems/Research/ResearchService.luau",
    "src/ServerScriptService/Systems/Production/ProductionService.luau",
    "src/ServerScriptService/Systems/Economy/EconomyService.luau",
    "src/ServerScriptService/Systems/Military/MilitaryService.luau",
    "src/ServerScriptService/Systems/Water/WaterService.luau",
    "src/ServerScriptService/Systems/Power/PowerService.luau",
    "src/ServerScriptService/Systems/Stats/StatsService.luau",
    "src/ServerScriptService/Systems/Vehicles/VehicleService.luau",
    "src/ServerScriptService/Tests/RuntimeSelfTest.server.luau",
    "src/ReplicatedStorage/Shared/Constants/Constants.luau",
    "src/ReplicatedStorage/Shared/Types/Types.luau",
    "src/ReplicatedStorage/Shared/Config/GameConfig.json",
    "src/ReplicatedStorage/Shared/Config/BuildingConfig.json",
    "src/ReplicatedStorage/Shared/Config/RoadConfig.json",
    "src/ReplicatedStorage/Shared/Config/PlacementConfig.json",
    "src/ReplicatedStorage/Shared/Config/BuildMenuConfig.json",
    "src/ReplicatedStorage/Shared/Config/TechnologyConfig.json",
    "src/ReplicatedStorage/Shared/Config/CountryRegistry.json",
    "src/ReplicatedStorage/Shared/Config/ThemeConfig.luau",
    "src/ReplicatedStorage/Shared/Modules/GridMath.luau",
    "src/ReplicatedStorage/Shared/Modules/PlacementRules.luau",
    "src/ReplicatedStorage/Shared/Modules/RoadGraph.luau",
    "src/ReplicatedStorage/Shared/Modules/BuildingModels.luau",
    "src/ReplicatedStorage/Shared/Modules/RoadModels.luau",
    "src/ReplicatedStorage/Shared/Modules/Countries.luau",
    "src/ReplicatedStorage/Shared/Modules/DefaultCountry.luau",
    "src/ReplicatedStorage/Shared/Modules/Plots.luau",
    "src/ReplicatedStorage/Shared/Modules/UtilityGrid.luau",
    "src/StarterPlayer/StarterPlayerScripts/ClientMain.client.luau",
    "src/StarterPlayer/StarterPlayerScripts/Controllers/ClientState.luau",
    "src/StarterPlayer/StarterPlayerScripts/Controllers/PlacementController.luau",
    "src/StarterPlayer/StarterPlayerScripts/Controllers/ConstructionBars.luau",
    "src/StarterGui/MainUI/Components/UIKit.luau",
    "src/StarterGui/MainUI/Screens/MainMenu.luau",
    "src/StarterGui/MainUI/Screens/SlotScreen.luau",
    "src/StarterGui/MainUI/Screens/CreateStateScreen.luau",
    "src/StarterGui/MainUI/Screens/PlotScreen.luau",
    "src/StarterGui/MainUI/Screens/HUD.luau",
    "src/StarterGui/MainUI/Screens/BuildMenu.luau",
    "src/StarterGui/MainUI/Screens/PlacementBar.luau",
    "src/StarterGui/MainUI/Screens/StatsPanel.luau",
    "src/StarterGui/MainUI/Screens/Toast.luau",
    "plugin/WarStateBridge.server.luau",
    "plugin.project.json",
    "PROJECT.md",
    "DEVELOPMENT_ROADMAP.md",
    "AGENTS.md",
]

# Only directories that actually contain files. Git does not store empty directories, so the
# Workspace runtime folders are declared as explicit Folders in default.project.json instead.
REQUIRED_DIRS = [
    "src/ReplicatedStorage/Shared/Config",
    "src/ReplicatedStorage/Shared/Constants",
    "src/ReplicatedStorage/Shared/Types",
    "src/ReplicatedStorage/Shared/Modules",
]

WORKSPACE_FOLDERS = ["Buildings", "Roads", "Vehicles", "NPCs"]


def server_sources():
    return "\n".join(p.read_text(encoding="utf-8") for p in (SRC / "ServerScriptService").rglob("*.luau"))


class StructureTests(unittest.TestCase):
    def test_required_files_exist(self):
        missing = [f for f in REQUIRED_FILES if not (ROOT / f).is_file()]
        self.assertEqual(missing, [], "Missing files: %s" % missing)

    def test_required_dirs_exist(self):
        missing = [d for d in REQUIRED_DIRS if not (ROOT / d).is_dir()]
        self.assertEqual(missing, [])

    def test_workspace_folders_declared_in_project(self):
        workspace = json.loads(read("default.project.json"))["tree"]["Workspace"]
        for name in WORKSPACE_FOLDERS:
            self.assertIn(name, workspace, name)
            self.assertEqual(workspace[name].get("$className"), "Folder", name)
            self.assertNotIn("$path", workspace[name], "%s must not point at an empty dir" % name)
        # The static map is real place content generated into src/Workspace/Map (gen_static_map.py)
        self.assertEqual(workspace["Map"]["$path"], "src/Workspace/Map")
        self.assertEqual(workspace["Terrain"]["$className"], "Terrain")

    def test_no_dead_assets_mapping(self):
        replicated = json.loads(read("default.project.json"))["tree"]["ReplicatedStorage"]
        self.assertNotIn("Assets", replicated)

    def test_project_json_paths_exist(self):
        project = json.loads(read("default.project.json"))
        self.assertEqual(project["tree"]["$className"], "DataModel")
        bad = []

        def walk(node):
            for key, value in node.items():
                if key == "$path" and not (ROOT / value).exists():
                    bad.append(value)
                elif isinstance(value, dict) and not key.startswith("$"):
                    walk(value)

        walk(project["tree"])
        self.assertEqual(bad, [])

    def test_services_do_not_wipe_existing_place(self):
        tree = json.loads(read("default.project.json"))["tree"]
        for service in ("ReplicatedStorage", "ServerScriptService", "StarterPlayer", "StarterGui", "Workspace"):
            self.assertIn(service, tree)
            self.assertNotIn("$path", tree[service], "%s must not be mapped wholesale" % service)
            self.assertTrue(tree[service].get("$ignoreUnknownInstances"), service)

    def test_remotes_match_constants(self):
        tree = json.loads(read("default.project.json"))["tree"]
        remotes = tree["ReplicatedStorage"]["Remotes"]
        names = {k for k in remotes if not k.startswith("$")}
        constants = read("src/ReplicatedStorage/Shared/Constants/Constants.luau")
        block = re.search(r"Constants\.Remotes = \{(.*?)\n\}", constants, re.S).group(1)
        declared = set(re.findall(r'^\t(\w+) = "\1",$', block, re.M))
        self.assertEqual(names, declared)
        fn_block = re.search(r"Constants\.RemoteFunctions = \{(.*?)\n\}", constants, re.S).group(1)
        ev_block = re.search(r"Constants\.RemoteEvents = \{(.*?)\n\}", constants, re.S).group(1)
        fns = set(re.findall(r'"(\w+)"', fn_block))
        evs = set(re.findall(r'"(\w+)"', ev_block))
        self.assertEqual(fns | evs, names)
        for name in fns:
            self.assertEqual(remotes[name]["$className"], "RemoteFunction", name)
        for name in evs:
            self.assertEqual(remotes[name]["$className"], "RemoteEvent", name)

    def test_every_remote_function_has_a_server_handler(self):
        constants = read("src/ReplicatedStorage/Shared/Constants/Constants.luau")
        fn_block = re.search(r"Constants\.RemoteFunctions = \{(.*?)\n\}", constants, re.S).group(1)
        server = server_sources()
        for name in re.findall(r'"(\w+)"', fn_block):
            self.assertRegex(server, r"Remotes\.%s\]\.OnServerInvoke\s*=" % name, name)

    def test_every_system_in_server_main_exists(self):
        main = read("src/ServerScriptService/ServerMain.server.luau")
        for folder, module in re.findall(r'\{ "(\w+)", "(\w+)" \}', main):
            self.assertTrue((SRC / "ServerScriptService" / "Systems" / folder / (module + ".luau")).is_file(), module)

    def test_screens_required_by_client_exist(self):
        client = read("src/StarterPlayer/StarterPlayerScripts/ClientMain.client.luau")
        for name in re.findall(r'Screens:WaitForChild\("(\w+)"\)', client):
            self.assertTrue((SRC / "StarterGui" / "MainUI" / "Screens" / (name + ".luau")).is_file(), name)
        for name in re.findall(r'Controllers:WaitForChild\("(\w+)"\)', client):
            self.assertTrue((SRC / "StarterPlayer" / "StarterPlayerScripts" / "Controllers" / (name + ".luau")).is_file(), name)

    def test_no_instance_name_collisions(self):
        # Rojo fails when a folder contains two children with the same instance name.
        for folder in SRC.rglob("*"):
            if not folder.is_dir():
                continue
            names = []
            for child in folder.iterdir():
                if child.name.startswith("."):
                    continue
                n = child.name
                for suffix in (".server.luau", ".client.luau", ".model.json", ".luau", ".json"):
                    if n.endswith(suffix):
                        n = n[: -len(suffix)]
                        break
                names.append(n)
            self.assertEqual(len(names), len(set(names)), str(folder))


if __name__ == "__main__":
    unittest.main()
