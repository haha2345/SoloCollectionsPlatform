#include "PreviewItemBridge.hpp"

namespace
{
constexpr std::uint32_t kPreviewRangeEnd = 0x1FFFFFFF;
}

PreviewItemRequest DecodePreviewItemRequest(std::uint32_t request)
{
    PreviewItemRequest decoded{};
    if (request < kPreviewTryOnBase || request > kPreviewRangeEnd)
    {
        return decoded;
    }
    if (request == kPreviewUndress)
    {
        decoded.command = PreviewItemCommand::Undress;
        return decoded;
    }

    if (request > kPreviewTryOnBase && request <= kPreviewTryOnBase + kPreviewMaximumItemId)
    {
        decoded.command = PreviewItemCommand::TryOnAuto;
        decoded.itemId = request - kPreviewTryOnBase;
        return decoded;
    }

    if (request >= kPreviewTryOnSlotBase)
    {
        const std::uint32_t packed = request - kPreviewTryOnSlotBase;
        const std::uint32_t equipmentSlotId = packed / kPreviewTryOnSlotStride;
        const std::uint32_t itemId = packed % kPreviewTryOnSlotStride;
        if (equipmentSlotId >= kPreviewMinimumEquipmentSlotId
            && equipmentSlotId <= kPreviewMaximumEquipmentSlotId
            && itemId > 0
            && itemId <= kPreviewMaximumItemId)
        {
            decoded.command = PreviewItemCommand::TryOnSlot;
            decoded.itemId = itemId;
            decoded.equipmentSlotId = equipmentSlotId;
            return decoded;
        }
    }

    decoded.command = PreviewItemCommand::Invalid;
    return decoded;
}

int ResolvePreviewModelSlotId(std::uint32_t equipmentSlotId)
{
    // Build 12340's stock DressUpModel:TryOn passes -1 into 0x00597FC0.
    // Its 0x005980D0 dispatcher resolves Main Hand to internal model slot 15
    // and shields/off-hand items to model slot 16. Transmorpher 3.0.0 packs
    // the Lua paper-doll slots 16/17/18 and passes them straight through,
    // which sends a shield to nonexistent model slot 17: geometry attaches,
    // but its replaceable texture is bound to the wrong material context.
    if (equipmentSlotId == 16)
    {
        return 15;
    }
    if (equipmentSlotId == 17)
    {
        return 16;
    }
    // Ranged inventory types split between the two model weapon slots; let
    // the stock dispatcher choose from the item's InventoryType.
    return -1;
}
