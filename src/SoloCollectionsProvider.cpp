#include "SoloCollectionsProvider.h"

#include <algorithm>
#include <functional>
#include <utility>

namespace SoloCollections
{
RegistryRegistrationResult RegistryRegistrationResult::Success()
{
    return { true, CollectionReasonCode::Ok, {} };
}

RegistryRegistrationResult RegistryRegistrationResult::Fatal(CollectionReasonCode reason, std::string message)
{
    return { false, reason, std::move(message) };
}

RegistryFinalizeResult RegistryFinalizeResult::Ok()
{
    return { true, CollectionReasonCode::Ok, {} };
}

RegistryFinalizeResult RegistryFinalizeResult::Fatal(CollectionReasonCode reason, std::string message)
{
    return { false, reason, std::move(message) };
}

bool CollectionProviderRegistry::IsCanonicalTypeKey(std::string_view typeKey)
{
    if (typeKey.empty())
        return false;

    return std::all_of(typeKey.begin(), typeKey.end(), [](char value)
    {
        return (value >= 'a' && value <= 'z') || (value >= '0' && value <= '9') ||
            value == '.' || value == '_' || value == '-';
    });
}

RegistryRegistrationResult CollectionProviderRegistry::Register(std::unique_ptr<CollectionProvider> provider)
{
    if (_finalized)
        return RegistryRegistrationResult::Fatal(CollectionReasonCode::NotReady,
            "Provider registration is closed after registry finalization.");
    if (!provider)
        return RegistryRegistrationResult::Fatal(CollectionReasonCode::InvalidArgument,
            "Cannot register a null collection provider.");

    CollectionProviderDescriptor const& descriptor = provider->Descriptor();
    if (!descriptor.TypeId.IsValid() || !IsCanonicalTypeKey(descriptor.TypeKey))
        return RegistryRegistrationResult::Fatal(CollectionReasonCode::InvalidArgument,
            "Provider type ID and type key must be non-zero and canonical.");

    if (_tombstonesById.contains(descriptor.TypeId) || _tombstonesByKey.contains(descriptor.TypeKey))
    {
        RegistryRegistrationResult failure = RegistryRegistrationResult::Fatal(CollectionReasonCode::Tombstoned,
            "Provider attempted to reuse a tombstoned type ID or type key.");
        _fatalRegistrationError = failure;
        return failure;
    }

    if (_providersById.contains(descriptor.TypeId) || _providersByKey.contains(descriptor.TypeKey))
    {
        RegistryRegistrationResult failure = RegistryRegistrationResult::Fatal(CollectionReasonCode::DuplicateProvider,
            "Duplicate collection provider type ID or type key.");
        _fatalRegistrationError = failure;
        return failure;
    }

    CollectionTypeId typeId = descriptor.TypeId;
    std::string typeKey = descriptor.TypeKey;
    _providersById.emplace(typeId, std::move(provider));
    _providersByKey.emplace(std::move(typeKey), typeId);
    return RegistryRegistrationResult::Success();
}

RegistryRegistrationResult CollectionProviderRegistry::ReserveTombstone(CollectionTypeId typeId, std::string typeKey)
{
    if (_finalized || !typeId.IsValid() || !IsCanonicalTypeKey(typeKey))
        return RegistryRegistrationResult::Fatal(CollectionReasonCode::InvalidArgument,
            "Invalid tombstone reservation or finalized registry.");

    if (_providersById.contains(typeId) || _providersByKey.contains(typeKey) ||
        _tombstonesById.contains(typeId) || _tombstonesByKey.contains(typeKey))
    {
        RegistryRegistrationResult failure = RegistryRegistrationResult::Fatal(CollectionReasonCode::DuplicateProvider,
            "Duplicate active or tombstoned collection type reservation.");
        _fatalRegistrationError = failure;
        return failure;
    }

    _tombstonesById.emplace(typeId, typeKey);
    _tombstonesByKey.emplace(std::move(typeKey), typeId);
    return RegistryRegistrationResult::Success();
}

RegistryFinalizeResult CollectionProviderRegistry::Finalize()
{
    if (_fatalRegistrationError)
        return RegistryFinalizeResult::Fatal(_fatalRegistrationError->Reason, _fatalRegistrationError->Message);
    if (_finalized)
        return RegistryFinalizeResult::Ok();

    _topologicalOrder.clear();
    _runtimeStates.clear();

    std::map<CollectionTypeId, VisitState> visits;
    for (auto const& [typeId, provider] : _providersById)
    {
        (void)provider;
        visits.emplace(typeId, VisitState::Unvisited);
    }

    std::function<bool(CollectionTypeId)> visit = [&](CollectionTypeId typeId)
    {
        VisitState& state = visits[typeId];
        if (state == VisitState::Visiting)
            return false;
        if (state == VisitState::Visited)
            return true;

        state = VisitState::Visiting;
        CollectionProviderDescriptor const& descriptor = _providersById.at(typeId)->Descriptor();
        std::vector<CollectionTypeId> dependencies = descriptor.Dependencies;
        std::sort(dependencies.begin(), dependencies.end());
        for (CollectionTypeId dependency : dependencies)
        {
            if (_providersById.contains(dependency) && !visit(dependency))
                return false;
        }
        state = VisitState::Visited;
        _topologicalOrder.push_back(typeId);
        return true;
    };

    for (auto const& [typeId, provider] : _providersById)
    {
        (void)provider;
        if (!visit(typeId))
        {
            _topologicalOrder.clear();
            return RegistryFinalizeResult::Fatal(CollectionReasonCode::DependencyCycle,
                "Collection provider dependency graph contains a cycle.");
        }
    }

    for (CollectionTypeId typeId : _topologicalOrder)
    {
        CollectionProviderDescriptor const& descriptor = _providersById.at(typeId)->Descriptor();
        CollectionProviderRuntimeState runtime;
        for (CollectionTypeId dependency : descriptor.Dependencies)
        {
            auto provider = _providersById.find(dependency);
            auto dependencyState = _runtimeStates.find(dependency);
            if (provider == _providersById.end() || dependencyState == _runtimeStates.end() ||
                dependencyState->second.Mode != CollectionProviderMode::Enabled)
                runtime.UnavailableDependencies.push_back(dependency);
        }

        if (runtime.UnavailableDependencies.empty())
        {
            runtime.Mode = CollectionProviderMode::Enabled;
            runtime.Reason = CollectionReasonCode::Ok;
        }
        else
        {
            runtime.Mode = descriptor.ReadOnlyWhenDependencyMissing ?
                CollectionProviderMode::ReadOnly : CollectionProviderMode::Disabled;
            runtime.Reason = CollectionReasonCode::DependencyMissing;
        }
        _runtimeStates.emplace(typeId, std::move(runtime));
    }

    _finalized = true;
    return RegistryFinalizeResult::Ok();
}

CollectionProvider const* CollectionProviderRegistry::Find(CollectionTypeId typeId) const
{
    auto provider = _providersById.find(typeId);
    return provider == _providersById.end() ? nullptr : provider->second.get();
}

CollectionProvider const* CollectionProviderRegistry::Find(std::string_view typeKey) const
{
    auto typeId = _providersByKey.find(std::string(typeKey));
    return typeId == _providersByKey.end() ? nullptr : Find(typeId->second);
}

CollectionProviderRuntimeState const* CollectionProviderRegistry::State(CollectionTypeId typeId) const
{
    auto state = _runtimeStates.find(typeId);
    return state == _runtimeStates.end() ? nullptr : &state->second;
}

CollectionProviderRegistry& GetCollectionProviderRegistry()
{
    static CollectionProviderRegistry registry;
    return registry;
}
}
