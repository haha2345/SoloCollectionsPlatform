import pathlib
import unittest


ROOT = pathlib.Path(__file__).resolve().parents[1]
SOURCE = (ROOT / "src" / "SoloCollectionsCommands.cpp").read_text(encoding="utf-8")
STORE = (ROOT / "src" / "SoloCollectionsAccountStore.cpp").read_text(encoding="utf-8")
LOADER = (ROOT / "src" / "transmog_loader.cpp").read_text(encoding="utf-8")
RBAC = (ROOT / "data" / "sql" / "db-auth" / "solo_collections_rbac.sql").read_text(encoding="utf-8")


class DiagnosticsAndAdminCommandContractTests(unittest.TestCase):
    def test_all_required_commands_are_registered(self):
        for name in (
            '"status"',
            '"account"',
            '"grant"',
            '"revoke"',
            '"reload"',
            '"resync"',
            '"import"',
            '"reconcile"',
        ):
            self.assertIn(name, SOURCE)
        self.assertIn('"solocollections"', SOURCE)
        self.assertIn("AddSC_solo_collections_commands", LOADER)

    def test_write_commands_use_module_rbac_and_defense_in_depth(self):
        self.assertIn("RBAC_SC_WRITE = 71052", SOURCE)
        self.assertIn("handler->HasPermission(RBAC_SC_WRITE)", SOURCE)
        self.assertGreaterEqual(SOURCE.count("RBAC_SC_WRITE"), 4)
        for permission in range(71050, 71055):
            self.assertIn(str(permission), RBAC)
        self.assertIn("rbac_linked_permissions", RBAC)

    def test_rejected_and_successful_writes_are_audited(self):
        self.assertIn("RecordRejectedMutation", SOURCE)
        self.assertIn("sc_collection_audit", STORE)
        self.assertIn("ToStableReasonCode(reason)", STORE)
        self.assertIn("revision, result_code", STORE)

    def test_unknown_ids_and_database_not_ready_fail_closed(self):
        self.assertIn("CollectionReasonCode::UnknownType", SOURCE)
        self.assertIn("CollectionReasonCode::UnknownCollection", SOURCE)
        self.assertIn("AccountCacheLoadState::Ready", SOURCE)
        self.assertIn("IsSchemaReady", SOURCE)
        self.assertIn("--dry-run", SOURCE)
        self.assertIn("writes=0", SOURCE)


if __name__ == "__main__":
    unittest.main()
