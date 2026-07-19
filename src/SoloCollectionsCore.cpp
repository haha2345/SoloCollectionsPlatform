#include "SoloCollectionsProvider.h"

#include "Log.h"
#include "ScriptMgr.h"

#include <memory>
#include <stdexcept>

namespace SoloCollections
{
namespace
{
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
    SoloCollectionsCoreWorldScript() : WorldScript("SoloCollectionsCoreWorldScript", { WORLDHOOK_ON_STARTUP }) { }

    void OnStartup() override
    {
        CollectionProviderRegistry& registry = GetCollectionProviderRegistry();
        RegistryRegistrationResult registration = registry.Register(std::make_unique<SyntheticCollectionProvider>());
        if (!registration.Accepted)
            throw std::runtime_error("SoloCollections provider registration failed: " + registration.Message);

        RegistryFinalizeResult finalized = registry.Finalize();
        if (!finalized.Success)
            throw std::runtime_error("SoloCollections provider finalization failed: " + finalized.Message);

        LOG_INFO("module", "SoloCollections provider registry initialized with {} provider(s).",
            registry.TopologicalOrder().size());
    }
};
}
}

void AddSC_solo_collections_core()
{
    new SoloCollections::SoloCollectionsCoreWorldScript();
}
