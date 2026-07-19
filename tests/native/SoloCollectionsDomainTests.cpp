#include "SoloCollectionsAccountCache.h"
#include "SoloCollectionsIdentity.h"
#include "SoloCollectionsProvider.h"

#include <cstdlib>
#include <iostream>
#include <memory>
#include <set>
#include <stdexcept>
#include <string>
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
        std::vector<std::uint16_t> dependencies = {}, bool readOnlyOnMissing = false)
    {
        _descriptor.TypeId = SC::CollectionTypeId(typeId);
        _descriptor.TypeKey = std::move(typeKey);
        _descriptor.ReadOnlyWhenDependencyMissing = readOnlyOnMissing;
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

void TestWorldThreadConfinement()
{
    SC::AccountCollectionCache cache(100);
    bool rejected = false;
    std::thread worker([&cache, &rejected]()
    {
        try
        {
            (void)cache.Snapshot(Account(6));
        }
        catch (std::logic_error const&)
        {
            rejected = true;
        }
    });
    worker.join();
    Require(rejected, "cross-thread cache access was not rejected");
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

void TestExtensibleIdentityRegistry()
{
    SC::ClassIdentityDefinition syntheticClass {
        SC::LogicalClassId(std::uint16_t { 501 }), "chronomancer", 101,
        { "CHRONOMANCER" }, { "armor.cloth", "weapon.staff" },
        "class.caster", "class.chronomancer", 0, "CLOTH", { "STAFF" }, { "OFFHAND_ITEM" }
    };
    SC::RaceIdentityDefinition syntheticRace {
        SC::LogicalRaceId(std::uint16_t { 601 }), "earthen", 102,
        { "EARTHEN" }, {}, "ALLIANCE", "race.medium", "race.earthen", ""
    };
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
}

int main()
{
    try
    {
        TestStableTypes();
        TestDuplicateAndTombstoneFailures();
        TestCyclesAndMissingDependencies();
        TestRegistrationOrderIndependence();
        TestTwoSessionsShareOneLoad();
        TestLogoutBeforeCallback();
        TestUnlockDuringLoad();
        TestRelogAndDelayedEviction();
        TestFailedLoadRetry();
        TestWorldThreadConfinement();
        TestExplicitReloadAndDiagnostics();
        TestExtensibleIdentityRegistry();
        std::cout << "SoloCollections native domain tests passed" << std::endl;
        return EXIT_SUCCESS;
    }
    catch (std::exception const& exception)
    {
        std::cerr << exception.what() << std::endl;
        return EXIT_FAILURE;
    }
}
