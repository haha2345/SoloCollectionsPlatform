-- DragonUI_NewEra/modules/bags/Bags.lua — "Retail bags" style for the 3.3.5a bag windows.
--
-- DOWNPORT: distilled from NewEra (Classic 1.15) ContainerFrame/ContainerFrame.lua's restyle-in-
-- place path, plus knowledge of the 3.3.5a stock ContainerFrame structure taken from the
-- "Retail Bags" FrameXML downport. It RESTYLES the live Blizzard ContainerFrame1..N in place —
-- it does NOT replace item handling, anchoring, open/close, tooltips or cooldowns (all native and
-- left untouched). That keeps the module small, combat-safe, and impossible to break bag mechanics.
--
-- What it does, per bag window, matching the rest of DragonUI_NewEra's Dragonflight look:
--   * hides the stock UI-Bag-Components chrome (BackgroundTop/Middle1/Middle2/Bottom/1Slot)
--   * paints the shared dark rock Bg + applies the metal "HeldBagLayout" nineslice border
--   * seats the bag's own portrait icon into the metal top-left corner cutout (portrait.ApplyCutout)
--   * modernizes the close button to the RedButton-Exit family
--   * restyles the bag name with the shared centred-gold title (NE.panelchrome.SetTitle), matching
--     the combined bag + character/spellbook windows
--   * colours a per-item quality border (the retail coloured ring) — 3.3.5a's stock
--     ContainerFrame_Update never calls SetItemButtonQuality, so we drive it ourselves.
--   * red-tints items the player can't use (weapon/armor proficiency + under-level food/drink),
--     the same NE.bagskin.ApplyUsableTint the combined bag uses
--
-- DELIBERATELY OMITTED from the 1.15 original (each needs a retail-only system 3.3.5a lacks, so a
-- faithful port is a separate, larger effort): the single combined-bags window (grid engine is
-- present as core/ItemGrid.lua for a future pass), the currency/token border frame, the
-- right-click bag Menu (filters / cleanup / combined toggle — needs the retail Menu API), the
-- in-bag search box (needs BagSearchBoxTemplate), and the reskinned bag bar.
--
-- Reload-gated per Core/Modules.lua: disabled → not booted → stock Blizzard bags. We only ADD
-- chrome over the native frames, so "disabled" is simply "stock bags", no teardown needed.

local NE = DragonUI_NewEra
if not NE then return end

local MODULE = "bags"
NE.bags = NE.bags or {}
local B = NE.bags

local function log(msg)
  if NE.Log then NE.Log("BAGS", msg) end
end

-- ----------------------------------------------------------------------------
-- Constants / spec (3.3.5a stock ContainerFrame structure).
-- ----------------------------------------------------------------------------
local FRAME_COUNT       = NUM_CONTAINER_FRAMES or 13   -- ContainerFrame1..N
local MAX_ITEMS         = MAX_CONTAINER_ITEMS or 36    -- $parentItem1..36

-- Stock ARTWORK chrome textures that make up the classic bag frame — hidden so our metal border
-- shows instead. (Named $parent<suffix>; all built from Interface\ContainerFrame\UI-Bag-Components.)
local CHROME_SUFFIXES = {
  "BackgroundTop", "BackgroundMiddle1", "BackgroundMiddle2", "BackgroundBottom", "Background1Slot",
}

-- Portrait cutout geometry — MATCHES the combined bag exactly (size 60 seated at TOPLEFT{-5,8}) so
-- the bag's icon fills the metal ring instead of floating small inside it. The native
-- SetBagPortraitTexture still supplies the per-bag icon + circular crop; we only size/seat it.
local PORTRAIT_OPTS = { size = 60, layer = "ARTWORK", anchor = { "TOPLEFT", -5, 8 }, maskInset = { 1, 0, -1, 2 } }

-- The backpack (bag 0) has no per-bag inventory icon on 3.3.5a, so its portrait comes up blank.
-- Give it the same icon the combined window uses so the main bag has a proper portrait.
local BACKPACK_ICON = "Interface\\Icons\\Inv_misc_bag_08"

-- ----------------------------------------------------------------------------
-- Per-item skin: recessed slot cavity + quality ring (shared with the combined window via
-- NE.bagskin so both modules render identically). Skipped in combat for the FIRST skin of a button
-- (region creation), but re-colouring an already-skinned button is fine.
-- ----------------------------------------------------------------------------
local function styleItemButton(btn, bagID)
  if not btn then return end
  if not btn._neSlotRecess and InCombatLockdown() then return end
  if NE.bagskin then
    local slot = btn.GetID and btn:GetID()
    NE.bagskin.SkinButton(btn, btn.GetWidth and btn:GetWidth() or 37)
    NE.bagskin.ApplyQuality(btn, bagID, slot)
    -- Red-tint items the player can't use — unmet weapon/armor proficiency + food/drink below its
    -- required level — matching the combined bag. Always on here (individual bags have no options menu).
    NE.bagskin.ApplyUsableTint(btn, bagID, slot, true)
  end
end

-- Refresh every item button on a container frame (called after ContainerFrame_Update / generate).
local function styleItems(frame)
  if not frame or not frame.GetName then return end
  local name  = frame:GetName()
  local bagID = frame:GetID()
  local size  = frame.size or MAX_ITEMS
  for i = 1, size do
    styleItemButton(_G[name .. "Item" .. i], bagID)
  end
end
B.StyleItems = styleItems

-- ----------------------------------------------------------------------------
-- Frame chrome. Idempotent: the metal border / Bg persist once applied, so re-runs only re-hide
-- the classic chrome (which ContainerFrame_GenerateFrame re-shows on each open) and re-seat trim.
-- ----------------------------------------------------------------------------
local function hideClassicChrome(frame)
  local name = frame:GetName()
  for _, suffix in ipairs(CHROME_SUFFIXES) do
    local r = _G[name .. suffix]
    if r and r.Hide then r:Hide() end
  end
end

local function styleFrame(frame)
  if not frame or not frame.GetName then return end
  local name = frame:GetName()

  -- Always re-hide classic chrome — GenerateFrame re-shows it on every bag open.
  hideClassicChrome(frame)

  if not frame._neBagStyled then
    frame._neBagStyled = true

    -- Dark rock Bg + metal nineslice border (shared toolkit). ApplyModernChrome builds frame.Bg +
    -- frame.NineSlice; HeldBagLayout is the small-top-left-cutout metal variant used for held bags.
    if NE.chrome and NE.chrome.ApplyModernChrome then
      pcall(NE.chrome.ApplyModernChrome, frame, "HeldBagLayout")
    end

    -- Warm-dark backpack texture over the flat rock fill (matches the retail bag interior).
    if NE.bagskin and NE.bagskin.ApplyWindowBackground then
      pcall(NE.bagskin.ApplyWindowBackground, frame)
    end

    -- Portrait: seat the bag's own icon into the metal corner cutout.
    local portrait = _G[name .. "Portrait"]
    if portrait and NE.portrait and NE.portrait.ApplyCutout then
      pcall(NE.portrait.ApplyCutout, portrait, frame, PORTRAIT_OPTS)
    end

    -- Modern RedButton-Exit close button (reskin the EXISTING one — never create a duplicate).
    local close = _G[name .. "CloseButton"]
    if close and NE.panelchrome and NE.panelchrome.ModernizeCloseButton then
      pcall(NE.panelchrome.ModernizeCloseButton, close, { frameLevelBump = 10 })
    end

    -- Bag name → the shared panel-chrome title styling (GameFontNormal gold, centred in the title
    -- band between the portrait and close button), identical to the combined bag + character/spellbook
    -- windows. Pass text=nil so the bag keeps its own name and we only restyle/recentre it.
    local nameFS = _G[name .. "Name"]
    if nameFS then
      if NE.panelchrome and NE.panelchrome.TitleBand and NE.panelchrome.SetTitle then
        local band = NE.panelchrome.TitleBand(frame)
        NE.panelchrome.SetTitle(frame, nil, nameFS, band)
      else
        nameFS:ClearAllPoints()
        nameFS:SetPoint("TOPLEFT", frame, "TOPLEFT", 58, -10)
      end
      nameFS:SetDrawLayer("OVERLAY", 1)
    end
  end

  -- Backpack portrait fallback. Runs every call (the frame is reused for different bags): whenever
  -- this window is showing bag 0, stamp the bag icon into its otherwise-blank portrait; other bags
  -- keep their own native icon.
  if frame.GetID and frame:GetID() == 0 then
    local portrait = _G[name .. "Portrait"]
    if portrait then
      if SetPortraitToTexture then SetPortraitToTexture(portrait, BACKPACK_ICON)
      else portrait:SetTexture(BACKPACK_ICON) end
    end
  end
end
B.StyleFrame = styleFrame

-- Restyle whatever bag windows are already open (used on boot / re-enable).
local function styleOpen()
  for i = 1, FRAME_COUNT do
    local f = _G["ContainerFrame" .. i]
    if f and f:IsShown() then
      styleFrame(f)
      styleItems(f)
    end
  end
end
B.StyleOpen = styleOpen

-- ----------------------------------------------------------------------------
-- Boot: hook the stock container pipeline. hooksecurefunc runs AFTER Blizzard's body, so our
-- restyle re-asserts on top of every generate/update without interfering with item mechanics.
-- ----------------------------------------------------------------------------
local hooked = false
local function installHooks()
  if hooked then return end
  hooked = true

  if type(_G.ContainerFrame_GenerateFrame) == "function" then
    hooksecurefunc("ContainerFrame_GenerateFrame", function(frame)
      styleFrame(frame)
      styleItems(frame)
    end)
  else
    log("ContainerFrame_GenerateFrame missing; chrome will rely on OnShow hooks only")
  end

  if type(_G.ContainerFrame_Update) == "function" then
    hooksecurefunc("ContainerFrame_Update", function(frame) styleItems(frame) end)
  else
    log("ContainerFrame_Update missing; item quality borders will not auto-refresh")
  end

  -- OnShow safety net: catches any frame shown without going through GenerateFrame.
  for i = 1, FRAME_COUNT do
    local f = _G["ContainerFrame" .. i]
    if f and f.HookScript then
      f:HookScript("OnShow", function(self) styleFrame(self); styleItems(self) end)
    end
  end
end

local function boot()
  installHooks()
  styleOpen()   -- restyle anything already open (e.g. re-enable without a fresh open)
end
B.Boot = boot

-- ----------------------------------------------------------------------------
-- Register with Core/Modules.lua (reload-gated). conflictsWith the bag-replacement rivals so we
-- yield to Bagnon/ArkInventory/etc. when present (same policy as NewEra).
-- ----------------------------------------------------------------------------
if NE.modules and NE.modules.Register then
  NE.modules.Register{
    name    = MODULE,
    default = false,   -- superseded by the forced-on combined bag (CombinedBag.lua). Kept registered so
                       -- the per-window restyle can be re-enabled later; not booted by default.
    label   = NE.L["Retail bags"],
    category = "Windows",
    desc    = NE.L["Restyle the bag windows with the Dragonflight metal frame, portrait, and item "
           .. "quality borders. Disable to keep the stock Blizzard bags. Reload (/reload) to apply."],
    events  = { "PLAYER_LOGIN" },
    onBoot  = function() boot() end,
    conflictsWith = NE.modules.RIVALS and NE.modules.RIVALS.BAGS or nil,
  }
else
  log("NE.modules.Register absent; retail bags not booted")
end

-- ----------------------------------------------------------------------------
-- QA harness entry (optional; guarded). open/close drive the native bag toggles.
-- ----------------------------------------------------------------------------
if NE.qa then
  NE.qa.modules = NE.qa.modules or {}
  table.insert(NE.qa.modules, {
    name  = NE.L["Retail bags"],
    frame = _G.ContainerFrame1,
    open  = function() if OpenAllBags then OpenAllBags() elseif OpenBackpack then OpenBackpack() end end,
    close = function() if CloseAllBags then CloseAllBags() end end,
  })
end
