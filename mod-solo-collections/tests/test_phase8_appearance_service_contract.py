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
        self.assertEqual(1, implementation.count("custom_unlocked_appearances"))
        self.assertNotIn("INSERT IGNORE INTO custom_unlocked_appearances", implementation)

    def test_appearance_provider_is_independently_registered(self):
        core = (SRC / "SoloCollectionsCore.cpp").read_text(encoding="utf-8")
        self.assertIn("AppearanceCollectionProvider", core)
        self.assertIn("AppearanceCollectionTypeId", core)
        self.assertIn('TypeKey = "appearance"', core)

    def test_canonical_catalog_rejects_reserved_hide_visual_ids(self):
        catalog = (APPEARANCE / "SoloCollectionsAppearanceCatalog.cpp").read_text(encoding="utf-8")
        self.assertIn("definition.Id.Value() < 10", catalog)

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
        self.assertIn("CanApplyCollectedVisual", service)

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

    def test_every_appearance_acquisition_path_converges_on_the_unified_queue(self):
        core = (SRC / "SoloCollectionsCore.cpp").read_text(encoding="utf-8")
        service = (APPEARANCE / "SoloCollectionsAppearanceService.cpp").read_text(encoding="utf-8")
        for hook in (
            "PLAYERHOOK_ON_EQUIP", "PLAYERHOOK_ON_LOOT_ITEM", "PLAYERHOOK_ON_CREATE_ITEM",
            "PLAYERHOOK_ON_STORE_NEW_ITEM", "PLAYERHOOK_ON_QUEST_REWARD_ITEM",
            "PLAYERHOOK_ON_AFTER_STORE_OR_EQUIP_NEW_ITEM", "PLAYERHOOK_ON_GROUP_ROLL_REWARD_ITEM",
        ):
            self.assertIn(hook, core)
        for trigger in (
            "Equipment", "Loot", "Craft", "QuestReward", "InventoryStore", "Vendor", "GroupRoll",
        ):
            self.assertIn(f"AppearanceUnlockTrigger::{trigger}", core)
        self.assertIn("mail,", core)
        self.assertIn("trade,", core)
        self.assertIn("auction,", core)
        self.assertIn("buyback,", core)
        self.assertIn("GetAccountCollectionService().TryUnlock", service)
        self.assertIn("AdvanceQueuedUnlocks", service)

    def test_binding_policy_and_low_frequency_reconcile_are_explicit(self):
        service = (APPEARANCE / "SoloCollectionsAppearanceService.cpp").read_text(encoding="utf-8")
        self.assertIn("ITEM_FIELD_FLAG_REFUNDABLE", service)
        self.assertIn("ITEM_FIELD_FLAG_BOP_TRADEABLE", service)
        self.assertIn("GetAllowTradeable", service)
        self.assertIn("BIND_WHEN_PICKED_UP", service)
        self.assertIn("InventoryReconcileIntervalMs = 5000", service)
        self.assertIn("ScanHistoricalInventory", service)

    def test_only_the_reward_actually_granted_can_unlock_and_gm_uses_unified_queue(self):
        core = (SRC / "SoloCollectionsCore.cpp").read_text(encoding="utf-8")
        legacy_scripts = (SRC / "transmog_scripts.cpp").read_text(encoding="utf-8")
        gm_commands = (SRC / "cs_transmog.cpp").read_text(encoding="utf-8")
        self.assertIn("OnPlayerQuestRewardItem", core)
        self.assertNotIn("RewardChoiceItemId", legacy_scripts)
        self.assertNotIn("TryUnlockLegacy", legacy_scripts + gm_commands)
        self.assertIn("QueueGameMasterUnlock", gm_commands)

    def test_legacy_appearance_table_has_no_production_writer(self):
        production = "\n".join(
            path.read_text(encoding="utf-8", errors="replace")
            for path in SRC.rglob("*") if path.suffix in {".cpp", ".h"}
        )
        self.assertNotIn("INSERT IGNORE INTO custom_unlocked_appearances", production)

    def test_sc2_apply_resolves_the_owned_source_on_the_server(self):
        protocol = (SRC / "SoloCollectionsProtocolScript.cpp").read_text(encoding="utf-8")
        transmog_header = (SRC / "Transmogrification.h").read_text(encoding="utf-8")
        transmog = (SRC / "Transmogrification.cpp").read_text(encoding="utf-8")
        self.assertIn("AppearanceCollectionTypeId.Value()", protocol)
        self.assertIn('request.ActionId != "APPLY"', protocol)
        self.assertIn("TryApplyCanonicalAppearance", protocol)
        self.assertIn("TransmogApplySource::Addon", protocol)
        self.assertIn("Addon", transmog_header)
        self.assertIn("SC2 authenticates an AddOn action", transmog)
        self.assertNotIn("sourceItemId", protocol.split("request.TypeId == AppearanceCollectionTypeId.Value()", 1)[1])


if __name__ == "__main__":
    unittest.main()
