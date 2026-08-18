-- DragonUI_NewEra/modules/bags/BagSkin.lua — shared bag visual skin (asset reg + per-button skin
-- + window background), used by BOTH the per-window restyle (Bags.lua) and the combined window
-- (CombinedBag.lua) so the two render identically.
--
-- The defining "retail bags" look is the RECESSED SLOT CAVITY behind every item (the dark bordered
-- square each icon sits in). 3.3.5a item buttons only carry a thin outline (UI-Quickslot2), so we
-- hide it and draw the retail slot recess behind the icon. We use the target's OWN art
-- (BagsItemSlot.blp, from the Retail Bags downport) — a filled-centre recess, so the window bg
-- never bleeds through the slot. Every button also gets a quality ring (WhiteIconFrame, coloured by
-- core/ItemButton) and a search-dim overlay; the window fill is the tiled backpack background.

local NE = DragonUI_NewEra
if not NE then return end

NE.bagskin = NE.bagskin or {}
local BS = NE.bagskin

-- ----------------------------------------------------------------------------
-- Asset registration (guarded; NE.tex owns the API). The slot recess is a full-sheet atlas;
-- the backpack background is a plain texture (no atlas — set directly by path).
-- ----------------------------------------------------------------------------
local P = "Interface\\AddOns\\DragonUI_NewEra\\Textures\\Common\\"
-- The target's OWN slot art (from the Retail Bags downport): a recessed square with a FILLED dark
-- centre, so slots read clean and the window background never shows through them.
BS.SLOT_PATH        = P .. "BagsItemSlot.blp"
BS.SLOT_LOCKED_PATH = P .. "BagsItemSlotClose.blp"
-- Rarity-glow texture. The retail/modern "Interface\Common\WhiteIconFrame" is ABSENT on this client
-- (SetTexture silently no-ops → an invisible ring, which is why the combined window showed no glow);
-- UI-ActionButton-Border is a stock 3.3.5a soft-glow ring present on every client, ADD-blended and
-- tinted by quality colour it reads as the rarity glow.
BS.QUALITY_GLOW_PATH = "Interface\\Buttons\\UI-ActionButton-Border"
-- Window interior fill. Default: the SHARED dark rock body fill (NE.chrome.ApplyBodyFill /
-- PC.BODY_TINT) so the bag reads identically to the character panel and the rest of the window set —
-- one tint, tuned in one place, no drift.
BS.USE_SHARED_BODY_FILL = true
-- Set the above false to restore the bag's old bespoke look: the soft "marble" cloud texture
-- (UI-Background-Marble — near-black grey with gentle cloud variation) multiplied by a warm bronze
-- vertex tint, which leaned the window warm to echo the tightly-packed warm slot recesses. Tunable.
BS.BG_PATH          = P .. "9900002-ui-background-marble.blp"
BS.BG_TINT          = { 1.0, 0.82, 0.58 }   -- warm bronze wash over the grey marble (r,g,b multiply)

-- ----------------------------------------------------------------------------
-- Per-button skin. Idempotent. size = button edge (37 combined / native 37 per-window).
--   * hides the thin classic slot outline (NormalTexture)
--   * draws the recessed slot cavity on BACKGROUND, slightly larger than the button so adjacent
--     slots read as separated recesses (matches the retail grid)
--   * ensures an IconBorder region so core/ItemButton.ApplyQuality can colour a quality ring
-- ----------------------------------------------------------------------------
function BS.SkinButton(btn, size)
  if not btn then return end
  size = size or (btn.GetWidth and btn:GetWidth()) or 37

  -- Hide the default outline so only our recess frames the slot.
  local nt = btn.GetNormalTexture and btn:GetNormalTexture()
  if nt then nt:SetTexture(nil) end

  -- Recessed slot cavity (behind the icon) — filled-centre art so the window bg can't bleed through.
  local recess = btn._neSlotRecess
  if not recess then
    recess = btn:CreateTexture(nil, "BACKGROUND", nil, -1)
    btn._neSlotRecess = recess
  end
  recess:SetTexture(BS.SLOT_PATH)
  recess:SetTexCoord(0, 1, 0, 1)
  recess:ClearAllPoints()
  recess:SetPoint("TOPLEFT",     btn, "TOPLEFT",     -2, 2)
  recess:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT",  2, -2)
  recess:Show()

  -- Quality ring region (coloured later by ApplyQuality). Created at the TOP OVERLAY sublevel and
  -- OVERHANGING the button by 3px so the coloured ring sits in the inter-slot gap — never hidden
  -- behind the item icon (which the combined grid draws SetAllPoints over the whole button, which
  -- was swallowing a slot-sized ring and is why the combined window showed no rarity glow).
  if not btn.IconBorder then
    local b = btn:CreateTexture(nil, "OVERLAY", nil, 7)
    b:SetTexture(BS.QUALITY_GLOW_PATH)
    b:SetBlendMode("ADD")
    b:Hide()
    btn.IconBorder = b
  end
  -- UI-ActionButton-Border keeps its glow INSET within the texture (transparent margin), so the ring
  -- must be drawn a good bit LARGER than the slot for the visible glow to reach the slot edge. Overhang
  -- ~35% of the slot size on every side.
  local over = math.max(8, math.floor(size * 0.35 + 0.5))
  btn.IconBorder:ClearAllPoints()
  btn.IconBorder:SetPoint("TOPLEFT",     btn, "TOPLEFT",     -over,  over)
  btn.IconBorder:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT",  over, -over)

  -- Search-dim overlay (shown when this slot doesn't match the active search text).
  if not btn._neSearchDim then
    local d = btn:CreateTexture(nil, "OVERLAY", nil, 5)
    d:SetTexture(0, 0, 0, 0.7)
    d:SetAllPoints(btn)
    d:Hide()
    btn._neSearchDim = d
  end
end

-- Show/hide a slot's search dim. Also dims the quest-item border/glow (IconQuestTexture), which sits
-- ABOVE the dim overlay and otherwise stays bright on filtered-out items. The grid re-shows/positions
-- it on the next refresh (before this runs), so we only need to fade its alpha.
function BS.SetSearchDim(btn, dim)
  if not btn then return end
  if btn._neSearchDim then
    if dim then btn._neSearchDim:Show() else btn._neSearchDim:Hide() end
  end
  local qt = btn.IconQuestTexture or (btn.GetName and btn:GetName() and _G[btn:GetName() .. "IconQuestTexture"])
  if qt then qt:SetAlpha(dim and 0.25 or 1) end
  btn._neDim = dim and true or false
  if BS.ApplyGlowState then BS.ApplyGlowState(btn) end   -- fade the rarity glow to match the dimmed icon
end

-- "Can't use" detection. IsUsableItem does NOT catch armor/weapon PROFICIENCY (e.g. a Mail belt on a
-- class that can't wear Mail, or a weapon skill the player lacks). The reliable signal is the item
-- tooltip: Blizzard colours any UNMET requirement line (armor type, weapon skill, level, class,
-- reputation) red. We scan a hidden tooltip for a red left-line. Cached by itemID; the cache is
-- wiped when player state that changes usability changes (level/skill/talent/proficiency).
local unusableCache = {}
local usableScanTip
local RED_REQ = function(r, g, b) return r and g and b and r > 0.9 and g < 0.2 and b < 0.2 end

-- A line counts as an unmet-requirement red ONLY if it actually has text. GameTooltip:ClearLines()
-- clears line text but NOT the font strings' colour, and the right column is shared/pooled — so a
-- line the current item leaves empty can still carry a stale red from a previously-scanned unusable
-- item (e.g. a mace), which would falsely redden the next item (a belt, a bag). Guard on non-empty text.
local function lineIsRed(fs)
  if not fs then return false end
  local txt = fs:GetText()
  if not txt or txt == "" then return false end
  return RED_REQ(fs:GetTextColor())
end

local function scanUnusable(bagID, slot, itemID)
  if itemID and unusableCache[itemID] ~= nil then return unusableCache[itemID] end
  if not (bagID and slot) then return false end
  if not usableScanTip then
    usableScanTip = CreateFrame("GameTooltip", "NE_BagUsableScan", UIParent, "GameTooltipTemplate")
    usableScanTip:SetOwner(UIParent, "ANCHOR_NONE")
  end
  usableScanTip:ClearLines()
  local ok = pcall(usableScanTip.SetBagItem, usableScanTip, bagID, slot)
  local red = false
  if ok then
    -- Scan BOTH columns: unmet level/class/reputation lines are red on the LEFT, but a weapon/armor
    -- PROFICIENCY you lack (e.g. "Mace"/"Mail") is the item's subtype on the RIGHT — opposite the
    -- equip-slot line. Checking only the left column missed maces the player can't wield.
    for i = 2, (usableScanTip:NumLines() or 0) do   -- skip line 1 (the quality-coloured name)
      if lineIsRed(_G["NE_BagUsableScanTextLeft"  .. i])
         or lineIsRed(_G["NE_BagUsableScanTextRight" .. i]) then
        red = true; break
      end
    end
  end
  if itemID then unusableCache[itemID] = red end
  return red
end

-- Wipe the cache when the player's usability can change.
do
  local w = CreateFrame("Frame")
  for _, e in ipairs({ "PLAYER_LEVEL_UP", "SKILL_LINES_CHANGED", "CHARACTER_POINTS_CHANGED",
                       "LEARNED_SPELL_IN_TAB", "PLAYER_ENTERING_WORLD" }) do
    pcall(function() w:RegisterEvent(e) end)
  end
  w:SetScript("OnEvent", function() if wipe then wipe(unusableCache) else unusableCache = {} end end)
end

-- Red-tint the icon of an item the player can't use, when `enabled`. The item tooltip colours ANY
-- unmet requirement line red — weapon/armor proficiency, class, required level, AND a recipe's
-- required PROFESSION + skill level (also reputation, "already known", etc.) — so we scan the tooltip
-- for a red requirement line (both columns, non-empty text only, cached per itemID). One check covers
-- gear, level-gated food/drink, and recipes you can't learn (wrong/absent profession or skill too low).
-- The cache wipes on level-up / SKILL_LINES_CHANGED / LEARNED_SPELL_IN_TAB, so tints re-evaluate when
-- the player levels a profession or learns the recipe. Cleared to normal when disabled or usable.
function BS.ApplyUsableTint(btn, bagID, slot, enabled)
  if not btn then return end
  local red = false
  if enabled and bagID and slot and C_Container and C_Container.GetContainerItemInfo then
    local info = C_Container.GetContainerItemInfo(bagID, slot)
    if info and scanUnusable(bagID, slot, info.itemID) then red = true end
  end
  if SetItemButtonTextureVertexColor then
    if red then SetItemButtonTextureVertexColor(btn, 1.0, 0.30, 0.30)
    else SetItemButtonTextureVertexColor(btn, 1, 1, 1) end
  else
    local icon = btn.icon or (btn.GetName and _G[btn:GetName() .. "IconTexture"])
    if icon then
      if red then icon:SetVertexColor(1, 0.30, 0.30) else icon:SetVertexColor(1, 1, 1) end
    end
  end
  btn._neRed = red
  if BS.ApplyGlowState then BS.ApplyGlowState(btn) end   -- tint the rarity glow the same when unusable
end

-- Quality colour lookup: prefer the brighter ITEM_QUALITY_COLORS, fall back to BAG_ITEM_QUALITY_COLORS.
local function qualityColor(q)
  if not q then return nil end
  return (ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[q]) or (BAG_ITEM_QUALITY_COLORS and BAG_ITEM_QUALITY_COLORS[q])
end

-- Recompute the quality glow from every active filter so the ring matches the icon: base rarity
-- colour, multiplied by the "can't use" red tint (same factor the icon gets) and faded when the slot
-- is search-dimmed. State is stamped on the button by ApplyQuality/ApplyUsableTint/SetSearchDim.
local function applyGlowState(btn)
  local ib = btn and btn.IconBorder
  if not ib then return end
  local c = btn._neQualityColor
  if not c then ib:Hide(); return end
  local r, g, b = c.r, c.g, c.b
  if btn._neRed then r, g, b = r * 1.0, g * 0.30, b * 0.30 end   -- match the red unusable icon tint
  ib:SetVertexColor(r, g, b)
  ib:SetAlpha(btn._neDim and 0.30 or 1)                          -- match the search-dimmed icon
  ib:Show()
end
BS.ApplyGlowState = applyGlowState

-- Colour a button's quality ring (the WhiteIconFrame glow) from its container item. Self-contained —
-- it colours btn.IconBorder DIRECTLY rather than delegating to NE.itembutton, so the combined grid's
-- rings render even if that helper is unavailable/mistimed (they weren't showing before). The
-- container `quality` is unreliable on 3.3.5a (often -1 until the item is queried — the same quirk
-- that broke junk detection), so resolve from the item LINK via GetItemInfo when it's missing/negative.
-- Glows uncommon+ (quality >= 2), matching retail (common/poor get no visible ring).
function BS.ApplyQuality(btn, bagID, slot)
  if not btn then return end
  local border = btn.IconBorder or (btn.GetName and btn:GetName() and _G[btn:GetName() .. "IconBorder"])
  if not border then return end

  local quality
  if bagID and slot and C_Container and C_Container.GetContainerItemInfo then
    local info = C_Container.GetContainerItemInfo(bagID, slot)
    if info then
      quality = info.quality
      local link = info.hyperlink or info.itemID
      if (not quality or quality < 0) and link and GetItemInfo then
        quality = select(3, GetItemInfo(link))   -- 3rd return = quality; reliable for held items
      end
    end
  end

  local c = quality and quality >= 2 and qualityColor(quality)
  btn._neQualityColor = c or nil
  if c then
    border:SetTexture(BS.QUALITY_GLOW_PATH)
    border:SetBlendMode("ADD")
  end
  applyGlowState(btn)   -- colour/alpha honour the red + search-dim filters
end

-- ----------------------------------------------------------------------------
-- Item level number on a bag slot — drawn by DRAGONUI's item level module (its modules/itemlevel
-- .lua), not by us. It owns the font family/outline/size, the number's position, and the per-context
-- checkboxes in Options -> Enhancements -> Item Level; NewEra shipping a second implementation just
-- put two numbers on every icon (which is exactly what happened, and why ours was removed).
--
-- addon.UpdateItemLevelSlot(button, link, anchorTo, context) is its public per-button entry point —
-- the same one Bagster uses for its own recycled slots, so this is the supported seam rather than a
-- reach into its internals. It does ALL the gating itself (module enabled + the context's checkbox)
-- and hides the text when the slot is empty or the setting is off, so there is nothing to test here
-- and nothing to clean up when the player turns it off.
--
-- Silently absent on an older DragonUI without the module: no number, no error.
-- ----------------------------------------------------------------------------
-- The bag menu's item level checkbox IS the "Enable Item Level" checkbox in Options ->
-- Enhancements -> Item Level. Not a mirror, not a copy: the same single flag
-- (profile.modules.itemlevel.enabled), read and written through DragonUI's own accessors, with the
-- same side effects its setFunc runs. Flip either one and the other is already showing the new
-- state next time it's drawn, because there is only one value in existence.
--
-- Being the MASTER switch, it governs every frame the module draws on — this bag, the character
-- panel, bank, merchant, loot, mail and the rest. DragonUI's per-frame checkboxes underneath it are
-- untouched and keep working as the finer control.
local ITEMLEVEL_MODULE = "itemlevel"

-- False only when DragonUI has no item level module at all (an older build) — then there is no
-- checkbox to be in sync with, and the menu entry greys out instead of pretending.
function BS.CanToggleItemLevel()
  local d = NE.dragon
  return (d and d.RefreshItemLevel and d.IsModuleEnabled) and true or false
end

-- Exactly what the options checkbox's getFunc reads: addon:IsModuleEnabled("itemlevel").
function BS.IsItemLevelShown()
  if not BS.CanToggleItemLevel() then return false end
  local d = NE.dragon
  local ok, enabled = pcall(d.IsModuleEnabled, d, ITEMLEVEL_MODULE)
  return (ok and enabled) and true or false
end

-- Where the flag lives. The options checkbox writes EnsureModuleTable("itemlevel"), which is
-- addon.PanelControls:EnsureModuleTable — so when DragonUI_Options is loaded we call that method
-- itself rather than reimplementing it. Only if the options addon isn't loaded (it's OptionalDeps +
-- load-on-demand) do we walk the profile ourselves, which is all that method does anyway.
local function itemLevelConfigTable()
  local d = NE.dragon
  if not d then return nil end

  local C = d.PanelControls
  if C and type(C.EnsureModuleTable) == "function" then
    local ok, tbl = pcall(C.EnsureModuleTable, C, ITEMLEVEL_MODULE)
    if ok and type(tbl) == "table" then return tbl end
  end

  if not (d.db and d.db.profile) then return nil end
  local profile = d.db.profile
  profile.modules = profile.modules or {}
  profile.modules[ITEMLEVEL_MODULE] = profile.modules[ITEMLEVEL_MODULE] or {}
  return profile.modules[ITEMLEVEL_MODULE]
end

-- The options checkbox's setFunc, step for step:
--   EnsureModuleTable("itemlevel").enabled = val
--   if val then addon.ApplyItemLevelSystem() end     -- re-installs the module's hooks
--   addon:RefreshItemLevel()                         -- repaints, or tears the system back down
-- Anything less and the two controls would behave differently for the same flag, which is the whole
-- thing this is meant to avoid.
function BS.SetItemLevelShown(on)
  local cfg = itemLevelConfigTable()
  if not cfg then return end
  cfg.enabled = on and true or false

  -- RefreshItemLevel repaints the character slots for us: its UpdateAll -> UpdateAllCharacterSlots
  -- walks the stock Character*Slot globals, which our panel REPARENTS rather than replaces, so they
  -- are the very buttons on screen. Only the bag grid needs the extra nudge below, because those
  -- buttons are ours and DragonUI has never heard of them.
  local d = NE.dragon
  if on and d.ApplyItemLevelSystem then pcall(d.ApplyItemLevelSystem) end
  if d.RefreshItemLevel then pcall(d.RefreshItemLevel, d) end

  -- Redraw the options window if it's sitting on the Enhancements tab, so its "Enable Item Level"
  -- checkbox visibly follows this click instead of showing the old state until you switch tabs.
  -- SelectTab on the CURRENT tab is DragonUI's own rebuild path and preserves the scroll offset —
  -- its comment calls out "a toggle refreshing disabled states", which is exactly this.
  local P = d.OptionsPanel
  if P and P.SelectTab and P.currentTab == "enhancements"
     and P.frame and P.frame.IsShown and P.frame:IsShown() then
    pcall(P.SelectTab, P, "enhancements")
  end

  -- Repaint our own grid DIRECTLY rather than trusting the RefreshItemLevel hook to do it.
  -- RefreshItemLevel hides every text it owns (ours included) and then re-runs only ITS update
  -- paths; the hook in CombinedBag is what normally brings ours back, but this is the one caller
  -- that must not depend on that hook having registered. Calling both is harmless — the repaint is
  -- idempotent — and it means the menu entry works even if the hook never took.
  if NE.combinedbag and NE.combinedbag.Refresh then pcall(NE.combinedbag.Refresh) end
end

-- ----------------------------------------------------------------------------
-- ONE-TIME REPAIR of state earlier builds of this menu left behind.
--
-- Before it drove the master switch, this checkbox wrote DragonUI's PER-FRAME context flags —
-- first "bags", then "bags" plus "character". Anyone who clicked it off in one of those builds
-- still has those flags false in their saved profile, and the master switch it drives now cannot
-- clear them: the module reports itself enabled while IsContextEnabled("bags") stays false, so the
-- numbers are simply absent from the bag with nothing on screen to explain why.
--
-- Set the two flags we ever wrote back to DragonUI's own default (on), exactly once, tracked by a
-- flag in OUR db so it can never fight a deliberate choice made afterwards in the options panel.
-- Bails without marking itself done if the config isn't reachable yet, so it retries next login.
-- ----------------------------------------------------------------------------
local function repairStompedContexts()
  if not NE.db or NE.db.itemLevelContextRepair then return end
  local cfg = itemLevelConfigTable()
  if not cfg then return end
  NE.db.itemLevelContextRepair = true
  cfg.bags, cfg.character = true, true
  local d = NE.dragon
  if d and d.RefreshItemLevel then pcall(d.RefreshItemLevel, d) end
end

local repairBoot = CreateFrame("Frame")
repairBoot:RegisterEvent("PLAYER_LOGIN")
repairBoot:SetScript("OnEvent", function(self)
  pcall(repairStompedContexts)
  self:UnregisterAllEvents()
end)

function BS.ApplyItemLevel(btn, bagID, slot)
  if not btn then return end
  local dragon = NE.dragon
  if not (dragon and dragon.UpdateItemLevelSlot) then return end

  -- Stock global, matching DragonUI's own container path — no compat shim in the way.
  local link
  if bagID and slot and GetContainerItemLink then
    link = GetContainerItemLink(bagID, slot)
  end

  -- Bank bags are their own checkbox over there; mirror its ContainerContext() split exactly.
  local context = (bagID and bagID >= 5 and bagID <= 11) and "bank" or "bags"
  pcall(dragon.UpdateItemLevelSlot, btn, link, nil, context)
end

-- ----------------------------------------------------------------------------
-- Window content background, inside the metal border. Applied on top of ApplyModernChrome's
-- frame.Bg (which we retexture). Idempotent.
-- ----------------------------------------------------------------------------
function BS.ApplyWindowBackground(frame)
  if not frame then return end

  -- Shared dark rock fill — the same texture and PC.BODY_TINT the character panel body uses, so the
  -- two windows match. ApplyBodyFill already handles the missing-art degrade (a solid near-black),
  -- so a false return still leaves a DARK frame — don't fall through to the warm marble there, or a
  -- client without the rock sheet would be the only one showing the old bronze bag.
  if BS.USE_SHARED_BODY_FILL and NE.chrome and NE.chrome.ApplyBodyFill then
    NE.chrome.ApplyBodyFill(frame)
    return
  end

  local bg = frame.Bg
  if not bg then
    bg = frame:CreateTexture(nil, "BACKGROUND")
    bg:SetPoint("TOPLEFT", 4, -4)
    bg:SetPoint("BOTTOMRIGHT", -4, 4)
    frame.Bg = bg
  end
  -- STRETCH the soft marble across the interior. DOWNPORT: tiling (SetHorizTile + wrap modes) turned
  -- the fill black on 3.3.5a here; the plain-stretch path is what actually rendered. Marble is a soft
  -- cloud with no hard pattern, so a stretch (downscale from 1024²) reads clean, not distorted.
  if bg.SetHorizTile then bg:SetHorizTile(false) end
  if bg.SetVertTile  then bg:SetVertTile(false) end
  bg:SetTexture(BS.BG_PATH)
  bg:SetTexCoord(0, 1, 0, 1)
  local t = BS.BG_TINT or { 1, 1, 1 }
  bg:SetVertexColor(t[1], t[2], t[3])   -- warm the grey marble toward the retail bronze
  bg:Show()
end
