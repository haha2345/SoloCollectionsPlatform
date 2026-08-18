from __future__ import annotations

import json
import unittest

from common import ADDON, ROOT, read_text


class IdentityRegistryContractTests(unittest.TestCase):
    def test_generated_identity_data_matches_canonical_source(self):
        source_classes = json.loads((ROOT / "catalog/source/classes.json").read_text(encoding="utf-8"))["entries"]
        source_races = json.loads((ROOT / "catalog/source/races.json").read_text(encoding="utf-8"))["entries"]
        generated = read_text(ADDON / "Data/Generated/IdentityRegistry.lua")
        for entry in source_classes:
            self.assertIn(f'logicalClassId = {entry["logicalClassId"]}', generated)
            self.assertIn(f'runtimeClassId = {entry["runtimeClassId"]}', generated)
            self.assertIn(f'classKey = "{entry["classKey"]}"', generated)
        for entry in source_races:
            self.assertIn(f'logicalRaceId = {entry["logicalRaceId"]}', generated)
            self.assertIn(f'runtimeRaceId = {entry["runtimeRaceId"]}', generated)

    def test_registry_returns_unknown_instead_of_default_identity(self):
        registry = read_text(ADDON / "Core/IdentityRegistry.lua")
        self.assertIn('reason = "UNKNOWN_IDENTITY"', registry)
        self.assertIn('unknown("class", runtimeId)', registry)
        self.assertIn('unknown("race", runtimeId)', registry)
        self.assertNotIn('or classesByKey["warrior"]', registry)
        self.assertNotIn('or racesByKey["human"]', registry)

    def test_synthetic_race_can_use_global_camera_fallback(self):
        registry = read_text(ADDON / "Core/IdentityRegistry.lua")
        self.assertIn('cameraProfile = "global"', registry)
        self.assertIn('return entry.cameraProfile or "global"', registry)

    def test_race_presentation_is_versioned_and_missing_assets_fail_closed(self):
        generated = read_text(ADDON / "Data/Generated/IdentityRegistry.lua")
        registry = read_text(ADDON / "Core/IdentityRegistry.lua")
        for field in ("appearanceOverrideProfile", "clientAssetVersion", "modelProfile"):
            self.assertIn(field, generated)
        for reason in (
            "ASSET_VERSION_MISMATCH",
            "MODEL_MISSING",
            "TEXTURE_MISSING",
        ):
            self.assertIn(reason, registry)
        self.assertIn("resources.modelAvailable ~= true", registry)
        self.assertIn("resources.textureAvailable ~= true", registry)
        self.assertIn("previewEnabled = false", registry)
        self.assertIn("actionEnabled = false", registry)

    def test_consumers_use_registry_instead_of_hardcoded_class_tables(self):
        catalog = read_text(ADDON / "Core/Catalog.lua")
        bootstrap = read_text(ADDON / "Core/Bootstrap.lua")
        wardrobe = read_text(ADDON / "UI/Wardrobe.lua")
        self.assertIn("SC.IdentityRegistry.GetLegacyClassBit", catalog)
        self.assertNotIn("local CLASS_BITS =", catalog)
        self.assertIn("SC.IdentityRegistry.GetValidClassTokens()", bootstrap)
        self.assertIn("Identity.GetClassFilterOptions()", wardrobe)
        self.assertIn("Identity.GetWeaponTypes(slot)", wardrobe)
        self.assertNotIn("local CLASS_WEAPON_TYPES =", wardrobe)


if __name__ == "__main__":
    unittest.main()
