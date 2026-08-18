-- DragonUI_NewEra/modules/collections/MicroButton.lua
-- A micromenu-adjacent button that opens the Collections (Mounts & Pet Journal) window.
--
-- DragonUI's own micromenu module (DragonUI/modules/micromenu.lua) already RESERVES a slot for
-- this: its MICRO_BUTTONS array includes `_G.CollectionsMicroButton` between LFDMicroButton and
-- PVPMicroButton (micromenu.lua:120), and it ships full colored-mode atlas coordinates for it
-- (MicromenuAtlas["UI-HUD-MicroMenu-Collections-*"], micromenu.lua:192-195) pointing at
-- Interface\AddOns\DragonUI\Textures\Micromenu\uimicromenu2x.blp -- this client just has no
-- native CollectionsMicroButton frame for 3.3.5a to have discovered, so that slot has sat
-- permanently nil. We can't retroactively fill it though: MICRO_BUTTONS is a `local` table built
-- ONCE at DragonUI's own file-load time (before DragonUI_NewEra ever runs), so creating a real
-- `_G.CollectionsMicroButton` afterward is invisible to that closure -- same extension-point
-- problem modules/encounterjournal/MicroButton.lua hit for Adventure Guide, just with the added
-- irony that here the array slot AND the art already exist. We build a standalone button exactly
-- like that module does, just reusing DragonUI's own shipped Collections icon (a real in-tree
-- asset, no need to import another BLP) and inserting at the position DragonUI's own array
-- already implies is correct: between LFD and PVP.
--
-- See modules/encounterjournal/MicroButton.lua for the full rationale on the shift-cluster
-- technique below -- this is the same mechanism, just targeting a different gap.

local NE = DragonUI_NewEra
if not NE then return end
NE.collections = NE.collections or {}

local unpack = unpack

-- DragonUI's own colored micro-icon sheet already contains real Collections art (mirrors
-- DragonUI/modules/micromenu.lua:192-195 exactly -- verified present in-tree at
-- DragonUI/Textures/Micromenu/uimicromenu2x.blp).
local ICON_FILE = [[Interface\AddOns\DragonUI\Textures\Micromenu\uimicromenu2x]]
local COORDS = {
  up        = { 0.129883, 0.192383, 0.166016, 0.326172 },
  down      = { 0.065430, 0.127930, 0.822266, 0.982422 },
  mouseover = { 0.129883, 0.192383, 0.001953, 0.162109 },
  disabled  = { 0.065430, 0.127930, 0.658203, 0.818359 },
}
-- Shared rounded backplate DragonUI paints behind every native icon -- same rect for every
-- button (DragonUI/modules/micromenu.lua:2157/2164), not per-icon art.
local BG = {
  normal = { 0.065430, 0.127930, 0.330078, 0.490234 },
  pushed = { 0.065430, 0.127930, 0.494141, 0.654297 },
}

local btn

local function create()
  if btn then return btn end

  -- Parent to pUiMicroMenu (not UIParent) to inherit the same effective scale as every native
  -- button -- see encounterjournal/MicroButton.lua for why a plain-UIParent parent renders
  -- 1/menuScale times too big on screen.
  local parent = _G.pUiMicroMenu or UIParent
  local b = CreateFrame("Button", "NE_CollectionsMicroButton", parent)
  b:SetSize(32, 40)
  b:SetFrameStrata("MEDIUM")

  local bg = b:CreateTexture(nil, "BACKGROUND")
  bg:SetTexture(ICON_FILE)
  bg:SetTexCoord(unpack(BG.normal))
  bg:SetPoint("CENTER", b, "CENTER", -1, 1)
  bg:SetSize(32, 41)

  local bgPushed = b:CreateTexture(nil, "BACKGROUND")
  bgPushed:SetTexture(ICON_FILE)
  bgPushed:SetTexCoord(unpack(BG.pushed))
  bgPushed:SetPoint("CENTER", b, "CENTER", -1, 1)
  bgPushed:SetSize(32, 41)
  bgPushed:Hide()
  b:SetScript("OnMouseDown", function() bg:Hide(); bgPushed:Show() end)
  b:SetScript("OnMouseUp", function() bg:Show(); bgPushed:Hide() end)

  local n = b:CreateTexture(nil, "ARTWORK")
  n:SetTexture(ICON_FILE)
  n:SetTexCoord(unpack(COORDS.up))
  n:SetAllPoints(b)
  b:SetNormalTexture(n)

  local p = b:CreateTexture(nil, "ARTWORK")
  p:SetTexture(ICON_FILE)
  p:SetTexCoord(unpack(COORDS.down))
  p:SetAllPoints(b)
  b:SetPushedTexture(p)

  local h = b:CreateTexture(nil, "HIGHLIGHT")
  h:SetTexture(ICON_FILE)
  h:SetTexCoord(unpack(COORDS.mouseover))
  h:SetAllPoints(b)
  h:SetBlendMode("ADD")
  b:SetHighlightTexture(h)

  local d = b:CreateTexture(nil, "ARTWORK")
  d:SetTexture(ICON_FILE)
  d:SetTexCoord(unpack(COORDS.disabled))
  d:SetAllPoints(b)
  b:SetDisabledTexture(d)

  b:SetScript("OnClick", function()
    if NE.collections.Toggle then NE.collections.Toggle() end
  end)
  b:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_LEFT")
    GameTooltip:SetText("Collections")
    GameTooltip:Show()
  end)
  b:SetScript("OnLeave", function() GameTooltip:Hide() end)

  btn = b
  return b
end

-- Temporarily restore a DragonUI-noop'd button's real SetPoint, reposition it, then re-install
-- the no-op -- same pattern DragonUI itself uses when it needs to move one of its own buttons
-- after initial layout (see MainMenuBarBackpackButton handling in micromenu.lua).
local function setPointThroughNoop(button, ...)
  local dragon = NE.dragon
  local noop = dragon and dragon._noop
  local wasNooped = (noop ~= nil and button.SetPoint == noop)
  if wasNooped then button.SetPoint = UIParent.SetPoint end
  button:ClearAllPoints()
  button:SetPoint(...)
  if wasNooped then button.SetPoint = noop end
end

-- Native buttons from Character through LFD (inclusive), DragonUI's own left-to-right order
-- (micromenu.lua:112-124), nearest-to-the-gap first. These all shift one slot further left to
-- open a gap immediately left of PVP, where DragonUI's own MICRO_BUTTONS array already expects
-- Collections to sit.
local LEFT_CLUSTER_NAMES = {
  "LFDMicroButton", "SocialsMicroButton", "QuestLogMicroButton",
  "AchievementMicroButton", "TalentMicroButton", "SpellbookMicroButton", "CharacterMicroButton",
}

local function reposition()
  if not btn then return end

  local pvp = _G.PVPMicroButton
  local mainMenu = _G.MainMenuMicroButton
  local help = _G.HelpMicroButton
  local lfd = _G.LFDMicroButton
  local menu = _G.pUiMicroMenu
  if not (pvp and mainMenu and help and lfd and menu and pvp:IsVisible()) then
    btn:Hide()
    return
  end

  -- Live gap measured off Help/MainMenu -- NOT PVP/MainMenu. PVP is exactly the button
  -- encounterjournal/MicroButton.lua shifts left to open room for its own insertion between PVP
  -- and MainMenu, so whenever that module is active, PVP no longer sits its native one-gap
  -- distance from MainMenu -- measuring off it here would read a bloated ~2-gap distance and
  -- blow up every spacing this module computes (its own button, and the whole LFD..Character
  -- shift). Help/MainMenu are the two buttons NEITHER module ever moves, so they're a gap
  -- reference that stays a true single-unit gap regardless of which of these two modules are
  -- enabled or what order their repositioning runs in.
  local realGap = help:GetLeft() - mainMenu:GetRight()

  -- Sanity guard: DragonUI's skin may not have applied yet (buttons still at stock Blizzard
  -- positions). Bail and let the next scheduled retry (or the next real DragonUI refresh) catch
  -- it once the skin has actually settled.
  if realGap > 100 or realGap < -100 then
    btn:Hide()
    return
  end

  local menuScale = menu:GetEffectiveScale()
  local localGap = menuScale ~= 0 and (realGap / menuScale) or realGap

  -- PVP/MainMenu/Help are never touched -- our button sits immediately left of PVP, and the
  -- whole Character..LFD cluster shifts one slot further left (open screen space there) to make
  -- room.
  btn:ClearAllPoints()
  btn:SetPoint("BOTTOMRIGHT", pvp, "BOTTOMLEFT", -localGap, 0)
  btn:Show()

  local prev = btn
  for _, name in ipairs(LEFT_CLUSTER_NAMES) do
    local b = _G[name]
    if b then
      setPointThroughNoop(b, "BOTTOMRIGHT", prev, "BOTTOMLEFT", -localGap, 0)
      prev = b
    end
  end
end
NE.collections.RefreshMicroButton = reposition

-- The module ships disabled (DragonUI has its own collections UI), and this file's frames are built
-- outside the module dispatcher — so gate here too, or a disabled module still leaves a dead button
-- in the micromenu and shoves the whole Character..LFD cluster one slot left for nothing.
local function enabled()
  local C = NE.collections
  return not (C and C.IsEnabled) or C.IsEnabled()
end

local function init()
  if not enabled() then return end
  create()
  reposition()
end

local f = CreateFrame("Frame")
f:RegisterEvent("PLAYER_LOGIN")
f:RegisterEvent("UNIT_ENTERING_VEHICLE")
f:RegisterEvent("UNIT_EXITING_VEHICLE")
f:SetScript("OnEvent", function(_, event)
  if event == "PLAYER_LOGIN" then
    -- DragonUI applies its micromenu skin on the same event, but how long that actually takes to
    -- settle varies -- retry a few times over the first several seconds; reposition() is
    -- idempotent (recomputes fresh from current button positions, with its own sanity guard
    -- against an unsettled layout), so repeated calls are harmless and self-correcting.
    if C_Timer and C_Timer.After then
      C_Timer.After(1, init)
      C_Timer.After(3, reposition)
      C_Timer.After(6, reposition)
      C_Timer.After(10, reposition)
    else
      init()
    end
    f:UnregisterEvent("PLAYER_LOGIN")
  else
    reposition()
  end
end)

-- Track DragonUI's own relayouts (spacing/scale/grayscale/vehicle changes) instead of its private
-- layout internals -- these are the module's public refresh entry points.
do
  local dragon = NE.dragon
  if dragon then
    if dragon.RefreshMicromenu then hooksecurefunc(dragon, "RefreshMicromenu", reposition) end
    if dragon.RefreshMicromenuSystem then hooksecurefunc(dragon, "RefreshMicromenuSystem", reposition) end
    if dragon.RefreshMicromenuVehicle then hooksecurefunc(dragon, "RefreshMicromenuVehicle", reposition) end
  end
end
