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
        if UI.EnsureDefaultSetClassFilter then UI.EnsureDefaultSetClassFilter() end
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

function UI.ToggleTransmog()
    local frame = UI.CreateTransmogFrame()
    if not frame then return end
    if frame:IsShown() then
        frame:Hide()
    else
        if UI.HideJournal then UI.HideJournal() end
        restoreFramePosition(frame)
        frame:Show()
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
