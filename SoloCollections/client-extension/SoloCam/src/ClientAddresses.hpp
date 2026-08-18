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

constexpr std::uintptr_t LuaIsNumber = 0x0084DF20;
constexpr std::uintptr_t LuaToInteger = 0x0084E070;

// Transmorpher v3.0.0 preview route, locked to the same build-12340 code
// image as SoloCam. The Lua SetCreature binding is only a carrier for the
// reserved request range; these are the engine methods used by the native
// DressUpModel TryOn/Undress bindings.
constexpr std::uintptr_t PlayerModelTryOn = 0x00597FC0;
constexpr std::uint8_t PlayerModelTryOnBytes[] = {
    0x55, 0x8B, 0xEC, 0x83, 0xEC, 0x70, 0x53, 0x56,
    0x57, 0x33, 0xDB, 0x53, 0x53, 0x53, 0x89, 0x4D,
};
constexpr std::size_t PlayerModelTryOnLength = sizeof(PlayerModelTryOnBytes);

constexpr std::uintptr_t PlayerModelUndress = 0x00597BA0;
constexpr std::uint8_t PlayerModelUndressBytes[] = {
    0x56, 0x8B, 0xF1, 0x83, 0xBE, 0xA0, 0x02, 0x00,
    0x00, 0x00, 0x0F, 0x84, 0x9B, 0x00, 0x00, 0x00,
};
constexpr std::size_t PlayerModelUndressLength = sizeof(PlayerModelUndressBytes);

// Resolve widgetTable[0] exactly as the stock model Lua getter does. The old
// ResolveScriptObject call depended on ESI and could resolve the wrong widget.
constexpr std::uintptr_t LuaRawGetI = 0x0084E670;
constexpr std::uint8_t LuaRawGetIBytes[] = {
    0x55, 0x8B, 0xEC, 0x8B, 0x45, 0x0C, 0x56, 0x8B,
    0x75, 0x08, 0x8B, 0xCE, 0xE8, 0x3F, 0xF3, 0xFF,
};
constexpr std::size_t LuaRawGetILength = sizeof(LuaRawGetIBytes);

constexpr std::uintptr_t LuaToUserData = 0x0084E1C0;
constexpr std::uint8_t LuaToUserDataBytes[] = {
    0x55, 0x8B, 0xEC, 0x8B, 0x45, 0x0C, 0x8B, 0x4D,
    0x08, 0xE8, 0xF2, 0xF7, 0xFF, 0xFF,
};
constexpr std::size_t LuaToUserDataLength = sizeof(LuaToUserDataBytes);

constexpr std::uintptr_t LuaSetTop = 0x0084DBF0;
constexpr std::uint8_t LuaSetTopBytes[] = {
    0x55, 0x8B, 0xEC, 0x8B, 0x4D, 0x0C, 0x85, 0xC9,
    0x8B, 0x45, 0x08, 0x7C, 0x41, 0xC1, 0xE1, 0x04,
};
constexpr std::size_t LuaSetTopLength = sizeof(LuaSetTopBytes);

// Transmorpher uses this function from a window timer on WoW's UI thread.
// SoloCam uses the same path to re-advertise capability after every /reload.
constexpr std::uintptr_t FrameScriptExecute = 0x00819210;
constexpr std::uint8_t FrameScriptExecuteBytes[] = {
    0x55, 0x8B, 0xEC, 0x51, 0x83, 0x05, 0xA0, 0x13,
    0xD4, 0x00, 0x01, 0xA1, 0x9C, 0x13, 0xD4, 0x00,
};
constexpr std::size_t FrameScriptExecuteLength = sizeof(FrameScriptExecuteBytes);

constexpr std::uint32_t NativeDressingRoomCamera = 1;
}
