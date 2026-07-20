from __future__ import annotations

import importlib.util
import json
import subprocess
import sys
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[3]
MODULE_ROOT = ROOT.parent / "mod-solo-collections"
GENERATOR_PATH = ROOT / "tools" / "catalog" / "set_catalog.py"
SPEC = importlib.util.spec_from_file_location("solo_set_catalog", GENERATOR_PATH)
generator = importlib.util.module_from_spec(SPEC)
assert SPEC and SPEC.loader
SPEC.loader.exec_module(generator)


class SetCatalogTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.source = json.loads((ROOT / "catalog/source/sets.json").read_text(encoding="utf-8"))
        cls.appearances = json.loads(
            (ROOT / "catalog/generated/appearance-sources.json").read_text(encoding="utf-8")
        )
        cls.model = generator.build_model(cls.source, cls.appearances)

    def test_checked_in_outputs_are_current(self):
        result = subprocess.run(
            [sys.executable, str(GENERATOR_PATH), "--module-root", str(MODULE_ROOT), "--check"],
            cwd=ROOT, text=True, capture_output=True,
        )
        self.assertEqual(0, result.returncode, result.stdout + result.stderr)

    def test_real_sets_reference_canonical_appearances(self):
        self.assertEqual(8, len(self.model["sets"]))
        members = [member for row in self.model["sets"] for variant in row["variants"]
                   for member in variant["members"] if member["lifecycle"] == "active"]
        self.assertEqual(64, len(members))
        self.assertTrue(all(member["appearanceIds"] for member in members))
        self.assertTrue(all(variant["requiredCount"] == 8 for row in self.model["sets"]
                            for variant in row["variants"] if variant["lifecycle"] == "active"))

    def test_same_slot_alternatives_variants_and_disabled_members_do_not_inflate_denominator(self):
        synthetic = {
            "schemaVersion": 1,
            "sets": [{
                "collectionId": 999001, "collectionKey": "set.synthetic", "ordinal": 999001,
                "itemSetId": 999, "classToken": "WARRIOR",
                "name": {"enUS": "Synthetic", "zhCN": "合成"}, "icon": "icon",
                "variants": [
                    {"variantKey": "normal", "lifecycle": "active", "itemIds": [16802, 16806, 16799],
                     "disabledItemIds": [16799]},
                    {"variantKey": "heroic", "lifecycle": "disabled", "itemIds": [16802]},
                ],
            }],
        }
        model = generator.build_model(synthetic, self.appearances)
        normal = model["sets"][0]["variants"][0]
        self.assertEqual(1, normal["requiredCount"])
        waist = next(member for member in normal["members"] if member["slotKey"] == "WAIST")
        self.assertEqual(2, len(waist["appearanceIds"]))
        disabled = next(member for member in normal["members"] if member["lifecycle"] == "disabled")
        self.assertFalse(disabled["required"])

    def test_client_derives_completion_from_type_13_without_set_collected_state(self):
        catalog = (ROOT / "addon/SoloCollections/Core/Catalog.lua").read_text(encoding="utf-8")
        sets = (ROOT / "addon/SoloCollections/Data/Sets.lua").read_text(encoding="utf-8")
        self.assertIn("deriveSetState", catalog)
        self.assertIn("IsOwnedByType(13, appearanceId)", catalog)
        self.assertIn("collectedCount", catalog)
        self.assertNotIn("set_collected", catalog + sets)
        self.assertNotIn("collected = true", sets)

    def test_sets_publish_apply_actions_using_logical_set_ids(self):
        manifest = json.loads((ROOT / "catalog/generated/catalog-manifest.json").read_text(encoding="utf-8"))
        rows = [row for row in manifest["collections"] if row["typeKey"] == "set"]
        self.assertEqual(8, len(rows))
        self.assertTrue(all(row["actionKind"] == "APPLY" for row in rows))
        self.assertTrue(all(row["actionId"] == row["collectionId"] for row in rows))


if __name__ == "__main__":
    unittest.main()
