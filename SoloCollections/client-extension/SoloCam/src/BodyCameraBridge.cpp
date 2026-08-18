#include "BodyCameraBridge.hpp"

#include <cmath>
#include <cstddef>
#include <cstring>

namespace
{
constexpr float kPi = 3.14159265f;
constexpr std::uint8_t kVerticalHorizontalBit = 0x01;
constexpr std::uint8_t kDistanceMinimumBit = 0x02;
constexpr std::uint8_t kYawBit = 0x04;
constexpr std::uint8_t kAllValueCommandBits =
    kVerticalHorizontalBit | kDistanceMinimumBit | kYawBit;
constexpr std::uint16_t kAllHashChunkBits =
    static_cast<std::uint16_t>((1u << kBodyCameraHashChunkCount) - 1u);

float DecodeQuantized(std::uint32_t value, float minimum, float maximum)
{
    const float normalized = static_cast<float>(value) /
        static_cast<float>(kBodyCameraPairQuantization);
    return minimum + (maximum - minimum) * normalized;
}

float DecodeLow(std::uint32_t payload, float minimum, float maximum)
{
    return DecodeQuantized(payload & kBodyCameraPairMask, minimum, maximum);
}

float DecodeHigh(std::uint32_t payload, float minimum, float maximum)
{
    return DecodeQuantized(
        (payload >> 12) & kBodyCameraPairMask,
        minimum,
        maximum
    );
}

int HexValue(char value)
{
    if (value >= '0' && value <= '9')
    {
        return value - '0';
    }
    if (value >= 'a' && value <= 'f')
    {
        return value - 'a' + 10;
    }
    if (value >= 'A' && value <= 'F')
    {
        return value - 'A' + 10;
    }
    return -1;
}

bool ExpectedHashChunk(
    const char* hash,
    std::uint32_t index,
    std::uint32_t& chunk
)
{
    if (!hash || std::strlen(hash) != 64 || index >= kBodyCameraHashChunkCount)
    {
        return false;
    }

    const std::size_t offset = static_cast<std::size_t>(index) * 5u;
    const std::size_t remaining = 64u - offset;
    const std::size_t width = remaining < 5u ? remaining : 5u;
    std::uint32_t value = 0;
    for (std::size_t position = 0; position < width; ++position)
    {
        const int hex = HexValue(hash[offset + position]);
        if (hex < 0)
        {
            return false;
        }
        value = (value << 4) | static_cast<std::uint32_t>(hex);
    }

    // The final chunk contains four hex digits.  Pad it on the low side so
    // every chunk retains a fixed 20-bit request representation.
    if (width < 5u)
    {
        value <<= 4;
    }
    chunk = value;
    return true;
}
}

bool IsBodyCameraRequest(std::uint32_t request)
{
    return (request & kBodyCameraRequestClassMask) == kBodyCameraRequestClass;
}

bool TryDecodeBodyCameraRequest(
    std::uint32_t request,
    BodyCameraCommand& command,
    std::uint32_t& payload
)
{
    if (!IsBodyCameraRequest(request))
    {
        return false;
    }

    const std::uint32_t rawCommand =
        (request & kBodyCameraCommandMask) >> 24;
    if (rawCommand < static_cast<std::uint32_t>(BodyCameraCommand::Begin)
        || rawCommand > static_cast<std::uint32_t>(BodyCameraCommand::Activate))
    {
        return false;
    }

    command = static_cast<BodyCameraCommand>(rawCommand);
    payload = request & kBodyCameraPayloadMask;
    switch (command)
    {
    case BodyCameraCommand::Begin:
        return payload == (static_cast<std::uint32_t>(kBodyCameraProtocolVersion) << 16);
    case BodyCameraCommand::ProfileHashChunk:
    {
        const std::uint32_t index = (payload >> 20) & 0x0Fu;
        const std::uint32_t chunk = payload & kBodyCameraHashChunkMask;
        return index < kBodyCameraHashChunkCount
            && (index + 1u != kBodyCameraHashChunkCount || (chunk & 0x0Fu) == 0);
    }
    case BodyCameraCommand::VerticalHorizontal:
    case BodyCameraCommand::DistanceMinimum:
        return true;
    case BodyCameraCommand::Yaw:
        return (payload & ~kBodyCameraPairMask) == 0;
    case BodyCameraCommand::Activate:
        return payload == 0;
    }
    return false;
}

void ResetBodyCameraPending(PendingBodyCamera& pending)
{
    pending = PendingBodyCamera{};
}

bool ApplyBodyCameraCommand(
    PendingBodyCamera& pending,
    BodyCameraCommand command,
    std::uint32_t payload
)
{
    switch (command)
    {
    case BodyCameraCommand::Begin:
        if (payload != (static_cast<std::uint32_t>(kBodyCameraProtocolVersion) << 16))
        {
            return false;
        }
        ResetBodyCameraPending(pending);
        pending.started = true;
        pending.protocolVersion = kBodyCameraProtocolVersion;
        return true;
    case BodyCameraCommand::ProfileHashChunk:
    {
        if (!pending.started)
        {
            return false;
        }
        const std::uint32_t index = (payload >> 20) & 0x0Fu;
        const std::uint32_t chunk = payload & kBodyCameraHashChunkMask;
        if (index >= kBodyCameraHashChunkCount
            || (index + 1u == kBodyCameraHashChunkCount && (chunk & 0x0Fu) != 0))
        {
            return false;
        }
        pending.hashChunks[index] = chunk;
        pending.hashChunkMask |= static_cast<std::uint16_t>(1u << index);
        return true;
    }
    case BodyCameraCommand::VerticalHorizontal:
        if (!pending.started)
        {
            return false;
        }
        pending.delta.verticalOffsetDelta = DecodeLow(
            payload,
            -kBodyCameraOffsetDeltaLimit,
            kBodyCameraOffsetDeltaLimit
        );
        pending.delta.horizontalOffsetDelta = DecodeHigh(
            payload,
            -kBodyCameraOffsetDeltaLimit,
            kBodyCameraOffsetDeltaLimit
        );
        pending.valueCommandMask |= kVerticalHorizontalBit;
        return true;
    case BodyCameraCommand::DistanceMinimum:
        if (!pending.started)
        {
            return false;
        }
        pending.delta.distanceScaleMultiplier = DecodeLow(
            payload,
            kBodyCameraMinimumDistanceScaleMultiplier,
            kBodyCameraMaximumDistanceScaleMultiplier
        );
        pending.delta.minimumDistanceDelta = DecodeHigh(
            payload,
            -kBodyCameraMinimumDistanceDeltaLimit,
            kBodyCameraMinimumDistanceDeltaLimit
        );
        pending.valueCommandMask |= kDistanceMinimumBit;
        return true;
    case BodyCameraCommand::Yaw:
        if (!pending.started || (payload & ~kBodyCameraPairMask) != 0)
        {
            return false;
        }
        pending.delta.yawOffsetDelta = DecodeLow(payload, -kPi, kPi);
        pending.valueCommandMask |= kYawBit;
        return true;
    case BodyCameraCommand::Activate:
        return pending.started && payload == 0;
    }
    return false;
}

bool IsBodyCameraPendingComplete(
    const PendingBodyCamera& pending,
    const char* expectedProfileHash
)
{
    if (!pending.started
        || pending.protocolVersion != kBodyCameraProtocolVersion
        || pending.hashChunkMask != kAllHashChunkBits
        || pending.valueCommandMask != kAllValueCommandBits
        || !IsBodyCameraDeltaValid(pending.delta))
    {
        return false;
    }

    for (std::uint32_t index = 0; index < kBodyCameraHashChunkCount; ++index)
    {
        std::uint32_t expected = 0;
        if (!ExpectedHashChunk(expectedProfileHash, index, expected)
            || pending.hashChunks[index] != expected)
        {
            return false;
        }
    }
    return true;
}
