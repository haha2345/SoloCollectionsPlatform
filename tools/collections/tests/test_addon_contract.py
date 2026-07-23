from __future__ import annotations

import unittest
import re

from common import ADDON, ROOT, all_lua_text, read_text


EXPECTED_LOAD_ORDER = [
    "SoloCollections.lua",
    "Data\\Generated\\Catalog.lua",
    "Data\\Generated\\IdentityRegistry.lua",
    "Data\\Generated\\PolicyRegistry.lua",
    "Data\\Generated\\CameraProfiles.lua",
    "Data\\Mounts.lua",
    "Data\\Pets.lua",
    "Data\\Toys.lua",
    "Data\\Appearances.lua",
    "Data\\Sets.lua",
    "Core\\IdentityRegistry.lua",
    "Core\\CollectionState.lua",
    "Core\\Catalog.lua",
    "Core\\Bridge.lua",
    "Core\\M2Camera.lua",
    "UI\\Templates.lua",
    "UI\\Launcher.lua",
    "UI\\CompanionBase.lua",
    "UI\\Mounts.lua",
    "UI\\Pets.lua",
    "UI\\Toys.lua",
    "UI\\Wardrobe.lua",
    "UI\\CollectionsFrame.lua",
    "Core\\Diagnostics.lua",
    "Core\\Bootstrap.lua",
]

FORBIDDEN_APIS = (
    "C_MountJournal",
    "C_PetJournal",
    "C_ToyBox",
    "C_TransmogCollection",
    "CreateScrollBoxListLinearView",
    "SetAtlas(",
    "ModelScene",
    "Mixin(",
)


def lua_function_region(text: str, name: str) -> str:
    """Return one top-level Lua function through the next function declaration."""
    start_match = re.search(
        rf"(?m)^function\s+{re.escape(name)}\s*\(",
        text,
    )
    if not start_match:
        raise AssertionError(f"missing Lua function: {name}")
    next_match = re.search(
        r"(?m)^(?:local\s+)?function\s+[A-Za-z0-9_.:]+\s*\(",
        text[start_match.end() :],
    )
    end = len(text) if not next_match else start_match.end() + next_match.start()
    return text[start_match.start() : end]


class AddonContractTests(unittest.TestCase):
    def test_addon_directory_and_toc_exist(self):
        self.assertTrue(ADDON.is_dir(), f"missing addon source: {ADDON}")
        self.assertTrue((ADDON / "SoloCollections.toc").is_file())

    def test_toc_has_30300_saved_variables_and_load_order(self):
        toc_path = ADDON / "SoloCollections.toc"
        self.assertTrue(toc_path.is_file(), f"missing {toc_path}")
        toc = read_text(toc_path)
        self.assertIn("## Interface: 30300", toc)
        self.assertIn("## SavedVariables: SoloCollectionsDB", toc)
        loaded = [
            line.strip()
            for line in toc.splitlines()
            if line.strip() and not line.lstrip().startswith("##")
        ]
        self.assertEqual(EXPECTED_LOAD_ORDER, loaded)

    def test_addon_uses_one_namespace_and_no_modern_api(self):
        text = all_lua_text()
        self.assertEqual(1, text.count("SoloCollections = SoloCollections or {}"))
        for api in FORBIDDEN_APIS:
            self.assertNotIn(api, text)

    def test_five_main_tabs_and_two_wardrobe_views_are_declared(self):
        text = all_lua_text()
        for token in ('"MOUNTS"', '"PETS"', '"TOYS"', '"WARDROBE"', '"TITLES"'):
            self.assertIn(token, text)
        self.assertIn('"ITEMS"', text)
        self.assertIn('"SETS"', text)

    def test_phase_one_does_not_execute_collection_actions(self):
        self.assertTrue(ADDON.is_dir(), f"missing addon source: {ADDON}")
        text = all_lua_text()
        for forbidden in (
            "UseItemByName",
            "PickupItem",
            "LearnSpell",
            "CastSpellByName",
            "CastSpell(",
        ):
            self.assertNotIn(forbidden, text)

    def test_generated_catalog_branch_has_no_global_mount_or_pet_icon(self):
        catalog = read_text(ADDON / "Core" / "Catalog.lua")
        self.assertNotIn("Ability_Mount_RidingHorse", catalog)
        self.assertNotIn("INV_Box_PetCarrier_01", catalog)

    def test_launcher_is_bottom_right_draggable_and_persistent(self):
        path = ADDON / "UI" / "Launcher.lua"
        self.assertTrue(path.is_file(), f"missing {path}")
        text = read_text(path)
        for token in (
            '"SoloCollectionsLauncher"',
            'SetWidth(46)',
            'SetHeight(46)',
            '"BOTTOMRIGHT"',
            'RegisterForDrag("LeftButton")',
            'SetClampedToScreen(true)',
            'GameTooltip:SetText("收藏")',
            'SC:ToggleJournal()',
            'SC.db.launcher',
        ):
            self.assertIn(token, text)

    def test_journal_is_lazy_and_has_shared_shell_controls(self):
        path = ADDON / "UI" / "CollectionsFrame.lua"
        self.assertTrue(path.is_file(), f"missing {path}")
        text = read_text(path)
        bootstrap = read_text(ADDON / "Core" / "Bootstrap.lua")
        self.assertIn("function UI.CreateCollectionsFrame()", text)
        self.assertIn("if UI.CollectionsFrame then", text)
        self.assertIn('UI.CreateJournalFrame(UIParent, "SoloCollectionsJournal"', text)
        for token in (
            '"UIPanelCloseButton"',
            'UI.CreateRetailProgressBar(',
            'UI.CreateRetailSearchBox(',
            'UI.CreateFilterPopup(',
            'scContentHost',
            'scPageTitle',
            'scPortrait',
        ):
            self.assertIn(token, text)
        self.assertNotIn("CreateCollectionsFrame", bootstrap)

    def test_journal_shell_uses_collection_count_and_no_internal_footer(self):
        journal = read_text(ADDON / "UI" / "CollectionsFrame.lua")
        templates = read_text(ADDON / "UI" / "Templates.lua")
        shell = lua_function_region(templates, "UI.CreateJournalFrame")

        for token in (
            "JOURNAL_HEIGHT = 793",
            "UI.Media.mountPortrait",
            "UI.CreateCollectionCount(frame)",
            "UI.CreateRetailProgressBar(frame, 286)",
            "MiniMap-TrackingBorder",
            "portrait:SetWidth(62)",
            "portrait:SetHeight(62)",
            "portrait:SetTexCoord(0, 1, 0, 1)",
            "portraitRing:SetTexCoord(0, 0.625, 0, 0.625)",
            "frame.scCollectionCount",
        ):
            self.assertIn(token, journal)
        self.assertNotIn("local footer =", shell)
        self.assertNotIn("scFooterBackground", shell)
        self.assertNotRegex(
            journal,
            r'contentHost:SetPoint\(\s*"BOTTOMRIGHT"[^\n]*,\s*72\s*\)',
        )

    def test_journal_header_state_and_launcher_use_retail_helpers_and_artwork(self):
        journal = read_text(ADDON / "UI" / "CollectionsFrame.lua")
        launcher = read_text(ADDON / "UI" / "Launcher.lua")

        for token in (
            "UI.CreateRetailSearchBox(",
            "UI.CreateRetailBottomTab(",
            "frame.scCollectionCount:Show()",
            "frame.scCollectionCount:Hide()",
            'frame.scCollectionCount:SetLabel("所有坐骑")',
            'frame.scCollectionCount:SetLabel("所有小宠物")',
            "frame.scPortrait:SetTexture(UI.Media.mountPortrait)",
        ):
            self.assertIn(token, journal)
        self.assertIn("icon:SetTexture(UI.Media.launcher)", launcher)
        self.assertNotIn("Media\\Icons\\launcher.tga", launcher)
        self.assertNotIn("UI.Media.collectedFrame", launcher)

    def test_retail_search_uses_three_slice_and_progress_uses_clipped_inner_bar(self):
        templates = read_text(ADDON / "UI" / "Templates.lua")
        three_slice = lua_function_region(templates, "UI.CreateThreeSlice")
        for token in (
            "leftTexture",
            "middleTexture",
            "rightTexture",
            "local left =",
            "local middle =",
            "local right =",
            "left:SetTexture(leftTexture)",
            "middle:SetTexture(middleTexture)",
            "right:SetTexture(rightTexture)",
            'middle:SetPoint("LEFT", left, "RIGHT"',
            'middle:SetPoint("RIGHT", right, "LEFT"',
            "middle:SetHorizTile(true)",
        ):
            self.assertIn(token, three_slice)
        self.assertNotIn("setAllPoints(", three_slice)
        self.assertNotIn(":SetAllPoints(", three_slice)

        search = lua_function_region(templates, "UI.CreateRetailSearchBox")
        self.assertIn("UI.CreateThreeSlice(", search)

        progress = lua_function_region(templates, "UI.CreateRetailProgressBar")
        for token in (
            'CreateFrame("StatusBar", nil, holder)',
            "statusBar:SetWidth(barWidth)",
            "statusBar:SetHeight(14)",
            "statusBar:SetStatusBarTexture(UI.Media.stock.progressFill)",
            'local borderHost = CreateFrame("Frame", nil, holder)',
            "borderHost:SetFrameLevel(statusBar:GetFrameLevel() + 1)",
            'local border = borderHost:CreateTexture(nil, "ARTWORK")',
            "border:SetWidth(barWidth + 9)",
            "border:SetHeight(27)",
            'border:SetPoint("LEFT", statusBar, "LEFT", -5, 0)',
            'local label = createLabel(borderHost, "GameFontHighlightSmall"',
            'label:SetText(current .. " / " .. total)',
            "holder.scStatusBar = statusBar",
            "holder.scBorderHost = borderHost",
        ):
            self.assertIn(token, progress)
        self.assertNotIn("UI.CreateThreeSlice(", progress)

    def test_retail_bottom_tab_has_opaque_base_and_gold_selected_gradient(self):
        templates = read_text(ADDON / "UI" / "Templates.lua")
        tab = lua_function_region(templates, "UI.CreateRetailBottomTab")
        self.assertGreaterEqual(tab.count("UI.CreateThreeSlice("), 2)
        for token in (
            'createSolidTexture(button, "BACKGROUND", 0.035, 0.028, 0.018, 1)',
            'inactiveFill:SetGradientAlpha("VERTICAL"',
            'selectedGradient:SetGradientAlpha("VERTICAL"',
            'highlight:SetTexture("Interface\\\\Buttons\\\\WHITE8X8")',
            "button.scInactiveFill = inactiveFill",
            "button.scEdgeTextures = edgeTextures",
        ):
            self.assertIn(token, tab)
        self.assertNotIn("UI.Media.stock.tabHighlight", tab)
        self.assertNotIn("LockHighlight()", tab)
        self.assertNotIn("UnlockHighlight()", tab)

    def test_progress_clamps_values_and_empty_mount_rows_clear_visual_state(self):
        templates = read_text(ADDON / "UI" / "Templates.lua")
        progress = lua_function_region(templates, "UI.CreateRetailProgressBar")
        self.assertIn("current = math.max(0, math.min(current, total))", progress)
        self.assertIn("statusBar:SetValue(current)", progress)

        row = lua_function_region(templates, "UI.CreateMountListRow")
        empty_branch = row[row.index("if not record then") : row.index("UI.SetIconTexture(")]
        for token in (
            "self.scRecord = nil",
            "self.scSelected = nil",
            "selected:Hide()",
            "star:Hide()",
            "collectedTint:Hide()",
            "self:Hide()",
        ):
            self.assertIn(token, empty_branch)

    def test_journal_tabs_have_required_order_and_wardrobe_subtabs(self):
        path = ADDON / "UI" / "CollectionsFrame.lua"
        self.assertTrue(path.is_file(), f"missing {path}")
        text = read_text(path)
        labels = [
            text.index('label = "坐骑"'),
            text.index('label = "小宠物"'),
            text.index('label = "玩具箱"'),
            text.index('label = "外观"'),
        ]
        self.assertEqual(sorted(labels), labels)
        for token in (
            'key = "MOUNTS"',
            'key = "PETS"',
            'key = "TOYS"',
            'key = "WARDROBE"',
            '"ITEMS"',
            '"SETS"',
            'SC.db.wardrobeTab',
        ):
            self.assertIn(token, text)

    def test_journal_scales_and_clamps_for_display_changes(self):
        path = ADDON / "UI" / "CollectionsFrame.lua"
        self.assertTrue(path.is_file(), f"missing {path}")
        text = read_text(path)
        for token in (
            "DESIGN_SCREEN_WIDTH = 1920",
            "DESIGN_SCREEN_HEIGHT = 1080",
            "UIParent:GetWidth() / DESIGN_SCREEN_WIDTH",
            "UIParent:GetHeight() / DESIGN_SCREEN_HEIGHT",
            "math.min(1,",
            'RegisterEvent("DISPLAY_SIZE_CHANGED")',
            'RegisterEvent("UI_SCALE_CHANGED")',
            'SetClampRectInsets(0, 0, 0, -40)',
            'SetClampedToScreen(true)',
            'SetScript("OnShow"',
        ):
            self.assertIn(token, text)

    def test_journal_initial_search_callback_runs_after_frame_is_ready(self):
        text = read_text(ADDON / "UI" / "CollectionsFrame.lua")
        self.assertLess(
            text.index("UI.CollectionsFrame = frame"),
            text.index('search:SetText((SC.db and SC.db.query) or "")'),
        )

    def test_journal_refreshes_active_page_when_shown(self):
        text = read_text(ADDON / "UI" / "CollectionsFrame.lua")
        on_show = text[text.index('frame:SetScript("OnShow"'):text.index("local pageTitle")]
        self.assertIn("UI.RefreshActivePage()", on_show)

    def test_reset_resyncs_open_journal_shell(self):
        launcher = read_text(ADDON / "UI" / "Launcher.lua")
        journal = read_text(ADDON / "UI" / "CollectionsFrame.lua")
        self.assertIn("UI.SyncJournalFromDatabase", launcher)
        self.assertIn("function UI.SyncJournalFromDatabase()", journal)
        for token in (
            'frame.scSearchBox:SetText(SC.db.query or "")',
            "UI.SetMainTab(SC.db.mainTab)",
            "UI.SetWardrobeTab(SC.db.wardrobeTab)",
            "UI.SyncFilterControls",
            "refreshPage()",
        ):
            self.assertIn(token, journal)

    def test_saved_variables_repair_invalid_types_and_enums_field_by_field(self):
        bootstrap = read_text(ADDON / "Core" / "Bootstrap.lua")
        for token in (
            "local VALID_POINTS =",
            "local VALID_MAIN_TABS =",
            "local VALID_WARDROBE_TABS =",
            "local VALID_CLASS_TOKENS = SC.IdentityRegistry.GetValidClassTokens()",
            "local VALID_SLOTS =",
            "local VALID_BRIDGE_STATUS =",
            "local function repairScalar(",
            "local function repairEnum(",
            "local function normalizePosition(",
            "local function normalizeDatabase(",
            'repairScalar(db, "schemaVersion", "number", DEFAULTS.schemaVersion)',
            'repairEnum(db, "mainTab", VALID_MAIN_TABS, DEFAULTS.mainTab)',
            'repairEnum(db, "wardrobeTab", VALID_WARDROBE_TABS, DEFAULTS.wardrobeTab)',
            'repairScalar(db, "query", "string", DEFAULTS.query)',
            'repairScalar(db.filters, "collected", "boolean", DEFAULTS.filters.collected)',
            'repairScalar(db.filters, "uncollected", "boolean", DEFAULTS.filters.uncollected)',
            'repairScalar(db.filters, "favorites", "boolean", DEFAULTS.filters.favorites)',
            'repairEnum(db.filters, "classToken", VALID_CLASS_TOKENS, DEFAULTS.filters.classToken)',
            'repairEnum(db.filters, "slot", VALID_SLOTS, DEFAULTS.filters.slot)',
            'repairScalar(db, "favorites", "table", {})',
            'repairScalar(db, "debug", "boolean", DEFAULTS.debug)',
            'repairScalar(db, "bridge", "table", {})',
            'repairEnum(db.bridge, "status", VALID_BRIDGE_STATUS, DEFAULTS.bridge.status)',
            'repairScalar(db.bridge, "connected", "boolean", DEFAULTS.bridge.connected)',
            'repairScalar(db.bridge, "demoMode", "boolean", DEFAULTS.bridge.demoMode)',
            'repairScalar(db.bridge, "features", "table", {})',
        ):
            self.assertIn(token, bootstrap)
        self.assertNotIn("copyDefaults", bootstrap)

    def test_named_frames_use_only_addon_prefix(self):
        for path in (ADDON / "UI" / "Launcher.lua", ADDON / "UI" / "CollectionsFrame.lua"):
            self.assertTrue(path.is_file(), f"missing {path}")
            text = read_text(path)
            names = re.findall(r'CreateFrame\([^,]+,\s*"([^"]+)"', text)
            for name in names:
                self.assertTrue(
                    name.startswith("SoloCollections"),
                    f"global frame name must use SoloCollections prefix: {name}",
                )

    def test_mounts_and_pets_use_dedicated_full_height_scroll_pages(self):
        mounts_path = ADDON / "UI" / "Mounts.lua"
        companion_path = ADDON / "UI" / "CompanionBase.lua"
        pets_path = ADDON / "UI" / "Pets.lua"
        self.assertTrue(mounts_path.is_file(), f"missing {mounts_path}")
        self.assertTrue(companion_path.is_file(), f"missing {companion_path}")
        self.assertTrue(pets_path.is_file(), f"missing {pets_path}")
        mounts = read_text(mounts_path)
        pets = read_text(pets_path)
        for token in (
            "function UI.CreateMountsPage(",
            "VISIBLE_ROWS = 12",
            "FauxScrollFrameTemplate",
            "FauxScrollFrame_Update(",
            "FauxScrollFrame_GetOffset(",
            "EnableMouseWheel(true)",
            'SetScript("OnMouseWheel"',
            "FauxScrollFrame_OnVerticalScroll(",
            'Catalog.QueryAll("MOUNTS"',
            "Catalog.GetProgress(",
            "Catalog.ToggleDemoFavorite(",
            "function page:Refresh()",
            "function page:ClearSelection()",
        ):
            self.assertIn(token, mounts)
        for pagination_token in (
            "UI.CreatePageControls(",
            "scTotalPages",
            "controls:SetPage(",
        ):
            self.assertNotIn(pagination_token, mounts)
        self.assertNotIn('UI.CreateCompanionPageBase("MOUNTS"', mounts)
        self.assertNotIn("function UI.CreateCompanionPageBase(", mounts)
        self.assertIn("function UI.CreatePetsPage(", pets)
        for token in (
            "local VISIBLE_ROWS = 12",
            "FauxScrollFrameTemplate",
            "FauxScrollFrame_Update(",
            "FauxScrollFrame_GetOffset(",
            "FauxScrollFrame_OnVerticalScroll(",
            'Catalog.QueryAll("PETS"',
            'Catalog.GetProgress("PETS"',
            'Catalog.ToggleDemoFavorite("PETS", record.id)',
            "SC.Bridge.RequestCreaturePreview(11, record.id,",
            "SC.Bridge.SummonPet(record.id,",
            "function page:Refresh()",
            "function page:ClearSelection()",
        ):
            self.assertIn(token, pets)
        for pagination_token in (
            "UI.CreateCompanionPageBase(",
            "UI.CreatePageControls(",
            "scTotalPages",
            "controls:SetPage(",
        ):
            self.assertNotIn(pagination_token, pets)

    def test_pet_list_and_detail_match_mount_journal_interactions(self):
        pets = read_text(ADDON / "UI" / "Pets.lua")
        for token in (
            "UI.ApplyNineSlice(list, UI.Media.border, 14)",
            'scrollHint:SetText("滚轮或拖动滚动条查看更多小宠物")',
            'CreateFrame("PlayerModel"',
            'CreateFrame("Button", nil, detail)',
            'RegisterForClicks("LeftButtonUp", "RightButtonUp")',
            'UIDropDownMenu_Initialize(',
            'SetText("召唤小宠物")',
            'SetText("重置视角")',
            'SetScript("OnMouseWheel"',
            'SetScript("OnMouseDown"',
            'SetScript("OnMouseUp"',
            "favorite:Disable()",
            "if not record.collected then",
            "model:SetCreature(record.previewCreatureEntry)",
        ):
            self.assertIn(token, pets)
        self.assertNotIn("model:SetCamera(", pets)
        self.assertNotIn("model:SetPosition(0, 0, 0)", pets)
        self.assertNotIn("model:SetModelScale(1)", pets)

    def test_mount_list_uses_full_height_bordered_viewport_and_scroll_cue(self):
        mounts = read_text(ADDON / "UI" / "Mounts.lua")
        page = lua_function_region(mounts, "UI.CreateMountsPage")
        for token in (
            "UI.ApplyNineSlice(list, UI.Media.border, 14)",
            'listBackground:SetTexture("Interface\\\\Buttons\\\\WHITE8X8")',
            'scrollFrame:SetPoint("TOPLEFT", list, "TOPLEFT", 9, -9)',
            'scrollFrame:SetPoint("BOTTOMRIGHT", list, "BOTTOMRIGHT", -30, 31)',
            'scrollHint:SetText("滚轮或拖动滚动条查看更多坐骑")',
            "page.scScrollHint = scrollHint",
        ):
            self.assertIn(token, page)
        self.assertIn("local VISIBLE_ROWS = 12", mounts)

    def test_mount_rows_support_left_and_right_click_context_actions(self):
        mounts = read_text(ADDON / "UI" / "Mounts.lua")
        templates = read_text(ADDON / "UI" / "Templates.lua")
        row_factory = lua_function_region(templates, "UI.CreateMountListRow")
        self.assertRegex(
            row_factory,
            r'RegisterForClicks\([^\n]*"LeftButtonUp"[^\n]*"RightButtonUp"[^\n]*\)',
        )
        self.assertIn("onContext", row_factory)
        self.assertIn('button == "RightButton"', row_factory)
        self.assertRegex(row_factory, r"onContext\([^\n]*record")

        mount_page = lua_function_region(mounts, "UI.CreateMountsPage")
        for token in (
            "UIDropDownMenuTemplate",
            "UIDropDownMenu_Initialize(",
            "UIDropDownMenu_CreateInfo(",
            "UIDropDownMenu_AddButton(",
            "ToggleDropDownMenu(",
            "SC.Bridge.SummonMount(record.id,",
            'Catalog.ToggleDemoFavorite("MOUNTS", record.id)',
        ):
            self.assertIn(token, mount_page)

    def test_mount_wheel_clamps_row_offsets_and_rows_forward_wheel_events(self):
        mounts = read_text(ADDON / "UI" / "Mounts.lua")
        mount_page = lua_function_region(mounts, "UI.CreateMountsPage")
        for token in (
            "local function scrollByWheel(self, delta)",
            "local currentOffset = FauxScrollFrame_GetOffset(self) or 0",
            "local maxOffset = math.max(0, #(page.scRecords or {}) - VISIBLE_ROWS)",
            "local newOffset = math.max(0, math.min(maxOffset, currentOffset - delta))",
            "FauxScrollFrame_OnVerticalScroll(self, newOffset * ROW_HEIGHT, ROW_HEIGHT, refreshRows)",
            "row:EnableMouseWheel(true)",
            'row:SetScript("OnMouseWheel", function(_, delta)',
            "scrollByWheel(scrollFrame, delta)",
        ):
            self.assertIn(token, mount_page)
        self.assertNotIn("self:GetVerticalScroll()", mount_page)

    def test_mount_empty_refresh_clears_previous_selection_before_showing_empty_state(self):
        mounts = read_text(ADDON / "UI" / "Mounts.lua")
        mount_page = lua_function_region(mounts, "UI.CreateMountsPage")
        empty_branch = mount_page[
            mount_page.index("if #records == 0 then") : mount_page.index("else", mount_page.index("if #records == 0 then"))
        ]
        self.assertIn("self:ClearSelection()", empty_branch)
        self.assertLess(
            empty_branch.index("self:ClearSelection()"),
            empty_branch.index("UI.ShowEmptyState("),
        )

    def test_mount_model_schedulers_reuse_fixed_drivers_and_clear_queued_work(self):
        mounts = read_text(ADDON / "UI" / "Mounts.lua")
        mount_page = lua_function_region(mounts, "UI.CreateMountsPage")
        defer_start = mounts.index("local function deferNextFrame(callback)")
        defer_end = mounts.index("local function showNotice", defer_start)
        defer_region = mounts[defer_start:defer_end]
        schedule_start = mount_page.index("local function scheduleModel(delay, generation, callback)")
        schedule_end = mount_page.index("local function resetModelState", schedule_start)
        schedule_region = mount_page[schedule_start:schedule_end]

        for token in (
            'local nextFrameDriver = CreateFrame("Frame")',
            "local nextFrameQueue = {}",
            "local function runNextFrameQueue(self)",
            'local modelTimerDriver = CreateFrame("Frame", nil, page)',
            "page.scModelTasks = {}",
            "for index = #page.scModelTasks, 1, -1 do",
            "table.remove(page.scModelTasks, index)",
            'modelTimerDriver:SetScript("OnUpdate", nil)',
        ):
            self.assertIn(token, mounts)
        self.assertNotIn("CreateFrame(", defer_region)
        self.assertNotIn("CreateFrame(", schedule_region)
        self.assertIn("table.insert(nextFrameQueue, callback)", defer_region)
        self.assertIn("table.insert(page.scModelTasks", schedule_region)

    def test_five_main_tabs_are_anchored_outside_the_journal(self):
        journal = read_text(ADDON / "UI" / "CollectionsFrame.lua")
        tab_keys = re.findall(
            r'\{\s*key\s*=\s*"(MOUNTS|PETS|TOYS|WARDROBE|TITLES)"',
            journal,
        )
        self.assertEqual(["MOUNTS", "PETS", "TOYS", "WARDROBE", "TITLES"], tab_keys)
        self.assertIn("JOURNAL_HEIGHT = 793", journal)
        self.assertRegex(
            journal,
            r'button:SetPoint\(\s*"TOPLEFT",\s*frame,\s*"BOTTOMLEFT"',
        )
        self.assertRegex(
            journal,
            r'button:SetPoint\(\s*"(?:TOPLEFT|LEFT)",\s*previousTab,\s*"(?:TOPRIGHT|RIGHT)"',
        )
        self.assertIn('button:SetPoint("TOPLEFT", previousTab, "TOPRIGHT", 6, 0)', journal)

    def test_mount_preview_uses_correlated_model_requests_and_335_model_controls(self):
        mounts_path = ADDON / "UI" / "Mounts.lua"
        self.assertTrue(mounts_path.is_file(), f"missing {mounts_path}")
        mounts = read_text(mounts_path)
        for token in (
            'CreateFrame("PlayerModel"',
            "ClearModel()",
            "SetCreature(",
            "self:GetModel()",
            "SC.Bridge.RequestCreaturePreview(10,",
            "scModelGeneration",
            'SetScript("OnMouseDown"',
            'SetScript("OnMouseUp"',
            'SetScript("OnUpdate"',
            'SetScript("OnMouseWheel"',
            "GetCursorPosition()",
            "UIParent:GetEffectiveScale()",
            'IsMouseButtonDown("LeftButton")',
            "clearDragState()",
            "clearModelInteraction()",
            "SetRotation(",
            "SetModelScale(",
            "0.35",
            "2.5",
            "pcall(function()",
            'SetText("重置视角")',
            'SetText("无法预览")',
            'SetScript("OnHide"',
        ):
            self.assertIn(token, mounts)
        self.assertRegex(
            mounts,
            r"scModelGeneration\s*=\s*\([^\n]*scModelGeneration[^\n]*\)\s*\+\s*1",
        )
        self.assertRegex(
            mounts,
            r"if\s+(?:(?:page|self)\.scModelGeneration\s*~=\s*generation|generation\s*~=\s*(?:page|self)\.scModelGeneration)\s+then",
        )
        self.assertNotIn('SetScript("OnModelLoaded"', mounts)
        self.assertNotIn('CreateFrame("DressUpModel"', mounts)

    def test_mount_model_preserves_native_framing_and_requires_a_stable_path(self):
        mounts = read_text(ADDON / "UI" / "Mounts.lua")
        page = lua_function_region(mounts, "UI.CreateMountsPage")
        apply_model = page[
            page.index("local function applyModel") : page.index("local function requestModel")
        ]
        for token in (
            "local MODEL_STABILITY_DELAY = 0.35",
            "local MODEL_MAX_STABILITY_RESTARTS = 8",
            "candidatePath",
            "candidateFrames",
            "stablePath",
            "MODEL_STABILITY_DELAY",
            "stabilityRestarts > MODEL_MAX_STABILITY_RESTARTS",
            "expectedPath = page.scModelPaths[record.id]",
            "page.scModelPaths[record.id] = currentPath",
            "page.scModelReady = true",
            "model.scBaseScale",
            "model:GetModelScale()",
            "self.scBaseScale * zoom",
        ):
            self.assertIn(token, mounts)
        self.assertNotIn("resetModelView()", apply_model)
        self.assertNotIn("SetCamera(", apply_model)
        self.assertNotIn("SetModelScale(DEFAULT_MODEL_SCALE)", apply_model)
        self.assertNotIn("SetPosition(0, 0, 0)", apply_model)
        self.assertNotIn("MODEL_FIRST_SWITCH_WINDOWS", mounts)
        self.assertNotIn("MODEL_CLEAR_BARRIER_FRAMES", mounts)
        self.assertNotIn("waitForClearedModel", apply_model)
        self.assertNotIn("previousModelPath", apply_model)

        set_creature = apply_model[
            apply_model.index("setCreatureAndVerify = function") :
            apply_model.index("setCreatureAndVerify()", apply_model.index("setCreatureAndVerify = function"))
        ]
        self.assertIn("model:ClearModel()", set_creature)
        self.assertIn("model:SetCreature(record.previewCreatureEntry)", set_creature)
        self.assertIn("scheduleModel(0, generation, verifyModel)", set_creature)
        fail_model = apply_model[
            apply_model.index("local function failModel") : apply_model.index("local function retryLoad")
        ]
        self.assertIn("model:ClearModel()", fail_model)

        wheel = page[
            page.index('model:SetScript("OnMouseWheel"') : page.index('page:SetScript("OnHide"')
        ]
        self.assertIn("if not page.scModelReady", wheel)
        self.assertIn("if not self.scBaseScale then", wheel)
        self.assertNotIn("getNativeModelScale()", wheel)

        reset = page[
            page.index('reset:SetScript("OnClick"') : page.index('infoButton:SetScript("OnClick"')
        ]
        self.assertIn("requestModel(record)", reset)
        self.assertNotIn("SetModelScale", reset)

    def test_uncollected_mount_favorite_controls_are_disabled(self):
        mounts = read_text(ADDON / "UI" / "Mounts.lua")
        page = lua_function_region(mounts, "UI.CreateMountsPage")
        for token in (
            "favoriteInfo.disabled = 1",
            'favoriteInfo.tooltipTitle = "尚未收集"',
            "favorite:Disable()",
            "favorite:Enable()",
            "if not record.collected then",
        ):
            self.assertIn(token, page)

    def test_mount_detail_icon_and_model_retry_pipeline_are_bounded(self):
        mounts = read_text(ADDON / "UI" / "Mounts.lua")
        mount_page = lua_function_region(mounts, "UI.CreateMountsPage")
        for token in (
            'local infoButton = CreateFrame("Button"',
            "infoButton:SetWidth(38)",
            "infoButton:SetHeight(38)",
            'infoButton:RegisterForClicks("LeftButtonUp", "RightButtonUp")',
            "SC.Bridge.RequestCreaturePreview(10, record.id,",
            "deferNextFrame(",
            "GetModel()",
        ):
            self.assertIn(token, mount_page)
        self.assertRegex(
            mounts,
            r"MODEL_RETRY_DELAYS\s*=\s*\{\s*0\.1\s*,\s*0\.25\s*,\s*0\.5\s*\}",
        )
        self.assertRegex(mounts, r"MODEL_MAX_WINDOW\s*=\s*2")
        self.assertIn('unavailable:SetText("模型预览暂不可用")', mount_page)
        self.assertRegex(
            mount_page,
            r"retryIndex\s*=\s*retryIndex\s*\+\s*1",
        )
        self.assertRegex(
            mount_page,
            r"retryIndex\s*<=\s*#MODEL_RETRY_DELAYS",
        )
        self.assertRegex(
            mount_page,
            r"MODEL_RETRY_DELAYS\s*\[\s*retryIndex\s*\]",
        )

    def test_collection_icons_use_the_335_desaturation_wrapper(self):
        templates = read_text(ADDON / "UI" / "Templates.lua")
        self.assertIn("function UI.SetCollectedVisual(", templates)
        self.assertIn("SetDesaturation(texture, not collected)", templates)
        self.assertGreaterEqual(templates.count("UI.SetCollectedVisual(icon, record.collected"), 2)
        self.assertNotIn("icon:SetDesaturated(", templates)

    def test_companion_pages_expose_metadata_collection_state_and_dispatch(self):
        mounts_path = ADDON / "UI" / "Mounts.lua"
        self.assertTrue(mounts_path.is_file(), f"missing {mounts_path}")
        mounts = read_text(mounts_path)
        journal = read_text(ADDON / "UI" / "CollectionsFrame.lua")
        for token in (
            "record.source",
            "record.description",
            "record.collected",
            "record.favorite",
            'SetText("已收集")',
            'SetText("未收集")',
            'SetText("设为偏好")',
        ):
            self.assertIn(token, mounts)
        for token in (
            "UI.CreateMountsPage(",
            "UI.CreatePetsPage(",
            "function UI.RefreshActivePage()",
            'SC.db.mainTab == "MOUNTS"',
            'SC.db.mainTab == "PETS"',
        ):
            self.assertIn(token, journal)

    def test_pets_page_has_no_battle_pet_semantics(self):
        pets_path = ADDON / "UI" / "Pets.lua"
        self.assertTrue(pets_path.is_file(), f"missing {pets_path}")
        pets = read_text(pets_path).lower()
        for forbidden in (
            "battle",
            "level",
            "rarity",
            "ability",
            "health",
            "loadout",
            "revive",
            "cage",
            "release",
        ):
            self.assertNotIn(forbidden, pets)

    def test_toy_box_uses_eighteen_pooled_tiles_with_shared_catalog_controls(self):
        toys_path = ADDON / "UI" / "Toys.lua"
        self.assertTrue(toys_path.is_file(), f"missing {toys_path}")
        toys = read_text(toys_path)
        journal = read_text(ADDON / "UI" / "CollectionsFrame.lua")
        for token in (
            "function UI.CreateToysPage(",
            "VISIBLE_TILES = 18",
            "GRID_COLUMNS = 3",
            "for index = 1, VISIBLE_TILES do",
            "UI.CreateIconTile(",
            'Catalog.Query("TOYS"',
            'Catalog.GetProgress("TOYS"',
            'Catalog.ToggleDemoFavorite("TOYS"',
            "UI.CreatePageControls(",
            "function page:Refresh()",
            "function page:ClearSelection()",
            "self.scPage = currentPage",
            "UI.ShowEmptyState(",
        ):
            self.assertIn(token, toys)
        self.assertIn("TOYS = UI.CreateToysPage(contentHost)", journal)
        self.assertIn('SC.db.mainTab == "TOYS"', journal)

    def test_toy_box_uses_retail_style_three_by_six_layout(self):
        toys = read_text(ADDON / "UI" / "Toys.lua")
        self.assertIn("local GRID_COLUMNS = 3", toys)
        self.assertIn("local VISIBLE_TILES = 18", toys)
        self.assertIn("tile.scIcon:ClearAllPoints()", toys)
        self.assertIn("tile.scName:SetJustifyH(\"LEFT\")", toys)
        self.assertIn("local GRID_PADDING_X = 16", toys)
        self.assertIn("local GRID_PADDING_TOP = 12", toys)
        self.assertIn("local GRID_COLUMN_GAP = 6", toys)
        self.assertIn("local TILE_HEIGHT = 72", toys)
        self.assertNotIn("local TILE_WIDTH =", toys)
        self.assertIn("local function layoutTiles()", toys)
        self.assertIn('grid:SetScript("OnSizeChanged", layoutTiles)', toys)
        self.assertIn("local leftMargin = math.floor((gridWidth - blockWidth) / 2)", toys)
        self.assertIn("column * (tileWidth + GRID_COLUMN_GAP)", toys)
        self.assertIn("GRID_PADDING_TOP + (row * TILE_HEIGHT)", toys)

        for grid_width in (848, 1014, 1354, 1908, 2548, 3428):
            tile_width = (grid_width - (2 * 16) - (2 * 6)) // 3
            block_width = (3 * tile_width) + (2 * 6)
            left_margin = (grid_width - block_width) // 2
            right_margin = grid_width - left_margin - block_width
            self.assertLessEqual(abs(left_margin - right_margin), 1)
        self.assertEqual((848 - (2 * 16) - (2 * 6)) // 3, 268)

    def test_active_collection_templates_use_independent_thin_state_borders(self):
        templates = read_text(ADDON / "UI" / "Templates.lua")
        wardrobe = read_text(ADDON / "UI" / "Wardrobe.lua")
        mounts = read_text(ADDON / "UI" / "Mounts.lua")
        pets = read_text(ADDON / "UI" / "Pets.lua")
        toys = read_text(ADDON / "UI" / "Toys.lua")

        for token in (
            "function UI.CreateThinCardBorder(parent, thickness)",
            "function UI.CreateCollectionCardBorders(parent)",
            "local collection = UI.CreateThinCardBorder(parent, 1)",
            "local selected = UI.CreateThinCardBorder(parent, 2)",
            "collection:SetCollected(false)",
            "selected:SetBorderColor(1.00, 0.78, 0.14, 1)",
            "self:SetBorderColor(0.58, 0.43, 0.16, 1)",
            "self:SetBorderColor(0.38, 0.39, 0.40, 1)",
        ):
            self.assertIn(token, templates)

        self.assertNotIn("local function createThinCardBorder", wardrobe)
        self.assertGreaterEqual(wardrobe.count("UI.CreateThinCardBorder("), 5)
        for active_source in (mounts, pets, toys):
            self.assertNotIn("UI.Media.collectedFrame", active_source)
            self.assertNotIn("UI.Media.uncollectedFrame", active_source)

        selected_match = re.search(
            r"function tile:SetSelected\(value\)(.*?)\n    end",
            templates,
            re.DOTALL,
        )
        self.assertIsNotNone(selected_match)
        set_selected = selected_match.group(1)
        self.assertIn("selectedBorder:Show()", set_selected)
        self.assertIn("selectedBorder:Hide()", set_selected)
        self.assertNotIn("SetCollected", set_selected)
        self.assertNotIn("hover:Show()", set_selected)

    def test_phase_four_runtime_audit_covers_layout_state_and_reload_contracts(self):
        audit = read_text(ROOT / "tools" / "runtime" / "SoloCollectionsLayoutAudit" / "LayoutAudit.lua")
        toc = read_text(ROOT / "tools" / "runtime" / "SoloCollectionsLayoutAudit" / "SoloCollectionsLayoutAudit.toc")
        for token in (
            "## SavedVariables: SoloCollectionsLayoutAuditDB",
            "## Dependencies: SoloCollections",
        ):
            self.assertIn(token, toc)
        for token in (
            "GetScreenWidth()",
            "GetScreenHeight()",
            'GetCVar("uiScale")',
            "UIParent:GetEffectiveScale()",
            "toyPage.scLayoutTiles()",
            "math.abs(leftMargin - rightMargin) <= 1.01",
            "visibleCounts.one == 1",
            "visibleCounts.two == 2",
            "visibleCounts.four == 4",
            "visibleCounts.full == 18",
            "firstCollectionAfterSelection",
            "hoverVisible",
            "reloadRestored",
            "Screenshot()",
        ):
            self.assertIn(token, audit)
        runner = read_text(ROOT / "tools" / "runtime" / "Start-SoloCollectionsLayoutAudit.ps1")
        for token in (
            "[Security.SecureString]$Password",
            "Assert-AbsoluteNonCPath",
            "Set-ConfigValue $lines 'gxResolution' $Resolution",
            "Set-ConfigValue $lines 'uiScale'",
            "Invoke-Reload $processName $commandScript",
            "SoloCollectionsLayoutAudit.lua",
            "EnsureDesktopAtLeast",
            "RestoreDesktop()",
        ):
            self.assertIn(token, runner)

    def test_toy_box_enriches_tooltips_and_refreshes_item_cache_safely(self):
        toys_path = ADDON / "UI" / "Toys.lua"
        self.assertTrue(toys_path.is_file(), f"missing {toys_path}")
        toys = read_text(toys_path)
        for token in (
            "GetItemInfo(record.itemId)",
            "GetItemIcon(record.itemId)",
            "GameTooltip:SetOwner(",
            "GameTooltip:SetHyperlink(itemLink)",
            "record.source",
            "record.description",
            'RegisterEvent("GET_ITEM_INFO_RECEIVED")',
            'SetScript("OnEvent"',
            "page:Refresh()",
            "UI.SetCollectedVisual(",
            "tile:SetSelected(",
        ):
            self.assertIn(token, toys)
        for forbidden in (
            "UseItemByName",
            "PickupItem",
            "CastSpell",
            "SendAddonMessage",
            "RunScript",
        ):
            self.assertNotIn(forbidden, toys)

    def test_toy_box_uses_collected_toys_and_drags_persistent_macro_actions(self):
        toys = read_text(ADDON / "UI" / "Toys.lua")
        bootstrap = read_text(ADDON / "Core" / "Bootstrap.lua")
        for token in (
            "local COLLECTED_NAME_COLOR = { 1.00, 0.82, 0.18 }",
            "local UNCOLLECTED_NAME_COLOR = { 0.46, 0.43, 0.39 }",
            "tile.scName:SetTextColor(",
            'tile:RegisterForClicks("LeftButtonUp", "RightButtonUp")',
            'tile:RegisterForDrag("LeftButton")',
            'tile:SetScript("OnDragStart"',
            "CreateMacro(",
            "EditMacro(",
            "PickupMacro(",
            "FALLBACK_MACRO_ICON = 1",
            "local function createToyMacro(",
            "InCombatLockdown()",
            '"/sc toy "',
            "SC.Bridge.UseToy(record.id",
            "UIDropDownMenu_Initialize(",
            'useInfo.text = "使用玩具"',
            "ToggleDropDownMenu(",
            "if not record.collected then",
        ):
            self.assertIn(token, toys)
        self.assertIn('string.match(command, "^toy%s+(%d+)$")', bootstrap)
        self.assertIn("SC.Bridge.UseToy(tonumber(toyId)", bootstrap)
        self.assertNotIn("UseItemByName", toys)
        self.assertNotIn("PickupItem", toys)

    def test_wardrobe_items_use_retail_style_eighteen_model_grid(self):
        path = ADDON / "UI" / "Wardrobe.lua"
        self.assertTrue(path.is_file(), f"missing {path}")
        text = read_text(path)
        journal = read_text(ADDON / "UI" / "CollectionsFrame.lua")
        for token in (
            "function UI.CreateWardrobePage(",
            "ITEM_ROWS = 3",
            "ITEM_COLUMNS = 6",
            "ITEM_PAGE_SIZE = ITEM_ROWS * ITEM_COLUMNS",
            "for index = 1, ITEM_PAGE_SIZE do",
            'local itemModel = CreateFrame("DressUpModel", nil, itemCard)',
            "itemModel:SetAllPoints(itemCard)",
            "page.scItemModels[index] = itemModel",
            'Catalog.Query("APPEARANCES"',
            'Catalog.GetProgress("APPEARANCES"',
            'Catalog.ToggleDemoFavorite("APPEARANCES"',
            "UI.CreatePageControls(",
            'filters.classToken',
            'filters.slot',
            "GameTooltip:SetHyperlink(itemLink)",
            "itemModel.scBorder",
            "itemModel.scName",
            "itemModel.scFavorite",
            "itemModel.scCollectionState",
        ):
            self.assertIn(token, text)
        self.assertNotIn("scUncollectedOverlay", text)
        self.assertNotIn("uncollectedOverlay", text)
        self.assertNotIn("UI.CreateIconTile(itemsPanel", text)
        self.assertIn("WARDROBE = UI.CreateWardrobePage(contentHost)", journal)

    def test_wardrobe_uncollected_items_use_retail_style_border_and_badge_without_model_veil(self):
        text = read_text(ADDON / "UI" / "Wardrobe.lua")
        for token in (
            'collectionStateLabel:SetText("未收集")',
            "collectionState:SetWidth(58)",
            "itemModel.scCollectionState:Show()",
            "itemModel.scCollectionState:Hide()",
            "itemModel.scBorder:SetCollected(record.collected)",
            "itemModel.scName:SetTextColor(0.62, 0.62, 0.60)",
        ):
            self.assertIn(token, text)
        self.assertNotIn("scUncollectedOverlay", text)
        self.assertNotIn("uncollectedOverlay", text)

    def test_wardrobe_item_models_use_slot_camera_profiles_and_try_on_item_strings(self):
        text = read_text(ADDON / "UI" / "Wardrobe.lua")
        for token in (
            "local WARDROBE_MODEL_PROFILES = {",
            "HEAD = {",
            "SHOULDER = {",
            "CHEST = {",
            "WRIST = {",
            "HANDS = {",
            "WAIST = {",
            "LEGS = {",
            "FEET = {",
            "local function applyItemModelRecord(model, record, pageGeneration)",
            "local function selectItemModelCamera(model)",
            "local function applyItemModelTransform(model)",
            "local function queueItemModelView(model, force)",
            "local function finishPendingItemModelView(model)",
            'model:SetUnit("player")',
            "model:Undress()",
            "model:SetCamera(model.scClientCameraSentinel)",
            "model:SetCamera(1)",
            "model:GetModelScale()",
            "model:GetPosition()",
            "model:SetModelScale(nativeScale * (profile.scaleMultiplier or 1.00))",
            "model:SetPosition(nativeHorizontal + (profile.horizontalOffset or 0), nativeVertical + (profile.verticalOffset or 0), nativeDepth + (profile.depthOffset or 0))",
            "model:SetRotation(profile.rotation)",
            "resolveTryOnItem(record.itemId)",
            "model:TryOn(itemString)",
        ):
            self.assertIn(token, text)
        for forbidden in (
            "ModelScene",
            "C_TransmogCollection",
            "Model_ApplyUICamera",
            "GetUICameraInfo",
            "UndressSlot",
            "SetKeepModelOnHide",
            "SetCustomCamera",
            "MakeCurrentCameraCustom",
            "SetCameraPosition",
            "SetCameraTarget",
            "SetCameraDistance",
            "SetPortraitZoom",
        ):
            self.assertNotIn(forbidden, text)

    def test_wardrobe_human_female_profiles_use_native_relative_offsets(self):
        text = read_text(ADDON / "UI" / "Wardrobe.lua")
        vertical_positions = {}
        depth_positions = {}
        model_scales = {}
        for slot in ("HEAD", "SHOULDER", "CHEST", "WRIST", "HANDS", "WAIST", "LEGS", "FEET"):
            vertical_match = re.search(
                rf"{slot}\s*=\s*\{{[^}}]*?verticalOffset\s*=\s*(-?\d+(?:\.\d+)?)",
                text,
            )
            depth_match = re.search(
                rf"{slot}\s*=\s*\{{[^}}]*?depthOffset\s*=\s*(-?\d+(?:\.\d+)?)",
                text,
            )
            scale_match = re.search(
                rf"{slot}\s*=\s*\{{[^}}]*?scaleMultiplier\s*=\s*(-?\d+(?:\.\d+)?)",
                text,
            )
            self.assertIsNotNone(vertical_match, f"missing native-relative vertical offset for {slot}")
            self.assertIsNotNone(depth_match, f"missing native-relative depth offset for {slot}")
            self.assertIsNotNone(scale_match, f"missing native-relative scale for {slot}")
            vertical_positions[slot] = float(vertical_match.group(1))
            depth_positions[slot] = float(depth_match.group(1))
            model_scales[slot] = float(scale_match.group(1))

        self.assertEqual(vertical_positions["HEAD"], 0)
        self.assertLess(vertical_positions["CHEST"], 0, "chest zoom must pull the enlarged torso back into the card")
        self.assertEqual(depth_positions["HEAD"], 0)
        self.assertGreater(model_scales["CHEST"], 2, "chest needs a real crop, not another full-body view")

    def test_wardrobe_avoids_unusable_free_camera_for_item_cards(self):
        text = read_text(ADDON / "UI" / "Wardrobe.lua")
        cameras = {}
        for slot in ("DEFAULT", "HEAD", "SHOULDER", "CHEST", "WRIST", "HANDS", "WAIST", "LEGS", "FEET"):
            match = re.search(
                rf"{slot}\s*=\s*\{{[^}}]*?camera\s*=\s*(\d+)",
                text,
            )
            self.assertIsNotNone(match, f"missing camera index for {slot}")
            cameras[slot] = int(match.group(1))

        self.assertEqual(cameras["HEAD"], 0)
        for slot in ("DEFAULT", "SHOULDER", "CHEST", "WRIST", "HANDS", "WAIST", "LEGS", "FEET"):
            self.assertEqual(cameras[slot], 1, f"{slot} must use the full-body dressing-room camera")

    def test_wardrobe_shoulder_rotation_is_owned_by_native_camera_hook(self):
        text = read_text(ADDON / "UI" / "Wardrobe.lua")
        head = re.search(r"HEAD\s*=\s*\{([^}]*)\}", text)
        shoulder = re.search(r"SHOULDER\s*=\s*\{([^}]*)\}", text)
        self.assertIsNotNone(head)
        self.assertIsNotNone(shoulder)
        self.assertIn("rotation = 0.50", head.group(1))
        self.assertIn("rotation = 0.50", shoulder.group(1))

    def test_wardrobe_does_not_expose_unreliable_model_animation_controls(self):
        bootstrap = read_text(ADDON / "Core" / "Bootstrap.lua")
        wardrobe = read_text(ADDON / "UI" / "Wardrobe.lua")
        self.assertNotIn("wardrobeModelsAnimated", bootstrap)
        for token in (
            "animationToggle",
            "animationLabel",
            "wardrobeModelsAnimated",
            "applyModelAnimationState",
            "holdStaticModelFrame",
            "SetSequenceTime",
            "scApplyingStaticPose",
        ):
            self.assertNotIn(token, wardrobe)

    def test_wardrobe_item_cards_keep_legacy_models_in_fixed_card_rectangles(self):
        text = read_text(ADDON / "UI" / "Wardrobe.lua")
        chest = re.search(r"CHEST\s*=\s*\{([^}]*)\}", text)
        self.assertIsNotNone(chest)
        chest_profile = chest.group(1)
        for token in (
            "camera = 1",
            "scaleMultiplier = 2.40",
            "depthOffset = 0.00",
            "horizontalOffset = 0.00",
            "verticalOffset = -0.30",
        ):
            self.assertIn(token, chest_profile)

        for forbidden in (
            "canvasScale",
            "cropHorizontal",
            "cropVertical",
            "applyItemModelViewport",
            'CreateFrame("ScrollFrame", nil, itemCard)',
            "SetScrollChild(itemModel)",
            "SetHorizontalScroll(horizontalScroll)",
            "SetVerticalScroll(profile.cropVertical or 0)",
        ):
            self.assertNotIn(forbidden, text)

        self.assertIn('local itemModel = CreateFrame("DressUpModel", nil, itemCard)', text)
        self.assertIn("itemModel:SetAllPoints(itemCard)", text)

    def test_wardrobe_chest_uses_captured_native_framing_without_unavailable_camera_apis(self):
        text = read_text(ADDON / "UI" / "Wardrobe.lua")
        transform = text[
            text.index("local function captureItemModelBaseline(model)") :
            text.index("local function queueItemModelView(model, force)")
        ]
        apply_transform = text[
            text.index("local function applyItemModelTransform(model)") :
            text.index("local function queueItemModelView(model, force)")
        ]
        for token in (
            "model:GetModelScale()",
            "model:GetPosition()",
            "model.scNativeScale = nativeScale",
            "model.scNativeHorizontal = nativeHorizontal",
            "model.scNativeVertical = nativeVertical",
            "model.scNativeDepth = nativeDepth",
            "model.scBaselineGeneration = model.scAppearanceGeneration",
        ):
            self.assertIn(token, transform)
        self.assertIn("captureItemModelBaseline(model)", apply_transform)
        self.assertIn("nativeScale * (profile.scaleMultiplier or 1.00)", apply_transform)
        self.assertNotIn("SetCamDistanceScale", text)
        self.assertNotIn("camDistanceScale", text)
        self.assertNotIn("SetWidth", apply_transform)
        self.assertNotIn("SetHeight", apply_transform)

    def test_wardrobe_waits_for_item_model_load_before_trying_on(self):
        text = read_text(ADDON / "UI" / "Wardrobe.lua")
        for token in (
            "local function finishPendingItemModel(model)",
            "model.scPendingItemString",
            "model.scModelReadyFrames",
            "model:GetModel()",
            "model:Undress()",
            "model:TryOn(itemString)",
            "itemModel.scUpdateHandler = updatePendingItemModel",
            "finishPendingItemModel(self)",
        ):
            self.assertIn(token, text)

        apply_record = text[
            text.index("local function applyItemModelRecord(model, record, pageGeneration)") :
            text.index("function UI.CreateWardrobePage(parent)")
        ]
        self.assertIn("model.scPendingItemString = resolveTryOnItem(record.itemId)", apply_record)
        self.assertIn('model:SetUnit("player")', apply_record)
        self.assertNotIn("model:Undress()", apply_record)
        self.assertNotIn("model:TryOn(itemString)", apply_record)

    def test_wardrobe_item_models_stop_per_frame_updates_after_settling(self):
        text = read_text(ADDON / "UI" / "Wardrobe.lua")
        for token in (
            "local function updatePendingItemModel(self)",
            'model:SetScript("OnUpdate", nil)',
            "itemModel.scUpdateHandler = updatePendingItemModel",
            'model:SetScript("OnUpdate", model.scUpdateHandler)',
            "not self.scPendingItemString and not self.scViewStage",
        ):
            self.assertIn(token, text)

    def test_wardrobe_defers_item_transforms_until_the_camera_settles(self):
        text = read_text(ADDON / "UI" / "Wardrobe.lua")

        camera_region = text[
            text.index("local function selectItemModelCamera(model)") :
            text.index("local function applyItemModelTransform(model)")
        ]
        transform_region = text[
            text.index("local function applyItemModelTransform(model)") :
            text.index("local function queueItemModelView(model, force)")
        ]
        view_region = text[
            text.index("local function finishPendingItemModelView(model)") :
            text.index("local function finishPendingItemModel(model)")
        ]
        pending_region = text[
            text.index("local function finishPendingItemModel(model)") :
            text.index("local function applyItemModelRecord(model, record, pageGeneration)")
        ]

        self.assertIn("model:SetCamera(model.scClientCameraSentinel)", camera_region)
        self.assertGreaterEqual(camera_region.count("model:SetCamera(1)"), 2)
        self.assertNotIn("SetPosition", camera_region)
        self.assertNotIn("SetRotation", camera_region)
        self.assertNotIn("SetModelScale", camera_region)
        self.assertIn("model:SetModelScale(nativeScale * (profile.scaleMultiplier or 1.00))", transform_region)
        self.assertIn("model:SetPosition(nativeHorizontal + (profile.horizontalOffset or 0), nativeVertical + (profile.verticalOffset or 0), nativeDepth + (profile.depthOffset or 0))", transform_region)
        self.assertIn("model:SetRotation(profile.rotation)", transform_region)
        self.assertNotIn("SetCamera", transform_region)

        for token in (
            'model.scViewStage == "CAMERA"',
            'model.scViewStage = "SETTLE"',
            "model.scViewFrames = model.scViewFrames + 1",
            "model.scViewFrames < 2",
            "applyItemModelTransform(model)",
        ):
            self.assertIn(token, view_region)
        self.assertLess(pending_region.index("model:TryOn(itemString)"), pending_region.index("queueItemModelView(model, true)"))
        self.assertNotIn("applyItemModelTransform(model)", pending_region)

        update_model = text[
            text.index('itemModel:SetScript("OnUpdateModel"') :
            text.index('itemModel:SetScript("OnUpdate"')
        ]
        self.assertIn("queueItemModelView(self, true)", update_model)
        self.assertNotIn("applyItemModelProfile", update_model)
        self.assertNotIn("SetCamera", update_model)
        self.assertNotIn("SetPosition", update_model)

        update = text[
            text.index("local function updatePendingItemModel(self)") :
            text.index("local function applyItemModelRecord(model, record, pageGeneration)")
        ]
        self.assertIn("local appearanceApplied = finishPendingItemModel(self)", update)
        self.assertIn("finishPendingItemModelView(self)", update)
        self.assertLess(update.index("finishPendingItemModel(self)"), update.index("finishPendingItemModelView(self)"))

    def test_wardrobe_set_to_item_transition_invalidates_dressup_cache(self):
        text = read_text(ADDON / "UI" / "Wardrobe.lua")
        refresh_sets = text[text.index("local function refreshSets()") : text.index("function page:Refresh()")]
        self.assertIn("for _, itemModel in ipairs(page.scItemModels) do", refresh_sets)
        self.assertIn("itemModel.scRecordId = nil", refresh_sets)

    def test_wardrobe_item_model_pool_reuses_and_cleans_models(self):
        text = read_text(ADDON / "UI" / "Wardrobe.lua")
        for token in (
            "for index, itemModel in ipairs(page.scItemModels) do",
            "applyItemModelRecord(itemModel, record, pageGeneration)",
            "model:ClearModel()",
            "model:Hide()",
            "model:Show()",
            "for _, itemModel in ipairs(self.scItemModels) do",
            "itemModel:ClearModel()",
        ):
            self.assertIn(token, text)
        refresh_items = text[text.index("local function refreshItems()") : text.index("local function refreshSets()")]
        self.assertNotIn('CreateFrame("DressUpModel"', refresh_items)

    def test_wardrobe_has_dedicated_armor_class_slot_and_weapon_filters(self):
        text = read_text(ADDON / "UI" / "Wardrobe.lua")
        for token in (
            'CreateFrame("Frame", nil, page)',
            'CreateFrame("Frame", "SoloCollectionsWardrobeArmorDropdown", filterBar, "UIDropDownMenuTemplate")',
            'CreateFrame("Frame", "SoloCollectionsWardrobeClassDropdown", filterBar, "UIDropDownMenuTemplate")',
            'CreateFrame("Frame", "SoloCollectionsWardrobeWeaponDropdown", filterBar, "UIDropDownMenuTemplate")',
            'local slotsFrame = CreateFrame("Frame", nil, filterBar)',
            "UIDropDownMenu_Initialize(armorDropdown",
            "UIDropDownMenu_Initialize(classDropdown",
            "UIDropDownMenu_Initialize(weaponDropdown",
            "UIDropDownMenu_SetSelectedValue(armorDropdown, filters.armorType)",
            "UIDropDownMenu_SetSelectedValue(classDropdown, filters.classToken)",
            "UIDropDownMenu_SetSelectedValue(weaponDropdown, filters.weaponType)",
            "page.scArmorDropdown = armorDropdown",
            "page.scClassDropdown = classDropdown",
            "page.scWeaponDropdown = weaponDropdown",
            "page.scSlotsFrame = slotsFrame",
            'if SC.db.wardrobeTab == "ITEMS" then',
            "slotsFrame:Show()",
            "slotsFrame:Hide()",
        ):
            self.assertIn(token, text)
        self.assertNotIn('CreateFrame("Frame", nil, filterBar, "UIDropDownMenuTemplate")', text)

        sync_filters = text[text.index("function page:SyncFilters()") : text.index("local function refreshItems()")]
        self.assertNotIn("CLASS_FILTERS", sync_filters)
        self.assertNotIn("SLOT_FILTERS", sync_filters)

    def test_wardrobe_sets_try_on_stable_piece_order_and_show_progress(self):
        path = ADDON / "UI" / "Wardrobe.lua"
        self.assertTrue(path.is_file(), f"missing {path}")
        text = read_text(path)
        for token in (
            "VISIBLE_SET_ROWS = 8",
            "createSetListRow(",
            'Catalog.QueryAll("SETS"',
            'Catalog.GetProgress("SETS"',
            "SET_MEMBER_SLOT_ORDER",
            "ipairs(variant and variant.members or {})",
            "table.sort(result",
            "resolveTryOnItem(itemId)",
            "model:TryOn(itemString)",
            "scPieceIcons",
            "scSetProgress",
            'SC.db.wardrobeTab == "ITEMS"',
            'SC.db.wardrobeTab == "SETS"',
        ):
            self.assertIn(token, text)
        for forbidden in (
            "SaveOutfit",
            "ApplyOutfit",
            "DeleteOutfit",
            "C_Transmog",
        ):
            self.assertNotIn(forbidden, text)
        self.assertIn("setsPanel:SetWidth(350)", text)
        self.assertIn('pieces:SetPoint("TOP", name, "BOTTOM"', text)
        self.assertIn("local pieceState = deriveSetPieceState(record)", text)
        self.assertIn("SC.CollectionState.IsOwnedByType(13, appearanceId)", text)
        self.assertIn("local collectedPieces = tonumber(record.collectedCount) or 0", text)
        self.assertIn("local requiredPieces = tonumber(record.requiredCount) or #previewItems", text)
        self.assertNotIn('setProgress:SetText("套装收集进度：" .. collectedPieces .. " / " .. #previewItems)', text)
        bridge = read_text(ADDON / "Core" / "Bridge.lua")
        self.assertIn("function B.ApplySet(collectionId, variantIndex, callback)", bridge)
        self.assertIn('B.RequestSC2Action(14, collectionId, "APPLY", variantIndex, callback)', bridge)
        self.assertIn('applySet:SetText("应用套装")', text)
        self.assertIn("SC.Bridge.ApplySet(record.id, variant and variant.variantOrdinal or nil, showSetActionResult)", text)
        self.assertIn("local SET_PIECE_POOL_LIMIT = 12", text)
        self.assertIn("local piecePoolSize = SET_PIECE_POOL_LIMIT", text)
        self.assertNotIn("maxActiveSetSlots", text)

    def test_wardrobe_set_view_ignores_item_slot_filter(self):
        text = read_text(ADDON / "UI" / "Wardrobe.lua")
        self.assertIn('setFilters.slot = "ALL"', text)
        self.assertIn('Catalog.QueryAll("SETS", SC.db.query, setFilters', text)
        self.assertIn('Catalog.GetProgress("SETS", setFilters)', text)

    def test_wardrobe_preview_rotates_resets_and_cleans_up_without_modern_apis(self):
        path = ADDON / "UI" / "Wardrobe.lua"
        self.assertTrue(path.is_file(), f"missing {path}")
        text = read_text(path)
        for token in (
            'SetScript("OnMouseDown"',
            'SetScript("OnMouseUp"',
            'SetScript("OnUpdate"',
            "GetCursorPosition()",
            'IsMouseButtonDown("LeftButton")',
            "SetRotation(",
            "if model.SetPosition then",
            'SetText("重置视角")',
            'SetScript("OnHide"',
            "model:ClearModel()",
            "GameTooltip:Hide()",
        ):
            self.assertIn(token, text)
        for forbidden in ("ModelScene", "SetAtlas(", "Mixin("):
            self.assertNotIn(forbidden, text)

    def test_wardrobe_uses_item_strings_and_scopes_item_cache_events(self):
        text = read_text(ADDON / "UI" / "Wardrobe.lua")
        for token in (
            "local function resolveTryOnItem(itemId)",
            "return itemLink or (\"item:\" .. itemId)",
            "local itemId, success = ...",
            "if success == false or not itemId then",
            "itemModel.scRecord.itemId == itemId",
            "piece.scItemId == itemId",
            "itemModel.scRecordId = nil",
            "applyItemModelRecord(itemModel, itemModel.scRecord)",
            "UI.SetIconTexture(piece.scIcon",
        ):
            self.assertIn(token, text)
        self.assertNotIn("model:TryOn(record.itemId)", text)
        self.assertNotIn("model:TryOn(itemId)", text)
        event_handler = text[text.index('page:SetScript("OnEvent"'):text.index('page:SetScript("OnHide"')]
        item_cache_handler = event_handler[event_handler.index("local itemId, success = ..."):]
        self.assertNotIn("self:Refresh()", item_cache_handler)
        self.assertNotIn("preparePlayerModel()", item_cache_handler)

    def test_addon_uses_lua_51_modulo_operator(self):
        text = all_lua_text()
        self.assertNotIn("math.mod", text)


if __name__ == "__main__":
    unittest.main()
