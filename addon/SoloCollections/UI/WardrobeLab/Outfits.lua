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
        if not box then return end
        if Lab.pendingOutfitMode == "rename" and Lab.pendingOutfitState then
            local current
            for _, outfit in ipairs(Lab.GetStoredOutfits()) do
                if outfit.uid == Lab.pendingOutfitState.activeOutfitUid then
                    current = outfit.name
                    break
                end
            end
            if current then box:SetText(current) end
        end
        box:SetFocus()
        box:HighlightText()
    end,
    OnAccept = function(dialog)
        local box = dialog.editBox or _G[dialog:GetName() .. "EditBox"]
        local name = box and box:GetText() or ""
        local state = Lab.pendingOutfitState
        if not state then return end
        if Lab.pendingOutfitMode == "rename" then
            state:RenameOutfit(state.activeOutfitUid, name)
        else
            state:SaveOutfit(name)
        end
        Lab.pendingOutfitMode = nil
    end,
    EditBoxOnEnterPressed = function(editBox)
        local dialog = editBox:GetParent()
        local name = editBox:GetText() or ""
        local state = Lab.pendingOutfitState
        if state then
            if Lab.pendingOutfitMode == "rename" then
                state:RenameOutfit(state.activeOutfitUid, name)
            else
                state:SaveOutfit(name)
            end
        end
        Lab.pendingOutfitMode = nil
        dialog:Hide()
    end,
    EditBoxOnEscapePressed = function(editBox)
        editBox:GetParent():Hide()
    end,
}

StaticPopupDialogs["SOLOCOLLECTIONS_TRANSMOG_CONFIRM"] = {
    text = "%s",
    button1 = "确定",
    button2 = "取消",
    timeout = 0,
    whileDead = 1,
    hideOnEscape = 1,
    showAlert = 1,
    OnAccept = function()
        local fn = Lab.pendingPopupAccept
        Lab.pendingPopupAccept = nil
        if type(fn) == "function" then fn() end
    end,
    OnCancel = function()
        Lab.pendingPopupAccept = nil
    end,
}

StaticPopupDialogs["SOLOCOLLECTIONS_TRANSMOG_APPLY"] = {
    text = "%s",
    button1 = "应用",
    button2 = "取消",
    hasMoneyFrame = 1,
    showAlert = 1,
    timeout = 0,
    whileDead = 1,
    hideOnEscape = 1,
    OnShow = function(self)
        local copper = 0
        if type(self.data) == "number" then
            copper = self.data
        end
        local frameName = self:GetName() .. "MoneyFrame"
        if MoneyFrame_Update then
            MoneyFrame_Update(frameName, copper)
        end
    end,
    OnAccept = function()
        local fn = Lab.pendingPopupAccept
        Lab.pendingPopupAccept = nil
        if type(fn) == "function" then fn() end
    end,
    OnCancel = function()
        Lab.pendingPopupAccept = nil
    end,
}

StaticPopupDialogs["SOLOCOLLECTIONS_TRANSMOG_NOTICE"] = {
    text = "%s",
    button1 = "确定",
    timeout = 0,
    whileDead = 1,
    hideOnEscape = 1,
    showAlert = 1,
    OnAccept = function()
        local fn = Lab.pendingPopupAccept
        Lab.pendingPopupAccept = nil
        if type(fn) == "function" then fn() end
    end,
}
end

local function promptSave(state, mode)
    Lab.pendingOutfitState = state
    Lab.pendingOutfitMode = mode or "save"
    if StaticPopupDialogs and StaticPopupDialogs["SOLOCOLLECTIONS_SAVE_TRANSMOG_OUTFIT"] then
        if mode == "rename" then
            StaticPopupDialogs["SOLOCOLLECTIONS_SAVE_TRANSMOG_OUTFIT"].text = "输入新的方案名称："
        else
            StaticPopupDialogs["SOLOCOLLECTIONS_SAVE_TRANSMOG_OUTFIT"].text = "输入幻化方案名称："
        end
    end
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

    local function applyEquipped()
        state:ClearDraft()
        state.activeOutfitUid = nil
        state:CaptureEquipped()
        state:Notify("EQUIPPED_REFRESH")
    end

    local function chooseEquipped()
        if state:HasDraft() then
            Lab.Confirm("切换到当前装备会清除未应用的待定幻化。", applyEquipped)
        else
            applyEquipped()
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
            info.func = function()
                local selected = outfit
                if state:HasDraft() then
                    Lab.Confirm("载入方案会替换当前未应用的待定幻化。", function()
                        state:LoadOutfit(selected)
                    end)
                else
                    state:LoadOutfit(selected)
                end
            end
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
            local overwriteInfo = UIDropDownMenu_CreateInfo()
            overwriteInfo.text = "覆盖当前方案"
            overwriteInfo.notCheckable = true
            overwriteInfo.disabled = not state:HasDraft()
            overwriteInfo.func = function()
                local uid = state.activeOutfitUid
                local name = UIDropDownMenu_GetText and UIDropDownMenu_GetText(dropdown) or "当前方案"
                Lab.Confirm("用当前待定外观覆盖方案「" .. tostring(name) .. "」？", function()
                    state:OverwriteOutfit(uid)
                end)
            end
            UIDropDownMenu_AddButton(overwriteInfo)

            local renameInfo = UIDropDownMenu_CreateInfo()
            renameInfo.text = "重命名当前方案…"
            renameInfo.notCheckable = true
            renameInfo.func = function() promptSave(state, "rename") end
            UIDropDownMenu_AddButton(renameInfo)

            local deleteInfo = UIDropDownMenu_CreateInfo()
            deleteInfo.text = "删除当前方案"
            deleteInfo.notCheckable = true
            deleteInfo.func = function()
                local uid = state.activeOutfitUid
                local name = UIDropDownMenu_GetText and UIDropDownMenu_GetText(dropdown) or "当前方案"
                Lab.Confirm("删除方案「" .. tostring(name) .. "」？此操作不能撤销。", function()
                    state:DeleteOutfit(uid)
                end)
            end
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
        Lab.Confirm("清除全部待定幻化？不会改动已经应用到装备的外观。", function()
            state:ClearDraft()
            state.activeOutfitUid = nil
            if Lab.PlaySound then Lab.PlaySound("revert") end
        end)
    end)
    clear:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText("撤销所有待定幻化", 1, 0.82, 0.18)
        GameTooltip:AddLine("点击后会弹出确认，不会立即清除。", 0.72, 0.72, 0.72, true)
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
