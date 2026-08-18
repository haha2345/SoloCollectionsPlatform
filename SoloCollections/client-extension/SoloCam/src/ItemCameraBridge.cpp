#include "ItemCameraBridge.hpp"

namespace
{
constexpr float kPi = 3.14159265f;
constexpr float kPitchLimit = 1.20f;
constexpr float kMinimumDistanceScale = 0.25f;
constexpr float kMaximumDistanceScale = 4.00f;
constexpr float kMaximumTargetOffset = 4.00f;

float DecodeQuantized(std::uint32_t value, float minimum, float maximum)
{
    const float normalized = static_cast<float>(value) /
        static_cast<float>(kItemCameraPairQuantization);
    return minimum + (maximum - minimum) * normalized;
}

float DecodeLow(std::uint32_t payload, float minimum, float maximum)
{
    return DecodeQuantized(payload & kItemCameraPairMask, minimum, maximum);
}

float DecodeHigh(std::uint32_t payload, float minimum, float maximum)
{
    return DecodeQuantized(
        (payload >> 12) & kItemCameraPairMask,
        minimum,
        maximum
    );
}
}

bool IsItemCameraRequest(std::uint32_t request)
{
    return (request & kItemCameraRequestClassMask) == kItemCameraRequestClass;
}

bool TryDecodeItemCameraRequest(
    std::uint32_t request,
    ItemCameraCommand& command,
    std::uint32_t& payload
)
{
    if (!IsItemCameraRequest(request))
    {
        return false;
    }

    const std::uint32_t rawCommand =
        (request & kItemCameraCommandMask) >> 24;
    if (rawCommand < static_cast<std::uint32_t>(ItemCameraCommand::YawPitch)
        || rawCommand > static_cast<std::uint32_t>(ItemCameraCommand::Roll))
    {
        return false;
    }

    command = static_cast<ItemCameraCommand>(rawCommand);
    payload = request & kItemCameraPayloadMask;
    if (command == ItemCameraCommand::Activate)
    {
        return payload == 0;
    }

    // Roll is one scalar, encoded in the low 12-bit quantization field. The
    // unused high bits must stay empty so malformed requests cannot silently
    // become a different pose when the protocol grows again.
    return command != ItemCameraCommand::Roll
        || (payload & ~kItemCameraPairMask) == 0;
}

bool ApplyItemCameraCommand(
    ItemCameraPose& pose,
    ItemCameraCommand command,
    std::uint32_t payload
)
{
    switch (command)
    {
    case ItemCameraCommand::YawPitch:
        pose.yawOffset = DecodeLow(payload, -kPi, kPi);
        pose.pitchOffset = DecodeHigh(payload, -kPitchLimit, kPitchLimit);
        return true;
    case ItemCameraCommand::DistanceTargetZ:
        pose.distanceScale = DecodeLow(
            payload,
            kMinimumDistanceScale,
            kMaximumDistanceScale
        );
        pose.targetOffset.z = DecodeHigh(
            payload,
            -kMaximumTargetOffset,
            kMaximumTargetOffset
        );
        return true;
    case ItemCameraCommand::TargetXY:
        pose.targetOffset.x = DecodeLow(
            payload,
            -kMaximumTargetOffset,
            kMaximumTargetOffset
        );
        pose.targetOffset.y = DecodeHigh(
            payload,
            -kMaximumTargetOffset,
            kMaximumTargetOffset
        );
        return true;
    case ItemCameraCommand::Activate:
        return payload == 0;
    case ItemCameraCommand::Roll:
        pose.rollOffset = DecodeLow(payload, -kPi, kPi);
        return true;
    }
    return false;
}
