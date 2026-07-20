from __future__ import annotations

import pathlib
import unittest

from common import ADDON, ROOT


class SC2ClientContractTests(unittest.TestCase):
    def test_collection_state_loads_before_catalog_and_bridge(self):
        toc = (ADDON / "SoloCollections.toc").read_text(encoding="utf-8")
        state = toc.index("Core\\CollectionState.lua")
        self.assertLess(state, toc.index("Core\\Catalog.lua"))
        self.assertLess(state, toc.index("Core\\Bridge.lua"))

    def test_sc1_and_sc2_have_separate_prefixes_and_request_tables(self):
        bridge = (ADDON / "Core/Bridge.lua").read_text(encoding="utf-8")
        self.assertIn('B.prefix = "SC1"', bridge)
        self.assertIn('B.sc2Prefix = "SC2"', bridge)
        self.assertIn("pendingModels", bridge)
        self.assertIn("sc2PendingActions", bridge)
        self.assertIn("B.ConnectSC2", bridge)
        self.assertIn("CS.HandleMessage", bridge)

    def test_state_machine_has_atomic_snapshot_and_revision_guards(self):
        state = (ADDON / "Core/CollectionState.lua").read_text(encoding="utf-8")
        for token in (
            '"Loading"',
            '"Ready"',
            '"Failed"',
            '"Mismatch"',
            "pendingTransfers",
            "queuedDeltas",
            "adler32Hex",
            "parseOwnedPayload",
            "commitSnapshot",
            "requestResync",
            "REVISION_GAP",
            "CHECKSUM_MISMATCH",
            "TRANSFER_TIMEOUT",
        ):
            self.assertIn(token, state)
        self.assertNotIn("SoloCollectionsDB.owned", state)
        self.assertNotIn("SC.db.owned", state)

    def test_catalog_overlays_authoritative_owned_state(self):
        catalog = (ADDON / "Core/Catalog.lua").read_text(encoding="utf-8")
        self.assertIn("CollectionState.ResolveOwned", catalog)
        self.assertIn("ownershipKnown", catalog)
        self.assertIn("collectionState", catalog)

    def test_mount_actions_submit_only_logical_collection_id(self):
        bridge = (ADDON / "Core/Bridge.lua").read_text(encoding="utf-8")
        catalog = (ADDON / "Core/Catalog.lua").read_text(encoding="utf-8")
        generated = (ADDON / "Data/Generated/Catalog.lua").read_text(encoding="utf-8")
        self.assertIn('B.RequestSC2Action(10, collectionId, "SUMMON", nil, callback)', bridge)
        self.assertNotIn('"SUMMON|" .. requestId', bridge)
        self.assertIn("getGeneratedMountSource", catalog)
        self.assertIn("displayCreatureId", generated)
        self.assertNotIn("spellId =", generated)
        self.assertNotIn("actionId =", generated)

    def test_companion_and_toy_actions_submit_only_logical_collection_id(self):
        bridge = (ADDON / "Core/Bridge.lua").read_text(encoding="utf-8")
        catalog = (ADDON / "Core/Catalog.lua").read_text(encoding="utf-8")
        generated = (ADDON / "Data/Generated/Catalog.lua").read_text(encoding="utf-8")
        self.assertIn('B.RequestSC2Action(11, collectionId, "SUMMON", nil, callback)', bridge)
        self.assertIn('B.RequestSC2Action(12, collectionId, "USE", target, callback)', bridge)
        self.assertIn("getGeneratedCompanionSource", catalog)
        self.assertIn("getGeneratedToySource", catalog)
        self.assertIn("displayCreatureId", generated)
        self.assertIn("displayItemId", generated)
        self.assertNotIn("sourceId =", generated)
        self.assertNotIn("actionId =", generated)

    def test_lua_state_harness_is_checked_in(self):
        harness = ROOT / "tools/collections/tests/lua/sc2_collection_state_harness.lua"
        self.assertTrue(harness.is_file())
        text = harness.read_text(encoding="utf-8")
        for token in ("out of order", "conflicting duplicate", "old nonce", "revision gap"):
            self.assertIn(token, text)


if __name__ == "__main__":
    unittest.main()
