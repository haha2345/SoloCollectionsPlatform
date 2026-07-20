from __future__ import annotations

import re
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
CORE = (ROOT / "src" / "SoloCollectionsCore.cpp").read_text(encoding="utf-8")
COMMANDS = (ROOT / "src" / "SoloCollectionsCommands.cpp").read_text(encoding="utf-8")
STORE_H = (ROOT / "src" / "SoloCollectionsAccountStore.h").read_text(encoding="utf-8")
STORE_CPP = (ROOT / "src" / "SoloCollectionsAccountStore.cpp").read_text(encoding="utf-8")
PROTOCOL_H = (ROOT / "src" / "SoloCollectionsProtocol.h").read_text(encoding="utf-8")
PROTOCOL_SERVER = (ROOT / "src" / "SoloCollectionsProtocolServer.cpp").read_text(encoding="utf-8")
PROTOCOL_SCRIPT = (ROOT / "src" / "SoloCollectionsProtocolScript.cpp").read_text(encoding="utf-8")
GENERATED_VERSIONS = (ROOT / "src" / "generated" / "SoloCollectionsProtocolCatalog.inc").read_text(
    encoding="utf-8"
)


class Phase12HealthContractTests(unittest.TestCase):
    def test_startup_reports_authoritative_versions(self):
        self.assertIn("AccountStoreSchemaVersion", STORE_H)
        self.assertIn("Sc2ProtocolVersion", PROTOCOL_H)
        for token in (
            "GeneratedCatalogVersion",
            "GeneratedIdentityVersion",
            "GeneratedSc2AssetPackVersion",
        ):
            self.assertIn(token, GENERATED_VERSIONS)
        self.assertIn("event=startup_versions schema={} catalog={} identity={} protocol={} asset={}", CORE)
        self.assertIn("Sc2ProtocolVersion", PROTOCOL_SERVER)
        self.assertNotIn("message.ProtocolVersion != 1", PROTOCOL_SERVER)

    def test_status_exposes_provider_cache_and_pending_write_health(self):
        for token in (
            "providers_ready={}",
            "providers_readonly={}",
            "providers_disabled={}",
            "online_accounts={}",
            "cache_entries={}",
            "pending_writes={}",
        ):
            self.assertIn(token, COMMANDS)
        self.assertIn("store.PendingMutations + store.PendingAudits", COMMANDS)
        self.assertIn("store.PendingMigrationMarkers", COMMANDS)

    def test_failures_use_distinct_log_categories(self):
        self.assertIn('LOG_ERROR("module.solocollections.database"', STORE_CPP)
        self.assertIn('LOG_ERROR("module.solocollections.catalog"', CORE)
        self.assertIn('LOG_ERROR("module.solocollections.provider"', CORE)
        self.assertIn('LOG_WARN("module.solocollections.protocol"', PROTOCOL_SCRIPT)

    def test_logs_do_not_emit_client_text_snapshots_or_credentials(self):
        sources = "\n".join((CORE, STORE_CPP, PROTOCOL_SCRIPT))
        log_calls = re.findall(r"LOG_(?:TRACE|DEBUG|INFO|WARN|ERROR|FATAL)\(.*?\);", sources, re.DOTALL)
        self.assertTrue(log_calls)
        joined = "\n".join(log_calls)
        for forbidden in (
            "request.ActionId",
            "request.Target",
            "request.Payload",
            "message.c_str",
            "body.data",
            "payload={}",
            "ClientNonce",
            "SessionNonce",
        ):
            self.assertNotIn(forbidden, joined)
        lowered = joined.lower()
        self.assertNotIn("password", lowered)
        self.assertNotIn("credential", lowered)


if __name__ == "__main__":
    unittest.main()
