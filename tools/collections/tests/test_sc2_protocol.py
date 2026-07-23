from __future__ import annotations

import importlib.util
import json
import unittest

from common import ROOT


CODEC_PATH = ROOT / "tools" / "protocol" / "sc2_codec.py"
SCHEMA_PATH = ROOT / "protocol" / "sc2" / "schema.json"
VECTORS_PATH = ROOT / "protocol" / "sc2" / "golden-vectors.json"

SPEC = importlib.util.spec_from_file_location("solo_sc2_codec", CODEC_PATH)
codec = importlib.util.module_from_spec(SPEC)
assert SPEC and SPEC.loader
SPEC.loader.exec_module(codec)


class SC2ProtocolTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.schema = json.loads(SCHEMA_PATH.read_text(encoding="utf-8"))
        cls.vectors = json.loads(VECTORS_PATH.read_text(encoding="utf-8"))

    def test_schema_reserves_transport_headroom(self):
        self.assertEqual("SC2", self.schema["prefix"])
        self.assertEqual(1, self.schema["protocolVersion"])
        self.assertLessEqual(self.schema["maxBodyBytes"], 240)
        self.assertLess(self.schema["maxBodyBytes"], self.schema["coreMessageLimitBytes"])
        self.assertEqual(160, self.schema["maxChunkPayloadBytes"])
        self.assertEqual(
            "ASCII_ALNUM_DOT_UNDERSCORE_TILDE_HYPHEN_1_TO_64",
            self.schema["fields"]["token"],
        )

    def test_all_golden_packets_round_trip(self):
        for vector in self.vectors["packets"]:
            with self.subTest(vector=vector["name"]):
                packet = codec.encode(vector["message"])
                self.assertEqual(vector["wire"], packet)
                self.assertEqual(vector["message"], codec.decode(packet))
                self.assertLessEqual(len(packet.encode("ascii")), self.schema["maxBodyBytes"])

    def test_snapshot_checksum_vectors_match(self):
        for vector in self.vectors["checksums"]:
            with self.subTest(vector=vector["name"]):
                self.assertEqual(vector["adler32"], codec.adler32_hex(vector["payload"]))

    def test_chunking_is_deterministic_and_bounded(self):
        payload = ",".join(codec.to_base36(value) for value in range(1, 401))
        chunks = codec.chunk_payload(payload)
        self.assertEqual(payload, "".join(chunks))
        self.assertTrue(all(len(chunk.encode("ascii")) <= 160 for chunk in chunks))
        self.assertEqual(chunks, codec.chunk_payload(payload))

    def test_decoder_rejects_noncanonical_or_oversized_packets(self):
        invalid = [
            "H|1|ABCDEF0123456789|dev|1|1",
            "D|0123456789abcdef|1|0002|A|1",
            "C|0123456789abcdef|1|1|bad payload",
            "X|0123456789abcdef|0|FREE_FORM_TEXT",
            "Z|1",
            "C|0123456789abcdef|4294967295|4294967295|" + ("a" * 200),
        ]
        for packet in invalid:
            with self.subTest(packet=packet[:32]):
                with self.assertRaises(codec.ProtocolError):
                    codec.decode(packet)

    def test_version_token_boundary_accepts_current_asset_pack_and_rejects_65_bytes(self):
        token = "round-two-stage8-weapon-presentation-v2"
        self.assertEqual(39, len(token))
        packet = codec.encode(
            {
                "kind": "HELLO",
                "protocolVersion": 1,
                "clientNonce": "fedcba9876543210",
                "clientBuild": "0.1.0",
                "metadataVersion": "2026.07.23.2",
                "assetPackVersion": token,
            }
        )
        self.assertEqual(token, codec.decode(packet)["assetPackVersion"])
        too_long = "a" * 65
        with self.assertRaises(codec.ProtocolError):
            codec.encode(
                {
                    "kind": "HELLO",
                    "protocolVersion": 1,
                    "clientNonce": "fedcba9876543210",
                    "clientBuild": "0.1.0",
                    "metadataVersion": "2026.07.23.2",
                    "assetPackVersion": too_long,
                }
            )


if __name__ == "__main__":
    unittest.main()
