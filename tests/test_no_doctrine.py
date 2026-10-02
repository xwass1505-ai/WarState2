import json
import unittest

from tests._common import CONFIG, ROOT, SRC

WORD = "doc" + "trine"  # split so this test file does not match itself


def all_keys(value):
    if isinstance(value, dict):
        for k, v in value.items():
            yield k
            yield from all_keys(v)
    elif isinstance(value, list):
        for v in value:
            yield from all_keys(v)


class NoDoctrineTests(unittest.TestCase):
    def test_no_doctrine_config_fields(self):
        for path in CONFIG.glob("*.json"):
            data = json.loads(path.read_text(encoding="utf-8"))
            bad = [k for k in all_keys(data) if WORD in str(k).lower()]
            self.assertEqual(bad, [], path.name)

    def test_no_doctrine_in_game_code(self):
        offenders = []
        for path in SRC.rglob("*"):
            if path.is_file() and path.suffix in (".luau", ".lua", ".json"):
                if "Tests" in path.parts:
                    continue  # the runtime self-test checks for the word on purpose
                if WORD in path.read_text(encoding="utf-8").lower():
                    offenders.append(str(path.relative_to(ROOT)))
        self.assertEqual(offenders, [])


if __name__ == "__main__":
    unittest.main()

