from __future__ import annotations

import importlib.util
import json
import tempfile
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[3]
PATH = ROOT / "tools/catalog/itemset_import.py"
SPEC = importlib.util.spec_from_file_location("solo_itemset_import_test", PATH)
importer = importlib.util.module_from_spec(SPEC)
assert SPEC and SPEC.loader
SPEC.loader.exec_module(importer)


class ItemSetImportTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.evidence = json.loads((ROOT / "catalog/review/sets/evidence.json").read_text(encoding="utf-8"))
        cls.review = json.loads((ROOT / "catalog/review/sets/review-policy.json").read_text(encoding="utf-8"))
        cls.model = json.loads((ROOT / "catalog/generated/normalized-itemsets.json").read_text(encoding="utf-8"))

    def test_exact_509_review_denominator_and_counters(self):
        counters = self.evidence["expectedCounters"]
        self.assertEqual(509, counters["rawRows"])
        self.assertEqual(509, counters["reviewUnits"])
        self.assertEqual(509, len(self.evidence["candidates"]))
        self.assertEqual(509, len(self.review["decisions"]))
        self.assertEqual({"accepted", "excluded", "deferred"}, {r["decision"] for r in self.review["decisions"]})

    def test_manual8_identity_and_priest_t1_fixture(self):
        for item_set_id, identity in importer.OLD_SET_IDENTITIES.items():
            row = next(value for value in self.model["sets"] if value["itemSetId"] == item_set_id)
            self.assertEqual(identity, (row["collectionId"], row["collectionKey"], row["ordinal"]))
        priest = next(value for value in self.model["sets"] if value["itemSetId"] == 202)
        self.assertEqual(8, len(priest["variants"][0]["members"]))

    def test_class_policy_modes_include_single_multi_and_any(self):
        modes = {row["classPolicy"]["mode"] for row in self.model["sets"]}
        self.assertIn("ANY", modes)
        self.assertIn("ALLOW_LIST", modes)
        lengths = {len(row["classPolicy"]["allowedClassKeys"]) for row in self.model["sets"]}
        self.assertIn(1, lengths)
        self.assertTrue(any(length > 1 for length in lengths))

    def test_mapping_hash_covers_authorization_and_variant_fields(self):
        original = self.model["mappingHash"]
        self.assertEqual(64, len(original))
        first = self.model["sets"][0]
        basis = [{
            "collectionId": first["collectionId"], "collectionKey": first["collectionKey"],
            "itemSetId": first["itemSetId"], "catalogLifecycle": first["catalogLifecycle"],
            "classPolicy": first["classPolicy"], "variants": first["variants"],
        }]
        baseline = importer.canonical_hash(basis)
        basis[0]["variants"][0]["variantOrdinal"] += 1
        self.assertNotEqual(baseline, importer.canonical_hash(basis))

    def test_manual8_profile_supports_runbook_flag_form(self):
        work = ROOT / "_work"
        work.mkdir(exist_ok=True)
        with tempfile.TemporaryDirectory(dir=work) as temp:
            output = Path(temp) / "manual8.normalized.json"
            self.assertEqual(0, importer.main([
                "--repo-root", str(ROOT),
                "--profile", "manual8",
                "--output", str(output),
            ]))
            self.assertEqual(
                (ROOT / "catalog/fixtures/sets/manual8.normalized.json").read_bytes(),
                output.read_bytes(),
            )


if __name__ == "__main__":
    unittest.main()
