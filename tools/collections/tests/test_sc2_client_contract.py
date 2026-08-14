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

    def test_sc1_and_sc2_have_separate_prefixes_and_preview_uses_sc2(self):
        bridge = (ADDON / "Core/Bridge.lua").read_text(encoding="utf-8")
        self.assertIn('B.prefix = "SC1"', bridge)
        self.assertIn('B.sc2Prefix = "SC2"', bridge)
        self.assertNotIn("pendingModels", bridge)
        self.assertNotIn("pendingPetModels", bridge)
        self.assertIn("sc2PendingActions", bridge)
        self.assertIn('B.RequestSC2Action(typeId, collectionId, "PREVIEW", nil, callback)', bridge)
        self.assertIn("B.ConnectSC2", bridge)
        self.assertIn("CS.HandleMessage", bridge)
        self.assertIn("local requestTimeout = 5", bridge)

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

    def test_client_accepts_the_versioned_asset_pack_token_limit(self):
        state = (ADDON / "Core/CollectionState.lua").read_text(encoding="utf-8")
        harness = ROOT / "tools/collections/tests/lua/sc2_collection_state_harness.lua"
        self.assertIn("local MAX_TOKEN_BYTES = 64", state)
        self.assertIn("#value <= MAX_TOKEN_BYTES", state)
        self.assertIn("round-two-stage8-weapon-presentation-v2", harness.read_text(encoding="utf-8"))

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
        self.assertIn("spellId =", generated)
        self.assertIn("faction =", generated)
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
        self.assertIn('status == "ACCEPTED" or status == "DISMISSED"', bridge)

    def test_lua_state_harness_is_checked_in(self):
        harness = ROOT / "tools/collections/tests/lua/sc2_collection_state_harness.lua"
        self.assertTrue(harness.is_file())
        text = harness.read_text(encoding="utf-8")
        for token in ("out of order", "conflicting duplicate", "old nonce", "revision gap"):
            self.assertIn(token, text)

    def test_schema_reserves_companion_favorite_as_an_internal_projection(self):
        schema = (ROOT / "protocol/sc2/schema.json").read_text(encoding="utf-8")
        docs = (ROOT / "docs/protocol/sc2-wire-v1.md").read_text(encoding="utf-8")
        self.assertIn('"17": "internal companion-favorite membership', schema)
        self.assertIn('"typeIds": [10, 11]', schema)
        self.assertIn("Types 16 and", docs)
        self.assertIn("17 are internal projections", docs)
        self.assertIn("never", docs)
        self.assertIn("collection totals or progress", docs)

    def test_collection_state_recognizes_companion_favorites_without_page_progress(self):
        state = (ADDON / "Core/CollectionState.lua").read_text(encoding="utf-8")
        self.assertIn('[17] = { typeId = 17, typeKey = "companion-favorite"', state)
        self.assertIn('mappingSourceKey = "companion"', state)
        category_keys = state[state.index("local CATEGORY_TYPE_KEYS"):state.index("local INTERNAL_PROJECTION_TYPES")]
        self.assertNotIn("companion-favorite", category_keys)


if __name__ == "__main__":
    unittest.main()
