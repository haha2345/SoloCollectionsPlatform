#include "BodyCameraBridge.hpp"
#include "CameraProfile.hpp"
#include "DisplayInfoBridge.hpp"
#include "ItemCameraBridge.hpp"

#include <cmath>
#include <cstdlib>
#include <cstring>
#include <iostream>

namespace
{
bool NearlyEqual(float left, float right, float tolerance = 0.001f)
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

std::uint32_t PackPair(std::uint32_t low, std::uint32_t high)
{
    return low | (high << 12);
}

int HexValue(char value)
{
    if (value >= '0' && value <= '9') return value - '0';
    if (value >= 'a' && value <= 'f') return value - 'a' + 10;
    return value - 'A' + 10;
}

std::uint32_t MakeHashChunk(const char* hash, std::uint32_t index)
{
    const std::size_t offset = static_cast<std::size_t>(index) * 5u;
    const std::size_t remaining = 64u - offset;
    const std::size_t width = remaining < 5u ? remaining : 5u;
    std::uint32_t value = 0;
    for (std::size_t position = 0; position < width; ++position)
    {
        value = (value << 4) | static_cast<std::uint32_t>(HexValue(hash[offset + position]));
    }
    if (width < 5u) value <<= 4;
    return 0x72000000 | (index << 20) | value;
}

void Apply(PendingBodyCamera& pending, std::uint32_t request)
{
    BodyCameraCommand command{};
    std::uint32_t payload = 0;
    Require(TryDecodeBodyCameraRequest(request, command, payload), "body request must decode");
    Require(ApplyBodyCameraCommand(pending, command, payload), "body command must apply");
}
}

int main()
{
    // The allocated command family cannot overlap any generated sentinel,
    // item-camera transport command, or direct display-info request range.
    Require(!IsBodyCameraRequest(0x5341), "legacy sentinel is not a body request");
    Require(!IsBodyCameraRequest(0x51000000), "item request is not a body request");
    Require(!IsBodyCameraRequest(kDisplayInfoRequestBase + 1), "display request is not a body request");
    for (std::uint32_t sentinel = 0x5000; sentinel < 0x7000; ++sentinel)
    {
        Require(!IsBodyCameraRequest(sentinel), "sentinel range must not overlap body requests");
    }
    std::uint32_t displayId = 0;
    Require(!TryDecodeDisplayInfoRequest(0x71010000, displayId), "body begin is not a display request");
    Require(!IsItemCameraRequest(0x71010000), "body begin is not an item request");

    BodyCameraCommand command{};
    std::uint32_t payload = 0;
    Require(
        !TryDecodeBodyCameraRequest(0x71020000, command, payload),
        "unknown body protocol version must be rejected"
    );
    Require(
        !TryDecodeBodyCameraRequest(0x77000000, command, payload),
        "unknown body command must be rejected"
    );
    Require(
        !TryDecodeBodyCameraRequest(0x76000001, command, payload),
        "activate payload must remain empty"
    );

    PendingBodyCamera pending{};
    Apply(pending, 0x71010000);
    Require(!IsBodyCameraPendingComplete(pending, GetCharacterCameraProfileHash()), "incomplete transaction must not activate");
    for (std::uint32_t index = 0; index < kBodyCameraHashChunkCount; ++index)
    {
        Apply(pending, MakeHashChunk(GetCharacterCameraProfileHash(), index));
    }
    Apply(pending, 0x73000000 | PackPair(2304, 1792));
    Apply(pending, 0x74000000 | PackPair(2048, 2304));
    Apply(pending, 0x75000000 | 2048);
    Require(
        IsBodyCameraPendingComplete(pending, GetCharacterCameraProfileHash()),
        "complete matching body transaction must activate"
    );
    Require(
        !IsBodyCameraPendingComplete(pending, "0000000000000000000000000000000000000000000000000000000000000000"),
        "mismatched full profile hash must be rejected"
    );
    Require(std::fabs(pending.delta.verticalOffsetDelta) < 0.3f, "vertical delta decoded");
    Require(std::fabs(pending.delta.horizontalOffsetDelta) < 0.3f, "horizontal delta decoded");
    Require(NearlyEqual(pending.delta.distanceScaleMultiplier, 1.25f, 0.01f), "distance multiplier decoded");

    PendingBodyCamera malformed{};
    Apply(malformed, 0x71010000);
    Require(
        !TryDecodeBodyCameraRequest(0x7200000F | (12u << 20), command, payload),
        "final hash chunk must preserve its low padding nibble"
    );
    ResetBodyCameraPending(pending);
    Require(!pending.started && pending.hashChunkMask == 0, "reset clears pending body pose");

    const CameraVector nativePosition{4.0f, 0.0f, 1.0f};
    const CameraVector nativeTarget{0.0f, 0.0f, 1.0f};
    for (std::uint32_t sentinel = 0; sentinel < 0x7000; ++sentinel)
    {
        const CharacterCameraProfile* profile = FindCharacterCameraProfile(sentinel);
        if (!profile) continue;
        CameraVector baselinePosition{};
        CameraVector baselineTarget{};
        CameraVector identityPosition{};
        CameraVector identityTarget{};
        Require(
            BuildCharacterCamera(*profile, nativePosition, nativeTarget, baselinePosition, baselineTarget),
            "every generated profile must build"
        );
        Require(
            BuildBodyCharacterCamera(
                *profile,
                BodyCameraDelta{},
                nativePosition,
                nativeTarget,
                identityPosition,
                identityTarget),
            "identity body delta must build every generated profile"
        );
        Require(NearlyEqual(baselinePosition.x, identityPosition.x), "identity body x regression");
        Require(NearlyEqual(baselinePosition.y, identityPosition.y), "identity body y regression");
        Require(NearlyEqual(baselineTarget.z, identityTarget.z), "identity body target regression");
    }

    const CharacterCameraProfile* chest = FindCharacterCameraProfile(0x5343);
    Require(chest != nullptr, "human female chest profile must exist");
    BodyCameraDelta delta{};
    delta.verticalOffsetDelta = 0.20f;
    delta.horizontalOffsetDelta = -0.10f;
    delta.distanceScaleMultiplier = 1.10f;
    delta.minimumDistanceDelta = 0.10f;
    delta.yawOffsetDelta = 0.20f;
    CameraVector adjustedPosition{};
    CameraVector adjustedTarget{};
    Require(
        BuildBodyCharacterCamera(
            *chest,
            delta,
            nativePosition,
            nativeTarget,
            adjustedPosition,
            adjustedTarget),
        "valid body delta must build"
    );
    Require(!NearlyEqual(adjustedTarget.z, nativeTarget.z + chest->verticalOffset), "vertical delta must move target");
    delta.distanceScaleMultiplier = 0.0f;
    Require(
        !BuildBodyCharacterCamera(
            *chest,
            delta,
            nativePosition,
            nativeTarget,
            adjustedPosition,
            adjustedTarget),
        "non-positive distance multiplier must fail closed"
    );

    std::cout << "BodyCameraBridgeTests: all checks passed\n";
    return 0;
}
