from __future__ import annotations

import json
import unittest

from common import ROOT, read_text


class RoundTwoReleaseToolsTests(unittest.TestCase):
    def test_all_required_release_tools_exist(self):
        release = ROOT / "tools/release"
        for name in (
            "deployment-profile.schema.json", "Initialize-RoundTwoEnvironment.ps1",
            "New-SoloCollectionsBuildInfo.ps1", "New-RoundTwoBundle.ps1",
            "Test-RoundTwoBundle.ps1", "Install-RoundTwoBundle.ps1",
            "Restore-RoundTwoBundle.ps1", "Test-RepositoryHygiene.ps1",
        ):
            self.assertTrue((release / name).is_file(), name)

    def test_profile_schema_declares_exact_roots_and_control_modes(self):
        schema = json.loads(read_text(ROOT / "tools/release/deployment-profile.schema.json"))
        required = set(schema["required"])
        self.assertTrue({
            "serverRoot", "worldserverExeTarget", "worldserverWorkingDirectory",
            "worldserverDependencyTargets", "runtimeModuleConfig", "addonRoot", "clientRoot",
            "soloCamDllTarget", "assetPatchTargets", "wdbRoots", "backupRoot", "serverControl",
        }.issubset(required))
        text = read_text(ROOT / "tools/release/RoundTwoRelease.Common.ps1")
        for mode in ("WINDOWS_SERVICE", "EXTERNAL_COMMAND", "MANUAL"):
            self.assertIn(mode, text)
        self.assertNotIn("Stop-Process", text)

    def test_bundle_is_static_explicit_and_hash_verified(self):
        create = read_text(ROOT / "tools/release/New-RoundTwoBundle.ps1")
        verify = read_text(ROOT / "tools/release/Test-RoundTwoBundle.ps1")
        self.assertIn("Assert-RoundTwoWithin -Path $worldserver -Root $build", create)
        self.assertIn("modules='static'", create)
        self.assertIn("Get-RoundTwoPeInfo", create)
        self.assertNotIn("Copy-Item -Path", create)
        self.assertIn("Get-RoundTwoSha256", verify)
        self.assertIn("module-build-metadata.json", verify)

    def test_install_and_restore_are_manifested_without_recursive_deletion(self):
        install = read_text(ROOT / "tools/release/Install-RoundTwoBundle.ps1")
        restore = read_text(ROOT / "tools/release/Restore-RoundTwoBundle.ps1")
        self.assertIn("backup-manifest.json", install)
        self.assertIn("originalSha256", install)
        self.assertIn("installedSha256", restore)
        self.assertNotIn("-Recurse", restore)
        self.assertNotIn("Stop-Process", install + restore)


if __name__ == "__main__":
    unittest.main()
