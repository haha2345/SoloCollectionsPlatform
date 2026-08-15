local SC = SoloCollections

SC.WardrobeLab = SC.WardrobeLab or {}
local Lab = SC.WardrobeLab

function Lab.IsEnabled()
    return SC.db and SC.db.experimental and SC.db.experimental.transmogLabEnabled == true
end

local STATUS_TEXT = {
    IDLE = "仅本地预览 · 尚未应用", LOCAL_DRAFT = "本地草稿 · 尚未应用",
    LOCAL_PRESET = "套装预设 · 尚未应用",
    CONFIRM_CLEAR = "存在未保存草稿 · 再点一次“清除草稿”确认",
    CONFIRM_SWITCH_EQUIPPED = "切换到当前装备会清除草稿 · 再点一次确认",
    CONFIRM_SET_PRESET = "切换套装预设会清除当前草稿 · 再点同一套装确认",
    REQUESTING = "正在请求应用…",
    CONFIRMED = "服务端已确认应用", FAILED = "应用失败",
}

local REASON_TEXT = {
    ACCEPTED = "服务端已接受。",
    NO_DRAFT = "当前槽位没有本地草稿。",
    NO_PRESET = "尚未选择套装预设。",
    NOT_OWNED = "尚未收藏此外观或完整套装。",
    INVALID_APPEARANCE = "外观记录无效。",
    INVALID_REQUEST = "应用请求无效。",
    INVALID_TARGET_SLOT = "对应装备栏没有可幻化物品。",
    CLASS_RESTRICTED = "当前角色无法使用这个外观。",
    NOT_ENOUGH_MONEY = "你没有足够的钱。",
    NOT_ENOUGH_TOKENS = "你的筹码不够。",
    BRIDGE_UNAVAILABLE = "统一收藏服务尚未就绪。",
    REQUEST_NOT_SENT = "请求未发送。",
    REQUEST_PENDING = "已有应用请求正在处理。",
    DISMISSED = "服务端未执行应用。",
    TIMEOUT = "服务端响应超时。",
    UNSUPPORTED = "服务端暂不支持这个操作。",
}

local SHORT_REASON_TEXT = {
    NOT_OWNED = "未收藏，不能应用",
    INVALID_TARGET_SLOT = "目标槽位不可用",
    BRIDGE_UNAVAILABLE = "服务未就绪",
    REQUEST_NOT_SENT = "请求未发送",
    REQUEST_PENDING = "请求处理中",
    DISMISSED = "服务端未执行",
}

local function recordName(record)
    if type(record) ~= "table" then return nil end
    return record.name or record.longName or (record.id and ("#" .. tostring(record.id))) or nil
end

local function reasonLabel(reason)
    return REASON_TEXT[tostring(reason or "")] or tostring(reason or "UNKNOWN")
end

local function shortReasonLabel(reason)
    return SHORT_REASON_TEXT[tostring(reason or "")] or reasonLabel(reason)
end

local function addChatNotice(message, ok)
    if DEFAULT_CHAT_FRAME and DEFAULT_CHAT_FRAME.AddMessage then
        DEFAULT_CHAT_FRAME:AddMessage("|cffff9f40SoloCollections:|r " .. tostring(message or ""))
    elseif UIErrorsFrame and UIErrorsFrame.AddMessage then
        UIErrorsFrame:AddMessage(tostring(message or ""), ok and 0.35 or 1, ok and 1 or 0.35, 0.2, 1)
    end
end

local function showActionNotice(request)
    request = request or {}
    local ok = request.status == "CONFIRMED"
    local message
    if ok then
        if request.kind == "SET" then
            message = "套装外观已应用。"
        elseif request.kind == "DRAFT" then
            message = "本地草稿已逐槽应用。"
        else
            message = "外观已应用。"
        end
    else
        local prefix = request.kind == "SET" and "套装应用失败：" or
            (request.kind == "DRAFT" and "草稿应用失败：" or "外观应用失败：")
        message = prefix .. reasonLabel(request.reason)
    end
    addChatNotice(message, ok)
end

local function showBlockedNotice()
    addChatNotice(reasonLabel("REQUEST_PENDING"), false)
end

local function slotLabel(slotKey)
    local definition = Lab.SLOT_BY_KEY and Lab.SLOT_BY_KEY[slotKey]
    return definition and definition.label or tostring(slotKey or "所选槽位")
end

local function isLabCollectionType(typeId)
    if typeId == nil then return true end
    typeId = tonumber(typeId)
    return typeId == 13 or typeId == 14
end

local function statusTextFor(state, request)
    request = request or {}
    if request.status == "LOCAL_DRAFT" then
        local slotKey = state.selectedSlot or request.slot
        local record = state.draftBySlot and state.draftBySlot[slotKey]
        if not record then
            slotKey = request.slot
            record = state.draftBySlot and state.draftBySlot[slotKey]
        end
        local count = state.GetDirtyCount and state:GetDirtyCount() or 0
        if record then
            return "本地草稿（" .. tostring(count) .. " 槽）：" ..
                slotLabel(slotKey) .. " · " .. tostring(recordName(record) or "未命名外观")
        end
        return "本地草稿（" .. tostring(count) .. " 槽）"
    elseif request.status == "LOCAL_PRESET" then
        return "套装预设：" .. tostring(recordName(request.record or state.presetRecord) or "未命名套装")
    elseif request.status == "CONFIRM_SET_PRESET" then
        return "切换套装预设会清除当前草稿 · 再点同一套装确认：" ..
            tostring(recordName(request.record) or "未命名套装")
    elseif request.status == "REQUESTING" then
        if request.kind == "SET" then
            return "正在请求应用套装预设…"
        elseif request.kind == "DRAFT" then
            return "正在逐槽应用草稿 " .. tostring(request.index or 0) .. "/" ..
                tostring(request.total or 0) .. " · " .. slotLabel(request.slot or state.selectedSlot)
        end
        return "正在请求应用" .. slotLabel(request.slot or state.selectedSlot) .. "…"
    elseif request.status == "CONFIRMED" then
        if request.kind == "SET" then
            return "服务端已确认应用套装"
        elseif request.kind == "DRAFT" then
            return "服务端已确认逐槽应用 " .. tostring(request.appliedCount or 0) .. " 个槽位"
        end
        return "服务端已确认应用" .. slotLabel(request.slot or state.selectedSlot)
    elseif request.status == "FAILED" then
        local slotText = request.slot and (slotLabel(request.slot) .. " · ") or ""
        return STATUS_TEXT.FAILED .. "：" .. slotText .. shortReasonLabel(request.reason)
    end
    return STATUS_TEXT[request.status] or STATUS_TEXT.IDLE
end

function Lab.CreatePage(parent)
    local page = CreateFrame("Frame", nil, parent)
    page:SetAllPoints(parent); page:Hide()
    local state = Lab.CreateState()
    page.scState = state
    Lab.CreateLayout(page, state)
    function page:Refresh()
        if state.presetRecord and state.RefreshPresetRecord then state:RefreshPresetRecord() end
        local request = state.requestState or {}
        self.scStateText:SetText(statusTextFor(state, request))
        self.scOutfits:Refresh()
        self.scSlots:Refresh()
        self.scSources:Refresh()
        self.scPreview:RefreshDraft()
        self:SyncFilters()
        if self.scApplyButton then
            local canApply = false
            self.scApplyButton:SetText("应用")
            if state.presetRecord then
                canApply = state.GetSetApplyState and state:GetSetApplyState(true) or false
            else
                canApply = state.GetDraftApplyState and state:GetDraftApplyState() or false
            end
            if canApply then
                self.scApplyButton:Enable()
                if self.scApplyDisabledTip then self.scApplyDisabledTip:Hide() end
            else
                self.scApplyButton:Disable()
                if self.scApplyDisabledTip then self.scApplyDisabledTip:Show() end
            end
        end
    end
    state:Subscribe(page, function(owner, _, reason)
        if not owner:IsShown() then return end
        if reason == "REQUEST_RESULT" then
            showActionNotice(owner.scState and owner.scState.requestState)
        elseif reason == "REQUEST_PENDING_BLOCKED" then
            showBlockedNotice()
        end
        if reason == "SELECT_SLOT" and owner.scSources then
            owner.scSources.itemPage = 1
            if owner.scSources.mode ~= "ITEMS" then
                owner.scSources:SetMode("ITEMS")
                owner:Refresh()
                return
            end
        end
        owner:Refresh()
    end)
    if SC.Bridge and type(SC.Bridge.RegisterStateListener) == "function" then
        page.scBridgeStateListener = SC.Bridge.RegisterStateListener(function(_, typeId)
            if not page:IsShown() or not isLabCollectionType(typeId) then return false end
            page:Refresh()
            return true
        end)
    end
    page:RegisterEvent("PLAYER_ENTERING_WORLD")
    page:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")
    page:RegisterEvent("UNIT_MODEL_CHANGED")
    page:RegisterEvent("GET_ITEM_INFO_RECEIVED")
    page:SetScript("OnEvent", function(self, event, ...)
        if event == "GET_ITEM_INFO_RECEIVED" then
            if not self:IsShown() then return end
            local itemId, success = ...
            if success == false or not itemId then return end
            if self.scSources and self.scSources.ContainsVisibleItem and
                self.scSources:ContainsVisibleItem(itemId) then
                self:Refresh()
            end
            return
        end
        if event == "UNIT_MODEL_CHANGED" then
            local unit = ...
            if unit ~= "player" then return end
        end
        state:CaptureEquipped()
        if self:IsShown() then self:Refresh() end
    end)
    page:SetScript("OnShow", function(self)
        state:CaptureEquipped()
        self:Refresh()
    end)
    page:SetScript("OnHide", function(self)
        state:MarkClosed()
        if self.scPreview and self.scPreview.scPresenter then self.scPreview.scPresenter:Clear("PAGE_HIDDEN") end
        if self.scSources and self.scSources.ClearPresenters then self.scSources:ClearPresenters("PAGE_HIDDEN") end
    end)
    function page:SyncFilters()
        if self.scSources and self.scSources.SyncFilters then
            self.scSources:SyncFilters()
        end
    end
    return page
end
