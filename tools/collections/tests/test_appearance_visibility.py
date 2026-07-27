from __future__ import annotations

import csv
import io
import json
import unittest

from common import ADDON, ROOT, read_text


class AppearanceVisibilityTests(unittest.TestCase):
    def setUp(self):
        self.catalog = json.loads(read_text(ROOT / "catalog/generated/catalog-manifest.json"))
        self.evidence = json.loads(read_text(ROOT / "catalog/review/appearances/visibility-evidence.json"))
        self.report = list(csv.DictReader(io.StringIO(read_text(ROOT / "catalog/generated/appearance-visibility-report.csv"))))

    def test_every_canonical_appearance_has_one_reviewed_ui_lifecycle(self):
        appearances = [entry for entry in self.catalog["collections"] if entry["typeKey"] == "appearance"]
        self.assertEqual(len(appearances), self.evidence["reviewUnitCount"])
        self.assertEqual(len(appearances), len(self.evidence["decisions"]))
        self.assertEqual(len(appearances), len(self.report))
        self.assertEqual(len({row["appearanceId"] for row in self.evidence["decisions"]}), len(appearances))
        self.assertEqual(
            {"public", "hidden_internal", "deprecated", "test", "unobtainable", "deferred"},
            set(self.evidence["counters"]),
        )

    def test_ui_lifecycle_is_independent_from_catalog_authorization(self):
        generated = {entry["collectionId"]: entry for entry in self.catalog["collections"] if entry["typeKey"] == "appearance"}
        for decision in self.evidence["decisions"]:
            entry = generated[decision["appearanceId"]]
            self.assertEqual(entry["catalogLifecycle"], decision["catalogLifecycle"])
            self.assertEqual(entry["uiLifecycle"], decision["uiLifecycle"])
        source = read_text(ROOT / "tools/catalog/generate_catalog.py")
        self.assertIn('"uiLifecycle",', source)
        self.assertIn("uiLifecycleDoesNotChangeCatalogAuthorization", read_text(ROOT / "catalog/review/appearances/visibility-policy.json"))

    def test_client_only_lists_public_appearances(self):
        catalog_lua = read_text(ADDON / "Core/Catalog.lua")
        self.assertIn('collection.uiLifecycle == "public"', catalog_lua)

    def test_risk_signals_are_evidence_not_identity_deletion(self):
        ids = {entry["appearanceId"] for entry in self.evidence["decisions"]}
        canonical = json.loads(read_text(ROOT / "catalog/generated/appearance-sources.json"))
        self.assertEqual(ids, {entry["appearanceId"] for entry in canonical["groups"]})
        self.assertTrue(any(entry["riskSignals"] for entry in self.evidence["decisions"]))


if __name__ == "__main__":
    unittest.main()
