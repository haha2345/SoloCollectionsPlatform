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
inline constexpr CollectionTypeId MountFavoriteCollectionTypeId { std::uint16_t { 16 } };
inline constexpr CollectionId MountRandomActionCollectionId { std::uint32_t { 1 } };
inline constexpr std::uint32_t MountRandomSpellId = 150544;

enum class MountCapability : std::uint8_t
{
    Ground,
    Flying,
    Aquatic,
    Special,
};

enum class MountExclusionReason : std::uint8_t
{
    None,
    Taxi,
    QuestTemporary,
    ClassForm,
    Test,
    Duplicate,
    Internal,
};

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
    std::uint32_t PreviewCreatureEntry = 0;
    CatalogLifecycle Lifecycle = CatalogLifecycle::Disabled;
    bool JournalVisible = false;
    bool Actionable = false;
    bool Draggable = false;
    bool RandomEligible = false;
    std::uint32_t CanonicalActionSpellId = 0;
    MountCapability Capability = MountCapability::Special;
    MountExclusionReason ExclusionReason = MountExclusionReason::Internal;
};

class MountCatalog final
{
public:
    explicit MountCatalog(std::vector<MountCollectionDefinition> collections);

    [[nodiscard]] MountCollectionDefinition const* Find(CollectionId collectionId) const;
    [[nodiscard]] MountCollectionDefinition const* FindByUnlockSpell(std::uint32_t spellId) const;
    [[nodiscard]] MountCollectionDefinition const* FindByActionSpell(std::uint32_t spellId) const;
    [[nodiscard]] std::vector<MountCollectionDefinition> const& Collections() const { return _collections; }

private:
    std::vector<MountCollectionDefinition> _collections;
    std::map<CollectionId, std::size_t> _byCollection;
    std::map<std::uint32_t, std::size_t> _byUnlockSpell;
    std::map<std::uint32_t, std::size_t> _byActionSpell;
};

MountCatalog const& GetMountCatalog();
}

#endif
