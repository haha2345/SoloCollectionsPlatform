from __future__ import annotations

import importlib.util
import json
import tempfile
import unittest
from pathlib import Path

from common import ROOT


TOOL = ROOT / "tools/catalog/appearance_presentations.py"
SPEC = importlib.util.spec_from_file_location("appearance_presentations", TOOL)
assert SPEC and SPEC.loader
generator = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(generator)


class AppearancePresentationTests(unittest.TestCase):
    def test_checked_in_report_matches_named_evidence_pack(self):
        evidence = ROOT / "_work/evidence/round2-20260722-stage1-presentations"
        if not evidence.exists():
            self.skipTest("named external evidence pack is not installed")
        expected = generator.build_report(
            ROOT / "catalog/source/appearance_presentations.json",
            ROOT / "catalog/generated/appearance-sources.json",
            evidence,
        )
        actual = json.loads(
            (ROOT / "catalog/generated/appearance-presentation-report.json").read_text(encoding="utf-8")
        )
        self.assertEqual(expected, actual)

    def test_source_uses_canonical_identity_not_legacy_demo_ids(self):
        source = json.loads(
            (ROOT / "catalog/source/appearance_presentations.json").read_text(encoding="utf-8")
        )
        self.assertEqual(21, len(source["entries"]))
        self.assertTrue(all(row["appearanceId"] >= 200000 for row in source["entries"]))
        self.assertTrue(all("legacyDemoId" not in row for row in source["entries"]))
        self.assertEqual(set(range(40000, 40021)), {
            row["syntheticDisplayId"] for row in source["entries"]
        })

    def test_hash_or_canonical_drift_fails_closed(self):
        evidence = ROOT / "_work/evidence/round2-20260722-stage1-presentations"
        if not evidence.exists():
            self.skipTest("named external evidence pack is not installed")
        source = json.loads(
            (ROOT / "catalog/source/appearance_presentations.json").read_text(encoding="utf-8")
        )
        with tempfile.TemporaryDirectory(dir=ROOT / "_work") as temporary:
            temp = Path(temporary) / "source.json"
            source["entries"][0]["appearanceId"] += 1
            temp.write_text(json.dumps(source), encoding="utf-8")
            with self.assertRaises(generator.PresentationError):
                generator.build_report(
                    temp,
                    ROOT / "catalog/generated/appearance-sources.json",
                    evidence,
                )


if __name__ == "__main__":
    unittest.main()
