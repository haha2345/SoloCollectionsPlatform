#ifndef SOLO_COLLECTIONS_TRANSMOG_PROJECTION_H
#define SOLO_COLLECTIONS_TRANSMOG_PROJECTION_H

#include "SoloCollectionsTypes.h"

#include <algorithm>
#include <array>
#include <cstdint>
#include <optional>
#include <string>
#include <string_view>
#include <vector>

namespace SoloCollections
{
inline constexpr CollectionTypeId CharacterAppliedCollectionTypeId { std::uint16_t { 18 } };
inline constexpr CollectionTypeId AccountOutfitCollectionTypeId { std::uint16_t { 19 } };

inline constexpr std::uint32_t HideVisualCollectionId = 2;
inline constexpr std::uint32_t ReservedAppearanceIdMax = 9;
inline constexpr std::size_t WardrobeSlotCount = 14;
inline constexpr std::size_t MaxAccountOutfits = 10;
inline constexpr std::size_t OutfitNameMaxBytes = 48;

inline constexpr char CharacterAppliedMappingHash[] =
    "f09cf3e459d598eef49d2d1b56c76b5f36939e7023bce18291a7b51ec393e814";
inline constexpr char AccountOutfitMappingHash[] =
    "ef7629703270ae32078c089e505474f952caa1db778a5ea737abe9a1f7fc0ec5";

inline constexpr std::uint32_t WarningReplacesExisting = 0x00000001;
inline constexpr std::uint32_t WarningIncludesHide = 0x00000002;
inline constexpr std::uint32_t WarningNoItemInSlot = 0x00000004;

struct WardrobeSlotDefinition
{
    char const* Key;
    std::uint8_t InventorySlot;
};

inline constexpr std::array<WardrobeSlotDefinition, WardrobeSlotCount> WardrobeSlots {{
    { "HEAD", 0 }, { "SHOULDER", 2 }, { "BACK", 14 }, { "CHEST", 4 },
    { "SHIRT", 3 }, { "TABARD", 18 }, { "WRIST", 8 }, { "HANDS", 9 },
    { "WAIST", 5 }, { "LEGS", 6 }, { "FEET", 7 }, { "MAINHAND", 15 },
    { "OFFHAND", 16 }, { "RANGED", 17 },
}};

using WardrobeSlotValues = std::array<std::uint32_t, WardrobeSlotCount>;

[[nodiscard]] inline std::optional<std::size_t> WardrobeIndexForInventorySlot(std::uint8_t slot)
{
    for (std::size_t index = 0; index < WardrobeSlots.size(); ++index)
        if (WardrobeSlots[index].InventorySlot == slot)
            return index;
    return std::nullopt;
}

[[nodiscard]] inline bool IsReservedAppearanceId(std::uint32_t collectionId)
{
    return collectionId >= 1 && collectionId <= ReservedAppearanceIdMax;
}

[[nodiscard]] inline bool IsHideVisualId(std::uint32_t collectionId)
{
    return collectionId == HideVisualCollectionId;
}

[[nodiscard]] inline std::string EncodeWardrobeSlots(WardrobeSlotValues const& slots)
{
    std::string payload;
    for (std::size_t index = 0; index < slots.size(); ++index)
    {
        if (index)
            payload.push_back(',');
        if (slots[index] == 0)
            payload.push_back('-');
        else
            payload += std::to_string(slots[index]);
    }
    return payload;
}

[[nodiscard]] inline std::optional<WardrobeSlotValues> DecodeWardrobeSlots(std::string_view payload)
{
    WardrobeSlotValues slots {};
    std::size_t index = 0;
    std::size_t begin = 0;
    while (index < WardrobeSlotCount)
    {
        std::size_t comma = payload.find(',', begin);
        std::string_view token = payload.substr(begin,
            (comma == std::string_view::npos ? payload.size() : comma) - begin);
        if (token == "-")
            slots[index] = 0;
        else
        {
            if (token.empty() || (token.size() > 1 && token.front() == '0'))
                return std::nullopt;
            std::uint32_t value = 0;
            for (char character : token)
            {
                if (character < '0' || character > '9')
                    return std::nullopt;
                if (value > (4294967295u - static_cast<std::uint32_t>(character - '0')) / 10)
                    return std::nullopt;
                value = value * 10 + static_cast<std::uint32_t>(character - '0');
            }
            if (value == 0)
                return std::nullopt;
            slots[index] = value;
        }
        ++index;
        if (comma == std::string_view::npos)
            break;
        begin = comma + 1;
    }
    if (index != WardrobeSlotCount)
        return std::nullopt;
    if (std::count(payload.begin(), payload.end(), ',') != static_cast<std::ptrdiff_t>(WardrobeSlotCount - 1))
        return std::nullopt;
    return slots;
}

struct AccountOutfitRecord
{
    std::uint32_t Uid = 0;
    std::string NameHex;
    WardrobeSlotValues Slots {};
    std::uint64_t Revision = 0;
};

[[nodiscard]] inline std::string EncodeAccountOutfits(std::vector<AccountOutfitRecord> const& outfits)
{
    if (outfits.empty())
        return "-";
    std::string payload;
    for (AccountOutfitRecord const& outfit : outfits)
    {
        if (!payload.empty())
            payload.push_back(';');
        payload += std::to_string(outfit.Uid);
        payload.push_back(':');
        payload += outfit.NameHex;
        payload.push_back(':');
        payload += EncodeWardrobeSlots(outfit.Slots);
    }
    return payload;
}

[[nodiscard]] inline bool ClientBuildHasWardrobe(std::string_view clientBuild)
{
    return clientBuild.find("-w1") != std::string_view::npos;
}
}

#endif
