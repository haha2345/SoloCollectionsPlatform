import hashlib
import json
import os
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
BACKEND_H = (ROOT / "src/SoloCollectionsBackend.h").read_text(encoding="utf-8")
BACKEND = (ROOT / "src/SoloCollectionsBackend.cpp").read_text(encoding="utf-8")
CORE = (ROOT / "src/SoloCollectionsCore.cpp").read_text(encoding="utf-8")
PROTOCOL = (ROOT / "src/SoloCollectionsProtocolScript.cpp").read_text(encoding="utf-8")
STORE = (ROOT / "src/SoloCollectionsAccountStore.cpp").read_text(encoding="utf-8")
SHADOW = (ROOT / "src/SoloCollectionsShadowService.cpp").read_text(encoding="utf-8")
COMPARISON = (ROOT / "src/SoloCollectionsShadowComparison.cpp").read_text(encoding="utf-8")
CONFIG = (ROOT / "conf/transmog.conf.dist").read_text(encoding="utf-8")
GENERATED = json.loads((ROOT / "data/generated/solo_collections_legacy_sc1_shadow.json").read_text(encoding="utf-8"))
ADDON_ROOT = Path(os.environ.get("SOLO_COLLECTIONS_ADDON_ROOT", ROOT.parent / "SoloCollections"))
LUA = ADDON_ROOT / "server" / "ale" / "solo_collections.lua"
LUA_TEXT = LUA.read_text(encoding="utf-8") if LUA.is_file() else ""


class Phase11ShadowContractTests(unittest.TestCase):
    def test_backend_modes_are_explicit_and_compare_is_the_phase_default(self):
        for token in ("Lua = 1", "Compare = 2", "Cpp = 3"):
            self.assertIn(token, BACKEND_H)
        self.assertIn('"SoloCollections.Backend", "Compare"', BACKEND)
        self.assertIn("SoloCollections.Backend = Compare", CONFIG)
        self.assertIn("SoloCollections.ShadowReportPath", CONFIG)
        self.assertIn("fallback=Lua writes_enabled=0 actions_enabled=0", BACKEND)

    def test_compare_mode_keeps_cpp_writes_actions_and_success_deltas_disabled(self):
        self.assertIn("SetWritesEnabled(IsCppBackendOwner())", CORE)
        self.assertIn("if (!_writesEnabled)", STORE)
        self.assertIn("CollectionReasonCode::ReadOnly", STORE)
        self.assertIn("result=shadow_suppressed", STORE)
        self.assertIn("if (!IsCppBackendOwner())\n        return true;", PROTOCOL)
        self.assertIn("if (!IsCppBackendOwner())\n            return;", CORE)
        self.assertIn("writes=0 actions=0 success_deltas=0", SHADOW)

    @unittest.skipUnless(LUA.is_file(), "matching SoloCollections AddOn checkout was not provided")
    def test_backend_modes_have_exactly_one_production_owner(self):
        self.assertIn('GetConfigValue("SoloCollections.Backend")', LUA_TEXT)
        self.assertIn('BACKEND ~= "cpp"', LUA_TEXT)
        self.assertIn('if ENABLED then\n    RegisterServerEvent(30, onAddonMessage)', LUA_TEXT)
        self.assertIn('RegisterServerEvent(30, onRetiredAddonMessage)', LUA_TEXT)
        self.assertIn('UPGRADE_RESPONSE = "UPGRADE_REQUIRED|2"', LUA_TEXT)
        retired = LUA_TEXT.split("local function onRetiredAddonMessage", 1)[1].split("if ENABLED then", 1)[0]
        self.assertIn("sender:SendAddonMessage", retired)
        for forbidden in ("handleModel", "handleSummon", "handlePet", "handleToy", "CharDB", "WorldDB"):
            self.assertNotIn(forbidden, retired)
        self.assertIn("if (GetBackendMode() == BackendMode::Lua)\n            return;", CORE)
        self.assertIn("SetWritesEnabled(IsCppBackendOwner())", CORE)
        self.assertIn("if (!IsCppBackendOwner())\n        return true;", PROTOCOL)

    def test_shadow_login_waits_for_read_only_account_load_and_exports_structured_results(self):
        self.assertIn("ShadowComparisonOnPlayerLogin(player)", CORE)
        self.assertIn("AccountCacheLoadState::Loading", SHADOW)
        self.assertIn("GetAccountCollectionService().OwnedByType", SHADOW)
        self.assertIn("GetAccountCollectionService().Evaluate", SHADOW)
        self.assertIn("event=shadow_compare", SHADOW)
        self.assertIn("event=shadow_difference", SHADOW)
        self.assertIn("solo-collections-shadow.jsonl", BACKEND)
        self.assertIn("std::filesystem::create_directories", SHADOW)
        self.assertIn("result=directory_failed", SHADOW)
        self.assertIn("std::ios::app", SHADOW)
        self.assertIn("catch (...)", SHADOW)
        for forbidden in ("CharacterDatabase", "BeginMutation", "CastSpell", "SendDirectMessage"):
            self.assertNotIn(forbidden, SHADOW)

    @unittest.skipUnless(LUA.is_file(), "matching SoloCollections AddOn checkout was not provided")
    def test_generated_mapping_is_bound_to_the_same_legacy_lua_source(self):
        source = LUA.read_text(encoding="utf-8").replace("\r\n", "\n").replace("\r", "\n")
        self.assertEqual(hashlib.sha256(source.encode("utf-8")).hexdigest(), GENERATED["sourceHash"])
        by_type = {entry["typeKey"]: entry for entry in GENERATED["categories"]}
        self.assertEqual((24, 24), (by_type["mount"]["legacyEntryCount"], by_type["mount"]["mappedEntryCount"]))
        self.assertEqual((24, 24), (by_type["companion"]["legacyEntryCount"], by_type["companion"]["mappedEntryCount"]))
        self.assertEqual((36, 9), (by_type["toy"]["legacyEntryCount"], by_type["toy"]["mappedEntryCount"]))

    def test_comparison_covers_owned_ids_hash_catalog_and_availability(self):
        for token in (
            "CategoryHashMismatchCount", "CatalogMismatchCount", "OwnedMismatchCount",
            "AvailabilityMismatchCount", "LegacyOwnedIds", "CanonicalOwnedIds",
            "ExtraCanonicalOwned", "UnmappedEntryCount",
        ):
            self.assertIn(token, COMPARISON + (ROOT / "src/SoloCollectionsShadowComparison.h").read_text(encoding="utf-8"))


if __name__ == "__main__":
    unittest.main()
