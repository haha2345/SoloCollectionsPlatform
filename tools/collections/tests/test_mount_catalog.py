from __future__ import annotations

import importlib.util
import json
import os
import shutil
import tempfile
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[3]
MODULE_ROOT = Path(os.environ.get("SOLOCOLLECTIONS_MODULE_ROOT", ROOT.parent / "mod-solo-collections"))
TOOL_PATH = ROOT / "tools/catalog/mount_catalog.py"
SPEC = importlib.util.spec_from_file_location("mount_catalog", TOOL_PATH)
assert SPEC and SPEC.loader
mount_catalog = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(mount_catalog)


class MountCatalogTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.evidence = json.loads((ROOT / "catalog/review/mounts/evidence.json").read_text(encoding="utf-8"))
        cls.policy = json.loads((ROOT / "catalog/review/mounts/review-policy.json").read_text(encoding="utf-8"))
        cls.actions = json.loads((ROOT / "catalog/source/mount_actions.json").read_text(encoding="utf-8"))

    def test_review_is_pinned_and_covers_every_candidate(self) -> None:
        basis = [{key: value for key, value in candidate.items() if key != "decision"} for candidate in self.evidence["candidates"]]
        self.assertEqual(self.evidence["candidateHash"], mount_catalog.canonical_hash(basis))
        self.assertEqual(self.policy["candidateHash"], self.evidence["candidateHash"])
        accepted, excluded = mount_catalog.review(self.evidence, self.policy)
        self.assertEqual(396, len(self.evidence["candidates"]))
        self.assertEqual(295, len(accepted))
        self.assertEqual(101, len(excluded))
        self.assertEqual(396, len(accepted) + len(excluded))

    def test_only_exact_creature_entries_are_grouped(self) -> None:
        self.assertEqual("EXACT_CREATURE_ENTRY_ONLY", self.actions["reviewMethod"])
        self.assertEqual(281, len(self.actions["collections"]))
        creature_groups = [tuple(entry["creatureIds"]) for entry in self.actions["collections"]]
        self.assertEqual(len(creature_groups), len(set(creature_groups)))
        name_groups: dict[str, set[tuple[int, ...]]] = {}
        for entry in self.actions["collections"]:
            name_groups.setdefault(entry["name_enUS"], set()).add(tuple(entry["creatureIds"]))
        self.assertTrue(any(len(creatures) > 1 for creatures in name_groups.values()), "test data must prove same-name mounts are not merged")

    def test_action_and_identity_mappings_are_unique_and_contiguous(self) -> None:
        entries = self.actions["collections"]
        self.assertEqual(list(range(len(entries))), [entry["ordinal"] for entry in entries])
        self.assertEqual(len(entries), len({entry["collectionId"] for entry in entries}))
        spell_ids = [spell for entry in entries for spell in entry["unlockSpellIds"]]
        self.assertEqual(295, len(spell_ids))
        self.assertEqual(len(spell_ids), len(set(spell_ids)))
        for entry in entries:
            variant_ids = [variant["spellId"] for variant in entry["actionVariants"]]
            self.assertEqual(sorted(entry["unlockSpellIds"]), sorted(variant_ids))
            self.assertIn(entry["canonicalSpellId"], variant_ids)

    def test_committed_generation_is_current(self) -> None:
        work_root = ROOT / "_work"
        work_root.mkdir(parents=True, exist_ok=True)
        with tempfile.TemporaryDirectory(dir=work_root) as temp:
            temp_root = Path(temp)
            ids = temp_root / "ids.json"
            shutil.copy2(ROOT / "catalog/ids.json", ids)
            parser = type("Args", (), {
                "evidence": ROOT / "catalog/review/mounts/evidence.json",
                "policy": ROOT / "catalog/review/mounts/review-policy.json",
                "ids": ids,
                "collections": temp_root / "mounts.csv",
                "actions": temp_root / "mount_actions.json",
                "candidates_report": temp_root / "mount-candidates.csv",
                "exclusions_report": temp_root / "mount-exclusions.csv",
                "review_report": temp_root / "review.md",
            })()
            mount_catalog.generate(parser)
            comparisons = {
                parser.collections: ROOT / "catalog/source/collections/mounts.csv",
                parser.actions: ROOT / "catalog/source/mount_actions.json",
                parser.candidates_report: ROOT / "catalog/generated/mount-candidates.csv",
                parser.exclusions_report: ROOT / "catalog/generated/mount-exclusions.csv",
                parser.review_report: ROOT / "docs/reports/2026-07-20-wotlk-mount-catalog-review.md",
                ids: ROOT / "catalog/ids.json",
            }
            for actual, expected in comparisons.items():
                self.assertEqual(expected.read_bytes(), actual.read_bytes(), str(expected))

    def test_client_and_server_catalog_hashes_match(self) -> None:
        local = json.loads((ROOT / "catalog/generated/catalog-manifest.json").read_text(encoding="utf-8"))
        server = json.loads((MODULE_ROOT / "data/generated/solo_collections_catalog_manifest.json").read_text(encoding="utf-8"))
        server_actions = json.loads((MODULE_ROOT / "data/generated/solo_collections_mount_actions.json").read_text(encoding="utf-8"))
        self.assertEqual(local["mappingHash"], server["mappingHash"])
        self.assertEqual(local["typeMappingHashes"]["mount"], server["typeMappingHashes"]["mount"])
        self.assertEqual(local["mountActions"], server_actions)


if __name__ == "__main__":
    unittest.main()
