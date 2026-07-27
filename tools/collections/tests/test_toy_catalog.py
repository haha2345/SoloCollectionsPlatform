from __future__ import annotations

import csv
import importlib.util
import json
import unittest
from pathlib import Path

from common import ROOT


TOOL = ROOT / "tools/catalog/toy_catalog.py"
SPEC = importlib.util.spec_from_file_location("toy_catalog", TOOL)
toy = importlib.util.module_from_spec(SPEC)
assert SPEC and SPEC.loader
SPEC.loader.exec_module(toy)

EVIDENCE = ROOT / "catalog/review/toys/evidence.json"
POLICY = ROOT / "catalog/review/toys/review-policy.json"
ACTIONS = ROOT / "catalog/source/toy_actions.json"
COLLECTIONS = ROOT / "catalog/source/collections/toys.csv"
IDS = ROOT / "catalog/ids.json"


def read_json(path: Path):
    return json.loads(path.read_text(encoding="utf-8-sig"))


class ToyCatalogTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.evidence = read_json(EVIDENCE)
        cls.policy = read_json(POLICY)
        cls.actions = read_json(ACTIONS)
        with COLLECTIONS.open(encoding="utf-8-sig", newline="") as handle:
            cls.collections = list(csv.DictReader(handle))

    def test_exact_legacy_pool_has_one_explicit_decision_per_item(self):
        self.assertEqual("LEGACY_36_ITEM_SPELL_EXACT_REVIEW", self.evidence["reviewMethod"])
        self.assertEqual(36, self.evidence["counts"]["legacyPrototypes"])
        self.assertEqual(36, self.evidence["counts"]["clientItemsPresent"])
        self.assertEqual(36, self.evidence["counts"]["clientDisplaysPresent"])
        self.assertEqual(toy.canonical_hash({"candidates": self.evidence["candidates"]}), self.evidence["candidateHash"])
        self.assertEqual(self.evidence["candidateHash"], self.policy["candidateHash"])
        self.assertEqual(
            {row["itemId"] for row in self.evidence["candidates"]},
            {row["itemId"] for row in self.policy["decisions"]},
        )
        self.assertEqual({"accepted": 9, "deferred": 27}, {
            value: sum(row["decision"] == value for row in self.policy["decisions"])
            for value in ("accepted", "deferred")
        })

    def test_schema_v2_is_complete_safe_and_preserves_existing_ids(self):
        self.assertEqual(2, self.actions["schemaVersion"])
        self.assertEqual(9, len(self.actions["entries"]))
        by_item = {row["itemId"]: row for row in self.actions["entries"]}
        self.assertEqual(
            {35275: 100305, 21713: 100306, 33223: 100307, 45984: 100308},
            {item: by_item[item]["collectionId"] for item in (35275, 21713, 33223, 45984)},
        )
        for row in self.actions["entries"]:
            self.assertEqual("ITEM_ACQUIRED", row["unlockSource"])
            self.assertIn(row["actionKind"], toy.ACTION_KINDS)
            self.assertIn(row["targetPolicy"], toy.TARGET_POLICIES)
            self.assertIn(row["cooldownScope"], toy.COOLDOWN_SCOPES)
            self.assertIn(row["replayPolicy"], toy.REPLAY_POLICIES)
            self.assertEqual("ACTIVE", row["catalogLifecycle"])
            self.assertFalse(row["consumesMaterial"])
            self.assertTrue(set(row["riskFlags"]) <= toy.RISK_FLAGS)
        self.assertEqual({"SPELL_SELF", "SPELL_TARGET", "ITEM_USE", "CUSTOM_HANDLER"},
                         {row["actionKind"] for row in self.actions["entries"]})

    def test_high_risk_decisions_are_deferred_and_formal_count_is_review_driven(self):
        high_risk = {"TELEPORT", "ECONOMY", "ITEM_CREATE", "MATERIAL"}
        accepted_items = {row["itemId"] for row in self.actions["entries"]}
        for decision in self.policy["decisions"]:
            if high_risk.intersection(decision.get("riskFlags", [])):
                self.assertEqual("deferred", decision["decision"])
                self.assertNotIn(decision["itemId"], accepted_items)
        self.assertEqual(len(self.actions["entries"]), len(self.collections))
        self.assertNotEqual(4, len(self.collections))
        self.assertNotEqual(36, len(self.collections))

    def test_registry_allocations_are_append_only_and_deterministic(self):
        reservations = {row["key"]: row for row in read_json(IDS)["reservations"]["collections"]}
        for row in self.collections:
            reservation = reservations[row["collectionKey"]]
            self.assertEqual(int(row["collectionId"]), reservation["id"])
            self.assertEqual(int(row["ordinal"]), reservation["ordinal"])
        self.assertEqual({"accepted": 9, "excluded": 0, "deferred": 27}, toy.generate(ROOT, EVIDENCE, True))


if __name__ == "__main__":
    unittest.main()
