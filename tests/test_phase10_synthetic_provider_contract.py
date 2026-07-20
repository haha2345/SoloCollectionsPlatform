from __future__ import annotations

import pathlib
import unittest


ROOT = pathlib.Path(__file__).resolve().parents[1]
PROVIDER = (ROOT / "src/SoloCollectionsProvider.h").read_text(encoding="utf-8")
ACCOUNT = (ROOT / "src/SoloCollectionsAccountService.cpp").read_text(encoding="utf-8")
CORE = (ROOT / "src/SoloCollectionsCore.cpp").read_text(encoding="utf-8")
DOMAIN = (ROOT / "tests/native/SoloCollectionsDomainTests.cpp").read_text(encoding="utf-8")
PROTOCOL = (ROOT / "tests/native/SoloCollectionsProtocolTests.cpp").read_text(encoding="utf-8")


class SyntheticProviderContractTests(unittest.TestCase):
    def test_storage_modes_are_explicit_and_derived_sets_do_not_write_unlocks(self):
        for mode in ("Persisted = 1", "Derived = 2", "External = 3"):
            self.assertIn(mode, PROVIDER)
        self.assertIn("CollectionStorageMode Storage", PROVIDER)
        self.assertIn("CollectionStorageMode::Derived", CORE)

    def test_external_reads_never_fall_back_to_generic_unlock_state(self):
        self.assertIn("storage == CollectionStorageMode::External", ACCOUNT)
        self.assertIn("provider->IsOwned(accountId, key.Id).value_or(false)", ACCOUNT)
        self.assertIn("provider->Descriptor().Storage != CollectionStorageMode::Persisted", ACCOUNT)
        self.assertIn("external provider unexpectedly required a generic unlock row", DOMAIN)
        self.assertIn("external provider account projection was not readable", DOMAIN)

    def test_only_persisted_enabled_providers_can_mutate(self):
        self.assertIn("providerState->Mode == CollectionProviderMode::Disabled", ACCOUNT)
        self.assertIn("providerState->Mode == CollectionProviderMode::ReadOnly", ACCOUNT)
        self.assertIn("CollectionReasonCode::ReadOnly", ACCOUNT)
        self.assertIn("persisted provider did not reuse account ownership and revision state", DOMAIN)
        self.assertIn("synthetic persisted provider did not reuse revisioned SC2 delta sync", PROTOCOL)

    def test_dependency_failures_are_isolated(self):
        self.assertIn("healthy providers were affected by another provider dependency failure", DOMAIN)
        self.assertIn("missing dependencies did not degrade providers independently", DOMAIN)


if __name__ == "__main__":
    unittest.main()
