from __future__ import annotations

import unittest

from common import ADDON, ROOT, read_text


LAB = ADDON / "UI" / "WardrobeLab"


class TransmogLabContractTests(unittest.TestCase):
    def test_lab_entry_is_experimental_and_uses_the_wide_journal_shell(self):
        bootstrap = read_text(ADDON / "Core" / "Bootstrap.lua")
        frame = read_text(ADDON / "UI" / "CollectionsFrame.lua")
        ez_templates = read_text(ADDON / "UI" / "EzCollections" / "Templates.lua")
        toc = read_text(ADDON / "SoloCollections.toc")
        self.assertIn("X-SoloCollections-BuildChannel: development", toc)
        self.assertIn("transmogLabEnabled = SC.BUILD_CHANNEL == \"development\"", bootstrap)
        self.assertIn('if key == "TRANSMOG_LAB" then', frame)
        self.assertIn('{ key = "TRANSMOG_LAB", label = "幻化", title = "幻化"', frame)
        self.assertIn("transmogLabEnabled == true", frame)
        self.assertIn("local TRANSMOG_WIDTH = 965", frame)
        self.assertIn('key == "TRANSMOG_LAB" and TRANSMOG_WIDTH', frame)
        self.assertIn("frame.scProgress:Show()", frame)
        self.assertIn("frame.scPages.TRANSMOG_LAB = SC.WardrobeLab.CreatePage(contentHost)", frame)
        self.assertIn('if db.mainTab == "TRANSMOG_LAB" and not db.experimental.transmogLabEnabled then', bootstrap)
        self.assertIn("TRANSMOG_LAB = {", ez_templates)
        self.assertIn("UI-MicroButton-Transmogrify-Up.tga", ez_templates)
        self.assertIn("fallback = \"Interface\\\\Icons\\\\INV_Chest_Cloth_17\"", ez_templates)
        self.assertNotIn("UI.Media.tabs.TRANSMOG_LAB", ez_templates)

    def test_toc_loads_lab_after_ez_wardrobe_foundation(self):
        toc = read_text(ADDON / "SoloCollections.toc")
        self.assertLess(toc.index("UI\\EzWardrobe\\DataProvider.lua"), toc.index("UI\\WardrobeLab\\Sources.lua"))
        self.assertLess(toc.index("UI\\EzWardrobe\\Model.lua"), toc.index("UI\\WardrobeLab\\Sources.lua"))
        self.assertLess(toc.index("UI\\WardrobeLab\\State.lua"), toc.index("UI\\WardrobeLab\\Controller.lua"))
        self.assertLess(toc.index("UI\\WardrobeLab\\Sources.lua"), toc.index("UI\\WardrobeLab\\Layout.lua"))
        self.assertLess(toc.index("UI\\WardrobeLab\\Layout.lua"), toc.index("UI\\CollectionsFrame.lua"))

    def test_state_submits_only_sc2_authoritative_actions(self):
        state = read_text(LAB / "State.lua")
        for token in (
            "{ key = \"SHIRT\", label = \"衬衣\", inventorySlot = 3 }",
            "{ key = \"TABARD\", label = \"战袍\", inventorySlot = 18 }",
            "function State:GetSlotApplyState(slotKey)",
            "function State:GetDraftApplyState()",
            "function State:GetSetApplyState(useCachedRecord)",
            "function State:RefreshPresetRecord()",
            "function State:MaterializePresetDrafts()",
            "function State:RejectMutationWhilePending()",
            "function State:StoreAppliedRecord(slotKey, record)",
            "function State:StoreAppliedPreset(record)",
            "local function applyAccepted(ok, reason)",
            "local function getMemberAppearanceId(member)",
            "local function selectedVariantOwned(record)",
            "local function appearanceLookup()",
            "local function appearanceRecordForMember(member, setRecord, lookup)",
            "local APPEARANCE_CATEGORY = \"APPEARANCES\"",
            "local SET_CATEGORY = \"SETS\"",
            "SC.Catalog.Get(APPEARANCE_CATEGORY)",
            "collectionId = appearanceId",
            "state.ResolveOwned(APPEARANCE_CATEGORY, id, fallback)",
            "local owned, ownershipKnown, stateName = state.ResolveOwned(APPEARANCE_CATEGORY, id, fallback)",
            "return owned and true or false, ownershipKnown and true or false, stateName",
            "local function selectedVariantOrdinal(record)",
            "local function samePresetRecord(left, right)",
            "local function sameAppearanceRecord(left, right)",
            "local BLOCKED_FAILURE_REASONS = {",
            "function State:GetBlockedFailureReason(kind, slotKey, record)",
            "local blockedReason = self:GetBlockedFailureReason(\"SLOT\", slotKey, record)",
            "local blockedReason = self:GetBlockedFailureReason(\"DRAFT\")",
            "local blockedReason = self:GetBlockedFailureReason(\"SET\")",
            "SC.Catalog.Get(SET_CATEGORY)",
            "local ordinal = selectedVariantOrdinal(record)",
            "current.scSelectedVariantMissing = nil",
            "local matchedVariant = false",
            "current.selectedVariantOrdinal = ordinal",
            "current.scSelectedVariantMissing = true",
            "local function firstDirtySlot(dirtySlots)",
            "if dirtySlots and dirtySlots[definition.key] then return definition.key end",
            "local remainingSlot = firstDirtySlot(self.dirtySlots)",
            "and { status = \"LOCAL_DRAFT\", slot = remainingSlot, revision = currentRevision() }",
            "if self.presetRecord then self:MaterializePresetDrafts() end",
            "local alreadySelected = self.presetRecord and samePresetRecord(self.presetRecord, record)",
            "self.requestState.status == \"CONFIRM_SET_PRESET\"",
            "return false, \"CONFIRM_SET_PRESET\"",
            "if slotKey then",
            "self.draftBySlot[slotKey] = draft",
            "self.dirtySlots[slotKey] = true",
            "self.presetRecord = currentSetRecord(self.presetRecord)",
            "self.presetRecord = record",
            "self.presetRecord = nil",
            "if record.scSelectedVariantMissing then return false, \"INVALID_REQUEST\" end",
            "if not ownershipKnown and ownershipState ~= \"Demo\" then return false, \"BRIDGE_UNAVAILABLE\", count end",
            "if not ownershipKnown and ownershipState ~= \"Demo\" then return false, \"BRIDGE_UNAVAILABLE\" end",
            "local variantOwned, variantOwnedCount, variantRequiredCount, variantReason = selectedVariantOwned(record)",
            "return false, \"BRIDGE_UNAVAILABLE\", variantOwnedCount, variantRequiredCount",
            "if record.ownershipKnown == false then",
            "if not variantOwned then",
            "return false, variantReason or \"NOT_OWNED\", variantOwnedCount, variantRequiredCount",
            "return true, nil, variantOwnedCount, variantRequiredCount",
            "return ok == true and (reason == nil or tostring(reason) == \"ACCEPTED\")",
            "if value and value > 0 and value == math.floor(value) then return value end",
            "if self:RejectMutationWhilePending() then return false, \"REQUEST_PENDING\" end",
            "bridgeCategoryReady(13)",
            "bridgeCategoryReady(14)",
            "SC.Bridge.ApplyAppearance(appearanceCollectionId, definition.inventorySlot",
            "SC.Bridge.ApplyAppearance(entry.collectionId, entry.inventorySlot",
            "self:StoreAppliedRecord(entry.slot, entry.record)",
            "self.draftBySlot[entry.slot], self.dirtySlots[entry.slot] = nil, nil",
            "and self.requestState.index == nextIndex and self.requestState.status == \"REQUESTING\"",
            "self.requestState.status = \"FAILED\"",
            "SC.Bridge.ApplySet(setCollectionId, variant and variant.variantOrdinal or nil",
            "self:CompleteApply(\"SLOT\"",
            "self:CompleteApply(\"DRAFT\"",
            "self:CompleteApply(\"SET\"",
            "function State:MarkClosed()",
            "self.preservedOnClose = self:HasDraft()",
            "status ~= \"CONFIRM_CLEAR\" and status ~= \"CONFIRM_SWITCH_EQUIPPED\"",
            "status ~= \"CONFIRM_SET_PRESET\"",
        ):
            self.assertIn(token, state)
        for forbidden in ("TRANSMOGRIFY:", "C_Transmog", "SendAddonMessage("):
            self.assertNotIn(forbidden, state)
        for forbidden in ("WAITING_STATE", "ObserveAuthoritativeState", "AUTHORITATIVE_REFRESH"):
            self.assertNotIn(forbidden, state)
        self.assertNotIn("if not record.collected then return false, \"NOT_OWNED\", count end", state)
        self.assertNotIn("if not record.collected then return false, \"NOT_OWNED\" end", state)
        self.assertNotIn("if ok then\n            self:CompleteApply", state)
        set_draft = state[state.index("function State:SetDraft(slotKey, record)"):state.index("function State:SetPreset(record)")]
        self.assertLess(
            set_draft.index("if self.presetRecord then self:MaterializePresetDrafts() end"),
            set_draft.index("self.draftBySlot[slotKey] = record"),
        )
        materialize = state[state.index("function State:MaterializePresetDrafts()"):state.index("function State:FailApply")]
        self.assertLess(
            materialize.index("self.presetRecord = nil"),
            materialize.index("local lookup = appearanceLookup()"),
        )
        self.assertIn("self.draftBySlot[slotKey] = draft", materialize)
        self.assertIn("self.dirtySlots[slotKey] = true", materialize)
        set_preset = state[state.index("function State:SetPreset(record)"):state.index("function State:ClearDraft")]
        self.assertLess(
            set_preset.index("self.requestState.status == \"CONFIRM_SET_PRESET\""),
            set_preset.index("self.draftBySlot, self.dirtySlots = {}, {}"),
        )
        self.assertLess(
            set_preset.index("return false, \"CONFIRM_SET_PRESET\""),
            set_preset.index("self.draftBySlot, self.dirtySlots = {}, {}"),
        )
        clear_draft = state[state.index("function State:ClearDraft(slotKey)"):state.index("function State:GetDirtyCount")]
        self.assertLess(
            clear_draft.index("if self.presetRecord then self:MaterializePresetDrafts() end"),
            clear_draft.index("self.draftBySlot[slotKey], self.dirtySlots[slotKey] = nil, nil"),
        )
        mark_closed = state[state.index("function State:MarkClosed()"):]
        for token in (
            "self.requestState = { status = \"LOCAL_PRESET\", record = self.presetRecord, revision = currentRevision() }",
            "local remainingSlot = firstDirtySlot(self.dirtySlots)",
            "and { status = \"LOCAL_DRAFT\", slot = remainingSlot, revision = currentRevision() }",
            "or { status = \"IDLE\", revision = currentRevision() }",
        ):
            self.assertIn(token, mark_closed)
        self.assertLess(
            mark_closed.index("self.preservedOnClose = self:HasDraft()"),
            mark_closed.index("local status = self.requestState and self.requestState.status"),
        )
        draft_state = state[state.index("function State:GetDraftApplyState()"):state.index("function State:GetSlotApplyState")]
        self.assertLess(
            draft_state.index("if count == 0 then return false, \"NO_DRAFT\", 0 end"),
            draft_state.index("if not SC.Bridge or type(SC.Bridge.ApplyAppearance) ~= \"function\" then"),
        )
        self.assertLess(
            draft_state.index("if not SC.Bridge or type(SC.Bridge.ApplyAppearance) ~= \"function\" then"),
            draft_state.index("local owned, ownershipKnown, ownershipState = currentAppearanceOwned(entry.record, entry.id)"),
        )
        slot_state = state[state.index("function State:GetSlotApplyState(slotKey)"):state.index("function State:GetSetApplyState")]
        self.assertLess(
            slot_state.index("if not SC.Bridge or type(SC.Bridge.ApplyAppearance) ~= \"function\" then"),
            slot_state.index("local owned, ownershipKnown, ownershipState = currentAppearanceOwned(record, id)"),
        )
        set_state = state[state.index("function State:GetSetApplyState(useCachedRecord)"):state.index("function State:GetSlotPreviewItemId")]
        self.assertLess(
            set_state.index("local variantOwned, variantOwnedCount, variantRequiredCount, variantReason = selectedVariantOwned(record)"),
            set_state.index("if not SC.Bridge or type(SC.Bridge.ApplySet) ~= \"function\" then"),
        )
        self.assertLess(
            set_state.index("if not SC.Bridge or type(SC.Bridge.ApplySet) ~= \"function\" then"),
            set_state.index("if record.ownershipKnown == false then"),
        )
        self.assertLess(
            set_state.index("if record.ownershipKnown == false then"),
            set_state.index("if not variantOwned then"),
        )

    def test_state_keeps_server_accepted_visuals_as_preview_projection(self):
        state = read_text(LAB / "State.lua")
        for token in (
            "equippedBySlot = {}, appliedBySlot = {}, draftBySlot = {}",
            "equippedCaptured = false",
            "local previous, hadPrevious = self.equippedBySlot or {}, self.equippedCaptured == true",
            "self.appliedBySlot[definition.key] = nil",
            "self.equippedCaptured = true",
            "local function appliedCopy(slotKey, record)",
            "self:StoreAppliedPreset(self.presetRecord)",
            "self:StoreAppliedRecord(slotKey, self.draftBySlot[slotKey])",
            "self:StoreAppliedRecord(entry.slot, entry.record)",
            "local applied = self.appliedBySlot and self.appliedBySlot[slotKey]",
            "if itemId then return itemId, true, \"PRESET\" end",
            "if draft then return recordItemId(draft), true, \"DRAFT\" end",
            "if applied then return recordItemId(applied), false, \"APPLIED\" end",
            "return equipped, false, equipped and \"EQUIPPED\" or \"EMPTY\"",
            "recordItemId(self.draftBySlot[definition.key] or",
            "(self.appliedBySlot and self.appliedBySlot[definition.key])",
            "self:CompleteApply(\"SLOT\", slotKey, reason)",
            "self:CompleteApply(\"DRAFT\", nil, \"ACCEPTED\", { appliedCount = #queue })",
            "self:CompleteApply(\"SET\", nil, reason)",
        ):
            self.assertIn(token, state)

        preview_state = state[state.index("function State:GetSlotPreviewItemId(slotKey)"):state.index("function State:GetPreviewItemIds")]
        self.assertLess(preview_state.index("local draft = self.draftBySlot[slotKey]"), preview_state.index("local applied = self.appliedBySlot"))
        self.assertLess(preview_state.index("local applied = self.appliedBySlot"), preview_state.index("local equipped = self.equippedBySlot[slotKey]"))
        self.assertIn("if applied then return recordItemId(applied), false, \"APPLIED\" end", preview_state)

    def test_sources_reuse_ez_item_provider_and_sync_lab_filters(self):
        sources = read_text(LAB / "Sources.lua")
        provider = read_text(ADDON / "UI" / "EzWardrobe" / "DataProvider.lua")
        wardrobe_catalog = read_text(
            ROOT / "addon" / "SoloCollections_WardrobeData" / "Data" / "Generated" / "WardrobeCatalog.lua"
        )
        for token in (
            "SC.WardrobeUI.ItemCardRenderer",
            "SC.EzWardrobe.DataProvider:Create(host)",
            "itemDataProvider:QueryItems(",
            "{ slot = state.selectedSlot }",
            "function host:SyncFilters()",
            "host:SetFilter(\"weaponType\"",
            "label = \"武器：全部可用\"",
            "host:SetFilter(\"weaponType\", \"AUTO\")",
            "host:SetFilter(\"armorType\"",
            "label = \"护甲：职业默认\"",
            "host:SetFilter(\"armorType\", \"AUTO\")",
            "local function armorFilterApplies(slotKey)",
            "if not armorFilterApplies(slotKey) then filters.armorType = \"ALL\" end",
            "local function copySetFilters()",
            "filters.slot = \"ALL\"",
            "filters.armorType = \"ALL\"",
            "filters.weaponType = \"ALL\"",
            "elseif self.mode == \"ITEMS\" and armorFilterApplies(state.selectedSlot) then",
            "itemDataProvider:GetArmorState(state.selectedSlot)",
            "host:SetFilter(\"classToken\"",
            "SC.Catalog.Query(\"SETS\"",
            "local function setRecordKey(record)",
            "local recordKey = setRecordKey(record)",
            "local changed = not record or self.scRecordKey ~= recordKey",
            "card.scRecordKey == recordKey",
            "self.scRecordKey = recordKey",
            "setRecordKey(record) == setRecordKey(state.presetRecord)",
            "and setRecordKey(state.requestState.record) == setRecordKey(record)",
            "function host:ContainsVisibleItem(itemId)",
            "memberContainsItem(member, itemId)",
            "record = state.presetRecord",
            "state:RefreshPresetRecord()",
            "state:GetSetApplyState(true)",
            "local canApplySet, _, variantOwned, variantRequired = false, nil, nil, nil",
            "canApplySet, _, variantOwned, variantRequired = state:GetSetApplyState(true)",
            "local owned = tonumber(variantOwned) or tonumber(state.presetRecord.collectedCount) or 0",
            "当前版本尚未收集完整",
            "local function showApplySetTooltip(self)",
            "local applySetDisabledTip = CreateFrame(\"Frame\", nil, applySet)",
            "applySetDisabledTip:SetAllPoints(applySet)",
            "applySetDisabledTip:EnableMouse(true)",
            "applySetDisabledTip:SetScript(\"OnEnter\", showApplySetTooltip)",
            "applySetDisabledTip:Hide()",
            "applySetDisabledTip:Show()",
            "host.scApplySetDisabledTip = applySetDisabledTip",
            "if self.scLastQuery ~= query then",
            "self.scLastQuery = query",
            "if self.mode == \"ITEMS\" then",
            "elseif self.mode == \"SETS\" then",
            "local ITEM_COLUMNS = 6",
            "local ITEM_PAGE_SIZE = 18",
            "local ITEM_WIDTH = 78",
            "local ITEM_HEIGHT = 104",
            "local ITEM_FIRST_CENTER_X = -238",
            "local ITEM_FIRST_TOP_Y = -85",
            "\"TOP\", itemsView, \"TOP\"",
            "ITEM_FIRST_CENTER_X + column * (ITEM_WIDTH + ITEM_GAP_X)",
            "ITEM_FIRST_TOP_Y - row * (ITEM_HEIGHT + ITEM_GAP_Y)",
            "itemControls:SetPoint(\"BOTTOM\", itemsView, \"BOTTOM\", 22, 38)",
            "setControls:SetPoint(\"BOTTOM\", setsView, \"BOTTOM\", 22, 38)",
            "applySet:Hide()",
            "selectedItemName:Hide()",
            "selectedSetName:Hide()",
            "frame.scFilterButton:SetText(self.mode == \"ITEMS\" and \"来源\" or \"过滤器\")",
            "selectedItemName:SetWidth(260)",
        ):
            self.assertIn(token, sources)
        self.assertNotIn("filters.weaponType = options[1] and options[1].key", sources)
        set_card_record = sources[
            sources.index("for index = 1, SET_PAGE_SIZE do"):
            sources.index("function card:SetSelected(value)", sources.index("for index = 1, SET_PAGE_SIZE do"))
        ]
        self.assertNotIn("local changed = not record or self.scRecordId ~= record.id", set_card_record)
        self.assertNotIn("record.id == state.presetRecord.id", sources)
        for forbidden in ("C_Transmog", "TRANSMOGRIFY:", "ezCollections:SendAddonMessage"):
            self.assertNotIn(forbidden, sources)
        self.assertIn('"slot:SHIRT"', wardrobe_catalog)
        self.assertIn('"slot:TABARD"', wardrobe_catalog)
        for token in (
            "local function finishApply(callback, ok, reason)",
            "ok == true and (reason == nil or tostring(reason) == \"ACCEPTED\")",
            "local function positiveInteger(value)",
            "finishApply(callback, ok, reason)",
        ):
            self.assertIn(token, provider)
        set_apply_tooltip = sources[
            sources.index("local function showApplySetTooltip"):
            sources.index("applySet:SetScript(\"OnLeave\"", sources.index("applySet:SetScript(\"OnEnter\""))
        ]
        self.assertLess(
            set_apply_tooltip.index("elseif canApply then"),
            set_apply_tooltip.index("elseif reason == \"NOT_OWNED\" then"),
        )
        self.assertNotIn("not record.collected", set_apply_tooltip)
        self.assertLess(
            sources.index("if state.presetRecord and state.RefreshPresetRecord then"),
            sources.index("for index, card in ipairs(self.setCards) do"),
        )
        self.assertLess(
            sources.index("if state.presetRecord and state.RefreshPresetRecord then"),
            sources.index("selectedSetName:SetText(tostring(state.presetRecord.name"),
        )
        self.assertNotIn("state.presetRecord = record", sources)
        self.assertLess(
            sources.index("local function copySetFilters()"),
            sources.index("local records, page, totalPages = SC.Catalog.Query(\"SETS\", query, filters"),
        )

    def test_empty_item_cards_clear_selection_and_hide(self):
        sources = read_text(LAB / "Sources.lua")
        empty_branch = sources[sources.index("if not record then") : sources.index("self:Show()", sources.index("if not record then"))]
        self.assertIn("selected:Hide()", empty_branch)
        self.assertIn("favorite:Hide()", empty_branch)
        self.assertIn("self:Hide()", empty_branch)

        clear_renderer = sources[sources.index("function card:ClearRenderer()") : sources.index("function card:SetSelected", sources.index("function card:ClearRenderer()"))]
        self.assertIn("itemRenderer:Clear(model, self.scGeneration)", clear_renderer)
        self.assertIn("selected:Hide()", clear_renderer)
        self.assertIn("favorite:Hide()", clear_renderer)
        self.assertIn("self:Hide()", clear_renderer)

        set_clear_renderer = sources[sources.index("function card:ClearRenderer(reason)") : sources.index("hit:SetScript(\"OnClick\"", sources.index("function card:ClearRenderer(reason)"))]
        self.assertIn("presenter:Clear(reason or \"LAB_SET_CLEARED\")", set_clear_renderer)
        self.assertIn("selected:Hide()", set_clear_renderer)
        self.assertIn("favorite:Hide()", set_clear_renderer)
        self.assertIn("self:Hide()", set_clear_renderer)
        self.assertIn("card:ClearRenderer(\"LAB_SET_VIEW_HIDDEN\")", sources)

    def test_layout_exposes_apply_controls_without_custom_save_protocol(self):
        layout = read_text(LAB / "Layout.lua")
        controller = read_text(LAB / "Controller.lua")
        outfits = read_text(LAB / "Outfits.lua")
        for token in (
            "left:SetWidth(300)",
            "left:SetHeight(495)",
            "left:SetPoint(\"TOPLEFT\", page, \"TOPLEFT\", 4, -86)",
            "right:SetWidth(662)",
            "right:SetHeight(606)",
            "right:SetPoint(\"TOPRIGHT\", page, \"TOPRIGHT\", 0, 0)",
            "local stateText = page:CreateFontString(nil, \"OVERLAY\", \"GameFontHighlightSmall\")",
            "stateText:SetPoint(\"BOTTOMLEFT\", page, \"BOTTOMLEFT\", 0, 0)",
            "stateText:Hide()",
            "MoneyFrame.tga",
            "moneyLeft:SetPoint(\"BOTTOMLEFT\", left, \"BOTTOMLEFT\", -3, -22)",
            "apply:SetPoint(\"BOTTOMRIGHT\", left, \"BOTTOMRIGHT\", 0, -22)",
            "spec:SetPoint(\"RIGHT\", apply, \"LEFT\", 1, 0)",
            "SquareButtonTextures.tga",
            "local function createDisabledTooltipOverlay(button, onEnter)",
            "overlay:SetScript(\"OnEnter\", onEnter)",
            "local applyDisabledTip = createDisabledTooltipOverlay(apply, showApplyTooltip)",
            "state:BeginApplySet()",
            "state:BeginApplyDraft()",
            "page.scApplyButton = apply",
            "page.scApplyDisabledTip = applyDisabledTip",
            "page.scMoneyFrameTextures = { moneyLeft, moneyMiddle, moneyRight }",
            "page.scSpecButton = spec",
            "page.scMultiSaveButton = outfits.scSaveButton",
            "已有应用请求正在处理。",
        ):
            self.assertIn(token, layout)
        for token in (
            "self.scApplyButton:SetText(\"应用\")",
            "state:GetDraftApplyState()",
            "state:GetSetApplyState(true)",
            "self.scApplyDisabledTip:Hide()",
            "self.scApplyDisabledTip:Show()",
        ):
            self.assertIn(token, controller)
        for token in (
            "save:SetText(\"保存整套\")",
            "save:Disable()",
            "save:Hide()",
            "local saveTip = CreateFrame(\"Frame\", nil, save)",
            "saveTip:SetAllPoints(save)",
            "saveTip:SetFrameLevel(save:GetFrameLevel() + 1)",
            "saveTip:EnableMouse(true)",
            "saveTip:SetScript(\"OnEnter\"",
            "saveTip:Hide()",
            "保存整套（待原子协议）",
            "自定义整套保存尚未接入服务端原子协议",
            "host.scSaveButton = save",
            "host.scSaveTooltip = saveTip",
        ):
            self.assertIn(token, outfits)
        self.assertNotIn("page.scMultiSaveButton = applyAll", layout)
        self.assertNotIn("page.scApplySlot = apply", layout)
        self.assertNotIn("page.scApplyAll = applyAll", layout)
        self.assertNotIn("ObserveAuthoritativeState", controller)
        self.assertNotIn("WAITING_STATE", controller)
        for forbidden in (
            "C_TransmogCollection.SaveOutfit",
            "C_TransmogCollection.CreateOutfit",
            "WardrobeOutfitFrame",
            "TRANSMOGRIFY:",
            "C_Transmog",
        ):
            self.assertNotIn(forbidden, layout)
            self.assertNotIn(forbidden, outfits)
        save_outfit_region = outfits[
            outfits.index("local save = CreateFrame"):
            outfits.index("local function chooseEquipped")
        ]
        for forbidden in (
            "BeginApply",
            "ApplySet",
            "ApplyAppearance",
            "SaveOutfit",
            "CreateOutfit",
            "SendAddonMessage",
        ):
            self.assertNotIn(forbidden, save_outfit_region)
        apply_all_tooltip = layout[
            layout.index("local function showApplyTooltip"):
            layout.index("apply:SetScript(\"OnLeave\"", layout.index("apply:SetScript(\"OnEnter\""))
        ]
        self.assertLess(
            apply_all_tooltip.index("if canApply then"),
            apply_all_tooltip.index("elseif reason == \"NOT_OWNED\" then"),
        )
        self.assertIn("当前版本尚未收集完整", apply_all_tooltip)

    def test_lab_does_not_import_ez_outfit_persistence_protocol(self):
        combined = "\n".join(read_text(path) for path in sorted(LAB.glob("*.lua"), key=str))
        for forbidden in (
            "C_TransmogCollection.SaveOutfit",
            "C_TransmogCollection.ModifyOutfit",
            "C_TransmogCollection.DeleteOutfit",
            "WardrobeOutfitFrame",
            "TransmogUtil.CreateOutfitSlashCommand",
            "TransmogUtil.ParseOutfitSlashCommand",
        ):
            self.assertNotIn(forbidden, combined)

    def test_legacy_wardrobe_apply_messages_require_accepted_status(self):
        wardrobe = read_text(ADDON / "UI" / "Wardrobe.lua")
        for token in (
            "local function applyActionAccepted(ok, reason)",
            "return ok == true and (reason == nil or tostring(reason) == \"ACCEPTED\")",
            "local function setBridgeReadyForApply()",
            "SC.Bridge.GetCategoryState(14) == \"Ready\"",
            "if not setBridgeReadyForApply() or record.ownershipKnown == false then",
            "ok = applyActionAccepted(ok, reason)",
            "服务端未执行应用。",
        ):
            self.assertIn(token, wardrobe)
        self.assertLess(
            wardrobe.index("ok = applyActionAccepted(ok, reason)"),
            wardrobe.index("message = \"外观已应用。\""),
        )
        self.assertLess(
            wardrobe.rindex("ok = applyActionAccepted(ok, reason)"),
            wardrobe.index("message = \"套装外观已原子应用。\""),
        )

    def test_pending_apply_blocks_local_mutation_controls(self):
        state = read_text(LAB / "State.lua")
        self.assertIn("self:Notify(\"REQUEST_PENDING_BLOCKED\")", state)
        self.assertGreaterEqual(
            state.count("if self:RejectMutationWhilePending() then return false, \"REQUEST_PENDING\" end"),
            3,
        )

        outfits = read_text(LAB / "Outfits.lua")
        for token in (
            "state:IsRequestPending()",
            "state:Notify(\"REQUEST_PENDING_BLOCKED\")",
            "已有应用请求正在处理，暂不能清除。",
        ):
            self.assertIn(token, outfits)

        sources = read_text(LAB / "Sources.lua")
        for token in (
            "应用请求处理中，暂不能改动本地草稿。",
            "应用请求处理中，暂不能切换套装预设。",
            "再次点击同一套装确认切换预设。",
        ):
            self.assertIn(token, sources)

        slots = read_text(LAB / "Slots.lua")
        templates = read_text(ADDON / "UI" / "EzCollections" / "Templates.lua")
        self.assertIn("应用请求处理中 · 暂不能撤销", slots)
        for token in (
            "local itemId, pending, source = state:GetSlotPreviewItemId(self.scSlotKey)",
            "服务端已确认的已应用外观",
            "当前装备槽位",
            "if state:IsRequestPending() then",
            "state:Notify(\"REQUEST_PENDING_BLOCKED\")",
            "state:ClearDraft(self.scSlotKey)",
            "套装预设 · 右键移除此槽位并转为本地草稿",
            "SHIRT = { \"TOP\", -121, -253 }",
            "TABARD = { \"TOP\", -121, -306 }",
            "WRIST = { \"TOP\", -121, -359 }",
            "MAINHAND = { \"BOTTOM\", -26, 45 }",
            "OFFHAND = { \"BOTTOM\", 27, 45 }",
            "RANGED = { \"BOTTOM\", 90, 45, false, \"远程\" }",
            "MAINHAND_ENCHANT = { \"CENTER\", -26, -203, true, \"主手附魔\" }",
            "OFFHAND_ENCHANT = { \"CENTER\", 27, -203, true, \"副手附魔\" }",
            "local function createUnsupportedSlot(host, key, point)",
            "host.unsupportedButtons[key] = createUnsupportedSlot(host, key, point)",
            "BACK = \"Interface\\\\PaperDoll\\\\UI-PaperDoll-Slot-Back\"",
            "SHIRT = \"Interface\\\\PaperDoll\\\\UI-PaperDoll-Slot-Shirt\"",
            "TABARD = \"Interface\\\\PaperDoll\\\\UI-PaperDoll-Slot-Tabard\"",
            "local itemId, pending, source = state:GetSlotPreviewItemId(slotKey)",
            "button:SetSlotPending(pending)",
            "button:SetSlotApplied(source == \"APPLIED\")",
        ):
            self.assertIn(token, slots)
        for token in (
            "local appliedStatus = parent:CreateTexture(nil, \"OVERLAY\")",
            "appliedStatus:SetVertexColor(0.35, 1.00, 0.35, 0.92)",
            "function parent:SetSlotApplied(value)",
            "parent.scAppliedStatusBorder = appliedStatus",
        ):
            self.assertIn(token, templates)
        self.assertLess(
            templates.index("appliedStatus:Hide()"),
            templates.index("status:Show()"),
        )
        self.assertNotIn("if state.presetRecord then state:ClearDraft() else state:ClearDraft(self.scSlotKey) end", slots)
        self.assertNotIn("套装预设 · 右键撤销整个预设", slots)

    def test_controller_updates_status_buttons_and_lab_mode(self):
        controller = read_text(LAB / "Controller.lua")
        for token in (
            "showActionNotice",
            "showBlockedNotice",
            "addChatNotice(message, ok)",
            "DEFAULT_CHAT_FRAME:AddMessage",
            "SHORT_REASON_TEXT",
            "shortReasonLabel(request.reason)",
            "DISMISSED = \"服务端未执行应用。\"",
            "CONFIRM_SET_PRESET = \"切换套装预设会清除当前草稿 · 再点同一套装确认\"",
            "request.status == \"CONFIRM_SET_PRESET\"",
            "local function isLabCollectionType(typeId)",
            "typeId == 13 or typeId == 14",
            "REQUEST_RESULT",
            "REQUEST_PENDING_BLOCKED",
            "SC.Bridge.RegisterStateListener",
            "state:GetDraftApplyState()",
            "state:GetSetApplyState(true)",
            "self.scApplyButton:SetText(\"应用\")",
            "self.scApplyDisabledTip:Hide()",
            "self.scApplyDisabledTip:Show()",
            "state:RefreshPresetRecord()",
            "owner.scSources.itemPage = 1",
            "owner.scSources:SetMode(\"ITEMS\")",
            "page:RegisterEvent(\"GET_ITEM_INFO_RECEIVED\")",
            "page:RegisterEvent(\"UNIT_MODEL_CHANGED\")",
            "self.scSources:ContainsVisibleItem(itemId)",
            "function page:SyncFilters()",
        ):
            self.assertIn(token, controller)
        self.assertLess(
            controller.index("state:RefreshPresetRecord()"),
            controller.index("self.scStateText:SetText(statusTextFor(state, request))"),
        )

    def test_lab_visual_fit_adjustments_keep_status_and_waist_cards_readable(self):
        model = read_text(ADDON / "UI" / "EzWardrobe" / "Model.lua")
        sources = read_text(LAB / "Sources.lua")
        layout = read_text(LAB / "Layout.lua")
        frame = read_text(ADDON / "UI" / "CollectionsFrame.lua")
        for token in (
            "local ITEM_COLUMNS = 6",
            "local ITEM_PAGE_SIZE = 18",
            "local ITEM_WIDTH = 78",
            "local ITEM_HEIGHT = 104",
            "local ITEM_FIRST_CENTER_X = -238",
            "local ITEM_FIRST_TOP_Y = -85",
            "ITEM_FIRST_CENTER_X + column * (ITEM_WIDTH + ITEM_GAP_X)",
            "ITEM_FIRST_TOP_Y - row * (ITEM_HEIGHT + ITEM_GAP_Y)",
        ):
            self.assertIn(token, sources)
        for token in (
            "local ARMOR_SLOT_MODEL_SCALE = {",
            "WAIST = 0.86",
            "safeCall(self.frame, \"SetModelScale\", ARMOR_SLOT_MODEL_SCALE[record.slot] or TYPE_SCALE[TYPE_PLAYER])",
        ):
            self.assertIn(token, model)
        self.assertIn("stateText:SetPoint(\"BOTTOMLEFT\", page, \"BOTTOMLEFT\", 0, 0)", layout)
        self.assertIn("stateText:Hide()", layout)
        self.assertIn("frame.scProgress:Show()", frame)


if __name__ == "__main__":
    unittest.main()
