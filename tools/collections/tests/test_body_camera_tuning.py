from __future__ import annotations

import copy
import importlib.util
import json
import sys
import unittest
from pathlib import Path

from common import ROOT


TOOLS = ROOT / "tools" / "catalog"
if str(TOOLS) not in sys.path:
    sys.path.insert(0, str(TOOLS))


def load_tool(name: str):
    spec = importlib.util.spec_from_file_location(name, TOOLS / f"{name}.py")
    module = importlib.util.module_from_spec(spec)
    assert spec and spec.loader
    spec.loader.exec_module(module)
    return module


importer = load_tool("body_camera_tuning_import")
review = load_tool("body_camera_tuning_review")
camera = load_tool("character_camera_profiles")

CANONICAL = ROOT / "catalog" / "source" / "camera_profiles.json"
OVERRIDES = ROOT / "catalog" / "source" / "overrides" / "camera_profiles.json"


class BodyCameraTuningTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.canonical = json.loads(CANONICAL.read_text(encoding="utf-8"))
        cls.overrides = json.loads(OVERRIDES.read_text(encoding="utf-8"))
        cls.profile = next(
            row for row in cls.canonical["profiles"]
            if row["raceKey"] == "human" and row["sex"] == "FEMALE" and row["slot"] == "CHEST"
        )
        cls.profile_key = importer.profile_key(cls.profile)

    def export_rows(self):
        profile = self.profile
        header = {
            "kind": importer.EXPORT_KIND,
            "schemaVersion": importer.SCHEMA_VERSION,
            "metadataVersion": "test-metadata-v1",
            "assetPackVersion": "test-assets-v1",
            "cameraProfileVersion": self.canonical["profileVersion"],
            "cameraProfileHash": self.canonical["profileHash"],
        }
        record = {
            "scope": "bodyProfile",
            "profileKey": self.profile_key,
            "sentinel": profile["sentinel"],
            "raceToken": importer.RACE_TOKENS[profile["raceKey"]],
            "clientAssetProfile": profile["cameraProfile"],
            "sex": profile["sex"],
            "slot": profile["slot"],
            "cameraProfileVersion": self.canonical["profileVersion"],
            "cameraProfileHash": self.canonical["profileHash"],
            "metadataVersion": header["metadataVersion"],
            "assetPackVersion": header["assetPackVersion"],
            "delta": {
                "verticalOffsetDelta": 0.25,
                "horizontalOffsetDelta": -0.125,
                "distanceScaleMultiplier": 1.05,
                "minimumDistanceDelta": 0.1,
                "yawOffsetDelta": 0.05,
            },
        }
        return header, record

    def candidates_from_export(self):
        header, record = self.export_rows()
        text = "\n".join(json.dumps(row, sort_keys=True) for row in (header, record)) + "\n"
        parsed_header, records = importer.parse_export(text)
        return importer.validate_export(parsed_header, records, self.canonical)

    def test_valid_export_is_reduced_to_a_profile_scoped_review_candidate(self):
        candidates = self.candidates_from_export()
        self.assertEqual("SoloCollectionsBodyCameraTuningReviewCandidates", candidates["kind"])
        self.assertEqual(self.canonical["profileHash"], candidates["cameraProfileHash"])
        self.assertEqual([self.profile_key], [row["profileKey"] for row in candidates["candidates"]])
        candidate = candidates["candidates"][0]
        self.assertEqual(self.profile["sentinel"], candidate["sentinel"])
        self.assertEqual(1.05, candidate["delta"]["distanceScaleMultiplier"])

    def test_import_rejects_stale_hash_and_duplicate_profile_target(self):
        header, record = self.export_rows()
        header["cameraProfileHash"] = "0" * 64
        with self.assertRaisesRegex(importer.BodyCameraTuningImportError, "camera profile hash mismatch"):
            importer.validate_export(header, [record], self.canonical)

        header, record = self.export_rows()
        with self.assertRaisesRegex(importer.BodyCameraTuningImportError, "duplicate or conflicting"):
            importer.validate_export(header, [record, copy.deepcopy(record)], self.canonical)

    def test_review_reports_base_proposed_and_approved_merge_stays_explicit(self):
        candidates = self.candidates_from_export()
        report = review.build_review_report(candidates, self.canonical)
        self.assertEqual([self.profile_key], report["affectedProfileKeys"])
        row = report["rows"][0]
        self.assertAlmostEqual(self.profile["verticalOffset"] + 0.25, row["proposed"]["verticalOffset"])
        self.assertEqual(1.05, row["magnitude"]["distanceScaleMultiplier"])

        with self.assertRaisesRegex(review.BodyCameraReviewError, "at least one approved"):
            review.merge_approved_deltas(candidates, self.canonical, self.overrides, set())

        merged = review.merge_approved_deltas(
            candidates, self.canonical, self.overrides, {self.profile_key}
        )
        self.assertEqual(self.overrides, json.loads(OVERRIDES.read_text(encoding="utf-8")))
        approved = merged["approvedBodyDeltas"]
        self.assertEqual(len(self.overrides.get("approvedBodyDeltas", [])) + 1, len(approved))
        approved_row = next(row for row in approved if row["profileKey"] == self.profile_key)
        self.assertEqual(self.canonical["profileHash"], approved_row["cameraProfileHash"])

    def test_approved_delta_changes_only_its_generated_profile_and_bad_types_fail_closed(self):
        races = json.loads((ROOT / "catalog/source/races.json").read_text(encoding="utf-8"))
        evidence = {
            "sourceBuild": self.canonical["sourceBuild"],
            "clientAssetProfile": self.canonical["clientAssetProfile"],
            "evidenceHash": self.canonical["evidenceHash"],
            "dbc": self.canonical["sourceEvidence"]["dbc"],
            "models": self.canonical["models"],
        }
        original_loader = camera._load_inputs
        try:
            baseline_overrides = copy.deepcopy(self.overrides)
            camera._load_inputs = lambda _root, _evidence: (races, baseline_overrides, evidence)
            baseline = camera.build_canonical(ROOT, ROOT)
            base_by_key = {
                importer.profile_key(row): row for row in baseline["profiles"]
            }
            target = base_by_key[self.profile_key]

            approved_overrides = copy.deepcopy(self.overrides)
            approved_overrides.setdefault("approvedBodyDeltas", []).append({
                "profileKey": self.profile_key,
                "sentinel": target["sentinel"],
                "cameraProfileVersion": baseline["profileVersion"],
                "cameraProfileHash": baseline["profileHash"],
                "verticalOffsetDelta": 0.25,
                "horizontalOffsetDelta": -0.125,
                "distanceScaleMultiplier": 1.05,
                "minimumDistanceDelta": 0.1,
                "yawOffsetDelta": 0.05,
            })
            camera._load_inputs = lambda _root, _evidence: (races, approved_overrides, evidence)
            generated = camera.build_canonical(ROOT, ROOT)
            generated_by_key = {
                importer.profile_key(row): row for row in generated["profiles"]
            }
            changed = generated_by_key[self.profile_key]
            self.assertEqual("approved_delta", changed["status"])
            self.assertAlmostEqual(target["verticalOffset"] + 0.25, changed["verticalOffset"])
            self.assertAlmostEqual(target["horizontalOffset"] - 0.125, changed["horizontalOffset"])
            self.assertAlmostEqual(target["distanceScale"] * 1.05, changed["distanceScale"])
            self.assertAlmostEqual(target["minimumDistance"] + 0.1, changed["minimumDistance"])
            self.assertAlmostEqual(target["yawOffset"] + 0.05, changed["yawOffset"])
            for key, row in base_by_key.items():
                if key != self.profile_key and key.startswith("human:female:"):
                    self.assertEqual(row, generated_by_key[key])

            malformed_overrides = copy.deepcopy(approved_overrides)
            malformed_overrides["approvedBodyDeltas"][-1]["sentinel"] = "not-a-number"
            camera._load_inputs = lambda _root, _evidence: (races, malformed_overrides, evidence)
            with self.assertRaisesRegex(camera.CameraProfileError, "invalid approved body delta sentinel"):
                camera.build_canonical(ROOT, ROOT)
        finally:
            camera._load_inputs = original_loader


if __name__ == "__main__":
    unittest.main()
