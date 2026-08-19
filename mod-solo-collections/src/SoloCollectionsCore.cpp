#include "SoloCollectionsAccountCache.h"
#include "SoloCollectionsAccountStore.h"
#include "SoloCollectionsBackend.h"
#include "Categories/Appearance/SoloCollectionsAppearanceService.h"
#include "Categories/Appearance/SoloCollectionsAppearanceCatalog.h"
#include "SoloCollectionsCompanionCatalog.h"
#include "SoloCollectionsCompanionService.h"
#include "SoloCollectionsIdentity.h"
#include "SoloCollectionsMountCatalog.h"
#include "SoloCollectionsMountService.h"
#include "SoloCollectionsProvider.h"
#include "SoloCollectionsProtocol.h"
#include "SoloCollectionsProtocolScript.h"
#include "SoloCollectionsSetCatalog.h"
#include "SoloCollectionsShadowService.h"
#include "SoloCollectionsToyCatalog.h"
#include "SoloCollectionsToyService.h"
#include "SoloCollectionsTitleService.h"

#include "Item.h"
#include "Chat.h"
#include "Log.h"
#include "Player.h"
#include "ScriptMgr.h"
#include "SpellScript.h"
#include "WorldSession.h"

#include <chrono>
#include <memory>
#include <stdexcept>
#include <string_view>

namespace SoloCollections
{
namespace
{
constexpr char const* kCreditsModuleName = "SoloCollections";
constexpr char const* kCreditsSummary = "SoloCollections模块模拟军团再临版本的收藏系统和幻化系统。";
constexpr char const* kCreditsAuthor = "本项目由woden开发";
constexpr char const* kCreditsQqGroup = "1031799838";
constexpr char const* kCreditsEmail = "woden3702@gmail.com";
constexpr char const* kCreditsRepository = "https://github.com/haha2345/SoloCollectionsPlatform";
constexpr char const* kCreditsLicense = "本模块仅限学习交流使用，禁止用于商业用途。";

constexpr char const* kCreditsBanner[] = {
    "  ███████╗ ██████╗ ██╗      ██████╗",
    "  ██╔════╝██╔═══██╗██║     ██╔═══██╗",
    "  ███████╗██║   ██║██║     ██║   ██║",
    "  ╚════██║██║   ██║██║     ██║   ██║",
    "  ███████║╚██████╔╝███████╗╚██████╔╝",
    "  ╚══════╝ ╚═════╝ ╚══════╝ ╚═════╝",
    " ",
    "  ██████╗  ██████╗ ██╗     ██╗     ███████╗ ██████╗ ████████╗██╗ ██████╗ ███╗   ██╗ ███████╗",
    " ██╔════╝ ██╔═══██╗██║     ██║     ██╔════╝██╔════╝ ╚══██╔══╝██║██╔═══██╗████╗  ██║ ██╔════╝",
    " ██║      ██║   ██║██║     ██║     █████╗  ██║         ██║   ██║██║   ██║██╔██╗ ██║ ███████╗",
    " ██║      ██║   ██║██║     ██║     ██╔══╝  ██║         ██║   ██║██║   ██║██║╚██╗██║ ╚════██║",
    " ╚██████╗ ╚██████╔╝███████╗███████╗███████╗╚██████╗    ██║   ██║╚██████╔╝██║ ╚████║ ███████║",
    "  ╚═════╝  ╚═════╝ ╚══════╝╚══════╝╚══════╝ ╚═════╝    ╚═╝   ╚═╝ ╚═════╝ ╚═╝  ╚═══╝ ╚══════╝",
};

void LogModuleCredits()
{
    LOG_INFO("server.worldserver", " ");
    for (char const* line : kCreditsBanner)
        LOG_INFO("server.worldserver", "{}", line);
    LOG_INFO("server.worldserver", " ");
    LOG_INFO("server.worldserver", "     {}", kCreditsSummary);
    LOG_INFO("server.worldserver", "     {}  ·  QQ群：{}  ·  {}", kCreditsAuthor, kCreditsQqGroup, kCreditsEmail);
    LOG_INFO("server.worldserver", "     {}", kCreditsRepository);
    LOG_INFO("server.worldserver", "     {}", kCreditsLicense);
    LOG_INFO("server.worldserver", " ");
}

void SendModuleCredits(Player* player)
{
    if (!player || !player->GetSession())
        return;

    ChatHandler handler(player->GetSession());
    handler.PSendSysMessage("本服务端已加载|cffffd100{}|r模块，此模块模拟军团再临版本的收藏系统和幻化系统。",
        kCreditsModuleName);
    handler.PSendSysMessage("{}  ·  QQ群：{}  ·  {}", kCreditsAuthor, kCreditsQqGroup, kCreditsEmail);
    handler.PSendSysMessage("{}", kCreditsRepository);
    handler.PSendSysMessage("{}", kCreditsLicense);
}

std::uint64_t MonotonicMilliseconds()
{
    return static_cast<std::uint64_t>(std::chrono::duration_cast<std::chrono::milliseconds>(
        std::chrono::steady_clock::now().time_since_epoch()).count());
}

std::string_view RandomMountMessage(std::string_view reason)
{
    if (reason == "NO_MOUNTS") return "尚未获得可召唤的坐骑。";
    if (reason == "NO_USABLE_MOUNTS") return "当前没有可在此处召唤的坐骑。";
    if (reason == "IN_COMBAT") return "战斗中不能召唤坐骑。";
    if (reason == "DEAD") return "死亡状态下不能召唤坐骑。";
    if (reason == "IN_VEHICLE") return "乘坐载具时不能召唤坐骑。";
    if (reason == "ON_TAXI") return "使用飞行点时不能召唤坐骑。";
    if (reason == "INDOORS") return "室内不能召唤坐骑。";
    if (reason == "SHAPESHIFT_RESTRICTED") return "当前形态不能召唤坐骑，请恢复人形。";
    if (reason == "BATTLEGROUND_RESTRICTED") return "当前战场状态不能召唤该坐骑。";
    if (reason == "LOADING") return "收藏状态正在同步，请稍后再试。";
    if (reason == "DB_UNAVAILABLE") return "收藏服务暂时不可用，请稍后再试。";
    return "坐骑召唤失败，请检查当前角色状态。";
}

class spell_solo_collections_random_mount final : public SpellScript
{
    PrepareSpellScript(spell_solo_collections_random_mount);

    void HandleDummy(SpellEffIndex effectIndex)
    {
        PreventHitDefaultEffect(effectIndex);
        Player* player = GetCaster() ? GetCaster()->ToPlayer() : nullptr;
        if (!player || !player->GetSession())
            return;
        std::string result = GetMountCollectionService().ExecuteRandomSummon(player);
        if (result != "ACCEPTED" && result != "DISMISSED")
            ChatHandler(player->GetSession()).SendNotification(RandomMountMessage(result).data());
    }

    void Register() override
    {
        OnEffectHitTarget += SpellEffectFn(
            spell_solo_collections_random_mount::HandleDummy, EFFECT_0, SPELL_EFFECT_DUMMY);
    }
};

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

class MountFavoriteCollectionProvider final : public CollectionProvider
{
public:
    MountFavoriteCollectionProvider()
    {
        _descriptor.TypeId = MountFavoriteCollectionTypeId;
        _descriptor.TypeKey = "mount-favorite";
        _descriptor.Dependencies = { MountCollectionTypeId };
    }

    [[nodiscard]] CollectionProviderDescriptor const& Descriptor() const override { return _descriptor; }

    [[nodiscard]] CollectionResult Evaluate(CollectionId collectionId) const override
    {
        CollectionResult result;
        MountCollectionDefinition const* definition = GetMountCatalog().Find(collectionId);
        bool known = definition && definition->JournalVisible && definition->Actionable;
        result.Reason = known ? CollectionReasonCode::NotOwned : CollectionReasonCode::UnknownCollection;
        result.Availability.CatalogKnown = known;
        result.Availability.AssetReady = known;
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

class CompanionFavoriteCollectionProvider final : public CollectionProvider
{
public:
    CompanionFavoriteCollectionProvider()
    {
        _descriptor.TypeId = CompanionFavoriteCollectionTypeId;
        _descriptor.TypeKey = "companion-favorite";
        _descriptor.Dependencies = { CompanionCollectionTypeId };
    }

    [[nodiscard]] CollectionProviderDescriptor const& Descriptor() const override { return _descriptor; }

    [[nodiscard]] CollectionResult Evaluate(CollectionId collectionId) const override
    {
        CollectionResult result;
        CompanionCollectionDefinition const* definition = GetCompanionCatalog().Find(collectionId);
        bool known = definition && definition->Lifecycle == CatalogLifecycle::Active &&
            definition->JournalVisible && definition->Actionable;
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

class AppearanceNewCollectionProvider final : public CollectionProvider
{
public:
    AppearanceNewCollectionProvider()
    {
        _descriptor.TypeId = AppearanceNewCollectionTypeId;
        _descriptor.TypeKey = "appearance-new";
        _descriptor.Dependencies = { AppearanceCollectionTypeId };
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
        InitializeBackendConfiguration();

        IdentityRegistry const& identities = GetIdentityRegistry();
        if (!identities.IsValid())
            throw std::runtime_error("generated identity registry is invalid");
        (void)GetAppearanceCatalog().Collections().size();
        CollectionProviderRegistry& registry = GetCollectionProviderRegistry();
        auto registerProvider = [&registry](std::string_view,
            std::unique_ptr<CollectionProvider> provider)
        {
            RegistryRegistrationResult registration = registry.Register(std::move(provider));
            if (registration.Accepted)
                return;
            throw std::runtime_error("SoloCollections provider registration failed");
        };
        registerProvider("synthetic", std::make_unique<SyntheticCollectionProvider>());
        registerProvider("mount", std::make_unique<MountCollectionProvider>());
        registerProvider("mount-favorite", std::make_unique<MountFavoriteCollectionProvider>());
        registerProvider("companion", std::make_unique<CompanionCollectionProvider>());
        registerProvider("companion-favorite", std::make_unique<CompanionFavoriteCollectionProvider>());
        registerProvider("toy", std::make_unique<ToyCollectionProvider>());
        registerProvider("appearance", std::make_unique<AppearanceCollectionProvider>());
        registerProvider("appearance-new", std::make_unique<AppearanceNewCollectionProvider>());
        registerProvider("set", std::make_unique<SetCollectionProvider>());
        registerProvider("title", std::make_unique<TitleCollectionProvider>());

        RegistryFinalizeResult finalized = registry.Finalize();
        if (!finalized.Success)
            throw std::runtime_error("SoloCollections provider finalization failed");

        (void)GetAccountCollectionCache();
        GetAccountCollectionStore().SetWritesEnabled(IsCppBackendOwner());
        if (GetBackendMode() != BackendMode::Lua)
            GetAccountCollectionStore().Initialize();

        LogModuleCredits();
    }

    void OnUpdate(std::uint32_t /*diff*/) override
    {
        if (GetBackendMode() == BackendMode::Lua)
            return;
        GetAccountCollectionStore().Update();
        if (IsCppBackendOwner())
        {
            GetMountCollectionService().Update();
            GetCompanionCollectionService().Update();
            GetToyCollectionService().Update();
            GetAppearanceService().Update();
        }
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
            PLAYERHOOK_CAN_PLAYER_USE_PRIVATE_CHAT,
            PLAYERHOOK_ON_CAN_USE_FLYING_MOUNT_AS_GROUND,
            PLAYERHOOK_ON_CAN_REPLACE_MOUNT }) { }

    bool OnPlayerCanUseFlyingMountAsGround(Player* player, SpellInfo const* spellInfo,
        std::uint32_t mapId, std::uint32_t zoneId, std::uint32_t areaId) override
    {
        return IsCppBackendOwner() && GetMountCollectionService().CanUseFlyingMountAsGround(
            player, spellInfo, mapId, zoneId, areaId);
    }

    bool OnPlayerCanReplaceMount(Player* player, SpellInfo const* spellInfo) override
    {
        return IsCppBackendOwner() && GetMountCollectionService().CanReplaceMount(player, spellInfo);
    }

    void OnPlayerLogin(Player* player) override
    {
        if (!player || !player->GetSession())
            return;

        SendModuleCredits(player);

        if (GetBackendMode() == BackendMode::Lua)
            return;

        AccountId accountId(player->GetSession()->GetAccountId());
        std::uint32_t playerGuid = player->GetGUID().GetCounter();
        AccountSessionOpenResult opened = GetAccountCollectionCache().OpenSession(
            accountId, AccountSessionId(playerGuid), MonotonicMilliseconds());
        if (opened.Accepted && opened.ShouldStartLoad)
            GetAccountCollectionStore().BeginLoad(accountId, playerGuid, opened.Generation);
        if (IsCppBackendOwner())
        {
            GetMountCollectionService().OnPlayerLogin(player);
            GetCompanionCollectionService().OnPlayerLogin(player);
            GetToyCollectionService().OnPlayerLogin(player);
            GetAppearanceService().OnPlayerLogin(player);
            Sc2ProtocolOpenSession(player);
        }
        else
            ShadowComparisonOnPlayerLogin(player);
    }

    void OnPlayerLogout(Player* player) override
    {
        if (!player || !player->GetSession())
            return;

        if (GetBackendMode() == BackendMode::Lua)
            return;
        if (IsCppBackendOwner())
        {
            Sc2ProtocolCloseSession(player);
            GetAppearanceService().OnPlayerLogout(player);
        }
        else
            ShadowComparisonOnPlayerLogout(player);
        (void)GetAccountCollectionCache().CloseSession(
            AccountId(player->GetSession()->GetAccountId()),
            AccountSessionId(player->GetGUID().GetCounter()), MonotonicMilliseconds());
    }

    void OnPlayerUpdate(Player* player, std::uint32_t diff) override
    {
        if (IsCppBackendOwner())
        {
            GetMountCollectionService().ReconcileNativeMountState(player);
            GetMountCollectionService().ReconcileCharacterMountActions(player);
            if (player && player->GetSession() && !player->HasSpell(MountRandomSpellId))
            {
                std::optional<AccountCacheSnapshot> snapshot = GetAccountCollectionCache().Snapshot(
                    AccountId(player->GetSession()->GetAccountId()));
                if (snapshot && snapshot->State == AccountCacheLoadState::Ready)
                {
                    player->learnSpell(MountRandomSpellId, false);
                }
            }
            Sc2ProtocolPumpAndSend(player);
            GetAppearanceService().OnPlayerUpdate(player, diff);
        }
        else if (IsShadowComparisonEnabled())
            ShadowComparisonOnPlayerUpdate(player);
    }

    void OnPlayerLearnSpell(Player* player, std::uint32_t spellId) override
    {
        if (!IsCppBackendOwner())
            return;
        GetMountCollectionService().OnPlayerLearnSpell(player, spellId);
        GetCompanionCollectionService().OnPlayerLearnSpell(player, spellId);
    }

    void OnPlayerStoreNewItem(Player* player, Item* item, std::uint32_t /*count*/) override
    {
        if (!IsCppBackendOwner())
            return;
        OnToyItem(player, item);
        // Player::StoreNewItem is the shared convergence path for mail,
        // trade, auction, buyback, GM delivery, and other inventory stores.
        OnAppearanceItem(player, item, AppearanceUnlockTrigger::InventoryStore);
    }

    void OnPlayerCreateItem(Player* player, Item* item, std::uint32_t /*count*/) override
    {
        if (!IsCppBackendOwner())
            return;
        OnToyItem(player, item);
        OnAppearanceItem(player, item, AppearanceUnlockTrigger::Craft);
    }

    void OnPlayerQuestRewardItem(Player* player, Item* item, std::uint32_t /*count*/) override
    {
        if (!IsCppBackendOwner())
            return;
        OnToyItem(player, item);
        // This callback contains only the reward item actually granted; never
        // infer ownership from every candidate in RewardChoiceItemId.
        OnAppearanceItem(player, item, AppearanceUnlockTrigger::QuestReward);
    }

    void OnPlayerAfterStoreOrEquipNewItem(Player* player, std::uint32_t /*vendorslot*/, Item* item,
        std::uint8_t /*count*/, std::uint8_t /*bag*/, std::uint8_t /*slot*/, ItemTemplate const* /*pProto*/,
        Creature* pVendor, VendorItem const* /*crItem*/, bool /*bStore*/) override
    {
        if (!IsCppBackendOwner())
            return;
        OnToyItem(player, item);
        OnAppearanceItem(player, item, pVendor ? AppearanceUnlockTrigger::Vendor :
            AppearanceUnlockTrigger::InventoryStore);
    }

    void OnPlayerEquip(Player* player, Item* item, std::uint8_t /*bag*/,
        std::uint8_t /*slot*/, bool /*update*/) override
    {
        if (!IsCppBackendOwner())
            return;
        OnAppearanceItem(player, item, AppearanceUnlockTrigger::Equipment);
    }

    void OnPlayerLootItem(Player* player, Item* item, std::uint32_t /*count*/,
        ObjectGuid /*lootGuid*/) override
    {
        if (!IsCppBackendOwner())
            return;
        OnAppearanceItem(player, item, AppearanceUnlockTrigger::Loot);
    }

    void OnPlayerGroupRollRewardItem(Player* player, Item* item, std::uint32_t /*count*/,
        RollVote /*voteType*/, Roll* /*roll*/) override
    {
        if (!IsCppBackendOwner())
            return;
        OnAppearanceItem(player, item, AppearanceUnlockTrigger::GroupRoll);
    }

    bool OnPlayerCanUseChat(Player* player, std::uint32_t type, std::uint32_t language,
        std::string& message, Player* receiver) override
    {
        return IsCppBackendOwner() ?
            Sc2ProtocolCanUsePrivateChat(player, type, language, message, receiver) : true;
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
    RegisterSpellScript(SoloCollections::spell_solo_collections_random_mount);
    new SoloCollections::SoloCollectionsCoreWorldScript();
    new SoloCollections::SoloCollectionsCorePlayerScript();
}
