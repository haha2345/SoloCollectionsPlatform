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
    if spec.onChanged then
        box:SetScript("OnTextChanged", function(self, userInput)
            if userInput then spec.onChanged(self:GetText() or "") end
        end)
    end
    return box
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

