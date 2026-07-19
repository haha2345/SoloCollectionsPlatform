#include "SoloCollectionsProvider.h"

#include <cstdlib>
#include <iostream>
#include <memory>
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
}

int main()
{
    try
    {
        TestStableTypes();
        TestDuplicateAndTombstoneFailures();
        TestCyclesAndMissingDependencies();
        TestRegistrationOrderIndependence();
        std::cout << "SoloCollections native domain tests passed" << std::endl;
        return EXIT_SUCCESS;
    }
    catch (std::exception const& exception)
    {
        std::cerr << exception.what() << std::endl;
        return EXIT_FAILURE;
    }
}
