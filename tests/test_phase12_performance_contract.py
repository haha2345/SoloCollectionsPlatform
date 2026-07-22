from __future__ import annotations

import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
CACHE_H = (ROOT / "src" / "SoloCollectionsAccountCache.h").read_text(encoding="utf-8")
STORE_H = (ROOT / "src" / "SoloCollectionsAccountStore.h").read_text(encoding="utf-8")
STORE_CPP = (ROOT / "src" / "SoloCollectionsAccountStore.cpp").read_text(encoding="utf-8")
PROTOCOL_H = (ROOT / "src" / "SoloCollectionsProtocolServer.h").read_text(encoding="utf-8")
PROTOCOL_CPP = (ROOT / "src" / "SoloCollectionsProtocolServer.cpp").read_text(encoding="utf-8")
COMMANDS = (ROOT / "src" / "SoloCollectionsCommands.cpp").read_text(encoding="utf-8")


class Phase12ServerPerformanceContractTests(unittest.TestCase):
    def test_login_query_time_rows_cache_hits_evictions_and_memory_are_measured(self):
        for token in ("LoadQueryCount", "LoadedUnlockRows", "LastLoadMicroseconds", "MaxLoadMicroseconds"):
            self.assertIn(token, STORE_H)
        self.assertIn('event=account_load result=ready', STORE_CPP)
        for token in ("CacheHits", "CacheMisses", "TotalEvictions", "EstimatedBytes"):
            self.assertIn(token, CACHE_H)

    def test_snapshot_chunks_payload_and_send_time_are_measured(self):
        for token in ("SnapshotTransfers", "SnapshotChunks", "SnapshotPayloadBytes", "SentPackets", "SentBytes"):
            self.assertIn(token, PROTOCOL_H)
        self.assertIn("RecordSendBatch", PROTOCOL_CPP)

    def test_duplicate_unlock_retry_and_17k_catalog_baseline_are_visible(self):
        self.assertIn("DuplicateGrantRequests", STORE_H)
        self.assertIn("TransactionRetryAttempts", STORE_H)
        self.assertIn("constexpr std::size_t BenchmarkEntries = 18'190", COMMANDS)
        self.assertIn("constexpr std::size_t ShadowSetRows = 509", COMMANDS)
        self.assertIn("constexpr std::size_t CompanionCandidateRows = 201", COMMANDS)
        self.assertIn('"benchmark", HandleBenchmark', COMMANDS)
        self.assertIn("module.solocollections.performance", COMMANDS)
