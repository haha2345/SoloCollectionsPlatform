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

    def test_schema_documents_transmog_projection_types(self):
        projection_types = self.schema["projectionTypes"]
        self.assertEqual(
            "authoritative account-owned appearance collection IDs",
            projection_types["13"],
        )
        self.assertEqual(
            "authoritative account-owned official wardrobe set collection IDs derived from appearance ownership",
            projection_types["14"],
        )

    def test_schema_documents_transmog_apply_without_ownership_delta(self):
        apply_semantics = self.schema["actionSemantics"]["APPLY"]
        protocol_doc = (ROOT / "docs" / "protocol" / "sc2-wire-v1.md").read_text(encoding="utf-8")
        self.assertEqual([13, 14], apply_semantics["typeIds"])
        self.assertTrue(apply_semantics["requiresOwned"])
        self.assertEqual(
            "EQUIPMENT_SLOT_1_TO_19_ONE_BASED",
            apply_semantics["targetByTypeId"]["13"],
        )
        self.assertEqual(
            "SET_VARIANT_ORDINAL_OR_DASH",
            apply_semantics["targetByTypeId"]["14"],
        )
        self.assertEqual(
            "SERVER_APPLIES_CHARACTER_TRANSMOG_NO_COLLECTION_OWNERSHIP_DELTA_REQUIRED",
            apply_semantics["sideEffects"],
        )
        self.assertEqual(
            "SERVER_VALIDATED_AND_EXECUTED_CHARACTER_APPLY",
            apply_semantics["acceptedMeaning"],
        )
        self.assertIn("The wardrobe UI sends the selected ordinal, including the default", protocol_doc)

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

    def test_companion_owned_and_favorite_projection_contract(self):
        projection_types = self.schema["projectionTypes"]
        self.assertEqual(
            "authoritative account-owned companion collection IDs",
            projection_types["11"],
        )
        self.assertEqual(
            "internal companion-favorite membership using type 11 collection IDs; excluded from navigation and progress",
            projection_types["17"],
        )
        favorite = self.schema["actionSemantics"]["SET_FAVORITE"]
        random_summon = self.schema["actionSemantics"]["RANDOM_SUMMON"]
        self.assertEqual([10, 11], favorite["typeIds"])
        self.assertEqual({"10": 16, "11": 17}, favorite["projectionTypeByOwnedType"])
        self.assertEqual([10, 11], random_summon["typeIds"])
        self.assertEqual(1, random_summon["collectionId"])
        self.assertIn("NO_COMPANIONS", self.schema["actionStatuses"])
        self.assertIn("NO_USABLE_COMPANIONS", self.schema["actionStatuses"])

    def test_companion_favorite_and_random_golden_vectors_are_complete(self):
        names = {row["name"] for row in self.vectors["packets"]}
        expected = {
            "companion_favorite_snapshot_begin", "companion_favorite_snapshot_chunk",
            "companion_favorite_snapshot_end", "companion_favorite_delta_add",
            "companion_favorite_delta_remove", "companion_set_favorite_on_request",
            "companion_set_favorite_off_request", "companion_random_summon_request",
            "companion_favorite_not_owned_result", "companion_invalid_random_control_id_result",
        }
        self.assertTrue(expected <= names)
        original_mount_vectors = {
            "mount_favorite_snapshot_begin", "mount_favorite_snapshot_chunk",
            "mount_favorite_snapshot_end", "mount_favorite_delta_add",
            "mount_set_favorite_request", "mount_random_summon_request",
        }
        self.assertTrue(original_mount_vectors <= names)

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
