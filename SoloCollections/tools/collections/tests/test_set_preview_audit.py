from __future__ import annotations

import importlib.util
import sys
import tempfile
import unittest
from pathlib import Path

from common import ROOT


CATALOG_TOOLS = ROOT / "tools" / "catalog"
if str(CATALOG_TOOLS) not in sys.path:
    sys.path.insert(0, str(CATALOG_TOOLS))

TOOL = CATALOG_TOOLS / "check_set_preview_audit.py"


def load_tool(name: str, path: Path):
    spec = importlib.util.spec_from_file_location(name, path)
    assert spec and spec.loader
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


set_preview_audit = load_tool("set_preview_audit_for_test", TOOL)


def audit_text(*, ready: bool = True) -> str:
    scan_rows = "\n".join(
        "{ [\"setId\"] = %d, [\"pass\"] = true, [\"undressCount\"] = 1, "
        "[\"expectedCount\"] = 5, [\"actualCount\"] = 5 }," % index
        for index in range(1, 466)
    )
    sample_rows = "\n".join(
        "{ [\"label\"] = \"%s\", [\"pass\"] = true, [\"undressCount\"] = 1, "
        "[\"expectedCount\"] = %d, [\"actualCount\"] = %d }," % (label, count, count)
        for label, count in (
            ("synthetic selected variant 2/9", 9),
            ("sample 2 pieces", 2),
            ("sample 3 pieces", 3),
            ("sample 5 pieces", 5),
            ("sample 8 pieces", 8),
            ("pregear-clear two-piece", 2),
            ("rapid final of 20", 5),
        )
    )
    pagination_rows = "\n".join(
        "{ [\"label\"] = \"%s\", [\"pass\"] = true, [\"recordCount\"] = %d, [\"offset\"] = %d, "
        "[\"page\"] = %d, [\"totalPages\"] = %d, [\"visible\"] = %d, [\"maximum\"] = %d },"
        % (label, values["recordCount"], values["offset"], values["page"], values["totalPages"],
           values["visible"], values["maximum"])
        for label, values in set_preview_audit.EXPECTED_PAGINATION.items()
    )
    return f'''SoloCollectionsSetAuditDB = {{
 ["ready"] = {str(ready).lower()}, ["completed"] = true, ["reloadObserved"] = true,
 ["rowCount"] = 465, ["uniqueSetCount"] = 465, ["sampleCount"] = 7,
 ["paginationPassed"] = true, ["syntheticFixturePassed"] = true, ["rapidPassed"] = true,
 ["errors"] = {{}},
 ["scroll"] = {{ ["pass"] = true, ["middle"] = 228, ["afterWheel"] = 229, ["scrollbarValue"] = 229 }},
 ["scanRows"] = {{ {scan_rows} }},
 ["samples"] = {{ {sample_rows} }},
 ["pagination"] = {{ {pagination_rows} }},
}}'''


class SetPreviewAuditTests(unittest.TestCase):
    def test_accepts_a_complete_ready_runtime_matrix(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            saved = root / "SoloCollectionsSetAudit.lua"
            shots = root / "screens"
            shots.mkdir()
            saved.write_text(audit_text(), encoding="utf-8")
            for name in set_preview_audit.REQUIRED_SCREENSHOTS:
                (shots / name).write_bytes(b"evidence")
            result = set_preview_audit.check_set_preview_audit(saved, shots)
        self.assertEqual(465, result["sets"])
        self.assertEqual(7, result["samples"])
        self.assertTrue(result["syntheticNinePiece"])

    def test_rejects_non_ready_audit(self):
        with tempfile.TemporaryDirectory() as temporary:
            saved = Path(temporary) / "SoloCollectionsSetAudit.lua"
            saved.write_text(audit_text(ready=False), encoding="utf-8")
            with self.assertRaisesRegex(set_preview_audit.CameraRuntimeMatrixError, "ready"):
                set_preview_audit.check_set_preview_audit(saved)


if __name__ == "__main__":
    unittest.main()
