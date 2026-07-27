from __future__ import annotations

import json
import os
import shutil
import subprocess
import unittest
import uuid
from pathlib import Path

from common import ROOT


POWERSHELL = "powershell.exe"
RUNTIME = ROOT / "tools" / "runtime"


class WdbColdCacheTests(unittest.TestCase):
    def setUp(self):
        self.root = ROOT / "_work" / "test-temp" / f"wdb-{uuid.uuid4().hex}"
        self.client = self.root / "client"
        self.backup = self.root / "backup"
        self.wdb = self.client / "Cache" / "WDB" / "enUS"
        self.wdb.mkdir(parents=True)
        (self.wdb / "creaturecache.wdb").write_bytes(b"old-creature-cache")
        (self.wdb / "nested").mkdir()
        (self.wdb / "nested" / "itemcache.wdb").write_bytes(b"old-item-cache")

    def tearDown(self):
        expected = (ROOT / "_work" / "test-temp").resolve()
        resolved = self.root.resolve()
        self.assertTrue(str(resolved).startswith(str(expected) + os.sep))
        if self.root.exists():
            shutil.rmtree(self.root)

    def run_script(self, name: str, *extra: str) -> subprocess.CompletedProcess[str]:
        env = os.environ.copy()
        env["TEMP"] = str(self.root)
        env["TMP"] = str(self.root)
        return subprocess.run(
            [
                POWERSHELL,
                "-NoProfile",
                "-ExecutionPolicy",
                "Bypass",
                "-File",
                str(RUNTIME / name),
                "-ClientRoot",
                str(self.client),
                "-Locale",
                "enUS",
                "-BackupRoot",
                str(self.backup),
                *extra,
            ],
            capture_output=True,
            text=True,
            encoding="utf-8",
            errors="replace",
            env=env,
            check=False,
        )

    def test_backup_restore_preserves_old_and_quarantines_generated_cache(self):
        old_bytes = {
            path.relative_to(self.wdb).as_posix(): path.read_bytes()
            for path in self.wdb.rglob("*")
            if path.is_file()
        }
        backup = self.run_script("Backup-ClientWdb.ps1")
        self.assertEqual(0, backup.returncode, backup.stderr + backup.stdout)
        manifest_path = self.backup / "wdb-backup-manifest.json"
        manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
        self.assertEqual("BACKED_UP", manifest["state"])
        self.assertFalse(self.wdb.exists())
        self.assertTrue(Path(manifest["coldDirectoryPath"]).is_dir())
        self.assertEqual(2, len(manifest["oldFiles"]))

        self.wdb.mkdir(parents=True)
        (self.wdb / "creaturecache.wdb").write_bytes(b"generated-during-test")
        restore = self.run_script("Restore-ClientWdb.ps1")
        self.assertEqual(0, restore.returncode, restore.stderr + restore.stdout)
        restored = {
            path.relative_to(self.wdb).as_posix(): path.read_bytes()
            for path in self.wdb.rglob("*")
            if path.is_file()
        }
        self.assertEqual(old_bytes, restored)
        manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
        self.assertEqual("RESTORED", manifest["state"])
        self.assertEqual(1, len(manifest["generatedDuringTest"]))
        quarantine = Path(manifest["generatedDuringTest"][0]["quarantinePath"])
        self.assertEqual(b"generated-during-test", (quarantine / "creaturecache.wdb").read_bytes())
        self.assertTrue((quarantine / "generated-wdb-manifest.json").is_file())

        repeat = self.run_script("Restore-ClientWdb.ps1")
        self.assertEqual(0, repeat.returncode, repeat.stderr + repeat.stdout)
        self.assertIn("already restored", repeat.stdout.lower())

    def test_restore_fails_closed_when_verified_cold_copy_changes(self):
        backup = self.run_script("Backup-ClientWdb.ps1")
        self.assertEqual(0, backup.returncode, backup.stderr + backup.stdout)
        manifest = json.loads((self.backup / "wdb-backup-manifest.json").read_text(encoding="utf-8"))
        cold_file = Path(manifest["coldDirectoryPath"]) / "creaturecache.wdb"
        cold_file.write_bytes(b"tampered")
        restore = self.run_script("Restore-ClientWdb.ps1")
        self.assertNotEqual(0, restore.returncode)
        self.assertIn("manifest mismatch", (restore.stderr + restore.stdout).lower())
        self.assertFalse(self.wdb.exists())

    def test_backup_rejects_system_drive_output_before_creating_it(self):
        invalid = Path("C:/solo-collections-wdb-test-must-not-exist")
        result = subprocess.run(
            [
                POWERSHELL,
                "-NoProfile",
                "-ExecutionPolicy",
                "Bypass",
                "-File",
                str(RUNTIME / "Backup-ClientWdb.ps1"),
                "-ClientRoot",
                str(self.client),
                "-Locale",
                "enUS",
                "-BackupRoot",
                str(invalid),
            ],
            capture_output=True,
            text=True,
            encoding="utf-8",
            errors="replace",
            check=False,
        )
        self.assertNotEqual(0, result.returncode)
        self.assertIn("must stay off the windows system drive", (result.stderr + result.stdout).lower())
        self.assertFalse(invalid.exists())

    def test_scripts_never_recursively_delete_cache_or_quarantine(self):
        combined = "\n".join(
            (RUNTIME / name).read_text(encoding="utf-8-sig")
            for name in ("WdbState.Common.ps1", "Backup-ClientWdb.ps1", "Restore-ClientWdb.ps1")
        )
        self.assertNotIn("Remove-Item", combined)
        self.assertIn("wdb-operation-journal.jsonl", combined)
        self.assertIn("generated-during-test", combined)


if __name__ == "__main__":
    unittest.main()
