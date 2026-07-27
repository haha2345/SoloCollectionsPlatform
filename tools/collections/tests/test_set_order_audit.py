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

TOOL = CATALOG_TOOLS / "check_set_order_audit.py"


def load_tool(name: str, path: Path):
    spec = importlib.util.spec_from_file_location(name, path)
    assert spec and spec.loader
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


set_order_audit = load_tool("set_order_audit_for_test", TOOL)


def run_text(class_token: str, run_key: str, signature: str) -> str:
    return f'''["{run_key}"] = {{
  ["playerClass"] = "{class_token}", ["runKey"] = "{run_key}",
  ["completed"] = true, ["ready"] = true, ["allCount"] = 465,
  ["allSignature"] = "{signature}", ["allOrderSorted"] = true,
  ["t10PrefixPass"] = true, ["higherCohortPass"] = true,
  ["searchPass"] = true, ["searchCount"] = 1,
  ["classFilterPass"] = true, ["classFilterCount"] = 20,
  ["pageStartPass"] = true, ["pageEndPass"] = true, ["errorCount"] = 0,
}},'''


def audit_text(*, cross_class: bool = True) -> str:
    signature = ",".join(str(value) for value in range(1, 466))
    return f'''SoloCollectionsSetOrderAuditDB = {{
 ["completed"] = true, ["ready"] = true, ["reloadPass"] = true,
 ["relogPass"] = true, ["differentClassPass"] = {str(cross_class).lower()},
 ["runs"] = {{
   {run_text("PALADIN", "paladin@realm:PALADIN", signature)}
   {run_text("MAGE", "mage@realm:MAGE", signature)}
 }},
}}'''


class SetOrderAuditTests(unittest.TestCase):
    def test_accepts_completed_two_class_runtime_matrix(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            saved = root / "SoloCollectionsSetOrderAudit.lua"
            shots = root / "screens"
            shots.mkdir()
            saved.write_text(audit_text(), encoding="utf-8")
            for name in set_order_audit.REQUIRED_SCREENSHOTS:
                (shots / name).write_bytes(b"evidence")
            result = set_order_audit.check_set_order_audit(saved, shots)
        self.assertEqual(465, result["sets"])
        self.assertEqual(["MAGE", "PALADIN"], result["classes"])
        self.assertTrue(result["crossClass"])

    def test_rejects_missing_cross_class_confirmation(self):
        with tempfile.TemporaryDirectory() as temporary:
            saved = Path(temporary) / "SoloCollectionsSetOrderAudit.lua"
            saved.write_text(audit_text(cross_class=False), encoding="utf-8")
            with self.assertRaisesRegex(set_order_audit.CameraRuntimeMatrixError, "second character class"):
                set_order_audit.check_set_order_audit(saved)


if __name__ == "__main__":
    unittest.main()
