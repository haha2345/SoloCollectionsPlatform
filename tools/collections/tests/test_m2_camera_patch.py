import importlib.util
import math
import struct
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path


PROJECT_ROOT = Path(__file__).resolve().parents[3]
TOOL_PATH = PROJECT_ROOT / "tools" / "collections" / "m2_camera_patch.py"
WARDROBE_PATH = PROJECT_ROOT / "addon" / "SoloCollections" / "UI" / "Wardrobe.lua"
README_PATH = PROJECT_ROOT / "tools" / "collections" / "README.md"


def load_tool_module():
    if not TOOL_PATH.exists():
        return None
    spec = importlib.util.spec_from_file_location("m2_camera_patch", TOOL_PATH)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def make_camera(camera_type, marker, position, target, fov=1.069064):
    camera = bytearray([marker] * 100)
    struct.pack_into("<ifff", camera, 0, camera_type, fov, 277.7778, 0.2222222)
    struct.pack_into("<3f", camera, 36, *position)
    struct.pack_into("<3f", camera, 68, *target)
    return bytes(camera)


def make_synthetic_m2():
    data = bytearray([0x5A] * 1024)
    data[0:4] = b"MD20"
    struct.pack_into("<I", data, 4, 264)
    camera_offset = 0x200
    lookup_offset = 0x300
    camera0 = make_camera(0, 0x11, (0.45, -0.35, 1.80), (-0.04, 0.02, 1.74), 0.7853982)
    camera1 = make_camera(1, 0x22, (3.00, 0.03, 0.95), (-0.36, 0.00, 0.89))
    data[camera_offset : camera_offset + 100] = camera0
    data[camera_offset + 100 : camera_offset + 200] = camera1
    struct.pack_into("<4I", data, 0x110, 2, camera_offset, 2, lookup_offset)
    struct.pack_into("<2h", data, lookup_offset, 0, 1)
    return bytes(data), camera0, camera1


class M2CameraPatchTests(unittest.TestCase):
    def setUp(self):
        self.tool = load_tool_module()
        self.assertIsNotNone(self.tool, f"missing production tool: {TOOL_PATH}")

    def test_inspect_reads_wotlk_camera_header(self):
        source, _, _ = make_synthetic_m2()
        info = self.tool.inspect_m2(source)
        self.assertEqual(info["magic"], "MD20")
        self.assertEqual(info["version"], 264)
        self.assertEqual(info["camera_count"], 2)
        self.assertEqual(info["camera_lookup"], [0, 1])
        self.assertEqual([camera["type"] for camera in info["cameras"]], [0, 1])

    def test_append_camera_moves_arrays_without_relocating_original_payload(self):
        source, camera0, camera1 = make_synthetic_m2()
        config = self.tool.CameraConfig(
            camera_type=2,
            fov=0.7853982,
            position=(1.10, 0.013, 1.272),
            target=(-0.15, 0.0, 1.25),
        )
        patched = self.tool.patch_m2_bytes(source, config)
        info = self.tool.inspect_m2(patched)

        self.assertEqual(info["camera_count"], 3)
        self.assertEqual(info["camera_lookup"], [0, 1, 2])
        self.assertEqual(info["camera_offset"] % 16, 0)
        self.assertEqual(info["camera_lookup_offset"] % 16, 0)
        self.assertGreaterEqual(info["camera_offset"], len(source))
        self.assertEqual(patched[info["camera_offset"] : info["camera_offset"] + 100], camera0)
        self.assertEqual(patched[info["camera_offset"] + 100 : info["camera_offset"] + 200], camera1)

        expected_prefix = bytearray(source)
        expected_prefix[0x110:0x120] = patched[0x110:0x120]
        self.assertEqual(patched[: len(source)], bytes(expected_prefix))

        camera2_offset = info["camera_offset"] + 200
        camera2 = patched[camera2_offset : camera2_offset + 100]
        self.assertEqual(camera2[16:36], camera1[16:36])
        self.assertEqual(camera2[48:68], camera1[48:68])
        self.assertEqual(camera2[80:100], camera1[80:100])
        self.assertEqual(info["cameras"][2]["type"], 2)
        self.assertTrue(math.isclose(info["cameras"][2]["fov"], config.fov, rel_tol=1e-6))
        for actual, expected in zip(info["cameras"][2]["position"], config.position):
            self.assertTrue(math.isclose(actual, expected, rel_tol=1e-6, abs_tol=1e-6))
        for actual, expected in zip(info["cameras"][2]["target"], config.target):
            self.assertTrue(math.isclose(actual, expected, rel_tol=1e-6, abs_tol=1e-6))

    def test_rejects_unsupported_or_already_patched_sources(self):
        source, _, _ = make_synthetic_m2()
        config = self.tool.CameraConfig(2, 0.7853982, (1.10, 0.013, 1.272), (-0.15, 0.0, 1.25))
        with self.assertRaisesRegex(ValueError, "MD20"):
            self.tool.patch_m2_bytes(b"BAD!" + source[4:], config)
        bad_version = bytearray(source)
        struct.pack_into("<I", bad_version, 4, 272)
        with self.assertRaisesRegex(ValueError, "version"):
            self.tool.patch_m2_bytes(bytes(bad_version), config)
        with self.assertRaisesRegex(ValueError, "exactly 2 cameras"):
            self.tool.patch_m2_bytes(self.tool.patch_m2_bytes(source, config), config)

    def test_cli_writes_binary_and_json_manifest(self):
        source, _, _ = make_synthetic_m2()
        with tempfile.TemporaryDirectory() as temp_dir:
            temp = Path(temp_dir)
            input_path = temp / "HumanFemale.m2"
            output_path = temp / "patched" / "HumanFemale.m2"
            manifest_path = temp / "manifest.json"
            input_path.write_bytes(source)
            result = subprocess.run(
                [
                    sys.executable,
                    str(TOOL_PATH),
                    "patch",
                    "--input",
                    str(input_path),
                    "--output",
                    str(output_path),
                    "--manifest",
                    str(manifest_path),
                    "--camera-type",
                    "2",
                    "--fov",
                    "0.7853982",
                    "--position",
                    "1.10,0.013,1.272",
                    "--target=-0.15,0.0,1.25",
                    "--allow-unsafe-player-model",
                ],
                capture_output=True,
                text=True,
                encoding="utf-8",
            )
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertTrue(output_path.exists())
            self.assertTrue(manifest_path.exists())
            self.assertEqual(self.tool.inspect_m2(output_path.read_bytes())["camera_lookup"], [0, 1, 2])

    def test_cli_rejects_player_character_m2_without_explicit_unsafe_override(self):
        source, _, _ = make_synthetic_m2()
        with tempfile.TemporaryDirectory() as temp_dir:
            temp = Path(temp_dir)
            input_path = temp / "HumanFemale.m2"
            output_path = temp / "patched.m2"
            input_path.write_bytes(source)
            result = subprocess.run(
                [
                    sys.executable,
                    str(TOOL_PATH),
                    "patch",
                    "--input",
                    str(input_path),
                    "--output",
                    str(output_path),
                    "--fov",
                    "0.7853982",
                    "--position",
                    "1.10,0.013,1.272",
                    "--target=-0.15,0.0,1.25",
                ],
                capture_output=True,
                text=True,
                encoding="utf-8",
            )
            self.assertEqual(result.returncode, 2)
            self.assertIn("3.3.5 client crashes", result.stderr)
            self.assertFalse(output_path.exists())


class WardrobeCameraContractTests(unittest.TestCase):
    def test_wardrobe_never_selects_unsupported_third_player_camera(self):
        source = WARDROBE_PATH.read_text(encoding="utf-8")
        self.assertRegex(source, r"CHEST\s*=\s*\{\s*camera\s*=\s*1")
        self.assertNotIn("CHEST_HUMAN_FEMALE", source)
        self.assertNotRegex(source, r"camera\s*=\s*2")

    def test_tooling_docs_record_runtime_rejection_of_third_player_camera(self):
        source = README_PATH.read_text(encoding="utf-8")
        self.assertIn("ERROR #132", source)
        self.assertIn("Do not deploy a third camera to a playable character M2", source)


if __name__ == "__main__":
    unittest.main()
