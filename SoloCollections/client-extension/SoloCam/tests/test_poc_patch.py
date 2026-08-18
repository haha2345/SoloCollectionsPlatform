import hashlib
import os
import sys
import tempfile
import unittest
from pathlib import Path


PROJECT_ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(PROJECT_ROOT))

import poc_patch


WOW_EXE = Path(os.environ.get("SOLOCOLLECTIONS_WOW_EXE", ""))
EXPECTED_SHA256 = "AA63A5750D60EF16746C686B3D5E26876D98953EAB08B1C026CD0FAF78E88CB8"


@unittest.skipUnless(
    os.environ.get("SOLOCOLLECTIONS_WOW_EXE") and WOW_EXE.is_file(),
    "set SOLOCOLLECTIONS_WOW_EXE to the supported local Wow.exe",
)
class PocPatchTests(unittest.TestCase):
    def test_fixture_is_the_supported_12340_client(self):
        digest = hashlib.sha256(WOW_EXE.read_bytes()).hexdigest().upper()
        self.assertEqual(EXPECTED_SHA256, digest)

    def test_patch_plan_matches_every_original_byte(self):
        image = WOW_EXE.read_bytes()
        poc_patch.validate_supported_image(image)
        for patch in poc_patch.build_patch_plan(image):
            self.assertEqual(len(patch.expected), len(patch.replacement), patch.name)
            self.assertEqual(
                patch.expected,
                image[patch.offset : patch.offset + len(patch.expected)],
                patch.name,
            )

    def test_patcher_creates_a_copy_and_is_idempotent(self):
        original = WOW_EXE.read_bytes()
        (PROJECT_ROOT / "build").mkdir(parents=True, exist_ok=True)
        with tempfile.TemporaryDirectory(dir=PROJECT_ROOT / "build") as temp_dir:
            source = Path(temp_dir) / "Wow.exe"
            target = Path(temp_dir) / "Wow-SoloCam-PoC.exe"
            source.write_bytes(original)

            poc_patch.patch_copy(source, target)
            first = target.read_bytes()
            self.assertEqual(original, source.read_bytes())
            self.assertNotEqual(original, first)

            poc_patch.patch_copy(source, target)
            self.assertEqual(first, target.read_bytes())

    def test_wrong_client_is_rejected(self):
        image = bytearray(WOW_EXE.read_bytes())
        image[0x200] ^= 0x01
        with self.assertRaisesRegex(ValueError, "unsupported Wow.exe"):
            poc_patch.validate_supported_image(bytes(image))


if __name__ == "__main__":
    unittest.main()
