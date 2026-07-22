from __future__ import annotations

import unittest

from common import ADDON, ROOT, load_json, read_text


BOOTSTRAP = ADDON / "Core" / "Bootstrap.lua"
M2_CAMERA = ADDON / "Core" / "M2Camera.lua"
WARDROBE = ADDON / "UI" / "Wardrobe.lua"
PRESENTATION_REPORT = ROOT / "catalog" / "generated" / "appearance-presentation-report.json"
PRESENTATION_SOURCE = ROOT / "catalog" / "source" / "appearance_presentations.json"
IMPORTER = ROOT / "tools" / "catalog" / "camera_tuning_import.py"


class CameraWorkbenchContractTests(unittest.TestCase):
    def test_saved_variables_migrate_and_stay_sparse(self):
        source = read_text(BOOTSTRAP)
        self.assertIn("CAMERA_TUNING_SCHEMA_VERSION = 2", source)
        self.assertIn("MAX_CAMERA_TUNING_SCOPE_ENTRIES = 512", source)
        self.assertIn("MAX_LEGACY_CAMERA_TUNING_BACKUP_ENTRIES = 128", source)
        self.assertIn("legacyM2CameraTuningV1", source)
        self.assertIn("normalizedCameraScope(tuning.model, \"model\"", source)
        self.assertIn("normalizedCameraScope(tuning.appearance, \"appearance\"", source)
        self.assertIn("normalizedCameraScope(tuning.bodyProfile, \"bodyProfile\"", source)
        self.assertIn("db.cameraTuning = nil", source)
        self.assertIn("local stored = entries[key]", source)
        self.assertIn('if type(stored) ~= "table" then return nil end', source)
        self.assertNotIn("cameraTuning = {}", source.split("local DEFAULTS", 1)[1].split("local VALID_POINTS", 1)[0])

    def test_effective_pose_and_scope_editing_have_independent_precedence(self):
        source = read_text(WARDROBE)
        effective = source[source.index("local function getEffectiveM2CameraPose"):source.index("local function isM2CameraTunableRecord")]
        positions = [effective.index(token) for token in ("appearance", "modelPose", "weaponFamily", "autoCamera")]
        self.assertEqual(positions, sorted(positions))
        scoped = source[source.index("local function resolveM2CameraScopePose"):source.index("local function getEffectiveM2CameraPose")]
        self.assertIn("{ appearance = true, model = true }", scoped)
        self.assertIn("getAutoM2CameraPose(record)", scoped)
        self.assertIn("resolveM2CameraScopePose(cameraTuningPanel.scRecord, scope)", source)
        self.assertIn("CameraTuning.Reset(scope, tuningKey)", source)

    def test_generated_standalone_records_provide_stable_identity_and_auto_baseline(self):
        report = load_json(PRESENTATION_REPORT)
        self.assertEqual(2, report["schemaVersion"])
        self.assertGreater(report["presentationCount"], 0)
        for entry in report["entries"]:
            self.assertRegex(entry["modelSignature"], r"^m2:[a-f0-9]{64}$")
            self.assertEqual({"yaw", "pitch", "roll", "distanceScale", "target"}, set(entry["autoCamera"]))
            self.assertEqual({"x", "y", "z"}, set(entry["autoCamera"]["target"]))

    def test_current_verified_weapon_baselines_are_zero_drift_from_source(self):
        source = load_json(PRESENTATION_SOURCE)["entries"]
        report = load_json(PRESENTATION_REPORT)["entries"]
        self.assertEqual(21, len(source))
        self.assertEqual(21, len(report))
        source_by_appearance = {entry["appearanceId"]: entry for entry in source}
        report_by_appearance = {entry["appearanceId"]: entry for entry in report}
        self.assertEqual(set(source_by_appearance), set(report_by_appearance))
        for appearance_id, source_entry in source_by_appearance.items():
            self.assertEqual(
                source_entry["m2Camera"],
                report_by_appearance[appearance_id]["autoCamera"],
                msg=f"appearance {appearance_id} camera baseline drifted",
            )

    def test_workbench_reflows_inside_item_page_and_exposes_complete_controls(self):
        source = read_text(WARDROBE)
        self.assertIn("WORKBENCH_ITEM_COLUMNS = 4", source)
        self.assertIn("WORKBENCH_ITEM_PAGE_SIZE", source)
        self.assertIn("function page:UpdateCameraWorkbenchLayout()", source)
        self.assertIn("cameraTuningPanel:SetPoint(\"TOPRIGHT\", itemsPanel", source)
        self.assertIn("self:UpdateCameraWorkbenchLayout()", source)
        self.assertIn("page.scItemPageSize or ITEM_PAGE_SIZE", source)
        for label in ("武器类别", "此模型", "此外观", "上一条", "下一条", "上一条未校准", "下一条未校准"):
            self.assertIn(label, source)
        for token in ("tuningPrevious", "tuningNext", "tuningPreviousUncalibrated", "tuningNextUncalibrated"):
            self.assertIn(token, source)
        self.assertIn("presentationReasonCode", source)
        self.assertIn('local slider = CreateFrame("Slider", sliderName, row)', source)
        self.assertIn('slider:SetThumbTexture(sliderThumb)', source)
        self.assertNotIn('"OptionsSliderTemplate"', source)
        sync = source[source.index("cameraTuningPanel.scRecord = record"):source.index("cameraTuningPanel.scSyncing = nil")]
        self.assertLess(sync.index("cameraTuningPanel.scSyncing = true"), sync.index("setCameraTuningControlsEnabled(true)"))
        self.assertLess(sync.index("cameraTuningPanel:Show()"), sync.index("control.slider:SetValue(value)"))

    def test_export_and_import_are_versioned_identity_checked_jsonl(self):
        camera = read_text(M2_CAMERA)
        importer = read_text(IMPORTER)
        for token in ("metadataVersion", "assetPackVersion", "appearancePresentationHash", "weaponType", "slot"):
            self.assertIn(token, camera)
            self.assertIn(token, importer)
        self.assertIn("SoloCollectionsCameraTuningExport", camera)
        self.assertIn("duplicate or conflicting tuning target", importer)
        self.assertIn("record asset pack version mismatch", importer)
        self.assertIn("record appearance presentation hash mismatch", importer)


if __name__ == "__main__":
    unittest.main()
