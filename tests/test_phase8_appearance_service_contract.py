from __future__ import annotations

import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
SRC = ROOT / "src"
APPEARANCE = SRC / "Categories" / "Appearance"


class AppearanceServiceContractTests(unittest.TestCase):
    def test_account_service_is_the_unified_state_and_mutation_boundary(self):
        header = (SRC / "SoloCollectionsAccountService.h").read_text(encoding="utf-8")
        implementation = (SRC / "SoloCollectionsAccountService.cpp").read_text(encoding="utf-8")
        self.assertIn("CollectionResult Evaluate", header)
        self.assertIn("MutationStartResult TryUnlock", header)
        self.assertIn("GetAccountCollectionCache().IsOwned", implementation)
        self.assertIn("GetAccountCollectionStore().BeginMutation", implementation)

    def test_transmog_consumers_use_appearance_facade(self):
        scripts = (SRC / "transmog_scripts.cpp").read_text(encoding="utf-8")
        commands = (SRC / "cs_transmog.cpp").read_text(encoding="utf-8")
        transmog = (SRC / "Transmogrification.cpp").read_text(encoding="utf-8")
        for consumer in (scripts, commands):
            self.assertIn("GetAppearanceService()", consumer)
            self.assertNotIn("AddCollectedAppearance", consumer)
            self.assertNotIn("GetCollectedAppearances", consumer)
            self.assertNotIn("HasCollectedAppearance", consumer)
            self.assertNotIn("INSERT INTO custom_unlocked_appearances", consumer)
        self.assertIn("GetAppearanceService().HasCollectedSource", transmog)

    def test_legacy_repository_is_private_atomic_and_transitional(self):
        header = (APPEARANCE / "SoloCollectionsAppearanceService.h").read_text(encoding="utf-8")
        implementation = (APPEARANCE / "SoloCollectionsAppearanceService.cpp").read_text(encoding="utf-8")
        self.assertIn("LegacyCollectionCache _legacyCollections", header.split("private:", 1)[1])
        self.assertIn("std::scoped_lock", implementation)
        self.assertIn("_legacyCollections.swap(refreshed)", implementation)
        self.assertEqual(2, implementation.count("custom_unlocked_appearances"))

    def test_appearance_provider_is_independently_registered(self):
        core = (SRC / "SoloCollectionsCore.cpp").read_text(encoding="utf-8")
        self.assertIn("AppearanceCollectionProvider", core)
        self.assertIn("AppearanceCollectionTypeId", core)
        self.assertIn('TypeKey = "appearance"', core)

    def test_canonical_catalog_maps_every_source_once_and_selects_server_side(self):
        catalog = (APPEARANCE / "SoloCollectionsAppearanceCatalog.cpp").read_text(encoding="utf-8")
        service = (APPEARANCE / "SoloCollectionsAppearanceService.cpp").read_text(encoding="utf-8")
        generated = (SRC / "generated" / "SoloCollectionsAppearanceCatalog.inc").read_text(encoding="utf-8")
        self.assertIn("static constexpr GeneratedAppearanceGroup GeneratedAppearanceGroups[]", generated)
        self.assertEqual(18190, generated.count("\n    { "))
        self.assertIn("generated.SourceOffset", catalog)
        self.assertIn("generated.SourceCount", catalog)
        self.assertIn("_bySource.emplace(sourceItemId, index)", catalog)
        self.assertIn("GetAppearanceCatalog().FindBySource", service)
        self.assertIn("GetAccountCollectionService().Evaluate", service)
        self.assertIn("ResolveOwnedSource", service)
        self.assertIn("CanTransmogrifyItemWithItem", service)

    def test_same_display_is_partitioned_by_slot_and_compatibility_family(self):
        data = __import__("json").loads(
            (ROOT / "data" / "generated" / "solo_collections_appearance_sources.json").read_text(encoding="utf-8")
        )
        groups = [row for row in data["groups"] if row["lifecycle"] == "active"]
        signatures = {(row["displayId"], row["slotFamily"], row["compatibilityFamily"]) for row in groups}
        self.assertEqual(len(groups), len(signatures))
        by_display = {}
        for row in groups:
            by_display.setdefault(row["displayId"], set()).add((row["slotFamily"], row["compatibilityFamily"]))
        self.assertTrue(any(len(families) > 1 for families in by_display.values()))

    def test_legacy_migration_is_marker_guarded_idempotent_and_keeps_source_table(self):
        service = (APPEARANCE / "SoloCollectionsAppearanceService.cpp").read_text(encoding="utf-8")
        store_header = (SRC / "SoloCollectionsAccountStore.h").read_text(encoding="utf-8")
        store = (SRC / "SoloCollectionsAccountStore.cpp").read_text(encoding="utf-8")
        self.assertIn("AppearanceMigrationId = 3", service)
        self.assertIn("MigrationMarkerRequest::Source::LegacyAppearance", service)
        self.assertIn("CheckMigrationMarker", service)
        self.assertIn("CompleteMigrationMarker", service)
        self.assertIn("GetAccountCollectionService().TryUnlock", service)
        self.assertIn("event=migration_reconcile", service)
        self.assertIn("ExpectedCanonicalGroups", service)
        self.assertIn("LegacyAppearance = 2", store_header)
        self.assertIn("SELECT 1 AS row_kind, item_template_id AS value FROM custom_unlocked_appearances", store)
        self.assertNotIn("DROP TABLE", service + store)
        self.assertNotIn("DELETE FROM custom_unlocked_appearances", service + store)

    def test_dry_run_reports_every_required_migration_bucket_without_writes(self):
        service = (APPEARANCE / "SoloCollectionsAppearanceService.cpp").read_text(encoding="utf-8")
        commands = (SRC / "SoloCollectionsCommands.cpp").read_text(encoding="utf-8")
        for field in (
            "ValidSources", "CanonicalGroups", "MergedSources", "UnknownSources",
            "DisabledSources", "MissingTemplates", "Conflicts",
        ):
            self.assertIn(field, service)
        self.assertIn("BuildMigrationDryRun", commands)
        self.assertIn("writes=0", commands)
        self.assertIn("missing_template", commands)


if __name__ == "__main__":
    unittest.main()
