from __future__ import annotations

import re
import unittest
from copy import deepcopy

from common import ADDON, extract_int, parse_lua_records, read_text


EXPECTED = {
    "Mounts.lua": (24, ("id", "creatureId", "spellId", "name", "icon", "source", "description", "collected", "favorite")),
    "Pets.lua": (24, ("id", "creatureId", "spellId", "name", "icon", "source", "description", "collected", "favorite")),
    "Toys.lua": (36, ("id", "itemId", "spellId", "name", "icon", "source", "description", "collected", "favorite")),
    "Appearances.lua": (70, ("id", "itemId", "slot", "classMask", "name", "icon", "source", "collected", "favorite")),
    "Sets.lua": (8, ("id", "classToken", "name", "icon", "itemIds", "collected", "favorite")),
}


CLASS_BITS = {
    "WARRIOR": 1,
    "PALADIN": 2,
    "HUNTER": 4,
    "ROGUE": 8,
    "PRIEST": 16,
    "DEATHKNIGHT": 32,
    "SHAMAN": 64,
    "MAGE": 128,
    "WARLOCK": 256,
    "DRUID": 1024,
}


class CatalogModel:
    """Executable specification mirrored by Core/Catalog.lua."""

    DEFAULT_FILTERS = {
        "collected": True,
        "uncollected": True,
        "favorites": False,
        "classToken": "ALL",
        "slot": "ALL",
    }

    def __init__(self, records):
        self.source = deepcopy(records)
        self.favorite_overrides = {}

    def get(self):
        result = deepcopy(self.source)
        for record in result:
            if record["id"] in self.favorite_overrides:
                record["favorite"] = self.favorite_overrides[record["id"]]
        return result

    @staticmethod
    def _class_matches(record, class_token):
        if not class_token or class_token == "ALL":
            return True
        if "classToken" in record:
            return record["classToken"] == class_token
        class_bit = CLASS_BITS.get(class_token)
        return bool(class_bit and record.get("classMask", 0) & class_bit)

    def query(self, query="", filters=None, page=1, page_size=18, category="APPEARANCES"):
        filters = {**self.DEFAULT_FILTERS, **(filters or {})}
        needle = query.casefold().strip()
        matches = []
        for source_index, record in enumerate(self.get()):
            if record["collected"] and not filters["collected"]:
                continue
            if not record["collected"] and not filters["uncollected"]:
                continue
            if filters["favorites"] and not record["favorite"]:
                continue
            if category == "SETS" and not self._class_matches(record, filters["classToken"]):
                continue
            if category == "APPEARANCES" and filters["slot"] != "ALL" and record.get("slot") != filters["slot"]:
                continue
            haystack = " ".join(
                str(record.get(field, "")) for field in ("name", "source", "description")
            ).casefold()
            if needle and needle not in haystack:
                continue
            matches.append((source_index, record))

        # Source position is the final tie breaker, so filtering never scrambles rows.
        matches.sort(key=lambda pair: pair[0])
        page_size = max(1, int(page_size or 1))
        total = len(matches)
        total_pages = max(1, (total + page_size - 1) // page_size)
        page = max(1, min(int(page or 1), total_pages))
        start = (page - 1) * page_size
        return [record for _, record in matches[start : start + page_size]], page, total_pages, total

    def progress(self, filters=None, category="APPEARANCES"):
        filters = {**self.DEFAULT_FILTERS, **(filters or {})}
        filters["collected"] = True
        filters["uncollected"] = True
        records, _, _, total = self.query("", filters, 1, 10_000, category=category)
        return sum(1 for record in records if record["collected"]), total

    def toggle_favorite(self, record_id):
        record = next(record for record in self.get() if record["id"] == record_id)
        value = not record["favorite"]
        self.favorite_overrides[record_id] = value
        return value

    @classmethod
    def reset_filters(cls):
        return deepcopy(cls.DEFAULT_FILTERS)


MODEL_RECORDS = [
    {"id": 1, "name": "Azure Drake", "source": "Eye", "description": "Blue", "collected": True, "favorite": False, "classMask": 128, "slot": "HEAD"},
    {"id": 2, "name": "奥术师头冠", "source": "熔火之心", "description": "法师", "collected": False, "favorite": True, "classMask": 128, "slot": "HEAD"},
    {"id": 3, "name": "力量胸甲", "source": "熔火之心", "description": "战士", "collected": True, "favorite": True, "classMask": 1, "slot": "CHEST"},
    {"id": 4, "name": "Night Slayer", "source": "Molten Core", "description": "Rogue", "collected": False, "favorite": False, "classMask": 8, "slot": "HANDS"},
]


class CatalogContractTests(unittest.TestCase):
    def test_exact_counts_unique_ids_and_required_fields(self):
        for filename, (count, fields) in EXPECTED.items():
            path = ADDON / "Data" / filename
            self.assertTrue(path.is_file(), f"missing {path}")
            records = parse_lua_records(path)
            self.assertEqual(count, len(records), filename)
            ids = [extract_int(record, "id") for record in records]
            self.assertNotIn(None, ids, filename)
            self.assertEqual(len(ids), len(set(ids)), filename)
            for record in records:
                for field in fields:
                    self.assertRegex(record, rf"\b{re.escape(field)}\s*=", f"{filename}: {field}")

    def test_every_category_has_collected_and_uncollected_records(self):
        for filename in EXPECTED:
            path = ADDON / "Data" / filename
            self.assertTrue(path.is_file(), f"missing {path}")
            records = parse_lua_records(path)
            states = {
                match.group(1)
                for record in records
                if (match := re.search(r"\bcollected\s*=\s*(true|false)", record))
            }
            self.assertEqual({"true", "false"}, states, filename)

    def test_every_record_has_a_nonempty_chinese_fallback_name(self):
        for filename in EXPECTED:
            path = ADDON / "Data" / filename
            self.assertTrue(path.is_file(), f"missing {path}")
            for record in parse_lua_records(path):
                match = re.search(r'\bname\s*=\s*"([^"]+)"', record)
                self.assertIsNotNone(match, f"missing name in {filename}: {record}")
                self.assertRegex(match.group(1), r"[\u4e00-\u9fff]", filename)

    def test_sets_have_multiple_item_ids(self):
        path = ADDON / "Data" / "Sets.lua"
        self.assertTrue(path.is_file(), f"missing {path}")
        for record in parse_lua_records(path):
            match = re.search(r"\bitemIds\s*=\s*\{([^}]*)\}", record)
            self.assertIsNotNone(match)
            item_ids = [int(value) for value in re.findall(r"\d+", match.group(1))]
            self.assertGreaterEqual(len(item_ids), 4, record)

    def test_lua_catalog_exposes_the_phase_one_service_contract(self):
        source = (ADDON / "Core" / "Catalog.lua").read_text(encoding="utf-8")
        for signature in (
            "function Catalog.Get(category)",
            "function Catalog.QueryAll(category, query, filters)",
            "function Catalog.Query(category, query, filters, page, pageSize)",
            "function Catalog.GetProgress(category, filters)",
            "function Catalog.ToggleDemoFavorite(category, id)",
            "function Catalog.ResetFilters(category)",
        ):
            self.assertIn(signature, source)
        self.assertIn("SoloCollectionsDB.favorites", source)
        self.assertNotIn("table.remove(source", source)
        self.assertNotIn("table.sort(source", source)

    def test_lua_catalog_query_all_is_the_unpaged_source_for_paged_queries(self):
        source = (ADDON / "Core" / "Catalog.lua").read_text(encoding="utf-8")
        query_all_start = source.find("function Catalog.QueryAll(category, query, filters)")
        self.assertGreaterEqual(query_all_start, 0, "missing Catalog.QueryAll")
        query_start = source.index("function Catalog.Query(category, query, filters, page, pageSize)")
        progress_start = source.index("function Catalog.GetProgress(category, filters)")
        query_all = source[query_all_start:query_start]
        query = source[query_start:progress_start]
        self.assertIn("return matches", query_all)
        self.assertNotIn("pageSize", query_all)
        self.assertIn("local matches = Catalog.QueryAll(category, query, filters)", query)

    def test_lua_catalog_repairs_malformed_saved_favorite_tables(self):
        source = (ADDON / "Core" / "Catalog.lua").read_text(encoding="utf-8")
        self.assertIn('if type(SoloCollectionsDB) ~= "table" then', source)
        self.assertIn('if type(SoloCollectionsDB.favorites) ~= "table" then', source)
        self.assertIn('if type(SoloCollectionsDB.favorites[category]) ~= "table" then', source)
        self.assertIn('if type(database) ~= "table" then', source)
        self.assertIn('if type(categories) ~= "table" then', source)
        self.assertIn('if type(overrides) ~= "table" then', source)

    def test_lua_catalog_never_exposes_or_enables_uncollected_companion_favorites(self):
        source = read_text(ADDON / "Core" / "Catalog.lua")
        get_favorite = source[
            source.index("local function getFavorite") : source.index("local function resolvedFilters")
        ]
        toggle = source[
            source.index("function Catalog.ToggleDemoFavorite") : source.index("function Catalog.ResetFilters")
        ]
        guard = 'isCollectibleCompanion(category) and not record.collected'
        self.assertIn('category == "MOUNTS" or category == "PETS"', source)
        self.assertIn(guard, get_favorite)
        self.assertIn(guard, toggle)
        self.assertIn("ensureFavoriteStore(category)[id] = false", toggle)

    def test_lua_catalog_scopes_wardrobe_filters_to_wardrobe_categories(self):
        source = (ADDON / "Core" / "Catalog.lua").read_text(encoding="utf-8")
        self.assertIn('local usesClassFilter = category == "SETS"', source)
        self.assertIn('category == "APPEARANCES" and filters.slot', source)
        self.assertIn('category == "APPEARANCES" and not armorTypeMatches', source)
        self.assertIn('category == "APPEARANCES" and not weaponTypeMatches', source)

    def test_shared_controls_define_popup_dismissal_and_empty_page_cleanup(self):
        source = (ADDON / "UI" / "Templates.lua").read_text(encoding="utf-8")
        self.assertIn("UI.scFilterPopupSerial", source)
        self.assertIn('local popupName = "SoloCollectionsFilterPopup" .. serial', source)
        self.assertIn('local dismissName = "SoloCollectionsFilterDismiss" .. serial', source)
        self.assertIn('CreateFrame("Button", dismissName, UIParent)', source)
        self.assertIn("registerSpecialFrameOnce(popupName)", source)
        self.assertIn("function UI.ShowEmptyState(state, page, message, detail)", source)
        self.assertIn("page:ClearSelection()", source)
        self.assertIn("page.scModel:ClearModel()", source)

    def test_model_search_is_case_insensitive_for_ascii_and_preserves_chinese(self):
        model = CatalogModel(MODEL_RECORDS)
        self.assertEqual([1], [r["id"] for r in model.query("aZuRe")[0]])
        self.assertEqual([2, 3], [r["id"] for r in model.query("熔火")[0]])

    def test_model_collection_favorite_class_and_slot_filters(self):
        model = CatalogModel(MODEL_RECORDS)
        self.assertEqual([1, 3], [r["id"] for r in model.query(filters={"uncollected": False})[0]])
        self.assertEqual([2, 4], [r["id"] for r in model.query(filters={"collected": False})[0]])
        self.assertEqual([2, 3], [r["id"] for r in model.query(filters={"favorites": True})[0]])
        self.assertEqual(
            [1, 2],
            [r["id"] for r in model.query(filters={"classToken": "MAGE"}, category="SETS")[0]],
        )
        self.assertEqual([1, 2], [r["id"] for r in model.query(filters={"slot": "HEAD"})[0]])

    def test_model_non_wardrobe_query_ignores_saved_class_and_slot_filters(self):
        companions = [
            {"id": 1, "name": "坐骑甲", "collected": True, "favorite": False},
            {"id": 2, "name": "坐骑乙", "collected": False, "favorite": False},
        ]
        model = CatalogModel(companions)
        records, _, _, total = model.query(
            filters={"classToken": "MAGE", "slot": "HEAD"}, category="MOUNTS"
        )
        self.assertEqual(([1, 2], 2), ([record["id"] for record in records], total))

    def test_model_stable_order_page_clamping_and_fresh_results(self):
        model = CatalogModel(MODEL_RECORDS)
        first, page, pages, total = model.query(page=99, page_size=2)
        self.assertEqual(([3, 4], 2, 2, 4), ([r["id"] for r in first], page, pages, total))
        first[0]["name"] = "mutated copy"
        self.assertEqual("力量胸甲", model.get()[2]["name"])

    def test_model_progress_toggle_and_reset(self):
        model = CatalogModel(MODEL_RECORDS)
        self.assertEqual((2, 4), model.progress())
        self.assertEqual((1, 2), model.progress({"classToken": "MAGE"}, category="SETS"))
        self.assertTrue(model.toggle_favorite(1))
        self.assertTrue(model.get()[0]["favorite"])
        self.assertEqual(CatalogModel.DEFAULT_FILTERS, model.reset_filters())

    def test_model_all_collection_filters_off_and_zero_results(self):
        model = CatalogModel(MODEL_RECORDS)
        records, page, pages, total = model.query(
            filters={"collected": False, "uncollected": False}, page=9, page_size=2
        )
        self.assertEqual(([], 1, 1, 0), (records, page, pages, total))
        self.assertEqual(([], 1, 1, 0), model.query("不存在", page=5, page_size=2))


if __name__ == "__main__":
    unittest.main()
