local SC = SoloCollections
local UI = SC.UI
local Lab = SC.WardrobeLab
if not Lab then return end

local DESIGN_SCREEN_WIDTH = 1920
local DESIGN_SCREEN_HEIGHT = 1080
local TRANSMOG_WIDTH = 965
local TRANSMOG_HEIGHT = 606
local MIN_SCALE = 0.72

local function getResponsiveScale()
    local widthScale = UIParent:GetWidth() / DESIGN_SCREEN_WIDTH
    local heightScale = UIParent:GetHeight() / DESIGN_SCREEN_HEIGHT
    return math.max(MIN_SCALE, math.min(1, widthScale, heightScale))
end

local function clampFrame(frame)
    frame:SetScale(getResponsiveScale())
    frame:SetClampRectInsets(0, 0, 0, 0)
    frame:SetClampedToScreen(false)
    frame:SetClampedToScreen(true)
end

local function saveFramePosition(frame)
    if SC.UIPlatform and SC.UIPlatform:IsDragonUIShell() then return end
    if not SC.db then return end
    local point, _, relativePoint, x, y = frame:GetPoint(1)
    SC.db.transmogFrame = {
        point = point or "CENTER",
        relativePoint = relativePoint or "CENTER",
        x = math.floor((x or 0) + 0.5),
        y = math.floor((y or 0) + 0.5),
    }
end

local function restoreFramePosition(frame)
    if SC.UIPlatform and SC.UIPlatform:IsDragonUIShell() then
        SC.UIPlatform:RestoreTransmogWindow(frame)
        clampFrame(frame)
        return
    end
    local saved = SC.db and SC.db.transmogFrame
    frame:ClearAllPoints()
    frame:SetPoint(
        (saved and saved.point) or "CENTER",
        UIParent,
        (saved and saved.relativePoint) or "CENTER",
        (saved and saved.x) or 0,
        (saved and saved.y) or 0
    )
    clampFrame(frame)
end

local function refreshTransmogPage()
    local frame = UI.TransmogFrame
    if frame and frame.scPage and frame.scPage.Refresh then
        frame.scPage:Refresh()
    end
end

local function transmogPortraitPath()
    if UI.EzCollections and UI.EzCollections.AssetPath then
        local path = UI.EzCollections:AssetPath("Textures\\UI-MicroButton-Transmogrify-Up.tga")
        if path then return path end
    end
    if SC.RetailUI and type(SC.RetailUI.GetWardrobePortraitPath) == "function" then
        local path = SC.RetailUI.GetWardrobePortraitPath()
        if path then return path end
    end
    return "Interface\\Icons\\INV_Chest_Cloth_17"
end

function UI.CreateTransmogFrame()
    if UI.TransmogFrame then
        return UI.TransmogFrame
    end
    if not (Lab and Lab.CreatePage) then return nil end
    if SC.UIPlatform and not SC.UIPlatform:CanCreateUI() then return nil end

    local frame = UI.CreateJournalFrame(
        UIParent,
        "SoloCollectionsWardrobeFrame",
        TRANSMOG_WIDTH,
        TRANSMOG_HEIGHT,
        { title = "幻化", portrait = transmogPortraitPath() }
    )
    local dragonShell = UI.IsDragonUIShell and UI.IsDragonUIShell()
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetClampedToScreen(true)
    frame:Hide()

    if frame.Title then
        frame.Title:SetText("幻化")
        frame.Title:SetTextColor(1, 0.82, 0.18)
    end

    if not dragonShell then
        frame:SetScript("OnDragStart", function(self)
            self:StartMoving()
        end)
        frame:SetScript("OnDragStop", function(self)
            self:StopMovingOrSizing()
            clampFrame(self)
            saveFramePosition(self)
        end)
    end
    frame:SetScript("OnShow", function(self)
        if UI.ApplyTransmogOpenFilters then
            local changed = UI.ApplyTransmogOpenFilters()
            if changed and self.scPage and self.scPage.scSources then
                self.scPage.scSources.itemPage = 1
                self.scPage.scSources.setPage = 1
            end
        end
        clampFrame(self)
        if self.scSearchBox and SC.db then
            self.scSearchBox:SetText(SC.db.query or "")
        end
        if self.scPage then
            self.scPage:Show()
            if self.scPage.Refresh then self.scPage:Refresh() end
        end
        if UI.BindTransmogKeys then UI.BindTransmogKeys(self) end
        if Lab.PlaySound then Lab.PlaySound("open") end
    end)
    frame:SetScript("OnHide", function(self)
        if UI.ClearTransmogKeys then UI.ClearTransmogKeys(self) end
        if self.scFilterPopup then self.scFilterPopup:Hide() end
        if CloseDropDownMenus then CloseDropDownMenus() end
        if Lab.HideDialogs then Lab.HideDialogs() end
        if Lab.PlaySound then Lab.PlaySound("close") end
    end)

    if dragonShell and SC.UIPlatform then
        SC.UIPlatform:PersistTransmogWindow(frame, frame)
    end

    local closeButton = dragonShell and frame.CloseButton or CreateFrame("Button", nil, frame, "UIPanelCloseButton")
    if not dragonShell then closeButton:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -10, -9) end
    closeButton:SetScript("OnClick", function() frame:Hide() end)

    local pageTitle = dragonShell and frame.Title or frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    if not dragonShell then
        pageTitle:SetPoint("TOP", frame, "TOP", 0, -17)
        pageTitle:SetText("幻化")
        pageTitle:SetTextColor(1, 0.82, 0.18)
    end

    local portraitFrame
    local portrait
    local portraitRing
    local portraitTexture = transmogPortraitPath()
    if dragonShell and frame.portrait then
        portraitFrame = frame
        portrait = frame.portrait
        portraitRing = frame.portraitRing or frame.PortraitFrame
    else
        portraitFrame = CreateFrame("Frame", nil, frame)
        portraitFrame:SetWidth(80)
        portraitFrame:SetHeight(80)
        portraitFrame:SetPoint("TOPLEFT", frame, "TOPLEFT", -7, 5)
        portraitFrame:SetFrameLevel(frame:GetFrameLevel() + 4)
        portrait = portraitFrame:CreateTexture(nil, "ARTWORK")
        portrait:SetWidth(62)
        portrait:SetHeight(62)
        portrait:SetPoint("CENTER", portraitFrame, "CENTER", 0, 0)
        portraitRing = portraitFrame:CreateTexture(nil, "OVERLAY")
        portraitRing:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
        portraitRing:SetWidth(80)
        portraitRing:SetHeight(80)
        portraitRing:SetPoint("CENTER", portraitFrame, "CENTER", 0, 0)
        portraitRing:SetTexCoord(0, 0.625, 0, 0.625)
    end
    frame.scPortrait = portrait
    if UI.EzCollections and UI.EzCollections.SetPortraitForTab then
        UI.EzCollections:SetPortraitForTab(frame, "WARDROBE")
    elseif SetPortraitToTexture then
        SetPortraitToTexture(portrait, portraitTexture)
    else
        portrait:SetTexture(portraitTexture)
        portrait:SetTexCoord(0, 1, 0, 1)
    end

    local portraitButton = CreateFrame("Button", nil, frame)
    portraitButton:SetWidth(60)
    portraitButton:SetHeight(60)
    portraitButton:SetPoint("TOPLEFT", frame, "TOPLEFT", -5, 8)
    portraitButton:SetFrameLevel(frame:GetFrameLevel() + 24)
    portraitButton:RegisterForClicks("LeftButtonUp")
    portraitButton:SetScript("OnClick", function()
        UI.HideTransmog()
        if UI.ShowJournal then UI.ShowJournal() end
    end)
    portraitButton:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText("收藏", 1, 0.82, 0.18)
        GameTooltip:AddLine("打开收藏手册。", 0.72, 0.72, 0.72)
        GameTooltip:Show()
    end)
    portraitButton:SetScript("OnLeave", function() GameTooltip:Hide() end)

    local progress = UI.CreateRetailProgressBar(frame, 194)
    progress:SetWidth(210)
    progress:SetHeight(20)
    progress:SetPoint("TOP", frame, "TOP", 0, -35)
    progress:SetFrameLevel(frame:GetFrameLevel() + 40)
    progress.scStatusBar:SetWidth(194)
    progress.scStatusBar:SetHeight(10)
    progress.scBorder:Hide()
    UI.EzCollections:ApplyInputBorder(progress)

    local searchFilterHost = CreateFrame("Frame", nil, frame)
    searchFilterHost:SetWidth(210)
    searchFilterHost:SetHeight(22)
    searchFilterHost:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -12, -34)
    searchFilterHost:SetFrameLevel(frame:GetFrameLevel() + 30)

    local search = UI.CreateRetailSearchBox(searchFilterHost, 115, function(value)
        if SC.db then
            SC.db.query = value or ""
        end
        refreshTransmogPage()
    end)
    search:SetPoint("LEFT", searchFilterHost, "LEFT", 0, -1)
    UI.EzCollections:SkinSearchBox(search)
    search:SetScript("OnEditFocusGained", function()
        if UI.ClearTransmogKeys then UI.ClearTransmogKeys(frame) end
    end)
    search:SetScript("OnEditFocusLost", function()
        if frame:IsShown() and UI.BindTransmogKeys then
            UI.BindTransmogKeys(frame)
        end
    end)

    local filterButton, filterPopup = UI.CreateFilterPopup(searchFilterHost, 93)
    filterButton:SetHeight(22)
    filterButton:SetPoint("LEFT", search, "RIGHT", 2, -1)
    if filterButton.scLabel then
        filterButton.scLabel:SetText("来源")
    end
    if filterButton.scArrow then
        filterButton.scArrow:SetTexCoord(0, 1, 0, 1)
    end
    UI.EzCollections:SkinSilverMenuButton(filterButton)

    local transmogFilterDropDown = CreateFrame(
        "Frame",
        "SoloCollectionsTransmogFilterDropDown",
        searchFilterHost,
        "UIDropDownMenuTemplate"
    )
    transmogFilterDropDown:Hide()
    filterButton:SetWardrobeDropDown(transmogFilterDropDown)
    if UIDropDownMenu_Initialize then
        UIDropDownMenu_Initialize(transmogFilterDropDown, function(_, level)
            if level ~= 1 then return end
            UI.AddCollectedStateMenuButtons(level, refreshTransmogPage)
            local sources = UI.TransmogFrame and UI.TransmogFrame.scPage and UI.TransmogFrame.scPage.scSources
            if not (sources and sources.mode == "SETS") then
                UI.AddAppearanceSourceMenuButtons(level, refreshTransmogPage)
            end
        end, "MENU")
        transmogFilterDropDown.scSoloCollectionsInitialized = true
    end

    local page = Lab.CreatePage(frame)
    page:SetAllPoints(frame)

    local right = page.scPanels and page.scPanels.right
    local itemTab = page.scSources and page.scSources.scItemTab
    if right and itemTab then
        -- ez 2.2: progress is TOPLEFT of ItemsTab (195, -11), not above the
        -- collection frame. Search/filter live on the 662 CollectionFrame.
        progress:ClearAllPoints()
        progress:SetPoint("TOPLEFT", itemTab, "TOPLEFT", 195, -11)
        progress:SetFrameLevel(frame:GetFrameLevel() + 40)
        searchFilterHost:SetParent(right)
        searchFilterHost:ClearAllPoints()
        searchFilterHost:SetWidth(210)
        searchFilterHost:SetHeight(22)
        searchFilterHost:SetPoint("TOPRIGHT", right, "TOPRIGHT", -12, -34)
        searchFilterHost:EnableMouse(true)
        searchFilterHost:SetFrameLevel(right:GetFrameLevel() + 30)
        search:ClearAllPoints()
        search:SetPoint("LEFT", searchFilterHost, "LEFT", 0, -1)
        filterButton:ClearAllPoints()
        filterButton:SetPoint("LEFT", search, "RIGHT", 2, -1)
    end

    frame.scTitle = pageTitle
    frame.scPageTitle = pageTitle
    frame.scPortraitFrame = portraitFrame
    frame.scPortrait = portrait
    frame.scPortraitRing = portraitRing
    frame.scPortraitButton = portraitButton
    frame.scCloseButton = closeButton
    frame.scProgress = progress
    frame.scSearchFilterHost = searchFilterHost
    frame.scSearchBox = search
    frame.scFilterButton = filterButton
    frame.scFilterPopup = filterPopup
    frame.scWardrobeFilterDropDown = transmogFilterDropDown
    frame.scPage = page

    local itemsView = page.scSources and page.scSources.scItemsView
    if itemsView and UIDropDownMenu_Initialize then
        local weaponDropDown = CreateFrame(
            "Frame",
            "SoloCollectionsTransmogWeaponDropDown",
            itemsView,
            "UIDropDownMenuTemplate"
        )
        weaponDropDown:SetPoint("TOPRIGHT", itemsView, "TOPRIGHT", -32, -25)
        weaponDropDown:SetFrameLevel(itemsView:GetFrameLevel() + 10)
        if UIDropDownMenu_SetWidth then
            UIDropDownMenu_SetWidth(weaponDropDown, 140)
        end
        weaponDropDown:Hide()
        UIDropDownMenu_Initialize(weaponDropDown, function()
            local slot = page.scState and page.scState.selectedSlot
            if not (slot and SC.db and SC.db.filters and SC.Catalog) then return end
            for _, option in ipairs(SC.Catalog.GetAvailableWeaponFilters(slot)) do
                local weaponOption = option
                local info = UIDropDownMenu_CreateInfo()
                info.text = weaponOption.label
                info.value = weaponOption.key
                info.checked = SC.db.filters.weaponType == weaponOption.key
                info.func = function()
                    SC.db.filters.weaponType = weaponOption.key
                    if page.scSources then page.scSources.itemPage = 1 end
                    refreshTransmogPage()
                end
                UIDropDownMenu_AddButton(info)
            end
        end)
        frame.scWeaponDropDown = weaponDropDown

        local armorDropDown = CreateFrame(
            "Frame",
            "SoloCollectionsTransmogArmorDropDown",
            itemsView,
            "UIDropDownMenuTemplate"
        )
        armorDropDown:SetPoint("TOPRIGHT", itemsView, "TOPRIGHT", -32, -25)
        armorDropDown:SetFrameLevel(itemsView:GetFrameLevel() + 10)
        if UIDropDownMenu_SetWidth then
            UIDropDownMenu_SetWidth(armorDropDown, 140)
        end
        armorDropDown:Hide()
        UIDropDownMenu_Initialize(armorDropDown, function()
            if not (SC.db and SC.db.filters) then return end
            local options = UI.GetTransmogArmorFilterOptions and UI.GetTransmogArmorFilterOptions() or {}
            for _, option in ipairs(options) do
                local armorOption = option
                local info = UIDropDownMenu_CreateInfo()
                info.text = armorOption.label
                info.value = armorOption.key
                info.checked = SC.db.filters.armorType == armorOption.key
                    or (armorOption.key ~= "ALL" and SC.db.filters.armorType == "AUTO"
                        and SC.Catalog and SC.Catalog.ResolveArmorTypeForQuery
                        and SC.Catalog.ResolveArmorTypeForQuery(SC.db.filters) == armorOption.key)
                info.func = function()
                    SC.db.filters.armorType = armorOption.key
                    if page.scSources then page.scSources.itemPage = 1 end
                    refreshTransmogPage()
                end
                UIDropDownMenu_AddButton(info)
            end
        end)
        frame.scArmorDropDown = armorDropDown
    end

    frame.scKeyButtons = {}
    local visualKeys = { "LEFT", "RIGHT", "UP", "DOWN", "PAGEUP", "PAGEDOWN" }
    for _, key in ipairs(visualKeys) do
        local button = CreateFrame("Button", "SoloCollectionsWardrobeKey" .. key, frame)
        button.scKey = key
        button:SetScript("OnClick", function(self)
            if not frame:IsShown() then return end
            if frame.scSearchBox and frame.scSearchBox.HasFocus and frame.scSearchBox:HasFocus() then
                return
            end
            local sources = frame.scPage and frame.scPage.scSources
            if sources and sources.HandleVisualKey then
                sources:HandleVisualKey(self.scKey)
            end
        end)
        frame.scKeyButtons[key] = button
    end
    local escapeButton = CreateFrame("Button", "SoloCollectionsWardrobeKeyESCAPE", frame)
    escapeButton:SetScript("OnClick", function()
        frame:Hide()
    end)
    frame.scEscapeButton = escapeButton

    local setsView = page.scSources and page.scSources.scSetsView
    if setsView and UIDropDownMenu_Initialize then
        local classDropDown = CreateFrame(
            "Frame",
            "SoloCollectionsTransmogClassDropDown",
            setsView,
            "UIDropDownMenuTemplate"
        )
        classDropDown:SetPoint("TOPRIGHT", setsView, "TOPRIGHT", -32, -25)
        classDropDown:SetFrameLevel(setsView:GetFrameLevel() + 10)
        if UIDropDownMenu_SetWidth then
            UIDropDownMenu_SetWidth(classDropDown, 140)
        end
        classDropDown:Hide()
        UIDropDownMenu_Initialize(classDropDown, function()
            local Identity = SC.IdentityRegistry
            local options = Identity and Identity.GetClassFilterOptions and Identity.GetClassFilterOptions() or {}
            for _, option in ipairs(options) do
                local classOption = option
                local info = UIDropDownMenu_CreateInfo()
                info.text = classOption.label
                info.value = classOption.key
                info.checked = SC.db and SC.db.filters and SC.db.filters.classToken == classOption.key
                info.func = function()
                    if not (SC.db and SC.db.filters) then return end
                    SC.db.filters.classToken = classOption.key
                    if page.scSources then page.scSources.setPage = 1 end
                    refreshTransmogPage()
                end
                UIDropDownMenu_AddButton(info)
            end
        end)
        frame.scClassDropDown = classDropDown
    end

    UI.TransmogFrame = frame
    restoreFramePosition(frame)

    if UISpecialFrames then
        table.insert(UISpecialFrames, "SoloCollectionsWardrobeFrame")
    end
    return frame
end

function UI.ShowTransmog()
    local frame = UI.CreateTransmogFrame()
    if not frame then return end
    if frame:IsShown() then return frame end
    if UI.HideJournal then UI.HideJournal() end
    restoreFramePosition(frame)
    frame:Show()
    return frame
end

function UI.ToggleTransmog()
    local frame = UI.CreateTransmogFrame()
    if not frame then return end
    if frame:IsShown() then
        frame:Hide()
    else
        UI.ShowTransmog()
    end
end

function UI.HideTransmog()
    if UI.TransmogFrame then UI.TransmogFrame:Hide() end
end

function UI.SyncTransmogFilterChrome(mode, closeMenus)
    local frame = UI.TransmogFrame
    if not (frame and frame.scFilterButton) then return end
    if frame.scFilterPopup then frame.scFilterPopup:Hide() end
    if frame.scFilterButton.scLabel then
        frame.scFilterButton.scLabel:SetText(mode == "SETS" and "过滤器" or "来源")
    end
    if frame.scFilterButton.scArrow then
        frame.scFilterButton.scArrow:SetTexCoord(0, 1, 0, 1)
    end
    frame.scFilterButton:Show()
    if closeMenus and CloseDropDownMenus then
        CloseDropDownMenus()
    end
end

function UI.SyncTransmogClassDropDown(mode)
    local frame = UI.TransmogFrame
    local dropDown = frame and frame.scClassDropDown
    if not dropDown then return end
    if mode ~= "SETS" then
        dropDown:Hide()
        return
    end
    local Identity = SC.IdentityRegistry
    local options = Identity and Identity.GetClassFilterOptions and Identity.GetClassFilterOptions() or {}
    local selected = SC.db and SC.db.filters and SC.db.filters.classToken or "ALL"
    local label = "全部职业"
    for _, option in ipairs(options) do
        if option.key == selected then
            label = option.label
            break
        end
    end
    if UIDropDownMenu_SetSelectedValue then
        UIDropDownMenu_SetSelectedValue(dropDown, selected)
    end
    if UIDropDownMenu_SetText then
        UIDropDownMenu_SetText(dropDown, label)
    end
    dropDown:Show()
end

function UI.GetTransmogArmorFilterOptions()
    local options = {}
    local source = SC.EzWardrobe and SC.EzWardrobe.DataProvider and SC.EzWardrobe.DataProvider.ARMOR_OPTIONS or {}
    for _, option in ipairs(source) do
        options[#options + 1] = option
    end
    options[#options + 1] = { key = "ALL", label = "全部" }
    return options
end

function UI.ClearTransmogKeys(frame)
    frame = frame or UI.TransmogFrame
    if frame and ClearOverrideBindings then
        ClearOverrideBindings(frame)
    end
end

function UI.BindTransmogKeys(frame)
    frame = frame or UI.TransmogFrame
    if not (frame and SetOverrideBindingClick) then return end
    UI.ClearTransmogKeys(frame)
    if not frame:IsShown() then return end
    if frame.scSearchBox and frame.scSearchBox.HasFocus and frame.scSearchBox:HasFocus() then
        return
    end
    for key, button in pairs(frame.scKeyButtons or {}) do
        if button and button.GetName then
            SetOverrideBindingClick(frame, true, key, button:GetName())
        end
    end
    if frame.scEscapeButton and frame.scEscapeButton.GetName then
        SetOverrideBindingClick(frame, true, "ESCAPE", frame.scEscapeButton:GetName())
    end
end

function UI.SyncTransmogArmorDropDown(slot, mode)
    local frame = UI.TransmogFrame
    local dropDown = frame and frame.scArmorDropDown
    if not dropDown then return end
    if mode == "SETS" or not (SC.Catalog and SC.Catalog.IsArmorFilterSlot and SC.Catalog.IsArmorFilterSlot(slot)) then
        dropDown:Hide()
        return
    end
    local options = UI.GetTransmogArmorFilterOptions()
    local stored = SC.db and SC.db.filters and SC.db.filters.armorType or "AUTO"
    local selected = stored
    if stored == "AUTO" and SC.Catalog.ResolveArmorTypeForQuery then
        selected = SC.Catalog.ResolveArmorTypeForQuery(SC.db and SC.db.filters)
    end
    local label = "全部"
    for _, option in ipairs(options) do
        if option.key == selected then
            label = option.label
            break
        end
    end
    if UIDropDownMenu_SetSelectedValue then
        UIDropDownMenu_SetSelectedValue(dropDown, selected)
    end
    if UIDropDownMenu_SetText then
        UIDropDownMenu_SetText(dropDown, label)
    end
    dropDown:Show()
    if UIDropDownMenu_EnableDropDown then
        UIDropDownMenu_EnableDropDown(dropDown)
    end
end

function UI.SyncTransmogWeaponDropDown(slot, mode)
    local frame = UI.TransmogFrame
    local dropDown = frame and frame.scWeaponDropDown
    if not dropDown then return end
    if mode == "SETS" or not (SC.Catalog and SC.Catalog.IsWeaponFilterSlot(slot)) then
        dropDown:Hide()
        return
    end
    local options = SC.Catalog.GetAvailableWeaponFilters(slot)
    if #options == 0 then
        dropDown:Hide()
        return
    end
    local selected = "AUTO"
    if SC.db and SC.db.filters then
        selected = SC.Catalog.EnsureWeaponTypeForSlot(SC.db.filters, slot)
    end
    local label = SC.Catalog.WeaponFilterLabel(selected) or (options[1] and options[1].label) or ""
    if UIDropDownMenu_SetSelectedValue then
        UIDropDownMenu_SetSelectedValue(dropDown, selected)
    end
    if UIDropDownMenu_SetText then
        UIDropDownMenu_SetText(dropDown, label)
    end
    dropDown:Show()
    if #options > 1 then
        if UIDropDownMenu_EnableDropDown then UIDropDownMenu_EnableDropDown(dropDown) end
    elseif UIDropDownMenu_DisableDropDown then
        UIDropDownMenu_DisableDropDown(dropDown)
    end
end

local displayWatcher = CreateFrame("Frame")
displayWatcher:RegisterEvent("DISPLAY_SIZE_CHANGED")
displayWatcher:RegisterEvent("UI_SCALE_CHANGED")
displayWatcher:SetScript("OnEvent", function()
    if UI.TransmogFrame then
        restoreFramePosition(UI.TransmogFrame)
    end
    if UI.TransmogLauncher then
        UI.TransmogLauncher:SetClampedToScreen(true)
    end
end)

local function acceptChat(text)
    if DEFAULT_CHAT_FRAME and DEFAULT_CHAT_FRAME.AddMessage then
        DEFAULT_CHAT_FRAME:AddMessage(text)
    end
end

local function acceptNear(value, expected, slack)
    return math.abs((tonumber(value) or 0) - expected) <= (slack or 2)
end

local function acceptMeasure(region)
    if not region then return nil end
    return {
        w = region.GetWidth and region:GetWidth() or 0,
        h = region.GetHeight and region:GetHeight() or 0,
        shown = region.IsShown and region:IsShown() and true or false,
        alpha = region.GetAlpha and region:GetAlpha() or nil,
        left = region.GetLeft and region:GetLeft() or nil,
        right = region.GetRight and region:GetRight() or nil,
        top = region.GetTop and region:GetTop() or nil,
        bottom = region.GetBottom and region:GetBottom() or nil,
    }
end

local function acceptCovers(outer, inner)
    if not (outer and inner and outer.left and inner.left) then return false end
    return outer.left <= inner.left + 1
        and outer.right >= inner.right - 1
        and outer.top >= inner.top - 1
        and outer.bottom <= inner.bottom + 1
end

local function acceptAdd(report, name, ok, detail)
    report.checks[#report.checks + 1] = {
        name = name,
        ok = ok and true or false,
        detail = detail or "",
    }
    if not ok then report.passed = false end
end

function SC.RunAcceptanceCheck()
    if UI.ShowTransmog then
        UI.ShowTransmog()
    elseif SC.ToggleTransmog then
        SC:ToggleTransmog()
    end

    local frame = UI.TransmogFrame
    if frame then
        if SC.db then
            SC.db.transmogFrame = { point = "CENTER", relativePoint = "CENTER", x = 0, y = 20 }
        end
        frame:ClearAllPoints()
        frame:SetPoint("CENTER", UIParent, "CENTER", 0, 20)
        frame:Show()
    end

    local report = {
        time = tostring((time and time()) or 0),
        passed = true,
        checks = {},
        slots = {},
        cards = {},
    }
    local page = frame and frame.scPage
    local state = page and page.scState
    local slots = page and page.scSlots
    local sources = page and page.scSources
    if page and page.Refresh then page:Refresh() end

    acceptAdd(report, "transmog_shown", frame and frame:IsShown() and true or false,
        frame and string.format("scale=%.2f left=%.0f right=%.0f w=%.0f parentW=%.0f",
            frame:GetScale() or 0, frame:GetLeft() or -1, frame:GetRight() or -1,
            frame:GetWidth() or 0, UIParent:GetWidth() or 0) or "missing frame")
    acceptAdd(report, "page_ready", page and state and slots and true or false,
        page and "scPage" or "missing page")

    local emptyCount = 0
    local occupiedCount = 0
    local selectedBefore = state and state.selectedSlot
    if slots and slots.buttons and state then
        for _, definition in ipairs(Lab.SLOTS or {}) do
            local button = slots.buttons[definition.key]
            local occupied = state:IsSlotOccupied(definition.key) and true or false
            local block = button and button.scEmptyBlock
            local highlight = button and button.scSlotHighlight
            local ring = button and button.scSelectedTexture
            local blockSize = acceptMeasure(block)
            local ringSize = acceptMeasure(ring)
            local highlightAlpha = highlight and highlight.GetAlpha and highlight:GetAlpha() or -1
            local mouseEnabled = button and button.IsMouseEnabled and button:IsMouseEnabled()
            if mouseEnabled == 1 then mouseEnabled = true end
            if mouseEnabled == 0 then mouseEnabled = false end
            local beforeThis = state.selectedSlot
            local selectOk = state:SelectSlot(definition.key)
            local selectedAfter = state.selectedSlot
            if occupied then
                occupiedCount = occupiedCount + 1
            else
                emptyCount = emptyCount + 1
                if block and block.GetScript and block:GetScript("OnClick") then
                    block:GetScript("OnClick")(block, "LeftButton")
                end
            end
            local row = {
                key = definition.key,
                occupied = occupied,
                blockShown = block and block:IsShown() and true or false,
                blockSize = blockSize,
                coversRing = acceptCovers(blockSize, ringSize),
                highlightAlpha = highlightAlpha,
                mouseEnabled = mouseEnabled and true or false,
                selectReturned = selectOk and true or false,
                selectedAfter = selectedAfter,
            }
            report.slots[#report.slots + 1] = row
            if occupied then
                acceptAdd(report, "occupied_" .. definition.key,
                    (not row.blockShown)
                        and acceptNear(highlightAlpha, 1, 0.05)
                        and mouseEnabled
                        and (selectOk and selectedAfter == definition.key),
                    string.format("block=%s hl=%.2f mouse=%s select=%s",
                        tostring(row.blockShown), highlightAlpha,
                        tostring(row.mouseEnabled), tostring(selectOk)))
            else
                acceptAdd(report, "empty_" .. definition.key,
                    row.blockShown
                        and blockSize and blockSize.w >= 70 and blockSize.h >= 70
                        and row.coversRing
                        and acceptNear(highlightAlpha, 0, 0.05)
                        and not mouseEnabled
                        and not selectOk
                        and selectedAfter == beforeThis,
                    string.format("block=%sx%s cover=%s hl=%.2f mouse=%s select=%s stay=%s",
                        tostring(blockSize and blockSize.w), tostring(blockSize and blockSize.h),
                        tostring(row.coversRing), highlightAlpha, tostring(row.mouseEnabled),
                        tostring(selectOk), tostring(selectedAfter == beforeThis)))
            end
        end
        if selectedBefore and state.selectedSlot ~= selectedBefore and state:IsSlotOccupied(selectedBefore) then
            state:SelectSlot(selectedBefore)
        end
    end
    acceptAdd(report, "has_empty_slot", emptyCount > 0,
        string.format("empty=%d occupied=%d", emptyCount, occupiedCount))

    local firstCard
    if sources and sources.itemCards then
        for index, card in ipairs(sources.itemCards) do
            if card:IsShown() then
                firstCard = card
                break
            end
        end
        if not firstCard then firstCard = sources.itemCards[1] end
    end
    if firstCard then
        local cardSize = acceptMeasure(firstCard)
        local borderTex = firstCard.scBorder and firstCard.scBorder.scTexture
        local selectedTex = firstCard.scSelected and firstCard.scSelected.scTexture
        local applied = firstCard.scApplied
        local appliedTex = applied and applied.scTexture
        local borderSize = acceptMeasure(borderTex)
        local selectedSize = acceptMeasure(selectedTex)
        local appliedSize = acceptMeasure(appliedTex)
        report.cards = {
            card = cardSize,
            border = borderSize,
            selected = selectedSize,
            applied = appliedSize,
        }
        acceptAdd(report, "card_body_78x104",
            cardSize and acceptNear(cardSize.w, 78) and acceptNear(cardSize.h, 104),
            cardSize and string.format("%sx%s", cardSize.w, cardSize.h) or "missing")
        acceptAdd(report, "border_94x120_not_stretched",
            borderSize and acceptNear(borderSize.w, 94) and acceptNear(borderSize.h, 120)
                and not (acceptNear(borderSize.w, 78) and acceptNear(borderSize.h, 104)),
            borderSize and string.format("%sx%s", borderSize.w, borderSize.h) or "missing")
        acceptAdd(report, "selected_98x124_not_stretched",
            selectedSize and acceptNear(selectedSize.w, 98) and acceptNear(selectedSize.h, 124)
                and not (acceptNear(selectedSize.w, 78) and acceptNear(selectedSize.h, 104)),
            selectedSize and string.format("%sx%s", selectedSize.w, selectedSize.h) or "missing")
        if appliedSize then
            acceptAdd(report, "applied_94x124_not_stretched",
                acceptNear(appliedSize.w, 94) and acceptNear(appliedSize.h, 124)
                    and not (acceptNear(appliedSize.w, 78) and acceptNear(appliedSize.h, 104)),
                string.format("%sx%s", appliedSize.w, appliedSize.h))
        end
    else
        acceptAdd(report, "item_card_present", false, "no item cards")
    end

    if type(SoloCollectionsDB) ~= "table" then SoloCollectionsDB = {} end
    SoloCollectionsDB.acceptanceProbe = report
    if SC.db then SC.db.acceptanceProbe = report end

    local failed = {}
    for _, check in ipairs(report.checks) do
        if not check.ok then
            failed[#failed + 1] = check.name
        end
    end
    local summary = string.format(
        "SoloCollections acceptcheck: %s %d/%d",
        report.passed and "PASS" or "FAIL",
        #report.checks - #failed,
        #report.checks
    )
    if UIErrorsFrame and UIErrorsFrame.AddMessage then
        UIErrorsFrame:AddMessage(summary, report.passed and 0.2 or 1, report.passed and 1 or 0.2, 0.2, 1)
    end
    acceptChat("|cff00ff96" .. summary .. "|r")
    if #failed > 0 then
        acceptChat("|cffff6060  fail: " .. table.concat(failed, ", ") .. "|r")
    end
    for _, check in ipairs(report.checks) do
        acceptChat(string.format("  %s %s %s", check.ok and "OK" or "NG", check.name, check.detail or ""))
    end
    return report
end
