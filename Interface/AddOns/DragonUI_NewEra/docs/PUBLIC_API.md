# DragonUI_NewEra Public API v1

External AddOns must use `DragonUI_NewEra.Public`; direct access to `NE.panelchrome`, `NE.nineslice`, `NE.tex`, `NE.tabs`, `NE.buttonskin`, `NE.scrollbar`, `NE.FrameUtil`, `NE.modules`, or DragonUI's ModuleRegistry is unsupported.

## Capability check

```lua
local Public = DragonUI_NewEra and DragonUI_NewEra.Public
local ok, missing = Public and Public.Require(1, {
    "chrome.panel",
    "components.inset",
    "components.tabs",
    "components.buttons",
})
if not ok then error("DragonUI_NewEra capability missing: " .. tostring(missing)) end
```

## Minimal external window example

```lua
local Public = DragonUI_NewEra.Public
local frame = CreateFrame("Frame", "ExampleModernWindow", UIParent)
frame:SetSize(520, 360)
frame:SetPoint("CENTER")
Public.Chrome:Apply(frame, { layout = "PortraitFrameTemplate", title = "Example" })
Public.Chrome:SetTitle(frame, "Example")

local inset = Public.Components:CreateInset(frame, { left = 18, top = 58, right = 18, bottom = 52 })
local tab = Public.Components:CreateBottomTab(frame, { label = "Overview" })
tab:SetPoint("TOPLEFT", frame, "BOTTOMLEFT", 16, 2)
local button = CreateFrame("Button", nil, inset, "UIPanelButtonTemplate")
button:SetSize(120, 24)
button:SetPoint("CENTER")
button:SetText("Refresh")
Public.Components:SkinButton(button)
```

`Public.Model` exists in v1 but reports `model.presenter` and `model.controls` as unavailable until the dedicated model-service migration stage.
