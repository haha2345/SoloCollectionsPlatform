from __future__ import annotations

import copy
import importlib.util
import json
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[3]
PATH = ROOT / "tools/catalog/set_presentations.py"
SPEC = importlib.util.spec_from_file_location("solo_set_presentations_test", PATH)
presentations = importlib.util.module_from_spec(SPEC)
assert SPEC and SPEC.loader
SPEC.loader.exec_module(presentations)


class SetPresentationTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.evidence = json.loads((ROOT / "catalog/review/sets/evidence.json").read_text(encoding="utf-8"))
        cls.normalized = json.loads((ROOT / "catalog/generated/normalized-itemsets.json").read_text(encoding="utf-8"))
        cls.generated = json.loads((ROOT / "catalog/generated/set-presentations.json").read_text(encoding="utf-8"))

    def test_itemset_evidence_carries_level_and_quality_for_every_review_unit(self):
        self.assertEqual(3, self.evidence["schemaVersion"])
        self.assertEqual(509, len(self.evidence["candidates"]))
        decisions = {row["candidateKey"]: row["decision"] for row in json.loads(
            (ROOT / "catalog/review/sets/review-policy.json").read_text(encoding="utf-8")
        )["decisions"]}
        for candidate in self.evidence["candidates"]:
            self.assertIn("count", candidate["itemLevel"])
            self.assertIn("count", candidate["quality"])
            if decisions[candidate["candidateKey"]] == "accepted":
                self.assertGreater(candidate["itemLevel"]["count"], 0, candidate["candidateKey"])
                self.assertIsNotNone(candidate["itemLevel"]["median"])
                self.assertGreater(candidate["quality"]["count"], 0, candidate["candidateKey"])

    def test_review_projection_covers_all_509_rows_and_all_active_sets(self):
        review_rows = (ROOT / "catalog/generated/set-presentation-review.csv").read_text(encoding="utf-8-sig").splitlines()
        self.assertEqual(510, len(review_rows))
        self.assertEqual(self.normalized["mappingHash"], self.generated["mappingHash"])
        self.assertEqual(465, len(self.generated["presentations"]))
        self.assertEqual(
            {row["collectionId"] for row in self.generated["presentations"]},
            {row["collectionId"] for row in self.normalized["sets"]},
        )

    def test_reviewed_tier_order_is_independent_of_localized_names(self):
        by_item_set = {row["itemSetId"]: row for row in self.generated["presentations"]}
        self.assertGreater(by_item_set[883]["sortRank"]["tier"], by_item_set[843]["sortRank"]["tier"])
        self.assertGreater(by_item_set[843]["sortRank"]["tier"], by_item_set[820]["sortRank"]["tier"])
        self.assertGreater(by_item_set[820]["sortRank"]["tier"], by_item_set[787]["sortRank"]["tier"])
        self.assertEqual("UNKNOWN", by_item_set[1]["status"])
        self.assertEqual("NO_REVIEWED_ITEMSET_PRESENTATION_RULE", by_item_set[1]["reasonCode"])

    def test_generated_outputs_are_byte_stable_and_presentation_hash_is_separate(self):
        output, review_rows = presentations.build(ROOT)
        for path, content in presentations.outputs(ROOT, output, review_rows).items():
            self.assertEqual(content, path.read_bytes().replace(b"\r\n", b"\n"), path)
        changed = copy.deepcopy(output["presentations"])
        changed[0]["sortRank"]["tier"] += 1
        self.assertNotEqual(output["presentationHash"], presentations.canonical_hash(changed))
        self.assertEqual("2110892144adcdf60834c30785569ef38b5af7980cbdb62d684846cf44cc87cf",
                         self.normalized["mappingHash"])

    def test_addon_comparator_uses_rank_then_itemset_id(self):
        catalog = (ROOT / "addon/SoloCollections/Core/Catalog.lua").read_text(encoding="utf-8")
        self.assertIn("local function setPresentationLess", catalog)
        self.assertIn("table.sort(matches, setPresentationLess)", catalog)
        self.assertIn("leftItemSetId < rightItemSetId", catalog)
        self.assertNotIn("record.name <", catalog)


if __name__ == "__main__":
    unittest.main()
