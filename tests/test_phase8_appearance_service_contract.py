from __future__ import annotations

import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
SRC = ROOT / "src"
APPEARANCE = SRC / "Categories" / "Appearance"


class AppearanceServiceContractTests(unittest.TestCase):
    def test_account_service_is_the_unified_state_and_mutation_boundary(self):
        header = (SRC / "SoloCollectionsAccountService.h").read_text(encoding="utf-8")
        implementation = (SRC / "SoloCollectionsAccountService.cpp").read_text(encoding="utf-8")
        self.assertIn("CollectionResult Evaluate", header)
        self.assertIn("MutationStartResult TryUnlock", header)
        self.assertIn("GetAccountCollectionCache().IsOwned", implementation)
        self.assertIn("GetAccountCollectionStore().BeginMutation", implementation)

    def test_transmog_consumers_use_appearance_facade(self):
        scripts = (SRC / "transmog_scripts.cpp").read_text(encoding="utf-8")
        commands = (SRC / "cs_transmog.cpp").read_text(encoding="utf-8")
        transmog = (SRC / "Transmogrification.cpp").read_text(encoding="utf-8")
        for consumer in (scripts, commands):
            self.assertIn("GetAppearanceService()", consumer)
            self.assertNotIn("AddCollectedAppearance", consumer)
            self.assertNotIn("GetCollectedAppearances", consumer)
            self.assertNotIn("HasCollectedAppearance", consumer)
            self.assertNotIn("INSERT INTO custom_unlocked_appearances", consumer)
        self.assertIn("GetAppearanceService().HasCollectedSource", transmog)

    def test_legacy_repository_is_private_atomic_and_transitional(self):
        header = (APPEARANCE / "SoloCollectionsAppearanceService.h").read_text(encoding="utf-8")
        implementation = (APPEARANCE / "SoloCollectionsAppearanceService.cpp").read_text(encoding="utf-8")
        self.assertIn("LegacyCollectionCache _legacyCollections", header.split("private:", 1)[1])
        self.assertIn("std::scoped_lock", implementation)
        self.assertIn("_legacyCollections.swap(refreshed)", implementation)
        self.assertEqual(2, implementation.count("custom_unlocked_appearances"))

    def test_appearance_provider_is_independently_registered(self):
        core = (SRC / "SoloCollectionsCore.cpp").read_text(encoding="utf-8")
        self.assertIn("AppearanceCollectionProvider", core)
        self.assertIn("AppearanceCollectionTypeId", core)
        self.assertIn('TypeKey = "appearance"', core)


if __name__ == "__main__":
    unittest.main()
