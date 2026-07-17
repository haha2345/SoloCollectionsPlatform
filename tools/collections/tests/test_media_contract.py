from __future__ import annotations

import re
import unittest

from common import ADDON, load_json, sha256


class MediaContractTests(unittest.TestCase):
    def test_media_manifest_files_exist_and_hash_match(self):
        manifest_path = ADDON / "Media" / "assets.json"
        self.assertTrue(manifest_path.is_file(), f"missing {manifest_path}")
        manifest = load_json(manifest_path)
        self.assertIn("source", manifest)
        self.assertIn("files", manifest)
        self.assertIn("externalFiles", manifest)
        self.assertGreaterEqual(len(manifest["files"]), 9)
        for relative, expected_hash in manifest["files"].items():
            path = ADDON / "Media" / relative
            self.assertTrue(path.is_file(), str(path))
            self.assertIn(path.suffix.lower(), {".tga", ".blp"})
            self.assertRegex(expected_hash, r"^[0-9A-F]{64}$")
            self.assertEqual(expected_hash, sha256(path), relative)

        for relative, expected_hash in manifest["externalFiles"].items():
            path = ADDON / "Media" / relative
            self.assertRegex(expected_hash, r"^[0-9A-F]{64}$")
            if path.is_file():
                self.assertEqual(expected_hash, sha256(path), relative)

    def test_every_media_reference_uses_addon_relative_path(self):
        self.assertTrue(ADDON.is_dir(), f"missing addon source: {ADDON}")
        manifest = load_json(ADDON / "Media" / "assets.json")
        declared_external = set(manifest.get("externalFiles", {}))
        for path in ADDON.rglob("*.lua") if ADDON.exists() else []:
            text = path.read_text(encoding="utf-8-sig")
            for ref in re.findall(r'Interface\\AddOns\\SoloCollections\\Media\\[^"\']+', text):
                relative = ref.split("SoloCollections\\Media\\", 1)[1].replace("\\", "/")
                self.assertTrue(
                    (ADDON / "Media" / relative).is_file() or relative in declared_external,
                    f"{path}: {ref}",
                )

    def test_mount_portrait_compatibility_asset_has_real_circular_alpha(self):
        path = ADDON / "Media" / "Retail" / "MountJournalPortraitRound.tga"
        if not path.is_file():
            self.skipTest("external Retail compatibility media is not installed")
        data = path.read_bytes()
        self.assertGreaterEqual(len(data), 18 + (64 * 64 * 4))
        self.assertEqual(2, data[2], "mount portrait must be an uncompressed true-color TGA")
        self.assertEqual(64, int.from_bytes(data[12:14], "little"))
        self.assertEqual(64, int.from_bytes(data[14:16], "little"))
        self.assertEqual(32, data[16])
        self.assertEqual(8, data[17] & 0x0F, "mount portrait must preserve an 8-bit alpha channel")

        def alpha_at(x: int, y: int) -> int:
            return data[18 + (((y * 64) + x) * 4) + 3]

        for corner in ((0, 0), (63, 0), (0, 63), (63, 63)):
            self.assertEqual(0, alpha_at(*corner), f"corner {corner} must be transparent")
        self.assertEqual(255, alpha_at(32, 32), "portrait center must remain opaque")


if __name__ == "__main__":
    unittest.main()
