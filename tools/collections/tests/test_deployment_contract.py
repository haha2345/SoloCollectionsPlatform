from __future__ import annotations

import json
import os
import subprocess
import tempfile
import unittest
from pathlib import Path

from common import TOOLS, load_json


POWERSHELL = "powershell.exe"


def run_ps(script: Path, *args: str, env: dict[str, str] | None = None) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        [POWERSHELL, "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", str(script), *args],
        capture_output=True,
        text=True,
        encoding="utf-8",
        errors="replace",
        check=False,
        env=env,
    )


class DeploymentContractTests(unittest.TestCase):
    def setUp(self):
        self.deploy = TOOLS / "deploy_phase1.ps1"
        self.verify = TOOLS / "verify_phase1.ps1"

    def test_deploy_script_has_repo_relative_sources_safe_targets_and_literal_copy(self):
        self.assertTrue(self.deploy.is_file(), f"missing {self.deploy}")
        text = self.deploy.read_text(encoding="utf-8-sig")
        self.assertIn("SupportsShouldProcess", text)
        self.assertIn("Test-FullyQualifiedPath", text)
        self.assertIn("GetFullPath", text)
        self.assertIn("Copy-Item -LiteralPath", text)
        self.assertIn("Join-Path $RepoRoot 'addon\\SoloCollections'", text)
        self.assertIn('[Parameter(Mandatory = $true)][string]$AddonTarget', text)
        self.assertIn("Join-Path $RepoRoot 'server\\ale\\solo_collections.lua'", text)
        self.assertIn('[Parameter(Mandatory = $true)][string]$ServerLuaTarget', text)
        self.assertNotIn("Remove-Item -Recurse", text)
        self.assertNotIn("Copy-Item *", text)

    def test_verifier_hashing_does_not_require_get_file_hash_cmdlet(self):
        text = self.verify.read_text(encoding="utf-8-sig")
        self.assertIn("System.Security.Cryptography.SHA256", text)
        self.assertIn("System.IO.File]::OpenRead", text)
        self.assertNotIn("Get-FileHash", text)

    def test_whatif_lists_operations_and_writes_nothing(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            source = root / "source" / "SoloCollections"
            target = root / "live" / "SoloCollections"
            server_source = root / "source-server" / "solo_collections.lua"
            server_target = root / "live-server" / "solo_collections.lua"
            backup = root / "backups"
            stage = root / "staging"
            source.mkdir(parents=True)
            server_source.parent.mkdir(parents=True)
            (source / "new.lua").write_text("new", encoding="utf-8")
            server_source.write_text("server", encoding="utf-8")

            result = run_ps(
                self.deploy,
                "-WhatIf",
                "-AddonSource", str(source),
                "-AddonTarget", str(target),
                "-ServerLuaSource", str(server_source),
                "-ServerLuaTarget", str(server_target),
                "-BackupRoot", str(backup),
                "-StageRoot", str(stage),
            )
            self.assertEqual(0, result.returncode, result.stderr + result.stdout)
            self.assertIn("CREATE", result.stdout)
            self.assertFalse(target.exists())
            self.assertFalse(server_target.exists())
            self.assertFalse(backup.exists())

    def test_whatif_can_hash_existing_same_and_different_targets_without_writes(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            source = root / "source" / "SoloCollections"
            target = root / "live" / "SoloCollections"
            server_source = root / "source-server" / "solo_collections.lua"
            server_target = root / "live-server" / "solo_collections.lua"
            backup = root / "backups"
            stage = root / "staging"
            source.mkdir(parents=True)
            target.mkdir(parents=True)
            server_source.parent.mkdir(parents=True)
            server_target.parent.mkdir(parents=True)
            (source / "same.lua").write_text("same", encoding="utf-8")
            (target / "same.lua").write_text("same", encoding="utf-8")
            (source / "changed.lua").write_text("new", encoding="utf-8")
            (target / "changed.lua").write_text("old", encoding="utf-8")
            server_source.write_text("new-server", encoding="utf-8")
            server_target.write_text("old-server", encoding="utf-8")
            before = {
                target / "same.lua": (target / "same.lua").read_bytes(),
                target / "changed.lua": (target / "changed.lua").read_bytes(),
                server_target: server_target.read_bytes(),
            }

            result = run_ps(
                self.deploy,
                "-WhatIf",
                "-AddonSource", str(source),
                "-AddonTarget", str(target),
                "-ServerLuaSource", str(server_source),
                "-ServerLuaTarget", str(server_target),
                "-BackupRoot", str(backup),
                "-StageRoot", str(stage),
            )
            self.assertEqual(0, result.returncode, result.stderr + result.stdout)
            self.assertIn("UNCHANGED same.lua", result.stdout)
            self.assertIn("UPDATE    changed.lua", result.stdout)
            self.assertIn("UPDATE    solo_collections.lua", result.stdout)
            self.assertIn("WOULD_BACKUP", result.stdout)
            self.assertFalse(any(line.startswith("BACKUP ") for line in result.stdout.splitlines()))
            for path, content in before.items():
                self.assertEqual(content, path.read_bytes())
            self.assertFalse(backup.exists())

    def test_actual_deploy_is_additive_and_backs_up_existing_files(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            source = root / "source" / "SoloCollections"
            target = root / "live" / "SoloCollections"
            server_source = root / "source-server" / "solo_collections.lua"
            server_target = root / "live-server" / "solo_collections.lua"
            backup = root / "backups"
            stage = root / "staging"
            (source / "Core").mkdir(parents=True)
            target.mkdir(parents=True)
            server_source.parent.mkdir(parents=True)
            server_target.parent.mkdir(parents=True)
            (source / "Core" / "new.lua").write_text("new", encoding="utf-8")
            (source / "same.lua").write_text("same", encoding="utf-8")
            (target / "Core").mkdir()
            (target / "Core" / "new.lua").write_text("old", encoding="utf-8")
            (target / "same.lua").write_text("same", encoding="utf-8")
            (target / "unrelated.user").write_text("preserve", encoding="utf-8")
            server_source.write_text("new-server", encoding="utf-8")
            server_target.write_text("old-server", encoding="utf-8")

            result = run_ps(
                self.deploy,
                "-AddonSource", str(source),
                "-AddonTarget", str(target),
                "-ServerLuaSource", str(server_source),
                "-ServerLuaTarget", str(server_target),
                "-BackupRoot", str(backup),
                "-StageRoot", str(stage),
            )
            self.assertEqual(0, result.returncode, result.stderr + result.stdout)
            self.assertEqual("new", (target / "Core" / "new.lua").read_text(encoding="utf-8"))
            self.assertEqual("preserve", (target / "unrelated.user").read_text(encoding="utf-8"))
            self.assertEqual("new-server", server_target.read_text(encoding="utf-8"))
            backups = list(backup.glob("*/SoloCollections/Core/new.lua"))
            self.assertEqual(1, len(backups))
            self.assertEqual("old", backups[0].read_text(encoding="utf-8"))

    def test_preflight_rejects_target_file_directory_and_parent_file_collisions(self):
        scenarios = ("addon_file_is_directory", "addon_parent_is_file", "server_target_is_directory")
        for scenario in scenarios:
            with self.subTest(scenario=scenario), tempfile.TemporaryDirectory() as temp:
                root = Path(temp)
                source = root / "source" / "SoloCollections"
                target = root / "live" / "SoloCollections"
                server_source = root / "source-server" / "solo_collections.lua"
                server_target = root / "live-server" / "solo_collections.lua"
                backup = root / "backups"
                stage = root / "staging"
                source.mkdir(parents=True)
                server_source.parent.mkdir(parents=True)
                server_target.parent.mkdir(parents=True)
                server_source.write_text("server", encoding="utf-8")
                if scenario == "addon_file_is_directory":
                    (source / "entry.lua").write_text("new", encoding="utf-8")
                    (target / "entry.lua").mkdir(parents=True)
                elif scenario == "addon_parent_is_file":
                    (source / "Core").mkdir()
                    (source / "Core" / "entry.lua").write_text("new", encoding="utf-8")
                    target.mkdir(parents=True)
                    (target / "Core").write_text("collision", encoding="utf-8")
                else:
                    (source / "entry.lua").write_text("new", encoding="utf-8")
                    server_target.mkdir()

                result = run_ps(
                    self.deploy,
                    "-AddonSource", str(source), "-AddonTarget", str(target),
                    "-ServerLuaSource", str(server_source), "-ServerLuaTarget", str(server_target),
                    "-BackupRoot", str(backup), "-StageRoot", str(stage),
                )
                self.assertNotEqual(0, result.returncode)
                self.assertIn("collision", (result.stderr + result.stdout).lower())
                self.assertFalse(backup.exists())
                self.assertFalse(stage.exists())

    def test_rejects_drive_relative_root_relative_and_overlapping_paths(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            source = root / "source" / "SoloCollections"
            target = root / "live" / "SoloCollections"
            server_source = root / "source-server" / "solo_collections.lua"
            server_target = root / "live-server" / "solo_collections.lua"
            source.mkdir(parents=True)
            server_source.parent.mkdir(parents=True)
            (source / "entry.lua").write_text("new", encoding="utf-8")
            server_source.write_text("server", encoding="utf-8")
            base = (
                "-AddonTarget", str(target), "-ServerLuaSource", str(server_source),
                "-ServerLuaTarget", str(server_target), "-BackupRoot", str(root / "backups"),
                "-StageRoot", str(root / "staging"),
            )
            for invalid in (r"C:relative\SoloCollections", r"\relative\SoloCollections"):
                result = run_ps(self.deploy, "-AddonSource", invalid, *base)
                self.assertNotEqual(0, result.returncode)
                self.assertIn("fully qualified", (result.stderr + result.stdout).lower())

            overlap_cases = (
                (source, source / "nested" / "SoloCollections", root / "backups", root / "staging"),
                (target / "nested" / "SoloCollections", target, root / "backups", root / "staging"),
                (source, target, source / "backups", root / "staging"),
                (source, target, root / "backups", target / "staging"),
            )
            for addon_source, addon_target, backup, stage in overlap_cases:
                addon_source.mkdir(parents=True, exist_ok=True)
                (addon_source / "entry.lua").write_text("new", encoding="utf-8")
                result = run_ps(
                    self.deploy,
                    "-AddonSource", str(addon_source), "-AddonTarget", str(addon_target),
                    "-ServerLuaSource", str(server_source), "-ServerLuaTarget", str(server_target),
                    "-BackupRoot", str(backup), "-StageRoot", str(stage), "-WhatIf",
                )
                self.assertNotEqual(0, result.returncode)
                self.assertIn("overlap", (result.stderr + result.stdout).lower())

    def test_transaction_rolls_back_overwrites_and_created_files_on_mid_commit_failure(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            source = root / "source" / "SoloCollections"
            target = root / "live" / "SoloCollections"
            server_source = root / "source-server" / "solo_collections.lua"
            server_target = root / "live-server" / "solo_collections.lua"
            backup = root / "backups"
            stage = root / "staging"
            source.mkdir(parents=True)
            target.mkdir(parents=True)
            server_source.parent.mkdir(parents=True)
            server_target.parent.mkdir(parents=True)
            (source / "a.lua").write_text("new-a", encoding="utf-8")
            (source / "b.lua").write_text("new-b", encoding="utf-8")
            (target / "a.lua").write_text("old-a", encoding="utf-8")
            (target / "unrelated.user").write_text("preserve", encoding="utf-8")
            server_source.write_text("new-server", encoding="utf-8")
            server_target.write_text("old-server", encoding="utf-8")
            env = os.environ.copy()
            env["SOLO_COLLECTIONS_DEPLOY_TEST_MODE"] = "1"

            result = run_ps(
                self.deploy,
                "-AddonSource", str(source), "-AddonTarget", str(target),
                "-ServerLuaSource", str(server_source), "-ServerLuaTarget", str(server_target),
                "-BackupRoot", str(backup), "-StageRoot", str(stage),
                "-SimulateFailureAfter", "2",
                env=env,
            )
            self.assertNotEqual(0, result.returncode)
            self.assertIn("rollback", (result.stderr + result.stdout).lower())
            self.assertEqual("old-a", (target / "a.lua").read_text(encoding="utf-8"))
            self.assertFalse((target / "b.lua").exists())
            self.assertEqual("old-server", server_target.read_text(encoding="utf-8"))
            self.assertEqual("preserve", (target / "unrelated.user").read_text(encoding="utf-8"))
            self.assertFalse(stage.exists())
            reports = list(backup.glob("*/deployment-failure.txt"))
            self.assertEqual(1, len(reports))
            self.assertIn("rollback", reports[0].read_text(encoding="utf-8").lower())

    def test_backup_names_are_unique_across_rapid_deployments(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            source = root / "source" / "SoloCollections"
            target = root / "live" / "SoloCollections"
            server_source = root / "source-server" / "solo_collections.lua"
            server_target = root / "live-server" / "solo_collections.lua"
            backup = root / "backups"
            stage = root / "staging"
            source.mkdir(parents=True)
            target.mkdir(parents=True)
            server_source.parent.mkdir(parents=True)
            server_target.parent.mkdir(parents=True)
            (source / "entry.lua").write_text("v1", encoding="utf-8")
            (target / "entry.lua").write_text("old", encoding="utf-8")
            server_source.write_text("server", encoding="utf-8")
            server_target.write_text("server", encoding="utf-8")
            args = (
                "-AddonSource", str(source), "-AddonTarget", str(target),
                "-ServerLuaSource", str(server_source), "-ServerLuaTarget", str(server_target),
                "-BackupRoot", str(backup), "-StageRoot", str(stage),
            )
            first = run_ps(self.deploy, *args)
            self.assertEqual(0, first.returncode, first.stderr + first.stdout)
            (source / "entry.lua").write_text("v2", encoding="utf-8")
            second = run_ps(self.deploy, *args)
            self.assertEqual(0, second.returncode, second.stderr + second.stdout)
            names = [path.name for path in backup.iterdir() if path.is_dir()]
            self.assertEqual(2, len(names))
            self.assertEqual(2, len(set(names)))
            self.assertTrue(all(len(name.rsplit("-", 1)[-1]) == 32 for name in names))

    def test_verifier_writes_deterministic_parity_manifest_and_fails_mismatch(self):
        self.assertTrue(self.verify.is_file(), f"missing {self.verify}")
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            source = root / "source" / "SoloCollections"
            target = root / "live" / "SoloCollections"
            server_source = root / "source-server" / "solo_collections.lua"
            server_target = root / "live-server" / "solo_collections.lua"
            manifest = root / "phase1_manifest.json"
            source.mkdir(parents=True)
            target.mkdir(parents=True)
            server_source.parent.mkdir(parents=True)
            server_target.parent.mkdir(parents=True)
            (source / "b.lua").write_text("b", encoding="utf-8")
            (source / "a.lua").write_text("a", encoding="utf-8")
            (target / "b.lua").write_text("b", encoding="utf-8")
            (target / "a.lua").write_text("a", encoding="utf-8")
            server_source.write_text("server", encoding="utf-8")
            server_target.write_text("server", encoding="utf-8")

            args = (
                "-AddonSource", str(source), "-AddonTarget", str(target),
                "-ServerLuaSource", str(server_source), "-ServerLuaTarget", str(server_target),
                "-ManifestPath", str(manifest),
            )
            first = run_ps(self.verify, *args)
            self.assertEqual(0, first.returncode, first.stderr + first.stdout)
            first_bytes = manifest.read_bytes()
            payload = json.loads(first_bytes.decode("utf-8"))
            self.assertEqual(2, payload["schema_version"])
            self.assertEqual(["a.lua", "b.lua"], [entry["relative_path"] for entry in payload["addon_files"]])
            self.assertTrue(all(entry["source_sha256"] == entry["live_sha256"] for entry in payload["addon_files"]))
            self.assertEqual([], payload["addon_target_only_files"])
            self.assertEqual(
                {
                    "addon_source_file_count": 2,
                    "addon_target_file_count": 2,
                    "matched": 3,
                    "missing": 0,
                    "mismatched": 0,
                    "target_only": 0,
                },
                payload["summary"],
            )
            second = run_ps(self.verify, *args)
            self.assertEqual(0, second.returncode, second.stderr + second.stdout)
            self.assertEqual(first_bytes, manifest.read_bytes())

            (target / "a.lua").write_text("mismatch", encoding="utf-8")
            mismatch = run_ps(self.verify, *args)
            self.assertNotEqual(0, mismatch.returncode)
            self.assertIn("mismatch", (mismatch.stderr + mismatch.stdout).lower())

    def test_verifier_fails_and_records_target_only_addon_files(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            source = root / "source" / "SoloCollections"
            target = root / "live" / "SoloCollections"
            server_source = root / "source-server" / "solo_collections.lua"
            server_target = root / "live-server" / "solo_collections.lua"
            manifest = root / "phase1_manifest.json"
            source.mkdir(parents=True)
            (target / "Legacy").mkdir(parents=True)
            server_source.parent.mkdir(parents=True)
            server_target.parent.mkdir(parents=True)
            (source / "entry.lua").write_text("same", encoding="utf-8")
            (target / "entry.lua").write_text("same", encoding="utf-8")
            (target / "z-extra.lua").write_text("extra-z", encoding="utf-8")
            (target / "Legacy" / "a-extra.lua").write_text("extra-a", encoding="utf-8")
            server_source.write_text("same", encoding="utf-8")
            server_target.write_text("same", encoding="utf-8")

            result = run_ps(
                self.verify,
                "-AddonSource", str(source), "-AddonTarget", str(target),
                "-ServerLuaSource", str(server_source), "-ServerLuaTarget", str(server_target),
                "-ManifestPath", str(manifest),
            )

            self.assertNotEqual(0, result.returncode)
            output = (result.stderr + result.stdout).lower()
            # Windows PowerShell 5.1 can hard-wrap native error records in the
            # middle of a word according to the host buffer width.
            self.assertIn("target-onlyaddonfile", "".join(output.split()))
            payload = json.loads(manifest.read_text(encoding="utf-8"))
            self.assertEqual(2, payload["schema_version"])
            self.assertEqual(
                ["Legacy/a-extra.lua", "z-extra.lua"],
                [entry["relative_path"] for entry in payload["addon_target_only_files"]],
            )
            self.assertTrue(all(entry["status"] == "target_only" for entry in payload["addon_target_only_files"]))
            self.assertTrue(all(entry["live_size"] is not None for entry in payload["addon_target_only_files"]))
            self.assertTrue(all(entry["live_sha256"] for entry in payload["addon_target_only_files"]))
            self.assertEqual(
                {
                    "addon_source_file_count": 1,
                    "addon_target_file_count": 3,
                    "matched": 2,
                    "missing": 0,
                    "mismatched": 0,
                    "target_only": 2,
                },
                payload["summary"],
            )

    def test_verifier_rejects_relative_and_overlapping_manifest_paths(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            source = root / "source" / "SoloCollections"
            target = root / "live" / "SoloCollections"
            server_source = root / "source-server" / "solo_collections.lua"
            server_target = root / "live-server" / "solo_collections.lua"
            source.mkdir(parents=True)
            target.mkdir(parents=True)
            server_source.parent.mkdir(parents=True)
            server_target.parent.mkdir(parents=True)
            (source / "entry.lua").write_text("same", encoding="utf-8")
            (target / "entry.lua").write_text("same", encoding="utf-8")
            server_source.write_text("same", encoding="utf-8")
            server_target.write_text("same", encoding="utf-8")
            base = (
                "-AddonSource", str(source), "-AddonTarget", str(target),
                "-ServerLuaSource", str(server_source), "-ServerLuaTarget", str(server_target),
            )
            relative = run_ps(self.verify, *base, "-ManifestPath", r"C:phase1_manifest.json")
            self.assertNotEqual(0, relative.returncode)
            self.assertIn("fully qualified", (relative.stderr + relative.stdout).lower())
            manifest = source / "phase1_manifest.json"
            overlap = run_ps(self.verify, *base, "-ManifestPath", str(manifest))
            self.assertNotEqual(0, overlap.returncode)
            self.assertIn("overlap", (overlap.stderr + overlap.stdout).lower())
            self.assertFalse(manifest.exists())

    def test_legacy_phase_manifest_covers_only_feature_targets_when_present(self):
        manifest_path = TOOLS / "phase1_manifest.json"
        if not manifest_path.is_file():
            self.skipTest("deployment manifests are local ignored output")
        manifest = load_json(manifest_path)
        self.assertEqual(2, manifest["schema_version"])
        self.assertEqual("SoloCollections", manifest["addon_name"])
        self.assertEqual("solo_collections.lua", manifest["server_lua"])
        self.assertEqual([], manifest["addon_target_only_files"])
        self.assertEqual(len(manifest["addon_files"]), manifest["summary"]["addon_source_file_count"])
        self.assertEqual(0, manifest["summary"]["target_only"])
        self.assertEqual(
            r"D:\Games\wow335\world of warcraft 3.3.5a hd\Interface\AddOns\SoloCollections",
            manifest["addon_target"],
        )
        self.assertEqual(
            r"D:\AzerothCore_NPCBots_Clean\lua_scripts\solo_collections.lua",
            manifest["server_lua_target"],
        )


if __name__ == "__main__":
    unittest.main()
