from __future__ import annotations

import re
import unittest

from common import ADDON, ROOT, read_text


M2_CAMERA = ADDON / "Core" / "M2Camera.lua"
BOOTSTRAP = ADDON / "Core" / "Bootstrap.lua"
WARDROBE = ADDON / "UI" / "Wardrobe.lua"
PROFILES = ADDON / "Data" / "Generated" / "CameraProfiles.lua"
BODY_BRIDGE = ROOT / "client-extension" / "SoloCam" / "src" / "BodyCameraBridge.cpp"
BODY_BRIDGE_HEADER = ROOT / "client-extension" / "SoloCam" / "src" / "BodyCameraBridge.hpp"
SOLOCAM = ROOT / "client-extension" / "SoloCam" / "src" / "SoloCam.cpp"


class BodyCameraWorkbenchContractTests(unittest.TestCase):
    def test_protocol_is_versioned_transactional_and_disjoint(self):
        source = read_text(M2_CAMERA)
        bridge = read_text(BODY_BRIDGE)
        bridge_header = read_text(BODY_BRIDGE_HEADER)
        for token in (
            "REQUEST_BODY_BEGIN = 0x71000000",
            "REQUEST_BODY_HASH_CHUNK = 0x72000000",
            "REQUEST_BODY_VERTICAL_HORIZONTAL = 0x73000000",
            "REQUEST_BODY_DISTANCE_MINIMUM = 0x74000000",
            "REQUEST_BODY_YAW = 0x75000000",
            "REQUEST_BODY_ACTIVATE = 0x76000000",
            "BODY_PROTOCOL_VERSION = 1",
            "BODY_HASH_CHUNK_COUNT = 13",
            "M2Camera.ApplyBodyProfile",
        ):
            self.assertIn(token, source)
        for token in (
            "kBodyCameraRequestClass = 0x70000000",
            "kBodyCameraHashChunkCount = 13",
        ):
            self.assertIn(token, bridge_header)
        for token in (
            "pending.hashChunkMask != kAllHashChunkBits",
            "pending.valueCommandMask != kAllValueCommandBits",
            "ExpectedHashChunk(expectedProfileHash",
        ):
            self.assertIn(token, bridge)

    def test_body_capability_is_runtime_only_and_stock_client_fails_closed(self):
        source = read_text(M2_CAMERA)
        bootstrap = read_text(BOOTSTRAP)
        self.assertIn("M2Camera._bodyCameraRuntimeCapability = nil", source)
        self.assertIn("local runtime = M2Camera._bodyCameraRuntimeCapability", source)
        self.assertNotIn("SC.db.bodyCameraRuntimeCapability", source)
        self.assertIn("db.bodyCameraRuntimeCapability = nil", bootstrap)
        self.assertIn("local capability, capabilityReason = M2Camera.GetBodyProfileCapability(profile)", source)
        self.assertLess(
            source.index("local capability, capabilityReason = M2Camera.GetBodyProfileCapability(profile)"),
            source.index("local chunks = profileHashChunks(profile.profileHash)"),
        )

    def test_generated_profile_metadata_has_one_stable_body_scope_for_each_profile(self):
        source = read_text(PROFILES)
        profile_keys = re.findall(r'profileKey = "([a-z_]+:[a-z]+:[A-Z_]+)"', source)
        self.assertEqual(180, len(profile_keys))
        self.assertEqual(180, len(set(profile_keys)))
        self.assertIn("CameraProfiles.profileMetadata", source)
        self.assertIn("function CameraProfiles.GetProfile", source)
        self.assertIn("profileHash = CameraProfiles.profileHash", source)

    def test_body_workbench_is_stripped_but_profile_validation_remains(self):
        # The body-camera workbench sliders were development tooling and are
        # stripped from the release addon; the runtime profile hash validation
        # in M2Camera must stay.
        source = read_text(WARDROBE)
        self.assertNotIn("createBodyCameraTuningSlider", source)
        self.assertNotIn("cameraTuningPanel", source)
        self.assertIn("PROFILE_HASH_MISMATCH", read_text(M2_CAMERA))

    def test_visible_same_profile_reapplies_by_generation_and_resets_on_pool_reuse(self):
        wardrobe = read_text(WARDROBE)
        native = read_text(SOLOCAM)
        self.assertIn("visibleProfile.profileKey == profile.profileKey", wardrobe)
        self.assertIn("queueItemModelView(itemModel, true)", wardrobe)
        self.assertGreaterEqual(wardrobe.count("SC.M2Camera.Reset(model)"), 3)
        for token in (
            "PendingBodyCamera pendingBodyCamera",
            "BodyCameraDelta activeBodyDelta",
            "bool bodyCameraActive = false",
            "tracked->bodyCameraActive = false",
            "BuildBodyCharacterCamera(",
            "DeactivateCustomCamera(simpleModel)",
        ):
            self.assertIn(token, native)


if __name__ == "__main__":
    unittest.main()
