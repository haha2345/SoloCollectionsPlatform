#pragma once

#include "CameraProfile.hpp"

#include <cstdint>

// Body-profile requests occupy the 0x7 high-nibble command family.  This is
// deliberately disjoint from generated character sentinels (< 0x7000), item
// camera requests (0x5...), and direct-display requests (0x6F...).
constexpr std::uint32_t kBodyCameraRequestClassMask = 0xF0000000;
constexpr std::uint32_t kBodyCameraRequestClass = 0x70000000;
constexpr std::uint32_t kBodyCameraCommandMask = 0x0F000000;
constexpr std::uint32_t kBodyCameraPayloadMask = 0x00FFFFFF;
constexpr std::uint32_t kBodyCameraPairMask = 0x00000FFF;
constexpr std::uint32_t kBodyCameraPairQuantization = 0x00000FFF;
constexpr std::uint32_t kBodyCameraHashChunkMask = 0x000FFFFF;
constexpr std::uint32_t kBodyCameraHashChunkCount = 13;
constexpr std::uint8_t kBodyCameraProtocolVersion = 1;

enum class BodyCameraCommand : std::uint8_t
{
    Begin = 1,
    ProfileHashChunk = 2,
    VerticalHorizontal = 3,
    DistanceMinimum = 4,
    Yaw = 5,
    Activate = 6,
};

// The protocol is transactional.  A Begin replaces any pending delta; all 13
// 20-bit SHA-256 chunks and all three value commands must arrive before
// Activate may make a body delta visible on a model.
struct PendingBodyCamera
{
    BodyCameraDelta delta{};
    std::uint32_t hashChunks[kBodyCameraHashChunkCount]{};
    std::uint16_t hashChunkMask = 0;
    std::uint8_t valueCommandMask = 0;
    std::uint8_t protocolVersion = 0;
    bool started = false;
};

bool IsBodyCameraRequest(std::uint32_t request);
bool TryDecodeBodyCameraRequest(
    std::uint32_t request,
    BodyCameraCommand& command,
    std::uint32_t& payload
);
bool ApplyBodyCameraCommand(
    PendingBodyCamera& pending,
    BodyCameraCommand command,
    std::uint32_t payload
);
bool IsBodyCameraPendingComplete(
    const PendingBodyCamera& pending,
    const char* expectedProfileHash
);
void ResetBodyCameraPending(PendingBodyCamera& pending);
