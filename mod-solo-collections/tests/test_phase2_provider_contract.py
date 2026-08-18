from __future__ import annotations

import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
HEADER_PATH = ROOT / "src" / "SoloCollectionsProvider.h"
IMPLEMENTATION_PATH = ROOT / "src" / "SoloCollectionsProvider.cpp"
CORE_PATH = ROOT / "src" / "SoloCollectionsCore.cpp"
LOADER_PATH = ROOT / "src" / "transmog_loader.cpp"


class ProviderRegistryContractTests(unittest.TestCase):
    def test_provider_interface_cannot_mutate_account_cache(self):
        header = HEADER_PATH.read_text(encoding="utf-8")
        provider = header.split("class CollectionProvider\n{", 1)[1].split("};", 1)[0]
        self.assertIn("virtual CollectionProviderDescriptor const& Descriptor() const", provider)
        self.assertIn("virtual CollectionResult Evaluate(CollectionId collectionId) const", provider)
        for forbidden in ("AccountCache", "CharacterDatabase", "Player*", "WorldSession"):
            self.assertNotIn(forbidden, provider)

    def test_duplicates_cycles_and_tombstone_reuse_are_fatal(self):
        implementation = IMPLEMENTATION_PATH.read_text(encoding="utf-8")
        self.assertIn("CollectionReasonCode::DuplicateProvider", implementation)
        self.assertIn("CollectionReasonCode::DependencyCycle", implementation)
        self.assertIn("CollectionReasonCode::Tombstoned", implementation)
        self.assertIn("_providersByKey.contains(descriptor.TypeKey)", implementation)
        self.assertIn("_tombstonesById.contains(descriptor.TypeId)", implementation)
        self.assertIn("VisitState::Visiting", implementation)
        self.assertIn("return RegistryFinalizeResult::Fatal", implementation)

    def test_missing_dependencies_degrade_without_registration_order_coupling(self):
        header = HEADER_PATH.read_text(encoding="utf-8")
        implementation = IMPLEMENTATION_PATH.read_text(encoding="utf-8")
        for mode in ("Enabled = 1", "ReadOnly = 2", "Disabled = 3"):
            self.assertIn(mode, header)
        self.assertIn("ReadOnlyWhenDependencyMissing", header)
        self.assertIn("CollectionReasonCode::DependencyMissing", implementation)
        self.assertIn("descriptor.ReadOnlyWhenDependencyMissing", implementation)
        self.assertIn("std::map<CollectionTypeId", header)
        self.assertIn("_topologicalOrder", header)
        self.assertNotIn("switch (descriptor.TypeId", implementation)

    def test_synthetic_provider_is_registered_through_the_generic_core(self):
        core = CORE_PATH.read_text(encoding="utf-8")
        loader = LOADER_PATH.read_text(encoding="utf-8")
        self.assertIn("class SyntheticCollectionProvider", core)
        self.assertIn('"synthetic"', core)
        self.assertIn('registerProvider("synthetic", std::make_unique<SyntheticCollectionProvider>())', core)
        self.assertIn("registration = registry.Register(std::move(provider))", core)
        self.assertIn("registry.Finalize()", core)
        self.assertIn("AddSC_solo_collections_core", loader)


if __name__ == "__main__":
    unittest.main()
