from __future__ import annotations

import re
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
HEADER = (ROOT / "src" / "Transmogrification.h").read_text(encoding="utf-8")
IMPLEMENTATION = (ROOT / "src" / "Transmogrification.cpp").read_text(encoding="utf-8")
SCRIPTS = (ROOT / "src" / "transmog_scripts.cpp").read_text(encoding="utf-8")
COMMANDS = (ROOT / "src" / "cs_transmog.cpp").read_text(encoding="utf-8")
APPEARANCE_HEADER = (ROOT / "src" / "Categories" / "Appearance" /
                     "SoloCollectionsAppearanceService.h").read_text(encoding="utf-8")
APPEARANCE_SERVICE = (ROOT / "src" / "Categories" / "Appearance" /
                      "SoloCollectionsAppearanceService.cpp").read_text(encoding="utf-8")
CORE = (ROOT / "src" / "SoloCollectionsCore.cpp").read_text(encoding="utf-8")


class AppearanceAuthorizationContractTests(unittest.TestCase):
    def test_only_safe_facade_is_publicly_callable(self):
        public_api = HEADER.split("private:", 1)[0]
        self.assertIn("TryApplyCollectedAppearance", public_api)
        self.assertNotIn("TransmogStrings Transmogrify(", public_api)
        self.assertNotIn("void PresetTransmog(", public_api)

        external_consumers = SCRIPTS + COMMANDS
        self.assertNotRegex(external_consumers, r"(?:sT|sTransmogrification)->Transmogrify\s*\(")
        self.assertNotRegex(external_consumers, r"(?:sT|sTransmogrification)->PresetTransmog\s*\(")

    def test_facade_rechecks_account_collection_and_exact_source(self):
        preflight = IMPLEMENTATION.split(
            "TransmogApplyResult Transmogrification::PreflightApply", 1
        )[1].split("TransmogApplyResult Transmogrification::CommitApplyPlan", 1)[0]

        self.assertIn("player->GetSession()->GetAccountId()", preflight)
        self.assertIn("GetAppearanceService().HasCollectedSource", preflight)
        self.assertIn("GetItemTemplate(request.SourceItemEntry)", preflight)
        self.assertIn("player->GetItemByEntry(request.SourceItemEntry)", preflight)
        self.assertLess(
            preflight.index("GetAppearanceService().HasCollectedSource"),
            preflight.index("plan.Appearances.push_back(prepared)"),
        )

    def test_facade_rechecks_npc_distance_session_and_portable_owner(self):
        self.assertIn("GetNPCIfCanInteractWith(interactionGuid", IMPLEMENTATION)
        self.assertIn("GetGossipMenu().GetSenderGUID() != interactionGuid", IMPLEMENTATION)
        self.assertIn("IsTransmogVendor(interaction->GetEntry())", IMPLEMENTATION)
        self.assertIn("summon->GetOwner() != player", IMPLEMENTATION)

    def test_gossip_vendor_and_presets_all_use_the_facade(self):
        calls = re.findall(r"GetAppearanceService\(\)\.TryApplyCollectedAppearance\s*\([^;]+;", SCRIPTS, re.DOTALL)
        self.assertEqual(1, len(calls))
        self.assertEqual(1, SCRIPTS.count("GetAppearanceService().TryApplyCollectedPreset("))
        self.assertIn("TransmogApplySource::Gossip", SCRIPTS)
        self.assertIn("TransmogApplySource::Vendor", SCRIPTS)
        self.assertIn("TransmogApplySource::Preset", IMPLEMENTATION)

    def test_missing_selection_cannot_default_to_equipment_slot_zero(self):
        indexed_access = "selectionCache[player->GetGUID()]"
        self.assertEqual(1, SCRIPTS.count(indexed_access))
        self.assertIn(f"{indexed_access} = action;", SCRIPTS)
        self.assertGreaterEqual(SCRIPTS.count("selectionCache.find(player->GetGUID())"), 3)


class TemplateSafetyContractTests(unittest.TestCase):
    def test_collection_listing_and_apply_do_not_create_temporary_items(self):
        all_sources = HEADER + IMPLEMENTATION + SCRIPTS + COMMANDS
        self.assertNotIn("Item::CreateItem", all_sources)
        self.assertNotIn("std::vector<Item*>", SCRIPTS)
        self.assertIn("std::vector<ItemTemplate const*>", SCRIPTS)
        self.assertIn("ItemTemplate const* SourceTemplate", HEADER)
        self.assertNotIn("TransmogStrings ApplyAppearance", HEADER)

    def test_store_hook_and_database_helpers_reject_null_items(self):
        hook = CORE.split("void OnPlayerAfterStoreOrEquipNewItem", 1)[1].split(
            "void OnPlayerEquip", 1
        )[0]
        self.assertIn("OnAppearanceItem(player, item", hook)
        item_helper = APPEARANCE_SERVICE.split("AppearanceService::OnItemAcquired", 1)[1].split(
            "AppearanceService::QueueGameMasterUnlock", 1
        )[0]
        self.assertIn("!player || !player->GetSession() || !item", item_helper)
        self.assertIn("if (!itemTemplate", item_helper)

    def test_quest_unlock_uses_only_the_item_actually_granted(self):
        quest_hook = CORE.split("void OnPlayerQuestRewardItem", 1)[1].split(
            "void OnPlayerAfterStoreOrEquipNewItem", 1
        )[0]
        self.assertIn("AppearanceUnlockTrigger::QuestReward", quest_hook)
        self.assertNotIn("RewardChoiceItemId", SCRIPTS)

    def test_item_links_mirror_images_and_portable_spell_are_null_safe(self):
        self.assertIn('return "(Unknown item: " + std::to_string(entry)', IMPLEMENTATION)
        self.assertIn("if (ItemTemplate const* sourceTemplate = sObjectMgr->GetItemTemplate(entry))", SCRIPTS)
        self.assertIn("PetEntry = 0;", IMPLEMENTATION)
        self.assertIn("Portable NPC spell", IMPLEMENTATION)


class AtomicApplyContractTests(unittest.TestCase):
    def test_preflight_checks_all_resources_without_mutating_them(self):
        preflight = IMPLEMENTATION.split(
            "TransmogApplyResult Transmogrification::PreflightApply", 1
        )[1].split("TransmogApplyResult Transmogrification::CommitApplyPlan", 1)[0]

        self.assertIn("LANG_TRANSMOG_MISSING_DEST_ITEM", preflight)
        self.assertIn("LANG_TRANSMOG_NOT_ENOUGH_MONEY", preflight)
        self.assertIn("LANG_TRANSMOG_NOT_ENOUGH_TOKENS", preflight)
        self.assertIn("CanTransmogrifyItemWithItem", preflight)
        self.assertNotIn("DestroyItemCount", preflight)
        self.assertNotIn("ModifyMoney", preflight)
        self.assertNotIn("transaction->Append", preflight)

    def test_multi_slot_preset_is_preflighted_and_committed_once(self):
        single = IMPLEMENTATION.split(
            "TransmogApplyResult Transmogrification::TryApplyCollectedAppearance", 1
        )[1].split("TransmogApplyResult Transmogrification::TryApplyCollectedAppearances", 1)[0]
        multi = IMPLEMENTATION.split(
            "TransmogApplyResult Transmogrification::TryApplyCollectedAppearances", 1
        )[1].split("TransmogApplyResult Transmogrification::TryApplyCollectedPreset", 1)[0]
        preset = IMPLEMENTATION.split(
            "TransmogApplyResult Transmogrification::TryApplyCollectedPreset", 1
        )[1].split("#endif", 1)[0]
        self.assertIn("source == TransmogApplySource::Preset", single)
        self.assertIn("TryApplyCollectedAppearances", single)
        self.assertIn("PreflightApply(player, requests", multi)
        self.assertIn("CommitApplyPlan(player, plan)", multi)
        self.assertIn("TryApplyCollectedAppearances", preset)
        self.assertIn("TransmogApplySource::Preset, true", preset)
        self.assertEqual(1, SCRIPTS.count("TryApplyCollectedPreset("))
        self.assertNotRegex(SCRIPTS, r"for \([^)]*preset[^)]*\)[\s\S]{0,500}TryApplyCollectedAppearance")

    def test_database_success_precedes_cost_and_cache_mutation(self):
        commit = IMPLEMENTATION.split(
            "TransmogApplyResult Transmogrification::CommitApplyPlan", 1
        )[1].split("TransmogApplyResult Transmogrification::TryApplyCollectedAppearance", 1)[0]
        db_success = commit.index("callback.m_future.get()")
        self.assertLess(db_success, commit.index("DestroyItemCount"))
        self.assertLess(db_success, commit.index("ModifyMoney"))
        self.assertLess(db_success, commit.index("ApplyCommittedFakeEntry"))
        self.assertIn("LANG_TRANSMOG_DATABASE_ERROR", commit)
        self.assertIn("no resources or cache entries were changed", commit)

    def test_gossip_confirmation_does_not_precharge_money(self):
        gossip_menu = SCRIPTS.split(
            "void ShowTransmogItemsInGossipMenu", 1
        )[1].split("static std::vector<ItemTemplate const*> GetSpoofedVendorItems", 1)[0]
        self.assertIn("GetTransmogPriceText(price)", gossip_menu)
        self.assertIn("CommitApplyPlan owns all resource changes", gossip_menu)
        self.assertNotIn("lineEnd, price, false", gossip_menu)
        self.assertRegex(gossip_menu, r"lineEnd,\s*0,\s*false\)")

    def test_duplicate_slots_and_duplicate_appearance_are_rejected(self):
        preflight = IMPLEMENTATION.split(
            "TransmogApplyResult Transmogrification::PreflightApply", 1
        )[1].split("TransmogApplyResult Transmogrification::CommitApplyPlan", 1)[0]
        self.assertIn("requestedSlots.insert(request.Slot).second", preflight)
        self.assertIn("GetFakeEntry(targetItem->GetGUID()) == prepared.FakeEntry", preflight)

    def test_commit_failure_has_localized_reason(self):
        sql = (ROOT / "data" / "sql" / "db-world" /
               "zzzzz_2026_07_19_transmog_atomic_apply_error.sql").read_text(encoding="utf-8")
        self.assertIn("('mod-transmog', 81", sql)
        self.assertIn("未扣除任何费用", sql)

    def test_current_module_strings_run_after_legacy_base_sql(self):
        world_sql = ROOT / "data" / "sql" / "db-world"
        base_name = "trasm_world_texts.sql"
        legacy_name = "updates/2026_05_09_migrate_strings_to_module_string.sql"
        current_name = "zzzz_2026_05_09_migrate_strings_to_module_string.sql"
        error_name = "zzzzz_2026_07_19_transmog_atomic_apply_error.sql"
        self.assertTrue((world_sql / base_name).is_file())
        self.assertTrue((world_sql / legacy_name).is_file())
        self.assertTrue((world_sql / current_name).is_file())
        self.assertTrue((world_sql / error_name).is_file())
        self.assertNotEqual(
            (world_sql / legacy_name).read_bytes(),
            (world_sql / current_name).read_bytes(),
        )
        current_sql = (world_sql / current_name).read_text(encoding="utf-8")
        self.assertGreaterEqual(current_sql.count("`id` BETWEEN 1 AND 80"), 2)
        self.assertNotIn("WHERE `module` = 'mod-transmog';", current_sql)
        self.assertLess(base_name, current_name)
        self.assertLess(current_name, error_name)


class AtomicReloadContractTests(unittest.TestCase):
    def test_collection_cache_is_private_and_consumers_use_read_only_api(self):
        public_api = APPEARANCE_HEADER.split("private:", 1)[0]
        self.assertNotIn("LegacyCollectionCache _legacyCollections", public_api)
        self.assertIn("CollectedSources", public_api)
        self.assertIn("HasCollectedSource", public_api)
        self.assertNotIn("_legacyCollections", SCRIPTS)
        self.assertNotIn("_legacyCollections", COMMANDS)

    def test_collection_query_distinguishes_empty_success_from_failure(self):
        load = APPEARANCE_SERVICE.split("bool AppearanceService::LoadLegacyCollections()", 1)[1].split(
            "bool AppearanceService::HasCollectedSource", 1
        )[0]
        self.assertIn("SELECT 0 AS row_kind", load)
        self.assertIn("UNION ALL", load)
        self.assertIn("if (!result)", load)
        self.assertIn("AppearanceRepositoryHealth::QueryFailed", load)
        self.assertIn("previous_accounts", load)

    def test_successful_reload_replaces_snapshot_and_removes_revoked_rows(self):
        load = APPEARANCE_SERVICE.split("bool AppearanceService::LoadLegacyCollections()", 1)[1].split(
            "bool AppearanceService::HasCollectedSource", 1
        )[0]
        self.assertIn("LegacyCollectionCache refreshed", load)
        self.assertIn("refreshed[fields[1].Get<std::uint32_t>()].insert", load)
        self.assertIn("_legacyCollections.swap(refreshed)", load)
        self.assertLess(load.index("if (!result)"), load.index("_legacyCollections.swap(refreshed)"))
        self.assertIn("AppearanceRepositoryHealth::Healthy", load)

    def test_config_sets_and_plus_cache_swap_only_after_complete_parse(self):
        parser = IMPLEMENTATION.split("bool ParseItemEntrySet", 1)[1].split(
            "bool ParseMembershipLevels", 1
        )[0]
        config = IMPLEMENTATION.split("void Transmogrification::LoadConfig(bool reload)", 1)[1].split(
            "void Transmogrification::DeleteFakeFromDB", 1
        )[0]
        self.assertIn("Acore::StringTo<uint32>(token)", parser)
        self.assertIn("if (!entry)", parser)
        self.assertIn("std::set<uint32> refreshedAllowed", config)
        self.assertIn("Allowed.swap(refreshedAllowed)", config)
        self.assertIn("NotAllowed.swap(refreshedNotAllowed)", config)
        self.assertIn("transmogPlusData refreshedPlusData", config)
        self.assertIn("plusDataMap.swap(refreshedPlusData)", config)
        self.assertNotIn("plusDataMap.clear()", config)

    def test_reload_command_reports_failed_collection_refresh(self):
        reload_handler = COMMANDS.split("static bool HandleReloadTransmogConfig", 1)[1].split(
            "};", 1
        )[0]
        self.assertIn("sConfigMgr->LoadModulesConfigs(true, false)", reload_handler)
        self.assertLess(
            reload_handler.index("LoadModulesConfigs(true, false)"),
            reload_handler.index("sTransmogrification->LoadConfig(true)"),
        )
        self.assertIn("if (SoloCollections::GetAppearanceService().LoadLegacyCollections())", reload_handler)
        self.assertIn("previous cache retained", reload_handler)


if __name__ == "__main__":
    unittest.main()
