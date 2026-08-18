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
    def test_checked_in_report_matches_production_projection(self):
        expected = generator.build_report(
            ROOT / "catalog/source/appearance_presentations.json",
            ROOT / "catalog/generated/appearance-sources.json",
            None,
        )
        actual = json.loads(
            (ROOT / "catalog/generated/appearance-presentation-report.json").read_text(encoding="utf-8")
        )
        self.assertEqual(expected, actual)

    def test_source_uses_canonical_identity_not_legacy_demo_ids(self):
        source = json.loads(
            (ROOT / "catalog/source/appearance_presentations.json").read_text(encoding="utf-8")
        )
        self.assertEqual(2, source["schemaVersion"])
        self.assertEqual(3690, source["publicAppearanceCount"])
        self.assertEqual({"READY": 3541, "UNAVAILABLE": 149}, source["terminalCounts"])
        self.assertEqual(3691, len(source["entries"]))
        self.assertTrue(all(row["appearanceId"] >= 200000 for row in source["entries"]))
        self.assertTrue(all("legacyDemoId" not in row for row in source["entries"]))
        standalone = [row for row in source["entries"] if row["renderMode"] == "STANDALONE"]
        self.assertEqual(3542, len(standalone))
        self.assertTrue(all(int(row["syntheticDisplayId"]) > 0 for row in standalone))
        self.assertTrue(all(row["presentationCapability"] == "DIRECT_DISPLAY_V1" for row in standalone))
        unavailable = [row for row in source["entries"] if row["presentationStatus"] == "UNAVAILABLE"]
        self.assertTrue(all(row["presentationReasonCode"] for row in unavailable))

    def test_hash_or_canonical_drift_fails_closed(self):
        source = json.loads(
            (ROOT / "catalog/source/appearance_presentations.json").read_text(encoding="utf-8")
        )
        work_root = ROOT / "_work"
        work_root.mkdir(parents=True, exist_ok=True)
        with tempfile.TemporaryDirectory(dir=work_root) as temporary:
            temp = Path(temporary) / "source.json"
            source["entries"][0]["appearanceId"] += 1
            temp.write_text(json.dumps(source), encoding="utf-8")
            with self.assertRaises(generator.PresentationError):
                generator.build_report(
                    temp,
                    ROOT / "catalog/generated/appearance-sources.json",
                    None,
                )


if __name__ == "__main__":
    unittest.main()
