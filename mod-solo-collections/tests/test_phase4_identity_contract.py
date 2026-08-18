from __future__ import annotations

import pathlib
import unittest


ROOT = pathlib.Path(__file__).resolve().parents[1]


class Phase4IdentityContractTests(unittest.TestCase):
    def test_registry_separates_logical_runtime_and_alias_lookups(self):
        header = (ROOT / "src/SoloCollectionsIdentity.h").read_text(encoding="utf-8")
        source = (ROOT / "src/SoloCollectionsIdentity.cpp").read_text(encoding="utf-8")
        for token in (
            "LogicalClassId LogicalId",
            "RuntimeClassId",
            "LogicalRaceId LogicalId",
            "RuntimeRaceId",
            "CompatibilityProfile",
            "ClientAssetProfile",
            "Capabilities",
            "Aliases",
            "IdentityResolutionCode::UnknownIdentity",
        ):
            self.assertIn(token, header + source)
        self.assertIn("NormalizeIdentityKey", source)

    def test_unknown_identity_has_no_human_or_warrior_default(self):
        source = (ROOT / "src/SoloCollectionsIdentity.cpp").read_text(encoding="utf-8")
        self.assertNotIn('ResolveClass("warrior")', source)
        self.assertNotIn('ResolveRace("human")', source)
        self.assertIn('return "global";', source)

    def test_generated_data_is_consumed_by_the_registry(self):
        source = (ROOT / "src/SoloCollectionsIdentity.cpp").read_text(encoding="utf-8")
        generated = (ROOT / "src/generated/SoloCollectionsIdentityData.inc").read_text(encoding="utf-8")
        self.assertIn('#include "generated/SoloCollectionsIdentityData.inc"', source)
        self.assertIn("LoadGeneratedClassIdentities", generated)
        self.assertIn("LoadGeneratedRaceIdentities", generated)
        self.assertIn("LogicalClassId{10}", generated)
        self.assertIn("LogicalRaceId{10}", generated)


if __name__ == "__main__":
    unittest.main()
