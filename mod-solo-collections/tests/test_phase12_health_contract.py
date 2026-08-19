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

    def test_collection_sources_do_not_emit_server_logs(self):
        sources = "\n".join((CORE, STORE_CPP, PROTOCOL_SCRIPT, PROTOCOL_SERVER))
        self.assertFalse(re.search(r"LOG_(?:TRACE|DEBUG|INFO|WARN|ERROR|FATAL)\s*\(", sources))


if __name__ == "__main__":
    unittest.main()
