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
        id = "HIDE:" .. tostring(slotKey or ""),
        isHideVisual = true,
        collected = true,
        favorite = false,
        name = "隐藏外观",
        slot = slotKey,
        itemId = nil,
        itemIds = {},
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
        requestState = { status = "IDLE", revision = currentRevision() },
        listeners = {}, generation = 0, preservedOnClose = false,
        presetRecord = nil, requestSerial = 0, applyQueue = {},
        activeOutfitUid = nil,
    }, State)
    state:CaptureEquipped()
    return state
end

function State:CaptureEquipped()
    self.equippedBySlot = {}
    for _, definition in ipairs(Lab.SLOTS) do
        local link = GetInventoryItemLink and GetInventoryItemLink("player", definition.inventorySlot + 1)
        self.equippedBySlot[definition.key] = link and tonumber(string.match(link, "item:(%d+)")) or nil
    end
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
    self.selectedSlot = slotKey
    self:Notify("SELECT_SLOT")
    return true
end

function State:SetDraft(slotKey, record)
    if not Lab.SLOT_BY_KEY[slotKey] or type(record) ~= "table" then return false end
    self.presetRecord = nil
    self.activeOutfitUid = nil
    self.draftBySlot[slotKey] = record
    self.dirtySlots[slotKey] = true
    self.preservedOnClose = false
    self.requestState = { status = "LOCAL_DRAFT", slot = slotKey, revision = currentRevision() }
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

function State:IsSlotHidden(slotKey)
    return Lab.IsHideVisualRecord(self.draftBySlot[slotKey])
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
    local hidden = self:GetHiddenSlots()
    if next(hidden) and #self:GetPendingApplySlots() > 0 then
        warnings[#warnings + 1] = "隐藏外观只会留在本地预览，不会写入装备。"
    end
    return warnings
end

-- Legion shows C_Transmog.GetCost() on the left MoneyFrame. SC2 has no cost
-- field yet; never invent a copper amount on the client.
function State:GetApplyCost()
    return 0, "UNAVAILABLE"
end

function Lab.ConfirmApply(state, summary, onAccept)
    local copper = 0
    if state and state.GetApplyCost then
        copper = state:GetApplyCost()
    end
    local text = tostring(summary or "确定应用当前待定幻化？")
        .. "\n当前费用（服务端尚未返回金额，按 0 显示）："
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
        if reason == "NOT_OWNED" then
            Lab.Notice(string.format(
                "当前套装尚未收集完整：%s / %s。未收藏套装只能预览。",
                tostring(owned or state.presetRecord.collectedCount or 0),
                tostring(required or state.presetRecord.requiredCount or 0)
            ))
            return false
        end
        Lab.Notice("当前套装预设暂不能提交应用。")
        return false
    end
    local canApply, reason = state:GetDraftApplyState()
    if reason == "HIDE_VISUAL_UNSUPPORTED" then
        Lab.Notice("隐藏外观只能本地预览，当前不能应用到装备。")
        return false
    end
    if reason == "NO_DRAFT" then
        Lab.Notice("先在右侧选择外观，建立待定幻化。")
        return false
    end
    if reason == "NOT_OWNED" then
        Lab.Notice("待定外观尚未收藏，只能本地预览。")
        return false
    end
    if not canApply then
        if reason == "BRIDGE_UNAVAILABLE" then
            Lab.Notice("SC2 外观服务尚未就绪，暂不能提交应用。")
        else
            Lab.Notice("当前待定外观暂不能提交应用。")
        end
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
    return self.equippedBySlot[slotKey], false
end

function State:GetPreviewItemIds()
    local items = {}
    for _, definition in ipairs(Lab.SLOTS) do
        if not self:IsSlotHidden(definition.key) then
            local itemId = self:GetSlotPreviewItemId(definition.key)
            if itemId then items[#items + 1] = itemId end
        end
    end
    return items
end

function State:GetPendingApplySlots()
    local slots = {}
    for _, definition in ipairs(Lab.SLOTS) do
        local record = self.draftBySlot[definition.key]
        if self.dirtySlots[definition.key] and record and record.collected
            and not Lab.IsHideVisualRecord(record) then
            slots[#slots + 1] = definition.key
        end
    end
    return slots
end

function State:GetDraftApplyState()
    if self.requestState.status == "REQUESTING" then return false, "REQUEST_PENDING" end
    if not SC.Bridge or type(SC.Bridge.ApplyAppearance) ~= "function" then
        return false, "BRIDGE_UNAVAILABLE"
    end
    local slots = self:GetPendingApplySlots()
    if #slots == 0 then
        if self:HasOnlyHideVisualDrafts() then return false, "HIDE_VISUAL_UNSUPPORTED" end
        if self:GetDirtyCount() > 0 then return false, "NOT_OWNED" end
        return false, "NO_DRAFT"
    end
    return true
end

function State:GetSetApplyState()
    local record = self.presetRecord
    if not record then return false, "NO_PRESET" end
    if self.requestState.status == "REQUESTING" then return false, "REQUEST_PENDING" end
    if not SC.Bridge or type(SC.Bridge.ApplySet) ~= "function" then
        return false, "BRIDGE_UNAVAILABLE"
    end
    if not record.collected then
        return false, "NOT_OWNED", tonumber(record.collectedCount), tonumber(record.requiredCount)
    end
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
    if Lab.IsHideVisualRecord(record) then return false, "HIDE_VISUAL_UNSUPPORTED" end
    if not record.collected then return false, "NOT_OWNED" end
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
    local slots = self:GetPendingApplySlots()
    if #slots == 0 then return false, "NO_DRAFT" end
    self.applyQueue = slots
    return self:BeginApplySlot(slots[1])
end

function State:BeginApplySet()
    local record = self.presetRecord
    if not record then return false, "NO_PRESET" end
    if not record.collected then return false, "NOT_OWNED" end
    if self.requestState.status == "REQUESTING" then return false, "REQUEST_PENDING" end
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
            -- HideVisual has no SC2 action yet; do not persist a fake outfit piece.
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

function State:SaveOutfit(name)
    name = string.gsub(tostring(name or ""), "^%s+", "")
    name = string.gsub(name, "%s+$", "")
    if name == "" or string.len(name) > Lab.OUTFIT_NAME_MAX then return nil, "INVALID_NAME" end
    local slots = self:CaptureOutfitSlots()
    if not next(slots) then return nil, "EMPTY_OUTFIT" end
    if not SC.db then return nil, "NO_DATABASE" end
    if type(SC.db.transmogOutfits) ~= "table" then SC.db.transmogOutfits = {} end
    local outfits = Lab.GetStoredOutfits()
    if #outfits >= Lab.MAX_OUTFITS then return nil, "OUTFIT_LIMIT" end
    local uid = string.format("%s-%d", tostring(time()), self.requestSerial + 1)
    local outfit = {
        uid = uid,
        name = name,
        character = characterKey(),
        slots = slots,
    }
    SC.db.transmogOutfits[#SC.db.transmogOutfits + 1] = outfit
    self.activeOutfitUid = uid
    self.requestState = { status = "OUTFIT_SAVED", revision = currentRevision() }
    self:Notify("OUTFIT_SAVED")
    return outfit
end

function State:OverwriteOutfit(uid)
    if not uid then return nil, "INVALID_OUTFIT" end
    local slots = self:CaptureOutfitSlots()
    if not next(slots) then return nil, "EMPTY_OUTFIT" end
    if not SC.db or type(SC.db.transmogOutfits) ~= "table" then return nil, "NO_DATABASE" end
    for _, outfit in ipairs(SC.db.transmogOutfits) do
        if outfit.uid == uid and outfit.character == characterKey() then
            outfit.slots = slots
            self.activeOutfitUid = uid
            self.requestState = { status = "OUTFIT_SAVED", revision = currentRevision() }
            self:Notify("OUTFIT_SAVED")
            return outfit
        end
    end
    return nil, "INVALID_OUTFIT"
end

function State:RenameOutfit(uid, name)
    name = string.gsub(tostring(name or ""), "^%s+", "")
    name = string.gsub(name, "%s+$", "")
    if name == "" or string.len(name) > Lab.OUTFIT_NAME_MAX then return nil, "INVALID_NAME" end
    if not SC.db or type(SC.db.transmogOutfits) ~= "table" then return nil, "NO_DATABASE" end
    for _, outfit in ipairs(SC.db.transmogOutfits) do
        if outfit.uid == uid and outfit.character == characterKey() then
            outfit.name = name
            self.activeOutfitUid = uid
            self.requestState = { status = "OUTFIT_SAVED", revision = currentRevision() }
            self:Notify("OUTFIT_SAVED")
            return outfit
        end
    end
    return nil, "INVALID_OUTFIT"
end

function State:LoadOutfit(outfit)
    if type(outfit) ~= "table" or type(outfit.slots) ~= "table" then return false, "INVALID_OUTFIT" end
    self.presetRecord = nil
    self.draftBySlot, self.dirtySlots = {}, {}
    for slotKey, payload in pairs(outfit.slots) do
        if Lab.SLOT_BY_KEY[slotKey] and type(payload) == "table" then
            local record = Lab.FindAppearanceRecord(payload.id, payload.itemId)
            if record then
                self.draftBySlot[slotKey] = record
                self.dirtySlots[slotKey] = true
            end
        end
    end
    self.activeOutfitUid = outfit.uid
    self.preservedOnClose = false
    self.requestState = { status = "OUTFIT_LOADED", revision = currentRevision() }
    self:Notify("OUTFIT_LOADED")
    return true
end

function State:DeleteOutfit(uid)
    if not SC.db or type(SC.db.transmogOutfits) ~= "table" then return false end
    for index, outfit in ipairs(SC.db.transmogOutfits) do
        if outfit.uid == uid then
            table.remove(SC.db.transmogOutfits, index)
            if self.activeOutfitUid == uid then self.activeOutfitUid = nil end
            self.requestState = { status = "OUTFIT_DELETED", revision = currentRevision() }
            self:Notify("OUTFIT_DELETED")
            return true
        end
    end
    return false
end

function State:ObserveAuthoritativeState()
    return false
end

function State:MarkClosed() self.preservedOnClose = self:HasDraft() end
