from __future__ import annotations

import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
SRC = ROOT / "src"


class SetCatalogContractTests(unittest.TestCase):
    def test_set_provider_depends_on_appearance_and_projects_owned_state(self):
        core = (SRC / "SoloCollectionsCore.cpp").read_text(encoding="utf-8")
        provider = (SRC / "SoloCollectionsProvider.h").read_text(encoding="utf-8")
        account = (SRC / "SoloCollectionsAccountService.cpp").read_text(encoding="utf-8")
        self.assertIn("SetCollectionProvider", core)
        self.assertIn("SetAppearanceDependencyTypeId", core)
        self.assertIn("GetSetCatalog().CompletedByAccount", core)
        self.assertIn("OwnedByAccount", provider)
        self.assertIn("provider->OwnedByAccount", account)

    def test_set_completion_is_derived_from_required_canonical_appearance_members(self):
        header = (SRC / "SoloCollectionsSetCatalog.h").read_text(encoding="utf-8")
        implementation = (SRC / "SoloCollectionsSetCatalog.cpp").read_text(encoding="utf-8")
        generated = (SRC / "generated/SoloCollectionsSetCatalog.inc").read_text(encoding="utf-8")
        self.assertIn("AppearanceAlternatives", header)
        self.assertIn("member.Enabled && member.Required", implementation)
        self.assertIn("SetAppearanceDependencyTypeId", implementation)
        self.assertIn("if (owned)", implementation)
        self.assertEqual(8, generated.count("{ CollectionId{ 3000"))

    def test_no_parallel_set_collected_writer_exists(self):
        production = "\n".join(
            path.read_text(encoding="utf-8", errors="replace")
            for path in SRC.rglob("*") if path.suffix in {".cpp", ".h"}
        )
        self.assertNotIn("set_collected", production.lower())
        self.assertNotIn("TryUnlock(accountId, { SetCollectionTypeId", production)


if __name__ == "__main__":
    unittest.main()
