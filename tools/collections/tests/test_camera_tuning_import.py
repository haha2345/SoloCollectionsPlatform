from __future__ import annotations

import importlib.util
import json
import unittest

from common import ROOT


TOOL = ROOT / "tools" / "catalog" / "camera_tuning_import.py"
SPEC = importlib.util.spec_from_file_location("camera_tuning_import", TOOL)
assert SPEC and SPEC.loader
camera_tuning_import = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(camera_tuning_import)


class CameraTuningImportTests(unittest.TestCase):
    def setUp(self):
        self.report = json.loads(
            (ROOT / "catalog" / "generated" / "appearance-presentation-report.json").read_text(encoding="utf-8")
        )
        self.entry = self.report["entries"][0]
        self.header = {
            "kind": camera_tuning_import.EXPORT_KIND,
            "schemaVersion": 2,
            "metadataVersion": "2026.07.22.4",
            "assetPackVersion": self.report["assetPackVersion"],
            "appearancePresentationHash": camera_tuning_import._presentation_hash(self.report["entries"]),
        }

    def record(self, scope: str = "appearance"):
        if scope == "appearance":
            key = f"appearance:{self.entry['appearanceId']}"
        elif scope == "model":
            key = self.entry["modelSignature"]
        else:
            key = self.entry["cameraTuningKey"]
        return {
            "scope": scope,
            "key": key,
            "appearanceId": self.entry["appearanceId"],
            "sourceItemId": self.entry["sourceItemId"],
            "nativeDisplayId": self.entry["nativeDisplayId"],
            "syntheticDisplayId": self.entry["syntheticDisplayId"],
            "modelSignature": self.entry["modelSignature"],
            "weaponFamily": self.entry["cameraTuningKey"],
            "weaponType": self.entry["weaponType"],
            "slot": "MAINHAND",
            "metadataVersion": self.header["metadataVersion"],
            "assetPackVersion": self.header["assetPackVersion"],
            "appearancePresentationHash": self.header["appearancePresentationHash"],
            "pose": {
                "yaw": 0.1,
                "pitch": -0.1,
                "roll": 0.2,
                "distanceScale": 1.1,
                "target": {"x": 0.0, "y": -0.2, "z": 0.1},
            },
        }

    def test_valid_export_becomes_review_only_candidate(self):
        result = camera_tuning_import.validate_export(self.header, [self.record("model")], self.report)
        self.assertEqual("SoloCollectionsCameraTuningReviewCandidates", result["kind"])
        self.assertEqual(1, len(result["candidates"]))
        self.assertEqual("model", result["candidates"][0]["scope"])
        self.assertEqual(self.entry["modelSignature"], result["candidates"][0]["key"])

    def test_identity_or_hash_drift_is_rejected(self):
        bad_header = dict(self.header)
        bad_header["appearancePresentationHash"] = "0" * 64
        with self.assertRaisesRegex(camera_tuning_import.CameraTuningImportError, "hash mismatch"):
            camera_tuning_import.validate_export(bad_header, [self.record()], self.report)

        bad_record = self.record()
        bad_record["modelSignature"] = "m2:" + "0" * 64
        with self.assertRaisesRegex(camera_tuning_import.CameraTuningImportError, "model signature mismatch"):
            camera_tuning_import.validate_export(self.header, [bad_record], self.report)

        version_drift = self.record()
        version_drift["metadataVersion"] = "drift"
        with self.assertRaisesRegex(camera_tuning_import.CameraTuningImportError, "metadata version mismatch"):
            camera_tuning_import.validate_export(self.header, [version_drift], self.report)

    def test_scope_keys_pose_ranges_and_duplicates_are_rejected(self):
        wrong_key = self.record("appearance")
        wrong_key["key"] = self.entry["modelSignature"]
        with self.assertRaisesRegex(camera_tuning_import.CameraTuningImportError, "appearance scope key"):
            camera_tuning_import.validate_export(self.header, [wrong_key], self.report)

        out_of_range = self.record("weaponFamily")
        out_of_range["pose"]["distanceScale"] = 8.0
        with self.assertRaisesRegex(camera_tuning_import.CameraTuningImportError, "out-of-range"):
            camera_tuning_import.validate_export(self.header, [out_of_range], self.report)

        duplicate = self.record("weaponFamily")
        with self.assertRaisesRegex(camera_tuning_import.CameraTuningImportError, "duplicate"):
            camera_tuning_import.validate_export(self.header, [duplicate, self.record("weaponFamily")], self.report)


if __name__ == "__main__":
    unittest.main()
