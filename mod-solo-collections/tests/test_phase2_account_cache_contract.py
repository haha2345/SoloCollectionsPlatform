import pathlib
import unittest


ROOT = pathlib.Path(__file__).resolve().parents[1]
HEADER = (ROOT / "src" / "SoloCollectionsAccountCache.h").read_text(encoding="utf-8")
SOURCE = (ROOT / "src" / "SoloCollectionsAccountCache.cpp").read_text(encoding="utf-8")
NATIVE = (ROOT / "tests" / "native" / "SoloCollectionsDomainTests.cpp").read_text(encoding="utf-8")


class AccountCacheContractTests(unittest.TestCase):
    def test_state_generation_sessions_and_delayed_eviction_are_explicit(self):
        for token in (
            "AccountCacheLoadState",
            "Loading = 1",
            "Ready = 2",
            "Failed = 3",
            "LoginGeneration",
            "std::set<AccountSessionId> Sessions",
            "EvictAfterMs",
        ):
            self.assertIn(token, HEADER)

    def test_load_callbacks_are_generation_guarded_and_deltas_are_deferred(self):
        self.assertIn("entry->second.Generation != generation", SOURCE)
        self.assertIn("PendingDeltas[delta.Key]", SOURCE)
        self.assertIn("ApplyDelta(entry->second, delta)", SOURCE)
        self.assertIn("DeltaQueueResult::Deferred", SOURCE)

    def test_cache_has_an_explicit_cross_thread_lock_policy(self):
        self.assertIn("mutable std::mutex _mutex", HEADER)
        self.assertIn("std::scoped_lock lock(_mutex)", SOURCE)
        self.assertNotIn("AssertOwnerThread", SOURCE)
        self.assertIn("TestExplicitCrossThreadLocking", NATIVE)

    def test_required_session_races_have_native_coverage(self):
        for test_name in (
            "TestTwoSessionsShareOneLoad",
            "TestLogoutBeforeCallback",
            "TestUnlockDuringLoad",
            "TestRelogAndDelayedEviction",
        ):
            self.assertIn(test_name, NATIVE)


if __name__ == "__main__":
    unittest.main()
