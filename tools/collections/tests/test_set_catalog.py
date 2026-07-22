from __future__ import annotations

import json
import os
import subprocess
import sys
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[3]
MODULE_ROOT = Path(os.environ.get("SOLOCOLLECTIONS_MODULE_ROOT", ROOT.parent / "mod-solo-collections"))
GENERATOR = ROOT / "tools/catalog/set_catalog.py"


class SetCatalogTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.model = json.loads((ROOT / "catalog/generated/normalized-itemsets.json").read_text(encoding="utf-8"))

    def test_checked_in_outputs_are_current(self):
        result = subprocess.run(
            [sys.executable, str(GENERATOR), "--module-root", str(MODULE_ROOT), "--check"],
            cwd=ROOT, text=True, capture_output=True,
        )
        self.assertEqual(0, result.returncode, result.stdout + result.stderr)

    def test_addon_projection_carries_presentation_without_touching_module_mapping_model(self):
        addon_model = json.loads((ROOT / "catalog/generated/set-catalog.json").read_text(encoding="utf-8"))
        self.assertEqual(3, addon_model["schemaVersion"])
        self.assertEqual(self.model["mappingHash"], addon_model["mappingHash"])
        self.assertNotEqual(self.model["presentationHash"], addon_model["presentationHash"])
        self.assertTrue(all("presentation" in row for row in addon_model["sets"]))
        addon_sets = (ROOT / "addon/SoloCollections/Data/Sets.lua").read_text(encoding="utf-8")
        self.assertIn("presentation =", addon_sets)

    def test_review_driven_catalog_and_priest_t1(self):
        self.assertEqual(465, len(self.model["sets"]))
        priest = next(row for row in self.model["sets"] if row["itemSetId"] == 202)
        self.assertEqual({"mode": "ALLOW_LIST", "allowedClassKeys": ["priest"]}, priest["classPolicy"])
        self.assertEqual(8, len(priest["variants"][0]["members"]))

    def test_variants_have_stable_ordinals_one_default_and_no_denominator_inflation(self):
        for definition in self.model["sets"]:
            variants = definition["variants"]
            self.assertEqual(1, sum(v["lifecycle"] == "ACTIVE" and v["isDefault"] for v in variants))
            self.assertEqual(len(variants), len({v["variantOrdinal"] for v in variants}))
            for variant in variants:
                slots = [m["slotKey"] for m in variant["members"] if m["required"]]
                self.assertEqual(len(slots), len(set(slots)))

    def test_client_derives_type14_from_type13_and_sends_variant_ordinal(self):
        catalog = (ROOT / "addon/SoloCollections/Core/Catalog.lua").read_text(encoding="utf-8")
        wardrobe = (ROOT / "addon/SoloCollections/UI/Wardrobe.lua").read_text(encoding="utf-8")
        sets = (ROOT / "addon/SoloCollections/Data/Sets.lua").read_text(encoding="utf-8")
        self.assertIn("IsOwnedByType(13, appearanceId)", catalog)
        self.assertIn("variant.variantOrdinal", wardrobe)
        self.assertIn("maxActiveSetSlots", wardrobe)
        self.assertNotIn("set_collected", catalog + wardrobe + sets)

    def test_sets_publish_apply_actions_using_logical_set_ids(self):
        manifest = json.loads((ROOT / "catalog/generated/catalog-manifest.json").read_text(encoding="utf-8"))
        rows = [row for row in manifest["collections"] if row["typeKey"] == "set"]
        self.assertEqual(465, len(rows))
        self.assertTrue(all(row["actionKind"] == "APPLY" and row["actionId"] == row["collectionId"] for row in rows))


if __name__ == "__main__":
    unittest.main()
