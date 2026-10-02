import re
import unittest

from tests._common import load_json


class CountryRegistryTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.registry = load_json("CountryRegistry.json")
        cls.countries = cls.registry["Countries"]

    def test_exactly_195(self):
        self.assertEqual(len(self.countries), 195)

    def test_no_duplicate_ids(self):
        ids = [c["Id"] for c in self.countries]
        self.assertEqual(len(ids), len(set(ids)))

    def test_no_duplicate_names(self):
        names = [c["DisplayNameEN"] for c in self.countries]
        self.assertEqual(len(names), len(set(names)))

    def test_required_fields(self):
        for c in self.countries:
            for field in ("Id", "DisplayNameEN", "DisplayNameRU", "Continent", "FlagAsset", "EmojiFallback"):
                self.assertIn(field, c, c.get("Id"))
            self.assertRegex(c["Id"], r"^[A-Z]{2}$")
            self.assertTrue(c["DisplayNameEN"])
            self.assertTrue(c["DisplayNameRU"])

    def test_holy_see_and_palestine(self):
        ids = {c["Id"] for c in self.countries}
        self.assertIn("VA", ids)
        self.assertIn("PS", ids)

    def test_continent_distribution(self):
        continents = self.registry["Continents"]
        self.assertEqual(continents, ["Europe", "Asia", "Africa", "North America", "South America", "Oceania"])
        counts = {k: 0 for k in continents}
        for c in self.countries:
            self.assertIn(c["Continent"], counts)
            counts[c["Continent"]] += 1
        self.assertEqual(counts, self.registry["ExpectedContinentCounts"])
        self.assertEqual(sum(counts.values()), 195)

    def test_flag_assets_never_invented(self):
        for c in self.countries:
            asset = c["FlagAsset"]
            self.assertTrue(asset == "" or re.match(r"^rbxassetid://\d+$", asset), c["Id"])

    def test_emoji_fallback_matches_iso(self):
        for c in self.countries:
            expected = "".join(chr(0x1F1E6 + ord(ch) - 65) for ch in c["Id"])
            self.assertEqual(c["EmojiFallback"], expected, c["Id"])

    def test_registry_matches_python_source(self):
        import sys
        from tests._common import ROOT
        sys.path.insert(0, str(ROOT / "tools"))
        import countries
        self.assertEqual(countries.country_registry(), self.registry)


if __name__ == "__main__":
    unittest.main()

