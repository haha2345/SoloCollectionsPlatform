#ifndef SOLO_COLLECTIONS_MOUNT_CATALOG_H
#define SOLO_COLLECTIONS_MOUNT_CATALOG_H

#include "SoloCollectionsTypes.h"

#include <cstdint>
#include <map>
#include <string>
#include <vector>

namespace SoloCollections
{
inline constexpr CollectionTypeId MountCollectionTypeId { std::uint16_t { 10 } };

struct MountActionVariant
{
    std::uint32_t SpellId = 0;
    std::vector<std::uint32_t> RaceMasks;
    std::vector<std::uint32_t> ClassMasks;
    std::uint32_t MinimumRidingSkill = 0;
    bool IsFlying = false;
};

struct MountCollectionDefinition
{
    CollectionId Id;
    std::string Key;
    std::uint32_t CanonicalSpellId = 0;
    std::vector<std::uint32_t> CreatureIds;
    std::vector<std::uint32_t> UnlockSpellIds;
    std::vector<MountActionVariant> ActionVariants;
};

class MountCatalog final
{
public:
    explicit MountCatalog(std::vector<MountCollectionDefinition> collections);

    [[nodiscard]] MountCollectionDefinition const* Find(CollectionId collectionId) const;
    [[nodiscard]] MountCollectionDefinition const* FindByUnlockSpell(std::uint32_t spellId) const;
    [[nodiscard]] std::vector<MountCollectionDefinition> const& Collections() const { return _collections; }

private:
    std::vector<MountCollectionDefinition> _collections;
    std::map<CollectionId, std::size_t> _byCollection;
    std::map<std::uint32_t, std::size_t> _byUnlockSpell;
};

MountCatalog const& GetMountCatalog();
}

#endif
