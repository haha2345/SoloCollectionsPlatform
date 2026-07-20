from __future__ import annotations

import pathlib
import unittest


ROOT = pathlib.Path(__file__).resolve().parents[1]
IDENTITY_HEADER = (ROOT / "src/SoloCollectionsIdentity.h").read_text(encoding="utf-8")
IDENTITY_SOURCE = (ROOT / "src/SoloCollectionsIdentity.cpp").read_text(encoding="utf-8")
ELIGIBILITY = (ROOT / "src/SoloCollectionsEligibility.cpp").read_text(encoding="utf-8")
NATIVE = (ROOT / "tests/native/SoloCollectionsDomainTests.cpp").read_text(encoding="utf-8")


class SyntheticRaceContractTests(unittest.TestCase):
    def test_race_identity_has_versioned_presentation_profiles(self):
        for token in (
            "AppearanceOverrideProfile",
            "ClientAssetVersion",
            "ModelProfile",
            "RacePresentationResources",
            "ResolveRacePresentation",
        ):
            self.assertIn(token, IDENTITY_HEADER)
        self.assertIn("AssetVersionMismatch", IDENTITY_SOURCE)
        self.assertIn("ModelMissing", IDENTITY_SOURCE)
        self.assertIn("TextureMissing", IDENTITY_SOURCE)

    def test_combined_context_carries_stable_race_and_faction(self):
        self.assertIn("raceIdentity.Identity->LogicalId", ELIGIBILITY)
        self.assertIn("raceIdentity.Identity->FactionKey", ELIGIBILITY)
        self.assertIn("raceIdentity.Identity->Capabilities", ELIGIBILITY)
        self.assertIn("LogicalRaceId(std::uint16_t { 601 })", NATIVE)
        self.assertIn('"ALLIANCE", "race.medium", "race.earthen"', NATIVE)

    def test_missing_camera_model_and_texture_are_safe(self):
        self.assertIn('ready.CameraProfile == "global"', NATIVE)
        self.assertIn("missing race model did not fail closed", NATIVE)
        self.assertIn("missing race texture did not disable preview and actions", NATIVE)
        self.assertIn("unknown race presentation did not use a safe disabled fallback", NATIVE)
        self.assertIn("RemappedRuntimeRaceId = 302", NATIVE)


if __name__ == "__main__":
    unittest.main()
