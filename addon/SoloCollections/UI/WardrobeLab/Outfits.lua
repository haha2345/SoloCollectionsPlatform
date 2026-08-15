local SC = SoloCollections
local UI = SC.UI
local Lab = SC.WardrobeLab
if not Lab then return end

function Lab.CreateOutfits(parent, state)
    local host = CreateFrame("Frame", nil, parent)
    host:SetAllPoints(parent)
    host:SetFrameLevel(parent:GetFrameLevel() + 12)

    local dropdown = CreateFrame("Frame", "SoloCollectionsTransmogOutfitDropdown", host, "UIDropDownMenuTemplate")
    dropdown:SetPoint("TOPLEFT", parent, "TOPLEFT", -14, 28)
    dropdown:SetFrameLevel(host:GetFrameLevel() + 2)
    UIDropDownMenu_SetWidth(dropdown, 188)

    local save = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    save:SetWidth(88)
    save:SetHeight(22)
    save:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -35, -12)
    save:SetFrameLevel(host:GetFrameLevel() + 2)
    save:SetText("保存整套")
    save:Disable()
    save:Hide()

    local saveTip = CreateFrame("Frame", nil, save)
    saveTip:SetAllPoints(save)
    saveTip:SetFrameLevel(save:GetFrameLevel() + 1)
    saveTip:EnableMouse(true)
    saveTip:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText("保存整套（待原子协议）", 1, 0.82, 0.18)
        GameTooltip:AddLine("自定义整套保存尚未接入服务端原子协议；当前只能本地预览或逐槽应用草稿。", 0.92, 0.76, 0.42, true)
        GameTooltip:Show()
    end)
    saveTip:SetScript("OnLeave", function() GameTooltip:Hide() end)
    saveTip:Hide()

    local function chooseEquipped()
        if state:IsRequestPending() then
            state:Notify("REQUEST_PENDING_BLOCKED")
            return
        end
        if state:HasDraft() then
            if state.requestState.status == "CONFIRM_SWITCH_EQUIPPED" then
                state:ClearDraft(); state:CaptureEquipped(); state:Notify("EQUIPPED_REFRESH")
            else
                state.requestState = { status = "CONFIRM_SWITCH_EQUIPPED", revision = state.requestState.revision }
                state:Notify("CONFIRM_SWITCH_EQUIPPED")
            end
        else state:CaptureEquipped(); state:Notify("EQUIPPED_REFRESH") end
    end

    UIDropDownMenu_Initialize(dropdown, function()
        local equippedInfo = UIDropDownMenu_CreateInfo()
        equippedInfo.text = "当前装备"
        equippedInfo.checked = not state:HasDraft()
        equippedInfo.func = chooseEquipped
        UIDropDownMenu_AddButton(equippedInfo)

        local draftInfo = UIDropDownMenu_CreateInfo()
        if state.presetRecord then
            draftInfo.text = "套装预设：" .. tostring(state.presetRecord.name or state.presetRecord.id)
        else
            draftInfo.text = "本地草稿（" .. state:GetDirtyCount() .. " 槽）"
        end
        draftInfo.checked = state:HasDraft()
        draftInfo.disabled = not state:HasDraft()
        draftInfo.func = function() state:Notify("DRAFT_SELECTED") end
        UIDropDownMenu_AddButton(draftInfo)
    end)

    local clear = CreateFrame("Button", nil, parent)
    clear:SetWidth(26)
    clear:SetHeight(26)
    clear:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -5, -10)
    clear:SetFrameLevel(host:GetFrameLevel() + 2)
    local clearIcon = clear:CreateTexture(nil, "ARTWORK")
    clearIcon:SetWidth(25)
    clearIcon:SetHeight(24)
    clearIcon:SetPoint("LEFT", clear, "LEFT", 1, 0)
    clearIcon:SetTexture(UI.EzCollections:MediaPath("Transmogrify", "Transmogrify.tga", "Interface\\Buttons\\UI-RotationRight-Button-Up"))
    clearIcon:SetTexCoord(0.533203125, 0.58203125, 0.248046875, 0.294921875)
    clear:SetNormalTexture(clearIcon)
    clear:SetHighlightTexture("Interface\\Buttons\\UI-Common-MouseHilight")
    clear:SetScript("OnClick", function()
        if not state:HasDraft() then return end
        if state:IsRequestPending() then
            state:Notify("REQUEST_PENDING_BLOCKED")
            return
        end
        if state.requestState.status == "CONFIRM_CLEAR" then state:ClearDraft()
        else
            state.requestState = { status = "CONFIRM_CLEAR", revision = state.requestState.revision }
            state:Notify("CONFIRM_CLEAR")
        end
    end)
    clear:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText("清除所有本地草稿", 1, 0.82, 0.18)
        if state:IsRequestPending() then
            GameTooltip:AddLine("已有应用请求正在处理，暂不能清除。", 1, 0.76, 0.32, true)
        else
            GameTooltip:AddLine("首次点击进入确认状态，再点一次清除。", 0.72, 0.72, 0.72)
        end
        GameTooltip:Show()
    end)
    clear:SetScript("OnLeave", function() GameTooltip:Hide() end)

    function host:Refresh()
        local dirtyCount = state:GetDirtyCount()
        if state.presetRecord then
            UIDropDownMenu_SetText(dropdown, "套装预设：" .. tostring(state.presetRecord.name or state.presetRecord.id))
        elseif dirtyCount > 0 then
            UIDropDownMenu_SetText(dropdown, "本地草稿（" .. dirtyCount .. " 槽）")
        else
            UIDropDownMenu_SetText(dropdown, "当前装备")
        end
        if state:HasDraft() then clear:Show() else clear:Hide() end
    end
    host.scDropDown = dropdown
    host.scSaveButton = save
    host.scSaveTooltip = saveTip
    host.scClearButton = clear
    return host
end
