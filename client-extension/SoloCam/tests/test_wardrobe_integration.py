import re
import unittest
from pathlib import Path


WORKSPACE = Path(__file__).resolve().parents[3]
ADDON_ROOT = WORKSPACE / "addon" / "SoloCollections"
WARDROBE = ADDON_ROOT / "UI" / "Wardrobe.lua"
APPEARANCES = ADDON_ROOT / "Data" / "Appearances.lua"
BOOTSTRAP = ADDON_ROOT / "Core" / "Bootstrap.lua"
CATALOG = ADDON_ROOT / "Core" / "Catalog.lua"
TEMPLATES = ADDON_ROOT / "UI" / "Templates.lua"
RETAIL_MEDIA = ADDON_ROOT / "Media" / "Retail"
M2_CAMERA = ADDON_ROOT / "Core" / "M2Camera.lua"
CLIENT_ROOT = Path(__file__).resolve().parents[1]
CLIENT_SOURCE = CLIENT_ROOT / "src" / "SoloCam.cpp"
CLIENT_ADDRESSES = CLIENT_ROOT / "src" / "ClientAddresses.hpp"
ITEM_CAMERA_BRIDGE = CLIENT_ROOT / "src" / "ItemCameraBridge.cpp"


class WardrobeIntegrationTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.source = WARDROBE.read_text(encoding="utf-8")
        cls.appearances = APPEARANCES.read_text(encoding="utf-8")
        cls.bootstrap = BOOTSTRAP.read_text(encoding="utf-8")
        cls.catalog = CATALOG.read_text(encoding="utf-8")
        cls.templates = TEMPLATES.read_text(encoding="utf-8")
        cls.m2_camera = M2_CAMERA.read_text(encoding="utf-8")
        cls.client_source = CLIENT_SOURCE.read_text(encoding="utf-8")
        cls.client_addresses = CLIENT_ADDRESSES.read_text(encoding="utf-8")
        cls.item_camera_bridge = ITEM_CAMERA_BRIDGE.read_text(encoding="utf-8")

    def test_human_female_slot_scope_is_explicit(self):
        expected = {
            "HEAD": "0x5341",
            "SHOULDER": "0x5342",
            "BACK": "0x5349",
            "CHEST": "0x5343",
            "WRIST": "0x5344",
            "HANDS": "0x5345",
            "WAIST": "0x5346",
            "LEGS": "0x5347",
            "FEET": "0x5348",
        }
        for slot, sentinel in expected.items():
            self.assertRegex(
                self.source,
                rf"{slot}\s*=\s*{sentinel}",
                f"missing custom camera handshake for {slot}",
            )
        self.assertRegex(self.source, r'UnitSex\("player"\)\s*==\s*3')
        self.assertRegex(self.source, r'raceToken\s*==\s*"Human"')
        self.assertIn("CUSTOM_CAMERA_HUMAN_FEMALE[model.scRecord.slot]", self.source)

    def test_all_retail_body_slots_are_available_as_filters(self):
        for slot in (
            "HEAD", "SHOULDER", "BACK", "CHEST", "WRIST",
            "HANDS", "WAIST", "LEGS", "FEET",
        ):
            self.assertRegex(self.source, rf'key\s*=\s*"{slot}"')
            self.assertRegex(self.bootstrap, rf'\b{slot}\s*=\s*true')

    def test_item_navigation_uses_armor_families_and_omits_shirt_tabard(self):
        for armor_type, label in (
            ("PLATE", "\u677f\u7532"),
            ("MAIL", "\u9501\u7532"),
            ("LEATHER", "\u76ae\u7532"),
            ("CLOTH", "\u5e03\u7532"),
        ):
            self.assertRegex(self.source, rf'key\s*=\s*"{armor_type}"[^\n]*label\s*=\s*"{label}"')
            self.assertRegex(self.bootstrap, rf'\b{armor_type}\s*=\s*true')
        self.assertIn('local function getDefaultArmorType()', self.source)
        self.assertIn('filters.armorType = getDefaultArmorType()', self.source)
        slot_filter = re.search(
            r"local SLOT_FILTERS\s*=\s*\{(.*?)\n\}",
            self.source,
            re.DOTALL,
        )
        self.assertIsNotNone(slot_filter)
        self.assertNotIn('key = "SHIRT"', slot_filter.group(1))
        self.assertNotIn('key = "TABARD"', slot_filter.group(1))
        self.assertIn('local function armorTypeMatches(record, filters)', self.catalog)

    def test_slot_buttons_use_retail_casc_atlas_assets(self):
        slot_atlas = RETAIL_MEDIA / "TransmogNavSlots.blp"
        highlight_atlas = RETAIL_MEDIA / "BagsRoundHighlight.blp"
        if slot_atlas.is_file():
            self.assertEqual(slot_atlas.read_bytes()[:4], b"BLP2")
        if highlight_atlas.is_file():
            self.assertEqual(highlight_atlas.read_bytes()[:4], b"BLP2")
        self.assertIn('wardrobeSlotAtlas = MEDIA_ROOT .. "Retail\\\\TransmogNavSlots.blp"', self.templates)
        self.assertIn('roundHighlightAtlas = MEDIA_ROOT .. "Retail\\\\BagsRoundHighlight.blp"', self.templates)
        self.assertIn('local SLOT_ATLAS_SIZE = 512', self.source)
        self.assertIn('selected = { 381, 426, 65, 112 }', self.source)
        self.assertIn('button.scSelected = selected', self.source)

    def test_weapon_dropdown_is_wotlk_only_and_class_aware(self):
        weapon_filters = re.search(
            r"local WEAPON_FILTERS\s*=\s*\{(.*?)\n\}",
            self.source,
            re.DOTALL,
        )
        self.assertIsNotNone(weapon_filters)
        filter_source = weapon_filters.group(1)
        expected = {
            "ONE_HAND_AXE", "TWO_HAND_AXE", "BOW", "GUN",
            "ONE_HAND_MACE", "TWO_HAND_MACE", "POLEARM",
            "ONE_HAND_SWORD", "TWO_HAND_SWORD", "STAFF", "FIST_WEAPON",
            "DAGGER", "THROWN", "CROSSBOW", "WAND", "FISHING_POLE",
            "SHIELD", "OFFHAND_ITEM",
        }
        actual = set(re.findall(r'key\s*=\s*"([A-Z0-9_]+)"', filter_source))
        self.assertEqual(actual, expected)
        self.assertNotIn("WAR_GLAIVE", actual)
        self.assertIn("local CLASS_WEAPON_TYPES = {", self.source)
        self.assertIn("ensureWeaponTypeForSlot(SC.db.filters, value)", self.source)
        self.assertIn('weaponCategory = "ONE_HAND_SWORD"', self.appearances)
        self.assertIn("local function weaponTypeMatches(record, filters)", self.catalog)

    def test_retail_rotations_are_slot_specific(self):
        self.assertRegex(self.source, r'HEAD\s*=\s*\{[^}]*rotation\s*=\s*0\.50')
        self.assertRegex(self.source, r'SHOULDER\s*=\s*\{[^}]*rotation\s*=\s*0\.50')
        self.assertRegex(self.source, r'BACK\s*=\s*\{[^}]*rotation\s*=\s*3\.14')

    def test_item_cards_use_thin_retail_style_borders(self):
        self.assertIn("local function createThinCardBorder", self.source)
        self.assertIn("createThinCardBorder(itemHitFrame, 1)", self.source)
        self.assertIn("createThinCardBorder(itemHitFrame, 2)", self.source)
        self.assertIn("itemModel.scBorder:SetCollected(record.collected)", self.source)
        self.assertNotRegex(
            self.source,
            r"itemModel\.scBorder:SetTexture\(record\.collected",
        )

    def test_item_card_hover_uses_a_full_card_warm_highlight(self):
        self.assertIn('hover:SetTexture("Interface\\\\Buttons\\\\WHITE8X8")', self.source)
        self.assertIn("hover:SetAllPoints(itemHitFrame)", self.source)
        self.assertIn("hover:SetVertexColor(0.80, 0.58, 0.18, 0.12)", self.source)
        self.assertNotIn("UI-Common-MouseHilight", self.source)

    def test_weapon_slots_use_direct_display_info_bridge(self):
        self.assertRegex(self.source, r'key\s*=\s*"MAINHAND"')
        self.assertRegex(self.source, r'key\s*=\s*"OFFHAND"')
        self.assertRegex(self.bootstrap, r'\bMAINHAND\s*=\s*true')
        self.assertRegex(self.bootstrap, r'\bOFFHAND\s*=\s*true')
        self.assertIn('CreateFrame("PlayerModel", nil, itemCard)', self.source)
        self.assertIn("isStandaloneItemRecord", self.source)
        self.assertIn("record.creatureDisplayId", self.source)
        self.assertIn("DIRECT_DISPLAY_REQUEST_BASE", self.source)
        self.assertRegex(
            self.source,
            r"model:SetCreature\(DIRECT_DISPLAY_REQUEST_BASE\s*\+\s*record\.creatureDisplayId\)",
        )
        self.assertIn("HookPlayerModelSetCreature", self.client_source)
        self.assertIn("TryDecodeDisplayInfoRequest", self.client_source)
        self.assertIn("PlayerModelSetCreatureRecord", self.client_source)
        self.assertIn("PlayerModelSetCreature", self.client_addresses)
        self.assertNotIn("ReplaceIconTexture(record.replacementTexture)", self.source)

    def test_standalone_weapon_models_receive_explicit_lighting(self):
        self.assertIn("local function applyStandaloneItemLighting", self.source)
        self.assertRegex(
            self.source,
            re.compile(
                r"applyStandaloneItemLighting\(model\).*?model:SetLight\(",
                re.DOTALL,
            ),
        )
        self.assertIn("applyStandaloneItemLighting(model)", self.source)

    def test_demo_catalog_contains_back_and_weapon_models(self):
        self.assertRegex(self.appearances, r'slot\s*=\s*"BACK"')
        self.assertRegex(
            self.appearances,
            r'slot\s*=\s*"MAINHAND"[^\n]*modelPath\s*=',
        )
        self.assertRegex(
            self.appearances,
            r'slot\s*=\s*"OFFHAND"[^\n]*modelPath\s*=',
        )
        weapon_model_paths = re.findall(
            r'slot\s*=\s*"(?:MAINHAND|OFFHAND)"[^\n]*modelPath\s*=\s*"([^"]+)"',
            self.appearances,
        )
        self.assertGreaterEqual(len(weapon_model_paths), 5)
        for model_path in weapon_model_paths:
            self.assertIn(
                r"Item\\ObjectComponents\\SoloCollections\\",
                model_path,
                "standalone item cards must use texture-resolved wardrobe M2 copies",
            )

    def test_weapon_calibration_catalog_covers_every_practical_wotlk_subclass(self):
        expected = {
            "ONE_HAND_AXE", "TWO_HAND_AXE", "BOW", "GUN",
            "ONE_HAND_MACE", "TWO_HAND_MACE", "POLEARM",
            "ONE_HAND_SWORD", "TWO_HAND_SWORD", "STAFF", "FIST_WEAPON",
            "DAGGER", "THROWN", "CROSSBOW", "WAND", "FISHING_POLE",
        }
        actual = set(re.findall(r'weaponType\s*=\s*"([A-Z0-9_]+)"', self.appearances))
        self.assertTrue(expected.issubset(actual))
        self.assertIn('GameTooltip:AddLine("武器类型：" .. record.weaponTypeLabel', self.source)

    def test_standalone_weapons_use_the_retail_lower_left_hilt_diagonal(self):
        self.assertIn("local WEAPON_M2_CAMERA", self.appearances)
        expected_poses = {
            "TWO_HAND_SWORD": "yaw = 1.04, pitch = -0.18, roll = 0.97",
            "ONE_HAND_AXE": "yaw = 0.90, pitch = -0.69, roll = 1.45",
            "WAR_GLAIVE_MAINHAND": "yaw = 0.76, pitch = -0.63, roll = 1.24",
            "WAR_GLAIVE_OFFHAND": "yaw = -1.93, pitch = -0.82, roll = 1.38",
        }
        for pose_key, values in expected_poses.items():
            self.assertRegex(self.appearances, rf'{pose_key}\s*=\s*\{{[^\n]*{re.escape(values)}')
        for item_id in (19364, 19019, 32837, 32838, 32375):
            self.assertRegex(
                self.appearances,
                rf'itemId\s*=\s*{item_id}[^\n]*m2Camera\s*=\s*WEAPON_M2_CAMERA\.',
                f"item {item_id} must use the M2 camera API",
            )
        self.assertIn('cameraTuningKey = "WAR_GLAIVE_MAINHAND"', self.appearances)
        self.assertIn('cameraTuningKey = "WAR_GLAIVE_OFFHAND"', self.appearances)

    def test_standalone_player_model_defers_orientation_to_m2_camera(self):
        transform = re.search(
            r"local function applyStandaloneItemTransform\(model\)(.*?)\nend",
            self.source,
            re.DOTALL,
        )
        self.assertIsNotNone(transform)
        body = transform.group(1)
        self.assertIn("if not record.m2Camera then", body)
        self.assertLess(body.index("if model.SetRotation then"), body.index("elseif model.SetFacing then"))
        self.assertIn("model:SetRotation(rotation)", body)
        self.assertIn("local cameraPose = getEffectiveM2CameraPose(model)", self.source)
        self.assertIn("SC.M2Camera.Apply(model, cameraPose)", self.source)

    def test_lua_m2_camera_api_encodes_and_activates_a_full_pose(self):
        for request in (
            "REQUEST_YAW_PITCH = 0x51000000",
            "REQUEST_DISTANCE_TARGET_Z = 0x52000000",
            "REQUEST_TARGET_XY = 0x53000000",
            "REQUEST_ACTIVATE = 0x54000000",
            "REQUEST_ROLL = 0x55000000",
        ):
            self.assertIn(request, self.m2_camera)
        self.assertIn("function M2Camera.Apply(model, pose)", self.m2_camera)
        self.assertIn("model:SetCamera(request)", self.m2_camera)
        self.assertIn("BuildItemM2Camera", self.client_source)
        self.assertIn("BuildItemM2CameraRoll", self.client_source)
        self.assertIn("DataMgrGetScalar", self.client_source)
        self.assertIn("CameraRollSlot", self.client_addresses)
        self.assertIn("IsItemCameraRequest", self.client_source)
        self.assertIn("TryDecodeItemCameraRequest", self.client_source)
        self.assertIn("kMaximumTargetOffset", self.item_camera_bridge)

    def test_m2_camera_tuning_panel_persists_and_exports_per_camera_key_pose(self):
        self.assertIn("m2CameraTuning = {}", self.bootstrap)
        self.assertIn("normalizeM2CameraTuning(db)", self.bootstrap)
        self.assertIn("function M2Camera.NormalizePose(pose)", self.m2_camera)
        self.assertIn("function M2Camera.FormatPose(pose)", self.m2_camera)
        self.assertIn("SoloCollectionsM2CameraTuningPanel", self.source)
        self.assertEqual(self.source.count("createCameraTuningSlider("), 8)
        self.assertIn('"Roll 滚转"', self.source)
        self.assertIn("local function getM2CameraTuningKey(record)", self.source)
        self.assertIn("SC.db.m2CameraTuning[getM2CameraTuningKey(cameraTuningPanel.scRecord)] = pose", self.source)
        self.assertIn('key:match("^[A-Z][A-Z0-9_]*$")', self.bootstrap)
        self.assertIn('weaponType = "%s", %s', self.source)
        self.assertIn('cameraTuningKey = "%s", %s', self.source)
        self.assertNotIn('saved = SC.db.m2CameraTuning[record.id]', self.source)
        self.assertIn("function page:SyncCameraTuningPanel(record)", self.source)
        self.assertIn("SC.M2Camera.FormatPose(cameraTuningPanel.scPose)", self.source)
        self.assertIn("tuningExport:HighlightText()", self.source)

    def test_handshake_has_a_stock_client_fallback(self):
        pattern = re.compile(
            r"SetCamera\(model\.scClientCameraSentinel\).*?"
            r"SetCamera\(1\)",
            re.DOTALL,
        )
        self.assertRegex(self.source, pattern)

    def test_custom_camera_does_not_reapply_legacy_slot_scale(self):
        self.assertIn("model.scUsesClientCamera", self.source)
        self.assertRegex(
            self.source,
            re.compile(
                r"if\s+model\.scUsesClientCamera\s+then.*?nativeScale",
                re.DOTALL,
            ),
        )


if __name__ == "__main__":
    unittest.main()
