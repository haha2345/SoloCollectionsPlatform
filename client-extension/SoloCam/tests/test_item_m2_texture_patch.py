import struct
import tempfile
import unittest
from pathlib import Path


PROJECT_ROOT = Path(__file__).resolve().parents[1]
SCRIPTS = PROJECT_ROOT / "scripts"

import sys

sys.path.insert(0, str(SCRIPTS))

from patch_item_m2_textures import (  # noqa: E402
    BOUNDING_BOX_OFFSET,
    CAMERA_DESCRIPTOR_OFFSET,
    CAMERA_LOOKUP_DESCRIPTOR_OFFSET,
    OBJECT_SKIN_TEXTURE_TYPE,
    append_static_item_camera,
    inspect_textures,
    patch_object_skin_bytes,
)


def build_test_m2() -> bytes:
    data = bytearray(0x180)
    data[0:4] = b"MD20"
    struct.pack_into("<I", data, 4, 264)
    struct.pack_into("<2I", data, 0x50, 2, 0x100)
    struct.pack_into("<4I", data, 0x100, OBJECT_SKIN_TEXTURE_TYPE, 3, 0, 0)
    hardcoded = b"SPELLS\\GLOW.BLP\0"
    data[0x150 : 0x150 + len(hardcoded)] = hardcoded
    struct.pack_into("<4I", data, 0x110, 0, 0, len(hardcoded), 0x150)
    struct.pack_into("<2I", data, 0x68, 3, 0x140)
    struct.pack_into("<3h", data, 0x140, 1, -1, 0)
    return bytes(data)


def build_camera_test_m2() -> bytes:
    data = bytearray(0x130)
    data[0:4] = b"MD20"
    struct.pack_into("<I", data, 4, 264)
    # Center = (2, 4, 3); radius = 2, so camera distance = 5.3.
    struct.pack_into("<7f", data, BOUNDING_BOX_OFFSET, 0, 1, 0, 4, 7, 6, 2)
    return bytes(data)


class ItemM2TexturePatchTests(unittest.TestCase):
    def test_object_skin_is_replaced_with_a_hardcoded_texture(self):
        source = build_test_m2()
        texture = r"ITEM\OBJECTCOMPONENTS\WEAPON\TEST_SWORD.BLP"

        output = patch_object_skin_bytes(source, texture)
        textures = inspect_textures(output)

        self.assertEqual(len(textures), 2)
        self.assertEqual(textures[0]["type"], 0)
        self.assertEqual(textures[0]["flags"], 3)
        self.assertEqual(textures[0]["filename"], texture)
        self.assertEqual(textures[1]["filename"], r"SPELLS\GLOW.BLP")
        self.assertEqual(output[:0x68], source[:0x68])
        self.assertEqual(output[0x6C:0x100], source[0x6C:0x100])

        replacement_count, replacement_offset = struct.unpack_from("<2I", output, 0x68)
        self.assertEqual(replacement_count, 1)
        self.assertEqual(struct.unpack_from("<h", output, replacement_offset)[0], 1)

    def test_rejects_a_non_wotlk_model(self):
        source = bytearray(build_test_m2())
        struct.pack_into("<I", source, 4, 263)
        with self.assertRaisesRegex(ValueError, "version 264"):
            patch_object_skin_bytes(bytes(source), r"ITEM\TEST.BLP")

    def test_requires_at_least_one_object_skin_texture(self):
        source = bytearray(build_test_m2())
        struct.pack_into("<I", source, 0x100, 0)
        with self.assertRaisesRegex(ValueError, "OBJECT_SKIN"):
            patch_object_skin_bytes(bytes(source), r"ITEM\TEST.BLP")

    def test_static_camera_uses_the_opposite_azimuth_test_view(self):
        output = append_static_item_camera(build_camera_test_m2())
        camera_count, camera_offset = struct.unpack_from("<2I", output, CAMERA_DESCRIPTOR_OFFSET)
        lookup_count, lookup_offset = struct.unpack_from(
            "<2I", output, CAMERA_LOOKUP_DESCRIPTOR_OFFSET
        )

        self.assertEqual(camera_count, 1)
        self.assertEqual(lookup_count, 1)
        self.assertEqual(struct.unpack_from("<h", output, lookup_offset)[0], 0)
        position = struct.unpack_from("<3f", output, camera_offset + 36)
        target = struct.unpack_from("<3f", output, camera_offset + 68)
        self.assertAlmostEqual(position[0], 2 - 5.3 * 0.6666667, places=5)
        self.assertAlmostEqual(position[1], 4 - 5.3 * 0.3333333, places=5)
        self.assertAlmostEqual(position[2], 3 + 5.3 * 0.6666667, places=5)
        self.assertEqual(target, (2.0, 4.0, 3.0))

    def test_real_weapon_samples_have_no_object_skin_after_patch(self):
        sample_root = Path(
            r"F:\1_projects\wow_projects\_work\solo_collections_weapon_models\extract"
        )
        samples = {
            "Sword_2H_Blackwing_A_02.m2": r"ITEM\OBJECTCOMPONENTS\WEAPON\SWORD_2H_BLACKWING_A_02.BLP",
            "Sword_2H_Ashbringer02.m2": r"ITEM\OBJECTCOMPONENTS\WEAPON\SWORD_2H_ASHBRINGER_A_01BLUE.BLP",
            "Glave_1H_DualBlade_D_02.m2": r"ITEM\OBJECTCOMPONENTS\WEAPON\GLAVE_1H_DUALBLADE_D_02.BLP",
            "Glave_1H_DualBlade_D_02left.m2": r"ITEM\OBJECTCOMPONENTS\WEAPON\GLAVE_1H_DUALBLADE_D_02.BLP",
            "Shield_2H_OutlandRaid_D_06.m2": r"ITEM\OBJECTCOMPONENTS\SHIELD\SHIELD_2H_OUTLANDRAID_D_06.BLP",
        }
        for filename, texture in samples.items():
            matches = list(sample_root.rglob(filename))
            if not matches:
                self.skipTest(f"local extracted sample is unavailable: {filename}")
            output = patch_object_skin_bytes(matches[0].read_bytes(), texture)
            patched = inspect_textures(output)
            self.assertNotIn(OBJECT_SKIN_TEXTURE_TYPE, [entry["type"] for entry in patched])
            self.assertIn(texture, [entry["filename"] for entry in patched])


if __name__ == "__main__":
    unittest.main()
