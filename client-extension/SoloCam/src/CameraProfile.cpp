#include "CameraProfile.hpp"

#include <cmath>

namespace
{
constexpr float kMinimumNativeDistanceSquared = 0.0001f;
constexpr float kMinimumHorizontalDistanceSquared = 0.0001f;
constexpr float kMaximumItemCameraPitch = 1.45f;
constexpr float kPi = 3.14159265f;

#include "generated/CharacterCameraProfiles.inc"
}

const CharacterCameraProfile* FindCharacterCameraProfile(std::uint32_t sentinel)
{
    for (const auto& profile : kCharacterCameraProfiles)
    {
        if (profile.sentinel == sentinel)
        {
            return &profile;
        }
    }
    return nullptr;
}

std::size_t GetCharacterCameraProfileCount()
{
    return sizeof(kCharacterCameraProfiles) / sizeof(kCharacterCameraProfiles[0]);
}

std::uint32_t GetCharacterCameraProfileVersion()
{
    return kCharacterCameraProfileVersion;
}

const char* GetCharacterCameraProfileHash()
{
    return kCharacterCameraProfileHash;
}

bool BuildCharacterCamera(
    const CharacterCameraProfile& profile,
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
