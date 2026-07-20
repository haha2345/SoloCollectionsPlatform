import json
import pathlib
import unittest


ROOT = pathlib.Path(__file__).resolve().parents[1]
CORE = (ROOT / "src/SoloCollectionsCore.cpp").read_text(encoding="utf-8")
SERVICE = (ROOT / "src/SoloCollectionsMountService.cpp").read_text(encoding="utf-8")
STORE_H = (ROOT / "src/SoloCollectionsAccountStore.h").read_text(encoding="utf-8")
STORE_CPP = (ROOT / "src/SoloCollectionsAccountStore.cpp").read_text(encoding="utf-8")
CATALOG = (ROOT / "src/SoloCollectionsMountCatalog.cpp").read_text(encoding="utf-8")
NATIVE = (ROOT / "tests/native/SoloCollectionsDomainTests.cpp").read_text(encoding="utf-8")
ACTIONS = json.loads((ROOT / "data/generated/solo_collections_mount_actions.json").read_text(encoding="utf-8"))


class MountUnlockContractTests(unittest.TestCase):
    def test_generated_allowlist_is_the_only_spell_to_collection_lookup(self):
        self.assertEqual(281, len(ACTIONS["collections"]))
        self.assertEqual(295, sum(len(entry["unlockSpellIds"]) for entry in ACTIONS["collections"]))
        self.assertIn("generated/SoloCollectionsMountCatalog.inc", CATALOG)
        self.assertIn("FindByUnlockSpell", CATALOG)
        self.assertIn("TestGeneratedMountCatalog", NATIVE)

    def test_new_spell_hook_only_grants_and_never_revokes(self):
        self.assertIn("PLAYERHOOK_ON_LEARN_SPELL", CORE)
        self.assertIn("void OnPlayerLearnSpell(Player* player, std::uint32_t spellId)", SERVICE)
        self.assertIn("CollectionMutationKind::Grant", SERVICE)
        self.assertNotIn("OnPlayerForgotSpell", CORE)
        self.assertNotIn("CollectionMutationKind::Revoke", SERVICE)

    def test_login_migration_waits_for_ready_and_is_marker_guarded(self):
        self.assertIn("snapshot->State != AccountCacheLoadState::Ready", SERVICE)
        self.assertIn("player->HasSpell(spellId)", SERVICE)
        self.assertIn("CheckMigrationMarker", STORE_H)
        self.assertIn("sc_migration_marker", STORE_CPP)
        self.assertIn("migration_version >=", STORE_CPP)
        self.assertIn("character_spell", STORE_CPP)
        self.assertIn("cs.disabled = 0", STORE_CPP)
        self.assertIn("CompleteMigrationMarker", SERVICE)

    def test_account_mutations_are_serial_and_emit_revision_deltas(self):
        self.assertIn("HasPendingMutation(account)", SERVICE)
        self.assertIn("state.Pending.front()", SERVICE)
        self.assertIn("mutation.Generation = state.Generation", SERVICE)
        self.assertIn("CollectionSourceKind::Migration", SERVICE)
        self.assertIn("OnCollectionDeltaCommitted", STORE_CPP)
        self.assertIn("nextRevision.Value()", STORE_CPP)


if __name__ == "__main__":
    unittest.main()
