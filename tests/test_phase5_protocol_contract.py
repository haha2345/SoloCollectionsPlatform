from __future__ import annotations

import pathlib
import unittest


ROOT = pathlib.Path(__file__).resolve().parents[1]


class Phase5ProtocolContractTests(unittest.TestCase):
    def test_protocol_layer_is_registered_and_core_independent(self):
        loader = (ROOT / "src/transmog_loader.cpp").read_text(encoding="utf-8")
        core = (ROOT / "src/SoloCollectionsCore.cpp").read_text(encoding="utf-8")
        header = (ROOT / "src/SoloCollectionsProtocol.h").read_text(encoding="utf-8")
        server = (ROOT / "src/SoloCollectionsProtocolServer.h").read_text(encoding="utf-8")
        self.assertIn("AddSC_solo_collections_protocol", loader)
        self.assertIn("PLAYERHOOK_CAN_PLAYER_USE_PRIVATE_CHAT", core)
        self.assertIn("PLAYERHOOK_ON_UPDATE", core)
        self.assertIn("DecodeSc2Body", header)
        self.assertIn("Sc2Server", server)

    def test_transport_is_addon_whisper_to_self_only(self):
        source = (ROOT / "src/SoloCollectionsProtocolScript.cpp").read_text(encoding="utf-8")
        for token in (
            "CHAT_MSG_WHISPER",
            "LANG_ADDON",
            "receiver != player",
            '"SC2\\t"',
            "BuildChatPacket",
            "SendDirectMessage",
        ):
            self.assertIn(token, source)
        self.assertNotIn("player->Whisper", source)

    def test_limits_replay_rate_and_outbound_queue_are_explicit(self):
        combined = "\n".join(
            (ROOT / path).read_text(encoding="utf-8")
            for path in (
                "src/SoloCollectionsProtocol.h",
                "src/SoloCollectionsProtocol.cpp",
                "src/SoloCollectionsProtocolServer.h",
                "src/SoloCollectionsProtocolServer.cpp",
            )
        )
        for token in (
            "MaxBodyBytes = 240",
            "MaxChunkPayloadBytes = 160",
            "MaxSnapshotChunks = 256",
            "MaxSnapshotBytes = 32768",
            "TokenBucket",
            "ReplayCache",
            "OutboundQueue",
            "MaxPacketsPerTick",
            "REPLAYED_REQUEST",
            "RATE_LIMITED",
            "LOADING",
        ):
            self.assertIn(token, combined)

    def test_account_cache_exposes_confirmed_owned_snapshot_only(self):
        header = (ROOT / "src/SoloCollectionsAccountCache.h").read_text(encoding="utf-8")
        source = (ROOT / "src/SoloCollectionsAccountCache.cpp").read_text(encoding="utf-8")
        self.assertIn("OwnedByType", header)
        self.assertIn("AccountCacheLoadState::Ready", source[source.index("OwnedByType"):])


if __name__ == "__main__":
    unittest.main()
