local SC = SoloCollections
local UI = SC.UI

SC.WardrobeLab = SC.WardrobeLab or {}
local Lab = SC.WardrobeLab

function Lab.IsEnabled()
    return true
end

local STATUS_TEXT = {
    IDLE = "选择外观试穿，再点应用写入当前装备",
    LOCAL_DRAFT = "待定幻化 · 尚未应用到装备",
    LOCAL_PRESET = "套装预设 · 尚未应用到装备",
    CONFIRM_CLEAR = "再点一次撤销按钮以清除全部待定",
    CONFIRM_SWITCH_EQUIPPED = "切换到当前装备会清除待定 · 再选一次确认",
    REQUESTING = "正在请求应用…",
    CONFIRMED = "已应用到装备",
    FAILED = "应用失败",
    OUTFIT_SAVED = "方案已保存",
    OUTFIT_LOADED = "已载入方案 · 点应用写入装备",
    OUTFIT_DELETED = "方案已删除",
}

local STATUS_REASON_TEXT = {
    CLASS_RESTRICTED = "当前装备与此外观不兼容",
    RACE_RESTRICTED = "当前种族不能使用此外观",
    SKILL_REQUIRED = "当前角色缺少使用此外观所需的技能",
    WEAPON_TYPE = "武器类型不兼容",
    ARMOR_TYPE = "护甲类型不兼容",
    INVALID_TARGET_SLOT = "该装备栏里没有装备物品。",
    UNKNOWN_IDENTITY = "未知外观，服务端已拒绝",
    NOT_OWNED = "此外观尚未收藏",
    COST_CHANGED = "费用已变化，请重新确认后再应用",
    INSUFFICIENT_FUNDS = "金币不足",
    NOTHING_EQUIPPED = "没有可写入的装备",
    UNSUPPORTED = "当前服务器不支持这项幻化",
    INVALID_REQUEST = "请求无效",
    REQUEST_NOT_SENT = "请求未能发出",
}

local function pendingApplyCount(state)
    if state.presetRecord then
        return state:GetDirtyCount(), "SET"
    end
    return #state:GetPendingApplySlots(), "SLOTS"
end

function Lab.CreatePage(parent)
    local page = CreateFrame("Frame", nil, parent)
    page:SetAllPoints(parent); page:Hide()
    local state = Lab.CreateState()
    page.scState = state
    Lab.CreateLayout(page, state)
    function page:Refresh()
        local request = state.requestState or {}
        local pendingCount = pendingApplyCount(state)
        local text = STATUS_TEXT[request.status] or STATUS_TEXT.IDLE
        if request.status == "REQUESTING" then
            if request.kind == "CLEAR" then
                text = "正在恢复原装备外观…"
            elseif request.kind == "SET" then
                text = "正在应用套装…"
            elseif request.queueTotal and request.queueTotal > 1 then
                text = string.format("正在应用 %d/%d 个部位…", request.queueIndex or 1, request.queueTotal)
            else
                text = "正在应用所选部位…"
            end
        elseif request.status == "CONFIRMED" and request.kind == "CLEAR" then
            text = "已恢复原装备外观"
        elseif request.status == "LOCAL_DRAFT" or request.status == "LOCAL_PRESET" then
            local canApply, reason, owned, required
            if state.presetRecord and state.GetSetApplyState then
                canApply, reason, owned, required = state:GetSetApplyState()
            elseif state.GetDraftApplyState then
                canApply, reason = state:GetDraftApplyState()
            end
            if not canApply and reason and reason ~= "NO_DRAFT" then
                text = Lab.ApplyReasonText and Lab.ApplyReasonText(reason, {
                    set = state.presetRecord ~= nil,
                    owned = owned or (state.presetRecord and state.presetRecord.collectedCount),
                    required = required or (state.presetRecord and state.presetRecord.requiredCount),
                }) or (STATUS_REASON_TEXT[reason] or text)
            elseif pendingCount > 0 then
                text = string.format("待定 %d 个部位 · 点应用写入装备", pendingCount)
            end
        elseif request.status == "FAILED" and request.reason then
            local reasonText = Lab.ApplyReasonText and Lab.ApplyReasonText(request.reason)
                or STATUS_REASON_TEXT[request.reason] or tostring(request.reason)
            text = text .. "：" .. reasonText
        end
        self.scStateText:SetText(text)
        self.scOutfits:Refresh()
        self.scSlots:Refresh()
        self.scSources:Refresh()
        self.scPreview:RefreshDraft()
        if self.scWeaponHandWarning and self.scWeaponHandWarning.SetActive then
            local slot = state.selectedSlot
            self.scWeaponHandWarning:SetActive(slot == "MAINHAND" or slot == "OFFHAND")
        end
        local copper = 0
        if state.GetApplyCost then
            copper = state:GetApplyCost() or 0
        end
        local canApply, applyReason = false, nil
        if state.presetRecord and state.GetSetApplyState then
            canApply, applyReason = state:GetSetApplyState()
        elseif state.GetDraftApplyState then
            canApply, applyReason = state:GetDraftApplyState()
        end
        if self.scMoneyFrame and Lab.UpdateQuotedMoney then
            local color = applyReason == "INSUFFICIENT_FUNDS" and "red" or "white"
            Lab.UpdateQuotedMoney(self.scMoneyFrame, copper, color)
        elseif self.scMoneyText then
            self.scMoneyText:SetText(tostring(copper))
        end
        local canClickApply = request.status ~= "REQUESTING" and canApply
        local apply = self.scApplyButton or self.scApplySlot
        if apply then
            if canClickApply then apply:Enable() else apply:Disable() end
            if self.scApplyDisabledTip then
                if canClickApply then self.scApplyDisabledTip:Hide() else self.scApplyDisabledTip:Show() end
            end
        end
        if self.scMultiSaveButton then
            if state:HasDraft() and request.status ~= "REQUESTING" then
                self.scMultiSaveButton:Enable()
            else
                self.scMultiSaveButton:Disable()
            end
        end
        self:SyncFilters()
    end
    local function warmupTicks()
        local entered = SC.ModelProvider and SC.ModelProvider.playerEnteredAt
        if entered and GetTime and (GetTime() - entered) < 8 then
            return 6
        end
        return 2
    end
    local function scheduleRefresh(owner, ticks)
        ticks = tonumber(ticks) or warmupTicks()
        if owner.scRefreshDelay then
            owner.scRefreshDelay = math.max(owner.scRefreshDelay, ticks)
            return
        end
        owner.scRefreshDelay = ticks
        if owner:GetScript("OnUpdate") then return end
        owner:SetScript("OnUpdate", function(self)
            if not self.scRefreshDelay then
                self:SetScript("OnUpdate", nil)
                return
            end
            self.scRefreshDelay = self.scRefreshDelay - 1
            if self.scRefreshDelay > 0 then return end
            self.scRefreshDelay = nil
            self:SetScript("OnUpdate", nil)
            if self:IsShown() then self:Refresh() end
        end)
    end
    if SC.Bridge and SC.Bridge.RegisterStateListener then
        page.scAppliedListener = SC.Bridge.RegisterStateListener(function(_, typeId)
            if tonumber(typeId) ~= 18 then return end
            if page:IsShown() then
                scheduleRefresh(page, 3)
            end
        end)
    end
    state:Subscribe(page, function(owner, _, reason)
        if not owner:IsShown() then return end
        if reason == "SELECT_SLOT" and owner.scSources and owner.scSources.mode ~= "ITEMS" then
            owner.scSources:SetMode("ITEMS")
            owner:Refresh()
            return
        end
        if reason == "AUTHORITATIVE_REFRESH" or reason == "REQUEST_RESULT" then
            scheduleRefresh(owner, 3)
            return
        end
        if owner.scRefreshDelay then return end
        owner:Refresh()
    end)
    page:RegisterEvent("PLAYER_ENTERING_WORLD")
    page:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")
    page:RegisterEvent("PLAYER_MONEY")
    page:SetScript("OnEvent", function(self, event)
        if event == "PLAYER_ENTERING_WORLD" and SC.ModelProvider then
            SC.ModelProvider.playerEnteredAt = GetTime and GetTime() or 0
        end
        if event == "PLAYER_MONEY" then
            if self:IsShown() then scheduleRefresh(self, 1) end
            return
        end
        state:CaptureEquipped()
        if event == "PLAYER_EQUIPMENT_CHANGED" and state.EnsureSelectedSlotCanTransmog then
            state:EnsureSelectedSlotCanTransmog()
        end
        if self:IsShown() then
            scheduleRefresh(self, event == "PLAYER_ENTERING_WORLD" and warmupTicks() or 3)
        end
    end)
    page:SetScript("OnShow", function(self)
        state:CaptureEquipped()
        if state.EnsureSelectedSlotCanTransmog then
            state:EnsureSelectedSlotCanTransmog()
        end
        if state.RequestQuote then state:RequestQuote() end
        scheduleRefresh(self)
    end)
    page:SetScript("OnHide", function(self)
        state:MarkClosed()
        if self.scPreview and Lab.StopDressUp then Lab.StopDressUp(self.scPreview) end
        if self.scSources and self.scSources.ClearPresenters then self.scSources:ClearPresenters("PAGE_HIDDEN") end
    end)
    function page:SyncFilters()
        local mode = self.scSources and self.scSources.mode or "ITEMS"
        if UI.SyncTransmogFilterChrome then
            UI.SyncTransmogFilterChrome(mode)
        end
    end
    return page
end
