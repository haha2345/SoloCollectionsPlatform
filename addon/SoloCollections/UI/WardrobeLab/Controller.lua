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
        local pendingCount, pendingKind = pendingApplyCount(state)
        local text = STATUS_TEXT[request.status] or STATUS_TEXT.IDLE
        if request.status == "REQUESTING" then
            if request.kind == "SET" then
                text = "正在应用套装…"
            elseif request.queueTotal and request.queueTotal > 1 then
                text = string.format("正在应用 %d/%d 个部位…", request.queueIndex or 1, request.queueTotal)
            else
                text = "正在应用所选部位…"
            end
        elseif request.status == "LOCAL_DRAFT" and state.HasOnlyHideVisualDrafts
            and state:HasOnlyHideVisualDrafts() then
            text = "隐藏外观仅本地预览 · 当前不能应用到装备"
        elseif request.status == "LOCAL_DRAFT" and pendingCount > 0 then
            text = string.format("待定 %d 个部位 · 点应用写入装备", pendingCount)
        elseif request.status == "FAILED" and request.reason then
            text = text .. "：" .. tostring(request.reason)
        end
        self.scStateText:SetText(text)
        self.scOutfits:Refresh()
        self.scSlots:Refresh()
        self.scSources:Refresh()
        self.scPreview:RefreshDraft()
        local canApply = pendingCount > 0 and request.status ~= "REQUESTING"
        if pendingKind == "SET" then
            canApply = state.presetRecord and state.presetRecord.collected and request.status ~= "REQUESTING"
        end
        local apply = self.scApplyButton or self.scApplySlot
        if apply then
            if canApply then apply:Enable() else apply:Disable() end
            if self.scApplyDisabledTip then
                if canApply then self.scApplyDisabledTip:Hide() else self.scApplyDisabledTip:Show() end
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
    state:Subscribe(page, function(owner, _, reason)
        if not owner:IsShown() then return end
        if reason == "SELECT_SLOT" and owner.scSources and owner.scSources.mode ~= "ITEMS" then
            owner.scSources:SetMode("ITEMS")
            owner:Refresh()
            return
        end
        owner:Refresh()
    end)
    page:RegisterEvent("PLAYER_ENTERING_WORLD")
    page:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")
    page:SetScript("OnEvent", function(self)
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
        local mode = self.scSources and self.scSources.mode or "ITEMS"
        if UI.SyncTransmogFilterChrome then
            UI.SyncTransmogFilterChrome(mode)
        end
    end
    return page
end
