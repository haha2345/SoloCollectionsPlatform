from __future__ import annotations

import re
import subprocess
import sys
import unittest
from pathlib import Path

from common import ADDON, ROOT, load_json, read_text, sha256


MEDIA = ADDON / "Media"
MANIFEST = MEDIA / "assets.json"
TEMPLATES = ADDON / "UI" / "Templates.lua"
GENERATOR = ROOT / "tools" / "media" / "generate_base_ui_media.py"
REQUIRED_ROLES = {"launcher", "mountPortrait", "wardrobeSlotAtlas", "roundHighlightAtlas"}


def read_tga_info(path: Path) -> dict[str, int]:
    data = path.read_bytes()
    if len(data) < 18:
        raise AssertionError(f"{path} is shorter than a TGA header")
    return {
        "image_type": data[2],
        "width": int.from_bytes(data[12:14], "little"),
        "height": int.from_bytes(data[14:16], "little"),
        "depth": data[16],
        "alpha_bits": data[17] & 0x0F,
        "top_left": bool(data[17] & 0x20),
    }


class MediaContractTests(unittest.TestCase):
    def test_base_ui_roles_are_tracked_tga_assets_with_fixed_hash_and_dimensions(self):
        self.assertTrue(MANIFEST.is_file(), f"missing {MANIFEST}")
        manifest = load_json(MANIFEST)
        self.assertEqual(2, manifest.get("schemaVersion"))
        files = manifest.get("files")
        required = manifest.get("requiredForBaseUI")
        optional = manifest.get("optionalExternalFiles")
        self.assertIsInstance(files, dict)
        self.assertIsInstance(required, dict)
        self.assertIsInstance(optional, dict)
        self.assertEqual(REQUIRED_ROLES, set(required))

        for role, entry in required.items():
            self.assertIsInstance(entry, dict, role)
            relative = entry.get("path")
            self.assertIsInstance(relative, str, role)
            self.assertFalse(relative.startswith("Retail/"), role)
            self.assertNotIn("..", Path(relative).parts, role)
            self.assertNotIn(relative, optional, role)
            self.assertIn(relative, files, role)
            self.assertEqual(entry.get("sha256"), files[relative], role)
            self.assertRegex(entry.get("sha256", ""), r"^[A-F0-9]{64}$", role)
            self.assertEqual("TGA", entry.get("fileType"), role)
            self.assertEqual("top-left", entry.get("origin"), role)
            self.assertEqual(8, entry.get("alphaBits"), role)
            self.assertTrue(entry.get("provenance"), role)
            self.assertEqual("project-authored-redistributable", entry.get("license"), role)

            path = MEDIA / relative
            self.assertTrue(path.is_file(), role)
            self.assertEqual(entry["sha256"], sha256(path), role)
            info = read_tga_info(path)
            self.assertEqual(2, info["image_type"], role)
            self.assertEqual(entry["width"], info["width"], role)
            self.assertEqual(entry["height"], info["height"], role)
            self.assertEqual(32, info["depth"], role)
            self.assertEqual(entry["alphaBits"], info["alpha_bits"], role)
            self.assertTrue(info["top_left"], role)

    def test_all_tracked_media_hashes_match_and_no_retail_artifact_is_declared(self):
        manifest = load_json(MANIFEST)
        for relative, expected_hash in manifest["files"].items():
            path = MEDIA / relative
            self.assertTrue(path.is_file(), relative)
            self.assertEqual(".tga", path.suffix.lower(), relative)
            self.assertEqual(expected_hash, sha256(path), relative)
            self.assertFalse(relative.startswith("Retail/"), relative)
        self.assertEqual({}, manifest.get("optionalExternalFiles"))
        self.assertFalse((MEDIA / "Retail").exists())

    def test_base_ui_media_generator_is_byte_stable(self):
        result = subprocess.run(
            [sys.executable, str(GENERATOR), "--output-root", str(MEDIA), "--check"],
            cwd=ROOT,
            capture_output=True,
            text=True,
        )
        self.assertEqual(0, result.returncode, result.stdout + result.stderr)

    def test_templates_map_every_default_role_to_required_project_media(self):
        manifest = load_json(MANIFEST)
        required = manifest["requiredForBaseUI"]
        source = read_text(TEMPLATES)
        self.assertNotIn('MEDIA_ROOT .. "Retail\\', source)
        for role, entry in required.items():
            match = re.search(
                rf'^\s*{re.escape(role)}\s*=\s*MEDIA_ROOT\s*\.\.\s*"([^"]+)"',
                source,
                re.MULTILINE,
            )
            self.assertIsNotNone(match, role)
            self.assertEqual(entry["path"].replace("/", "\\\\"), match.group(1), role)

    def test_every_literal_addon_media_reference_resolves_to_tracked_media_not_optional_only(self):
        manifest = load_json(MANIFEST)
        tracked = set(manifest["files"])
        optional = set(manifest["optionalExternalFiles"])
        self.assertFalse(tracked & optional)
        for path in ADDON.rglob("*.lua"):
            source = read_text(path)
            self.assertNotIn("Media\\Retail\\", source, path)
            for reference in re.findall(r'Interface\\AddOns\\SoloCollections\\Media\\([^"\']+)', source):
                relative = reference.replace("\\", "/")
                self.assertIn(relative, tracked, f"{path}: {reference}")


if __name__ == "__main__":
    unittest.main()
