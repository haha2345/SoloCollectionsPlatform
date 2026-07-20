from __future__ import annotations

import pathlib
import unittest


ROOT = pathlib.Path(__file__).resolve().parents[1]
HEADER = (ROOT / "src/SoloCollectionsEligibility.h").read_text(encoding="utf-8")
SOURCE = (ROOT / "src/SoloCollectionsEligibility.cpp").read_text(encoding="utf-8")
NATIVE = (ROOT / "tests/native/SoloCollectionsDomainTests.cpp").read_text(encoding="utf-8")


class SyntheticClassContractTests(unittest.TestCase):
    def test_registry_resolution_builds_capability_context_without_fallback(self):
        self.assertIn("LogicalClassId LogicalClass", HEADER)
        self.assertIn("BuildClassEligibilityContext", HEADER)
        self.assertIn("classIdentity.Identity->LogicalId", SOURCE)
        self.assertIn("classIdentity.Identity->Capabilities", SOURCE)
        self.assertIn("if (!classIdentity.IsKnown())", SOURCE)

    def test_synthetic_class_has_explicit_armor_weapon_and_appearance_capabilities(self):
        self.assertIn("TestSyntheticClassCapabilityAndCollectionContract", NATIVE)
        for capability in (
            "armor.cloth",
            "weapon.staff",
            "appearance.timeweave",
        ):
            self.assertIn(capability, NATIVE)
        self.assertIn("synthetic class inherited warrior capabilities", NATIVE)
        self.assertIn("missing synthetic policy did not fail closed", NATIVE)
        self.assertIn("unknown runtime class defaulted to warrior", NATIVE)

    def test_runtime_remap_preserves_logical_and_account_collection_ids(self):
        self.assertIn("InitialRuntimeClassId = 101", NATIVE)
        self.assertIn("RemappedRuntimeClassId = 202", NATIVE)
        self.assertIn("stableCatalogKey = Key(13, 260001)", NATIVE)
        self.assertIn("runtime remap changed account collection ownership", NATIVE)
        self.assertIn("runtime remap changed the stable catalog ID", NATIVE)


if __name__ == "__main__":
    unittest.main()
