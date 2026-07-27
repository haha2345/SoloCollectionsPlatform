from __future__ import annotations

import hashlib
import json
import os
import shutil
import struct
import subprocess
import sys
import unittest
import uuid
from pathlib import Path

from common import ROOT


SCRIPT = ROOT / "tools" / "catalog" / "creature_presentations.py"


def write_dbc(path: Path, fields: int, rows: list[list[int]], strings: bytes = b"\0") -> None:
    payload = b"".join(struct.pack(f"<{fields}I", *row) for row in rows)
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(b"WDBC" + struct.pack("<4I", len(rows), fields, fields * 4, len(strings)) + payload + strings)


class CreaturePresentationTests(unittest.TestCase):
    def setUp(self):
        self.root = ROOT / "_work" / "test-temp" / f"presentations-{uuid.uuid4().hex}"
        self.evidence = self.root / "evidence"
        self.output = self.root / "creature_presentations.json"
        self.evidence.mkdir(parents=True)
        strings = b"\0Interface\\Icons\\Mount_Test\0Interface\\Icons\\Pet_Test\0"
        mount_offset = 1
        pet_offset = strings.index(b"Interface\\Icons\\Pet_Test")
        write_dbc(self.evidence / "dbc" / "SpellIcon.dbc", 2, [[10, mount_offset], [11, pet_offset]], strings)
        mount_spell = [0] * 234
        mount_spell[0], mount_spell[133] = 1000, 10
        pet_spell = [0] * 234
        pet_spell[0], pet_spell[133] = 2000, 11
        write_dbc(self.evidence / "dbc" / "Spell.dbc", 234, [mount_spell, pet_spell])
        write_dbc(self.evidence / "dbc" / "CreatureDisplayInfo.dbc", 16, [[3000] + [0] * 15, [4000] + [0] * 15])
        self.write_json(
            "repository/catalog/generated/catalog-manifest.json",
            {
                "collections": [
                    {"typeKey": "mount", "collectionId": 1, "collectionKey": "mount.test", "lifecycle": "active"},
                    {"typeKey": "companion", "collectionId": 2, "collectionKey": "companion.test", "lifecycle": "active", "actionId": 2000},
                ]
            },
        )
        self.write_json(
            "repository/catalog/source/mount_actions.json",
            {"collections": [{"collectionId": 1, "canonicalSpellId": 1000, "creatureIds": [300]}]},
        )
        self.write_json(
            "repository/catalog/source/companion_actions.json",
            {"entries": [{"collectionId": 2, "creatureId": 400}]},
        )
        self.write_json(
            "repository/catalog/review/mounts/evidence.json",
            {
                "candidateHash": "mount-review-hash",
                "candidates": [
                    {"spellId": 1000, "creatures": [{"entry": 300, "displayResourcesPresent": True}]}
                ],
            },
        )
        self.write_json(
            "repository/catalog/review/mounts/review-policy.json",
            {"candidateHash": "mount-review-hash"},
        )
        self.write_json(
            "repository/catalog/review/companions/evidence.json",
            {
                "reviewMethod": "EXACT_CREATURE_ENTRY_ONLY",
                "entries": [
                    {
                        "collectionId": 2,
                        "iconSpellId": 2000,
                        "previewCreatureEntry": 400,
                        "status": "READY",
                        "reasonCode": "",
                    }
                ],
            },
        )
        self.seal_manifest()

    def tearDown(self):
        safe = (ROOT / "_work" / "test-temp").resolve()
        resolved = self.root.resolve()
        self.assertTrue(str(resolved).startswith(str(safe) + os.sep))
        if self.root.exists():
            shutil.rmtree(self.root)

    def write_json(self, relative: str, value: object) -> None:
        path = self.evidence / relative
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(json.dumps(value, sort_keys=True) + "\n", encoding="utf-8")

    def seal_manifest(self) -> None:
        files = []
        for path in sorted(self.evidence.rglob("*")):
            if not path.is_file() or path.name == "evidence-manifest.json":
                continue
            relative = path.relative_to(self.evidence).as_posix()
            payload = path.read_bytes()
            files.append({
                "relativePath": relative,
                "size": len(payload),
                "sha256": hashlib.sha256(payload).hexdigest(),
            })
        canonical = "".join(
            f'{entry["relativePath"]}\0{entry["size"]}\0{entry["sha256"]}\n' for entry in files
        ).encode()
        manifest = {
            "schemaVersion": 1,
            "evidenceId": "fixture-presentations",
            "clientBuild": "3, 3, 5, 12340",
            "packHash": hashlib.sha256(canonical).hexdigest(),
            "files": files,
        }
        self.write_json("evidence-manifest.json", manifest)

    def run_generate(self, *extra: str) -> subprocess.CompletedProcess[str]:
        return subprocess.run(
            [
                sys.executable,
                str(SCRIPT),
                "generate",
                "--evidence-root",
                str(self.evidence),
                "--output",
                str(self.output),
                *extra,
            ],
            cwd=ROOT,
            capture_output=True,
            text=True,
            encoding="utf-8",
            errors="replace",
            check=False,
        )

    def test_generate_emits_typed_native_presentations_without_actions(self):
        first = self.run_generate()
        self.assertEqual(0, first.returncode, first.stdout + first.stderr)
        value = json.loads(self.output.read_text(encoding="utf-8"))
        self.assertEqual("fixture-presentations", value["evidenceId"])
        self.assertEqual(2, len(value["entries"]))
        by_type = {entry["typeKey"]: entry for entry in value["entries"]}
        self.assertEqual("Interface\\Icons\\Mount_Test", by_type["mount"]["iconTexture"])
        self.assertEqual(300, by_type["mount"]["previewCreatureEntry"])
        self.assertEqual("Interface\\Icons\\Pet_Test", by_type["companion"]["iconTexture"])
        self.assertEqual(400, by_type["companion"]["previewCreatureEntry"])
        rendered = self.output.read_text(encoding="utf-8")
        self.assertNotIn("canonicalSpellId", rendered)
        self.assertNotIn("actionId", rendered)
        before = self.output.read_bytes()
        second = self.run_generate()
        self.assertEqual(0, second.returncode, second.stdout + second.stderr)
        self.assertEqual(before, self.output.read_bytes())
        checked = self.run_generate("--check")
        self.assertEqual(0, checked.returncode, checked.stdout + checked.stderr)

    def test_missing_or_hash_drifted_evidence_fails_closed(self):
        drifted = self.evidence / "dbc" / "SpellIcon.dbc"
        drifted.write_bytes(drifted.read_bytes() + b"drift")
        result = self.run_generate()
        self.assertEqual(2, result.returncode)
        self.assertIn("evidence size drift", result.stderr)

    def test_changed_review_policy_hash_fails_closed(self):
        policy = self.evidence / "repository" / "catalog" / "review" / "mounts" / "review-policy.json"
        policy.write_text('{"candidateHash":"changed"}\n', encoding="utf-8")
        self.seal_manifest()
        result = self.run_generate()
        self.assertEqual(2, result.returncode)
        self.assertIn("mount review policy hash changed", result.stderr)


if __name__ == "__main__":
    unittest.main()
