-- DragonUI_NewEra/modules/collections/Window.lua — the STANDALONE Collections WINDOW HOST.
--
-- A dedicated retail-style Collections journal (NE_CollectionsFrame), replacing the old
-- Mounts & Companions "Collection" view that used to live inside the Character panel's Pet tab
-- (modules/character/Companions.lua — now retired). Two bottom tabs, Mounts and Pet Journal, each a
-- self-contained "journal" pane built by Journal.lua over the raw 3.3.5a Companions API
-- (GetNumCompanions / GetCompanionInfo / CallCompanion / DismissCompanion) and enriched with the
-- ported source-info database (Data.lua) for the retail-looking right-hand info panel.
--
-- SHARED INTERFACE CONTRACT (Journal.lua depends on this — provided EXACTLY):
--   NE.collections.frame          the window Frame (global "NE_CollectionsFrame")
--   NE.collections.LeftInset      recessed panel that hosts the scrollable list
--   NE.collections.RightInset     recessed panel that hosts the model + info display
--   NE.collections.TopBand        thin strip under the title for count/search/filter/summon
--   NE.collections.BottomBand     strip under the insets for the Mount/Summon action button
--   NE.collections.activeKind     "MOUNT" or "CRITTER" (the GetCompanionInfo filter names)
--   NE.collections.RegisterJournal(kind, obj)   obj must expose :Show() :Hide() :Refresh()
--   NE.collections.Toggle()/.Open()/.SetShown(b)/.SelectTab(kind)
--
-- RULES (house style): only // -> -- comments; no SetShown widget method (Show/Hide); guard every
-- global; this is an INSECURE frame with no protected children, so no combat lockdown dance is
-- needed (unlike the spellbook's secure spell cards).

local NE = DragonUI_NewEra
NE.collections = NE.collections or {}
local C = NE.collections

local FRAME_NAME = "NE_CollectionsFrame"
local MODULE     = "Collections"

-- Enable gate. The module is registered default-OFF (DragonUI ships its own collections UI), and
-- "disabled" means "never booted" — but the show/toggle entry points below build the window lazily,
-- so a keybind or micro-button click would resurrect it past the boot gate. Every entry point checks
-- here instead. Reads NE.modules so the registered default applies when nothing is stored yet.
local function isModuleEnabled()
  if not (NE.modules and NE.modules.IsEnabled) then return true end
  return NE.modules.IsEnabled(MODULE) and true or false
end
C.IsEnabled = isModuleEnabled

-- Geometry (tunable). Portrait frame with a ~24px title band; a top strip for search/count/filter/
-- summon; twin recessed insets (narrow list on the left, wide model+info on the right); a bottom
-- strip for the action button. Bottom tabs hang BELOW the frame, character-panel style.
local FRAME_W    = 640
-- Reduced from 580 (owner feedback: "feels quite stretched height wise" — a screenshot showed a lot
-- of dead background below the list rows and below the model preview). Width is untouched; TOP_H/
-- BOTTOM_H/SIDE_PAD stay the same absolute pixel sizes, so the ~100px cut comes entirely out of the
-- two insets' available height (fewer rows per page, a somewhat smaller model viewport) rather than
-- out of any of the fixed chrome strips.
local FRAME_H    = 480
local TITLE_H    = 24
local TOP_H      = 34   -- search / count / filter / summon strip height
local BOTTOM_H   = 30   -- action-button strip height
local SIDE_PAD   = 14
local LEFT_W     = 244
local INSET_GAP  = 16

local TAB_H_INACTIVE = 36
local TAB_H_ACTIVE   = 42

-- ---------------------------------------------------------------------------
-- Logger + guard (NE.Log may be absent on a partial load).
-- ---------------------------------------------------------------------------
local function log(msg)
  if NE.Log then NE.Log("COLLECTIONS", msg); return end
  if DEFAULT_CHAT_FRAME then
    DEFAULT_CHAT_FRAME:AddMessage("|cffffcc55DragonUI_NewEra|r [collections]: " .. tostring(msg))
  end
end
C._log = log

local function guard(label, fn)
  local ok, err = pcall(fn)
  if not ok then log(label .. " failed: " .. tostring(err)) end
  return ok
end

-- Tab order + labels + portrait icon. "MOUNT"/"CRITTER" are the GetCompanionInfo filter names.
local TABS = {
  { key = "MOUNT",   label = _G.MOUNTS or "Mounts",  portrait = C.tex and C.tex.mountPortrait },
  { key = "CRITTER", label = "Pet Journal",          portrait = C.tex and C.tex.petPortrait  },
}

C.journals    = C.journals    or {}   -- kind -> journal object (Show/Hide/Refresh), set by Journal.lua
C._tabs       = C._tabs       or {}   -- kind -> tab button
C.activeKind  = C.activeKind  or "MOUNT"

function C.RegisterJournal(kind, obj)
  C.journals[kind] = obj
end

-- ---------------------------------------------------------------------------
-- Recessed inset (thin gold InsetFrameTemplate border + dark fill) — the same idiom every other
-- NE window uses (modules/lfg/Window.lua buildRail, modules/character/InsetFrames.lua).
-- ---------------------------------------------------------------------------
local function buildInset(name, parent)
  local inset = CreateFrame("Frame", name, parent)
  inset:SetFrameLevel((parent:GetFrameLevel() or 1) + 2)
  local bg = inset:CreateTexture(nil, "BACKGROUND")
  bg:SetPoint("TOPLEFT", 3, -3)
  bg:SetPoint("BOTTOMRIGHT", -3, 3)
  if bg.SetColorTexture then bg:SetColorTexture(0.05, 0.05, 0.06, 0.92)
  else bg:SetTexture(0.05, 0.05, 0.06, 0.92) end
  inset._bg = bg
  if NE.nineslice and NE.nineslice.ApplyLayout then
    pcall(NE.nineslice.ApplyLayout, inset, "InsetFrameTemplate")
  end
  return inset
end

-- ---------------------------------------------------------------------------
-- Portrait — the round Mount/Pet journal icon in the metal corner, swapped per active tab. Mirrors
-- the spellbook's own-portrait recipe (host on f.NineSlice at ARTWORK so it draws over the wood but
-- under the gold ring; apply the circular cutout mask, then set the flat icon texture).
-- ---------------------------------------------------------------------------
local function applyPortrait(f, path)
  if not f then return end
  local ringFrame = f.NineSlice or f
  if not f.portrait then f.portrait = ringFrame:CreateTexture(nil, "ARTWORK") end
  if NE.portrait and NE.portrait.ApplyCutout then pcall(NE.portrait.ApplyCutout, f.portrait, f) end
  if path then f.portrait:SetTexture(path) end
end

-- ---------------------------------------------------------------------------
-- Bottom tabs (Mounts / Pet Journal) — character-panel style: vanilla CharacterFrameTabButtonTemplate
-- reskinned to DF metal via NE.tabs.ReskinClassicTab, art driven manually (selected -> *Disabled/gold
-- pieces). Hang below the frame's BOTTOMLEFT.
-- ---------------------------------------------------------------------------
local function setTabArt(tab, selected)
  if not tab then return end
  local n = tab:GetName()
  local function set(suffix, show)
    local t = _G[n .. suffix]
    if t then if show then t:Show() else t:Hide() end end
  end
  set("Left",  not selected); set("Middle",  not selected); set("Right",  not selected)
  set("LeftDisabled", selected); set("MiddleDisabled", selected); set("RightDisabled", selected)
  local hl = tab._neCustomHL
  if hl then
    local a = selected and 0 or 0.4
    if hl.left   and hl.left.SetAlpha   then hl.left:SetAlpha(a)   end
    if hl.middle and hl.middle.SetAlpha then hl.middle:SetAlpha(a) end
    if hl.right  and hl.right.SetAlpha  then hl.right:SetAlpha(a)  end
  end
end

local function sizeTab(tab)
  if not tab then return end
  local text = _G[tab:GetName() .. "Text"]
  local w = 70
  if text then text:SetWidth(0); w = math.max(70, math.floor((text:GetWidth() or 0) + 30)) end
  tab:SetWidth(w)
end

local function rechainTabs(f)
  local prev
  for _, def in ipairs(TABS) do
    local tab = C._tabs[def.key]
    if tab then
      tab:ClearAllPoints()
      if prev then tab:SetPoint("TOPLEFT", prev, "TOPRIGHT", 1, 0)
      else tab:SetPoint("TOPLEFT", f, "BOTTOMLEFT", 14, 2) end
      prev = tab
    end
  end
end

local function buildTabs(f)
  for i, def in ipairs(TABS) do
    local name = FRAME_NAME .. "Tab" .. i
    local tab = C._tabs[def.key] or _G[name]
    if not tab then
      local ok, t = pcall(CreateFrame, "Button", name, f, "CharacterFrameTabButtonTemplate")
      if ok and t then tab = t else
        tab = CreateFrame("Button", name, f, "UIPanelButtonTemplate"); tab._nePlain = true
      end
      tab:SetID(i)
      tab.tabKey = def.key
      local txt = _G[name .. "Text"]
      if txt then txt:SetText(def.label) elseif tab.SetText then tab:SetText(def.label) end
      tab:SetScript("OnClick", function(self)
        if PlaySound then pcall(PlaySound, "igCharacterInfoTab") end
        C.SelectTab(self.tabKey)
      end)
      C._tabs[def.key] = tab
    end
    if not tab._nePlain and NE.tabs and NE.tabs.ReskinClassicTab then
      pcall(NE.tabs.ReskinClassicTab, name, {})
    end
    sizeTab(tab)
    tab:SetHeight(TAB_H_INACTIVE)
  end
  rechainTabs(f)
end

-- ---------------------------------------------------------------------------
-- Tab selection: swap art/height/level, portrait + title, and show the active journal (hide others).
-- ---------------------------------------------------------------------------
function C.SelectTab(kind)
  if not C._tabs[kind] then return end
  C.activeKind = kind
  local f = C.frame
  local baseLevel = (f and f:GetFrameLevel() or 1) + 2
  local activeDef
  for _, def in ipairs(TABS) do
    local tab = C._tabs[def.key]
    local on  = (def.key == kind)
    if def.key == kind then activeDef = def end
    if tab then
      setTabArt(tab, on)
      tab:SetHeight(on and TAB_H_ACTIVE or TAB_H_INACTIVE)
      sizeTab(tab)
      if tab.SetFrameLevel then tab:SetFrameLevel(baseLevel + (on and 8 or 0)) end
      local txt = _G[tab:GetName() .. "Text"]
      if txt then txt:ClearAllPoints(); txt:SetPoint("CENTER", tab, "CENTER", 0, on and -3 or 0) end
    end
  end
  rechainTabs(f)

  -- Portrait + title follow the active category (retail shows "Mounts" / "Pet Journal" in the bar).
  if activeDef then
    applyPortrait(f, activeDef.portrait)
    if NE.panelchrome and NE.panelchrome.SetTitle then NE.panelchrome.SetTitle(f, activeDef.label) end
  end

  -- Show the active journal, hide the rest, then refresh the one now in view.
  for k, j in pairs(C.journals) do
    if k == kind then if j.Show then j:Show() end else if j.Hide then j:Hide() end end
  end
  local jr = C.journals[kind]
  if jr and jr.Refresh then guard("journal refresh", function() jr:Refresh() end) end
end

-- ---------------------------------------------------------------------------
-- Build the window shell ONCE. Hidden by default.
-- ---------------------------------------------------------------------------
local function buildWindow()
  if C.frame then return C.frame end

  local f = CreateFrame("Frame", FRAME_NAME, UIParent)
  -- The red 3-slice is the addon's standard button; Watch keeps this window's panel buttons
  -- skinned as its panes are built (core/ButtonSkin.lua). Opt out per button with _neNoSkin.
  if NE.buttonskin and NE.buttonskin.Watch then pcall(NE.buttonskin.Watch, f) end
  f:SetSize(FRAME_W, FRAME_H)
  f:SetFrameStrata("HIGH")
  f:SetToplevel(true)
  f:Hide()
  C.frame = f

  -- Drag-to-move with saved position (account-wide, persists across /reload + sessions).
  if NE.FrameUtil and NE.FrameUtil.PersistWindowPosition then
    NE.FrameUtil.PersistWindowPosition(f, "collections",
      { point = "CENTER", relPoint = "CENTER", x = 0, y = 40 })
  else
    f:SetPoint("CENTER", UIParent, "CENTER", 0, 40)
    f:EnableMouse(true); f:SetMovable(true); f:SetClampedToScreen(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", function(self) self:StartMoving() end)
    f:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() end)
  end

  -- Open/close sounds via a child watcher (never on the frame itself).
  guard("sounds", function()
    if NE.FrameUtil and NE.FrameUtil.WirePanelSounds then
      NE.FrameUtil.WirePanelSounds(f, "igCharacterInfoOpen", "igCharacterInfoClose")
    end
  end)

  -- ESC closes it.
  guard("escClose", function()
    if NE.FrameUtil and NE.FrameUtil.EscClose then NE.FrameUtil.EscClose(FRAME_NAME)
    else tinsert(UISpecialFrames, FRAME_NAME) end
  end)

  -- Modern DF portrait chrome (nineslice + Rock bg + title). noPortrait: we own the portrait as the
  -- Mount/Pet journal icon, swapped per tab in SelectTab.
  guard("chrome.Apply", function()
    if NE.chrome and NE.chrome.Apply then
      NE.chrome.Apply(f, { layout = "PortraitFrameTemplate", title = _G.COLLECTIONS or "Collections", noPortrait = true })
    end
  end)
  -- PC.ApplyModernChrome tints its own f.Bg to 0.32 grey (a DOWNPORT fix for a different frame's
  -- first-paint colour flash), which reads noticeably darker than the plain, full-brightness
  -- UI-Background-Rock fill our other from-scratch standalone windows use (Guild/LFG/Professions/
  -- AuctionHouse/Social all build an untinted rock body). Retail's real Mount Journal outer frame
  -- is that same plain grey stone, so strip the tint back to full colour here to match.
  guard("bgTint", function()
    if f.Bg and f.Bg.SetVertexColor then f.Bg:SetVertexColor(1, 1, 1) end
  end)
  guard("portrait", function()
    applyPortrait(f, TABS[1].portrait)
    f:HookScript("OnShow", function(self) applyPortrait(self, (TABS[1] and TABS[1].portrait)) end)
  end)
  guard("closeButton", function()
    if NE.panelchrome and NE.panelchrome.ModernizeCloseButton and f.CloseButton then
      NE.panelchrome.ModernizeCloseButton(f.CloseButton, { frameLevelBump = 20 })
    end
  end)

  -- Top strip (count / search / filter / summon live here, built by the journals).
  local top = CreateFrame("Frame", nil, f)
  top:SetPoint("TOPLEFT", f, "TOPLEFT", SIDE_PAD, -(TITLE_H + 6))
  top:SetPoint("TOPRIGHT", f, "TOPRIGHT", -SIDE_PAD, -(TITLE_H + 6))
  top:SetHeight(TOP_H)
  top:SetFrameLevel((f:GetFrameLevel() or 1) + 3)
  C.TopBand = top

  -- Twin recessed insets.
  local left = buildInset(FRAME_NAME .. "LeftInset", f)
  left:SetPoint("TOPLEFT", f, "TOPLEFT", SIDE_PAD, -(TITLE_H + TOP_H + 8))
  left:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", SIDE_PAD, BOTTOM_H + 6)
  left:SetWidth(LEFT_W)
  C.LeftInset = left

  local right = buildInset(FRAME_NAME .. "RightInset", f)
  right:SetPoint("TOPLEFT", left, "TOPRIGHT", INSET_GAP, 0)
  right:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -SIDE_PAD, BOTTOM_H + 6)
  C.RightInset = right

  -- Bottom strip (the Mount/Summon action button lives here, built by the journals).
  local bottom = CreateFrame("Frame", nil, f)
  bottom:SetPoint("BOTTOMLEFT", left, "BOTTOMLEFT", 0, -(BOTTOM_H + 2))
  bottom:SetPoint("BOTTOMRIGHT", left, "BOTTOMRIGHT", 0, -(BOTTOM_H + 2))
  bottom:SetHeight(BOTTOM_H)
  bottom:SetFrameLevel((f:GetFrameLevel() or 1) + 3)
  C.BottomBand = bottom

  guard("tabs", function() buildTabs(f) end)

  return f
end
C.BuildWindow = buildWindow

-- ---------------------------------------------------------------------------
-- Show / hide / toggle.
-- ---------------------------------------------------------------------------
function C.SetShown(shown)
  if not isModuleEnabled() then return end
  local f = C.frame or buildWindow()
  if not f then return end
  if shown then
    f:Show()
    C.SelectTab(C.activeKind or "MOUNT")
  else
    f:Hide()
  end
end
function C.Open()   C.SetShown(true) end
function C.Show()   C.SetShown(true) end
function C.Hide()   C.SetShown(false) end
function C.Toggle()
  if not isModuleEnabled() then return end
  local f = C.frame or buildWindow()
  if not f then return end
  if f:IsShown() then C.SetShown(false) else C.SetShown(true) end
end

-- ---------------------------------------------------------------------------
-- Boot. PLAYER_LOGIN builds the shell then asks Journal.lua to build the two journals (guarded — it
-- loads after this file). Companion learn/update refresh the active journal only while shown.
-- ---------------------------------------------------------------------------
local function boot(event)
  if event == "PLAYER_LOGIN" then
    buildWindow()
    if C.BuildJournals then guard("buildJournals", C.BuildJournals) end
    -- Resting selection so the first open shows a populated Mounts tab.
    guard("selectInitial", function() C.SelectTab(C.activeKind or "MOUNT") end)
    return
  end
  if C.frame and C.frame:IsShown() then
    local jr = C.journals[C.activeKind]
    if jr and jr.Refresh then guard("refresh", function() jr:Refresh() end) end
  end
end
C.Boot = boot

if NE.modules and NE.modules.Register then
  NE.modules.Register(MODULE, {
    default  = false,  -- Default OFF: DragonUI now ships its own collections UI. Players opt in from
                       -- the "Windows" section of the options tab (integration/Options.lua).
    label    = "Collections",
    category = "Windows",
    desc     = "The modern Dragonflight Collections window (Mounts & Pet Journal). Off by default because DragonUI ships its own.",
    events   = {
      "PLAYER_LOGIN", "COMPANION_LEARNED", "COMPANION_UPDATE", "COMPANION_UNLEARNED",
    },
    onBoot = function(event) boot(event) end,
  })
else
  log("NE.modules.Register absent; collections window not booted")
end
