#include "SoloCollectionsAccountCache.h"
#include "SoloCollectionsAccountStore.h"
#include "SoloCollectionsProvider.h"
#include "SoloCollectionsProtocolScript.h"

#include "Player.h"
#include "Log.h"
#include "ScriptMgr.h"
#include "WorldSession.h"

#include <chrono>
#include <memory>
#include <stdexcept>

namespace SoloCollections
{
namespace
{
std::uint64_t MonotonicMilliseconds()
{
    return static_cast<std::uint64_t>(std::chrono::duration_cast<std::chrono::milliseconds>(
        std::chrono::steady_clock::now().time_since_epoch()).count());
}

class SyntheticCollectionProvider final : public CollectionProvider
{
public:
    SyntheticCollectionProvider()
    {
        _descriptor.TypeId = CollectionTypeId(std::uint16_t { 1 });
        _descriptor.TypeKey = "synthetic";
    }

    [[nodiscard]] CollectionProviderDescriptor const& Descriptor() const override
    {
        return _descriptor;
    }

    [[nodiscard]] CollectionResult Evaluate(CollectionId /*collectionId*/) const override
    {
        CollectionResult result;
        result.Reason = CollectionReasonCode::NotOwned;
        result.Availability.CatalogKnown = true;
        result.Availability.AssetReady = true;
        return result;
    }

private:
    CollectionProviderDescriptor _descriptor;
};

class SoloCollectionsCoreWorldScript final : public WorldScript
{
public:
    SoloCollectionsCoreWorldScript() : WorldScript(
        "SoloCollectionsCoreWorldScript", { WORLDHOOK_ON_STARTUP, WORLDHOOK_ON_UPDATE }) { }

    void OnStartup() override
    {
        CollectionProviderRegistry& registry = GetCollectionProviderRegistry();
        RegistryRegistrationResult registration = registry.Register(std::make_unique<SyntheticCollectionProvider>());
        if (!registration.Accepted)
            throw std::runtime_error("SoloCollections provider registration failed: " + registration.Message);

        RegistryFinalizeResult finalized = registry.Finalize();
        if (!finalized.Success)
            throw std::runtime_error("SoloCollections provider finalization failed: " + finalized.Message);

        (void)GetAccountCollectionCache();
        GetAccountCollectionStore().Initialize();

        LOG_INFO("module", "SoloCollections provider registry initialized with {} provider(s); "
            "account cache initialized with world-thread confinement.", registry.TopologicalOrder().size());
    }

    void OnUpdate(std::uint32_t /*diff*/) override
    {
        GetAccountCollectionStore().Update();
        (void)GetAccountCollectionCache().EvictExpired(MonotonicMilliseconds());
    }
};

class SoloCollectionsCorePlayerScript final : public PlayerScript
{
public:
    SoloCollectionsCorePlayerScript() : PlayerScript(
        "SoloCollectionsCorePlayerScript", { PLAYERHOOK_ON_LOGIN, PLAYERHOOK_ON_LOGOUT,
            PLAYERHOOK_ON_UPDATE, PLAYERHOOK_CAN_PLAYER_USE_PRIVATE_CHAT }) { }

    void OnPlayerLogin(Player* player) override
    {
        if (!player || !player->GetSession())
            return;

        AccountId accountId(player->GetSession()->GetAccountId());
        std::uint32_t playerGuid = player->GetGUID().GetCounter();
        AccountSessionOpenResult opened = GetAccountCollectionCache().OpenSession(
            accountId, AccountSessionId(playerGuid), MonotonicMilliseconds());
        if (opened.Accepted && opened.ShouldStartLoad)
            GetAccountCollectionStore().BeginLoad(accountId, playerGuid, opened.Generation);
        Sc2ProtocolOpenSession(player);
    }

    void OnPlayerLogout(Player* player) override
    {
        if (!player || !player->GetSession())
            return;

        Sc2ProtocolCloseSession(player);
        (void)GetAccountCollectionCache().CloseSession(
            AccountId(player->GetSession()->GetAccountId()),
            AccountSessionId(player->GetGUID().GetCounter()), MonotonicMilliseconds());
    }

    void OnPlayerUpdate(Player* player, std::uint32_t /*diff*/) override
    {
        Sc2ProtocolPumpAndSend(player);
    }

    bool OnPlayerCanUseChat(Player* player, std::uint32_t type, std::uint32_t language,
        std::string& message, Player* receiver) override
    {
        return Sc2ProtocolCanUsePrivateChat(player, type, language, message, receiver);
    }
};
}
}

void AddSC_solo_collections_core()
{
    new SoloCollections::SoloCollectionsCoreWorldScript();
    new SoloCollections::SoloCollectionsCorePlayerScript();
}
