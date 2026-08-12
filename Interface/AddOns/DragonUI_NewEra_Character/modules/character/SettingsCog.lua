-- DragonUI_NewEra/modules/character/SettingsCog.lua — the settings gear in the character panel's
-- top-right corner, and the menu of display options it opens.
--
-- Art + build follow the spellbook/professions/Cooldown Manager cogs (the "questlog-icon-setting"
-- atlas with the stock Interface\Buttons\UI-OptionsButton as the 3.3.5a fallback), so every cog in
-- the addon is the same gear. The menu goes through NE.menu, which gives it toggle-on-second-click
-- for free — the same path modules/cooldownviewer/SettingsMenu.lua's cog uses.
--
-- PLACEMENT: seated UNDER the close X (which PanelChrome anchors at TOPRIGHT(1,0) at 24x24), in the
-- empty gutter right of the sidebar tab strip. The cog's frame level clears the whole chrome stack
-- the same way the close button does — the nineslice corner (level+1) and the title band (level+11)
-- both paint over this corner otherwise.
--
-- ADDING AN OPTION: append to menuGenerator(). Anything with a getter/setter pair on CP works; keep
-- the SETTING itself in the module that owns the feature (as the body-background pair lives in
-- CharacterPanel.lua, which owns f.Bg) so this file stays presentation-only.

local NE = DragonUI_NewEra
NE.charpanel = NE.charpanel or {}
local CP = NE.charpanel

local MODULE = "character"
local L = NE.L or setmetatable({}, { __index = function(_, k) return k end })

local function log(msg) if CP._log then CP._log(msg) elseif NE.Log then NE.Log("CHARPANEL", msg) end end

local COG_SIZE = 6
-- Offsets from the close button's BOTTOMRIGHT (owner steer: the gear sits UNDER the X, not beside
-- it). x pulls the gear in off the frame's right border so the two don't crowd; y is the gap below
-- the 24px X. Anchoring off the button rather than the frame corner keeps the pair together if the
-- chrome ever moves the X. Fallback below uses the frame corner with the same resulting offsets.
local COG_X    = -9
local COG_Y    = -6

-- ----------------------------------------------------------------------------
-- The menu. Rebuilt from the generator on every open, so the radio marks are always current.
-- ----------------------------------------------------------------------------
local function menuGenerator(_, root)
  root:CreateTitle(L["Background"])
  root:CreateRadio(L["Stone"],
    function() return not CP.IsDarkBodyBackground() end,
    function() CP.SetDarkBodyBackground(false) end)
  root:CreateRadio(L["Dark"],
    function() return CP.IsDarkBodyBackground() end,
    function() CP.SetDarkBodyBackground(true) end)
end

local function toggleMenu(cog)
  if not (NE.menu and NE.menu.ToggleAnchored) then
    log("NE.menu unavailable; the settings cog has nothing to open")
    return
  end
  NE.menu.ToggleAnchored(menuGenerator, cog,
    { point = "TOPRIGHT", relativePoint = "BOTTOMRIGHT", x = 0, y = -2 })
end

-- ----------------------------------------------------------------------------
-- The gear button.
-- ----------------------------------------------------------------------------
local function buildCog()
  local f = CP.frame
  if not f then return nil end
  if CP._settingsCog then return CP._settingsCog end

  local cog = CreateFrame("Button", "NE_CharacterSettingsCog", f)
  cog:SetSize(COG_SIZE, COG_SIZE)

  cog.Icon = cog:CreateTexture(nil, "ARTWORK")
  if not (NE.tex and NE.tex.SetAtlas and NE.tex.SetAtlas(cog.Icon, "questlog-icon-setting", true)) then
    cog.Icon:SetTexture("Interface\\Buttons\\UI-OptionsButton"); cog.Icon:SetSize(16, 16)
  end
  cog.Icon:SetPoint("CENTER")

  cog.Hi = cog:CreateTexture(nil, "HIGHLIGHT")
  if not (NE.tex and NE.tex.SetAtlas and NE.tex.SetAtlas(cog.Hi, "questlog-icon-setting", true)) then
    cog.Hi:SetTexture("Interface\\Buttons\\UI-OptionsButton"); cog.Hi:SetSize(16, 16)
  end
  cog.Hi:SetPoint("CENTER"); cog.Hi:SetBlendMode("ADD"); cog.Hi:SetAlpha(0.4)

  -- Above the nineslice corner + title band, matching how CloseButton.lua lifts the X.
  cog:SetFrameLevel(((f.GetFrameLevel and f:GetFrameLevel()) or 1) + 20)
  local x = f.CloseButton
  if x then
    cog:SetPoint("TOPRIGHT", x, "BOTTOMRIGHT", COG_X, COG_Y)
  else
    -- No X to hang off (chrome degraded): same spot measured from the corner instead. The close
    -- button is 24x24 at TOPRIGHT(1,0), so its BOTTOMRIGHT is (1, -24) in frame coords.
    cog:SetPoint("TOPRIGHT", f, "TOPRIGHT", COG_X + 1, COG_Y - 24)
  end

  cog:RegisterForClicks("LeftButtonUp")
  cog:SetScript("OnClick", function(self) toggleMenu(self) end)
  cog:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:SetText(L["Character panel settings"], 1, 1, 1)
    GameTooltip:Show()
  end)
  cog:SetScript("OnLeave", function() GameTooltip:Hide() end)

  CP._settingsCog = cog
  return cog
end

CP.BuildSettingsCog = buildCog

local boot = CreateFrame("Frame")
boot:RegisterEvent("PLAYER_LOGIN")
boot:SetScript("OnEvent", function()
  if NE.modules and NE.modules.IsEnabled and not NE.modules.IsEnabled(MODULE) then return end
  -- The frame owns the corner we anchor into; build it first (idempotent), same as CloseButton.lua.
  if CP.BuildFrame then pcall(CP.BuildFrame) end
  local ok, err = pcall(buildCog)
  if not ok then log("settings cog build failed: " .. tostring(err)) end
end)
