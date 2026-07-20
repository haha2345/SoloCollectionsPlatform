#include "SoloCollectionsSetService.h"

#include "Categories/Appearance/SoloCollectionsAppearanceService.h"
#include "SoloCollectionsAccountService.h"
#include "SoloCollectionsIdentity.h"
#include "SoloCollectionsSetCatalog.h"
#include "Transmogrification.h"

#include "Item.h"
#include "Player.h"

#include <map>
#include <optional>
#include <set>
#include <string_view>

namespace SoloCollections
{
namespace
{
std::optional<std::uint8_t> EquipmentSlot(std::string_view slotKey)
{
    if (slotKey == "HEAD") return EQUIPMENT_SLOT_HEAD;
    if (slotKey == "SHOULDER") return EQUIPMENT_SLOT_SHOULDERS;
    if (slotKey == "SHIRT") return EQUIPMENT_SLOT_BODY;
    if (slotKey == "CHEST" || slotKey == "ROBE") return EQUIPMENT_SLOT_CHEST;
    if (slotKey == "WAIST") return EQUIPMENT_SLOT_WAIST;
    if (slotKey == "LEGS") return EQUIPMENT_SLOT_LEGS;
    if (slotKey == "FEET") return EQUIPMENT_SLOT_FEET;
    if (slotKey == "WRIST") return EQUIPMENT_SLOT_WRISTS;
    if (slotKey == "HANDS") return EQUIPMENT_SLOT_HANDS;
    if (slotKey == "BACK") return EQUIPMENT_SLOT_BACK;
    if (slotKey == "MAINHAND") return EQUIPMENT_SLOT_MAINHAND;
    if (slotKey == "OFFHAND") return EQUIPMENT_SLOT_OFFHAND;
    if (slotKey == "TABARD") return EQUIPMENT_SLOT_TABARD;
    return std::nullopt;
}

bool OwnsAppearance(AccountId accountId, CollectionId appearanceId)
{
    return GetAccountCollectionService().Evaluate(
        accountId, { SetAppearanceDependencyTypeId, appearanceId }).IsSuccess();
}

bool VariantComplete(AccountId accountId, SetVariantDefinition const& variant)
{
    if (!variant.Enabled)
        return false;
    std::uint32_t required = 0;
    std::uint32_t owned = 0;
    for (SetMemberDefinition const& member : variant.Members)
    {
        if (!member.Enabled || !member.Required)
            continue;
        ++required;
        for (CollectionId appearanceId : member.AppearanceAlternatives)
            if (OwnsAppearance(accountId, appearanceId))
            {
                ++owned;
                break;
            }
    }
    return required > 0 && owned == required;
}

SetVariantDefinition const* SelectVariant(AccountId accountId,
    SetCollectionDefinition const& definition, std::uint32_t variantIndex)
{
    if (variantIndex > 0)
    {
        if (variantIndex > definition.Variants.size())
            return nullptr;
        SetVariantDefinition const& selected = definition.Variants[variantIndex - 1];
        return VariantComplete(accountId, selected) ? &selected : nullptr;
    }
    for (SetVariantDefinition const& variant : definition.Variants)
        if (VariantComplete(accountId, variant))
            return &variant;
    return nullptr;
}
}

TransmogApplyResult SetService::TryApply(Player* player, CollectionId collectionId,
    std::uint32_t variantIndex, ObjectGuid interactionGuid, TransmogApplySource source) const
{
    if (!player || !player->GetSession() || !collectionId.IsValid())
        return { LANG_TRANSMOG_INVALID_SRC_ENTRY };

    SetCollectionDefinition const* definition = GetSetCatalog().Find(collectionId);
    if (!definition)
        return { LANG_TRANSMOG_INVALID_SRC_ENTRY };

    IdentityRegistry const& identities = GetIdentityRegistry();
    auto runtimeClass = identities.ResolveClass(player->getClass());
    auto requiredClass = identities.ResolveClass(definition->ClassToken);
    if (!runtimeClass.IsKnown() || !requiredClass.IsKnown() ||
        runtimeClass.Identity->LogicalId != requiredClass.Identity->LogicalId)
        return { LANG_TRANSMOG_INVALID_ITEMS };

    AccountId accountId(player->GetSession()->GetAccountId());
    SetVariantDefinition const* variant = SelectVariant(accountId, *definition, variantIndex);
    if (!variant)
        return { LANG_TRANSMOG_MISSING_SRC_ITEM };

    std::map<std::uint8_t, std::uint32_t> sources;
    std::set<std::uint8_t> requestedSlots;
    for (SetMemberDefinition const& member : variant->Members)
    {
        if (!member.Enabled)
            continue;
        std::optional<std::uint8_t> slot = EquipmentSlot(member.SlotKey);
        if (!slot)
            return { LANG_TRANSMOG_INVALID_SLOT };
        if (!requestedSlots.insert(*slot).second)
            return { LANG_TRANSMOG_INVALID_SLOT };

        Item* target = player->GetItemByPos(INVENTORY_SLOT_BAG_0, *slot);
        if (!target)
        {
            if (member.Required)
                return { LANG_TRANSMOG_MISSING_DEST_ITEM };
            continue;
        }

        bool ownsAlternative = false;
        std::optional<std::uint32_t> sourceItemId;
        for (CollectionId appearanceId : member.AppearanceAlternatives)
        {
            if (!OwnsAppearance(accountId, appearanceId))
                continue;
            ownsAlternative = true;
            sourceItemId = GetAppearanceService().ResolveOwnedSource(player, appearanceId, *slot);
            if (sourceItemId)
                break;
        }

        if (!sourceItemId)
        {
            if (member.Required)
                return { ownsAlternative ? LANG_TRANSMOG_INVALID_ITEMS : LANG_TRANSMOG_MISSING_SRC_ITEM };
            if (ownsAlternative)
                return { LANG_TRANSMOG_INVALID_ITEMS };
            continue;
        }

        sources.emplace(*slot, *sourceItemId);
        if (sTransmogrification->GetFakeEntry(target->GetGUID()) == *sourceItemId)
            sources.erase(*slot);
    }

    if (sources.empty())
        return { LANG_TRANSMOG_OK, 0 };
    return GetAppearanceService().TryApplyCollectedAppearances(
        player, sources, interactionGuid, source, false);
}

SetService const& GetSetService()
{
    static SetService service;
    return service;
}
}
