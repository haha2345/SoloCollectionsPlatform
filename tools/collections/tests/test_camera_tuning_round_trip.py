from __future__ import annotations

import copy
import importlib.util
import json
import unittest

from common import ROOT


IMPORT_TOOL = ROOT / "tools" / "catalog" / "camera_tuning_import.py"
ROUND_TRIP_TOOL = ROOT / "tools" / "catalog" / "camera_tuning_round_trip.py"


def load_tool(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    assert spec and spec.loader
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


camera_tuning_import = load_tool("camera_tuning_import_for_round_trip_test", IMPORT_TOOL)
camera_tuning_round_trip = load_tool("camera_tuning_round_trip_for_test", ROUND_TRIP_TOOL)


class CameraTuningRoundTripTests(unittest.TestCase):
    def setUp(self):
        self.source = json.loads(
            (ROOT / "catalog" / "source" / "appearance_presentations.json").read_text(encoding="utf-8")
        )
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

    def record(self, scope="model"):
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
                "yaw": 1.05,
                "pitch": -0.18,
                "roll": 0.97,
                "distanceScale": 0.72,
                "target": {"x": -0.44, "y": 0.0, "z": 0.0},
            },
        }

    def test_reviewed_model_candidate_stages_source_without_mutating_input(self):
        review = camera_tuning_import.validate_export(self.header, [self.record("model")], self.report)
        original = copy.deepcopy(self.source)
        staged, decisions = camera_tuning_round_trip.apply_candidates_to_source(
            self.source, self.report, review["candidates"]
        )
        self.assertEqual(original, self.source)
        self.assertEqual(1, len(decisions))
        expected_ids = sorted(
            row["appearanceId"]
            for row in self.report["entries"]
            if row.get("modelSignature") == self.entry["modelSignature"]
        )
        self.assertEqual(expected_ids, decisions[0]["affectedAppearanceIds"])
        staged_by_id = {row["appearanceId"]: row for row in staged["entries"]}
        for appearance_id in expected_ids:
            self.assertEqual(self.record()["pose"], staged_by_id[appearance_id]["m2Camera"])
            self.assertEqual(self.record()["pose"], staged_by_id[appearance_id]["autoCamera"])

    def test_overlapping_scopes_fail_closed(self):
        review = camera_tuning_import.validate_export(
            self.header, [self.record("model"), self.record("appearance")], self.report
        )
        with self.assertRaisesRegex(camera_tuning_round_trip.CameraTuningRoundTripError, "overlap"):
            camera_tuning_round_trip.apply_candidates_to_source(self.source, self.report, review["candidates"])


if __name__ == "__main__":
    unittest.main()
