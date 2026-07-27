from __future__ import annotations

import importlib.util
import json
import unittest
from pathlib import Path

from common import ROOT


TOOL = ROOT / "tools" / "catalog" / "weapon_presentations.py"
SPEC = importlib.util.spec_from_file_location("weapon_presentations", TOOL)
assert SPEC and SPEC.loader
weapon_presentations = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(weapon_presentations)

AUDIT_TOOL = ROOT / "tools" / "runtime" / "New-WeaponPresentationAuditData.py"
AUDIT_SPEC = importlib.util.spec_from_file_location("weapon_presentation_audit_data", AUDIT_TOOL)
assert AUDIT_SPEC and AUDIT_SPEC.loader
weapon_presentation_audit_data = importlib.util.module_from_spec(AUDIT_SPEC)
AUDIT_SPEC.loader.exec_module(weapon_presentation_audit_data)
PERFORMANCE_LAUNCHER = ROOT / "tools" / "runtime" / "Start-SoloCollectionsWeaponPresentationAudit.ps1"
VISUAL_PLAN_TOOL = ROOT / "tools" / "runtime" / "New-WeaponPresentationVisualSamplePlan.py"
VISUAL_PLAN_SPEC = importlib.util.spec_from_file_location("weapon_presentation_visual_sample_plan", VISUAL_PLAN_TOOL)
assert VISUAL_PLAN_SPEC and VISUAL_PLAN_SPEC.loader
weapon_presentation_visual_sample_plan = importlib.util.module_from_spec(VISUAL_PLAN_SPEC)
VISUAL_PLAN_SPEC.loader.exec_module(weapon_presentation_visual_sample_plan)


class WeaponPresentationTests(unittest.TestCase):
    def test_production_source_has_closed_public_terminal_states(self):
        source = json.loads(
            (ROOT / "catalog/source/appearance_presentations.json").read_text(encoding="utf-8")
        )
        self.assertEqual(2, source["schemaVersion"])
        self.assertEqual(3690, source["publicAppearanceCount"])
        self.assertEqual({"READY": 3541, "UNAVAILABLE": 149}, source["terminalCounts"])
        self.assertEqual(3691, len(source["entries"]))
        public = [entry for entry in source["entries"] if entry["presentationStatus"] != "RETAINED_BASELINE"]
        self.assertEqual(3690, len(public))
        self.assertEqual({"READY", "UNAVAILABLE"}, {entry["presentationStatus"] for entry in public})
        self.assertTrue(all(
            entry["presentationReasonCode"]
            for entry in public if entry["presentationStatus"] == "UNAVAILABLE"
        ))

    def test_checked_in_source_matches_runtime_safe_evidence_when_installed(self):
        evidence = ROOT.parent / "evidence"
        runtime_review = evidence / "round3-weapon-bundles-20260723" / "stage7-runtime-review-v1"
        stage = evidence / "round3-weapon-bundles-20260723" / "stage8-production-v2"
        shadow = evidence / "round3-weapon-shadow-20260723-stage6-stormbatch"
        if not all(path.is_dir() for path in (runtime_review, stage, shadow)):
            self.skipTest("stage-8 immutable weapon evidence is not installed")
        source_path = ROOT / "catalog/source/appearance_presentations.json"
        actual = json.loads(source_path.read_text(encoding="utf-8"))
        expected = weapon_presentations.render_source(
            ROOT / "catalog/source/appearance_presentations_baseline.json",
            ROOT / "catalog/generated/appearance-sources.json",
            runtime_review,
            stage,
            shadow,
            actual["assetPackVersion"],
        )
        self.assertEqual(expected, actual)

    def test_runtime_audit_data_is_bound_to_the_public_production_contract(self):
        metadata, records = weapon_presentation_audit_data.load_contract(
            ROOT / "catalog/source/appearance_presentations.json",
            ROOT / "catalog/generated/appearance-presentation-report.json",
            ROOT / "catalog/generated/catalog-manifest.json",
        )
        self.assertEqual("round-two-stage8-weapon-presentation-v2", metadata["bundleId"])
        self.assertEqual(3690, metadata["publicCount"])
        self.assertEqual(3541, metadata["readyCount"])
        self.assertEqual(149, metadata["unavailableCount"])
        self.assertEqual(3690, len(records))
        self.assertEqual(["READY", "UNAVAILABLE"], sorted({record["presentationStatus"] for record in records}))
        fishing_pole = next(record for record in records if record["appearanceId"] == 203258)
        self.assertEqual(43651, fishing_pole["sourceItemId"])
        self.assertEqual(6367, fishing_pole["displayItemId"])
        rendered = weapon_presentation_audit_data.render(metadata, records, "reload", True, 8.0)
        self.assertIn('cacheState = "reload"', rendered)
        self.assertIn("appearancePresentationHash", rendered)
        self.assertEqual(3690, rendered.count("appearanceId = "))

    def test_reviewed_outlier_is_promoted_as_a_model_default_not_an_appearance_override(self):
        source = json.loads(
            (ROOT / "catalog/source/appearance_presentations.json").read_text(encoding="utf-8")
        )
        self.assertEqual(1, source["modelCameraOverrides"]["count"])
        target = next(row for row in source["entries"] if row["appearanceId"] == 217942)
        override = target["generatedModelCameraOverride"]
        self.assertEqual("model", override["scope"])
        self.assertEqual(target["modelSignature"], override["key"])
        self.assertEqual("HEADER_BOUNDS_INCLUDE_EFFECTS", override["reasonCode"])
        self.assertEqual(0.6, override["pose"]["distanceScale"])
        self.assertEqual(
            "bca7f99a94d7e00015a58a4a07c620fc191f50df50760992645f6e30cebd85a2",
            target["assetHashes"]["m2"],
        )

    def test_runtime_audit_data_can_enable_bounded_performance_rounds(self):
        metadata, records = weapon_presentation_audit_data.load_contract(
            ROOT / "catalog/source/appearance_presentations.json",
            ROOT / "catalog/generated/appearance-presentation-report.json",
            ROOT / "catalog/generated/catalog-manifest.json",
        )
        metadata.update({"performanceMode": True, "performanceRounds": 2})
        rendered = weapon_presentation_audit_data.render(metadata, records, "hot", True, 8.0)
        self.assertIn("performanceMode = true", rendered)
        self.assertIn("performanceRounds = 2", rendered)
        self.assertNotIn("visualCapture = true", rendered)

    def test_performance_launcher_makes_cold_cache_an_actual_wdb_transition(self):
        launcher = PERFORMANCE_LAUNCHER.read_text(encoding="utf-8")
        self.assertIn("ColdWdbBackupRoot", launcher)
        self.assertIn("Backup-ClientWdb.ps1", launcher)
        self.assertIn("Restore-ClientWdb.ps1", launcher)
        self.assertIn("if ($CacheState -eq 'cold')", launcher)
        self.assertIn("coldWdbRestored", launcher)

    def test_legacy_baseline_plan_keeps_all_poses_and_selects_public_visual_records(self):
        source = json.loads(
            (ROOT / "catalog/source/appearance_presentations.json").read_text(encoding="utf-8")
        )
        baseline = json.loads(
            (ROOT / "catalog/source/appearance_presentations_baseline.json").read_text(encoding="utf-8")
        )
        groups = weapon_presentation_visual_sample_plan.load_groups(
            ROOT / "catalog/generated/appearance-sources.json"
        )
        candidates = weapon_presentation_visual_sample_plan.load_candidates(
            ROOT / "catalog/review/weapons/shadow-candidates.csv"
        )
        all_records = weapon_presentation_visual_sample_plan.make_records(source, groups, candidates)
        selected, coverage = weapon_presentation_visual_sample_plan.select_baseline_regression(
            source, all_records, baseline
        )
        self.assertEqual(21, coverage["baselineAppearanceCount"])
        self.assertEqual(20, coverage["publicVisualSampleCount"])
        self.assertEqual([212036], coverage["retainedNonPublicAppearanceIds"])
        self.assertEqual(20, len(selected))
        self.assertTrue(all(record["sampleKinds"] == ["LEGACY_BASELINE_VISUAL"] for record in selected))


if __name__ == "__main__":
    unittest.main()
