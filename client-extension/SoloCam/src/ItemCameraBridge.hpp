#pragma once

#include "CameraProfile.hpp"

#include <cstdint>

// PlayerModel:SetCamera accepts one uint32 index.  SoloCam reserves the high
// nibble 0x5 for item-camera commands; stock M2 cameras use small indexes and
// are forwarded unchanged.  Commands are emitted only by Core/M2Camera.lua.
constexpr std::uint32_t kItemCameraRequestClassMask = 0xF0000000;
constexpr std::uint32_t kItemCameraRequestClass = 0x50000000;
constexpr std::uint32_t kItemCameraCommandMask = 0x0F000000;
constexpr std::uint32_t kItemCameraPayloadMask = 0x00FFFFFF;
constexpr std::uint32_t kItemCameraPairMask = 0x00000FFF;
constexpr std::uint32_t kItemCameraPairQuantization = 0x00000FFF;

enum class ItemCameraCommand : std::uint8_t
{
    YawPitch = 1,
    DistanceTargetZ = 2,
    TargetXY = 3,
    Activate = 4,
    Roll = 5,
};

bool IsItemCameraRequest(std::uint32_t request);
bool TryDecodeItemCameraRequest(
    std::uint32_t request,
    ItemCameraCommand& command,
    std::uint32_t& payload
);
bool ApplyItemCameraCommand(
    ItemCameraPose& pose,
    ItemCameraCommand command,
    std::uint32_t payload
);
