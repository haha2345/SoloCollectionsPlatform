from __future__ import annotations

import csv
import hashlib
import importlib.util
import json
import os
import unittest
from pathlib import Path

from common import ROOT


TOOL = ROOT / "tools/catalog/companion_catalog.py"
SPEC = importlib.util.spec_from_file_location("companion_catalog", TOOL)
companion = importlib.util.module_from_spec(SPEC)
assert SPEC and SPEC.loader
SPEC.loader.exec_module(companion)

EVIDENCE = ROOT / "catalog/review/companions/evidence.json"
POLICY = ROOT / "catalog/review/companions/review-policy.json"
ACTIONS = ROOT / "catalog/source/companion_actions.json"
COLLECTIONS = ROOT / "catalog/source/collections/companions.csv"
IDS = ROOT / "catalog/ids.json"
PRESENTATIONS = ROOT / "catalog/source/creature_presentations.json"
VISIBILITY = ROOT / "catalog/review/companions/journal-visibility-policy.json"
DUPLICATES = ROOT / "catalog/review/companions/duplicate-audit.json"
JOURNAL_AUDIT = ROOT / "catalog/generated/companion-journal-audit.json"
JOURNAL_METADATA = ROOT / "catalog/source/companion_journal_metadata.json"
SOURCE_ZHCN = ROOT / "catalog/source/companion_source_zhCN.json"
TEXT_PROVENANCE = ROOT / "catalog/review/companions/text-provenance.json"
EVIDENCE_ROOT = Path(os.environ["SOLOCOLLECTIONS_EVIDENCE_ROOT"]) if os.environ.get("SOLOCOLLECTIONS_EVIDENCE_ROOT") else None


def read_json(path: Path):
    return json.loads(path.read_text(encoding="utf-8-sig"))


class CompanionCatalogTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.evidence = read_json(EVIDENCE)
        cls.policy = read_json(POLICY)
        cls.actions = read_json(ACTIONS)
        cls.visibility = read_json(VISIBILITY)
        cls.duplicates = read_json(DUPLICATES)
        cls.journal_audit = read_json(JOURNAL_AUDIT)
        cls.journal_metadata = read_json(JOURNAL_METADATA)
        cls.source_zhcn = read_json(SOURCE_ZHCN)
        cls.text_provenance = read_json(TEXT_PROVENANCE)
        with COLLECTIONS.open(encoding="utf-8-sig", newline="") as handle:
            cls.collections = list(csv.DictReader(handle))

    def test_fixed_evidence_matches_the_205_to_203_to_201_pipeline(self):
        self.assertEqual("SKILLLINE_778_EXACT_CREATURE_ENTRY", self.evidence["reviewMethod"])
        self.assertEqual(
            {
                "skillLineSpells": 205,
                "positiveSummonSpells": 203,
                "rejectedSkillLineSpells": 2,
                "candidates": 201,
                "resourceReadyCandidates": 201,
            },
            self.evidence["counts"],
        )
        basis = {
            "rejectedSkillLineSpells": self.evidence["rejectedSkillLineSpells"],
            "candidates": self.evidence["candidates"],
        }
        self.assertEqual(companion.canonical_hash(basis), self.evidence["candidateHash"])
        self.assertEqual(
            {17468, 17469},
            {row["spellId"] for row in self.evidence["rejectedSkillLineSpells"]},
        )

    def test_review_has_one_explicit_decision_for_every_candidate(self):
        self.assertEqual(self.evidence["candidateHash"], self.policy["candidateHash"])
        decisions = self.policy["decisions"]
        self.assertEqual(201, len(decisions))
        self.assertEqual(
            {row["creatureEntry"] for row in self.evidence["candidates"]},
            {row["creatureEntry"] for row in decisions},
        )
        self.assertEqual({"accepted"}, {row["decision"] for row in decisions})
        self.assertTrue(all(row["reasonCode"] for row in decisions))

    def test_evidence_records_world_relations_and_read_only_petdata_cross_references(self):
        spells = [spell for candidate in self.evidence["candidates"] for spell in candidate["spells"]]
        for key in (
            "itemSources", "questSources", "vendorSources", "lootSources", "achievementSources",
            "professionSources", "eventSources", "nameKeys", "referenceMatches",
        ):
            self.assertTrue(all(key in spell for spell in spells), key)
        self.assertGreater(sum(len(row["questSources"]) for row in spells), 0)
        self.assertGreater(sum(len(row["vendorSources"]) for row in spells), 0)
        self.assertGreater(sum(len(row["lootSources"]) for row in spells), 0)
        self.assertGreater(sum(len(row["achievementSources"]) for row in spells), 0)
        self.assertGreater(sum(len(row["professionSources"]) for row in spells), 0)
        self.assertGreater(sum(len(row["eventSources"]) for row in spells), 0)
        self.assertEqual(2, len(self.evidence["sources"]["petDataReferences"]))
        for candidate in self.evidence["candidates"]:
            for spell in candidate["spells"]:
                for reference in spell["referenceMatches"]:
                    self.assertEqual(candidate["creatureEntry"], reference["creatureEntry"])

    def test_visibility_audit_excludes_non_journal_classes_and_keeps_legacy_promotions(self):
        self.assertEqual(self.evidence["candidateHash"], self.visibility["candidateHash"])
        excluded = set(self.visibility["excludedClasses"])
        self.assertIn("TRANSPORT_OR_FLIGHT_POINT", excluded)
        self.assertIn("TEMPORARY_QUEST_FOLLOWER", excluded)
        self.assertIn("CLASS_GUARDIAN", excluded)
        visible = [row for row in self.visibility["entries"] if row["journalVisible"]]
        hidden = [row for row in self.visibility["entries"] if not row["journalVisible"]]
        self.assertEqual(201, len(visible))
        self.assertEqual({17468, 17469}, {row["spellId"] for row in hidden})
        self.assertTrue(all(row["actionable"] and row["randomEligible"] for row in visible))
        self.assertTrue(all(row["exclusionReason"] for row in hidden))
        promoted = [row for row in visible if row["sourceType"] in {6, 7, 8, 9}]
        self.assertTrue(promoted)
        self.assertTrue(all(row["acquisitionClass"] != "STANDARD" for row in promoted))

    def test_duplicate_audit_merges_unlock_aliases_into_one_collection_identity(self):
        self.assertEqual(2, self.duplicates["groupCount"])
        self.assertEqual(
            [([10712, 35157], 10712), ([24987, 25018], 25018)],
            [(row["mergedUnlockSpellIds"], row["canonicalSpellId"]) for row in self.duplicates["groups"]],
        )
        self.assertEqual(2, self.journal_audit["counts"]["duplicateMergedCount"])
        self.assertEqual(201, self.journal_audit["counts"]["visibleCount"])
        serialized = json.dumps(
            {"visibility": self.visibility, "audit": self.journal_audit}, ensure_ascii=False,
        )
        for forbidden in ("账号收藏", "服务端权威目录提供", "AI generated", "AI 生成"):
            self.assertNotIn(forbidden, serialized)

    def test_journal_metadata_has_exact_action_coverage_and_reviewed_zhcn_names(self):
        metadata = self.journal_metadata["entries"]
        actions = self.actions["entries"]
        self.assertEqual(
            {row["collectionId"] for row in actions},
            {row["collectionId"] for row in metadata},
        )
        action_by_id = {row["collectionId"]: row for row in actions}
        for row in metadata:
            action = action_by_id[row["collectionId"]]
            self.assertEqual(action["canonicalSpellId"], row["spellId"])
            self.assertEqual(action["canonicalSpellId"], row["canonicalActionSpellId"])
            self.assertTrue(row["journalNameZhCN"].strip())
            self.assertIn(row["sourceType"], range(12))
            self.assertTrue(row["journalVisible"])
            self.assertTrue(row["actionable"])
            self.assertTrue(row["randomEligible"])

    def test_reviewed_descriptions_are_traceable_and_gaps_remain_explicit(self):
        metadata = self.journal_metadata["entries"]
        provenance = {row["collectionId"]: row for row in self.text_provenance["entries"]}
        self.assertEqual(201, len(metadata))
        self.assertEqual(34, self.journal_audit["counts"]["zhCNDescriptionGapCount"])
        reviewed = [row for row in metadata if row["descriptionStatus"] == "OFFICIAL_ZHCN_BATTLE_PET_SPECIES"]
        missing = [row for row in metadata if row["descriptionStatus"] == "MISSING"]
        self.assertEqual(167, len(reviewed))
        self.assertEqual(34, len(missing))
        for row in metadata:
            description_provenance = provenance[row["collectionId"]]["description"]
            self.assertEqual(row["descriptionStatus"], description_provenance["status"])
            if row["descriptionStatus"] == "MISSING":
                self.assertEqual("", row["descriptionZhCN"])
                self.assertIsNone(description_provenance["reference"])
            else:
                self.assertTrue(row["descriptionZhCN"])
                self.assertEqual("BattlePetSpecies", description_provenance["reference"]["table"])
                self.assertEqual("7.3.5.26972", description_provenance["reference"]["build"])
        serialized = json.dumps(metadata, ensure_ascii=False)
        for forbidden in ("账号收藏", "服务端权威目录提供", "AI generated", "AI 生成"):
            self.assertNotIn(forbidden, serialized)

    def test_zhcn_sources_are_traceable_and_money_icons_stay_inline(self):
        sources = self.source_zhcn["entries"]
        self.assertEqual(201, len(sources))
        self.assertEqual(
            self.journal_audit["counts"]["zhCNSourceGapCount"],
            sum(row["sourceStatus"] == "MISSING" for row in sources),
        )
        for row in sources:
            self.assertIn(row["sourceStatus"], {"REVIEWED_ZHCN_WORLD", "REVIEWED_CATEGORY_CROSS_REFERENCE", "MISSING"})
            if "MoneyFrame" in row["source"]:
                self.assertIn("|TInterface\\MoneyFrame\\UI-GoldIcon.blp:0|t", row["source"])
                self.assertNotIn("UI-SilverIcon", row["source"])
                self.assertNotIn("UI-CopperIcon", row["source"])
            if row["sourceStatus"] != "MISSING":
                self.assertTrue(row["source"])
                self.assertTrue(row["provenanceRefs"] or row["sourceStatus"] == "REVIEWED_CATEGORY_CROSS_REFERENCE")

    def test_schema_v2_preserves_old_ids_and_indexes_all_unlock_variants(self):
        self.assertEqual(2, self.actions["schemaVersion"])
        self.assertEqual(201, len(self.actions["entries"]))
        by_id = {row["collectionId"]: row for row in self.actions["entries"]}
        self.assertEqual(list(range(100281, 100305)), sorted(by_id)[:24])
        unlocks = [spell for row in self.actions["entries"] for spell in row["unlockSpellIds"]]
        self.assertEqual(203, len(unlocks))
        self.assertEqual(len(unlocks), len(set(unlocks)))
        for row in self.actions["entries"]:
            self.assertIn(row["canonicalSpellId"], row["unlockSpellIds"])
            self.assertGreater(row["previewCreatureEntry"], 0)
            self.assertEqual("ACTIVE", row["catalogLifecycle"])
            self.assertEqual("public", row["uiLifecycle"])
        duplicates = [row for row in self.actions["entries"] if len(row["unlockSpellIds"]) > 1]
        self.assertEqual(
            [(7559, [10712, 35157], 10712), (15361, [24987, 25018], 25018)],
            [(row["previewCreatureEntry"], row["unlockSpellIds"], row["canonicalSpellId"]) for row in duplicates],
        )

    def test_new_ids_are_registry_allocated_append_only_and_do_not_reuse_toys(self):
        ids = read_json(IDS)["reservations"]["collections"]
        reservations = {row["key"]: row for row in ids}
        toy_ids = {row["id"] for row in ids if row["key"].startswith("toy.")}
        collection_ids = {int(row["collectionId"]) for row in self.collections}
        self.assertEqual(201, len(collection_ids))
        self.assertTrue(collection_ids.isdisjoint(toy_ids))
        new_ids = sorted(value for value in collection_ids if value > 100308)
        self.assertEqual(list(range(100309, 100486)), new_ids)
        for row in self.collections:
            reservation = reservations[row["collectionKey"]]
            self.assertEqual(int(row["collectionId"]), reservation["id"])
            self.assertEqual(int(row["ordinal"]), reservation["ordinal"])

    def test_every_active_companion_has_icon_template_display_and_presentation(self):
        candidates = {row["creatureEntry"]: row for row in self.evidence["candidates"]}
        presentations = {
            row["collectionId"]: row for row in read_json(PRESENTATIONS)["entries"]
            if row["typeKey"] == "companion"
        }
        self.assertEqual(201, len(presentations))
        for action in self.actions["entries"]:
            candidate = candidates[action["previewCreatureEntry"]]
            self.assertEqual("READY", candidate["resourceStatus"])
            self.assertTrue(candidate["creature"]["displayResourcesPresent"])
            presentation = presentations[action["collectionId"]]
            self.assertEqual("READY", presentation["presentationStatus"])
            self.assertTrue(presentation["iconTexture"].lower().startswith("interface\\icons\\"))
            self.assertEqual(action["previewCreatureEntry"], presentation["previewCreatureEntry"])

    def test_checked_in_outputs_are_deterministic(self):
        self.assertEqual(
            {"accepted": 201, "excluded": 0, "deferred": 0},
            companion.generate(ROOT, EVIDENCE, True),
        )

    def test_addon_projection_exposes_reviewed_companion_journal_fields(self):
        generated = (ROOT / "addon/SoloCollections/Data/Generated/Catalog.lua").read_text(encoding="utf-8")
        core = (ROOT / "addon/SoloCollections/Core/Catalog.lua").read_text(encoding="utf-8")
        self.assertGreaterEqual(generated.count('typeKey = "companion"'), 202)
        for field in ("journalVisible = true", "sourceText =", "sourceType =", "descriptionZhCN ="):
            self.assertIn(field, generated)
        companion_source = core[core.index("local function getGeneratedCompanionSource"):
                                core.index("local function getGeneratedToySource")]
        for forbidden in ("账号收藏", "服务端权威目录提供"):
            self.assertNotIn(forbidden, companion_source)

    @unittest.skipUnless(EVIDENCE_ROOT and EVIDENCE_ROOT.exists(), "named companion evidence pack is not configured")
    def test_named_evidence_pack_pins_review_outputs_and_dbc_hashes(self):
        self.assertRegex(companion.verify_review_pack(ROOT, EVIDENCE_ROOT), r"^[0-9a-f]{64}$")


if __name__ == "__main__":
    unittest.main()
