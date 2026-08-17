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

    // Asynchronous: completions run on the world update thread after the
    // database commit resolves, or synchronously on validation failure.
    using OutfitCompletion = std::function<void(TransmogApplyResult)>;

    [[nodiscard]] OutfitMap const& List(ObjectGuid characterGuid) const;
    [[nodiscard]] OutfitRecord const* Find(ObjectGuid characterGuid, std::uint8_t outfitId) const;
    void Save(Player* player, std::string_view requestedName, OutfitCompletion completion);
    void Delete(Player* player, std::uint8_t outfitId, OutfitCompletion completion);
    void Apply(Player* player, std::uint8_t outfitId, ObjectGuid interactionGuid,
        OutfitCompletion completion) const;

private:
    std::unordered_map<ObjectGuid, OutfitMap> _byCharacter;
};

OutfitService& GetOutfitService();
}

#endif
