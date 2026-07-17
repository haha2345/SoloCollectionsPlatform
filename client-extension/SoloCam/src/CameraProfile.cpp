#include "CameraProfile.hpp"

#include <cmath>

namespace
{
constexpr float kMinimumNativeDistanceSquared = 0.0001f;
constexpr float kMinimumHorizontalDistanceSquared = 0.0001f;
constexpr float kMaximumItemCameraPitch = 1.45f;
constexpr float kPi = 3.14159265f;

constexpr HumanFemaleCameraProfile kProfiles[] = {
    // Retail reference order: HEAD, SHOULDER, BACK, CHEST, WRIST, HANDS,
    // WAIST, LEGS and FEET. Each target follows the visible crop in the
    // supplied Retail wardrobe cards; values remain relative to the native
    // human-female dressing-room camera and never use screen coordinates.
    {0x5341, 0.55f, 0.32f, 0.55f, 0.00f, 0.00f}, // face and neck
    {0x5342, 0.40f, 0.16f, 0.52f, 0.10f, 0.00f}, // front-facing single shoulder crop
    {0x5349, 0.25f, 0.27f, 0.65f, 0.00f, 3.14159265f}, // rear torso and cloak
    {0x5343, 0.25f, 0.27f, 0.58f, 0.00f, 0.00f}, // neck to waist, slightly farther than the first crop
    {0x5344, 0.12f, 0.20f, 0.48f, 0.10f, 0.00f}, // centered right wrist, shifted upward in the card
    {0x5345, 0.08f, 0.24f, 0.48f, 0.10f, 0.00f}, // right hand plus wrist in one crop
    {0x5346, 0.10f, 0.27f, 0.58f, 0.00f, 0.00f}, // belt and hips
    {0x5347, -0.02f, 0.27f, 0.58f, 0.00f, 0.00f}, // hips to knees
    {0x5348, -0.38f, 0.30f, 0.68f, 0.00f, 0.00f}, // both boots and lower legs, retail-style centered crop
};
}

const HumanFemaleCameraProfile* FindHumanFemaleCameraProfile(std::uint32_t sentinel)
{
    for (const auto& profile : kProfiles)
    {
        if (profile.sentinel == sentinel)
        {
            return &profile;
        }
    }
    return nullptr;
}

bool BuildHumanFemaleCamera(
    const HumanFemaleCameraProfile& profile,
    const CameraVector& nativePosition,
    const CameraVector& nativeTarget,
    CameraVector& position,
    CameraVector& target
)
{
    const float viewX = nativePosition.x - nativeTarget.x;
    const float viewY = nativePosition.y - nativeTarget.y;
    const float viewZ = nativePosition.z - nativeTarget.z;
    const float distanceSquared = viewX * viewX + viewY * viewY + viewZ * viewZ;
    if (distanceSquared < kMinimumNativeDistanceSquared)
    {
        return false;
    }

    const float nativeDistance = std::sqrt(distanceSquared);
    const float inverseDistance = 1.0f / nativeDistance;
    const float cosYaw = std::cos(profile.yawOffset);
    const float sinYaw = std::sin(profile.yawOffset);
    const float rotatedViewX = viewX * cosYaw - viewY * sinYaw;
    const float rotatedViewY = viewX * sinYaw + viewY * cosYaw;
    float distance = nativeDistance * profile.distanceScale;
    if (distance < profile.minimumDistance)
    {
        distance = profile.minimumDistance;
    }

    target = nativeTarget;
    target.z += profile.verticalOffset;

    if (profile.horizontalOffset != 0.0f)
    {
        const float horizontalDistanceSquared = viewX * viewX + viewY * viewY;
        if (horizontalDistanceSquared < kMinimumHorizontalDistanceSquared)
        {
            return false;
        }
        const float inverseHorizontalDistance = 1.0f / std::sqrt(horizontalDistanceSquared);
        target.x += -viewY * inverseHorizontalDistance * profile.horizontalOffset;
        target.y += viewX * inverseHorizontalDistance * profile.horizontalOffset;
    }

    position.x = target.x + rotatedViewX * inverseDistance * distance;
    position.y = target.y + rotatedViewY * inverseDistance * distance;
    position.z = target.z + viewZ * inverseDistance * distance;
    return true;
}

bool BuildItemM2Camera(
    const ItemCameraPose& pose,
    const CameraVector& nativePosition,
    const CameraVector& nativeTarget,
    CameraVector& position,
    CameraVector& target
)
{
    if (!std::isfinite(pose.yawOffset)
        || !std::isfinite(pose.pitchOffset)
        || !std::isfinite(pose.rollOffset)
        || !std::isfinite(pose.distanceScale)
        || !std::isfinite(pose.targetOffset.x)
        || !std::isfinite(pose.targetOffset.y)
        || !std::isfinite(pose.targetOffset.z)
        || pose.distanceScale <= 0.0f)
    {
        return false;
    }

    const float viewX = nativePosition.x - nativeTarget.x;
    const float viewY = nativePosition.y - nativeTarget.y;
    const float viewZ = nativePosition.z - nativeTarget.z;
    const float distanceSquared = viewX * viewX + viewY * viewY + viewZ * viewZ;
    const float horizontalDistanceSquared = viewX * viewX + viewY * viewY;
    if (distanceSquared < kMinimumNativeDistanceSquared
        || horizontalDistanceSquared < kMinimumHorizontalDistanceSquared)
    {
        return false;
    }

    const float nativeDistance = std::sqrt(distanceSquared);
    const float horizontalDistance = std::sqrt(horizontalDistanceSquared);
    const float yaw = std::atan2(viewY, viewX) + pose.yawOffset;
    float pitch = std::atan2(viewZ, horizontalDistance) + pose.pitchOffset;
    if (pitch > kMaximumItemCameraPitch)
    {
        pitch = kMaximumItemCameraPitch;
    }
    else if (pitch < -kMaximumItemCameraPitch)
    {
        pitch = -kMaximumItemCameraPitch;
    }

    const float distance = nativeDistance * pose.distanceScale;
    const float horizontalProjection = distance * std::cos(pitch);
    target.x = nativeTarget.x + pose.targetOffset.x;
    target.y = nativeTarget.y + pose.targetOffset.y;
    target.z = nativeTarget.z + pose.targetOffset.z;
    position.x = target.x + horizontalProjection * std::cos(yaw);
    position.y = target.y + horizontalProjection * std::sin(yaw);
    position.z = target.z + distance * std::sin(pitch);
    return true;
}

bool BuildItemM2CameraRoll(
    const ItemCameraPose& pose,
    float nativeRoll,
    float& roll
)
{
    if (!std::isfinite(pose.rollOffset) || !std::isfinite(nativeRoll))
    {
        return false;
    }

    // Keep the scalar in the same canonical interval as the Lua protocol.
    // Normalization avoids steadily growing values when a pooled PlayerModel
    // is redrawn many times while preserving the authored M2 baseline roll.
    roll = std::fmod(nativeRoll + pose.rollOffset + kPi, 2.0f * kPi);
    if (roll < 0.0f)
    {
        roll += 2.0f * kPi;
    }
    roll -= kPi;
    return true;
}
