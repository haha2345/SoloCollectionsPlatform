from __future__ import annotations

import re
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
HEADER = (ROOT / "src" / "Transmogrification.h").read_text(encoding="utf-8")
IMPLEMENTATION = (ROOT / "src" / "Transmogrification.cpp").read_text(encoding="utf-8")
SCRIPTS = (ROOT / "src" / "transmog_scripts.cpp").read_text(encoding="utf-8")
COMMANDS = (ROOT / "src" / "cs_transmog.cpp").read_text(encoding="utf-8")


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
        facade = IMPLEMENTATION.split(
            "TransmogStrings Transmogrification::TryApplyCollectedAppearance", 1
        )[1].split("TransmogStrings Transmogrification::ApplyAppearance", 1)[0]

        self.assertIn("session->GetAccountId()", facade)
        self.assertIn("HasCollectedAppearance(session->GetAccountId(), sourceItemEntry)", facade)
        self.assertIn("GetItemTemplate(sourceItemEntry)", facade)
        self.assertIn("player->GetItemByEntry(sourceItemEntry)", facade)
        self.assertLess(
            facade.index("HasCollectedAppearance(session->GetAccountId(), sourceItemEntry)"),
            facade.index("return ApplyAppearance(player, sourceTemplate"),
        )

    def test_facade_rechecks_npc_distance_session_and_portable_owner(self):
        self.assertIn("GetNPCIfCanInteractWith(interactionGuid", IMPLEMENTATION)
        self.assertIn("GetGossipMenu().GetSenderGUID() != interactionGuid", IMPLEMENTATION)
        self.assertIn("IsTransmogVendor(interaction->GetEntry())", IMPLEMENTATION)
        self.assertIn("summon->GetOwner() != player", IMPLEMENTATION)

    def test_gossip_vendor_and_presets_all_use_the_facade(self):
        calls = re.findall(r"TryApplyCollectedAppearance\s*\([^;]+;", SCRIPTS, re.DOTALL)
        self.assertGreaterEqual(len(calls), 2)
        self.assertIn("TransmogApplySource::Gossip", SCRIPTS)
        self.assertIn("TransmogApplySource::Vendor", SCRIPTS)
        self.assertIn("TransmogApplySource::Preset", SCRIPTS)

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
        self.assertIn("ApplyAppearance(player, sourceTemplate, nullptr", IMPLEMENTATION)

    def test_store_hook_and_database_helpers_reject_null_items(self):
        hook = SCRIPTS.split("void OnPlayerAfterStoreOrEquipNewItem", 1)[1].split(
            "void OnPlayerCompleteQuest", 1
        )[0]
        self.assertIn("if (!item)", hook)
        self.assertIn("Received a null item", hook)

        item_helper = SCRIPTS.split("void AddToDatabase(Player* player, Item* item)", 1)[1].split(
            "void AddToDatabase(Player* player, ItemTemplate const* itemTemplate)", 1
        )[0]
        self.assertIn("if (!player || !item)", item_helper)
        self.assertIn("if (!itemTemplate)", item_helper)

    def test_missing_quest_reward_templates_are_skipped_and_logged(self):
        quest_hook = SCRIPTS.split("void OnPlayerCompleteQuest", 1)[1].split(
            "void OnPlayerAfterSetVisibleItemSlot", 1
        )[0]
        self.assertGreaterEqual(quest_hook.count("if (itemTemplate)"), 2)
        self.assertIn("choice reward item", quest_hook)
        self.assertIn("reward item", quest_hook)

    def test_item_links_mirror_images_and_portable_spell_are_null_safe(self):
        self.assertIn('return "(Unknown item: " + std::to_string(entry)', IMPLEMENTATION)
        self.assertIn("if (ItemTemplate const* sourceTemplate = sObjectMgr->GetItemTemplate(entry))", SCRIPTS)
        self.assertIn("PetEntry = 0;", IMPLEMENTATION)
        self.assertIn("Portable NPC spell", IMPLEMENTATION)


if __name__ == "__main__":
    unittest.main()
