from __future__ import annotations

import csv
import hashlib
import importlib.util
import json
import math
import struct
import tempfile
import unittest
from pathlib import Path

from common import ROOT


TOOL = ROOT / "tools/catalog/character_camera_profiles.py"
SPEC = importlib.util.spec_from_file_location("character_camera_profiles", TOOL)
camera = importlib.util.module_from_spec(SPEC)
assert SPEC and SPEC.loader
SPEC.loader.exec_module(camera)

CANONICAL = ROOT / "catalog/source/camera_profiles.json"
OVERRIDES = ROOT / "catalog/source/overrides/camera_profiles.json"
RACES = ROOT / "catalog/source/races.json"
LUA = ROOT / "addon/SoloCollections/Data/Generated/CameraProfiles.lua"
CPP = ROOT / "client-extension/SoloCam/src/generated/CharacterCameraProfiles.inc"
RUNTIME_AUDIT = ROOT / "tools/runtime/SoloCollectionsCameraAudit/CameraAudit.lua"
RUNTIME_REVIEW = ROOT / "catalog/review/cameras/runtime-matrix.csv"


def read_json(path: Path):
    return json.loads(path.read_text(encoding="utf-8"))


class CharacterCameraProfileTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.canonical = read_json(CANONICAL)
        cls.overrides = read_json(OVERRIDES)
        cls.profiles = cls.canonical["profiles"]

    def test_matrix_covers_ten_races_two_sexes_and_fixed_nine_slot_order(self):
        self.assertEqual(list(camera.SLOTS), self.canonical["slotOrder"])
        identities = {
            (row["raceKey"], row["sex"], row["slot"])
            for row in self.profiles
        }
        expected = {
            (race, sex, slot)
            for race in camera.RACE_MODELS
            for sex in camera.SEXES
            for slot in camera.SLOTS
        }
        self.assertEqual(expected, identities)
        self.assertEqual(180, len(self.profiles))
        self.assertEqual(20, len(self.canonical["models"]))
        self.assertEqual(20, len({row["previewDisplayId"] for row in self.canonical["models"]}))
        for model in self.canonical["models"]:
            self.assertGreater(model["previewDisplayId"], 0)
            self.assertGreater(model["extendedDisplayInfoId"], 0)
            self.assertGreater(model["previewDisplayScale"], 0)

    def test_all_sentinels_are_unique_safe_and_preserve_human_female(self):
        sentinels = [int(row["sentinel"]) for row in self.profiles]
        self.assertEqual(180, len(set(sentinels)))
        reference = {
            row["slot"]: row for row in self.overrides["reference"]["slots"]
        }
        human_female = {
            row["slot"]: row for row in self.profiles
            if row["cameraProfile"] == "race.human" and row["sex"] == "FEMALE"
        }
        value_keys = (
            "sentinel", "verticalOffset", "distanceScale", "minimumDistance",
            "horizontalOffset", "yawOffset",
        )
        for slot in camera.SLOTS:
            for key in value_keys:
                self.assertEqual(reference[slot][key], human_female[slot][key])
            self.assertEqual("verified", human_female[slot]["status"])
        new_values = sorted(set(sentinels) - {row["sentinel"] for row in reference.values()})
        self.assertEqual(list(range(0x6000, 0x6000 + 171)), new_values)
        self.assertTrue(all(value not in (0, 1) for value in sentinels))
        self.assertTrue(all(value < camera.RESERVED_ITEM_CAMERA_MIN for value in sentinels))

    def test_scaled_profiles_are_finite_dimension_derived_and_bounded(self):
        model_by_key = {
            (row["cameraProfile"], row["sex"]): row for row in self.canonical["models"]
        }
        reference_model = model_by_key[("race.human", "FEMALE")]
        reference = {
            row["slot"]: row for row in self.overrides["reference"]["slots"]
        }
        overrides = {
            (row["cameraProfile"], row["sex"], row["slot"]): row
            for row in self.overrides["entries"]
        }
        for row in self.profiles:
            for key in (
                "verticalOffset", "distanceScale", "minimumDistance",
                "horizontalOffset", "yawOffset",
            ):
                self.assertTrue(math.isfinite(float(row[key])), row)
            self.assertGreaterEqual(row["distanceScale"], 0.05)
            self.assertLessEqual(row["distanceScale"], 4.0)
            self.assertGreaterEqual(row["minimumDistance"], 0.05)
            self.assertLessEqual(row["minimumDistance"], 8.0)
            if row["status"] != "scaled":
                continue
            target = model_by_key[(row["cameraProfile"], row["sex"])]
            ref = reference[row["slot"]]
            expected_vertical = ref["verticalOffset"] / reference_model["bounds"]["height"] * target["bounds"]["height"]
            expected_horizontal = ref["horizontalOffset"] / reference_model["bounds"]["width"] * target["bounds"]["width"]
            expected_minimum = ref["minimumDistance"] / max(
                reference_model["bounds"]["height"], reference_model["bounds"]["width"]
            ) * max(target["bounds"]["height"], target["bounds"]["width"])
            override = overrides.get((row["cameraProfile"], row["sex"], row["slot"]), {})
            expected_vertical += override.get("centerZCorrection", 0.0)
            expected_vertical = override.get("verticalOffset", expected_vertical)
            expected_horizontal = override.get("horizontalOffset", expected_horizontal)
            expected_minimum = override.get("minimumDistance", expected_minimum)
            self.assertAlmostEqual(expected_vertical, row["verticalOffset"], places=7)
            self.assertAlmostEqual(expected_horizontal, row["horizontalOffset"], places=7)
            self.assertAlmostEqual(expected_minimum, row["minimumDistance"], places=7)
            self.assertEqual(ref["distanceScale"], row["distanceScale"])
            self.assertEqual(ref["yawOffset"], row["yawOffset"])

    def test_priority_override_families_are_declared(self):
        self.assertEqual(
            ["race.tauren", "race.troll", "race.undead", "race.gnome"],
            self.overrides["priorityReview"],
        )

    def test_races_use_distinct_native_camera_families(self):
        races = read_json(RACES)["entries"]
        self.assertEqual(10, len(races))
        for row in races:
            expected = f'race.{row["raceKey"]}'
            self.assertEqual(expected, row["cameraProfile"])
            self.assertEqual(expected, row["clientAssetProfile"])

    def test_lua_and_cpp_projections_have_identical_version_and_hash(self):
        lua = LUA.read_text(encoding="utf-8")
        cpp = CPP.read_text(encoding="utf-8")
        version = self.canonical["profileVersion"]
        profile_hash = self.canonical["profileHash"]
        self.assertIn(f"CameraProfiles.profileVersion = {version}", lua)
        self.assertIn(f'CameraProfiles.profileHash = "{profile_hash}"', lua)
        self.assertIn(f'kCharacterCameraProfileHash[] = "{profile_hash}"', cpp)
        self.assertIn(f"kCharacterCameraProfileVersion = {version}u", cpp)
        self.assertEqual(180, cpp.count("// race."))
        self.assertEqual(self.canonical, camera.check(ROOT))

    def test_lua_modes_and_fail_closed_fallback_contract_are_explicit(self):
        lua = LUA.read_text(encoding="utf-8")
        wardrobe = (ROOT / "addon/SoloCollections/UI/Wardrobe.lua").read_text(encoding="utf-8")
        for mode in ("LegacyHumanFemale", "Compare", "Generated", "Native"):
            self.assertIn(f'mode ~= "{mode}"', lua)
        self.assertIn("CameraProfiles.lastComparison", lua)
        self.assertIn("CameraProfiles.previewDisplayIds", lua)
        self.assertIn("clientAssetProfile ~= family", lua)
        self.assertIn("if not family then return nil end", lua)
        self.assertIn("if not sexKey then return nil end", lua)
        self.assertRegex(wardrobe, r"SetCamera\(model\.scClientCameraSentinel\)[\s\S]*?SetCamera\(1\)")
        self.assertIn("pcall(function() model:SetCamera(1) end)", wardrobe)

    def test_runtime_audit_covers_textured_180_row_matrix_and_async_reapply(self):
        audit = RUNTIME_AUDIT.read_text(encoding="utf-8")
        self.assertIn('CreateFrame("DressUpModel"', audit)
        self.assertIn("DIRECT_DISPLAY_REQUEST_BASE + displayId", audit)
        self.assertIn("card.model:TryOn(itemString(previewItem))", audit)
        self.assertIn("state.page > 20", audit)
        self.assertIn("SoloCollectionsCameraAuditDB.rowCount == 180", audit)
        self.assertIn("SoloCollectionsCameraAuditDB.pageCount == 20", audit)
        self.assertIn("reapplyPageCameras()", audit)
        self.assertIn("state.elapsed >= 0.30", audit)
        self.assertNotIn("math.mod", audit)

    def test_runtime_review_has_one_passing_row_for_every_profile(self):
        with RUNTIME_REVIEW.open(encoding="utf-8-sig", newline="") as handle:
            rows = list(csv.DictReader(handle))
        self.assertEqual(180, len(rows))
        expected = {
            (row["raceKey"], row["sex"], row["slot"], f'0x{int(row["sentinel"]):04X}')
            for row in self.profiles
        }
        actual = {
            (row["raceKey"], row["sex"], row["slot"], row["sentinel"])
            for row in rows
        }
        self.assertEqual(expected, actual)
        self.assertEqual({self.canonical["profileHash"]}, {row["profileHash"] for row in rows})
        for row in rows:
            self.assertEqual("PASS", row["modelReady"])
            self.assertEqual("PASS", row["inSafeFrame"])
            self.assertEqual("PASS", row["targetVisible"])
            self.assertEqual("PASS", row["targetCentered"])
            self.assertEqual("NONE", row["unexpectedClipping"])
            self.assertEqual("PASS", row["visualReview"])

    def test_m2_and_dbc_hash_drift_fail_closed(self):
        scratch = ROOT / "_work/test-temp"
        scratch.mkdir(parents=True, exist_ok=True)
        with tempfile.TemporaryDirectory(prefix="camera-profile-", dir=scratch) as value:
            temp = Path(value)
            source = temp / "catalog/source"
            (source / "overrides").mkdir(parents=True)
            races = []
            models = []
            for index, (race_key, (_, runtime_id)) in enumerate(camera.RACE_MODELS.items(), 1):
                family = f"race.{race_key}"
                races.append({
                    "raceKey": race_key, "runtimeRaceId": runtime_id,
                    "cameraProfile": family, "clientAssetProfile": family,
                })
                for sex_index, sex in enumerate(camera.SEXES):
                    model_path = temp / "models" / race_key / f"{sex}.m2"
                    model_path.parent.mkdir(parents=True, exist_ok=True)
                    data = bytearray(184)
                    data[:4] = b"MD20"
                    struct.pack_into("<I", data, 4, 264)
                    scale = 1.0 + index * 0.05 + sex_index * 0.01
                    struct.pack_into("<6f", data, camera.M2_BOUNDS_OFFSET, -scale, -scale, -scale, scale, scale, scale)
                    model_path.write_bytes(data)
                    models.append({
                        "cameraProfile": family, "raceKey": race_key,
                        "runtimeRaceId": runtime_id, "sex": sex,
                        "assetPath": f"Character\\{race_key}\\{sex}.m2",
                        "sourceArchive": "fixture.MPQ", "evidencePath": str(model_path),
                        "sha256": camera._sha256(model_path), "bytes": len(data),
                        "bounds": camera._m2_bounds(model_path),
                        "previewDisplayId": index * 10 + sex_index + 1,
                        "modelDataId": index * 10 + sex_index + 1,
                        "extendedDisplayInfoId": index * 10 + sex_index + 1,
                        "previewDisplayScale": 1.0,
                    })
            (source / "races.json").write_text(json.dumps({"schemaVersion": 1, "entries": races}), encoding="utf-8")
            overrides = read_json(OVERRIDES)
            (source / "overrides/camera_profiles.json").write_text(json.dumps(overrides), encoding="utf-8")
            dbc = {}
            for name in ("ChrRaces.dbc", "CreatureDisplayInfo.dbc", "CreatureModelData.dbc"):
                path = temp / name
                path.write_bytes(b"WDBC" + struct.pack("<4I", 0, 0, 0, 0))
                dbc[name] = {"path": str(path), "sha256": camera._sha256(path), **camera._dbc_header(path)}
            evidence = {
                "schemaVersion": 1, "sourceBuild": "3.3.5.12340",
                "clientRoot": str(temp), "clientAssetProfile": "fixture",
                "dbc": dbc, "models": models,
            }
            evidence["evidenceHash"] = hashlib.sha256(camera._json_bytes(evidence)).hexdigest()
            evidence_root = temp / "evidence"
            evidence_root.mkdir()
            (evidence_root / "camera-profile-evidence.json").write_text(json.dumps(evidence), encoding="utf-8")
            self.assertEqual(180, len(camera.build_canonical(temp, evidence_root)["profiles"]))
            Path(models[0]["evidencePath"]).write_bytes(b"drift")
            with self.assertRaisesRegex(camera.CameraProfileError, "M2 evidence drift"):
                camera.build_canonical(temp, evidence_root)


if __name__ == "__main__":
    unittest.main()
