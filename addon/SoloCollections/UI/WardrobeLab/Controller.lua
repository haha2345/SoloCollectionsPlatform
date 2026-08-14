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
    REQUESTING = "正在请求应用…",
    WAITING_STATE = "服务端已接受 · 等待 SC2 权威状态刷新",
    CONFIRMED = "SC2 权威状态已刷新", FAILED = "应用失败",
}

function Lab.CreatePage(parent)
    local page = CreateFrame("Frame", nil, parent)
    page:SetAllPoints(parent); page:Hide()
    local state = Lab.CreateState()
    page.scState = state
    Lab.CreateLayout(page, state)
    function page:Refresh()
        state:ObserveAuthoritativeState()
        local request = state.requestState or {}
        local text = STATUS_TEXT[request.status] or STATUS_TEXT.IDLE
        if request.status == "REQUESTING" then
            text = request.kind == "SET" and "正在请求应用套装预设…" or "正在请求应用所选槽位…"
        end
        if request.status == "FAILED" and request.reason then text = text .. "：" .. tostring(request.reason) end
        self.scStateText:SetText(text)
        self.scOutfits:Refresh()
        self.scSlots:Refresh()
        self.scSources:Refresh()
        self.scPreview:RefreshDraft()
        local record = state.draftBySlot[state.selectedSlot]
        if record and record.collected and not state.presetRecord
            and request.status ~= "REQUESTING" and request.status ~= "WAITING_STATE" then
            self.scApplySlot:Enable()
        else self.scApplySlot:Disable() end
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
    return page
end
