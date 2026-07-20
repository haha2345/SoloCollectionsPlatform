#ifndef SOLO_COLLECTIONS_OUTFIT_SERVICE_H
#define SOLO_COLLECTIONS_OUTFIT_SERVICE_H

#include "ObjectGuid.h"
#include "Transmogrification.h"

#include <cstddef>
#include <cstdint>
#include <map>
#include <string>
#include <string_view>
#include <unordered_map>

class Player;

namespace SoloCollections
{
inline constexpr std::size_t OutfitNameMaxBytes = 48;
inline constexpr std::size_t OutfitSlotMaxCount = 19;

struct OutfitRecord
{
    std::uint8_t Id = 0;
    std::string Name;
    std::map<std::uint8_t, std::uint32_t> Appearances;
};

class OutfitService final
{
public:
    using OutfitMap = std::map<std::uint8_t, OutfitRecord>;

    void Load(ObjectGuid characterGuid);
    void Unload(ObjectGuid characterGuid);

    [[nodiscard]] OutfitMap const& List(ObjectGuid characterGuid) const;
    [[nodiscard]] OutfitRecord const* Find(ObjectGuid characterGuid, std::uint8_t outfitId) const;
    [[nodiscard]] TransmogApplyResult Save(Player* player, std::string_view requestedName);
    [[nodiscard]] TransmogApplyResult Delete(Player* player, std::uint8_t outfitId);
    [[nodiscard]] TransmogApplyResult Apply(Player* player, std::uint8_t outfitId,
        ObjectGuid interactionGuid) const;

private:
    std::unordered_map<ObjectGuid, OutfitMap> _byCharacter;
};

OutfitService& GetOutfitService();
}

#endif
