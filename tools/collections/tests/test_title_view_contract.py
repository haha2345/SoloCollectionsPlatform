from __future__ import annotations

import json
import unittest

from common import ADDON, ROOT, read_text


class TitleViewContractTests(unittest.TestCase):
    def test_title_type_is_external_view_only_with_stable_id(self):
        source = json.loads((ROOT / "catalog" / "source" / "collection_types.json").read_text(encoding="utf-8"))
        title = next(entry for entry in source["entries"] if entry["typeKey"] == "title")
        self.assertEqual(15, title["typeId"])
        self.assertEqual("EXTERNAL", title["catalogMode"])
        self.assertEqual("title", title["providerKey"])
        self.assertEqual(["VIEW"], title["features"])

    def test_title_page_uses_native_catalog_and_server_ownership(self):
        text = read_text(ADDON / "UI" / "Titles.lua")
        for token in (
            "GetNumTitles",
            "GetTitleName",
            "IsTitleKnown",
            "GetCurrentTitle",
            'CS.ResolveOwned("TITLES", titleIndex, nativeKnown)',
            "目录可见",
            "未拥有",
            "已拥有",
            "已启用",
            "当前可用",
            "当前不可用",
            "资源已安装",
            "本页不会授予或切换头衔",
        ):
            self.assertIn(token, text)
        for forbidden in ("SetCurrentTitle", "RequestAction", "TryUnlock", ".titles add", ".titles remove"):
            self.assertNotIn(forbidden, text)

    def test_title_page_is_loaded_before_collections_frame(self):
        toc = read_text(ADDON / "SoloCollections.toc")
        self.assertLess(toc.index("UI\\Titles.lua"), toc.index("UI\\CollectionsFrame.lua"))
        frame = read_text(ADDON / "UI" / "CollectionsFrame.lua")
        self.assertIn('key = "TITLES"', frame)
        self.assertIn("TITLES = UI.CreateTitlesPage(contentHost)", frame)


if __name__ == "__main__":
    unittest.main()
