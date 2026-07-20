from __future__ import annotations

import importlib.util
import unittest

from common import ROOT


SCRIPT = ROOT / "tools" / "release" / "build_unified_release.py"
SPEC = importlib.util.spec_from_file_location("solo_unified_release", SCRIPT)
release = importlib.util.module_from_spec(SPEC)
assert SPEC and SPEC.loader
SPEC.loader.exec_module(release)


class UnifiedReleaseTests(unittest.TestCase):
    def test_manifest_records_all_cross_repository_compatibility_fields(self):
        catalog = {
            "schemaVersion": 1,
            "metadataVersion": "2026.07.20.2",
            "assetPackVersion": "asset-1",
            "mappingHash": "a" * 64,
            "collectionTypes": [
                {"typeId": 10, "typeKey": "mount"},
                {"typeId": 13, "typeKey": "appearance"},
            ],
            "typeMappingHashes": {"appearance": "b" * 64, "mount": "c" * 64},
        }
        manifest = release.compose_manifest(
            "1.0.0", "1" * 40, "2" * 40, "3" * 40, catalog,
            {"protocolVersion": 1}, 1, "2026_07_20_00",
        )
        self.assertEqual("1" * 40, manifest["commits"]["addon"])
        self.assertEqual("2" * 40, manifest["commits"]["module"])
        self.assertEqual("3" * 40, manifest["commits"]["azerothcore"])
        self.assertEqual(1, manifest["protocol"]["version"])
        self.assertEqual("asset-1", manifest["assetPackVersion"])
        self.assertEqual(1, manifest["sql"]["schemaVersion"])
        self.assertEqual("2026_07_20_00", manifest["sql"]["migrationVersion"])
        self.assertEqual([10, 13], [entry["typeId"] for entry in manifest["catalog"]["perCategoryMappingHashes"]])

    def test_release_safety_gate_rejects_binaries_paths_and_credentials(self):
        release.assert_safe_entries([("safe/readme.md", b"relative documentation")])
        rejected = [
            ("Wow.exe", b"binary"),
            ("client/Patch-W.MPQ", b"archive"),
            ("notes.txt", b"runtime F:\\private\\server"),
            ("db.txt", b"password=admin"),
        ]
        for entry in rejected:
            with self.subTest(entry=entry[0]), self.assertRaises(release.ReleaseError):
                release.assert_safe_entries([entry])

    def test_installation_document_defines_four_independent_boundaries(self):
        document = (ROOT / "docs" / "UNIFIED_BACKEND_INSTALLATION.zh-CN.md").read_text(encoding="utf-8")
        for token in ("AddOn", "C++ module", "SQL", "客户端资源"):
            self.assertIn(token, document)
        self.assertIn("不包含客户端 EXE、DLL 或 MPQ", document)


if __name__ == "__main__":
    unittest.main()
