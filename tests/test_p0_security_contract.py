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
        )[1].split("TransmogStrings Transmogrification::Transmogrify", 1)[0]

        self.assertIn("session->GetAccountId()", facade)
        self.assertIn("HasCollectedAppearance(session->GetAccountId(), sourceItemEntry)", facade)
        self.assertIn("GetItemTemplate(sourceItemEntry)", facade)
        self.assertIn("player->GetItemByEntry(sourceItemEntry)", facade)
        self.assertLess(
            facade.index("HasCollectedAppearance(session->GetAccountId(), sourceItemEntry)"),
            facade.index("return Transmogrify(player, sourceItemEntry"),
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


if __name__ == "__main__":
    unittest.main()
