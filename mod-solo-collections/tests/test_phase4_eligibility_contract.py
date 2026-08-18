from __future__ import annotations

import pathlib
import unittest


ROOT = pathlib.Path(__file__).resolve().parents[1]
HEADER = (ROOT / "src/SoloCollectionsEligibility.h").read_text(encoding="utf-8")
SOURCE = (ROOT / "src/SoloCollectionsEligibility.cpp").read_text(encoding="utf-8")
NATIVE = (ROOT / "tests/native/SoloCollectionsDomainTests.cpp").read_text(encoding="utf-8")


class Phase4EligibilityContractTests(unittest.TestCase):
    def test_policy_supports_every_declarative_axis(self):
        for token in (
            "RequiredCapabilities", "AnyCapabilities", "ForbiddenCapabilities",
            "AllowedRaceKeys", "DeniedRaceKeys", "AllowedClassKeys", "DeniedClassKeys",
            "FactionPolicy", "MinimumLevel", "RequiredSkills", "CustomPolicyKey", "LegacyFallback",
        ):
            self.assertIn(token, HEADER)

    def test_evaluation_order_is_hard_resource_override_policy_legacy_runtime(self):
        ordered = [
            "!request.Resources.CatalogKnown",
            "!request.Resources.TemplateValid",
            "!request.Resources.AssetReady",
            "!request.Resources.Enabled",
            "ExactEligibilityOverride::Deny",
            "EvaluateDeclarativePolicy",
            "policy.LegacyFallback",
            "request.RuntimeCondition",
        ]
        positions = [SOURCE.index(token, SOURCE.index("EligibilityResult EvaluateEligibility")) for token in ordered]
        self.assertEqual(sorted(positions), positions)

    def test_exact_allow_and_unknown_identity_are_fail_closed(self):
        self.assertIn("exact allow bypassed missing assets", NATIVE)
        self.assertIn("unknown identity could use a collection", NATIVE)
        self.assertIn('policy.PolicyKey != "unrestricted"', SOURCE)
        self.assertIn("request.Mode != EligibilityMode::View", SOURCE)

    def test_generated_policies_feed_registry(self):
        self.assertIn('#include "generated/SoloCollectionsPolicyData.inc"', SOURCE)
        generated = (ROOT / "src/generated/SoloCollectionsPolicyData.inc").read_text(encoding="utf-8")
        self.assertIn("LoadGeneratedEligibilityPolicies", generated)
        self.assertIn('"appearance.plate"', generated)


if __name__ == "__main__":
    unittest.main()
