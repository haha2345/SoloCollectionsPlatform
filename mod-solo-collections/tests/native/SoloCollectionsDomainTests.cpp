#include "SoloCollectionsAccountCache.h"
#include "SoloCollectionsCompanionCatalog.h"
#include "SoloCollectionsEligibility.h"
#include "SoloCollectionsIdentity.h"
#include "SoloCollectionsMountCatalog.h"
#include "SoloCollectionsProvider.h"
#include "SoloCollectionsShadowComparison.h"
#include "SoloCollectionsToyCatalog.h"

#include <cstdlib>
#include <iostream>
#include <memory>
#include <set>
#include <stdexcept>
#include <string>
#include <thread>
#include <utility>
#include <vector>

namespace SC = SoloCollections;

namespace
{
void Require(bool condition, std::string const& message)
{
    if (!condition)
        throw std::runtime_error(message);
}

class TestProvider final : public SC::CollectionProvider
{
public:
    TestProvider(std::uint16_t typeId, std::string typeKey,
        std::vector<std::uint16_t> dependencies = {}, bool readOnlyOnMissing = false,
        SC::CollectionStorageMode storage = SC::CollectionStorageMode::Persisted)
    {
        _descriptor.TypeId = SC::CollectionTypeId(typeId);
        _descriptor.TypeKey = std::move(typeKey);
        _descriptor.ReadOnlyWhenDependencyMissing = readOnlyOnMissing;
        _descriptor.Storage = storage;
        for (std::uint16_t dependency : dependencies)
            _descriptor.Dependencies.emplace_back(dependency);
    }

    SC::CollectionProviderDescriptor const& Descriptor() const override
    {
        return _descriptor;
    }

    SC::CollectionResult Evaluate(SC::CollectionId /*collectionId*/) const override
    {
        SC::CollectionResult result;
        result.Reason = SC::CollectionReasonCode::NotOwned;
        return result;
    }

private:
    SC::CollectionProviderDescriptor _descriptor;
};

class ExternalTestProvider final : public SC::CollectionProvider
{
public:
    ExternalTestProvider()
    {
        _descriptor.TypeId = SC::CollectionTypeId(std::uint16_t { 30 });
        _descriptor.TypeKey = "synthetic_external";
        _descriptor.Storage = SC::CollectionStorageMode::External;
    }

    SC::CollectionProviderDescriptor const& Descriptor() const override { return _descriptor; }

    SC::CollectionResult Evaluate(SC::CollectionId collectionId) const override
    {
        SC::CollectionResult result;
        bool known = collectionId == SC::CollectionId(300001);
        result.Availability.CatalogKnown = known;
        result.Availability.AssetReady = known;
        result.Reason = known ? SC::CollectionReasonCode::NotOwned :
            SC::CollectionReasonCode::UnknownCollection;
        return result;
    }

    std::optional<bool> IsOwned(SC::AccountId accountId, SC::CollectionId collectionId) const override
    {
        return accountId == SC::AccountId(77) && collectionId == SC::CollectionId(300001);
    }

    std::optional<std::vector<SC::CollectionId>> OwnedByAccount(SC::AccountId accountId) const override
    {
        return accountId == SC::AccountId(77) ?
            std::vector<SC::CollectionId> { SC::CollectionId(300001) } :
            std::vector<SC::CollectionId> {};
    }

private:
    SC::CollectionProviderDescriptor _descriptor;
};

void TestStableTypes()
{
    static_assert(sizeof(SC::CollectionTypeId::ValueType) == 2);
    static_assert(sizeof(SC::CollectionId::ValueType) == 4);
    static_assert(sizeof(SC::CollectionRevision::ValueType) == 8);
    static_assert(SC::ToStableReasonCode(SC::CollectionReasonCode::NotOwned) == 0x0400);

    auto parsed = SC::ParseStableReasonCode(0x0400);
    Require(parsed && *parsed == SC::CollectionReasonCode::NotOwned, "stable reason parse failed");
    Require(!SC::ParseStableReasonCode(0x1234), "unknown reason value was accepted");

    SC::StableIdReservation<SC::CollectionTypeId> tombstone {
        SC::CollectionTypeId(std::uint16_t { 7 }), SC::StableIdLifecycle::Tombstone
    };
    Require(tombstone.IsTombstone() && !tombstone.CanBind(), "tombstone became bindable");
}

void TestDuplicateAndTombstoneFailures()
{
    SC::CollectionProviderRegistry duplicates;
    Require(duplicates.Register(std::make_unique<TestProvider>(std::uint16_t { 1 }, "one")).Accepted,
        "initial provider registration failed");
    auto duplicate = duplicates.Register(std::make_unique<TestProvider>(std::uint16_t { 1 }, "other"));
    Require(!duplicate.Accepted && duplicate.Reason == SC::CollectionReasonCode::DuplicateProvider,
        "duplicate type ID was not fatal");
    Require(!duplicates.Finalize().Success, "registry finalized after duplicate registration");

    SC::CollectionProviderRegistry tombstones;
    Require(tombstones.ReserveTombstone(SC::CollectionTypeId(std::uint16_t { 9 }), "retired").Accepted,
        "tombstone reservation failed");
    auto reused = tombstones.Register(std::make_unique<TestProvider>(std::uint16_t { 9 }, "replacement"));
    Require(!reused.Accepted && reused.Reason == SC::CollectionReasonCode::Tombstoned,
        "tombstoned type ID was reused");
}

void TestCyclesAndMissingDependencies()
{
    SC::CollectionProviderRegistry cycle;
    Require(cycle.Register(std::make_unique<TestProvider>(std::uint16_t { 1 }, "one", std::vector<std::uint16_t> { 2 })).Accepted,
        "cycle provider one registration failed");
    Require(cycle.Register(std::make_unique<TestProvider>(std::uint16_t { 2 }, "two", std::vector<std::uint16_t> { 1 })).Accepted,
        "cycle provider two registration failed");
    auto cycleResult = cycle.Finalize();
    Require(!cycleResult.Success && cycleResult.Reason == SC::CollectionReasonCode::DependencyCycle,
        "dependency cycle was not fatal");

    SC::CollectionProviderRegistry missing;
    Require(missing.Register(std::make_unique<TestProvider>(std::uint16_t { 10 }, "readonly", std::vector<std::uint16_t> { 90 }, true)).Accepted,
        "read-only provider registration failed");
    Require(missing.Register(std::make_unique<TestProvider>(std::uint16_t { 11 }, "disabled", std::vector<std::uint16_t> { 91 }, false)).Accepted,
        "disabled provider registration failed");
    Require(missing.Finalize().Success, "missing dependency should degrade, not fail startup");
    Require(missing.State(SC::CollectionTypeId(std::uint16_t { 10 }))->Mode == SC::CollectionProviderMode::ReadOnly,
        "missing dependency did not produce read-only mode");
    Require(missing.State(SC::CollectionTypeId(std::uint16_t { 11 }))->Mode == SC::CollectionProviderMode::Disabled,
        "missing dependency did not produce disabled mode");
}

std::vector<std::uint16_t> FinalizedOrder(bool reverseRegistration)
{
    SC::CollectionProviderRegistry registry;
    auto base = std::make_unique<TestProvider>(std::uint16_t { 2 }, "base");
    auto dependent = std::make_unique<TestProvider>(std::uint16_t { 3 }, "dependent", std::vector<std::uint16_t> { 2 });
    if (reverseRegistration)
    {
        Require(registry.Register(std::move(dependent)).Accepted, "dependent registration failed");
        Require(registry.Register(std::move(base)).Accepted, "base registration failed");
    }
    else
    {
        Require(registry.Register(std::move(base)).Accepted, "base registration failed");
        Require(registry.Register(std::move(dependent)).Accepted, "dependent registration failed");
    }
    Require(registry.Finalize().Success, "valid registry did not finalize");

    std::vector<std::uint16_t> order;
    for (SC::CollectionTypeId typeId : registry.TopologicalOrder())
        order.push_back(typeId.Value());
    return order;
}

void TestRegistrationOrderIndependence()
{
    std::vector<std::uint16_t> expected { 2, 3 };
    Require(FinalizedOrder(false) == expected, "forward registration produced unstable order");
    Require(FinalizedOrder(true) == expected, "reverse registration produced unstable order");
}

SC::AccountId Account(std::uint32_t value)
{
    return SC::AccountId(value);
}

SC::AccountSessionId Session(std::uint64_t value)
{
    return SC::AccountSessionId(value);
}

SC::CollectionKey Key(std::uint16_t typeId, std::uint32_t collectionId)
{
    return { SC::CollectionTypeId(typeId), SC::CollectionId(collectionId) };
}

void TestSyntheticProviderStorageContracts()
{
    SC::CollectionProviderRegistry registry;
    Require(registry.Register(std::make_unique<ExternalTestProvider>()).Accepted,
        "external synthetic provider registration failed");
    Require(registry.Register(std::make_unique<TestProvider>(
        std::uint16_t { 31 }, "synthetic_persisted")).Accepted,
        "persisted synthetic provider registration failed");
    Require(registry.Register(std::make_unique<TestProvider>(
        std::uint16_t { 32 }, "synthetic_disabled", std::vector<std::uint16_t> { 99 })).Accepted,
        "disabled synthetic provider registration failed");
    Require(registry.Register(std::make_unique<TestProvider>(
        std::uint16_t { 33 }, "synthetic_readonly", std::vector<std::uint16_t> { 98 }, true,
        SC::CollectionStorageMode::External)).Accepted,
        "read-only synthetic provider registration failed");
    Require(registry.Finalize().Success, "synthetic storage registry did not finalize");
    Require(registry.State(SC::CollectionTypeId(30))->Mode == SC::CollectionProviderMode::Enabled &&
        registry.State(SC::CollectionTypeId(31))->Mode == SC::CollectionProviderMode::Enabled,
        "healthy providers were affected by another provider dependency failure");
    Require(registry.State(SC::CollectionTypeId(32))->Mode == SC::CollectionProviderMode::Disabled &&
        registry.State(SC::CollectionTypeId(33))->Mode == SC::CollectionProviderMode::ReadOnly,
        "missing dependencies did not degrade providers independently");

    SC::CollectionProvider const* external = registry.Find(SC::CollectionTypeId(30));
    Require(external && external->Descriptor().Storage == SC::CollectionStorageMode::External,
        "external provider lost its explicit storage mode");
    SC::CollectionResult visible = external->Evaluate(SC::CollectionId(300001));
    Require(visible.Availability.CatalogKnown && visible.Availability.AssetReady &&
        external->IsOwned(Account(77), SC::CollectionId(300001)).value_or(false),
        "external provider could not display its authoritative state");
    SC::AccountCollectionCache emptyGenericTable;
    Require(!emptyGenericTable.IsOwned(Account(77), Key(30, 300001)),
        "external provider unexpectedly required a generic unlock row");
    auto externalOwned = external->OwnedByAccount(Account(77));
    Require(externalOwned && *externalOwned ==
        std::vector<SC::CollectionId> { SC::CollectionId(300001) },
        "external provider account projection was not readable");

    SC::CollectionProvider const* persisted = registry.Find(SC::CollectionTypeId(31));
    Require(persisted && persisted->Descriptor().Storage == SC::CollectionStorageMode::Persisted,
        "persisted provider lost the unified account storage mode");
    SC::AccountCollectionCache accountCollections;
    auto opened = accountCollections.OpenSession(Account(77), Session(770), 0);
    Require(accountCollections.CompleteLoad(
        Account(77), opened.Generation, {}, SC::CollectionRevision(10)),
        "persisted provider account fixture did not load");
    SC::CollectionDelta unlock {
        Key(31, 310001), SC::CollectionDeltaKind::Unlock, SC::CollectionRevision(11)
    };
    Require(accountCollections.QueueDelta(Account(77), unlock) == SC::DeltaQueueResult::Applied &&
        accountCollections.IsOwned(Account(77), unlock.Key) &&
        accountCollections.Snapshot(Account(77))->Revision == SC::CollectionRevision(11),
        "persisted provider did not reuse account ownership and revision state");
}

void TestTwoSessionsShareOneLoad()
{
    SC::AccountCollectionCache cache(100);
    auto first = cache.OpenSession(Account(1), Session(10), 0);
    auto second = cache.OpenSession(Account(1), Session(11), 0);

    Require(first.Accepted && first.ShouldStartLoad, "first account session did not start lazy load");
    Require(second.Accepted && !second.ShouldStartLoad, "second account session started a duplicate load");
    Require(first.Generation == second.Generation, "same-account sessions did not share generation");
    auto snapshot = cache.Snapshot(Account(1));
    Require(snapshot && snapshot->SessionCount == 2 && snapshot->State == SC::AccountCacheLoadState::Loading,
        "same-account session set was not retained");
}

void TestLogoutBeforeCallback()
{
    SC::AccountCollectionCache cache(100);
    auto opened = cache.OpenSession(Account(2), Session(20), 0);
    Require(cache.CloseSession(Account(2), Session(20), 10), "session logout was not recorded");
    auto waiting = cache.Snapshot(Account(2));
    Require(waiting && waiting->SessionCount == 0 && waiting->EvictionScheduled,
        "loading account was removed before its delayed eviction deadline");
    Require(cache.CompleteLoad(Account(2), opened.Generation, {}, SC::CollectionRevision(std::uint64_t { 1 })),
        "valid callback was rejected after the last session logged out");
    Require(cache.EvictExpired(109) == 0, "account cache was evicted before its deadline");
    Require(cache.EvictExpired(110) == 1 && !cache.Snapshot(Account(2)),
        "account cache was not evicted at its deadline");
}

void TestUnlockDuringLoad()
{
    SC::AccountCollectionCache cache(100);
    auto opened = cache.OpenSession(Account(3), Session(30), 0);
    SC::CollectionDelta unlock {
        Key(1, 500), SC::CollectionDeltaKind::Unlock, SC::CollectionRevision(std::uint64_t { 8 })
    };
    Require(cache.QueueDelta(Account(3), unlock) == SC::DeltaQueueResult::Deferred,
        "unlock during load was not deferred");
    Require(cache.CompleteLoad(Account(3), opened.Generation, {}, SC::CollectionRevision(std::uint64_t { 7 })),
        "loading account did not accept its snapshot");
    Require(cache.IsOwned(Account(3), unlock.Key), "pending unlock was lost when the snapshot completed");
    auto snapshot = cache.Snapshot(Account(3));
    Require(snapshot && snapshot->Revision.Value() == 8 && snapshot->PendingDeltaCount == 0,
        "pending unlock revision was not merged");
    Require(cache.DrainReadyDeltas(Account(3)).size() == 1,
        "merged unlock was not available for account-session broadcast");
}

void TestRelogAndDelayedEviction()
{
    SC::AccountCollectionCache cache(100);
    auto first = cache.OpenSession(Account(4), Session(40), 0);
    Require(cache.CompleteLoad(Account(4), first.Generation, {}, SC::CollectionRevision(std::uint64_t { 1 })),
        "initial account load failed");
    Require(cache.CloseSession(Account(4), Session(40), 10), "initial logout failed");

    auto quickRelog = cache.OpenSession(Account(4), Session(41), 50);
    Require(!quickRelog.ShouldStartLoad && quickRelog.Generation == first.Generation,
        "relog before delayed eviction started a redundant load");
    Require(cache.CloseSession(Account(4), Session(41), 60), "second logout failed");
    Require(cache.EvictExpired(160) == 1, "last-session cache did not expire after renewed delay");

    auto afterEviction = cache.OpenSession(Account(4), Session(42), 161);
    Require(afterEviction.ShouldStartLoad && afterEviction.Generation.Value() == first.Generation.Value() + 1,
        "relog after eviction did not start a new generation");
    Require(!cache.CompleteLoad(Account(4), first.Generation, {}, SC::CollectionRevision(std::uint64_t { 2 })),
        "stale callback crossed login generations");
}

void TestFailedLoadRetry()
{
    SC::AccountCollectionCache cache(100);
    auto opened = cache.OpenSession(Account(5), Session(50), 0);
    Require(cache.FailLoad(Account(5), opened.Generation), "load failure was not accepted");
    auto retry = cache.RetryFailed(Account(5));
    Require(retry && retry->Value() == opened.Generation.Value() + 1,
        "failed online account did not receive a new retry generation");
    Require(!cache.CompleteLoad(Account(5), opened.Generation, {}, SC::CollectionRevision(std::uint64_t { 1 })),
        "failed-generation callback was accepted after retry");
}

void TestExplicitCrossThreadLocking()
{
    SC::AccountCollectionCache cache(100);
    auto opened = cache.OpenSession(Account(6), Session(60), 0);
    Require(cache.CompleteLoad(Account(6), opened.Generation, { Key(10, 600) },
        SC::CollectionRevision(std::uint64_t { 1 })), "cross-thread fixture did not load");
    bool observed = false;
    std::thread worker([&cache, &observed]()
    {
        auto snapshot = cache.Snapshot(Account(6));
        observed = snapshot && snapshot->State == SC::AccountCacheLoadState::Ready &&
            cache.IsOwned(Account(6), Key(10, 600));
    });
    worker.join();
    Require(observed, "explicit cache lock did not permit a synchronized map-worker read");
}

void TestExplicitReloadAndDiagnostics()
{
    SC::AccountCollectionCache cache(100);
    auto opened = cache.OpenSession(Account(7), Session(70), 0);
    (void)cache.OpenSession(Account(7), Session(71), 0);
    auto loading = cache.Diagnostics();
    Require(loading.EntryCount == 1 && loading.LoadingCount == 1 && loading.SessionCount == 2,
        "cache diagnostics did not report shared loading sessions");
    Require(cache.CompleteLoad(Account(7), opened.Generation, { Key(1, 700) },
        SC::CollectionRevision(std::uint64_t { 4 })), "initial reload fixture did not become ready");

    auto generation = cache.BeginReload(Account(7));
    Require(generation && generation->Value() == opened.Generation.Value() + 1,
        "explicit reload did not advance generation");
    auto reloading = cache.Snapshot(Account(7));
    Require(reloading && reloading->State == SC::AccountCacheLoadState::Loading &&
        reloading->SessionCount == 2 && reloading->Revision.Value() == 0,
        "explicit reload did not atomically reset the online snapshot");
    Require(!cache.CompleteLoad(Account(7), opened.Generation, {}, SC::CollectionRevision(std::uint64_t { 5 })),
        "pre-reload callback crossed generation boundary");
}

SC::ClassIdentityDefinition SyntheticChronomancer(std::uint32_t runtimeClassId)
{
    return {
        SC::LogicalClassId(std::uint16_t { 501 }), "chronomancer", runtimeClassId,
        { "CHRONOMANCER" }, { "armor.cloth", "weapon.staff", "appearance.timeweave" },
        "class.caster", "class.chronomancer", 0, "CLOTH", { "STAFF" }, { "OFFHAND_ITEM" }
    };
}

SC::RaceIdentityDefinition SyntheticEarthen(std::uint32_t runtimeRaceId)
{
    return {
        SC::LogicalRaceId(std::uint16_t { 601 }), "earthen", runtimeRaceId,
        { "EARTHEN" }, { "appearance.stoneform" }, "ALLIANCE", "race.medium", "race.earthen", "",
        "appearance.dwarf", "synthetic-assets-v2", "model.earthen.stone",
    };
}

void TestExtensibleIdentityRegistry()
{
    SC::ClassIdentityDefinition syntheticClass = SyntheticChronomancer(101);
    SC::RaceIdentityDefinition syntheticRace = SyntheticEarthen(102);
    SC::IdentityRegistry registry({ syntheticClass }, { syntheticRace });
    Require(registry.IsValid(), "synthetic identity registry was rejected");

    auto byRuntime = registry.ResolveClass(101);
    auto byAlias = registry.ResolveClass("CHRONOMANCER");
    Require(byRuntime.IsKnown() && byAlias.IsKnown(), "synthetic class runtime/alias did not resolve");
    Require(byRuntime.Identity->LogicalId.Value() == 501 && byAlias.Identity == byRuntime.Identity,
        "synthetic class lost its logical identity");
    Require(registry.ResolveCameraProfile(registry.ResolveRace(102)) == "global",
        "race without a camera profile did not use global fallback");
    Require(!registry.ResolveClass(999).IsKnown() &&
        registry.ResolveClass(999).Code == SC::IdentityResolutionCode::UnknownIdentity,
        "unknown runtime class did not fail closed");

    syntheticClass.RuntimeClassId = 202;
    SC::IdentityRegistry remapped({ syntheticClass }, { syntheticRace });
    auto afterRuntimeChange = remapped.ResolveClass(202);
    Require(afterRuntimeChange.IsKnown() && afterRuntimeChange.Identity->LogicalId.Value() == 501,
        "runtime class change renumbered the logical class");
    Require(!remapped.ResolveClass(101).IsKnown(), "old runtime class ID stayed implicitly bound");

    SC::IdentityRegistry const& generated = SC::GetIdentityRegistry();
    Require(generated.IsValid() && generated.Classes().size() == 10 && generated.Races().size() == 10,
        "generated WotLK identity registry is invalid");
    Require(generated.ResolveClass("DEATHKNIGHT").IsKnown(), "generated class aliases were not loaded");
}

void TestSyntheticClassCapabilityAndCollectionContract()
{
    constexpr std::uint32_t InitialRuntimeClassId = 101;
    constexpr std::uint32_t RemappedRuntimeClassId = 202;
    SC::IdentityRegistry initial({ SyntheticChronomancer(InitialRuntimeClassId) }, {});
    Require(initial.IsValid(), "synthetic class registration failed");

    auto initialResolution = initial.ResolveClass(InitialRuntimeClassId);
    SC::EligibilityIdentityContext initialContext =
        SC::BuildClassEligibilityContext(initialResolution, 80);
    Require(initialContext.IdentityKnown && initialContext.LogicalClass == SC::LogicalClassId(501) &&
        initialContext.ClassKey == "chronomancer",
        "synthetic class capability profile lost its stable identity");

    auto policyFor = [](std::string key, std::string capability)
    {
        SC::EligibilityPolicyDefinition policy;
        policy.PolicyKey = std::move(key);
        policy.RequiredCapabilities = { std::move(capability) };
        policy.FactionPolicy = "ANY";
        return policy;
    };
    std::vector<SC::EligibilityPolicyDefinition> explicitPolicies {
        policyFor("synthetic.armor.cloth", "armor.cloth"),
        policyFor("synthetic.weapon.staff", "weapon.staff"),
        policyFor("synthetic.appearance.timeweave", "appearance.timeweave"),
    };
    for (SC::EligibilityPolicyDefinition const& policy : explicitPolicies)
    {
        SC::EligibilityRequest request;
        request.Policy = &policy;
        request.Identity = &initialContext;
        Require(SC::EvaluateEligibility(request).IsAllowed(),
            "synthetic class was denied an explicitly granted capability");
    }

    SC::EligibilityPolicyDefinition warriorOnly = policyFor("synthetic.armor.plate", "armor.plate");
    SC::EligibilityRequest denied;
    denied.Policy = &warriorOnly;
    denied.Identity = &initialContext;
    Require(SC::EvaluateEligibility(denied).Reason == SC::EligibilityReason::RequiredCapabilityMissing,
        "synthetic class inherited warrior capabilities");

    SC::EligibilityPolicyRegistry policies({
        policyFor("unrestricted", "armor.cloth"),
        explicitPolicies[0], explicitPolicies[1], explicitPolicies[2],
    });
    Require(policies.IsValid() && policies.Find("synthetic.unconfigured") == nullptr,
        "unconfigured synthetic policy unexpectedly resolved");
    denied.Policy = policies.Find("synthetic.unconfigured");
    Require(SC::EvaluateEligibility(denied).Reason == SC::EligibilityReason::UnknownIdentity,
        "missing synthetic policy did not fail closed");

    SC::EligibilityIdentityContext unknown =
        SC::BuildClassEligibilityContext(initial.ResolveClass(999), 80);
    denied.Policy = &warriorOnly;
    denied.Identity = &unknown;
    Require(!unknown.IdentityKnown && unknown.ClassKey.empty() && unknown.Capabilities.empty() &&
        SC::EvaluateEligibility(denied).Reason == SC::EligibilityReason::UnknownIdentity,
        "unknown runtime class defaulted to warrior");

    SC::CollectionKey stableCatalogKey = Key(13, 260001);
    SC::AccountCollectionCache accountCollections;
    auto opened = accountCollections.OpenSession(Account(501), Session(501), 0);
    Require(opened.Accepted && accountCollections.CompleteLoad(
        Account(501), opened.Generation, { stableCatalogKey }, SC::CollectionRevision(7)),
        "synthetic account collection fixture failed to load");

    SC::IdentityRegistry remapped({ SyntheticChronomancer(RemappedRuntimeClassId) }, {});
    auto remappedResolution = remapped.ResolveClass(RemappedRuntimeClassId);
    SC::EligibilityIdentityContext remappedContext =
        SC::BuildClassEligibilityContext(remappedResolution, 80);
    Require(remappedContext.IdentityKnown && remappedContext.LogicalClass == initialContext.LogicalClass &&
        remappedContext.ClassKey == initialContext.ClassKey,
        "runtime remap changed synthetic logical or catalog identity");
    Require(!remapped.ResolveClass(InitialRuntimeClassId).IsKnown(),
        "runtime remap retained the obsolete class ID");
    Require(accountCollections.IsOwned(Account(501), stableCatalogKey),
        "runtime remap changed account collection ownership");
    auto ownedAppearances = accountCollections.OwnedByType(Account(501), stableCatalogKey.TypeId);
    Require(ownedAppearances && *ownedAppearances == std::vector<SC::CollectionId> { stableCatalogKey.Id },
        "runtime remap changed the stable catalog ID");
}

void TestSyntheticRacePresentationContract()
{
    constexpr std::uint32_t InitialRuntimeRaceId = 102;
    constexpr std::uint32_t RemappedRuntimeRaceId = 302;
    SC::IdentityRegistry registry(
        { SyntheticChronomancer(101) }, { SyntheticEarthen(InitialRuntimeRaceId) });
    Require(registry.IsValid(), "synthetic race registration failed");

    auto race = registry.ResolveRace(InitialRuntimeRaceId);
    SC::EligibilityIdentityContext identity = SC::BuildEligibilityIdentityContext(
        registry.ResolveClass(101), race, 80);
    Require(identity.IdentityKnown && identity.LogicalRace == SC::LogicalRaceId(601) &&
        identity.RaceKey == "earthen" && identity.FactionKey == "ALLIANCE" &&
        identity.Capabilities.contains("appearance.stoneform"),
        "synthetic race identity or faction profile was not composed");

    SC::EligibilityPolicyDefinition factionPolicy;
    factionPolicy.PolicyKey = "synthetic.earthen.alliance";
    factionPolicy.RequiredCapabilities = { "appearance.stoneform" };
    factionPolicy.AllowedRaceKeys = { "earthen" };
    factionPolicy.FactionPolicy = "ALLIANCE";
    SC::EligibilityRequest request;
    request.Policy = &factionPolicy;
    request.Identity = &identity;
    Require(SC::EvaluateEligibility(request).IsAllowed(),
        "synthetic race faction and appearance capability were denied");

    SC::RacePresentationResources readyAssets { "synthetic-assets-v2", true, true };
    SC::RacePresentationResolution ready = registry.ResolveRacePresentation(race, readyAssets);
    Require(ready.IsReady() && ready.CameraProfile == "global" &&
        ready.AppearanceOverrideProfile == "appearance.dwarf" &&
        ready.ModelProfile == "model.earthen.stone",
        "synthetic race presentation profiles did not resolve");

    SC::RacePresentationResources wrongVersion { "synthetic-assets-v1", true, true };
    auto versionDenied = registry.ResolveRacePresentation(race, wrongVersion);
    Require(versionDenied.Code == SC::RacePresentationCode::AssetVersionMismatch &&
        !versionDenied.PreviewEnabled && !versionDenied.ActionEnabled,
        "race asset version mismatch did not disable presentation");
    SC::RacePresentationResources missingModel { "synthetic-assets-v2", false, true };
    Require(registry.ResolveRacePresentation(race, missingModel).Code ==
        SC::RacePresentationCode::ModelMissing,
        "missing race model did not fail closed");
    SC::RacePresentationResources missingTexture { "synthetic-assets-v2", true, false };
    auto textureDenied = registry.ResolveRacePresentation(race, missingTexture);
    Require(textureDenied.Code == SC::RacePresentationCode::TextureMissing &&
        !textureDenied.PreviewEnabled && !textureDenied.ActionEnabled,
        "missing race texture did not disable preview and actions");

    auto unknown = registry.ResolveRacePresentation(registry.ResolveRace(999), readyAssets);
    Require(unknown.Code == SC::RacePresentationCode::UnknownIdentity &&
        unknown.CameraProfile == "global" && !unknown.PreviewEnabled && !unknown.ActionEnabled,
        "unknown race presentation did not use a safe disabled fallback");

    SC::IdentityRegistry remapped(
        { SyntheticChronomancer(101) }, { SyntheticEarthen(RemappedRuntimeRaceId) });
    auto remappedRace = remapped.ResolveRace(RemappedRuntimeRaceId);
    Require(remappedRace.IsKnown() && remappedRace.Identity->LogicalId == SC::LogicalRaceId(601) &&
        !remapped.ResolveRace(InitialRuntimeRaceId).IsKnown(),
        "synthetic race runtime remap changed its logical identity");
}

void TestEligibilityResourceAndOverrideOrder()
{
    SC::EligibilityPolicyDefinition unrestricted;
    unrestricted.PolicyKey = "unrestricted";
    unrestricted.FactionPolicy = "ANY";
    SC::EligibilityIdentityContext identity;
    identity.IdentityKnown = true;
    identity.ClassKey = "chronomancer";
    identity.RaceKey = "earthen";
    identity.FactionKey = "ALLIANCE";
    identity.Capabilities = { "armor.cloth", "weapon.staff" };
    identity.Level = 80;

    SC::EligibilityRequest request;
    request.Policy = &unrestricted;
    request.Identity = &identity;
    request.ExactOverride = SC::ExactEligibilityOverride::Allow;
    request.Resources.AssetReady = false;
    Require(SC::EvaluateEligibility(request).Reason == SC::EligibilityReason::AssetMissing,
        "exact allow bypassed missing assets");

    request.Resources.AssetReady = true;
    request.ExactOverride = SC::ExactEligibilityOverride::Deny;
    Require(SC::EvaluateEligibility(request).Reason == SC::EligibilityReason::ExactDenied,
        "exact deny did not precede ordinary policy allow");
}

void TestEligibilityDeclarativeAndFallbackOrder()
{
    SC::EligibilityPolicyDefinition policy;
    policy.PolicyKey = "synthetic.caster";
    policy.RequiredCapabilities = { "armor.cloth" };
    policy.AnyCapabilities = { "weapon.staff", "weapon.wand" };
    policy.ForbiddenCapabilities = { "form.demon" };
    policy.AllowedRaceKeys = { "earthen" };
    policy.AllowedClassKeys = { "chronomancer" };
    policy.FactionPolicy = "ALLIANCE";
    policy.MinimumLevel = 40;
    policy.RequiredSkills = { { "enchanting", 300 } };
    policy.CustomPolicyKey = "timeline.stable";
    policy.LegacyFallback = true;

    SC::EligibilityIdentityContext identity;
    identity.IdentityKnown = true;
    identity.ClassKey = "chronomancer";
    identity.RaceKey = "earthen";
    identity.FactionKey = "ALLIANCE";
    identity.Capabilities = { "armor.cloth", "weapon.staff" };
    identity.Level = 80;
    identity.Skills = { { "enchanting", 450 } };

    std::vector<std::string> order;
    SC::EligibilityRequest request;
    request.Policy = &policy;
    request.Identity = &identity;
    request.CustomPolicy = [&order](std::string_view key, SC::EligibilityIdentityContext const&)
    {
        order.emplace_back(key);
        return true;
    };
    request.LegacyFallback = [&order](SC::EligibilityIdentityContext const&)
    {
        order.emplace_back("legacy");
        return true;
    };
    request.RuntimeCondition = [&order](SC::EligibilityIdentityContext const&)
    {
        order.emplace_back("runtime");
        return true;
    };
    Require(SC::EvaluateEligibility(request).IsAllowed(), "synthetic reusable profile was denied");
    Require(order == std::vector<std::string>({ "timeline.stable", "legacy", "runtime" }),
        "custom, legacy and runtime policy order changed");

    identity.Capabilities.insert("form.demon");
    order.clear();
    Require(SC::EvaluateEligibility(request).Reason == SC::EligibilityReason::ForbiddenCapability,
        "forbidden capability was ignored");
    Require(order.empty(), "later policy stages ran after declarative denial");
}

void TestEligibilityUnknownIdentityViewOnly()
{
    SC::EligibilityPolicyDefinition unrestricted;
    unrestricted.PolicyKey = "unrestricted";
    unrestricted.FactionPolicy = "ANY";
    SC::EligibilityPolicyDefinition restricted = unrestricted;
    restricted.PolicyKey = "restricted";
    SC::EligibilityIdentityContext unknown;

    SC::EligibilityRequest request;
    request.Policy = &unrestricted;
    request.Identity = &unknown;
    request.Mode = SC::EligibilityMode::View;
    Require(SC::EvaluateEligibility(request).IsAllowed(), "unknown identity could not view unrestricted catalog");
    request.Mode = SC::EligibilityMode::Use;
    Require(SC::EvaluateEligibility(request).Reason == SC::EligibilityReason::UnknownIdentity,
        "unknown identity could use a collection");
    request.Mode = SC::EligibilityMode::View;
    request.Policy = &restricted;
    Require(SC::EvaluateEligibility(request).Reason == SC::EligibilityReason::UnknownIdentity,
        "unknown identity could view a restricted catalog");

    SC::EligibilityPolicyRegistry const& generated = SC::GetEligibilityPolicyRegistry();
    Require(generated.IsValid() && generated.Find("unrestricted") && generated.Find("appearance.plate"),
        "generated policy registry is invalid");
}

void TestGeneratedMountCatalog()
{
    SC::MountCatalog const& catalog = SC::GetMountCatalog();
    Require(catalog.Collections().size() == 281, "generated mount catalog count changed without review");
    SC::MountCollectionDefinition const* acherus = catalog.FindByUnlockSpell(48778);
    Require(acherus && acherus->Id == SC::CollectionId(100000), "Acherus mount spell lookup failed");
    Require(acherus->PreviewCreatureEntry == 28302 &&
        acherus->Lifecycle == SC::CatalogLifecycle::Active &&
        SC::CatalogLifecycleAllowsPreview(acherus->Lifecycle),
        "mount preview identity or lifecycle was not generated");
    Require(catalog.Find(acherus->Id) == acherus, "mount collection reverse lookup failed");
    Require(!catalog.FindByUnlockSpell(32345), "reviewed test mount spell entered the production lookup");
    SC::MountCollectionDefinition const* gryphon = catalog.FindByUnlockSpell(32292);
    Require(gryphon && gryphon->ActionVariants.front().MinimumRidingSkill == 300 &&
        gryphon->ActionVariants.front().IsFlying, "mount action requirements were not generated");
}

void TestGeneratedCompanionCatalog()
{
    SC::CompanionCatalog const& catalog = SC::GetCompanionCatalog();
    Require(catalog.Collections().size() == 201, "generated companion catalog does not match reviewed candidates");
    SC::CompanionCollectionDefinition const* worg = catalog.FindBySpell(15999);
    Require(worg && worg->Id == SC::CollectionId(100281) && worg->CanonicalSpellId == 15999,
        "Worg Pup companion lookup failed");
    Require(worg->PreviewCreatureEntry == 10259 &&
        worg->Lifecycle == SC::CatalogLifecycle::Active &&
        SC::CatalogLifecycleAllowsPreview(worg->Lifecycle),
        "companion preview identity or lifecycle was not generated");
    Require(catalog.Find(worg->Id) == worg, "companion collection reverse lookup failed");
    SC::CompanionCollectionDefinition const* spottedRabbit = catalog.FindBySpell(10712);
    Require(spottedRabbit && catalog.FindBySpell(35157) == spottedRabbit &&
        spottedRabbit->CanonicalSpellId == 10712 && spottedRabbit->PreviewCreatureEntry == 7559,
        "companion unlock spell variants do not resolve to one canonical identity");
    SC::CompanionCollectionDefinition const* murki = catalog.FindBySpell(24987);
    Require(murki && catalog.FindBySpell(25018) == murki && murki->CanonicalSpellId == 25018,
        "companion summon did not retain the reviewed canonical spell");
    Require(!catalog.FindBySpell(48778), "mount spell entered the companion allowlist");
}

void TestGeneratedToyCatalog()
{
    SC::ToyCatalog const& catalog = SC::GetToyCatalog();
    Require(catalog.Collections().size() == 9, "generated toy catalog count does not match reviewed first batch");
    SC::ToyCollectionDefinition const* orb = catalog.FindByItem(35275);
    Require(orb && orb->Id == SC::CollectionId(100305) && orb->ActionKind == SC::ToyActionKind::SpellSelf,
        "Orb of the Sin'dorei toy lookup failed");
    Require(catalog.Find(orb->Id) == orb, "toy collection reverse lookup failed");

    std::set<SC::ToyActionKind> actionKinds;
    for (SC::ToyCollectionDefinition const& toy : catalog.Collections())
        actionKinds.insert(toy.ActionKind);
    Require(actionKinds.size() == 4, "toy action registry no longer covers every reviewed handler kind");
    Require(!catalog.FindByItem(6948), "teleport item entered the toy allowlist");
    Require(catalog.FindByItem(36863) && catalog.FindByItem(36863)->Id == SC::CollectionId(100486),
        "reviewed dice toy was not assigned through the append-only registry");
    SC::ToyCollectionDefinition invalid = *orb;
    invalid.Id = SC::CollectionId(199999);
    invalid.Key = "toy.invalid_handler";
    invalid.ItemId = 199999;
    invalid.ActionKind = SC::ToyActionKind::CustomHandler;
    invalid.CustomHandler = "missing_handler";
    bool rejected = false;
    try
    {
        SC::ToyCatalog invalidCatalog({ invalid });
    }
    catch (std::runtime_error const&)
    {
        rejected = true;
    }
    Require(rejected, "unknown custom toy handler did not fail closed at catalog construction");
}

void TestReadOnlyShadowComparison()
{
    std::vector<SC::LegacyShadowCategoryDefinition> matchingCategories {
        { SC::CollectionTypeId(10), "mount", "same", "same", 1, 1 },
    };
    std::vector<SC::LegacyShadowEntryDefinition> matchingLegacy {
        { SC::CollectionTypeId(10), 1, SC::CollectionId(100), true, true, true },
    };
    std::vector<SC::ShadowObservedState> matchingObserved {
        { { SC::CollectionTypeId(10), SC::CollectionId(100) }, true, true, true },
    };
    SC::ShadowComparisonReport matching = SC::CompareLegacyShadow(
        matchingCategories, matchingLegacy, matchingObserved);
    Require(matching.ExactMatch() && matching.LegacyOwnedIds == matching.CanonicalOwnedIds,
        "matching shadow projection produced a difference");

    std::vector<SC::LegacyShadowCategoryDefinition> categories {
        { SC::CollectionTypeId(10), "mount", "legacy-mount", "canonical-mount", 2, 2 },
        { SC::CollectionTypeId(12), "toy", "same", "same", 1, 0 },
    };
    std::vector<SC::LegacyShadowEntryDefinition> legacy {
        { SC::CollectionTypeId(10), 1, SC::CollectionId(100), true, true, true },
        { SC::CollectionTypeId(10), 2, SC::CollectionId(101), false, true, true },
        { SC::CollectionTypeId(12), 1, SC::CollectionId(), true, true, true },
    };
    std::vector<SC::ShadowObservedState> observed {
        { { SC::CollectionTypeId(10), SC::CollectionId(100) }, true, true, true },
        { { SC::CollectionTypeId(10), SC::CollectionId(101) }, true, true, true },
        { { SC::CollectionTypeId(12), SC::CollectionId(999) }, true, true, true },
    };
    SC::ShadowComparisonReport report = SC::CompareLegacyShadow(categories, legacy, observed);
    Require(!report.ExactMatch() && report.LegacyEntryCount == 3 && report.MappedEntryCount == 2 &&
        report.UnmappedEntryCount == 1, "shadow ID coverage was not reported");
    Require(report.LegacyOwnedCount == 2 && report.CanonicalOwnedCount == 3 &&
        report.OwnedMismatchCount == 2, "shadow owned count/ID differences were not reported");
    Require(report.CategoryHashMismatchCount == 1 && report.CatalogMismatchCount == 0 &&
        report.AvailabilityMismatchCount == 0, "shadow hash/availability comparison changed");
    Require(report.Differences.size() == 3 && report.Differences.back().ExtraCanonicalOwned,
        "unmapped and extra canonical ownership were not exportable");
}
}

int main()
{
    try
    {
        TestStableTypes();
        TestDuplicateAndTombstoneFailures();
        TestCyclesAndMissingDependencies();
        TestRegistrationOrderIndependence();
        TestSyntheticProviderStorageContracts();
        TestTwoSessionsShareOneLoad();
        TestLogoutBeforeCallback();
        TestUnlockDuringLoad();
        TestRelogAndDelayedEviction();
        TestFailedLoadRetry();
        TestExplicitCrossThreadLocking();
        TestExplicitReloadAndDiagnostics();
        TestExtensibleIdentityRegistry();
        TestSyntheticClassCapabilityAndCollectionContract();
        TestSyntheticRacePresentationContract();
        TestEligibilityResourceAndOverrideOrder();
        TestEligibilityDeclarativeAndFallbackOrder();
        TestEligibilityUnknownIdentityViewOnly();
        TestGeneratedMountCatalog();
        TestGeneratedCompanionCatalog();
        TestGeneratedToyCatalog();
        TestReadOnlyShadowComparison();
        std::cout << "SoloCollections native domain tests passed" << std::endl;
        return EXIT_SUCCESS;
    }
    catch (std::exception const& exception)
    {
        std::cerr << exception.what() << std::endl;
        return EXIT_FAILURE;
    }
}
