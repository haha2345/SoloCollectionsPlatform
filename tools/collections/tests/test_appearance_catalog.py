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


if __name__ == "__main__":
    unittest.main()
