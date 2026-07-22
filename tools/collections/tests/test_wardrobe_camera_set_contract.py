from __future__ import annotations

import re
import unittest
from pathlib import Path

from common import ADDON, ROOT, load_json, read_text


MEDIA_MANIFEST = ADDON / "Media" / "assets.json"
TEMPLATES = ADDON / "UI" / "Templates.lua"
WARDROBE = ADDON / "UI" / "Wardrobe.lua"
PRESENTATIONS = ROOT / "tools" / "catalog" / "appearance_presentations.py"
NEW_BUNDLE = ROOT / "tools" / "release" / "New-RoundTwoBundle.ps1"
TEST_BUNDLE = ROOT / "tools" / "release" / "Test-RoundTwoBundle.ps1"
RELEASE_COMMON = ROOT / "tools" / "release" / "RoundTwoRelease.Common.ps1"


class WardrobeCameraSetContractTests(unittest.TestCase):
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

    def test_standalone_validation_is_registry_based_not_a_fixed_21_id_range(self):
        source = read_text(PRESENTATIONS)
        self.assertNotIn("len(entries) == 21", source)
        self.assertNotIn("set(range(40000, 40021))", source)
        self.assertIn("registry", source.lower())

    def test_weapon_camera_resolves_appearance_then_model_then_family_then_auto(self):
        source = read_text(WARDROBE)
        helper = re.search(
            r"local function getEffectiveM2CameraPose\(model\)(.*?)(?=\n\s*local function)",
            source,
            re.S,
        )
        self.assertIsNotNone(helper)
        block = helper.group(1)
        expected_order = ["appearance", "model", "weaponFamily", "autoCamera"]
        positions = [block.find(token) for token in expected_order]
        self.assertTrue(all(position >= 0 for position in positions), positions)
        self.assertEqual(positions, sorted(positions))

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
