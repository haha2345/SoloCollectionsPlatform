#include "ItemCameraBridge.hpp"

#include <cmath>
#include <cstdlib>
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
}

int main()
{
    Require(!IsItemCameraRequest(0x5341), "human camera sentinels are not item commands");
    Require(IsItemCameraRequest(0x51000000), "yaw/pitch request must use item range");

    ItemCameraCommand command{};
    std::uint32_t payload = 0;
    const std::uint32_t yawPitch = 0x51000000 | PackPair(4095, 0);
    Require(
        TryDecodeItemCameraRequest(yawPitch, command, payload)
            && command == ItemCameraCommand::YawPitch,
        "yaw/pitch request must decode"
    );

    ItemCameraPose pose{};
    Require(
        ApplyItemCameraCommand(pose, command, payload),
        "yaw/pitch command must apply"
    );
    Require(NearlyEqual(pose.yawOffset, 3.14159265f), "yaw maximum must decode to pi");
    Require(NearlyEqual(pose.pitchOffset, -1.20f), "pitch minimum must decode");

    const std::uint32_t distanceTargetZ = 0x52000000 | PackPair(0, 4095);
    Require(
        TryDecodeItemCameraRequest(distanceTargetZ, command, payload)
            && command == ItemCameraCommand::DistanceTargetZ,
        "distance/target-z request must decode"
    );
    Require(
        ApplyItemCameraCommand(pose, command, payload),
        "distance/target-z command must apply"
    );
    Require(NearlyEqual(pose.distanceScale, 0.25f), "minimum distance scale must decode");
    Require(NearlyEqual(pose.targetOffset.z, 4.0f), "maximum target z must decode");

    const std::uint32_t targetXY = 0x53000000 | PackPair(2048, 2048);
    Require(
        TryDecodeItemCameraRequest(targetXY, command, payload)
            && command == ItemCameraCommand::TargetXY,
        "target-xy request must decode"
    );
    Require(ApplyItemCameraCommand(pose, command, payload), "target-xy command must apply");
    Require(std::fabs(pose.targetOffset.x) < 0.01f, "target x center must decode near zero");
    Require(std::fabs(pose.targetOffset.y) < 0.01f, "target y center must decode near zero");

    Require(
        !TryDecodeItemCameraRequest(0x56000000, command, payload),
        "unknown reserved command must be rejected"
    );
    const std::uint32_t roll = 0x55000000 | 2048;
    Require(
        TryDecodeItemCameraRequest(roll, command, payload)
            && command == ItemCameraCommand::Roll
            && ApplyItemCameraCommand(pose, command, payload),
        "roll request must decode and apply"
    );
    Require(std::fabs(pose.rollOffset) < 0.01f, "roll center must decode near zero");
    Require(
        !TryDecodeItemCameraRequest(0x55000000 | PackPair(0, 1), command, payload),
        "roll request must reject unused high payload bits"
    );
    Require(
        !TryDecodeItemCameraRequest(0x54000001, command, payload),
        "activate request must have an empty payload"
    );
    Require(
        TryDecodeItemCameraRequest(0x54000000, command, payload)
            && command == ItemCameraCommand::Activate
            && ApplyItemCameraCommand(pose, command, payload),
        "empty activate request must be accepted"
    );

    std::cout << "ItemCameraBridgeTests: all checks passed\n";
    return 0;
}
