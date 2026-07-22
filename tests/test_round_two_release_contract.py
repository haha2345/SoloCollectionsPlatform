from __future__ import annotations

import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]


class RoundTwoReleaseContractTests(unittest.TestCase):
    def test_status_exports_stable_build_key_value_lines(self):
        source = (ROOT / "src/SoloCollectionsCommands.cpp").read_text(encoding="utf-8")
        for key in (
            "build.addon_commit", "build.module_commit", "build.core_commit",
            "build.metadata_version", "build.asset_pack_version", "build.mapping_hash",
            "build.presentation_hash", "build.type.mount", "build.type.companion",
            "build.type.toy", "build.type.appearance", "build.type.set",
        ):
            self.assertIn(f'"{key}={{}}"', source)

    def test_startup_logs_the_same_generated_build_info(self):
        source = (ROOT / "src/SoloCollectionsProtocolScript.cpp").read_text(encoding="utf-8")
        self.assertIn('event=build_info addon_commit={}', source)
        self.assertIn('SoloCollectionsBuildInfo.inc', source)
        self.assertNotIn('Stop-Process', source)


if __name__ == "__main__":
    unittest.main()
