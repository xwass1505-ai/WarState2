import json
import unittest

from tests import luau_names, luau_parser, luau_static
from tests._common import CONFIG, ROOT, SRC, luau_files


class LuauStaticTests(unittest.TestCase):
    def test_all_luau_files_heuristic(self):
        failures = {}
        files = luau_files()
        self.assertGreater(len(files), 40)
        for path in files:
            is_module = not (path.name.endswith(".server.luau") or path.name.endswith(".client.luau"))
            errors = luau_static.check_luau(path.read_text(encoding="utf-8"), is_module)
            if errors:
                failures[str(path.relative_to(ROOT))] = errors
        self.assertEqual(failures, {})

    def test_all_luau_files_parse(self):
        failures = {}
        for path in luau_files():
            errors = luau_parser.parse_luau(path.read_text(encoding="utf-8"))
            if errors:
                failures[str(path.relative_to(ROOT))] = errors
        self.assertEqual(failures, {})

    def test_parser_rejects_broken_code(self):
        for src in ("local x = 1 +", "if x then y()", "for i = 1 do end", "local t = {a = 1 b = 2}", "f(1,)", "x"):
            self.assertTrue(luau_parser.parse_luau(src), src)

    def test_no_undefined_identifiers(self):
        failures = {}
        for path in luau_files():
            missing = luau_names.undefined_names(path.read_text(encoding="utf-8"))
            if missing:
                failures[str(path.relative_to(ROOT))] = missing
        self.assertEqual(failures, {})

    def test_no_todo_placeholders_in_required_code(self):
        offenders = [str(p.relative_to(ROOT)) for p in SRC.rglob("*.luau") if "TODO" in p.read_text(encoding="utf-8")]
        self.assertEqual(offenders, [])

    def test_json_configs_parse(self):
        for path in CONFIG.glob("*.json"):
            json.loads(path.read_text(encoding="utf-8"))

    def test_no_heavy_render_loops_on_server(self):
        server = SRC / "ServerScriptService"
        for path in server.rglob("*.luau"):
            text = path.read_text(encoding="utf-8")
            self.assertNotIn("RenderStepped", text, path.name)
            self.assertNotIn(".Heartbeat:Connect", text, path.name)

    def test_render_stepped_only_in_placement(self):
        users = [p.name for p in SRC.rglob("*.luau") if "RenderStepped:Connect" in p.read_text(encoding="utf-8")]
        self.assertEqual(users, ["PlacementController.luau"])


if __name__ == "__main__":
    unittest.main()

