#include "SoloCollectionsCreaturePreviewService.h"

#include "SoloCollectionsCompanionCatalog.h"
#include "SoloCollectionsMountCatalog.h"
#include "SoloCollectionsProvider.h"

#include "Config.h"
#include "CreatureData.h"
#include "ObjectGuid.h"
#include "ObjectMgr.h"
#include "Opcodes.h"
#include "Player.h"
#include "WorldPacket.h"
#include "WorldSession.h"

namespace SoloCollections
{
bool IsCreaturePreviewEnabled()
{
    // ConfigMgr is refreshed by the existing `.transmog reload` command before
    // the next request reaches this read. Keeping no second cache prevents drift.
    return sConfigMgr->GetOption<bool>("SoloCollections.Preview.Enabled", true);
}

CreaturePreviewResult CreaturePreviewService::Execute(
    Player* player, CollectionTypeId typeId, CollectionId collectionId) const
{
    CreaturePreviewResult result;
    bool enabled = IsCreaturePreviewEnabled();
    if (!player || !player->GetSession() || !collectionId.IsValid() || !enabled)
    {
        result.Status = enabled ? "INVALID_REQUEST" : "UNSUPPORTED";
        return result;
    }

    CollectionProviderRuntimeState const* providerState = GetCollectionProviderRegistry().State(typeId);
    if (!providerState || providerState->Mode != CollectionProviderMode::Enabled)
    {
        result.Status = "UNSUPPORTED";
        return result;
    }

    CatalogLifecycle lifecycle = CatalogLifecycle::Disabled;
    if (typeId == MountCollectionTypeId)
    {
        MountCollectionDefinition const* definition = GetMountCatalog().Find(collectionId);
        if (!definition)
            return result;
        result.CreatureEntry = definition->PreviewCreatureEntry;
        lifecycle = definition->Lifecycle;
    }
    else if (typeId == CompanionCollectionTypeId)
    {
        CompanionCollectionDefinition const* definition = GetCompanionCatalog().Find(collectionId);
        if (!definition)
            return result;
        result.CreatureEntry = definition->PreviewCreatureEntry;
        lifecycle = definition->Lifecycle;
    }
    else
        return result;

    if (lifecycle == CatalogLifecycle::Tombstone)
        return result;
    if (!CatalogLifecycleAllowsPreview(lifecycle))
    {
        result.Status = "UNSUPPORTED";
        return result;
    }

    CreatureTemplate const* creatureTemplate = sObjectMgr->GetCreatureTemplate(result.CreatureEntry);
    bool hasModel = false;
    if (creatureTemplate)
        for (std::uint32_t index = 0; index < 4; ++index)
            hasModel = hasModel || creatureTemplate->GetModelByIdx(index) != nullptr;
    if (!creatureTemplate || !hasModel)
    {
        result.Status = "UNSUPPORTED";
        return result;
    }

    // Core 4cc67a3 reads uint32 Entry followed by a raw uint64 ObjectGuid.
    // Reuse its handler so the module never owns the response packet layout.
    WorldPacket query(CMSG_CREATURE_QUERY, sizeof(std::uint32_t) + sizeof(std::uint64_t));
    query << std::uint32_t(result.CreatureEntry) << ObjectGuid::Empty;
    player->GetSession()->HandleCreatureQueryOpcode(query);
    result.Status = "ACCEPTED";
    result.QueryQueued = true;
    return result;
}

CreaturePreviewService const& GetCreaturePreviewService()
{
    static CreaturePreviewService service;
    return service;
}
}
