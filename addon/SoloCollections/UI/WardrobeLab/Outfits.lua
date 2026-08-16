local SC = SoloCollections
local UI = SC.UI
local Lab = SC.WardrobeLab
if not Lab then return end

if StaticPopupDialogs then
StaticPopupDialogs["SOLOCOLLECTIONS_SAVE_TRANSMOG_OUTFIT"] = {
    text = "输入幻化方案名称：",
    button1 = "保存",
    button2 = "取消",
    hasEditBox = 1,
    maxLetters = 16,
    timeout = 0,
    whileDead = 1,
    hideOnEscape = 1,
    OnShow = function(dialog)
        local box = dialog.editBox or _G[dialog:GetName() .. "EditBox"]
        if box then
            box:SetFocus()
            box:HighlightText()
        end
    end,
    OnAccept = function(dialog)
        local box = dialog.editBox or _G[dialog:GetName() .. "EditBox"]
        local name = box and box:GetText() or ""
        local state = Lab.pendingOutfitState
        if state then state:SaveOutfit(name) end
    end,
    EditBoxOnEnterPressed = function(editBox)
        local dialog = editBox:GetParent()
        local name = editBox:GetText() or ""
        local state = Lab.pendingOutfitState
        if state then state:SaveOutfit(name) end
        dialog:Hide()
    end,
    EditBoxOnEscapePressed = function(editBox)
        editBox:GetParent():Hide()
    end,
}
end

local function promptSave(state)
    Lab.pendingOutfitState = state
    if StaticPopup_Show then
        StaticPopup_Show("SOLOCOLLECTIONS_SAVE_TRANSMOG_OUTFIT")
    end
end

function Lab.PromptSaveOutfit(state)
    promptSave(state)
end

function Lab.CreateOutfits(parent, state)
    local host = CreateFrame("Frame", nil, parent)
    host:SetAllPoints(parent)
    host:SetFrameLevel(parent:GetFrameLevel() + 12)

    local dropdown = CreateFrame("Frame", "SoloCollectionsTransmogOutfitDropdown", host, "UIDropDownMenuTemplate")
    dropdown:SetPoint("TOPLEFT", parent, "TOPLEFT", -14, 28)
    dropdown:SetFrameLevel(host:GetFrameLevel() + 2)
    UIDropDownMenu_SetWidth(dropdown, 188)

    local function chooseEquipped()
        if state:HasDraft() then
            if state.requestState.status == "CONFIRM_SWITCH_EQUIPPED" then
                state:ClearDraft()
                state.activeOutfitUid = nil
                state:CaptureEquipped()
                state:Notify("EQUIPPED_REFRESH")
            else
                state.requestState = { status = "CONFIRM_SWITCH_EQUIPPED", revision = state.requestState.revision }
                state:Notify("CONFIRM_SWITCH_EQUIPPED")
            end
        else
            state.activeOutfitUid = nil
            state:CaptureEquipped()
            state:Notify("EQUIPPED_REFRESH")
        end
    end

    UIDropDownMenu_Initialize(dropdown, function()
        local equippedInfo = UIDropDownMenu_CreateInfo()
        equippedInfo.text = "当前装备"
        equippedInfo.checked = not state:HasDraft() and not state.activeOutfitUid
        equippedInfo.func = chooseEquipped
        UIDropDownMenu_AddButton(equippedInfo)

        if state:HasDraft() then
            local draftInfo = UIDropDownMenu_CreateInfo()
            if state.presetRecord then
                draftInfo.text = "套装预设：" .. tostring(state.presetRecord.name or state.presetRecord.id)
            else
                draftInfo.text = "未保存方案（" .. state:GetDirtyCount() .. " 槽）"
            end
            draftInfo.checked = state:HasDraft() and not state.activeOutfitUid
            draftInfo.func = function() state:Notify("DRAFT_SELECTED") end
            UIDropDownMenu_AddButton(draftInfo)
        end

        local outfits = Lab.GetStoredOutfits()
        if #outfits > 0 then
            local spacer = UIDropDownMenu_CreateInfo()
            spacer.text = " "
            spacer.disabled = true
            spacer.notCheckable = true
            UIDropDownMenu_AddButton(spacer)
        end
        for _, outfit in ipairs(outfits) do
            local info = UIDropDownMenu_CreateInfo()
            info.text = outfit.name
            info.checked = state.activeOutfitUid == outfit.uid
            info.func = function() state:LoadOutfit(outfit) end
            UIDropDownMenu_AddButton(info)
        end

        local actions = UIDropDownMenu_CreateInfo()
        actions.text = " "
        actions.disabled = true
        actions.notCheckable = true
        UIDropDownMenu_AddButton(actions)

        local saveInfo = UIDropDownMenu_CreateInfo()
        saveInfo.text = "保存新方案…"
        saveInfo.notCheckable = true
        saveInfo.disabled = not state:HasDraft()
        saveInfo.func = function() promptSave(state) end
        UIDropDownMenu_AddButton(saveInfo)

        if state.activeOutfitUid then
            local deleteInfo = UIDropDownMenu_CreateInfo()
            deleteInfo.text = "删除当前方案"
            deleteInfo.notCheckable = true
            deleteInfo.func = function() state:DeleteOutfit(state.activeOutfitUid) end
            UIDropDownMenu_AddButton(deleteInfo)
        end
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
        if state.requestState.status == "CONFIRM_CLEAR" then
            state:ClearDraft()
            state.activeOutfitUid = nil
        else
            state.requestState = { status = "CONFIRM_CLEAR", revision = state.requestState.revision }
            state:Notify("CONFIRM_CLEAR")
        end
    end)
    clear:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText("撤销所有待定幻化", 1, 0.82, 0.18)
        GameTooltip:AddLine("与正式服幻化室相同：首次点击进入确认，再点一次清除。", 0.72, 0.72, 0.72, true)
        GameTooltip:Show()
    end)
    clear:SetScript("OnLeave", function() GameTooltip:Hide() end)

    function host:Refresh()
        local dirtyCount = state:GetDirtyCount()
        local activeName
        if state.activeOutfitUid then
            for _, outfit in ipairs(Lab.GetStoredOutfits()) do
                if outfit.uid == state.activeOutfitUid then
                    activeName = outfit.name
                    break
                end
            end
        end
        if activeName then
            UIDropDownMenu_SetText(dropdown, activeName)
        elseif state.presetRecord then
            UIDropDownMenu_SetText(dropdown, "套装预设：" .. tostring(state.presetRecord.name or state.presetRecord.id))
        elseif dirtyCount > 0 then
            UIDropDownMenu_SetText(dropdown, "未保存方案（" .. dirtyCount .. " 槽）")
        else
            UIDropDownMenu_SetText(dropdown, "当前装备")
        end
        if state:HasDraft() then clear:Show() else clear:Hide() end
    end
    host.scDropDown = dropdown
    host.scClearButton = clear
    host.PromptSave = function() promptSave(state) end
    return host
end
