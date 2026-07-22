from __future__ import annotations

import hashlib
import json
import os
import shutil
import subprocess
import unittest
import uuid
from pathlib import Path

from common import ROOT


POWERSHELL = "powershell.exe"
SCRIPT = ROOT / "tools" / "evidence" / "New-RoundTwoEvidencePack.ps1"
DBC_NAMES = (
    "ChrRaces.dbc",
    "CreatureDisplayInfo.dbc",
    "CreatureModelData.dbc",
    "Item.dbc",
    "ItemDisplayInfo.dbc",
    "ItemSet.dbc",
    "SkillLineAbility.dbc",
    "Spell.dbc",
    "SpellIcon.dbc",
)


class RoundTwoEvidencePackTests(unittest.TestCase):
    def setUp(self):
        self.root = ROOT / "_work" / "test-temp" / f"evidence-{uuid.uuid4().hex}"
        self.client = self.root / "client"
        self.weapon = self.root / "weapon"
        self.output = self.root / "output"
        (self.client / "dbc").mkdir(parents=True)
        (self.client / "WTF").mkdir()
        (self.client / "WTF" / "Config.wtf").write_text('SET locale "enUS"\n', encoding="utf-8")
        for index, name in enumerate(DBC_NAMES):
            (self.client / "dbc" / name).write_bytes(f"dbc-{index}".encode())
        (self.weapon / "stage" / "Item").mkdir(parents=True)
        (self.weapon / "stage" / "Item" / "sample.m2").write_bytes(b"m2")
        (self.weapon / "weapon-creature-build.json").write_text(
            json.dumps(
                [
                    {
                        "source_m2": "F:/private/build/extract/Item/Weapon/sample.m2",
                        "source_skin": "F:/private/build/extract/Item/Weapon/sample00.skin",
                        "source_texture": "F:/private/build/extract/Item/Weapon/sample.blp",
                        "target": "Item\\ObjectComponents\\SoloCollections\\SC_sample_19364",
                        "texture_name": "SC_sample_19364",
                        "model_id": 4000,
                        "display_id": 40000,
                    }
                ]
            ),
            encoding="utf-8",
        )
        (self.weapon / "weapon-model-verification.csv").write_text(
            'Archive,Path,StageLength,VerifyLength,StageSHA256,VerifySHA256,Match\n'
            '"F:\\private\\build\\Patch-W.MPQ","Item\\sample.m2",3,3,abc,abc,True\n',
            encoding="utf-8",
        )

    def tearDown(self):
        safe_root = (ROOT / "_work" / "test-temp").resolve()
        resolved = self.root.resolve()
        self.assertTrue(str(resolved).startswith(str(safe_root) + os.sep))
        if self.root.exists():
            shutil.rmtree(self.root)

    def run_pack(self, output: Path | None = None) -> subprocess.CompletedProcess[str]:
        output = output or self.output
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
                str(SCRIPT),
                "-EvidenceRoot",
                str(output),
                "-ClientRoot",
                str(self.client),
                "-WeaponBuildRoot",
                str(self.weapon),
                "-AddonRoot",
                str(ROOT),
                "-EvidenceId",
                "fixture-evidence",
            ],
            capture_output=True,
            text=True,
            encoding="utf-8",
            errors="replace",
            env=env,
            check=False,
        )

    def test_pack_contains_explicit_inputs_and_recomputable_hash(self):
        result = self.run_pack()
        self.assertEqual(0, result.returncode, result.stderr + result.stdout)
        manifest = json.loads((self.output / "evidence-manifest.json").read_text(encoding="utf-8"))
        self.assertEqual("fixture-evidence", manifest["evidenceId"])
        self.assertEqual("enUS", manifest["clientLocale"])
        self.assertFalse(manifest["sourceSanitization"]["credentialsIncluded"])
        self.assertFalse(manifest["sourceSanitization"]["absoluteSourcePathsIncluded"])
        self.assertEqual("mount-catalog-exact-entry-v1", manifest["worldSnapshot"]["queryVersion"])
        self.assertFalse(manifest["worldSnapshot"]["credentialsIncluded"])
        self.assertFalse(manifest["worldSnapshot"]["databaseDumpIncluded"])
        paths = [entry["relativePath"] for entry in manifest["files"]]
        for name in DBC_NAMES:
            self.assertIn(f"dbc/{name}", paths)
        self.assertIn("weapon-resources/stage/Item/sample.m2", paths)
        self.assertIn("repository/catalog/generated/catalog-manifest.json", paths)
        self.assertIn("repository/catalog/review/toys/evidence.json", paths)
        self.assertIn("repository/catalog/review/toys/review-policy.json", paths)
        self.assertIn("repository/catalog/generated/toy-candidates.csv", paths)
        self.assertIn("repository/catalog/generated/toy-exclusions.csv", paths)
        self.assertTrue(all(not Path(path).is_absolute() and ".." not in Path(path).parts for path in paths))
        weapon_manifest_text = (self.output / "weapon-resources" / "weapon-creature-build.json").read_text(
            encoding="utf-8-sig"
        )
        verification_text = (self.output / "weapon-resources" / "weapon-model-verification.csv").read_text(
            encoding="utf-8-sig"
        )
        self.assertNotIn("F:/private", weapon_manifest_text)
        self.assertNotIn("F:\\private", verification_text)
        weapon_entries = json.loads(weapon_manifest_text)
        self.assertEqual(19364, weapon_entries[0]["item_id"])
        self.assertEqual("extract/Item/Weapon/sample.m2", weapon_entries[0]["source_m2"])
        self.assertIn("Patch-W.MPQ", verification_text)
        for entry in manifest["files"]:
            payload = (self.output / entry["relativePath"]).read_bytes()
            self.assertEqual(entry["size"], len(payload))
            self.assertEqual(entry["sha256"], hashlib.sha256(payload).hexdigest())
        canonical = "".join(
            f'{entry["relativePath"]}\0{entry["size"]}\0{entry["sha256"]}\n'
            for entry in sorted(manifest["files"], key=lambda item: item["relativePath"])
        ).encode()
        self.assertEqual(manifest["packHash"], hashlib.sha256(canonical).hexdigest())

    def test_nonempty_output_and_c_drive_output_fail_closed(self):
        self.output.mkdir(parents=True)
        (self.output / "keep.txt").write_text("keep", encoding="utf-8")
        nonempty = self.run_pack()
        self.assertNotEqual(0, nonempty.returncode)
        self.assertEqual("keep", (self.output / "keep.txt").read_text(encoding="utf-8"))

        invalid = Path("C:/round-two-evidence-test-must-not-exist")
        c_drive = self.run_pack(invalid)
        self.assertNotEqual(0, c_drive.returncode)
        self.assertIn("must stay on f:", (c_drive.stderr + c_drive.stdout).lower())
        self.assertFalse(invalid.exists())

    def test_script_never_copies_client_executables_or_archives(self):
        text = SCRIPT.read_text(encoding="utf-8-sig")
        self.assertNotIn("Remove-Item", text)
        self.assertNotIn("*.MPQ", text)
        self.assertNotIn("Wow.exe' -RelativePath", text)
        self.assertIn("weaponResourceManifest", text)


if __name__ == "__main__":
    unittest.main()
