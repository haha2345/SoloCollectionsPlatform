local SC = SoloCollections

SC.WardrobeLab = SC.WardrobeLab or {}
local Lab = SC.WardrobeLab

Lab.SLOTS = {
    { key = "HEAD", label = "头部", inventorySlot = 0 },
    { key = "SHOULDER", label = "肩部", inventorySlot = 2 },
    { key = "BACK", label = "背部", inventorySlot = 14 },
    { key = "CHEST", label = "胸部", inventorySlot = 4 },
    { key = "SHIRT", label = "衬衣", inventorySlot = 3 },
    { key = "TABARD", label = "战袍", inventorySlot = 18 },
    { key = "WRIST", label = "手腕", inventorySlot = 8 },
    { key = "HANDS", label = "手部", inventorySlot = 9 },
    { key = "WAIST", label = "腰部", inventorySlot = 5 },
    { key = "LEGS", label = "腿部", inventorySlot = 6 },
    { key = "FEET", label = "脚部", inventorySlot = 7 },
    { key = "MAINHAND", label = "主手", inventorySlot = 15 },
    { key = "OFFHAND", label = "副手", inventorySlot = 16 },
    { key = "RANGED", label = "远程", inventorySlot = 17 },
}

Lab.SLOT_BY_KEY = {}
for _, definition in ipairs(Lab.SLOTS) do Lab.SLOT_BY_KEY[definition.key] = definition end

-- Legion TRANSMOGRIFY_INVALID_NO_ITEM. 3.3.5 GetInventoryItemLink is often
-- nil until the item is cached; a real item still has count > 0 or an icon
-- that is not the paperdoll empty-slot art. Item id 0 / "" is empty.
Lab.EMPTY_SLOT_TEXT = "该装备栏里没有装备物品。"

function Lab.PositiveItemId(value)
    value = tonumber(value)
    if value and value > 0 then return value end
    return nil
end

function Lab.InventoryItemLink(inventorySlotId)
    if not GetInventoryItemLink then return nil end
    local link = GetInventoryItemLink("player", inventorySlotId)
    if type(link) ~= "string" or link == "" then return nil end
    if not string.find(link, "item:") then return nil end
    return link
end

local function normalizeTexture(path)
    if type(path) ~= "string" or path == "" then return nil end
    path = string.lower(path)
    path = string.gsub(path, "\\", "/")
    path = string.gsub(path, "%.blp$", "")
    path = string.gsub(path, "%.tga$", "")
    return path
end

local function isPaperdollEmptyTexture(texture)
    local normalized = normalizeTexture(texture)
    if not normalized then return true end
    return string.find(normalized, "paperdoll/ui%-paperdoll%-slot", 1, false) ~= nil
end

function Lab.IsInventoryOccupied(inventorySlotId, knownItemId)
    inventorySlotId = tonumber(inventorySlotId)
    if not inventorySlotId then return false end
    if Lab.PositiveItemId(knownItemId) then return true end
    if GetInventoryItemID and Lab.PositiveItemId(GetInventoryItemID("player", inventorySlotId)) then
        return true
    end
    local link = Lab.InventoryItemLink(inventorySlotId)
    if link and Lab.PositiveItemId(string.match(link, "item:(%d+)")) then
        return true
    end
    if GetInventoryItemTexture then
        local texture = GetInventoryItemTexture("player", inventorySlotId)
        if texture and not isPaperdollEmptyTexture(texture) then
            return true
        end
        if isPaperdollEmptyTexture(texture) then
            return false
        end
    end
    if GetInventoryItemCount and (GetInventoryItemCount("player", inventorySlotId) or 0) > 0 then
        return true
    end
    return false
end

function Lab.NotifyEmptySlot()
    local text = Lab.EMPTY_SLOT_TEXT
    if UIErrorsFrame and UIErrorsFrame.AddMessage then
        UIErrorsFrame:AddMessage(text, 1, 0.12, 0.12, 1)
    end
end

-- Legion apply-block copy. Slot tooltip uses the same strings.
Lab.APPLY_REASON_TEXT = {
    NO_DRAFT = "先在右侧选择外观，建立待定幻化。",
    NOT_OWNED = "你尚未收集此外观。",
    INVALID_TARGET_SLOT = Lab.EMPTY_SLOT_TEXT,
    NOTHING_EQUIPPED = Lab.EMPTY_SLOT_TEXT,
    HIDE_VISUAL_UNSUPPORTED = "隐藏外观只能本地预览，当前不能应用到装备。",
    CLASS_RESTRICTED = "当前装备与此外观不兼容。",
    RACE_RESTRICTED = "当前种族不能使用此外观。",
    SKILL_REQUIRED = "当前角色缺少使用此外观所需的技能。",
    WEAPON_TYPE = "武器类型不兼容。",
    ARMOR_TYPE = "护甲类型不兼容。",
    UNKNOWN_IDENTITY = "未知外观，服务端已拒绝。",
    COST_CHANGED = "费用已变化，请重新确认后再应用。",
    INSUFFICIENT_FUNDS = "金币不足。",
    UNSUPPORTED = "当前服务器不支持这项幻化。",
    INVALID_REQUEST = "请求无效。",
    REQUEST_NOT_SENT = "请求未能发出。",
    REQUEST_PENDING = "已有应用请求正在处理。",
    BRIDGE_UNAVAILABLE = "SC2 外观服务尚未就绪，暂不能提交应用。",
    NO_PRESET = "先选择一套套装预设。",
}

function Lab.ApplyReasonText(reason, extra)
    extra = extra or {}
    local text
    if reason == "NOT_OWNED" and extra.set then
        text = string.format(
            "当前套装尚未收集完整：%s / %s。未收藏套装只能预览。",
            tostring(extra.owned or 0),
            tostring(extra.required or 0)
        )
    elseif reason and Lab.APPLY_REASON_TEXT[reason] then
        text = Lab.APPLY_REASON_TEXT[reason]
    else
        text = extra.fallback or "当前待定外观暂不能提交应用。"
    end
    if extra.slotLabel and extra.slotLabel ~= "" then
        return extra.slotLabel .. "：" .. text
    end
    return text
end

function Lab.NotifyApplyBlocked(reason, extra)
    return Lab.Notice(Lab.ApplyReasonText(reason, extra))
end

function Lab.IsCollectedRecord(record)
    if type(record) ~= "table" then return false end
    return record.collected == true or record.collected == 1
end

Lab.MAX_OUTFITS = 10
Lab.OUTFIT_NAME_MAX = 48

-- ez 2.2 plays extracted WAVs when SoloCollections_EzUI is present; otherwise
-- fall back to 3.3.5 stock kits. Legion plays SOUNDKIT.UI_TRANSMOG_* which
-- 3.3.5 does not have. Apply must not play on the button click.
Lab.SOUNDS = {
    open = { file = "UI_EtherealWindow_Open.wav", fallback = "igCharacterInfoOpen", alwaysFallback = true },
    close = { file = "UI_EtherealWindow_Close.wav", fallback = "igCharacterInfoClose", alwaysFallback = true },
    apply = { file = "UI_Transmogrify_Apply.wav" },
    revert = { file = "UI_Reforging_Restore.wav" },
    slot = { fallback = "igSpellBookSpellIconPickup" },
    item = { fallback = "igMainMenuOptionCheckBoxOn" },
}

function Lab.PlaySound(key)
    local spec = Lab.SOUNDS[key]
    if not spec then return end
    local UI = SC.UI
    local playedFile = false
    if spec.file and UI and UI.EzCollections and UI.EzCollections.MediaPath then
        local path = UI.EzCollections:MediaPath("Sounds", spec.file)
        if path and PlaySoundFile then
            -- 3.3.5 cannot tell if the optional EzUI file exists. A stub
            -- overlay still returns a path, so open/close always keep the
            -- stock kit. Apply/revert stay silent when the WAV is missing.
            pcall(PlaySoundFile, path)
            playedFile = true
        end
    end
    if spec.fallback and PlaySound and (spec.alwaysFallback or not playedFile) then
        pcall(PlaySound, spec.fallback)
    end
end

local POPUP_WHICH = {
    confirm = "SOLOCOLLECTIONS_TRANSMOG_CONFIRM",
    notice = "SOLOCOLLECTIONS_TRANSMOG_NOTICE",
}

function Lab.HideDialogs()
    Lab.pendingPopupAccept = nil
    Lab.pendingApplyState = nil
    Lab.pendingOutfitState = nil
    if not StaticPopup_Hide then return end
    StaticPopup_Hide("SOLOCOLLECTIONS_TRANSMOG_CONFIRM")
    StaticPopup_Hide("SOLOCOLLECTIONS_TRANSMOG_NOTICE")
    StaticPopup_Hide("SOLOCOLLECTIONS_TRANSMOG_APPLY")
    StaticPopup_Hide("SOLOCOLLECTIONS_TRANSMOG_APPLY_WARNING")
    StaticPopup_Hide("SOLOCOLLECTIONS_SAVE_TRANSMOG_OUTFIT")
end

function Lab.ShowDialog(kind, text, onAccept)
    text = tostring(text or "")
    Lab.pendingPopupAccept = onAccept
    local which = POPUP_WHICH[kind] or POPUP_WHICH.notice
    local dialog
    if StaticPopup_Show then
        dialog = StaticPopup_Show(which, text)
    end
    if dialog then return dialog end
    -- 3.3.5 can refuse a custom popup; never leave a confirm silent.
    if DEFAULT_CHAT_FRAME and DEFAULT_CHAT_FRAME.AddMessage then
        DEFAULT_CHAT_FRAME:AddMessage("|cffffd100幻化：|r" .. text)
    end
    if UIErrorsFrame and UIErrorsFrame.AddMessage then
        UIErrorsFrame:AddMessage(text, 1, 0.82, 0.18, 1, 6)
    end
    return nil
end

function Lab.Confirm(text, onAccept)
    return Lab.ShowDialog("confirm", text, onAccept)
end

function Lab.ConfirmRestoreOriginal(state, slotKey)
    if not state or not slotKey then return false end
    if not (state.GetAppliedCollectionId and state:GetAppliedCollectionId(slotKey)) then
        return false
    end
    local definition = Lab.SLOT_BY_KEY and Lab.SLOT_BY_KEY[slotKey]
    local slotName = (definition and definition.label) or "该部位"
    return Lab.Confirm("恢复" .. slotName .. "的原装备外观？已经应用到这件装备上的幻化会被清除。", function()
        if state.IsSlotDirty and state:IsSlotDirty(slotKey) then
            state:ClearDraft(slotKey)
        end
        if state.ClearApplied then
            state:ClearApplied(slotKey)
        end
        if Lab.PlaySound then Lab.PlaySound("revert") end
    end)
end

function Lab.Notice(text, onAccept)
    return Lab.ShowDialog("notice", text, onAccept)
end

local State = {}
State.__index = State

local function currentRevision()
    return SC.CollectionState and SC.CollectionState.GetRevision and SC.CollectionState.GetRevision() or "0"
end

local function recordItemId(record)
    if type(record) ~= "table" then return nil end
    return tonumber(record.itemId or (record.itemIds and record.itemIds[1]))
end

local function getSelectedVariant(record)
    if type(record) ~= "table" then return nil end
    if type(record.selectedVariant) == "table" then return record.selectedVariant end
    local requested = tonumber(record.selectedVariantOrdinal)
    local fallback
    for _, variant in ipairs(record.variants or {}) do
        if not fallback or variant.isDefault then fallback = variant end
        if requested and tonumber(variant.variantOrdinal) == requested then return variant end
    end
    return fallback
end

local function getMemberItemId(member)
    if type(member) ~= "table" then return nil end
    local itemId = tonumber(member.previewSourceItemId)
    for _, sourceItemId in ipairs(member.sourceItemIds or {}) do
        sourceItemId = tonumber(sourceItemId)
        if sourceItemId and (not itemId or sourceItemId < itemId) then itemId = sourceItemId end
    end
    return itemId
end

local function memberCollectionId(member)
    if type(member) ~= "table" then return nil end
    for _, appearanceId in ipairs(member.appearanceIds or {}) do
        appearanceId = tonumber(appearanceId)
        if appearanceId and SC.CollectionState and SC.CollectionState.IsOwnedByType
            and SC.CollectionState.IsOwnedByType(13, appearanceId) then
            return appearanceId
        end
    end
    return tonumber(member.collectionId) or tonumber(member.appearanceIds and member.appearanceIds[1])
end

local function characterKey()
    return tostring(UnitName("player") or "") .. "-" .. tostring(GetRealmName and GetRealmName() or "")
end

local function appearanceMatchesItem(record, itemId)
    if not record or not itemId then return false end
    if tonumber(record.itemId) == itemId then return true end
    for _, sourceItemId in ipairs(record.itemIds or {}) do
        if tonumber(sourceItemId) == itemId then return true end
    end
    return false
end

local appearanceById
local appearanceByItemId
local appearanceIndexRevision

local function rebuildAppearanceIndex()
    appearanceById, appearanceByItemId = {}, {}
    appearanceIndexRevision = currentRevision()
    if not SC.Catalog or type(SC.Catalog.Get) ~= "function" then return end
    for _, record in ipairs(SC.Catalog.Get("APPEARANCES") or {}) do
        local id = tonumber(record.id)
        if id then appearanceById[id] = record end
        local function indexItem(itemId)
            itemId = tonumber(itemId)
            if itemId and not appearanceByItemId[itemId] then
                appearanceByItemId[itemId] = record
            end
        end
        indexItem(record.itemId)
        for _, sourceItemId in ipairs(record.itemIds or {}) do
            indexItem(sourceItemId)
        end
    end
end

function Lab.IsHideVisualRecord(record)
    return type(record) == "table" and record.isHideVisual == true
end

function Lab.CreateHideVisualRecord(slotKey)
    return {
        id = 2,
        isHideVisual = true,
        collected = true,
        favorite = false,
        name = "隐藏外观",
        slot = slotKey,
        itemId = nil,
        itemIds = {},
    }
end

function Lab.IsAppliedReady()
    return SC.CollectionState and SC.CollectionState.IsAppliedReady and SC.CollectionState.IsAppliedReady()
end

function Lab.IsOutfitReady()
    return SC.CollectionState and SC.CollectionState.IsOutfitReady and SC.CollectionState.IsOutfitReady()
end

-- 3.3.5 SmallMoneyFrame STATIC collapses a true 0-copper quote. Only force the
-- copper button for that case. Forcing it on a 1g+ quote would hide gold and
-- show `copper % 100` as 0.
function Lab.UpdateQuotedMoney(frameOrName, copper, colorKey)
    copper = tonumber(copper) or 0
    if copper < 0 then copper = 0 end
    copper = math.floor(copper)
    local name
    if type(frameOrName) == "string" then
        name = frameOrName
    elseif type(frameOrName) == "table" and frameOrName.GetName then
        name = frameOrName:GetName()
    end
    if not name then return end
    if MoneyFrame_Update then
        pcall(MoneyFrame_Update, name, copper)
    end
    if SetMoneyFrameColor then
        pcall(SetMoneyFrameColor, name, colorKey or "white")
    end
    if copper > 0 then return end
    local copperButton = _G and _G[name .. "CopperButton"]
    if not copperButton and getglobal then
        copperButton = getglobal(name .. "CopperButton")
    end
    if copperButton then
        if copperButton.SetText then copperButton:SetText(0) end
        copperButton:Show()
    end
end

function Lab.ItemQualityColor(itemId)
    itemId = tonumber(itemId)
    if itemId and GetItemInfo then
        local name, _, quality = GetItemInfo(itemId)
        if GetItemQualityColor and quality then
            local red, green, blue = GetItemQualityColor(quality)
            return red, green, blue, name
        end
        return 1, 1, 1, name
    end
    return 1, 1, 1, nil
end

function Lab.AppearanceDisplayName(collectionId, itemId)
    collectionId = tonumber(collectionId)
    if collectionId == 2 then
        return "隐藏", true
    end
    local record = Lab.FindAppearanceRecord(collectionId, itemId)
    if record then
        return record.name or ("外观 " .. tostring(collectionId)), false
    end
    if itemId and GetItemInfo then
        local name = GetItemInfo(itemId)
        if name then return name, false end
    end
    if collectionId then
        return "外观 " .. tostring(collectionId), false
    end
    return nil, false
end

-- Legion / ez: header and appearance share TRANSMOGRIFY_FONT_COLOR (1, 0.5, 1).
-- Pending replaces the applied line. Hidden uses ez L["Tooltip.Transmog.Entry.Hidden"].
function Lab.AppendTransmogLines(tooltip, appearanceName, pending, hidden)
    if not tooltip or type(tooltip.AddLine) ~= "function" then return end
    local pinkR, pinkG, pinkB = 1, 0.5, 1
    if hidden then
        appearanceName = "隐藏"
    end
    if not appearanceName then return end
    if pending then
        tooltip:AddLine("你将要幻化为:", pinkR, pinkG, pinkB)
    else
        tooltip:AddLine("幻化为:", pinkR, pinkG, pinkB)
    end
    tooltip:AddLine(appearanceName, pinkR, pinkG, pinkB)
end

function Lab.GetEquippedAppearanceRecord(slotKey, equippedId)
    equippedId = tonumber(equippedId)
    if not equippedId then return nil end
    local record = Lab.FindAppearanceRecord(nil, equippedId)
    if record then
        local copy = {}
        for key, value in pairs(record) do
            copy[key] = value
        end
        copy.collected = true
        copy.isEquippedBase = true
        return copy
    end
    local name
    if GetItemInfo then
        name = GetItemInfo(equippedId)
    end
    return {
        id = "EQUIPPED:" .. tostring(equippedId),
        itemId = equippedId,
        itemIds = { equippedId },
        name = name or ("当前装备 " .. tostring(equippedId)),
        collected = true,
        favorite = false,
        slot = slotKey,
        isEquippedBase = true,
    }
end

function Lab.FindAppearanceRecord(collectionId, itemId)
    local revision = currentRevision()
    if not appearanceById or appearanceIndexRevision ~= revision then
        rebuildAppearanceIndex()
    end
    collectionId = tonumber(collectionId)
    itemId = tonumber(itemId)
    if collectionId and appearanceById[collectionId] then return appearanceById[collectionId] end
    if itemId then return appearanceByItemId[itemId] end
    return nil
end

function Lab.GetStoredOutfits()
    if Lab.IsOutfitReady() then
        return SC.CollectionState.GetAccountOutfits() or {}
    end
    return {}
end

function Lab.GetLocalOutfits()
    local outfits = {}
    local key = characterKey()
    for _, outfit in ipairs((SC.db and SC.db.transmogOutfits) or {}) do
        if type(outfit) == "table" and outfit.character == key and type(outfit.name) == "string"
            and type(outfit.slots) == "table" then
            outfits[#outfits + 1] = outfit
        end
    end
    return outfits
end

function Lab.CreateState()
    local state = setmetatable({
        equippedBySlot = {}, draftBySlot = {}, selectedSlot = "HEAD", dirtySlots = {},
        appliedOverlay = {}, trustedEquippedBySlot = {}, ignoredAppliedSlots = {},
        requestState = { status = "IDLE", revision = currentRevision() },
        listeners = {}, generation = 0, preservedOnClose = false,
        presetRecord = nil, requestSerial = 0, applyQueue = {},
        activeOutfitUid = nil,
        quotedCopper = nil, quoteStatus = "UNAVAILABLE", quoteWarningMask = 0,
        quoteToken = 0,
    }, State)
    state:CaptureEquipped()
    state:EnsureSelectedSlotCanTransmog()
    return state
end

function State:SyncEquippedTrust()
    self.trustedEquippedBySlot = self.trustedEquippedBySlot or {}
    self.ignoredAppliedSlots = self.ignoredAppliedSlots or {}
    for _, definition in ipairs(Lab.SLOTS) do
        local key = definition.key
        local current = self.equippedBySlot[key]
        if self.trustedEquippedBySlot[key] == nil then
            self.trustedEquippedBySlot[key] = current
        elseif self.trustedEquippedBySlot[key] ~= current then
            self.ignoredAppliedSlots[key] = true
        end
    end
end

function State:CaptureEquipped()
    self.equippedBySlot = {}
    for _, definition in ipairs(Lab.SLOTS) do
        local invSlot = definition.inventorySlot + 1
        local itemId = Lab.PositiveItemId(GetInventoryItemID and GetInventoryItemID("player", invSlot))
        if not itemId then
            local link = Lab.InventoryItemLink(invSlot)
            itemId = link and Lab.PositiveItemId(string.match(link, "item:(%d+)"))
        end
        self.equippedBySlot[definition.key] = itemId
    end
    self:SyncEquippedTrust()
    self:DropEmptySlotDrafts()
end

function State:IsSlotOccupied(slotKey)
    local definition = Lab.SLOT_BY_KEY[slotKey]
    if not definition then return false end
    local equippedId = self.equippedBySlot and self.equippedBySlot[slotKey]
    return Lab.IsInventoryOccupied(definition.inventorySlot + 1, equippedId)
end

function State:CanTransmogSlot(slotKey)
    return self:IsSlotOccupied(slotKey)
end

function State:EnsureSelectedSlotCanTransmog()
    if self:IsSlotOccupied(self.selectedSlot) then return false end
    for _, definition in ipairs(Lab.SLOTS) do
        if self:IsSlotOccupied(definition.key) then
            self.selectedSlot = definition.key
            return true
        end
    end
    return false
end

function State:DropEmptySlotDrafts()
    local changed = false
    for slotKey, _ in pairs(self.dirtySlots) do
        if not self:IsSlotOccupied(slotKey) then
            self.draftBySlot[slotKey] = nil
            self.dirtySlots[slotKey] = nil
            changed = true
        end
    end
    if changed then self:ScheduleQuote() end
    return changed
end

function State:HasEmptySlotDrafts()
    for slotKey, record in pairs(self.draftBySlot) do
        if self.dirtySlots[slotKey] and record and not self:IsSlotOccupied(slotKey) then
            return true
        end
    end
    return false
end

function State:Subscribe(owner, callback)
    if owner and type(callback) == "function" then self.listeners[owner] = callback end
end

function State:Notify(reason)
    self.generation = self.generation + 1
    for owner, callback in pairs(self.listeners) do pcall(callback, owner, self, reason) end
end

function State:SelectSlot(slotKey)
    if not Lab.SLOT_BY_KEY[slotKey] then return false end
    if not self:IsSlotOccupied(slotKey) then return false end
    self.selectedSlot = slotKey
    self:Notify("SELECT_SLOT")
    return true
end

function State:SetDraft(slotKey, record)
    if not Lab.SLOT_BY_KEY[slotKey] or type(record) ~= "table" then return false end
    if not self:IsSlotOccupied(slotKey) then return false, "INVALID_TARGET_SLOT" end
    self.presetRecord = nil
    self.activeOutfitUid = nil
    self.draftBySlot[slotKey] = record
    self.dirtySlots[slotKey] = true
    self.preservedOnClose = false
    self.requestState = { status = "LOCAL_DRAFT", slot = slotKey, revision = currentRevision() }
    self:ScheduleQuote()
    self:Notify("SET_DRAFT")
    return true
end

function State:SetPreset(record)
    if type(record) ~= "table" then return false end
    self.draftBySlot, self.dirtySlots = {}, {}
    self.presetRecord = record
    self.activeOutfitUid = nil
    self.preservedOnClose = false
    self.requestState = { status = "LOCAL_PRESET", record = record, revision = currentRevision() }
    self:ScheduleQuote()
    self:Notify("SET_PRESET")
    return true
end

function State:ClearDraft(slotKey)
    if slotKey then
        self.draftBySlot[slotKey], self.dirtySlots[slotKey] = nil, nil
    else
        self.draftBySlot, self.dirtySlots = {}, {}
        self.presetRecord = nil
        self.activeOutfitUid = nil
    end
    self.requestState = { status = "IDLE", revision = currentRevision() }
    self:ScheduleQuote()
    self:Notify("CLEAR_DRAFT")
end

function State:GetDirtyCount()
    if self.presetRecord then
        local count, seen = 0, {}
        local variant = getSelectedVariant(self.presetRecord)
        for _, member in ipairs((variant and variant.members) or {}) do
            local slotKey = member.slotKey
            if slotKey and Lab.SLOT_BY_KEY[slotKey] and not seen[slotKey] and getMemberItemId(member) then
                seen[slotKey] = true
                count = count + 1
            end
        end
        return count
    end
    local count = 0
    for _ in pairs(self.dirtySlots) do count = count + 1 end
    return count
end

function State:HasDraft() return self.presetRecord ~= nil or next(self.dirtySlots) ~= nil end

function State:IsSlotDirty(slotKey)
    if self.dirtySlots[slotKey] then return true end
    if not self.presetRecord then return false end
    local variant = getSelectedVariant(self.presetRecord)
    for _, member in ipairs((variant and variant.members) or {}) do
        if member.slotKey == slotKey and getMemberItemId(member) then return true end
    end
    return false
end

function State:RememberAppliedSlot(slotKey, collectionId)
    self.appliedOverlay = self.appliedOverlay or {}
    self.trustedEquippedBySlot = self.trustedEquippedBySlot or {}
    self.ignoredAppliedSlots = self.ignoredAppliedSlots or {}
    collectionId = tonumber(collectionId)
    local itemId = self.equippedBySlot and self.equippedBySlot[slotKey]
    if collectionId and collectionId > 0 then
        self.appliedOverlay[slotKey] = { collectionId = collectionId, itemId = itemId }
        self.trustedEquippedBySlot[slotKey] = itemId
        self.ignoredAppliedSlots[slotKey] = nil
    else
        self.appliedOverlay[slotKey] = nil
    end
end

function State:RememberAppliedEntries(entries)
    for token in string.gmatch(tostring(entries or ""), "[^,]+") do
        local slotPlus1, collectionId = string.match(token, "^(%d+):(%d+)$")
        slotPlus1, collectionId = tonumber(slotPlus1), tonumber(collectionId)
        if slotPlus1 and collectionId then
            for _, definition in ipairs(Lab.SLOTS) do
                if definition.inventorySlot + 1 == slotPlus1 then
                    self:RememberAppliedSlot(definition.key, collectionId)
                    break
                end
            end
        end
    end
end

function State:GetAppliedCollectionId(slotKey)
    local equippedId = self.equippedBySlot and self.equippedBySlot[slotKey]
    local overlay = self.appliedOverlay and self.appliedOverlay[slotKey]
    if type(overlay) == "table" and overlay.itemId == equippedId then
        return tonumber(overlay.collectionId)
    end
    if self.ignoredAppliedSlots and self.ignoredAppliedSlots[slotKey] then
        return nil
    end
    if not Lab.IsAppliedReady() then return nil end
    local applied = SC.CollectionState and SC.CollectionState.GetAppliedSlots
        and SC.CollectionState.GetAppliedSlots()
    if type(applied) ~= "table" then return nil end
    return tonumber(applied[slotKey])
end

function State:IsAppearanceUndoTarget(slotKey, record)
    if type(record) ~= "table" or not slotKey then return false end
    if Lab.IsHideVisualRecord and Lab.IsHideVisualRecord(record) then return false end
    local appliedId = self:GetAppliedCollectionId(slotKey)
    if not appliedId or tonumber(record.id) == appliedId then return false end
    local equippedId = self.equippedBySlot and tonumber(self.equippedBySlot[slotKey])
    if not equippedId then return false end
    if tonumber(record.itemId) == equippedId then return true end
    for _, sourceItemId in ipairs(record.itemIds or {}) do
        if tonumber(sourceItemId) == equippedId then return true end
    end
    return false
end

function State:IsAppearanceAppliedToSlot(slotKey, record)
    if type(record) ~= "table" or not slotKey then return false end
    local appliedId = self:GetAppliedCollectionId(slotKey)
    if not appliedId then return false end
    if Lab.IsHideVisualRecord(record) then
        return appliedId == 2
    end
    return tonumber(record.id) == appliedId
end

function State:IsSlotHidden(slotKey)
    if Lab.IsHideVisualRecord(self.draftBySlot[slotKey]) then
        return true
    end
    if self.draftBySlot[slotKey] then
        return false
    end
    return self:GetAppliedCollectionId(slotKey) == 2
end

function State:GetHiddenSlots()
    local hidden = {}
    for _, definition in ipairs(Lab.SLOTS) do
        if self:IsSlotHidden(definition.key) then
            hidden[definition.key] = true
        end
    end
    return hidden
end

function State:GetApplyWarnings()
    local warnings = {}
    local hideDraft = false
    for _, definition in ipairs(Lab.SLOTS) do
        if self.dirtySlots[definition.key]
            and Lab.IsHideVisualRecord(self.draftBySlot[definition.key]) then
            hideDraft = true
            break
        end
    end
    if hideDraft then
        if Lab.IsAppliedReady() then
            warnings[#warnings + 1] = "包含隐藏外观，将写入当前角色。"
        else
            warnings[#warnings + 1] = "隐藏外观只会留在本地预览，不会写入装备。"
        end
    end
    return warnings
end

function State:GetApplyCost()
    if self.quoteStatus == "READY" and type(self.quotedCopper) == "number" then
        return self.quotedCopper, "READY"
    end
    return 0, "UNAVAILABLE"
end

function State:BuildSetIntentEntries()
    local parts, seen = {}, {}
    local variant = getSelectedVariant(self.presetRecord)
    for _, member in ipairs((variant and variant.members) or {}) do
        local slotKey = member.slotKey
        local definition = slotKey and Lab.SLOT_BY_KEY[slotKey]
        local collectionId = memberCollectionId(member)
        if definition and collectionId and not seen[slotKey] and self:IsSlotOccupied(slotKey) then
            seen[slotKey] = true
            parts[#parts + 1] = string.format("%d:%d", definition.inventorySlot + 1, collectionId)
        end
    end
    return table.concat(parts, ","), #parts
end

function State:BuildIntentEntries()
    if self.presetRecord then
        return self:BuildSetIntentEntries()
    end
    local parts = {}
    for _, definition in ipairs(Lab.SLOTS) do
        local record = self.draftBySlot[definition.key]
        if self:IsSlotApplyable(definition.key) and record then
            local collectionId = Lab.IsHideVisualRecord(record) and 2 or tonumber(record.id)
            if collectionId then
                parts[#parts + 1] = string.format("%d:%d", definition.inventorySlot + 1, collectionId)
            end
        end
    end
    return table.concat(parts, ","), #parts
end

function State:RequestQuote()
    local entries, count = self:BuildIntentEntries()
    if count == 0 or not SC.Bridge or type(SC.Bridge.QuoteApply) ~= "function" then
        self.quotedCopper, self.quoteStatus, self.quoteWarningMask = nil, "UNAVAILABLE", 0
        return nil
    end
    self.quoteToken = (self.quoteToken or 0) + 1
    local token = self.quoteToken
    return SC.Bridge.QuoteApply(entries, count, function(ok, reason, detail)
        if self.quoteToken ~= token then return end
        if ok and type(detail) == "table" then
            self.quotedCopper = tonumber(detail.copper) or 0
            self.quoteWarningMask = tonumber(detail.warningMask) or 0
            self.quoteStatus = "READY"
        else
            self.quotedCopper, self.quoteStatus = nil, reason or "UNAVAILABLE"
        end
        self:Notify("QUOTE")
    end)
end

function State:ScheduleQuote()
    self.quoteAt = (GetTime and GetTime() or 0) + 0.2
    if self.quoteFrame then return end
    local frame = CreateFrame("Frame")
    self.quoteFrame = frame
    frame:SetScript("OnUpdate", function(owner)
        if not self.quoteAt then
            owner:SetScript("OnUpdate", nil)
            self.quoteFrame = nil
            return
        end
        if (GetTime and GetTime() or 0) >= self.quoteAt then
            self.quoteAt = nil
            owner:SetScript("OnUpdate", nil)
            self.quoteFrame = nil
            self:RequestQuote()
        end
    end)
end

function Lab.ConfirmApply(state, summary, onAccept)
    local copper = 0
    if state and state.GetApplyCost then
        copper = state:GetApplyCost()
    end
    local _, costState = state:GetApplyCost()
    local text = tostring(summary or "确定应用当前待定幻化？")
    if costState == "READY" then
        text = text .. "\n费用由服务端报价，见下方金额。"
    else
        text = text .. "\n当前没有有效报价，金额按 0 显示；应用时由服务端重新计价。"
    end
    Lab.pendingPopupAccept = onAccept
    local dialog
    if StaticPopup_Show then
        dialog = StaticPopup_Show("SOLOCOLLECTIONS_TRANSMOG_APPLY", text, nil, copper)
    end
    if dialog then return dialog end
    return Lab.Confirm(text, onAccept)
end

function Lab.BeginApplyWithWarnings(state)
    if not state then return false end
    if state.requestState and state.requestState.status == "REQUESTING" then
        Lab.Notice("已有应用请求正在处理。")
        return false
    end
    if state.presetRecord then
        local canApply, reason, owned, required = state:GetSetApplyState()
        if canApply then
            local name = tostring(state.presetRecord.name or state.presetRecord.id)
            return Lab.ConfirmApply(state, "确定应用套装「" .. name .. "」？", function()
                state:BeginApplyAll()
            end)
        end
        Lab.NotifyApplyBlocked(reason, {
            set = true,
            owned = owned or (state.presetRecord and state.presetRecord.collectedCount) or 0,
            required = required or (state.presetRecord and state.presetRecord.requiredCount) or 0,
        })
        return false
    end
    local canApply, reason = state:GetDraftApplyState()
    if not canApply then
        Lab.NotifyApplyBlocked(reason)
        return false
    end
    local slots = state:GetPendingApplySlots()
    local summary = string.format("确定将 %d 个部位的幻化写入装备？", #slots)
    local warnings = state:GetApplyWarnings()
    if warnings[1] then
        summary = warnings[1] .. summary
    end
    return Lab.ConfirmApply(state, summary, function()
        state:BeginApplyAll()
    end)
end

function State:HasOnlyHideVisualDrafts()
    local any = false
    for slotKey, record in pairs(self.draftBySlot) do
        if self.dirtySlots[slotKey] then
            any = true
            if not Lab.IsHideVisualRecord(record) then
                return false
            end
        end
    end
    return any
end

function State:GetSlotPreviewItemId(slotKey)
    if self.presetRecord then
        local variant = getSelectedVariant(self.presetRecord)
        for _, member in ipairs((variant and variant.members) or {}) do
            if member.slotKey == slotKey then
                local itemId = getMemberItemId(member)
                if itemId then return itemId, true end
            end
        end
    end
    local draft = self.draftBySlot[slotKey]
    if Lab.IsHideVisualRecord(draft) then
        return nil, true
    end
    if draft then return recordItemId(draft), true end
    local appliedId = self:GetAppliedCollectionId(slotKey)
    if appliedId == 2 then
        return nil, false
    end
    if appliedId then
        local record = Lab.FindAppearanceRecord(appliedId)
        if record then return recordItemId(record), false end
    end
    return self.equippedBySlot[slotKey], false
end

function State:GetPreviewItemIds()
    local items = {}
    local selected = self.selectedSlot
    local hideRanged = selected == "MAINHAND" or selected == "OFFHAND"
    local hideMelee = selected == "RANGED"
    for _, definition in ipairs(Lab.SLOTS) do
        local key = definition.key
        if hideRanged and key == "RANGED" then
            -- Hunters AutoDress a drawn ranged weapon; omit it while
            -- previewing a melee slot.
        elseif hideMelee and (key == "MAINHAND" or key == "OFFHAND") then
            -- Selecting the ranged slot should not keep a melee weapon drawn.
        elseif not self:IsSlotHidden(key) then
            local itemId = self:GetSlotPreviewItemId(key)
            if itemId then items[#items + 1] = itemId end
        end
    end
    return items
end

function State:IsSlotApplyable(slotKey)
    local record = self.draftBySlot[slotKey]
    if not self.dirtySlots[slotKey] or type(record) ~= "table" then return false end
    if not self:IsSlotOccupied(slotKey) then return false end
    if Lab.IsHideVisualRecord(record) then
        return Lab.IsAppliedReady() and true or false
    end
    return Lab.IsCollectedRecord(record)
end

function State:GetPendingApplySlots()
    local slots = {}
    for _, definition in ipairs(Lab.SLOTS) do
        if self:IsSlotApplyable(definition.key) then
            slots[#slots + 1] = definition.key
        end
    end
    return slots
end

function State:GetAffordabilityReason()
    if self.quoteStatus and self.quoteStatus ~= "READY" and self.quoteStatus ~= "UNAVAILABLE" then
        return self.quoteStatus
    end
    if self.quoteStatus == "READY" and type(self.quotedCopper) == "number" then
        local money = GetMoney and GetMoney() or 0
        if self.quotedCopper > 0 and money < self.quotedCopper then
            return "INSUFFICIENT_FUNDS"
        end
    end
    return nil
end

function State:GetDraftBlockReason()
    if self.requestState.status == "REQUESTING" then return "REQUEST_PENDING" end
    if Lab.IsAppliedReady() then
        if not SC.Bridge or type(SC.Bridge.ApplyPending) ~= "function" then
            return "BRIDGE_UNAVAILABLE"
        end
    elseif not SC.Bridge or type(SC.Bridge.ApplyAppearance) ~= "function" then
        return "BRIDGE_UNAVAILABLE"
    end
    local anyDirty = false
    local anyEmpty, anyUncollected, anyHideBlocked, anyApplyable = false, false, false, false
    for _, definition in ipairs(Lab.SLOTS) do
        local record = self.draftBySlot[definition.key]
        if self.dirtySlots[definition.key] and record then
            anyDirty = true
            if not self:IsSlotOccupied(definition.key) then
                anyEmpty = true
            elseif Lab.IsHideVisualRecord(record) and not Lab.IsAppliedReady() then
                anyHideBlocked = true
            elseif not Lab.IsHideVisualRecord(record) and not Lab.IsCollectedRecord(record) then
                anyUncollected = true
            else
                anyApplyable = true
            end
        end
    end
    if not anyDirty then return "NO_DRAFT" end
    if not anyApplyable then
        if anyUncollected then return "NOT_OWNED" end
        if anyEmpty then return "INVALID_TARGET_SLOT" end
        if anyHideBlocked then return "HIDE_VISUAL_UNSUPPORTED" end
        return "NO_DRAFT"
    end
    return self:GetAffordabilityReason()
end

local PREVIEW_RANGED_WEAPON_TYPES = {
    BOW = true, GUN = true, CROSSBOW = true, THROWN = true, WAND = true,
}

function State:GetDraftSlotReasons()
    local reasons = {}
    for _, definition in ipairs(Lab.SLOTS) do
        local record = self.draftBySlot[definition.key]
        if self.dirtySlots[definition.key] and record then
            local reason
            if not self:IsSlotOccupied(definition.key) then
                reason = "INVALID_TARGET_SLOT"
            elseif not Lab.IsHideVisualRecord(record) and not Lab.IsCollectedRecord(record) then
                reason = "NOT_OWNED"
            else
                local weaponType = record.weaponType or record.weaponCategory
                local isRanged = PREVIEW_RANGED_WEAPON_TYPES[weaponType] or record.slot == "RANGED"
                if (definition.key == "MAINHAND" or definition.key == "OFFHAND") and isRanged then
                    reason = "WEAPON_TYPE"
                elseif definition.key == "RANGED" and weaponType and not isRanged then
                    reason = "WEAPON_TYPE"
                end
            end
            if reason then
                reasons[#reasons + 1] = {
                    slot = definition.key,
                    label = definition.label,
                    reason = reason,
                }
            end
        end
    end
    if #reasons == 0 and self.quoteStatus
        and self.quoteStatus ~= "READY" and self.quoteStatus ~= "UNAVAILABLE" then
        for _, definition in ipairs(Lab.SLOTS) do
            if self:IsSlotApplyable(definition.key) then
                reasons[#reasons + 1] = {
                    slot = definition.key,
                    label = definition.label,
                    reason = self.quoteStatus,
                }
            end
        end
        if #reasons == 0 then
            local selected = Lab.SLOT_BY_KEY[self.selectedSlot]
            reasons[1] = {
                slot = self.selectedSlot,
                label = selected and selected.label or tostring(self.selectedSlot or ""),
                reason = self.quoteStatus,
            }
        end
    end
    return reasons
end

function State:GetDraftApplyState()
    local reason = self:GetDraftBlockReason()
    if reason then return false, reason end
    return true
end

function State:GetSetApplyState()
    local record = self.presetRecord
    if not record then return false, "NO_PRESET" end
    if self.requestState.status == "REQUESTING" then return false, "REQUEST_PENDING" end
    if Lab.IsAppliedReady() then
        if not SC.Bridge or type(SC.Bridge.ApplyPending) ~= "function" then
            return false, "BRIDGE_UNAVAILABLE"
        end
    elseif not SC.Bridge or type(SC.Bridge.ApplySet) ~= "function" then
        return false, "BRIDGE_UNAVAILABLE"
    end
    if not Lab.IsCollectedRecord(record) then
        return false, "NOT_OWNED", tonumber(record.collectedCount), tonumber(record.requiredCount)
    end
    local _, count = self:BuildSetIntentEntries()
    if count == 0 then return false, "INVALID_TARGET_SLOT" end
    local reason = self:GetAffordabilityReason()
    if reason then return false, reason end
    return true
end

function State:BeginApplyDraft()
    return self:BeginApplyAll()
end

function State:BeginApply()
    return self:BeginApplyAll()
end

function State:BeginApplySlot(slotKey)
    local record, definition = self.draftBySlot[slotKey], Lab.SLOT_BY_KEY[slotKey]
    if not record or not definition then return false, "NO_DRAFT" end
    if not self:IsSlotOccupied(slotKey) then return false, "INVALID_TARGET_SLOT" end
    if Lab.IsHideVisualRecord(record) then return false, "HIDE_VISUAL_UNSUPPORTED" end
    if not Lab.IsCollectedRecord(record) then return false, "NOT_OWNED" end
    if self.requestState.status == "REQUESTING" then return false, "REQUEST_PENDING" end
    if not SC.Bridge or type(SC.Bridge.ApplyAppearance) ~= "function" then
        return false, "BRIDGE_UNAVAILABLE"
    end
    local queue = self.applyQueue or {}
    local queueIndex, queueTotal = 1, 1
    for index, queued in ipairs(queue) do
        if queued == slotKey then
            queueIndex, queueTotal = index, #queue
            break
        end
    end
    self.requestSerial = self.requestSerial + 1
    local requestToken = self.requestSerial
    self.requestState = {
        status = "REQUESTING", kind = "SLOT", slot = slotKey, record = record,
        revision = currentRevision(), token = requestToken,
        queueIndex = queueIndex, queueTotal = queueTotal,
    }
    self:Notify("REQUESTING")
    local requestId = SC.Bridge.ApplyAppearance(record.id, definition.inventorySlot, function(ok, reason)
        if not self.requestState or self.requestState.token ~= requestToken then return end
        if ok then
            self:CompleteSlotApply(slotKey, requestToken, reason or "ACCEPTED")
        else
            self.applyQueue = {}
            self.requestState.status, self.requestState.reason = "FAILED", reason or "UNKNOWN"
            self:Notify("REQUEST_RESULT")
        end
    end)
    if self.requestState and self.requestState.token == requestToken then
        self.requestState.requestId = requestId
    end
    if not requestId and self.requestState and self.requestState.token == requestToken
        and self.requestState.status == "REQUESTING" then
        self.applyQueue = {}
        self.requestState.status, self.requestState.reason = "FAILED", "REQUEST_NOT_SENT"
        self:Notify("REQUEST_RESULT")
    end
    local failureReason = self.requestState and self.requestState.reason
    return requestId ~= nil, requestId and nil or failureReason
end

function State:CompleteSlotApply(slotKey, requestToken, reason)
    if not self.requestState or self.requestState.token ~= requestToken then return end
    local appliedId = Lab.IsHideVisualRecord(self.draftBySlot[slotKey]) and 2
        or tonumber(self.draftBySlot[slotKey] and self.draftBySlot[slotKey].id)
    if appliedId then self:RememberAppliedSlot(slotKey, appliedId) end
    self.draftBySlot[slotKey], self.dirtySlots[slotKey] = nil, nil
    self:CaptureEquipped()
    local queue = self.applyQueue or {}
    local nextIndex = nil
    for index, queued in ipairs(queue) do
        if queued == slotKey then
            nextIndex = index + 1
            break
        end
    end
    if nextIndex and queue[nextIndex] then
        self.requestState.status, self.requestState.reason = "CONFIRMED", reason
        self:Notify("REQUEST_RESULT")
        self:BeginApplySlot(queue[nextIndex])
        return
    end
    self.applyQueue = {}
    self.requestState = {
        status = "CONFIRMED", kind = "SLOT", slot = slotKey,
        revision = currentRevision(), reason = reason,
    }
    Lab.PlaySound("apply")
    self:Notify("AUTHORITATIVE_REFRESH")
end

function State:BeginApplyAll()
    if self.presetRecord then return self:BeginApplySet() end
    if self.requestState.status == "REQUESTING" then return false, "REQUEST_PENDING" end
    local canApply, reason = self:GetDraftApplyState()
    if not canApply then return false, reason end
    if not Lab.IsAppliedReady() then
        local slots = self:GetPendingApplySlots()
        if #slots == 0 then return false, "NO_DRAFT" end
        self.applyQueue = slots
        return self:BeginApplySlot(slots[1])
    end
    local entries, count = self:BuildIntentEntries()
    if count == 0 then return false, "NO_DRAFT" end
    self:RequestQuote()
    self.requestSerial = self.requestSerial + 1
    local requestToken = self.requestSerial
    self.requestState = {
        status = "REQUESTING", kind = "BATCH",
        revision = currentRevision(), token = requestToken,
    }
    self:Notify("REQUESTING")
    local requestId = SC.Bridge.ApplyPending(entries, count, function(ok, status)
        if not self.requestState or self.requestState.token ~= requestToken then return end
        if ok then
            self:RememberAppliedEntries(entries)
            self.draftBySlot, self.dirtySlots = {}, {}
            self:CaptureEquipped()
            self.requestState = {
                status = "CONFIRMED", kind = "BATCH",
                revision = currentRevision(), reason = status or "ACCEPTED",
            }
            Lab.PlaySound("apply")
            self:Notify("AUTHORITATIVE_REFRESH")
        else
            if status == "COST_CHANGED" then
                self:RequestQuote()
            end
            if status == "INSUFFICIENT_FUNDS" then
                Lab.Notice("金币不足，外观没有写入。费用见左侧金额。")
            end
            self.requestState.status, self.requestState.reason = "FAILED", status or "UNKNOWN"
            self:Notify("REQUEST_RESULT")
        end
    end)
    if self.requestState and self.requestState.token == requestToken then
        self.requestState.requestId = requestId
    end
    if not requestId and self.requestState and self.requestState.token == requestToken
        and self.requestState.status == "REQUESTING" then
        self.requestState.status, self.requestState.reason = "FAILED", "REQUEST_NOT_SENT"
        self:Notify("REQUEST_RESULT")
    end
    local failureReason = self.requestState and self.requestState.reason
    return requestId ~= nil, requestId and nil or failureReason
end

function State:BeginApplySet()
    local record = self.presetRecord
    if not record then return false, "NO_PRESET" end
    local canApply, reason = self:GetSetApplyState()
    if not canApply then return false, reason end
    if self.requestState.status == "REQUESTING" then return false, "REQUEST_PENDING" end
    local entries, count = self:BuildSetIntentEntries()
    if Lab.IsAppliedReady() and count > 0 and SC.Bridge and type(SC.Bridge.ApplyPending) == "function" then
        self:RequestQuote()
        self.requestSerial = self.requestSerial + 1
        local requestToken = self.requestSerial
        self.requestState = {
            status = "REQUESTING", kind = "SET", record = record,
            revision = currentRevision(), token = requestToken,
        }
        self:Notify("REQUESTING_SET")
        local requestId = SC.Bridge.ApplyPending(entries, count, function(ok, status)
            if not self.requestState or self.requestState.token ~= requestToken then return end
            if ok then
                self:RememberAppliedEntries(entries)
                self.presetRecord = nil
                self.draftBySlot, self.dirtySlots = {}, {}
                self:CaptureEquipped()
                self.requestState = {
                    status = "CONFIRMED", kind = "SET",
                    revision = currentRevision(), reason = status or "ACCEPTED",
                }
                Lab.PlaySound("apply")
                self:Notify("AUTHORITATIVE_REFRESH")
            else
                if status == "COST_CHANGED" then
                    self:RequestQuote()
                end
                if status == "INSUFFICIENT_FUNDS" then
                    Lab.Notice("金币不足，外观没有写入。费用见左侧金额。")
                end
                self.requestState.status, self.requestState.reason = "FAILED", status or "UNKNOWN"
                self:Notify("REQUEST_RESULT")
            end
        end)
        if self.requestState and self.requestState.token == requestToken then
            self.requestState.requestId = requestId
        end
        if not requestId and self.requestState and self.requestState.token == requestToken
            and self.requestState.status == "REQUESTING" then
            self.requestState.status, self.requestState.reason = "FAILED", "REQUEST_NOT_SENT"
            self:Notify("REQUEST_RESULT")
        end
        local failureReason = self.requestState and self.requestState.reason
        return requestId ~= nil, requestId and nil or failureReason
    end
    if not SC.Bridge or type(SC.Bridge.ApplySet) ~= "function" then
        return false, "BRIDGE_UNAVAILABLE"
    end
    local variant = getSelectedVariant(record)
    self.requestSerial = self.requestSerial + 1
    local requestToken = self.requestSerial
    self.requestState = {
        status = "REQUESTING", kind = "SET", record = record,
        revision = currentRevision(), token = requestToken,
    }
    self:Notify("REQUESTING_SET")
    local requestId = SC.Bridge.ApplySet(record.id, variant and variant.variantOrdinal or nil, function(ok, reason)
        if not self.requestState or self.requestState.token ~= requestToken then return end
        if ok then
            local appliedVariant = getSelectedVariant(record)
            for _, member in ipairs((appliedVariant and appliedVariant.members) or {}) do
                local collectionId = memberCollectionId(member)
                if member.slotKey and collectionId then
                    self:RememberAppliedSlot(member.slotKey, collectionId)
                end
            end
            self.presetRecord = nil
            self.draftBySlot, self.dirtySlots = {}, {}
            self:CaptureEquipped()
            self.requestState = {
                status = "CONFIRMED", kind = "SET",
                revision = currentRevision(), reason = reason or "ACCEPTED",
            }
            Lab.PlaySound("apply")
            self:Notify("AUTHORITATIVE_REFRESH")
        else
            if reason == "INSUFFICIENT_FUNDS" then
                Lab.Notice("金币不足，外观没有写入。费用见左侧金额。")
            end
            self.requestState.status, self.requestState.reason = "FAILED", reason or "UNKNOWN"
            self:Notify("REQUEST_RESULT")
        end
    end)
    if self.requestState and self.requestState.token == requestToken then
        self.requestState.requestId = requestId
    end
    if not requestId and self.requestState and self.requestState.token == requestToken
        and self.requestState.status == "REQUESTING" then
        self.requestState.status, self.requestState.reason = "FAILED", "REQUEST_NOT_SENT"
        self:Notify("REQUEST_RESULT")
    end
    local failureReason = self.requestState and self.requestState.reason
    return requestId ~= nil, requestId and nil or failureReason
end

function State:CaptureOutfitSlots()
    local slots = {}
    if self.presetRecord then
        local variant = getSelectedVariant(self.presetRecord)
        for _, member in ipairs((variant and variant.members) or {}) do
            local slotKey = member.slotKey
            if Lab.SLOT_BY_KEY[slotKey] then
                local itemId = getMemberItemId(member)
                local record = Lab.FindAppearanceRecord(member.collectionId, itemId)
                if record then
                    slots[slotKey] = { id = record.id, itemId = recordItemId(record) or itemId }
                elseif itemId then
                    slots[slotKey] = { itemId = itemId }
                end
            end
        end
        return slots
    end
    for _, definition in ipairs(Lab.SLOTS) do
        local record = self.draftBySlot[definition.key]
        if Lab.IsHideVisualRecord(record) then
            slots[definition.key] = { id = 2, hide = true }
        elseif record then
            slots[definition.key] = { id = record.id, itemId = recordItemId(record) }
        else
            local equippedId = self.equippedBySlot[definition.key]
            record = Lab.FindAppearanceRecord(nil, equippedId)
            if record then
                slots[definition.key] = { id = record.id, itemId = equippedId }
            end
        end
    end
    return slots
end

local function encodeOutfitEntries(slotMap)
    local parts = {}
    for _, definition in ipairs(Lab.SLOTS) do
        local payload = slotMap and slotMap[definition.key]
        local collectionId
        if type(payload) == "table" then
            collectionId = Lab.IsHideVisualRecord(payload) and 2 or tonumber(payload.id)
        else
            collectionId = tonumber(payload)
        end
        if collectionId == 2 then
            parts[#parts + 1] = "2"
        elseif collectionId and collectionId > 0 then
            parts[#parts + 1] = tostring(collectionId)
        else
            parts[#parts + 1] = "-"
        end
    end
    return table.concat(parts, ",")
end

function State:SaveOutfit(name)
    name = string.gsub(tostring(name or ""), "^%s+", "")
    name = string.gsub(name, "%s+$", "")
    if name == "" or string.len(name) > Lab.OUTFIT_NAME_MAX then return nil, "INVALID_NAME" end
    if not Lab.IsOutfitReady() or not SC.Bridge or type(SC.Bridge.SaveOutfit) ~= "function" then
        return nil, "BRIDGE_UNAVAILABLE"
    end
    local slots = self:CaptureOutfitSlots()
    if not next(slots) then return nil, "EMPTY_OUTFIT" end
    if #Lab.GetStoredOutfits() >= Lab.MAX_OUTFITS then return nil, "OUTFIT_LIMIT" end
    local requestId = SC.Bridge.SaveOutfit(0, name, encodeOutfitEntries(slots), function(ok, reason, detail)
        if ok then
            self.activeOutfitUid = detail and detail.collectionId or self.activeOutfitUid
            self.requestState = { status = "OUTFIT_SAVED", revision = currentRevision() }
            self:Notify("OUTFIT_SAVED")
        else
            self.requestState = { status = "FAILED", reason = reason or "UNKNOWN" }
            self:Notify("REQUEST_RESULT")
        end
    end)
    if not requestId then return nil, "REQUEST_NOT_SENT" end
    return { pending = true, requestId = requestId }
end

function State:OverwriteOutfit(uid)
    uid = tonumber(uid)
    if not uid then return nil, "INVALID_OUTFIT" end
    if not Lab.IsOutfitReady() or not SC.Bridge or type(SC.Bridge.SaveOutfit) ~= "function" then
        return nil, "BRIDGE_UNAVAILABLE"
    end
    local slots = self:CaptureOutfitSlots()
    if not next(slots) then return nil, "EMPTY_OUTFIT" end
    local name = "Outfit"
    for _, outfit in ipairs(Lab.GetStoredOutfits()) do
        if outfit.uid == uid then name = outfit.name break end
    end
    local requestId = SC.Bridge.SaveOutfit(uid, name, encodeOutfitEntries(slots), function(ok, reason)
        if ok then
            self.activeOutfitUid = uid
            self.requestState = { status = "OUTFIT_SAVED", revision = currentRevision() }
            self:Notify("OUTFIT_SAVED")
        else
            self.requestState = { status = "FAILED", reason = reason or "UNKNOWN" }
            self:Notify("REQUEST_RESULT")
        end
    end)
    if not requestId then return nil, "REQUEST_NOT_SENT" end
    return { pending = true, requestId = requestId }
end

function State:RenameOutfit(uid, name)
    uid = tonumber(uid)
    name = string.gsub(tostring(name or ""), "^%s+", "")
    name = string.gsub(name, "%s+$", "")
    if not uid or name == "" or string.len(name) > Lab.OUTFIT_NAME_MAX then return nil, "INVALID_NAME" end
    if not Lab.IsOutfitReady() or not SC.Bridge or type(SC.Bridge.RenameOutfit) ~= "function" then
        return nil, "BRIDGE_UNAVAILABLE"
    end
    local requestId = SC.Bridge.RenameOutfit(uid, name, function(ok, reason)
        if ok then
            self.activeOutfitUid = uid
            self.requestState = { status = "OUTFIT_SAVED", revision = currentRevision() }
            self:Notify("OUTFIT_SAVED")
        else
            self.requestState = { status = "FAILED", reason = reason or "UNKNOWN" }
            self:Notify("REQUEST_RESULT")
        end
    end)
    if not requestId then return nil, "REQUEST_NOT_SENT" end
    return { pending = true, requestId = requestId }
end

function State:LoadOutfit(outfit)
    if type(outfit) ~= "table" or type(outfit.slots) ~= "table" then return false, "INVALID_OUTFIT" end
    self.presetRecord = nil
    self.draftBySlot, self.dirtySlots = {}, {}
    for slotKey, payload in pairs(outfit.slots) do
        if Lab.SLOT_BY_KEY[slotKey] then
            local collectionId = type(payload) == "table" and tonumber(payload.id) or tonumber(payload)
            if collectionId == 2 or (type(payload) == "table" and payload.hide) then
                self.draftBySlot[slotKey] = Lab.CreateHideVisualRecord(slotKey)
                self.dirtySlots[slotKey] = true
            else
                local record = Lab.FindAppearanceRecord(collectionId, type(payload) == "table" and payload.itemId)
                if record then
                    self.draftBySlot[slotKey] = record
                    self.dirtySlots[slotKey] = true
                end
            end
        end
    end
    self.activeOutfitUid = outfit.uid
    self.preservedOnClose = false
    self.requestState = { status = "OUTFIT_LOADED", revision = currentRevision() }
    self:ScheduleQuote()
    self:Notify("OUTFIT_LOADED")
    return true
end

function State:DeleteOutfit(uid)
    uid = tonumber(uid)
    if not uid or not Lab.IsOutfitReady() or not SC.Bridge or type(SC.Bridge.DeleteOutfit) ~= "function" then
        return false
    end
    local requestId = SC.Bridge.DeleteOutfit(uid, function(ok, reason)
        if ok then
            if self.activeOutfitUid == uid then self.activeOutfitUid = nil end
            self.requestState = { status = "OUTFIT_DELETED", revision = currentRevision() }
            self:Notify("OUTFIT_DELETED")
        else
            self.requestState = { status = "FAILED", reason = reason or "UNKNOWN" }
            self:Notify("REQUEST_RESULT")
        end
    end)
    return requestId ~= nil
end

function State:UploadLocalOutfit(outfit)
    if type(outfit) ~= "table" or type(outfit.name) ~= "string" or type(outfit.slots) ~= "table" then
        return nil, "INVALID_OUTFIT"
    end
    if not Lab.IsOutfitReady() or not SC.Bridge or type(SC.Bridge.SaveOutfit) ~= "function" then
        return nil, "BRIDGE_UNAVAILABLE"
    end
    return SC.Bridge.SaveOutfit(0, outfit.name, encodeOutfitEntries(outfit.slots), function(ok, reason)
        self.requestState = {
            status = ok and "OUTFIT_SAVED" or "FAILED",
            reason = reason,
            revision = currentRevision(),
        }
        self:Notify(ok and "OUTFIT_SAVED" or "REQUEST_RESULT")
    end)
end

function State:CanClearAppliedSlot(slotKey)
    if not slotKey or self:IsSlotDirty(slotKey) then return false end
    if not Lab.IsAppliedReady() then return false end
    if self.requestState and self.requestState.status == "REQUESTING" then return false end
    return self:GetAppliedCollectionId(slotKey) ~= nil
end

function State:ClearApplied(slotKey)
    if not Lab.IsAppliedReady() or not SC.Bridge or type(SC.Bridge.ClearApplied) ~= "function" then
        return false, "BRIDGE_UNAVAILABLE"
    end
    if self.requestState and self.requestState.status == "REQUESTING" then
        return false, "REQUEST_PENDING"
    end
    local entries, count = "-", 0
    if slotKey then
        local definition = Lab.SLOT_BY_KEY[slotKey]
        if not definition or not self:GetAppliedCollectionId(slotKey) then
            return false, "NOTHING_EQUIPPED"
        end
        entries = tostring(definition.inventorySlot + 1)
        count = 1
    end
    self.requestSerial = self.requestSerial + 1
    local requestToken = self.requestSerial
    self.requestState = { status = "REQUESTING", kind = "CLEAR", token = requestToken, slot = slotKey }
    self:Notify("REQUESTING")
    local requestId = SC.Bridge.ClearApplied(entries, count, function(ok, reason)
        if not self.requestState or self.requestState.token ~= requestToken then return end
        if ok then
            if slotKey then
                self.appliedOverlay = self.appliedOverlay or {}
                self.ignoredAppliedSlots = self.ignoredAppliedSlots or {}
                self.appliedOverlay[slotKey] = nil
                self.ignoredAppliedSlots[slotKey] = true
                if self.trustedEquippedBySlot then
                    self.trustedEquippedBySlot[slotKey] = nil
                end
            else
                self.appliedOverlay, self.ignoredAppliedSlots = {}, {}
                self.trustedEquippedBySlot = {}
                self.draftBySlot, self.dirtySlots = {}, {}
            end
            self:CaptureEquipped()
            self.requestState = { status = "CONFIRMED", kind = "CLEAR", reason = reason or "ACCEPTED", slot = slotKey }
            self:Notify("AUTHORITATIVE_REFRESH")
        else
            self.requestState.status, self.requestState.reason = "FAILED", reason or "UNKNOWN"
            self:Notify("REQUEST_RESULT")
        end
    end)
    if not requestId and self.requestState and self.requestState.token == requestToken
        and self.requestState.status == "REQUESTING" then
        self.requestState.status, self.requestState.reason = "FAILED", "REQUEST_NOT_SENT"
        self:Notify("REQUEST_RESULT")
    end
    return requestId ~= nil
end

function State:ObserveAuthoritativeState()
    return false
end

function State:MarkClosed() self.preservedOnClose = self:HasDraft() end
