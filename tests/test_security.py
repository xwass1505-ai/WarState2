"""Static server-authority checks: plot ownership, placement, deletion, construction, resources."""
import re
import unittest

from tests._common import read


class ServerAuthorityTests(unittest.TestCase):
    def setUp(self):
        self.buildings = read("src/ServerScriptService/Systems/Buildings/BuildingService.luau")
        self.roads = read("src/ServerScriptService/Systems/Roads/RoadService.luau")
        self.world = read("src/ServerScriptService/Systems/World/WorldService.luau")
        self.country = read("src/ServerScriptService/Systems/Country/CountryService.luau")
        self.client = read("src/StarterPlayer/StarterPlayerScripts/Controllers/PlacementController.luau")

    def test_placement_uses_requesters_own_plot(self):
        for text in (self.buildings, self.roads):
            self.assertIn("services.WorldService.getBounds(player)", text)
            self.assertNotRegex(text, r"request\.(Plot|PlotIndex|Owner)")

    def test_server_revalidates_placement(self):
        self.assertIn("PlacementRules.validateBuilding(", self.buildings)
        self.assertIn("PlacementRules.validateRoadLine(", self.roads)

    def test_resource_checks_on_server(self):
        self.assertIn("ResourceService.canAfford", self.buildings)
        self.assertIn("ResourceService.canAfford", self.roads)

    def test_demolish_only_own_records(self):
        self.assertIn("country.Buildings[id]", self.buildings)
        self.assertIn('return false, "Not your building"', self.buildings)
        self.assertIn('return false, "Not your road"', self.roads)

    def test_plot_claim_rules(self):
        self.assertIn('return false, "This plot is already taken"', self.world)
        self.assertIn('return false, "You already own a plot"', self.world)
        self.assertIn("Plots.isValidIndex(index)", self.world)

    def test_no_automatic_plot_assignment(self):
        self.assertNotIn("WorldService.enter(", self.country)
        self.assertIn("needsPlot = true", self.country)
        self.assertIn("handleClaimPlot", self.country)

    def test_rate_limited_requests(self):
        self.assertIn("RequestCooldown", self.buildings)
        self.assertIn("RequestCooldown", self.roads)

    def test_client_only_requests(self):
        # The client never creates permanent world instances in Workspace.Buildings / Roads.
        self.assertNotRegex(self.client, r"Workspace\.Buildings\b.*Parent\s*=")
        self.assertIn("InvokeServer", self.client)

    def test_invalid_numbers_rejected(self):
        for text in (self.buildings, self.roads):
            self.assertIn("v == v", text, "NaN guard")


if __name__ == "__main__":
    unittest.main()

