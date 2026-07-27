from __future__ import annotations

import unittest

from common import ADDON, read_text


CATALOG = read_text(ADDON / "Core" / "Catalog.lua")
DIAGNOSTICS = read_text(ADDON / "Core" / "Diagnostics.lua")
WARDROBE = read_text(ADDON / "UI" / "Wardrobe.lua")


class Phase12ClientPerformanceContractTests(unittest.TestCase):
    def test_real_client_baseline_covers_every_page_search_paging_and_17k_scale(self):
        self.assertIn("Diagnostics.RunPerformanceBaseline", DIAGNOSTICS)
        self.assertIn('"MOUNTS", "PETS", "TOYS", "WARDROBE", "TITLES"', DIAGNOSTICS)
        self.assertIn("RunSyntheticAppearanceBenchmark(18190)", DIAGNOSTICS)
        self.assertIn("RunExpandedCollectionBenchmark(18190, 201, 509)", DIAGNOSTICS)
        self.assertIn("SC_PERF expanded appearances=%d companions=%d sets=%d", DIAGNOSTICS)
        self.assertIn("filterMs", CATALOG)
        self.assertIn("pageMs", CATALOG)

    def test_snapshot_reassembly_is_bounded_and_reports_memory(self):
        self.assertIn("bytes + added > 32000", DIAGNOSTICS)
        self.assertIn("for offset = 1, #payload, 160", DIAGNOSTICS)
        self.assertIn("parseOwnedPayload(reassembled)", DIAGNOSTICS)
        self.assertIn("peakMemoryKb", DIAGNOSTICS)

    def test_model_pool_is_fixed_and_hidden_work_is_observed(self):
        self.assertIn("modelPool = poolSize", DIAGNOSTICS)
        self.assertIn('model:GetScript("OnUpdate")', DIAGNOSTICS)
        self.assertIn('itemModel:SetScript("OnUpdate", nil)', WARDROBE)
        self.assertNotIn('SetScript("OnUpdate"', DIAGNOSTICS)
