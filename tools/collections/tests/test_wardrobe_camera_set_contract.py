from __future__ import annotations

import re
import unittest
from pathlib import Path

from common import ADDON, ROOT, load_json, read_text


MEDIA_MANIFEST = ADDON / "Media" / "assets.json"
TEMPLATES = ADDON / "UI" / "Templates.lua"
WARDROBE = ADDON / "UI" / "Wardrobe.lua"
EZ_WARDROBE_MODEL = ADDON / "UI" / "EzWardrobe" / "Model.lua"
TRANSMORPHER_SETUP = ADDON / "Data" / "TransmorpherPreviewSetup.lua"
PRESENTATIONS = ROOT / "tools" / "catalog" / "appearance_presentations.py"
NEW_BUNDLE = ROOT / "tools" / "release" / "New-RoundTwoBundle.ps1"
TEST_BUNDLE = ROOT / "tools" / "release" / "Test-RoundTwoBundle.ps1"
RELEASE_COMMON = ROOT / "tools" / "release" / "RoundTwoRelease.Common.ps1"


class WardrobeCameraSetContractTests(unittest.TestCase):
    def test_armor_uses_transmorpher_setup_for_every_supported_wardrobe_slot(self):
        model = read_text(EZ_WARDROBE_MODEL)
        setup = read_text(TRANSMORPHER_SETUP)
        slot_names = {
            "HEAD": "Head",
            "SHOULDER": "Shoulder",
            "BACK": "Back",
            "CHEST": "Chest",
            "WRIST": "Wrist",
            "HANDS": "Hands",
            "WAIST": "Waist",
            "LEGS": "Legs",
            "FEET": "Feet",
        }
        for stable_slot, transmorpher_slot in slot_names.items():
            self.assertIn(f'{stable_slot} = "{transmorpher_slot}"', model)
            self.assertEqual(20, setup.count(f'["{transmorpher_slot}"] = {{'))
        self.assertIn('local armorData = raceData["Armor"]', model)
        self.assertIn('return armorData[slotName], slotName, "READY"', model)

    def test_armor_follows_the_transmorpher_reset_and_render_order(self):
        source = read_text(EZ_WARDROBE_MODEL)
        block = source[
            source.index("function WardrobeItemsModelMixin:RenderTransmorpherArmor") :
            source.index("function WardrobeItemsModelMixin:RenderTransmorpherItem")
        ]
        expected_order = [
            "PrepareTransmorpherFrame",
            'safeCall(self.frame, "Undress")',
            'safeCall(self.frame, "SetPosition"',
            'safeCall(self.frame, "SetFacing"',
            'safeCall(self.frame, "TryOn"',
            'safeCall(self.frame, "SetSequence"',
        ]
        positions = [block.index(token) for token in expected_order]
        self.assertEqual(positions, sorted(positions))
        self.assertNotIn("NativePreview", block)
        self.assertNotIn("SetSequenceTime", source)
        self.assertNotIn("ApplyArmorCamera", source)
        self.assertNotIn('SetModelScale", 10', source)

    def test_all_item_cards_share_transmorpher_query_and_generation_queue(self):
        source = read_text(EZ_WARDROBE_MODEL)
        self.assertIn("local ItemQuery = SC.TransmorpherItemQuery", source)
        self.assertIn("ItemQuery:Query(record.itemId, onItemReady)", source)
        self.assertIn("queueItemRender(self, self.record, expectedGeneration)", source)
        self.assertIn('and "TRANSMORPHER_ARMOR" or "TRANSMORPHER_WEAPON"', source)
        self.assertIn("target:RenderTransmorpherItem(target.record)", source)

    def test_base_ui_media_is_explicitly_required_and_tracked(self):
        manifest = load_json(MEDIA_MANIFEST)
        required = manifest.get("requiredForBaseUI")
        self.assertIsInstance(required, dict)
        self.assertEqual(
            {"launcher", "mountPortrait", "wardrobeSlotAtlas", "roundHighlightAtlas"},
            set(required),
        )
        external = set(manifest.get("externalFiles", {}))
        for role, entry in required.items():
            self.assertIsInstance(entry, dict, role)
            relative = entry.get("path")
            self.assertIsInstance(relative, str, role)
            self.assertTrue((ADDON / "Media" / relative).is_file(), role)
            self.assertNotIn(relative, external, role)
            self.assertRegex(entry.get("sha256", ""), r"^[A-F0-9]{64}$", role)

    def test_production_media_paths_resolve_to_required_base_ui_assets(self):
        manifest = load_json(MEDIA_MANIFEST)
        required = manifest.get("requiredForBaseUI", {})
        expected = {role: entry["path"].replace("/", "\\\\") for role, entry in required.items()}
        source = read_text(TEMPLATES)
        for role, relative in expected.items():
            match = re.search(rf'^\s*{role}\s*=\s*MEDIA_ROOT\s*\.\.\s*"([^"]+)"', source, re.M)
            self.assertIsNotNone(match, role)
            self.assertEqual(relative, match.group(1), role)
        self.assertNotIn('MEDIA_ROOT .. "Retail\\', source)

    def test_bundle_tools_validate_required_media_after_assembly(self):
        new_bundle_source = read_text(NEW_BUNDLE)
        test_bundle_source = read_text(TEST_BUNDLE)
        common_source = read_text(RELEASE_COMMON)
        self.assertIn("Assert-RoundTwoBaseMedia", new_bundle_source)
        self.assertIn("Assert-RoundTwoBaseMedia", test_bundle_source)
        self.assertIn("requiredForBaseUI", common_source)
        self.assertIn("optionalExternalFiles", common_source)

    def test_set_scroll_uses_a_direct_offset_slider_mapping(self):
        source = read_text(WARDROBE)
        self.assertNotIn("maxOffset - page.scSetOffset", source)
        callback = re.search(
            r'setScrollbar:SetScript\("OnValueChanged",\s*function\(self, value\)(.*?)\n\s*end\)',
            source,
            re.S,
        )
        self.assertIsNotNone(callback)
        self.assertIn("setSetOffset(value)", callback.group(1))

    def test_set_scroll_inputs_share_the_single_offset_state_transition(self):
        source = read_text(WARDROBE)
        helper = re.search(
            r"local function scrollSetList\(delta\)(.*?)(?=\n\s*local setScrollbar)",
            source,
            re.S,
        )
        self.assertIsNotNone(helper)
        self.assertIn("setSetOffset(", helper.group(1))
        self.assertNotIn("page.scSetOffset =", helper.group(1))
        self.assertIn("setSetOffset((page.scSetOffset or 0) - VISIBLE_SET_ROWS)", source)
        self.assertIn("setSetOffset((page.scSetOffset or 0) + VISIBLE_SET_ROWS)", source)

    def test_set_scroll_clamps_filter_resets_and_last_partial_page_in_one_transition(self):
        source = read_text(WARDROBE)
        setter = re.search(
            r"setSetOffset\s*=\s*function\(value, suppressRefresh\)(.*?)(?=\n\s*local function scrollSetList)",
            source,
            re.S,
        )
        self.assertIsNotNone(setter)
        block = setter.group(1)
        self.assertIn("math.max(0, math.min", block)
        self.assertIn("getMaxSetOffset()", block)
        self.assertIn("math.floor(target / VISIBLE_SET_ROWS) + 1", block)
        self.assertGreaterEqual(source.count("setSetOffset(0, true)"), 5)
        self.assertNotIn("page.scSetOffset = math.max", source)
        self.assertIn("setSetOffset(page.scSetOffset, true)", source)
        self.assertIn("setScrollbar:SetValue(page.scSetOffset)", source)

    def test_set_preview_is_generation_aware_and_undresses_before_tryon(self):
        source = read_text(WARDROBE)
        self.assertIn("scSetPreviewGeneration", source)
        queued = re.search(r"local function queueSetPreview\(record\)(.*?)(?=\n\s*local function previewSet)", source, re.S)
        self.assertIsNotNone(queued)
        block = queued.group(1)
        self.assertIn("Undress", block)
        self.assertIn("TryOn", block)
        self.assertLess(block.index("Undress"), block.index("TryOn"))
        self.assertIn("scSetPreviewGeneration", block)

    def test_set_preview_uses_only_the_selected_variant_members(self):
        source = read_text(WARDROBE)
        helper = re.search(
            r"local function getSelectedVariantPreviewItems\(record\)(.*?)(?=\n\s*local function)",
            source,
            re.S,
        )
        self.assertIsNotNone(helper)
        self.assertIn("record.selectedVariant", helper.group(1))
        self.assertIn("previewSourceItemId", helper.group(1))
        self.assertIn("getSelectedVariantPreviewItems(record)", source)

    def test_set_preview_rejects_stale_work_and_cleans_pending_state(self):
        source = read_text(WARDROBE)
        queued = re.search(r"local function queueSetPreview\(record\)(.*?)(?=\n\s*local function previewSet)", source, re.S)
        self.assertIsNotNone(queued)
        block = queued.group(1)
        self.assertIn("pending.renderTicks < 2", block)
        self.assertIn('SC.db.wardrobeTab ~= "SETS"', block)
        self.assertIn("page.scSetPreviewPending ~= pending", block)
        self.assertIn("page.scSetPreviewGeneration ~= pending.generation", block)
        self.assertIn("local function cancelSetPreview()", source)
        self.assertIn("cancelSetPreview()", source[source.index("local function refreshItems()"):])
        self.assertIn('page:RegisterEvent("UNIT_MODEL_CHANGED")', source)
        self.assertIn('page:RegisterEvent("PLAYER_ENTERING_WORLD")', source)

    def test_set_preview_selects_one_deterministic_source_per_member_slot(self):
        source = read_text(WARDROBE)
        helper = re.search(
            r"local function getSelectedVariantPreviewItems\(record\)(.*?)(?=\n\s*local function)",
            source,
            re.S,
        )
        self.assertIsNotNone(helper)
        block = helper.group(1)
        self.assertIn("seenSlots", block)
        self.assertIn("member.sourceItemIds", block)
        self.assertIn("previewSourceItemId", block)
        self.assertIn("SET_MEMBER_SLOT_ORDER", block)
        self.assertIn("table.sort(result", block)

    def test_set_preview_preallocates_a_bounded_pool_for_nine_piece_variants(self):
        source = read_text(WARDROBE)
        self.assertIn("local SET_PIECE_POOL_LIMIT = 12", source)
        self.assertIn("local piecePoolSize = SET_PIECE_POOL_LIMIT", source)
        self.assertNotIn("local piecePoolSize = maxActiveSetSlots()", source)

    def test_standalone_validation_is_registry_based_not_a_fixed_21_id_range(self):
        source = read_text(PRESENTATIONS)
        wardrobe = read_text(WARDROBE)
        self.assertNotIn("len(entries) == 21", source)
        self.assertNotIn("set(range(40000, 40021))", source)
        self.assertIn("registry", source.lower())
        self.assertNotIn("record.syntheticDisplayId >= 40000", wardrobe)
        self.assertNotIn("record.syntheticDisplayId <= 40020", wardrobe)
        self.assertIn('record.presentationCapability == "DIRECT_DISPLAY_V1"', wardrobe)
        self.assertIn("hasAssetPackVersionMismatch", wardrobe)
        self.assertIn("record.assetPackVersion ~= generatedAssetPackVersion", wardrobe)
        self.assertIn("资源包版本不匹配", wardrobe)

    def test_weapon_grid_uses_a_fixed_pool_with_generation_safe_direct_models(self):
        source = read_text(WARDROBE)
        self.assertIn("local ITEM_PAGE_SIZE = ITEM_ROWS * ITEM_COLUMNS", source)
        self.assertIn("for index = 1, ITEM_PAGE_SIZE do", source)
        self.assertIn("page.scItemGeneration = (page.scItemGeneration or 0) + 1", source)
        self.assertIn("model.scStandaloneGeneration", source)
        self.assertIn("isStandaloneItemGenerationCurrent", source)
        self.assertIn("applyStandaloneItemRecord(objectModel, nil, pageGeneration)", source)

    def test_runtime_audit_drives_the_production_card_pool_without_a_second_renderer(self):
        source = read_text(WARDROBE)
        audit = read_text(ROOT / "tools" / "runtime" / "SoloCollectionsWeaponPresentationAudit" / "WeaponPresentationAudit.lua")
        self.assertIn("function page:LoadRuntimeAuditAppearanceRecords(records)", source)
        self.assertIn("AUDIT_RECORD_COUNT_EXCEEDS_CARD_POOL", source)
        self.assertIn("applyItemModelRecord(itemModel, record, pageGeneration)", source)
        self.assertIn("SC.Catalog.QueryAll(\"APPEARANCES\"", audit)
        self.assertIn("LoadRuntimeAuditAppearanceRecords(records)", audit)
        self.assertIn("#(state.page.scItemModels or {}) ~= 18", audit)
        self.assertIn("STABLE_TICKS = 3", audit)
        self.assertIn("UNAVAILABLE_CARD_INVALID", audit)
        self.assertIn('state.phase = "preflight"', audit)
        self.assertIn("if DATA.autoLogout then", audit)
        self.assertIn('state.phase = "reloadWait"', audit)
        self.assertIn("RELOAD_TIMEOUT_SECONDS = 120.0", audit)
        self.assertIn("db.reloadLoginCount", audit)
        self.assertIn('db.reloadBoundary = "PLAYER_LOGIN"', audit)
        self.assertIn("RELOAD_NOT_OBSERVED_WITHIN_TIMEOUT", audit)
        self.assertIn("VISUAL_SCREENSHOT_SETTLE_DELAY = 2.0", audit)
        self.assertIn("LoadRuntimeAuditAppearanceRecords", audit)
        self.assertIn("MAX_PERFORMANCE_ROUNDS = 3", audit)
        self.assertIn("performancePageCsv", audit)
        self.assertIn("performanceRoundCsv", audit)
        self.assertIn("poolOnUpdateCounts", audit)
        self.assertIn("beginNextPerformanceRound", audit)
        self.assertIn("beginPerformanceFilterScenarios", audit)
        self.assertIn("FILTER_RECORD_CROSS_CONTAMINATION", audit)
        self.assertIn("FILTER_RAPID_GENERATION_NOT_OBSERVED", audit)
        self.assertNotIn('CreateFrame("PlayerModel"', audit)

    def test_unavailable_cards_keep_item_identity_and_a_reason(self):
        source = read_text(WARDROBE)
        self.assertIn("resolveItemIcon(record)", source)
        self.assertIn("unavailableItemReasonText(record)", source)
        self.assertIn("CLIENT_MODEL_READY_TIMEOUT", source)
        self.assertIn("model.scUnavailableText", source)

    def test_weapon_pose_cache_has_explicit_presentation_and_tuning_revisions(self):
        source = read_text(WARDROBE)
        bootstrap = read_text(ADDON / "Core" / "Bootstrap.lua")
        self.assertIn("scEffectiveM2CameraPoseRevision", source)
        self.assertIn("appearancePresentationHash", source)
        self.assertIn("SC.CameraTuning or {}).revision", source)
        self.assertIn("CameraTuning.revision = CameraTuning.revision + 1", bootstrap)

    def test_weapon_camera_resolves_appearance_then_player_model_then_generated_model_then_family_then_auto(self):
        source = read_text(WARDROBE)
        helper = re.search(
            r"local function getEffectiveM2CameraPose\(model\)(.*?)(?=\n\s*local function)",
            source,
            re.S,
        )
        self.assertIsNotNone(helper)
        block = helper.group(1)
        expected_order = [
            'getCameraTuningScopePose("appearance"',
            'getCameraTuningScopePose("model"',
            "getGeneratedModelM2CameraPose(record)",
            'getCameraTuningScopePose("weaponFamily"',
            "local autoCamera",
        ]
        positions = [block.find(token) for token in expected_order]
        self.assertTrue(all(position >= 0 for position in positions), positions)
        self.assertEqual(positions, sorted(positions))
        self.assertIn("已审核模型基线", source)

    def test_camera_workbench_is_an_in_window_inspector_not_a_dialog_overlay(self):
        source = read_text(WARDROBE)
        panel = re.search(
            r'local cameraTuningPanel = CreateFrame\("Frame".*?cameraTuningPanel:Hide\(\)',
            source,
            re.S,
        )
        self.assertIsNotNone(panel)
        self.assertNotIn('SetFrameStrata("DIALOG")', panel.group(0))
        self.assertNotIn('page, "TOPRIGHT", -5, -42', panel.group(0))


if __name__ == "__main__":
    unittest.main()
