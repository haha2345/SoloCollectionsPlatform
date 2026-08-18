#include "CameraProfile.hpp"

#include <cmath>
#include <cstdlib>
#include <iostream>

namespace
{
bool NearlyEqual(float left, float right, float tolerance = 0.0001f)
{
    return std::fabs(left - right) <= tolerance;
}

void Require(bool condition, const char* message)
{
    if (!condition)
    {
        std::cerr << "FAILED: " << message << '\n';
        std::exit(1);
    }
}
}

int main()
{
    struct ExpectedProfile
    {
        std::uint32_t sentinel;
        float verticalOffset;
        float distanceScale;
        float minimumDistance;
        float horizontalOffset;
        float yawOffset;
    };

    const ExpectedProfile expectedProfiles[] = {
        // Retail-style human-female framing: head, shoulder, back, chest,
        // wrist, hands, waist, legs and feet.
        // Approved body-calibration delta for human:female:HEAD is folded
        // into the generated canonical profile; the remaining eight legacy
        // reference entries remain bit-for-bit at their baseline values.
        {0x5341, 0.60f, 0.3232f, 0.56f, 0.06f, 0.0084f},
        {0x5342, 0.40f, 0.16f, 0.52f, 0.10f, 0.00f},
        {0x5349, 0.25f, 0.27f, 0.65f, 0.00f, 3.14159265f},
        {0x5343, 0.25f, 0.27f, 0.58f, 0.00f, 0.00f},
        {0x5344, 0.12f, 0.20f, 0.48f, 0.10f, 0.00f},
        {0x5345, 0.08f, 0.24f, 0.48f, 0.10f, 0.00f},
        {0x5346, 0.10f, 0.27f, 0.58f, 0.00f, 0.00f},
        {0x5347, -0.02f, 0.27f, 0.58f, 0.00f, 0.00f},
        {0x5348, -0.38f, 0.30f, 0.68f, 0.00f, 0.00f},
    };

    const CameraVector nativePosition{4.0f, 0.0f, 1.0f};
    const CameraVector nativeTarget{0.0f, 0.0f, 1.0f};

    for (const auto& expected : expectedProfiles)
    {
        const CharacterCameraProfile* profile =
            FindCharacterCameraProfile(expected.sentinel);
        Require(profile != nullptr, "every supported sentinel must resolve");
        Require(NearlyEqual(profile->verticalOffset, expected.verticalOffset), "vertical offset");
        Require(NearlyEqual(profile->distanceScale, expected.distanceScale), "distance scale");
        Require(NearlyEqual(profile->minimumDistance, expected.minimumDistance), "minimum distance");
        Require(NearlyEqual(profile->horizontalOffset, expected.horizontalOffset), "horizontal offset");
        Require(NearlyEqual(profile->yawOffset, expected.yawOffset), "yaw offset");

        CameraVector position{};
        CameraVector target{};
        Require(
            BuildCharacterCamera(*profile, nativePosition, nativeTarget, position, target),
            "a valid native camera must produce a slot camera"
        );
        Require(NearlyEqual(target.x, 0.0f), "target x");
        Require(NearlyEqual(target.y, expected.horizontalOffset), "target horizontal offset");
        Require(NearlyEqual(target.z, 1.0f + expected.verticalOffset), "target vertical offset");
        const float expectedDistance = std::fmax(4.0f * expected.distanceScale, expected.minimumDistance);
        Require(
            NearlyEqual(position.x, std::cos(expected.yawOffset) * expectedDistance),
            "scaled and rotated camera x"
        );
        Require(
            NearlyEqual(position.y, expected.horizontalOffset + std::sin(expected.yawOffset) * expectedDistance),
            "scaled and rotated camera y"
        );
        Require(NearlyEqual(position.z, 1.0f + expected.verticalOffset), "position follows vertical target");
    }

    CameraVector shoulderPosition{};
    CameraVector shoulderTarget{};
    Require(
        BuildCharacterCamera(
            *FindCharacterCameraProfile(0x5342),
            nativePosition,
            nativeTarget,
            shoulderPosition,
            shoulderTarget),
        "shoulder camera must build"
    );
    Require(shoulderPosition.x > shoulderTarget.x, "shoulder camera must face the model from the front");
    Require(
        NearlyEqual(shoulderPosition.y, shoulderTarget.y),
        "shoulder camera must not orbit around the model"
    );
    Require(shoulderTarget.y > 0.0f, "shoulder camera must target the visible single shoulder");

    CameraVector backPosition{};
    CameraVector backTarget{};
    Require(
        BuildCharacterCamera(
            *FindCharacterCameraProfile(0x5349),
            nativePosition,
            nativeTarget,
            backPosition,
            backTarget),
        "back camera must build"
    );
    Require(backPosition.x < backTarget.x, "back camera must view the cloak from behind the model");

    Require(
        FindCharacterCameraProfile(0x5340) == nullptr,
        "unknown sentinels must not opt into a custom camera"
    );

    const CameraVector degenerate{1.0f, 1.0f, 1.0f};
    CameraVector position{};
    CameraVector target{};
    Require(
        !BuildCharacterCamera(
            *FindCharacterCameraProfile(0x5343),
            degenerate,
            degenerate,
            position,
            target),
        "a zero-length view vector must be rejected"
    );

    ItemCameraPose itemPose{};
    itemPose.yawOffset = 1.57079633f;
    itemPose.pitchOffset = 0.0f;
    itemPose.rollOffset = 0.50f;
    itemPose.distanceScale = 0.5f;
    itemPose.targetOffset = {1.0f, 2.0f, 3.0f};
    CameraVector itemPosition{};
    CameraVector itemTarget{};
    Require(
        BuildItemM2Camera(itemPose, nativePosition, nativeTarget, itemPosition, itemTarget),
        "a valid M2 camera must produce an item-camera pose"
    );
    Require(NearlyEqual(itemTarget.x, 1.0f), "item target x offset");
    Require(NearlyEqual(itemTarget.y, 2.0f), "item target y offset");
    Require(NearlyEqual(itemTarget.z, 4.0f), "item target z offset");
    Require(NearlyEqual(itemPosition.x, 1.0f), "item yaw must orbit around target");
    Require(NearlyEqual(itemPosition.y, 4.0f), "item distance scale must apply");
    Require(NearlyEqual(itemPosition.z, 4.0f), "item position follows target height");

    float itemRoll = 0.0f;
    Require(
        BuildItemM2CameraRoll(itemPose, 0.25f, itemRoll),
        "a valid M2 roll must be produced"
    );
    Require(NearlyEqual(itemRoll, 0.75f), "item roll must add to native M2 roll");

    ItemCameraPose invalidItemPose{};
    invalidItemPose.distanceScale = 0.0f;
    Require(
        !BuildItemM2Camera(
            invalidItemPose,
            nativePosition,
            nativeTarget,
            itemPosition,
            itemTarget),
        "an invalid item distance scale must be rejected"
    );

    Require(GetCharacterCameraProfileCount() == 180, "generated matrix must contain 180 profiles");
    Require(GetCharacterCameraProfileVersion() == 1, "generated profile version");
    Require(GetCharacterCameraProfileHash() != nullptr, "generated profile hash");
    Require(FindCharacterCameraProfile(0x6000) != nullptr, "human male profile must resolve");
    Require(FindCharacterCameraProfile(0x60AA) != nullptr, "draenei female profile must resolve");

    std::cout << "Generated character camera profile tests passed.\n";
    return 0;
}
