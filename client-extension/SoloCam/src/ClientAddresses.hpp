#pragma once

#include <cstddef>
#include <cstdint>

namespace Client12340
{
// Locked to Wow.exe SHA256:
// AA63A5750D60EF16746C686B3D5E26876D98953EAB08B1C026CD0FAF78E88CB8
constexpr std::uintptr_t SetCameraByIndex = 0x0095F9F0;
constexpr std::uint8_t SetCameraByIndexBytes[] = {0x55, 0x8B, 0xEC, 0x56, 0x8B, 0xF1};
constexpr std::size_t SetCameraByIndexLength = sizeof(SetCameraByIndexBytes);

constexpr std::uintptr_t RenderSimpleModel = 0x0095FC30;
constexpr std::uint8_t RenderSimpleModelBytes[] = {0x55, 0x8B, 0xEC, 0x81, 0xEC, 0xC8, 0x00, 0x00, 0x00};
constexpr std::size_t RenderSimpleModelLength = sizeof(RenderSimpleModelBytes);

constexpr std::uintptr_t DataMgrGetCoord = 0x004C1290;
constexpr std::uintptr_t DataMgrSetCoord = 0x004C12B0;
// M2 cameras store their in-plane roll as scalar property 5.  The stock
// loader writes this immediately after vector properties 7 (position) and 8
// (target); use the matching scalar accessors rather than treating it as a
// fourth vector component.
constexpr std::uintptr_t DataMgrGetScalar = 0x004C11F0;
constexpr std::uint8_t DataMgrGetScalarBytes[] = {
    0x55, 0x8B, 0xEC, 0x51, 0xD9, 0xEE, 0x8B, 0x4D,
    0x0C, 0x8B, 0x45, 0x08, 0xD9, 0x5D, 0xFC, 0x57,
};
constexpr std::size_t DataMgrGetScalarLength = sizeof(DataMgrGetScalarBytes);

constexpr std::uintptr_t DataMgrSetScalar = 0x004C1360;
constexpr std::uint8_t DataMgrSetScalarBytes[] = {
    0x55, 0x8B, 0xEC, 0x8B, 0x45, 0x08, 0x33, 0xD2,
    0x3B, 0xC2, 0x74, 0x21, 0x8B, 0x4D, 0x0C, 0x3B,
};
constexpr std::size_t DataMgrSetScalarLength = sizeof(DataMgrSetScalarBytes);

constexpr std::uint32_t CameraPositionSlot = 7;
constexpr std::uint32_t CameraTargetSlot = 8;
constexpr std::uint32_t CameraRollSlot = 5;
constexpr std::size_t SimpleModelCameraOffset = 0x2A4;

// PlayerModel:SetCreature Lua binding. The stock binding treats its numeric
// argument as a Creature entry and resolves it to a persistent creature-cache
// record. SoloCollections reserves a numeric range for direct display IDs and
// supplies a compatible persistent record without altering ordinary calls.
constexpr std::uintptr_t PlayerModelSetCreature = 0x00597960;
constexpr std::uint8_t PlayerModelSetCreatureBytes[] = {
    0x55, 0x8B, 0xEC, 0xA1, 0xD4, 0xE4, 0xC0, 0x00,
};
constexpr std::size_t PlayerModelSetCreatureLength = sizeof(PlayerModelSetCreatureBytes);

// Internal PlayerModel method that stores a creature-cache record pointer. The
// renderer reads the display ID from record + 0x24; this is not a uint32 API.
constexpr std::uintptr_t PlayerModelSetCreatureRecord = 0x00597840;
constexpr std::uint8_t PlayerModelSetCreatureRecordBytes[] = {
    0x55, 0x8B, 0xEC, 0x8B, 0x45, 0x08, 0x33, 0xD2,
    0x39, 0x91, 0xE0, 0x00, 0x00, 0x00,
};
constexpr std::size_t PlayerModelSetCreatureRecordLength =
    sizeof(PlayerModelSetCreatureRecordBytes);

constexpr std::uintptr_t PlayerModelTypeToken = 0x00C0E4D4;
constexpr std::uintptr_t NextScriptObjectTypeToken = 0x00D3F778;
constexpr std::uintptr_t ResolveScriptObject = 0x004A81B0;
constexpr std::uintptr_t LuaIsNumber = 0x0084DF20;
constexpr std::uintptr_t LuaToInteger = 0x0084E070;

constexpr std::uint32_t NativeDressingRoomCamera = 1;
}
