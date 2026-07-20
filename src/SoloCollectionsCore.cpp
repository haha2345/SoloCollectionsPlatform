#include "SoloCollectionsAccountCache.h"
#include "SoloCollectionsAccountStore.h"
#include "Categories/Appearance/SoloCollectionsAppearanceService.h"
#include "SoloCollectionsCompanionCatalog.h"
#include "SoloCollectionsCompanionService.h"
#include "SoloCollectionsMountCatalog.h"
#include "SoloCollectionsMountService.h"
#include "SoloCollectionsProvider.h"
#include "SoloCollectionsProtocolScript.h"
#include "SoloCollectionsSetCatalog.h"
#include "SoloCollectionsToyCatalog.h"
#include "SoloCollectionsToyService.h"
#include "SoloCollectionsTitleService.h"

#include "Item.h"
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

class MountCollectionProvider final : public CollectionProvider
{
public:
    MountCollectionProvider()
    {
        _descriptor.TypeId = MountCollectionTypeId;
        _descriptor.TypeKey = "mount";
    }

    [[nodiscard]] CollectionProviderDescriptor const& Descriptor() const override
    {
        return _descriptor;
    }

    [[nodiscard]] CollectionResult Evaluate(CollectionId collectionId) const override
    {
        CollectionResult result;
        MountCollectionDefinition const* definition = GetMountCatalog().Find(collectionId);
        result.Reason = definition ? CollectionReasonCode::NotOwned : CollectionReasonCode::UnknownCollection;
        result.Availability.CatalogKnown = definition != nullptr;
        result.Availability.AssetReady = definition != nullptr;
        return result;
    }

private:
    CollectionProviderDescriptor _descriptor;
};

class CompanionCollectionProvider final : public CollectionProvider
{
public:
    CompanionCollectionProvider()
    {
        _descriptor.TypeId = CompanionCollectionTypeId;
        _descriptor.TypeKey = "companion";
    }

    [[nodiscard]] CollectionProviderDescriptor const& Descriptor() const override { return _descriptor; }

    [[nodiscard]] CollectionResult Evaluate(CollectionId collectionId) const override
    {
        CollectionResult result;
        bool known = GetCompanionCatalog().Find(collectionId) != nullptr;
        result.Reason = known ? CollectionReasonCode::NotOwned : CollectionReasonCode::UnknownCollection;
        result.Availability.CatalogKnown = known;
        result.Availability.AssetReady = known;
        return result;
    }

private:
    CollectionProviderDescriptor _descriptor;
};

class ToyCollectionProvider final : public CollectionProvider
{
public:
    ToyCollectionProvider()
    {
        _descriptor.TypeId = ToyCollectionTypeId;
        _descriptor.TypeKey = "toy";
    }

    [[nodiscard]] CollectionProviderDescriptor const& Descriptor() const override { return _descriptor; }

    [[nodiscard]] CollectionResult Evaluate(CollectionId collectionId) const override
    {
        CollectionResult result;
        bool known = GetToyCatalog().Find(collectionId) != nullptr;
        result.Reason = known ? CollectionReasonCode::NotOwned : CollectionReasonCode::UnknownCollection;
        result.Availability.CatalogKnown = known;
        result.Availability.AssetReady = known;
        return result;
    }

private:
    CollectionProviderDescriptor _descriptor;
};

class AppearanceCollectionProvider final : public CollectionProvider
{
public:
    AppearanceCollectionProvider()
    {
        _descriptor.TypeId = AppearanceCollectionTypeId;
        _descriptor.TypeKey = "appearance";
    }

    [[nodiscard]] CollectionProviderDescriptor const& Descriptor() const override { return _descriptor; }
    [[nodiscard]] CollectionResult Evaluate(CollectionId collectionId) const override
    {
        return GetAppearanceService().Evaluate(collectionId);
    }

private:
    CollectionProviderDescriptor _descriptor;
};

class SetCollectionProvider final : public CollectionProvider
{
public:
    SetCollectionProvider()
    {
        _descriptor.TypeId = SetCollectionTypeId;
        _descriptor.TypeKey = "set";
        _descriptor.Dependencies = { SetAppearanceDependencyTypeId };
        _descriptor.Storage = CollectionStorageMode::Derived;
    }

    [[nodiscard]] CollectionProviderDescriptor const& Descriptor() const override { return _descriptor; }
    [[nodiscard]] CollectionResult Evaluate(CollectionId collectionId) const override
    {
        CollectionResult result;
        bool known = GetSetCatalog().Find(collectionId) != nullptr;
        result.Reason = known ? CollectionReasonCode::NotOwned : CollectionReasonCode::UnknownCollection;
        result.Availability.CatalogKnown = known;
        result.Availability.AssetReady = known;
        return result;
    }
    [[nodiscard]] std::optional<bool> IsOwned(AccountId accountId, CollectionId collectionId) const override
    {
        return GetSetCatalog().IsComplete(accountId, collectionId);
    }
    [[nodiscard]] std::optional<std::vector<CollectionId>> OwnedByAccount(AccountId accountId) const override
    {
        return GetSetCatalog().CompletedByAccount(accountId);
    }

private:
    CollectionProviderDescriptor _descriptor;
};

class TitleCollectionProvider final : public CollectionProvider
{
public:
    TitleCollectionProvider()
    {
        _descriptor.TypeId = TitleCollectionTypeId;
        _descriptor.TypeKey = "title";
        _descriptor.Storage = CollectionStorageMode::External;
    }

    [[nodiscard]] CollectionProviderDescriptor const& Descriptor() const override { return _descriptor; }
    [[nodiscard]] CollectionResult Evaluate(CollectionId collectionId) const override
    {
        return GetTitleService().Evaluate(collectionId);
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
        registration = registry.Register(std::make_unique<MountCollectionProvider>());
        if (!registration.Accepted)
            throw std::runtime_error("SoloCollections mount provider registration failed: " + registration.Message);
        registration = registry.Register(std::make_unique<CompanionCollectionProvider>());
        if (!registration.Accepted)
            throw std::runtime_error("SoloCollections companion provider registration failed: " + registration.Message);
        registration = registry.Register(std::make_unique<ToyCollectionProvider>());
        if (!registration.Accepted)
            throw std::runtime_error("SoloCollections toy provider registration failed: " + registration.Message);
        registration = registry.Register(std::make_unique<AppearanceCollectionProvider>());
        if (!registration.Accepted)
            throw std::runtime_error("SoloCollections appearance provider registration failed: " + registration.Message);
        registration = registry.Register(std::make_unique<SetCollectionProvider>());
        if (!registration.Accepted)
            throw std::runtime_error("SoloCollections set provider registration failed: " + registration.Message);
        registration = registry.Register(std::make_unique<TitleCollectionProvider>());
        if (!registration.Accepted)
            throw std::runtime_error("SoloCollections title provider registration failed: " + registration.Message);

        RegistryFinalizeResult finalized = registry.Finalize();
        if (!finalized.Success)
            throw std::runtime_error("SoloCollections provider finalization failed: " + finalized.Message);

        (void)GetAccountCollectionCache();
        GetAccountCollectionStore().Initialize();

        LOG_INFO("module", "SoloCollections provider registry initialized with {} provider(s); "
            "account cache initialized with explicit cross-thread locking.", registry.TopologicalOrder().size());
    }

    void OnUpdate(std::uint32_t /*diff*/) override
    {
        GetAccountCollectionStore().Update();
        GetMountCollectionService().Update();
        GetCompanionCollectionService().Update();
        GetToyCollectionService().Update();
        GetAppearanceService().Update();
        (void)GetAccountCollectionCache().EvictExpired(MonotonicMilliseconds());
    }
};

class SoloCollectionsCorePlayerScript final : public PlayerScript
{
public:
    SoloCollectionsCorePlayerScript() : PlayerScript(
        "SoloCollectionsCorePlayerScript", { PLAYERHOOK_ON_LOGIN, PLAYERHOOK_ON_LOGOUT,
            PLAYERHOOK_ON_UPDATE, PLAYERHOOK_ON_LEARN_SPELL, PLAYERHOOK_ON_STORE_NEW_ITEM,
            PLAYERHOOK_ON_CREATE_ITEM, PLAYERHOOK_ON_QUEST_REWARD_ITEM,
            PLAYERHOOK_ON_AFTER_STORE_OR_EQUIP_NEW_ITEM, PLAYERHOOK_ON_EQUIP,
            PLAYERHOOK_ON_LOOT_ITEM, PLAYERHOOK_ON_GROUP_ROLL_REWARD_ITEM,
            PLAYERHOOK_CAN_PLAYER_USE_PRIVATE_CHAT }) { }

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
        GetMountCollectionService().OnPlayerLogin(player);
        GetCompanionCollectionService().OnPlayerLogin(player);
        GetToyCollectionService().OnPlayerLogin(player);
        GetAppearanceService().OnPlayerLogin(player);
        Sc2ProtocolOpenSession(player);
    }

    void OnPlayerLogout(Player* player) override
    {
        if (!player || !player->GetSession())
            return;

        Sc2ProtocolCloseSession(player);
        GetAppearanceService().OnPlayerLogout(player);
        (void)GetAccountCollectionCache().CloseSession(
            AccountId(player->GetSession()->GetAccountId()),
            AccountSessionId(player->GetGUID().GetCounter()), MonotonicMilliseconds());
    }

    void OnPlayerUpdate(Player* player, std::uint32_t diff) override
    {
        Sc2ProtocolPumpAndSend(player);
        GetAppearanceService().OnPlayerUpdate(player, diff);
    }

    void OnPlayerLearnSpell(Player* player, std::uint32_t spellId) override
    {
        GetMountCollectionService().OnPlayerLearnSpell(player, spellId);
        GetCompanionCollectionService().OnPlayerLearnSpell(player, spellId);
    }

    void OnPlayerStoreNewItem(Player* player, Item* item, std::uint32_t /*count*/) override
    {
        OnToyItem(player, item);
        // Player::StoreNewItem is the shared convergence path for mail,
        // trade, auction, buyback, GM delivery, and other inventory stores.
        OnAppearanceItem(player, item, AppearanceUnlockTrigger::InventoryStore);
    }

    void OnPlayerCreateItem(Player* player, Item* item, std::uint32_t /*count*/) override
    {
        OnToyItem(player, item);
        OnAppearanceItem(player, item, AppearanceUnlockTrigger::Craft);
    }

    void OnPlayerQuestRewardItem(Player* player, Item* item, std::uint32_t /*count*/) override
    {
        OnToyItem(player, item);
        // This callback contains only the reward item actually granted; never
        // infer ownership from every candidate in RewardChoiceItemId.
        OnAppearanceItem(player, item, AppearanceUnlockTrigger::QuestReward);
    }

    void OnPlayerAfterStoreOrEquipNewItem(Player* player, std::uint32_t /*vendorslot*/, Item* item,
        std::uint8_t /*count*/, std::uint8_t /*bag*/, std::uint8_t /*slot*/, ItemTemplate const* /*pProto*/,
        Creature* pVendor, VendorItem const* /*crItem*/, bool /*bStore*/) override
    {
        OnToyItem(player, item);
        OnAppearanceItem(player, item, pVendor ? AppearanceUnlockTrigger::Vendor :
            AppearanceUnlockTrigger::InventoryStore);
    }

    void OnPlayerEquip(Player* player, Item* item, std::uint8_t /*bag*/,
        std::uint8_t /*slot*/, bool /*update*/) override
    {
        OnAppearanceItem(player, item, AppearanceUnlockTrigger::Equipment);
    }

    void OnPlayerLootItem(Player* player, Item* item, std::uint32_t /*count*/,
        ObjectGuid /*lootGuid*/) override
    {
        OnAppearanceItem(player, item, AppearanceUnlockTrigger::Loot);
    }

    void OnPlayerGroupRollRewardItem(Player* player, Item* item, std::uint32_t /*count*/,
        RollVote /*voteType*/, Roll* /*roll*/) override
    {
        OnAppearanceItem(player, item, AppearanceUnlockTrigger::GroupRoll);
    }

    bool OnPlayerCanUseChat(Player* player, std::uint32_t type, std::uint32_t language,
        std::string& message, Player* receiver) override
    {
        return Sc2ProtocolCanUsePrivateChat(player, type, language, message, receiver);
    }

private:
    static void OnToyItem(Player* player, Item* item)
    {
        if (item)
            GetToyCollectionService().OnItemAcquired(player, item->GetEntry());
    }

    static void OnAppearanceItem(Player* player, Item* item, AppearanceUnlockTrigger trigger)
    {
        if (item)
            (void)GetAppearanceService().OnItemAcquired(player, item, trigger);
    }
};
}
}

void AddSC_solo_collections_core()
{
    new SoloCollections::SoloCollectionsCoreWorldScript();
    new SoloCollections::SoloCollectionsCorePlayerScript();
}
