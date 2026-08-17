from __future__ import annotations

import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
SRC = ROOT / "src"


class WardrobeProjectionContractTests(unittest.TestCase):
    def test_sql_defines_character_applied_and_account_outfit_tables(self):
        schema = (ROOT / "data/sql/db-characters/solo_collections_schema_v1.sql").read_text(encoding="utf-8")
        update = (ROOT / "data/sql/updates/char/2026_08_16_00_wardrobe_projections.sql").read_text(encoding="utf-8")
        for text in (schema, update):
            self.assertIn("CREATE TABLE IF NOT EXISTS `character_sc_transmog`", text)
            self.assertIn("CREATE TABLE IF NOT EXISTS `account_sc_outfit`", text)
            self.assertIn("`slot_13`", text)
            self.assertIn("`name_hex` VARCHAR(96)", text)

    def test_service_uses_server_cost_keys_and_single_transaction(self):
        service = (SRC / "SoloCollectionsTransmogService.cpp").read_text(encoding="utf-8")
        script = (SRC / "SoloCollectionsProtocolScript.cpp").read_text(encoding="utf-8")
        projection = (SRC / "SoloCollectionsTransmogProjection.h").read_text(encoding="utf-8")
        transmog = (SRC / "Transmogrification.cpp").read_text(encoding="utf-8")
        self.assertIn("-w1", projection)
        self.assertIn("GetSpecialPrice", service)
        self.assertIn("GetScaledCostModifier", service)
        self.assertIn("GetCopperCost", service)
        self.assertIn("SlotSellPriceCopper", service)
        self.assertIn("GetItemTemplate(*sourceItemId)", service)
        self.assertIn("prepared.SourceTemplate ? prepared.SourceTemplate : targetTemplate", transmog)
        self.assertNotIn("ApplyBaseCopper", service)
        self.assertNotIn("ApplySlotCopper", service)
        self.assertIn("TransmogApplySource::Wardrobe", service)
        self.assertIn("AppendAppliedSql", service)
        self.assertIn("COST_CHANGED", service)
        self.assertIn("INSUFFICIENT_FUNDS", service)
        self.assertIn("CharacterAppliedCollectionTypeId", script)
        self.assertIn("AccountOutfitCollectionTypeId", script)
        self.assertIn("extraStatements", transmog)
        self.assertIn("TransmogApplySource::Wardrobe", transmog)

    def test_config_template_documents_sell_price_copper(self):
        config = (ROOT / "conf/transmog.conf.dist").read_text(encoding="utf-8")
        self.assertIn("max(source SellPrice, 10000)", config)
        self.assertIn("Hide and clear are free", config)
        self.assertIn("# SoloCollections.Transmog.ApplyBaseCopper = 0", config)
        self.assertIn("# SoloCollections.Transmog.ApplySlotCopper = 0", config)
        self.assertIn("SoloCollections.Transmog.MixedArmor = any", config)

    def test_collected_visual_uses_wardrobe_mixed_armor_policy(self):
        header = (SRC / "Transmogrification.h").read_text(encoding="utf-8")
        transmog = (SRC / "Transmogrification.cpp").read_text(encoding="utf-8")
        service = (SRC / "SoloCollectionsTransmogService.cpp").read_text(encoding="utf-8")
        self.assertIn("MIXED_ARMOR_ANY", header)
        self.assertIn("CollectedMixedArmorPolicy", header)
        self.assertIn("SoloCollections.Transmog.MixedArmor", transmog)
        self.assertIn("ParseCollectedMixedArmor", transmog)
        self.assertIn("CollectedMixedArmorPolicy == MIXED_ARMOR_ANY", transmog)
        self.assertIn("The player is already wearing `target`", transmog)
        self.assertNotIn(
            "if (!SuitableForTransmogrification(player, target))\n        return false;",
            transmog,
        )
        self.assertIn("OwnedSourceFailureStatus", service)
        self.assertIn("return sawTemplate ? \"CLASS_RESTRICTED\" : \"SKILL_REQUIRED\"", service)


if __name__ == "__main__":
    unittest.main()
