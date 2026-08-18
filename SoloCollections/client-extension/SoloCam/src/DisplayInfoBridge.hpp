#pragma once

#include <cstddef>
#include <cstdint>

constexpr std::uint32_t kDisplayInfoRequestBase = 0x6F000000;
constexpr std::uint32_t kMaximumDisplayInfoId = 0x00FFFFFF;

// The 3.3.5a PlayerModel path does not take a display ID directly. It keeps a
// pointer to a creature-cache record and reads the display ID at offset 0x24.
// Direct-display requests therefore need stable storage with this exact layout.
struct SyntheticCreatureRecord
{
    std::uint8_t reserved[0x24]{};
    std::uint32_t displayId = 0;
};

static_assert(
    offsetof(SyntheticCreatureRecord, displayId) == 0x24,
    "3.3.5a creature-cache display ID offset changed"
);

bool TryDecodeDisplayInfoRequest(std::uint32_t request, std::uint32_t& displayId);
