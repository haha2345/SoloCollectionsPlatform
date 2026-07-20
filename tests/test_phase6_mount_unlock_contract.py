import json
import pathlib
import unittest


ROOT = pathlib.Path(__file__).resolve().parents[1]
CORE = (ROOT / "src/SoloCollectionsCore.cpp").read_text(encoding="utf-8")
SERVICE = (ROOT / "src/SoloCollectionsMountService.cpp").read_text(encoding="utf-8")
STORE_H = (ROOT / "src/SoloCollectionsAccountStore.h").read_text(encoding="utf-8")
STORE_CPP = (ROOT / "src/SoloCollectionsAccountStore.cpp").read_text(encoding="utf-8")
CATALOG = (ROOT / "src/SoloCollectionsMountCatalog.cpp").read_text(encoding="utf-8")
PROTOCOL_SCRIPT = (ROOT / "src/SoloCollectionsProtocolScript.cpp").read_text(encoding="utf-8")
PROTOCOL_SERVER = (ROOT / "src/SoloCollectionsProtocolServer.cpp").read_text(encoding="utf-8")
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
        self.assertNotIn("cs.disabled", STORE_CPP)
        self.assertIn("CompleteMigrationMarker", SERVICE)
        self.assertIn("GetMountCollectionService().Update()", CORE)
        player_update = CORE[CORE.index("void OnPlayerUpdate"):CORE.index("void OnPlayerLearnSpell")]
        self.assertNotIn("GetMountCollectionService", player_update)
        self.assertIn("std::mutex _mutex", SERVICE)

    def test_account_mutations_are_serial_and_emit_revision_deltas(self):
        self.assertIn("HasPendingMutation(account)", SERVICE)
        self.assertIn("state.Pending.front()", SERVICE)
        self.assertIn("mutation.Generation = state.Generation", SERVICE)
        self.assertIn("CollectionSourceKind::Migration", SERVICE)
        self.assertIn("OnCollectionDeltaCommitted", STORE_CPP)
        self.assertIn("nextRevision.Value()", STORE_CPP)

    def test_summon_accepts_only_logical_collection_and_server_resolves_spell(self):
        self.assertIn('request.TypeId != MountCollectionTypeId.Value()', PROTOCOL_SCRIPT)
        self.assertIn('request.ActionId != "SUMMON"', PROTOCOL_SCRIPT)
        self.assertIn('request.Target != "-"', PROTOCOL_SCRIPT)
        self.assertIn("GetMountCatalog().Find(collectionId)", SERVICE)
        self.assertIn("GetAccountCollectionCache().IsOwned(account, key)", SERVICE)
        self.assertIn("sSpellMgr->GetSpellInfo(selected->SpellId)", SERVICE)

    def test_summon_prechecks_are_stable_and_never_explicitly_unmount(self):
        for token in (
            '"UNKNOWN_IDENTITY"', '"RACE_RESTRICTED"', '"CLASS_RESTRICTED"',
            '"SKILL_REQUIRED"', '"IN_COMBAT"', '"DEAD"',
            '"IN_VEHICLE"', '"ON_TAXI"', '"INDOORS"',
            '"FLYING_NOT_ALLOWED"', '"MAP_RESTRICTED"',
            '"BATTLEGROUND_RESTRICTED"', '"SHAPESHIFT_RESTRICTED"',
            '"CAST_FAILED"',
        ):
            self.assertIn(token, SERVICE)
        self.assertNotIn("Dismount(", SERVICE)
        self.assertIn("TRIGGERED_IGNORE_CASTER_MOUNTED_OR_ON_VEHICLE", SERVICE)
        self.assertIn("IsActionStatus", PROTOCOL_SERVER)


if __name__ == "__main__":
    unittest.main()
