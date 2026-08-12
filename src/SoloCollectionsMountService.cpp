#include "SoloCollectionsMountService.h"

#include "SoloCollectionsAccountCache.h"
#include "SoloCollectionsAccountStore.h"
#include "SoloCollectionsMountCatalog.h"
#include "SoloCollectionsIdentity.h"

#include "DBCStores.h"
#include "Log.h"
#include "Player.h"
#include "Random.h"
#include "SharedDefines.h"
#include "SpellAuraEffects.h"
#include "SpellAuras.h"
#include "SpellMgr.h"
#include "WorldSession.h"

#include <algorithm>
#include <deque>
#include <map>
#include <mutex>
#include <set>
#include <utility>

namespace SoloCollections
{
namespace
{
constexpr std::uint32_t MountSpellMigrationId = 1;
constexpr std::uint16_t MountSpellMigrationVersion = 1;
constexpr std::uint8_t EarlyRidingMaximumLevel = 19;
constexpr std::uint8_t EarlyFlightMinimumLevel = 45;
constexpr std::uint8_t FastFlightMinimumLevel = 60;
constexpr std::uint16_t ApprenticeRidingSkill = 75;
constexpr std::uint16_t ExpertRidingSkill = 225;
constexpr std::uint16_t ArtisanRidingSkill = 300;
constexpr std::int32_t ApprenticeMountedSpeedPercent = 60;
constexpr std::int32_t JourneymanMountedSpeedPercent = 100;
constexpr std::int32_t ExpertMountedFlightSpeedPercent = 150;

enum class MigrationPhase : std::uint8_t
{
    AwaitingReady = 1,
    CheckingMarker = 2,
    Importing = 3,
    WritingMarker = 4,
    Complete = 5,
    Failed = 6,
};

struct PendingMountGrant
{
    CollectionId Collection;
    std::uint32_t SpellId = 0;
    std::uint32_t CharacterGuid = 0;
    CollectionSourceKind SourceKind = CollectionSourceKind::Gameplay;
    bool Started = false;
};

struct MountAccountState
{
    MigrationPhase Phase = MigrationPhase::AwaitingReady;
    LoginGeneration Generation;
    std::uint32_t LoginCharacterGuid = 0;
    std::set<std::uint32_t> CandidateSpells;
    std::set<CollectionId> QueuedCollections;
    std::deque<PendingMountGrant> Pending;
    std::uint32_t ImportedCount = 0;
    std::uint32_t RejectedCount = 0;
    CollectionId LastRandomCollection;
};

AccountId PlayerAccount(Player* player)
{
    return AccountId(player->GetSession()->GetAccountId());
}

bool IsMountableHumanoidForm(ShapeshiftForm form)
{
    switch (form)
    {
        case FORM_NONE:
        case FORM_SHADOW_DANCE:
        case FORM_BATTLESTANCE:
        case FORM_DEFENSIVESTANCE:
        case FORM_BERSERKERSTANCE:
        case FORM_SHADOW:
        case FORM_STEALTH:
            return true;
        default:
            return false;
    }
}

void CapMountedGroundSpeed(Player* player, std::int32_t maximumPercent)
{
    std::set<Aura*> mountAuras;
    for (AuraEffect* mountedEffect : player->GetAuraEffectsByType(SPELL_AURA_MOUNTED))
        mountAuras.insert(mountedEffect->GetBase());

    for (Aura* mountAura : mountAuras)
    {
        for (std::uint8_t index = 0; index < MAX_SPELL_EFFECTS; ++index)
        {
            AuraEffect* effect = mountAura->GetEffect(index);
            if (!effect || effect->GetAmount() <= maximumPercent)
                continue;
            AuraType auraType = effect->GetAuraType();
            if (auraType == SPELL_AURA_MOD_INCREASE_MOUNTED_SPEED ||
                auraType == SPELL_AURA_MOD_MOUNTED_SPEED_ALWAYS ||
                auraType == SPELL_AURA_MOD_MOUNTED_SPEED_NOT_STACK)
                effect->ChangeAmount(maximumPercent);
        }
    }
}

void CapMountedFlightSpeedAtExpert(Player* player)
{
    std::set<Aura*> mountAuras;
    for (AuraEffect* mountedEffect : player->GetAuraEffectsByType(SPELL_AURA_MOUNTED))
        mountAuras.insert(mountedEffect->GetBase());

    for (Aura* mountAura : mountAuras)
    {
        for (std::uint8_t index = 0; index < MAX_SPELL_EFFECTS; ++index)
        {
            AuraEffect* effect = mountAura->GetEffect(index);
            if (!effect || effect->GetAmount() <= ExpertMountedFlightSpeedPercent)
                continue;
            AuraType auraType = effect->GetAuraType();
            if (auraType == SPELL_AURA_MOD_INCREASE_MOUNTED_FLIGHT_SPEED ||
                auraType == SPELL_AURA_MOD_MOUNTED_FLIGHT_SPEED_ALWAYS ||
                auraType == SPELL_AURA_MOD_FLIGHT_SPEED_MOUNTED_NOT_STACKING)
                effect->ChangeAmount(ExpertMountedFlightSpeedPercent);
        }
    }
}
}

class MountCollectionService::Impl
{
public:
    void OnPlayerLogin(Player* player)
    {
        if (!player || !player->GetSession())
            return;
        std::scoped_lock lock(_mutex);
        AccountId account = PlayerAccount(player);
        MountAccountState& state = _accounts[account];
        state.LoginCharacterGuid = player->GetGUID().GetCounter();
        for (MountCollectionDefinition const& definition : GetMountCatalog().Collections())
            for (std::uint32_t spellId : definition.UnlockSpellIds)
                if (player->HasSpell(spellId))
                    state.CandidateSpells.insert(spellId);
    }

    void OnPlayerLearnSpell(Player* player, std::uint32_t spellId)
    {
        if (!player || !player->GetSession())
            return;
        MountCollectionDefinition const* definition = GetMountCatalog().FindByUnlockSpell(spellId);
        if (!definition)
            return;
        std::scoped_lock lock(_mutex);
        AccountId account = PlayerAccount(player);
        auto suppressed = _projectionSuppression.find(player->GetGUID().GetCounter());
        if (suppressed != _projectionSuppression.end() && suppressed->second.erase(spellId) != 0)
        {
            if (suppressed->second.empty())
                _projectionSuppression.erase(suppressed);
            LOG_DEBUG("module.solocollections.mount",
                "event=mount_action_projection_learn character={} spell={} result=suppressed",
                player->GetGUID().GetCounter(), spellId);
            return;
        }
        MountAccountState& state = _accounts[account];
        state.LoginCharacterGuid = player->GetGUID().GetCounter();
        QueueGrant(state, *definition, spellId, state.LoginCharacterGuid, CollectionSourceKind::Gameplay);
        LOG_INFO("module.solocollections.mount",
            "event=mount_spell_learned account={} character={} spell={} collection={}",
            account.Value(), state.LoginCharacterGuid, spellId, definition->Id.Value());
    }

    void ReconcileCharacterMountActions(Player* player)
    {
        if (!player || !player->GetSession())
            return;
        AccountId account = PlayerAccount(player);
        std::optional<AccountCacheSnapshot> snapshot = GetAccountCollectionCache().Snapshot(account);
        if (!snapshot || snapshot->State != AccountCacheLoadState::Ready)
            return;
        std::uint32_t guid = player->GetGUID().GetCounter();
        {
            std::scoped_lock lock(_mutex);
            auto found = _projectionRevision.find(guid);
            if (found != _projectionRevision.end() && found->second == snapshot->Revision)
                return;
        }

        std::vector<std::uint32_t> learn;
        for (MountCollectionDefinition const& definition : GetMountCatalog().Collections())
        {
            if (definition.Lifecycle != CatalogLifecycle::Active || !definition.JournalVisible ||
                !definition.Actionable || !definition.Draggable || definition.CanonicalActionSpellId == 0)
                continue;
            if (!GetAccountCollectionCache().IsOwned(account, { MountCollectionTypeId, definition.Id }))
                continue;
            if (!player->HasSpell(definition.CanonicalActionSpellId))
                learn.push_back(definition.CanonicalActionSpellId);
        }
        {
            std::scoped_lock lock(_mutex);
            _projectionRevision[guid] = snapshot->Revision;
            _projectionSuppression[guid].insert(learn.begin(), learn.end());
            if (learn.empty())
                _projectionSuppression.erase(guid);
        }
        for (std::uint32_t spellId : learn)
            player->learnSpell(spellId, false);
        if (!learn.empty())
            LOG_INFO("module.solocollections.mount",
                "event=mount_action_reconcile account={} character={} revision={} learned={} result=complete",
                account.Value(), guid, snapshot->Revision.Value(), learn.size());
    }

    void ReconcileNativeMountState(Player* player)
    {
        if (!player || !player->GetSession())
            return;
        std::uint32_t guid = player->GetGUID().GetCounter();
        SpellInfo const* activeSpell = nullptr;
        if (player->IsMounted())
        {
            for (MountCollectionDefinition const& definition : GetMountCatalog().Collections())
            {
                if (definition.Lifecycle != CatalogLifecycle::Active || !definition.JournalVisible ||
                    !definition.Actionable || !definition.Draggable || definition.CanonicalActionSpellId == 0 ||
                    !player->HasAura(definition.CanonicalActionSpellId))
                    continue;
                SpellInfo const* candidate = sSpellMgr->GetSpellInfo(definition.CanonicalActionSpellId);
                if (FindOwnedAction(player, candidate))
                {
                    activeSpell = candidate;
                    break;
                }
            }
        }
        if (!activeSpell)
        {
            for (AuraEffect* mountedEffect : player->GetAuraEffectsByType(SPELL_AURA_MOUNTED))
            {
                if (!mountedEffect || !mountedEffect->GetBase())
                    continue;
                SpellInfo const* candidate = mountedEffect->GetSpellInfo();
                if (FindOwnedAction(player, candidate))
                {
                    activeSpell = candidate;
                    break;
                }
            }
        }
        if (!activeSpell)
        {
            std::scoped_lock lock(_mutex);
            _activeNativeMountState.erase(guid);
            _pendingPreviousMountAuras.erase(guid);
            return;
        }
        std::uint8_t level = player->GetLevel();
        std::uint8_t band = level <= EarlyRidingMaximumLevel ? 1 :
            level < EarlyFlightMinimumLevel ? 2 : level < FastFlightMinimumLevel ? 3 : 4;
        std::uint64_t stateKey = static_cast<std::uint64_t>(activeSpell->Id) |
            (static_cast<std::uint64_t>(band) << 32) |
            (static_cast<std::uint64_t>(player->GetMapId() & 0xFFFFu) << 40) |
            (static_cast<std::uint64_t>(player->GetAreaId() & 0xFFFFu) << 56);
        {
            std::scoped_lock lock(_mutex);
            auto found = _activeNativeMountState.find(guid);
            if (found != _activeNativeMountState.end() && found->second == stateKey)
                return;
            _activeNativeMountState[guid] = stateKey;
        }
        FinalizeNativeMountCast(player, activeSpell);
    }

    void Update()
    {
        std::scoped_lock lock(_mutex);
        for (auto& [account, state] : _accounts)
        {
            std::optional<AccountCacheSnapshot> snapshot = GetAccountCollectionCache().Snapshot(account);
            if (!snapshot || snapshot->State != AccountCacheLoadState::Ready)
                continue;
            state.Generation = snapshot->Generation;

            if (state.Phase == MigrationPhase::AwaitingReady)
                BeginMigrationCheck(account, state);
            Advance(account, state);
        }
    }

    std::string ExecuteSummon(Player* player, CollectionId collectionId)
    {
        if (!player || !player->GetSession() || !collectionId.IsValid())
            return "INVALID_REQUEST";
        AccountId account = PlayerAccount(player);
        std::optional<AccountCacheSnapshot> snapshot = GetAccountCollectionCache().Snapshot(account);
        if (!snapshot || snapshot->State == AccountCacheLoadState::Loading)
            return "LOADING";
        if (snapshot->State == AccountCacheLoadState::Failed)
            return "DB_UNAVAILABLE";

        MountCollectionDefinition const* definition = GetMountCatalog().Find(collectionId);
        if (!definition)
            return "INVALID_REQUEST";
        if (definition->Lifecycle == CatalogLifecycle::Tombstone)
            return "INVALID_REQUEST";
        if (!CatalogLifecycleAllowsAction(definition->Lifecycle))
            return "UNSUPPORTED";
        CollectionKey key { MountCollectionTypeId, collectionId };
        if (!GetAccountCollectionCache().IsOwned(account, key))
            return "NOT_OWNED";

        IdentityRegistry const& identities = GetIdentityRegistry();
        if (!identities.ResolveClass(player->getClass()).IsKnown() ||
            !identities.ResolveRace(player->getRace()).IsKnown())
            return "UNKNOWN_IDENTITY";
        if (!player->IsAlive())
            return "DEAD";
        if (player->IsInCombat())
            return "IN_COMBAT";
        if (player->GetVehicle())
            return "IN_VEHICLE";
        if (player->IsInFlight())
            return "ON_TAXI";
        if (player->InBattleground())
            return "BATTLEGROUND_RESTRICTED";
        if (!IsMountableHumanoidForm(player->GetShapeshiftForm()))
            return "SHAPESHIFT_RESTRICTED";
        if (!player->IsOutdoors())
            return "INDOORS";

        std::uint32_t raceMask = player->getRaceMask();
        std::uint32_t classMask = player->getClassMask();
        auto maskMatches = [](std::vector<std::uint32_t> const& masks, std::uint32_t value)
        {
            return masks.empty() || std::any_of(masks.begin(), masks.end(), [value](std::uint32_t mask)
            {
                return mask == 0 || (mask & value) != 0;
            });
        };
        bool raceCompatible = false;
        bool classCompatible = false;
        bool skillCompatible = false;
        bool flightRejected = false;
        bool locationRejected = false;
        MountActionVariant const* selected = nullptr;
        bool earlyRiding = player->GetLevel() <= EarlyRidingMaximumLevel;
        std::uint32_t ridingSkill = player->GetSkillValue(SKILL_RIDING);
        if (earlyRiding && ridingSkill < ApprenticeRidingSkill)
        {
            player->SetSkill(SKILL_RIDING, 1, ApprenticeRidingSkill, ApprenticeRidingSkill);
            ridingSkill = ApprenticeRidingSkill;
        }
        else if (player->GetLevel() >= FastFlightMinimumLevel && ridingSkill < ArtisanRidingSkill)
        {
            player->SetSkill(SKILL_RIDING, 4, ArtisanRidingSkill, ArtisanRidingSkill);
            ridingSkill = ArtisanRidingSkill;
        }
        else if (player->GetLevel() >= EarlyFlightMinimumLevel && ridingSkill < ExpertRidingSkill)
        {
            player->SetSkill(SKILL_RIDING, 3, ExpertRidingSkill, ExpertRidingSkill);
            ridingSkill = ExpertRidingSkill;
        }
        bool earlyFlightScaling = player->GetLevel() >= EarlyFlightMinimumLevel && ridingSkill < ArtisanRidingSkill;
        std::uint32_t effectiveRidingSkill = ridingSkill;
        if (earlyRiding)
            effectiveRidingSkill = std::max(effectiveRidingSkill, std::uint32_t { ApprenticeRidingSkill });
        else if (player->GetLevel() >= EarlyFlightMinimumLevel)
            effectiveRidingSkill = std::max(effectiveRidingSkill, std::uint32_t { ExpertRidingSkill });
        bool selectedWithinRidingSkill = false;
        for (MountActionVariant const& variant : definition->ActionVariants)
        {
            if (!maskMatches(variant.RaceMasks, raceMask))
                continue;
            raceCompatible = true;
            if (!maskMatches(variant.ClassMasks, classMask))
                continue;
            classCompatible = true;
            bool withinRidingSkill = effectiveRidingSkill >= variant.MinimumRidingSkill;
            if (!earlyRiding && !withinRidingSkill && !(earlyFlightScaling && variant.IsFlying))
                continue;
            skillCompatible = true;
            SpellInfo const* spellInfo = sSpellMgr->GetSpellInfo(variant.SpellId);
            if (!spellInfo)
                continue;
            SpellCastResult location = spellInfo->CheckLocation(
                player->GetMapId(), player->GetZoneId(), player->GetAreaId(), player, true);
            if (location != SPELL_CAST_OK)
            {
                flightRejected = flightRejected || variant.IsFlying;
                locationRejected = locationRejected || !variant.IsFlying;
                continue;
            }
            if (!selected || (withinRidingSkill && !selectedWithinRidingSkill) ||
                (withinRidingSkill == selectedWithinRidingSkill &&
                    ((earlyRiding || !withinRidingSkill) ?
                        variant.MinimumRidingSkill < selected->MinimumRidingSkill :
                        (variant.MinimumRidingSkill > selected->MinimumRidingSkill ||
                            (variant.MinimumRidingSkill == selected->MinimumRidingSkill && variant.IsFlying && !selected->IsFlying)))))
            {
                selected = &variant;
                selectedWithinRidingSkill = withinRidingSkill;
            }
        }
        if (!raceCompatible)
            return "RACE_RESTRICTED";
        if (!classCompatible)
            return "CLASS_RESTRICTED";
        if (!skillCompatible)
            return "SKILL_REQUIRED";
        if (!selected)
            return flightRejected && !locationRejected ? "FLYING_NOT_ALLOWED" : "MAP_RESTRICTED";

        SpellInfo const* spellInfo = sSpellMgr->GetSpellInfo(selected->SpellId);
        if (!spellInfo)
            return "CAST_FAILED";
        // Collection summons bypass the normal mounted cast restriction, so explicitly
        // remove the previous mount first instead of allowing its aura to remain stacked.
        player->Dismount();
        player->RemoveAurasByType(SPELL_AURA_MOUNTED);
        TriggerCastFlags castFlags = TriggerCastFlags(
            TRIGGERED_IGNORE_CASTER_MOUNTED_OR_ON_VEHICLE | TRIGGERED_IGNORE_SHAPESHIFT);
        SpellCastResult castResult = player->CastSpell(player, spellInfo, castFlags);
        if (castResult != SPELL_CAST_OK)
            return "CAST_FAILED";
        if (earlyRiding)
        {
            if (player->HasIncreaseMountedFlightSpeedAura() || player->HasFlyAura())
            {
                player->RemoveAurasByType(SPELL_AURA_MOUNTED);
                return "FLYING_NOT_ALLOWED";
            }
            CapMountedGroundSpeed(player, ApprenticeMountedSpeedPercent);
        }
        else if (earlyFlightScaling && player->HasIncreaseMountedFlightSpeedAura())
            CapMountedFlightSpeedAtExpert(player);
        LOG_INFO("module.solocollections.mount",
            "event=mount_summon result=accepted account={} character={} collection={} spell={}",
            account.Value(), player->GetGUID().GetCounter(), collectionId.Value(), selected->SpellId);
        return "ACCEPTED";
    }

    std::string ExecuteRandomSummon(Player* player)
    {
        if (!player || !player->GetSession())
            return "INVALID_REQUEST";
        if (player->IsMounted())
        {
            player->Dismount();
            player->RemoveAurasByType(SPELL_AURA_MOUNTED);
            return "DISMISSED";
        }

        AccountId account = PlayerAccount(player);
        std::optional<AccountCacheSnapshot> snapshot = GetAccountCollectionCache().Snapshot(account);
        if (!snapshot || snapshot->State == AccountCacheLoadState::Loading)
            return "LOADING";
        if (snapshot->State == AccountCacheLoadState::Failed)
            return "DB_UNAVAILABLE";

        std::vector<CollectionId> all;
        std::vector<CollectionId> favorites;
        for (MountCollectionDefinition const& definition : GetMountCatalog().Collections())
        {
            if (definition.Lifecycle != CatalogLifecycle::Active || !definition.JournalVisible ||
                !definition.Actionable || !definition.RandomEligible)
                continue;
            CollectionKey mountKey { MountCollectionTypeId, definition.Id };
            if (!GetAccountCollectionCache().IsOwned(account, mountKey))
                continue;
            all.push_back(definition.Id);
            CollectionKey favoriteKey { MountFavoriteCollectionTypeId, definition.Id };
            if (GetAccountCollectionCache().IsOwned(account, favoriteKey))
                favorites.push_back(definition.Id);
        }
        if (all.empty())
            return "NO_MOUNTS";

        CollectionId previous;
        {
            std::scoped_lock lock(_mutex);
            previous = _accounts[account].LastRandomCollection;
        }
        auto tryPool = [&](std::vector<CollectionId> pool, bool favoritePool) -> std::string
        {
            if (pool.size() > 1 && previous.IsValid())
                pool.erase(std::remove(pool.begin(), pool.end(), previous), pool.end());
            while (!pool.empty())
            {
                std::size_t index = urand(0, static_cast<std::uint32_t>(pool.size() - 1));
                CollectionId selected = pool[index];
                pool.erase(pool.begin() + index);
                std::string result = ExecuteSummon(player, selected);
                if (result == "ACCEPTED")
                {
                    MountCollectionDefinition const* definition = GetMountCatalog().Find(selected);
                    {
                        std::scoped_lock lock(_mutex);
                        _accounts[account].LastRandomCollection = selected;
                    }
                    LOG_INFO("module.solocollections.mount",
                        "event=mount_random account={} character={} pool_size={} favorite_pool={} collection={} spell={} capability={} result=accepted",
                        account.Value(), player->GetGUID().GetCounter(), all.size(), favoritePool ? favorites.size() : 0,
                        selected.Value(), definition ? definition->CanonicalActionSpellId : 0,
                        definition ? static_cast<unsigned>(definition->Capability) : 0);
                    return result;
                }
                if (result != "MAP_RESTRICTED" && result != "FLYING_NOT_ALLOWED" &&
                    result != "RACE_RESTRICTED" && result != "CLASS_RESTRICTED" &&
                    result != "SKILL_REQUIRED" && result != "UNSUPPORTED")
                    return result;
            }
            return "NO_USABLE_MOUNTS";
        };

        if (!favorites.empty())
        {
            std::string result = tryPool(favorites, true);
            if (result != "NO_USABLE_MOUNTS")
                return result;
        }
        return tryPool(all, false);
    }

    bool CanUseFlyingMountAsGround(Player* player, SpellInfo const* spellInfo,
        std::uint32_t /*mapId*/, std::uint32_t /*zoneId*/, std::uint32_t /*areaId*/)
    {
        MountCollectionDefinition const* definition = FindOwnedAction(player, spellInfo);
        return definition && definition->Capability == MountCapability::Flying;
    }

    bool CanReplaceMount(Player* player, SpellInfo const* spellInfo)
    {
        MountCollectionDefinition const* definition = FindOwnedAction(player, spellInfo);
        if (!definition)
            return false;

        std::set<std::uint32_t> previous;
        for (AuraEffect* mountedEffect : player->GetAuraEffectsByType(SPELL_AURA_MOUNTED))
            if (mountedEffect && mountedEffect->GetBase())
                previous.insert(mountedEffect->GetBase()->GetId());
        std::scoped_lock lock(_mutex);
        _pendingPreviousMountAuras[player->GetGUID().GetCounter()] = std::move(previous);
        return true;
    }

    void FinalizeNativeMountCast(Player* player, SpellInfo const* spellInfo)
    {
        MountCollectionDefinition const* definition = FindOwnedAction(player, spellInfo);
        if (!definition)
            return;

        std::set<std::uint32_t> previous;
        {
            std::scoped_lock lock(_mutex);
            auto found = _pendingPreviousMountAuras.find(player->GetGUID().GetCounter());
            if (found != _pendingPreviousMountAuras.end())
            {
                previous = std::move(found->second);
                _pendingPreviousMountAuras.erase(found);
            }
        }
        for (std::uint32_t auraSpellId : previous)
            if (auraSpellId != spellInfo->Id)
                player->RemoveAurasDueToSpell(auraSpellId);

        std::uint8_t level = player->GetLevel();
        std::uint32_t ridingSkill = player->GetSkillValue(SKILL_RIDING);
        if (level <= EarlyRidingMaximumLevel && ridingSkill < ApprenticeRidingSkill)
            player->SetSkill(SKILL_RIDING, 1, ApprenticeRidingSkill, ApprenticeRidingSkill);
        else if (level >= FastFlightMinimumLevel && ridingSkill < ArtisanRidingSkill)
            player->SetSkill(SKILL_RIDING, 4, ArtisanRidingSkill, ArtisanRidingSkill);
        else if (level >= EarlyFlightMinimumLevel && ridingSkill < ExpertRidingSkill)
            player->SetSkill(SKILL_RIDING, 3, ExpertRidingSkill, ExpertRidingSkill);

        bool flightAllowed = definition->Capability == MountCapability::Flying &&
            IsFlightAllowed(player, spellInfo);
        if (!flightAllowed)
        {
            player->SetCanFly(false);
            CapMountedGroundSpeed(player, level <= EarlyRidingMaximumLevel ?
                ApprenticeMountedSpeedPercent : JourneymanMountedSpeedPercent);
        }
        else if (level < FastFlightMinimumLevel)
            CapMountedFlightSpeedAtExpert(player);

        char const* band = level <= EarlyRidingMaximumLevel ? "1-19" :
            level < EarlyFlightMinimumLevel ? "20-44" :
            level < FastFlightMinimumLevel ? "45-59" : "60+";
        LOG_INFO("module.solocollections.mount",
            "event=mount_native_resolve account={} character={} collection={} spell={} level={} band={} flight={} result=accepted",
            PlayerAccount(player).Value(), player->GetGUID().GetCounter(), definition->Id.Value(), spellInfo->Id,
            static_cast<unsigned>(level), band, flightAllowed ? 1 : 0);
    }

private:
    MountCollectionDefinition const* FindOwnedAction(Player* player, SpellInfo const* spellInfo) const
    {
        if (!player || !player->GetSession() || !spellInfo)
            return nullptr;
        MountCollectionDefinition const* definition = GetMountCatalog().FindByActionSpell(spellInfo->Id);
        if (!definition || definition->Lifecycle != CatalogLifecycle::Active ||
            !definition->JournalVisible || !definition->Actionable || !definition->Draggable)
            return nullptr;
        AccountId account = PlayerAccount(player);
        std::optional<AccountCacheSnapshot> snapshot = GetAccountCollectionCache().Snapshot(account);
        if (!snapshot || snapshot->State != AccountCacheLoadState::Ready ||
            !GetAccountCollectionCache().IsOwned(account, { MountCollectionTypeId, definition->Id }))
            return nullptr;
        return definition;
    }

    static bool IsFlightAllowed(Player* player, SpellInfo const* spellInfo)
    {
        if (!player || player->GetLevel() < EarlyFlightMinimumLevel)
            return false;
        AreaTableEntry const* area = sAreaTableStore.LookupEntry(player->GetAreaId());
        if (!area)
            area = sAreaTableStore.LookupEntry(player->GetZoneId());
        if (!area || (area->flags & AREA_FLAG_NO_FLY_ZONE) != 0)
            return false;
        std::uint32_t virtualMap = GetVirtualMapForMapAndZone(player->GetMapId(), player->GetZoneId());
        if (virtualMap == MAP_EASTERN_KINGDOMS || virtualMap == MAP_KALIMDOR)
            return true;
        return area->IsFlyable() && player->canFlyInZone(player->GetMapId(), player->GetZoneId(), spellInfo);
    }

    static void QueueGrant(MountAccountState& state, MountCollectionDefinition const& definition,
        std::uint32_t spellId, std::uint32_t characterGuid, CollectionSourceKind sourceKind)
    {
        if (!state.QueuedCollections.insert(definition.Id).second)
            return;
        state.Pending.push_back({ definition.Id, spellId, characterGuid, sourceKind, false });
    }

    void BeginMigrationCheck(AccountId account, MountAccountState& state)
    {
        state.Phase = MigrationPhase::CheckingMarker;
        bool started = GetAccountCollectionStore().CheckMigrationMarker(
            { account, MountSpellMigrationId, MountSpellMigrationVersion },
            [this, account](bool succeeded, bool completed, std::vector<std::uint32_t> databaseSpells)
            {
                std::scoped_lock lock(_mutex);
                auto found = _accounts.find(account);
                if (found == _accounts.end())
                    return;
                MountAccountState& current = found->second;
                if (!succeeded)
                {
                    current.Phase = MigrationPhase::Failed;
                    LOG_ERROR("module.solocollections.mount",
                        "event=mount_migration_check result=failed account={}", account.Value());
                    return;
                }
                if (completed)
                {
                    current.Phase = MigrationPhase::Complete;
                    current.CandidateSpells.clear();
                    LOG_DEBUG("module.solocollections.mount",
                        "event=mount_migration_check result=already_complete account={}", account.Value());
                    return;
                }
                current.CandidateSpells.insert(databaseSpells.begin(), databaseSpells.end());
                for (std::uint32_t spellId : current.CandidateSpells)
                    if (MountCollectionDefinition const* definition = GetMountCatalog().FindByUnlockSpell(spellId))
                        QueueGrant(current, *definition, spellId, current.LoginCharacterGuid, CollectionSourceKind::Migration);
                current.CandidateSpells.clear();
                current.Phase = MigrationPhase::Importing;
                LOG_INFO("module.solocollections.mount",
                    "event=mount_migration_check result=import account={} queued={}",
                    account.Value(), current.Pending.size());
            });
        if (!started)
            state.Phase = MigrationPhase::AwaitingReady;
    }

    void Advance(AccountId account, MountAccountState& state)
    {
        AccountCollectionStore& store = GetAccountCollectionStore();
        if (store.HasPendingMutation(account))
            return;

        while (!state.Pending.empty())
        {
            PendingMountGrant& grant = state.Pending.front();
            CollectionKey key { MountCollectionTypeId, grant.Collection };
            if (GetAccountCollectionCache().IsOwned(account, key))
            {
                if (grant.Started && grant.SourceKind == CollectionSourceKind::Migration)
                    ++state.ImportedCount;
                state.QueuedCollections.erase(grant.Collection);
                state.Pending.pop_front();
                continue;
            }

            AccountCollectionMutation mutation;
            mutation.Account = account;
            mutation.Generation = state.Generation;
            mutation.Key = key;
            mutation.Kind = CollectionMutationKind::Grant;
            mutation.SourceKind = grant.SourceKind;
            mutation.SourceId = grant.SpellId;
            mutation.CharacterGuid = grant.CharacterGuid;
            MutationStartResult result = store.BeginMutation(mutation);
            if (result.Accepted)
            {
                grant.Started = true;
                return;
            }
            if (result.Reason == CollectionReasonCode::PendingOperation || result.Reason == CollectionReasonCode::NotReady)
                return;
            if (result.Reason == CollectionReasonCode::AlreadyOwned)
            {
                state.QueuedCollections.erase(grant.Collection);
                state.Pending.pop_front();
                continue;
            }
            if (grant.SourceKind == CollectionSourceKind::Migration)
                ++state.RejectedCount;
            LOG_ERROR("module.solocollections.mount",
                "event=mount_unlock result=rejected account={} spell={} collection={} reason={}",
                account.Value(), grant.SpellId, grant.Collection.Value(), ToStableReasonCode(result.Reason));
            state.QueuedCollections.erase(grant.Collection);
            state.Pending.pop_front();
        }

        if (state.Phase != MigrationPhase::Importing)
            return;
        std::optional<AccountCacheSnapshot> snapshot = GetAccountCollectionCache().Snapshot(account);
        if (!snapshot || snapshot->State != AccountCacheLoadState::Ready)
            return;
        state.Phase = MigrationPhase::WritingMarker;
        bool started = store.CompleteMigrationMarker(
            { { account, MountSpellMigrationId, MountSpellMigrationVersion }, snapshot->Revision,
                state.ImportedCount, state.RejectedCount },
            [this, account](bool committed)
            {
                std::scoped_lock lock(_mutex);
                auto found = _accounts.find(account);
                if (found == _accounts.end())
                    return;
                found->second.Phase = committed ? MigrationPhase::Complete : MigrationPhase::Failed;
                LOG_INFO("module.solocollections.mount",
                    "event=mount_migration_marker result={} account={} imported={} rejected={}",
                    committed ? "complete" : "failed", account.Value(),
                    found->second.ImportedCount, found->second.RejectedCount);
            });
        if (!started)
            state.Phase = MigrationPhase::Importing;
    }

    std::map<AccountId, MountAccountState> _accounts;
    std::map<std::uint32_t, CollectionRevision> _projectionRevision;
    std::map<std::uint32_t, std::set<std::uint32_t>> _projectionSuppression;
    std::map<std::uint32_t, std::set<std::uint32_t>> _pendingPreviousMountAuras;
    std::map<std::uint32_t, std::uint64_t> _activeNativeMountState;
    std::mutex _mutex;
};

MountCollectionService::MountCollectionService() : _impl(std::make_unique<Impl>()) { }
MountCollectionService::~MountCollectionService() = default;

void MountCollectionService::OnPlayerLogin(Player* player)
{
    _impl->OnPlayerLogin(player);
}

void MountCollectionService::OnPlayerLearnSpell(Player* player, std::uint32_t spellId)
{
    _impl->OnPlayerLearnSpell(player, spellId);
}

void MountCollectionService::ReconcileCharacterMountActions(Player* player)
{
    _impl->ReconcileCharacterMountActions(player);
}

void MountCollectionService::ReconcileNativeMountState(Player* player)
{
    _impl->ReconcileNativeMountState(player);
}

void MountCollectionService::Update()
{
    _impl->Update();
}

std::string MountCollectionService::ExecuteSummon(Player* player, CollectionId collectionId)
{
    return _impl->ExecuteSummon(player, collectionId);
}

std::string MountCollectionService::ExecuteRandomSummon(Player* player)
{
    return _impl->ExecuteRandomSummon(player);
}

bool MountCollectionService::CanUseFlyingMountAsGround(Player* player, SpellInfo const* spellInfo,
    std::uint32_t mapId, std::uint32_t zoneId, std::uint32_t areaId)
{
    return _impl->CanUseFlyingMountAsGround(player, spellInfo, mapId, zoneId, areaId);
}

bool MountCollectionService::CanReplaceMount(Player* player, SpellInfo const* spellInfo)
{
    return _impl->CanReplaceMount(player, spellInfo);
}

void MountCollectionService::FinalizeNativeMountCast(Player* player, SpellInfo const* spellInfo)
{
    _impl->FinalizeNativeMountCast(player, spellInfo);
}

MountCollectionService& GetMountCollectionService()
{
    static MountCollectionService service;
    return service;
}
}
