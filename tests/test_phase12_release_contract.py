from __future__ import annotations

import subprocess
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]


class Phase12ReleaseContractTests(unittest.TestCase):
    def test_module_release_keeps_sql_license_notice_and_boundaries(self):
        for relative in (
            "LICENSE",
            "THIRD_PARTY_NOTICES.md",
            "data/sql/db-characters/solo_collections_schema_v1.sql",
            "data/sql/updates/char/2026_07_20_00_solo_collections_schema_v1.sql",
        ):
            self.assertTrue((ROOT / relative).is_file(), relative)
        readme = (ROOT / "README.md").read_text(encoding="utf-8")
        for token in ("AddOn", "Client resources", "SQL schema", "AzerothCore commits"):
            self.assertIn(token, readme)
        self.assertIn("AGPL", readme)

    def test_clean_checkout_ci_runs_contracts_and_core_build(self):
        workflow = (ROOT / ".github" / "workflows" / "core_build.yml").read_text(encoding="utf-8")
        self.assertIn("actions/checkout@v4", workflow)
        self.assertIn("python -m unittest discover -s tests", workflow)
        self.assertIn("core_build_modules.yml@main", workflow)

    def test_tracked_module_has_no_client_binary_or_runtime_credential_file(self):
        output = subprocess.run(
            ["git", "-C", str(ROOT), "ls-files"],
            check=True,
            capture_output=True,
            text=True,
        ).stdout.splitlines()
        forbidden_suffixes = (".exe", ".dll", ".mpq", ".pdb", ".db", ".sqlite")
        forbidden_names = {".env", "authserver.conf", "worldserver.conf", "realmlist.wtf"}
        for relative in output:
            path = Path(relative)
            self.assertFalse(path.suffix.lower() in forbidden_suffixes, relative)
            self.assertNotIn(path.name.lower(), forbidden_names, relative)


if __name__ == "__main__":
    unittest.main()
