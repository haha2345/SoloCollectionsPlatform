import pathlib
import unittest


ROOT = pathlib.Path(__file__).resolve().parents[1]
HEADER = (ROOT / "src" / "SoloCollectionsAccountStore.h").read_text(encoding="utf-8")
SOURCE = (ROOT / "src" / "SoloCollectionsAccountStore.cpp").read_text(encoding="utf-8")
CORE = (ROOT / "src" / "SoloCollectionsCore.cpp").read_text(encoding="utf-8")


class AsyncAccountStoreContractTests(unittest.TestCase):
    def test_load_and_commit_use_confirmed_async_database_apis(self):
        self.assertIn("CharacterDatabase.AsyncQuery", SOURCE)
        self.assertIn("CharacterDatabase.AsyncCommitTransaction", SOURCE)
        self.assertIn("callback.AfterComplete", SOURCE)
        self.assertIn("TransactionCallback", SOURCE)

    def test_callbacks_capture_identifiers_and_never_raw_players(self):
        self.assertIn("accountId = load.Account", SOURCE)
        self.assertIn("playerGuid = load.PlayerGuid", SOURCE)
        self.assertIn("generation = load.Generation", SOURCE)
        self.assertNotIn("Player*", HEADER + SOURCE)
        self.assertNotIn("WorldSession*", HEADER + SOURCE)

    def test_revision_unlock_and_audit_share_one_transaction(self):
        self.assertIn("CharacterDatabaseTransaction transaction", SOURCE)
        self.assertIn("SET revision = IF(revision = {}", SOURCE)
        self.assertIn("sc_collection_unlock", SOURCE)
        self.assertIn("sc_collection_audit", SOURCE)
        self.assertIn("nextRevision.Value()", SOURCE)
        self.assertIn("_pendingMutations.contains(mutation.Account)", SOURCE)

    def test_cache_and_event_sink_only_update_after_commit_success(self):
        callback = SOURCE.split("callback.AfterComplete", 1)[1]
        success = callback.split("if (!committed)", 1)[1]
        self.assertLess(success.index("QueueDelta"), success.index("OnCollectionDeltaCommitted"))
        self.assertIn("OnCollectionMutationFailed", success)

    def test_login_logout_and_world_update_drive_the_store(self):
        self.assertIn("PLAYERHOOK_ON_LOGIN", CORE)
        self.assertIn("PLAYERHOOK_ON_LOGOUT", CORE)
        self.assertIn("GetAccountCollectionStore().BeginLoad", CORE)
        self.assertIn("GetAccountCollectionStore().Update", CORE)
        self.assertIn("EvictExpired", CORE)


if __name__ == "__main__":
    unittest.main()
