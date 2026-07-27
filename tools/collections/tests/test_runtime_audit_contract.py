from pathlib import Path
import unittest

from common import ROOT


class RuntimeAuditContractTests(unittest.TestCase):
    def test_qa_addon_is_read_only_bounded_and_not_in_release_addon(self):
        audit_root = ROOT / "tools/runtime/SoloCollectionsRuntimeAudit"
        toc = (audit_root / "SoloCollectionsRuntimeAudit.toc").read_text(encoding="utf-8")
        lua = (audit_root / "RuntimeAudit.lua").read_text(encoding="utf-8")
        self.assertIn("## Dependencies: SoloCollections", toc)
        self.assertIn("## SavedVariables: SoloCollectionsRuntimeAuditDB", toc)
        self.assertIn("REQUEST_INTERVAL = 0.25", lua)
        self.assertIn("REQUEST_TIMEOUT = 5", lua)
        self.assertIn("MODEL_WINDOW = 2", lua)
        self.assertIn("MODEL_RETRY_DELAYS = { 0.10, 0.25, 0.50 }", lua)
        self.assertIn("SC.Bridge.RequestCreaturePreview(", lua)
        self.assertIn('record.typeKey == "mount" and 10', lua)
        self.assertIn('record.typeKey == "companion" and 11', lua)
        self.assertIn("model:GetModel()", lua)
        self.assertIn("model:SetCreature(record.previewCreatureEntry)", lua)
        self.assertIn("staleGenerationDiscarded", lua)
        self.assertIn("SC.GeneratedCatalog.mappingHash", lua)
        self.assertIn("typeId,collectionId,previewCreatureEntry,previewStatus", lua)
        self.assertNotIn("ReloadUI()", lua)
        for forbidden in ("SummonMount", "SummonPet", "UseToy", "ApplyAppearance", "ApplySet"):
            self.assertNotIn(forbidden, lua)
        self.assertFalse((ROOT / "addon/SoloCollectionsRuntimeAudit").exists())

    def test_launcher_requires_closed_client_and_f_drive_output(self):
        script = (ROOT / "tools/runtime/Start-SoloCollectionsRuntimeAudit.ps1").read_text(encoding="utf-8")
        self.assertIn("Get-Process Wow", script)
        self.assertIn("output.StartsWith('F:\\'", script)
        self.assertIn("previous-SavedVariables.lua", script)
        self.assertIn("SoloCollectionsRuntimeAuditDB", script)

    def test_exporter_requires_complete_exact_zero_failure_evidence(self):
        script = (ROOT / "tools/runtime/Export-SoloCollectionsRuntimeAudit.ps1").read_text(encoding="utf-8")
        self.assertIn("Get-Process Wow", script)
        self.assertIn("output.StartsWith('F:\\'", script)
        self.assertIn("RuntimeAudit did not complete", script)
        self.assertIn("$mounts -ne 281", script)
        self.assertIn("$companions -ne $ExpectedCompanions", script)
        self.assertIn("$expectedTotal = 281 + $ExpectedCompanions", script)
        self.assertIn("ExpectedMappingHash", script)
        self.assertIn("$failed -ne 0", script)
        self.assertIn("staleGenerationDiscarded", script)
        self.assertIn("runtime-audit-summary.json", script)


if __name__ == "__main__":
    unittest.main()
