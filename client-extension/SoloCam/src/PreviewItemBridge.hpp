#pragma once

#include <cstdint>

constexpr std::uint32_t kPreviewTryOnBase = 0x10000000;
constexpr std::uint32_t kPreviewTryOnSlotBase = 0x18000000;
constexpr std::uint32_t kPreviewTryOnSlotStride = 0x00100000;
constexpr std::uint32_t kPreviewUndress = 0x1FFFFFFF;
constexpr std::uint32_t kPreviewMaximumItemId = 0x000FFFFF;
// These are Transmorpher's Lua equipment-slot carrier values, not the
// zero-based model slots consumed by CSimpleModelFFX::TryOn.
constexpr std::uint32_t kPreviewMinimumEquipmentSlotId = 16;
constexpr std::uint32_t kPreviewMaximumEquipmentSlotId = 18;

enum class PreviewItemCommand
{
    None,
    TryOnAuto,
    TryOnSlot,
    Undress,
    Invalid,
};

struct PreviewItemRequest
{
    PreviewItemCommand command = PreviewItemCommand::None;
    std::uint32_t itemId = 0;
    std::uint32_t equipmentSlotId = 0;
};

PreviewItemRequest DecodePreviewItemRequest(std::uint32_t request);
int ResolvePreviewModelSlotId(std::uint32_t equipmentSlotId);
