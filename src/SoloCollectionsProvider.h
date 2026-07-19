#ifndef SOLO_COLLECTIONS_PROVIDER_H
#define SOLO_COLLECTIONS_PROVIDER_H

#include "SoloCollectionsTypes.h"

#include <map>
#include <memory>
#include <optional>
#include <string>
#include <string_view>
#include <unordered_map>
#include <vector>

namespace SoloCollections
{
enum class CollectionProviderMode : std::uint8_t
{
    Enabled = 1,
    ReadOnly = 2,
    Disabled = 3,
};

struct CollectionProviderDescriptor
{
    CollectionTypeId TypeId;
    std::string TypeKey;
    std::vector<CollectionTypeId> Dependencies;
    bool ReadOnlyWhenDependencyMissing = false;
};

class CollectionProvider
{
public:
    virtual ~CollectionProvider() = default;
    [[nodiscard]] virtual CollectionProviderDescriptor const& Descriptor() const = 0;
    [[nodiscard]] virtual CollectionResult Evaluate(CollectionId collectionId) const = 0;
};

struct RegistryRegistrationResult
{
    bool Accepted = false;
    CollectionReasonCode Reason = CollectionReasonCode::InternalError;
    std::string Message;

    [[nodiscard]] static RegistryRegistrationResult Success();
    [[nodiscard]] static RegistryRegistrationResult Fatal(CollectionReasonCode reason, std::string message);
};

struct RegistryFinalizeResult
{
    bool Success = false;
    CollectionReasonCode Reason = CollectionReasonCode::InternalError;
    std::string Message;

    [[nodiscard]] static RegistryFinalizeResult Ok();
    [[nodiscard]] static RegistryFinalizeResult Fatal(CollectionReasonCode reason, std::string message);
};

struct CollectionProviderRuntimeState
{
    CollectionProviderMode Mode = CollectionProviderMode::Disabled;
    CollectionReasonCode Reason = CollectionReasonCode::NotReady;
    std::vector<CollectionTypeId> UnavailableDependencies;
};

class CollectionProviderRegistry
{
public:
    [[nodiscard]] RegistryRegistrationResult Register(std::unique_ptr<CollectionProvider> provider);
    [[nodiscard]] RegistryRegistrationResult ReserveTombstone(CollectionTypeId typeId, std::string typeKey);
    [[nodiscard]] RegistryFinalizeResult Finalize();

    [[nodiscard]] CollectionProvider const* Find(CollectionTypeId typeId) const;
    [[nodiscard]] CollectionProvider const* Find(std::string_view typeKey) const;
    [[nodiscard]] CollectionProviderRuntimeState const* State(CollectionTypeId typeId) const;
    [[nodiscard]] std::vector<CollectionTypeId> const& TopologicalOrder() const { return _topologicalOrder; }
    [[nodiscard]] bool IsFinalized() const { return _finalized; }

private:
    enum class VisitState : std::uint8_t
    {
        Unvisited = 0,
        Visiting = 1,
        Visited = 2,
    };

    [[nodiscard]] static bool IsCanonicalTypeKey(std::string_view typeKey);

    std::map<CollectionTypeId, std::unique_ptr<CollectionProvider>> _providersById;
    std::unordered_map<std::string, CollectionTypeId> _providersByKey;
    std::map<CollectionTypeId, std::string> _tombstonesById;
    std::unordered_map<std::string, CollectionTypeId> _tombstonesByKey;
    std::map<CollectionTypeId, CollectionProviderRuntimeState> _runtimeStates;
    std::vector<CollectionTypeId> _topologicalOrder;
    std::optional<RegistryRegistrationResult> _fatalRegistrationError;
    bool _finalized = false;
};

CollectionProviderRegistry& GetCollectionProviderRegistry();
}

#endif
