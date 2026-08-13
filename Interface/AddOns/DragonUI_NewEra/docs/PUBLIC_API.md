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
    "components.collection-header",
    "components.journal-filter",
    "components.random-collection",
    "components.random-mount",
    "components.red-action",
    "components.journal-tabs",
})
if not ok then error("DragonUI_NewEra capability missing: " .. tostring(missing)) end
```

## Collection journal components

The following stable methods are available from `Public.Components` for a collection journal
adapter. They expose widgets and visual behavior only; collection ownership, filtering state,
and action authorization remain with the consuming AddOn and its server bridge.

```lua
local Components = DragonUI_NewEra.Public.Components
local header = Components:CreateCollectionInfoHeader(parent, spec)
local filter = Components:CreateJournalFilterButton(parent, spec)
local random = Components:CreateRandomCollectionButton(parent, {
    label = "Summon Random Favorite Companion",
    icon = currentFavoriteIcon,
    fallbackIcon = "Interface\\Icons\\Ability_Hunter_BeastCall",
    tooltip = "Summon a random favorite companion",
    onClick = requestAuthoritativeRandomCompanion,
})
local legacyMountRandom = Components:CreateRandomMountButton(parent, spec)
Components:SkinRedActionButton(actionButton)
local tab = Components:CreateJournalTab(parent, {
    index = 1, label = "Mounts", onClick = onClick, height = 36, selectedHeight = 42,
})
Components:SetJournalTabSelected(tab, true)
Components:LayoutJournalTabs(frame, tabs, { startX = 14, startY = 2, gap = 1 })
```

`CreateCollectionInfoHeader` returns a projection containing `frame`, `icon`, `button`, `name`,
`source`, and `description`. `CreateJournalTab` uses the classic character tab template internally;
it exposes 36/42px inactive/selected heights and raises the selected tab's frame level by 8 before
restoring the normal level on deselection. Callers must not reach into `NE.tabs` or DragonUI's private
skin tables.

`CreateRandomCollectionButton` owns only icon cropping, border, pushed/highlight textures, optional
label and tooltip wiring. The consuming AddOn owns collection/favorite state and must route actions
to its authoritative server bridge. The component never creates macros and never emits `/script`.
`CreateRandomMountButton` remains a visual-compatibility alias with the existing mount icon default.

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
