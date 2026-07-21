from __future__ import annotations

import csv
import json
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[3]
CATALOG = ROOT / "catalog" / "generated" / "appearance-sources.json"


class CanonicalAppearanceCatalogTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.data = json.loads(CATALOG.read_text(encoding="utf-8"))
        cls.groups = [row for row in cls.data["groups"] if row["lifecycle"] == "active"]

    def test_full_wotlk_catalog_is_canonical_and_source_complete(self):
        self.assertEqual(18190, len(self.groups))
        self.assertEqual(27082, sum(len(row["sourceItemIds"]) for row in self.groups))
        self.assertEqual(27082, len({item for row in self.groups for item in row["sourceItemIds"]}))
        self.assertEqual(64, len(self.data["mappingHash"]))

    def test_group_signature_includes_display_slot_and_compatibility_family(self):
        signatures = {
            (row["displayId"], row["slotFamily"], row["compatibilityFamily"])
            for row in self.groups
        }
        self.assertEqual(len(self.groups), len(signatures))
        display_families = {}
        for row in self.groups:
            display_families.setdefault(row["displayId"], set()).add(
                (row["slotFamily"], row["compatibilityFamily"])
            )
        self.assertTrue(any(len(families) > 1 for families in display_families.values()))

    def test_source_csv_keeps_one_row_per_canonical_group_and_traceable_aliases(self):
        with (ROOT / "catalog" / "source" / "collections" / "appearances.csv").open(
            encoding="utf-8", newline=""
        ) as handle:
            rows = list(csv.DictReader(handle))
        active = [row for row in rows if row["lifecycle"] == "active"]
        self.assertEqual(len(self.groups), len(active))
        self.assertTrue(all("item:" in row["aliases"] for row in active))
        self.assertTrue(all("slot:" in row["aliases"] and "compat:" in row["aliases"] for row in active))

    def test_client_uses_generated_canonical_rows_instead_of_demo_duplicates(self):
        source = (ROOT / "addon" / "SoloCollections" / "Core" / "Catalog.lua").read_text(encoding="utf-8")
        self.assertIn("getGeneratedAppearanceSource", source)
        self.assertIn('collection.typeKey == "appearance"', source)
        self.assertIn('string.match(alias, "^item:(%d+)$")', source)

    def test_client_submits_only_canonical_id_and_equipment_slot_for_apply(self):
        bridge = (ROOT / "addon" / "SoloCollections" / "Core" / "Bridge.lua").read_text(encoding="utf-8")
        wardrobe = (ROOT / "addon" / "SoloCollections" / "UI" / "Wardrobe.lua").read_text(encoding="utf-8")
        self.assertIn("function B.ApplyAppearance(collectionId, equipmentSlot, callback)", bridge)
        self.assertIn('B.RequestSC2Action(13, collectionId, "APPLY", equipmentSlot + 1', bridge)
        self.assertNotIn("sourceItemId", bridge.split("function B.ApplyAppearance", 1)[1])
        self.assertIn("EQUIPMENT_SLOT_BY_APPEARANCE_SLOT", wardrobe)
        self.assertIn("SC.Bridge.ApplyAppearance(record.id, equipmentSlot", wardrobe)
        self.assertIn("Shift + 左键", wardrobe)

    def test_verified_standalone_presentations_join_canonical_ids(self):
        report = json.loads(
            (ROOT / "catalog/generated/appearance-presentation-report.json").read_text(encoding="utf-8")
        )
        manifest = json.loads(
            (ROOT / "catalog/generated/catalog-manifest.json").read_text(encoding="utf-8")
        )
        self.assertEqual(21, report["presentationCount"])
        self.assertEqual(set(range(40000, 40021)), {
            row["syntheticDisplayId"] for row in report["entries"]
        })
        canonical = {
            row["collectionId"]: row for row in manifest["collections"]
            if row["typeKey"] == "appearance"
        }
        for row in report["entries"]:
            projected = canonical[row["appearanceId"]]
            self.assertEqual("STANDALONE", projected["renderMode"])
            self.assertEqual(row["syntheticDisplayId"], projected["syntheticDisplayId"])
            self.assertEqual(row["modelPath"], projected["modelPath"])
            self.assertIn(row["sourceAlias"], projected["aliases"])

    def test_weapon_render_modes_are_explicit_and_fail_closed(self):
        manifest = json.loads(
            (ROOT / "catalog/generated/catalog-manifest.json").read_text(encoding="utf-8")
        )
        rows = [row for row in manifest["collections"] if row["typeKey"] == "appearance"]
        modes = {"BODY": 0, "STANDALONE": 0, "UNAVAILABLE": 0}
        for row in rows:
            modes[row["renderMode"]] += 1
            slots = {alias.split(":", 1)[1] for alias in row["aliases"] if alias.startswith("slot:")}
            if slots & {"MAINHAND", "OFFHAND"}:
                self.assertIn(row["renderMode"], {"STANDALONE", "UNAVAILABLE"})
            else:
                self.assertEqual("BODY", row["renderMode"])
        self.assertEqual(21, modes["STANDALONE"])
        self.assertGreater(modes["UNAVAILABLE"], 0)

    def test_renderer_uses_synthetic_display_only_at_adapter_boundary(self):
        wardrobe = (ROOT / "addon/SoloCollections/UI/Wardrobe.lua").read_text(encoding="utf-8")
        generated = (ROOT / "addon/SoloCollections/Data/Generated/Catalog.lua").read_text(encoding="utf-8")
        self.assertIn("DIRECT_DISPLAY_REQUEST_BASE + record.syntheticDisplayId", wardrobe)
        self.assertNotIn("creatureDisplayId", wardrobe)
        self.assertNotIn("creatureDisplayId", generated)
        self.assertIn('unavailableText:SetText("独立模型资源尚未生成")', wardrobe)


if __name__ == "__main__":
    unittest.main()
