local NE = DragonUI_NewEra
local Public = NE and NE.Public
if not Public then return end

local Components = Public.Components or {}
Public.Components = Components

local function setText(button, text)
    local label = button:GetFontString()
    if not label then
        label = button:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        label:SetPoint("CENTER")
        button:SetFontString(label)
    end
    button:SetText(text or "")
end

function Components:CreateInset(parent, options)
    options = options or {}
    local inset
    if NE.nineslice and NE.nineslice.AttachInset then
        inset = NE.nineslice.AttachInset(parent, options.left or 0, options.top or 0, options.right or 0, options.bottom or 0)
    else
        inset = CreateFrame("Frame", nil, parent)
        inset:SetPoint("TOPLEFT", parent, "TOPLEFT", options.left or 0, -(options.top or 0))
        inset:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", -(options.right or 0), options.bottom or 0)
    end
    return inset
end

function Components:CreateBottomTab(parent, spec)
    spec = spec or {}
    local button = CreateFrame("Button", spec.name, parent)
    button:SetWidth(spec.width or 112)
    button:SetHeight(spec.height or 30)
    setText(button, spec.label)
    if NE.buttonskin and NE.buttonskin.Skin then NE.buttonskin.Skin(button, spec.skinOptions or {}) end
    local selected = button:CreateTexture(nil, "ARTWORK")
    selected:SetTexture("Interface\\Buttons\\WHITE8X8")
    selected:SetPoint("TOPLEFT", button, "TOPLEFT", 4, -4)
    selected:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", -4, 4)
    selected:SetVertexColor(0.72, 0.38, 0.06, 0.42)
    selected:Hide()
    local line = button:CreateTexture(nil, "OVERLAY")
    line:SetTexture("Interface\\Buttons\\WHITE8X8")
    line:SetPoint("BOTTOMLEFT", button, "BOTTOMLEFT", 8, 3)
    line:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", -8, 3)
    line:SetHeight(2)
    line:SetVertexColor(1.00, 0.72, 0.16, 0.95)
    line:Hide()
    function button:SetSelected(value)
        self.scSelected = value and true or false
        if self.scSelected then selected:Show(); line:Show(); self:LockHighlight()
        else selected:Hide(); line:Hide(); self:UnlockHighlight() end
    end
    button.scSelectedTexture = selected
    button.scSelectedLine = line
    if spec.onClick then button:SetScript("OnClick", spec.onClick) end
    return button
end

function Components:CreateTopTab(parent, spec)
    local button = self:CreateBottomTab(parent, spec)
    button.scTopTab = true
    return button
end

function Components:CreateSearchBox(parent, spec)
    spec = spec or {}
    local box = CreateFrame("EditBox", spec.name, parent, "InputBoxTemplate")
    box:SetAutoFocus(false)
    box:SetWidth(spec.width or 210)
    box:SetHeight(spec.height or 24)
    box:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    box:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
    if spec.onChanged then
        box:SetScript("OnTextChanged", function(self, userInput)
            if userInput then spec.onChanged(self:GetText() or "") end
        end)
    end
    return box
end

function Components:SkinProgressBar(statusBar, background, border)
    if not statusBar then return false end
    statusBar:SetStatusBarColor(0.76, 0.48, 0.08, 1)
    if background then background:SetVertexColor(0.018, 0.020, 0.024, 1) end
    if border then border:SetVertexColor(0.82, 0.68, 0.36, 0.95) end
    return true
end

function Components:SkinCountFrame(frame)
    if not frame then return false end
    if NE.nineslice and NE.nineslice.Apply then
        NE.nineslice.Apply(frame, "InsetFrameTemplate")
    end
    return true
end

function Components:CreateFilterButton(parent, spec)
    spec = spec or {}
    local button = CreateFrame("Button", spec.name, parent, "UIPanelButtonTemplate")
    button:SetWidth(spec.width or 116)
    button:SetHeight(spec.height or 24)
    setText(button, spec.label or FILTER or "Filter")
    if spec.onClick then button:SetScript("OnClick", spec.onClick) end
    self:SkinButton(button, spec.skinOptions)
    return button
end

-- Public collection-journal header. The returned table is intentionally a
-- projection of stable widgets; callers do not receive DragonUI's local
-- collection implementation or its selection state.
function Components:CreateCollectionInfoHeader(parent, spec)
    spec = spec or {}
    local host = CreateFrame("Frame", spec.name, parent)
    host:SetPoint("TOPLEFT", parent, "TOPLEFT", spec.x or 0, -(spec.y or 0))
    if spec.width then host:SetWidth(spec.width) end
    if spec.height then host:SetHeight(spec.height) end
    if spec.point then
        host:ClearAllPoints()
        host:SetPoint(spec.point, parent, spec.relativePoint or spec.point, spec.x or 0, spec.y or 0)
    end

    local infoIconSize = spec.iconSize or 40
    local opening = 0.4922
    local frameSize = infoIconSize / opening
    local frameX = (0.5 - 0.4727) * frameSize
    local frameY = (0.4336 - 0.5) * frameSize

    local ornament = host:CreateTexture(nil, "OVERLAY")
    ornament:SetTexture(spec.frameTexture or "Interface\\AddOns\\DragonUI\\Textures\\Collections\\IconFrameGold.tga")
    ornament:SetSize(frameSize, frameSize)
    ornament:SetPoint("TOPLEFT", host, "TOPLEFT", 2, -2)

    local icon = host:CreateTexture(nil, "ARTWORK")
    icon:SetSize(infoIconSize, infoIconSize)
    icon:SetPoint("CENTER", ornament, "CENTER", -frameX, -frameY)
    icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

    local drag = CreateFrame("Button", nil, host)
    drag:SetAllPoints(icon)
    if spec.onClick then drag:SetScript("OnClick", spec.onClick) end
    if spec.onDragStart then
        drag:RegisterForDrag("LeftButton")
        drag:SetScript("OnDragStart", spec.onDragStart)
    end
    if spec.onEnter then drag:SetScript("OnEnter", spec.onEnter) end
    if spec.onLeave then drag:SetScript("OnLeave", spec.onLeave) end

    local name = host:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    name:SetPoint("LEFT", icon, "RIGHT", 14, 0)
    name:SetWidth(spec.nameWidth or 260)
    name:SetHeight(spec.nameHeight or 40)
    name:SetJustifyH("LEFT")
    name:SetJustifyV("CENTER")
    name:SetWordWrap(true)
    local source = host:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    source:SetPoint("TOPLEFT", ornament, "BOTTOMLEFT", 12, -4)
    source:SetWidth(spec.textWidth or 320)
    source:SetJustifyH("LEFT")
    local description = host:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    description:SetPoint("TOPLEFT", source, "BOTTOMLEFT", 0, -6)
    description:SetWidth(spec.textWidth or 320)
    description:SetJustifyH("LEFT")
    description:SetJustifyV("TOP")
    description:SetTextColor(0.82, 0.82, 0.82)

    return {
        frame = host,
        ornament = ornament,
        icon = icon,
        button = drag,
        name = name,
        source = source,
        description = description,
    }
end

function Components:CreateJournalFilterButton(parent, spec)
    spec = spec or {}
    local button = CreateFrame("Button", spec.name, parent, "UIPanelButtonTemplate")
    button:SetSize(spec.width or 76, spec.height or 20)
    setText(button, spec.label or FILTER or "Filter")
    local arrow = button:CreateTexture(nil, "ARTWORK")
    arrow:SetSize(8, 8)
    arrow:SetPoint("RIGHT", button, "RIGHT", -6, 0)
    arrow:SetTexture(spec.arrowTexture or "Interface\\ChatFrame\\ChatFrameExpandArrow")
    local label = button:GetFontString()
    if label then
        label:ClearAllPoints()
        label:SetPoint("LEFT", button, "LEFT", 8, 0)
    end
    self:SkinRedActionButton(button)
    if spec.onClick then button:SetScript("OnClick", spec.onClick) end
    return button
end

function Components:CreateRandomMountButton(parent, spec)
    spec = spec or {}
    local button = CreateFrame("Button", spec.name, parent)
    button:SetSize(spec.width or 30, spec.height or 30)
    local icon = button:CreateTexture(nil, "ARTWORK")
    icon:SetAllPoints(button)
    icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    icon:SetTexture(spec.icon or "Interface\\AddOns\\DragonUI_NewEra\\Textures\\Collections\\MountUpFavourites.blp")
    local border = button:CreateTexture(nil, "OVERLAY")
    border:SetTexture(spec.frameTexture or "Interface\\AddOns\\DragonUI\\Textures\\ActionBars\\uiactionbariconframe_white.tga")
    local scale = (spec.width or 30) / 37
    local frameX = 2.2 * scale
    local frameTop = 2.3 * scale
    border:SetVertexColor(0.08, 0.08, 0.08)
    border:SetPoint("TOPRIGHT", button, "TOPRIGHT", frameX, frameTop)
    border:SetPoint("BOTTOMLEFT", button, "BOTTOMLEFT", -frameX, -frameX)
    button._neIcon = icon
    button._neBorder = border
    button:SetPushedTexture("Interface\\Buttons\\UI-Quickslot-Depress")
    button:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
    if spec.onClick then button:SetScript("OnClick", spec.onClick) end
    if spec.onEnter then button:SetScript("OnEnter", spec.onEnter) end
    if spec.onLeave then button:SetScript("OnLeave", spec.onLeave) end
    if spec.onDragStart then
        button:RegisterForDrag("LeftButton")
        button:SetScript("OnDragStart", spec.onDragStart)
    end
    return button
end

function Components:SkinRedActionButton(button, options)
    if not button then return false end
    local dragon = NE.dragon
    if dragon and type(dragon.SkinRedButton) == "function" then
        if button._duiRedButton then return true end
        local ok = pcall(dragon.SkinRedButton, button, options)
        if ok then return true end
    end
    return self:SkinButton(button, options)
end

function Components:CreateJournalTab(parent, spec)
    spec = spec or {}
    local index = spec.index or 1
    local name = spec.name or ("DragonUI_NewEraJournalTab" .. tostring(index))
    local button = CreateFrame("Button", name, parent, "CharacterFrameTabButtonTemplate")
    button:SetID(index)
    button:SetText(spec.label or "")
    if NE.tabs and NE.tabs.ReskinClassicTab then
        NE.tabs.ReskinClassicTab(name, { selectedTextY = -3, deselectedTextY = -3 })
    end
    local label = _G[name .. "Text"] or button:GetFontString()
    local textWidth = label and label:GetStringWidth() or 40
    button:SetWidth(math.max(70, math.floor(textWidth + 30)))
    local normalHeight = spec.height or 36
    local selectedHeight = spec.selectedHeight or 42
    button:SetHeight(normalHeight)
    local normalLevel = button:GetFrameLevel()
    if spec.onClick then button:SetScript("OnClick", spec.onClick) end
    function button:SetSelected(value)
        Components:SetJournalTabSelected(self, value)
        self:SetHeight(value and selectedHeight or normalHeight)
        self:SetFrameLevel(normalLevel + (value and 8 or 0))
    end
    button.scCutoff = spec.cutoff and true or false
    button.scNewEraJournalTab = true
    return button
end

function Components:SetJournalTabSelected(button, selected)
    if not button then return false end
    if selected then
        if PanelTemplates_SelectTab then PanelTemplates_SelectTab(button) else button:Disable() end
    else
        if PanelTemplates_DeselectTab then PanelTemplates_DeselectTab(button) else button:Enable() end
    end
    button.scSelected = selected and true or false
    return true
end

function Components:LayoutJournalTabs(parent, tabs, spec)
    if not (parent and NE.tabs and NE.tabs.SizeAndAnchorTabs) then return false end
    spec = spec or {}
    local names = {}
    for _, tab in ipairs(tabs or {}) do
        if tab and tab:GetName() then names[#names + 1] = tab:GetName() end
    end
    NE.tabs.SizeAndAnchorTabs(parent, names, {
        parentPoint = "BOTTOMLEFT",
        startX = spec.startX or 14,
        startY = spec.startY or 2,
        gap = spec.gap or 1,
        minWidth = spec.minWidth or 70,
        textPadding = spec.textPadding or 30,
    })
    return true
end

function Components:SkinButton(button, options)
    if NE.buttonskin and NE.buttonskin.Skin then return NE.buttonskin.Skin(button, options or {}) end
    return false
end

function Components:SkinScrollbar(scrollbar, options)
    if NE.scrollbar and NE.scrollbar.Reskin then return NE.scrollbar.Reskin(scrollbar, options or {}) end
    return false
end

function Components:ApplyItemQuality(button, quality)
    if NE.itembutton and NE.itembutton.ApplyQuality then return NE.itembutton.ApplyQuality(button, quality) end
end

function Components:CreateItemGrid(options)
    if NE.itemgrid and NE.itemgrid.New then return NE.itemgrid.New(options or {}) end
    return nil, "itemgrid"
end

Public._SetCapability("components.inset", true)
Public._SetCapability("components.tabs", true)
Public._SetCapability("components.search", true)
Public._SetCapability("components.buttons", NE.buttonskin and type(NE.buttonskin.Skin) == "function")
Public._SetCapability("components.scrollbar", NE.scrollbar and type(NE.scrollbar.Reskin) == "function")
Public._SetCapability("components.progress", true)
Public._SetCapability("components.collection-header", type(Components.CreateCollectionInfoHeader) == "function")
Public._SetCapability("components.journal-filter", type(Components.CreateJournalFilterButton) == "function")
Public._SetCapability("components.random-mount", type(Components.CreateRandomMountButton) == "function")
Public._SetCapability("components.red-action", type(Components.SkinRedActionButton) == "function")
Public._SetCapability("components.journal-tabs", type(Components.CreateJournalTab) == "function" and type(Components.LayoutJournalTabs) == "function")
