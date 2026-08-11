local SC = SoloCollections

SC.WardrobeLab = SC.WardrobeLab or {}
local Lab = SC.WardrobeLab

function Lab.IsEnabled()
    return SC.db and SC.db.experimental and SC.db.experimental.transmogLabEnabled == true
end

local STATUS_TEXT = {
    IDLE = "仅本地预览 · 尚未应用", LOCAL_DRAFT = "本地草稿 · 尚未应用",
    CONFIRM_CLEAR = "存在未保存草稿 · 再点一次“清除草稿”确认",
    CONFIRM_SWITCH_EQUIPPED = "切换到当前装备会清除草稿 · 再点一次确认",
    REQUESTING = "正在请求应用所选槽位…",
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
        if request.status == "FAILED" and request.reason then text = text .. "：" .. tostring(request.reason) end
        self.scStateText:SetText(text)
        self.scCapabilityText:SetText(
            "候选来自 SoloCollections Catalog；点击只写本地草稿。单槽应用复用 SC2，整套保存等待服务端原子方案。"
        )
        self.scOutfits:Refresh(); self.scSlots:Refresh(); self.scSources:Refresh(); self.scPreview:RefreshDraft()
        local record = state.draftBySlot[state.selectedSlot]
        if record and record.collected and request.status ~= "REQUESTING" and request.status ~= "WAITING_STATE" then
            self.scApplySlot:Enable()
        else self.scApplySlot:Disable() end
    end
    state:Subscribe(page, function(owner) if owner:IsShown() then owner:Refresh() end end)
    page:SetScript("OnShow", function(self) self:Refresh() end)
    page:SetScript("OnHide", function(self)
        state:MarkClosed()
        if self.scPreview and self.scPreview.scPresenter then self.scPreview.scPresenter:Clear("PAGE_HIDDEN") end
    end)
    return page
end
