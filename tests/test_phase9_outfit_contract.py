from __future__ import annotations

import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
SRC = ROOT / "src"
HEADER = (SRC / "SoloCollectionsOutfitService.h").read_text(encoding="utf-8")
SERVICE = (SRC / "SoloCollectionsOutfitService.cpp").read_text(encoding="utf-8")
SCRIPTS = (SRC / "transmog_scripts.cpp").read_text(encoding="utf-8")
TRANSMOG = (SRC / "Transmogrification.cpp").read_text(encoding="utf-8")


class OutfitContractTests(unittest.TestCase):
    def test_outfits_are_character_scoped_and_do_not_grant_collections(self):
        self.assertIn("ObjectGuid characterGuid", HEADER)
        self.assertIn("WHERE `Owner` = {}", SERVICE)
        self.assertIn("player->GetGUID().GetCounter()", SERVICE)
        self.assertNotIn("AccountId", HEADER + SERVICE)
        self.assertNotIn("TryUnlock", SERVICE)
        self.assertNotIn("sc_collection_unlock", SERVICE)
        self.assertNotIn("SetCollectionTypeId", SERVICE)

    def test_name_is_bounded_valid_utf8_and_sql_escaped(self):
        self.assertIn("OutfitNameMaxBytes = 48", HEADER)
        self.assertIn("requested.size() > OutfitNameMaxBytes", SERVICE)
        self.assertIn("value < 0x20 || value == 0x7f", SERVICE)
        self.assertIn("Utf8toWStr(requested, wide)", SERVICE)
        self.assertIn("CharacterDatabase.EscapeString(escapedName)", SERVICE)
        self.assertNotIn('name.find(\'"\')', SCRIPTS)
        self.assertNotRegex(SCRIPTS, r"REPLACE INTO `custom_transmogrification_sets`")

    def test_slot_count_bounds_duplicates_and_entries_fail_closed(self):
        self.assertIn("outfitId >= sTransmogrification->GetMaxSets()", SERVICE)
        self.assertIn("OutfitSlotMaxCount = 19", HEADER)
        self.assertIn("rawSlot >= EQUIPMENT_SLOT_END", SERVICE)
        self.assertIn("appearances.size() >= OutfitSlotMaxCount", SERVICE)
        self.assertIn("!appearances.emplace", SERVICE)
        self.assertIn("entry != HIDDEN_ITEM_ID && !sObjectMgr->GetItemTemplate(entry)", SERVICE)
        self.assertIn("outfit->Appearances.size() > OutfitSlotMaxCount", SERVICE)

    def test_save_and_delete_update_memory_only_after_confirmed_database_commit(self):
        save = SERVICE.split("TransmogApplyResult OutfitService::Save", 1)[1].split(
            "TransmogApplyResult OutfitService::Delete", 1
        )[0]
        delete = SERVICE.split("TransmogApplyResult OutfitService::Delete", 1)[1].split(
            "TransmogApplyResult OutfitService::Apply", 1
        )[0]
        self.assertLess(save.index("CommitOutfitTransaction"), save.index("outfits.emplace"))
        self.assertLess(save.index("CommitOutfitTransaction"), save.index("player->ModifyMoney"))
        self.assertLess(delete.index("CommitOutfitTransaction"), delete.index(".erase(outfitId)"))
        self.assertNotIn("WHERE Owner = {} AND PresetID = {}", SCRIPTS)
        self.assertEqual(1, SCRIPTS.count("DELETE FROM `custom_transmogrification_sets`"))
        self.assertIn("WHERE NOT EXISTS", SCRIPTS)

    def test_apply_uses_the_shared_atomic_preflight_pipeline(self):
        apply = SERVICE.split("TransmogApplyResult OutfitService::Apply", 1)[1]
        self.assertIn("GetAppearanceService().TryApplyCollectedAppearances", apply)
        self.assertIn("TransmogApplySource::Outfit, true", apply)
        self.assertIn("PreflightApply(player, requests", TRANSMOG)
        self.assertIn("CommitApplyPlan(player, plan)", TRANSMOG)
        self.assertIn("GetOutfitService().Apply(", SCRIPTS)

    def test_legacy_gossip_is_only_a_view_and_service_router(self):
        self.assertIn("GetOutfitService().List", SCRIPTS)
        self.assertIn("GetOutfitService().Find", SCRIPTS)
        self.assertIn("GetOutfitService().Save", SCRIPTS)
        self.assertIn("GetOutfitService().Delete", SCRIPTS)
        for forbidden in ("presetById", "presetByName", "TryApplyCollectedPreset"):
            self.assertNotIn(forbidden, SCRIPTS + TRANSMOG)


if __name__ == "__main__":
    unittest.main()
