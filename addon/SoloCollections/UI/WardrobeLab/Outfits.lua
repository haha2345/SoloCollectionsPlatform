local SC = SoloCollections
local UI = SC.UI
local Lab = SC.WardrobeLab
if not Lab then return end

function Lab.CreateOutfits(parent, state)
    local host = CreateFrame("Frame", nil, parent)
    host:SetPoint("TOPLEFT", parent, "TOPLEFT", 12, -46)
    host:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", -12, 56)
    local equipped = UI.CreateListRow(host, 160, 46, function()
        if state:HasDraft() then
            if state.requestState.status == "CONFIRM_SWITCH_EQUIPPED" then
                state:ClearDraft(); state:CaptureEquipped(); state:Notify("EQUIPPED_REFRESH")
            else
                state.requestState = { status = "CONFIRM_SWITCH_EQUIPPED", revision = state.requestState.revision }
                state:Notify("CONFIRM_SWITCH_EQUIPPED")
            end
        else state:CaptureEquipped(); state:Notify("EQUIPPED_REFRESH") end
    end)
    equipped:SetPoint("TOPLEFT", host, "TOPLEFT", 0, 0)
    equipped:SetRecord({ id = -1, name = "当前装备", source = "本地读取", collected = true })
    local draft = UI.CreateListRow(host, 160, 46, function() state:Notify("DRAFT_SELECTED") end)
    draft:SetPoint("TOPLEFT", equipped, "BOTTOMLEFT", 0, -6)
    local clear = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    clear:SetWidth(148); clear:SetHeight(25); clear:SetPoint("BOTTOM", parent, "BOTTOM", 0, 17)
    clear:SetText("清除草稿")
    clear:SetScript("OnClick", function()
        if not state:HasDraft() then return end
        if state.requestState.status == "CONFIRM_CLEAR" then state:ClearDraft()
        else
            state.requestState = { status = "CONFIRM_CLEAR", revision = state.requestState.revision }
            state:Notify("CONFIRM_CLEAR")
        end
    end)
    local public = SC.UIPlatform and SC.UIPlatform:GetPublic()
    if public then public.Components:SkinButton(clear) end
    function host:Refresh()
        local dirtyCount = state:GetDirtyCount()
        draft:SetRecord({ id = -2,
            name = dirtyCount > 0 and ("当前草稿（" .. dirtyCount .. " 槽）") or "当前草稿（空）",
            source = state.preservedOnClose and "关闭时已保留" or "仅本地", collected = dirtyCount > 0 })
        equipped:SetSelected(dirtyCount == 0); draft:SetSelected(dirtyCount > 0)
        if dirtyCount > 0 then clear:Enable() else clear:Disable() end
    end
    return host
end
