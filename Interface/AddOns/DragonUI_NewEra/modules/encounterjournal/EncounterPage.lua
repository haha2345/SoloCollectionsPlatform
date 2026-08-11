-- DragonUI_NewEra/modules/encounterjournal/EncounterPage.lua — the encounter view, data-driven
-- from NE.ej.DATA. Left lore/instance panel + right full-width info panel (book bg + info tabs
-- + boss list + per-boss content).
--
-- DOWNPORT of NewEra/EncounterJournal/EncounterPage.lua (Classic 1.15) onto 3.3.5a:
--   * ModelScene → gone (Cata+ widget). The PlayerModel FALLBACK path is now the PRIMARY:
--     boss models load via Model:SetCreature(displayID) (proven on this client by
--     ezCollections; NOT SetDisplayInfo — on this custom client that method takes a raw
--     model M2 FileID, not a creatureDisplayID, per WeakAuras' own compat shim, so calling
--     it with a displayID silently "succeeds" while rendering nothing). The retail
--     auto-fit camera (SetPortraitZoom / SetCameraPosition — none exist here) is emulated by
--     offsetting the MODEL from the fixed default camera using the generated per-boss
--     MODEL_CAM table (cdist/ctz), with MODEL_TWEAKS + tunable globals for outliers.
--   * Drag-rotate: Era's Model_OnMouseDown/_OnUpdate handlers don't exist on 3.3.5a — a small
--     cursor-delta OnUpdate drives Model:SetFacing instead.
--   * Dropdowns (loot slot filter + TBC Normal/Heroic): WowStyle1 DropdownButton →
--     NE.ej.CreateDropdown (Support.lua).
--   * SetShown → Show/Hide (3.3.5a hard rule); Button:SetEnabled → Enable/Disable.
--   * All UIPanelScrollFrameTemplate frames are NAMED (template OnLoad does _G name lookups).
--   * Loot rows: NE_EncounterItemTemplate XML (mixin attr is Legion+) → NE.ej.CreateLootRow.
--   * GET_ITEM_INFO_RECEIVED doesn't fire on 3.3.5a → uncached loot is primed via a hidden
--     tooltip (server item query) and the visible list re-renders on a short C_Timer poll.
--   * "Defeated this week": GetSavedInstanceEncounterInfo is Cata+ → feature degrades to off
--     (guarded); checkmark art = native ReadyCheck-Ready (no map-markeddefeated atlas here).
--   * "Show Map": 3.3.5a has no dungeon maps for Classic/TBC instances (WotLK-only) and no
--     WorldMapFrame:SetMapID — the button is hidden unless a NE.worldmap.ShowDungeonMap
--     provider appears later (guarded call kept).
--   * GetSpellTexture(spellID) can't resolve arbitrary ids on 3.3.5a → select(3, GetSpellInfo).
--
-- Layout transcribed from retail Cata Blizzard_EncounterJournal.xml:1307-1610 (12.0.5.67451).

local NE = DragonUI_NewEra
if not NE then return end

NE.ej = NE.ej or {}

local selInst, selBoss   -- module state: current instance + boss tables

-- 3.3.5a: no Region:SetShown.
local function setShown(o, on)
  if on then o:Show() else o:Hide() end
end

-- GameFontBlack may be absent on 3.3.5a; dark parchment color is set explicitly at use sites.
local BLACK_FONT = _G.GameFontBlack and "GameFontBlack" or "GameFontHighlightSmall"

-- Difficulty-toggle cluster geometry. The tab (p.diffPanel) wraps whichever toggles are visible, so
-- its width is derived here rather than hardcoded per case; buildInfoPanel builds the widgets and
-- refreshView picks the width.
--
-- The tab is built from the SAME DF metal art as the Dungeons/Raids bottom tabs (core/Tabs.lua's
-- ATLAS_BY_SUFFIX). Those atlases are drawn flat-edge-at-top, tapering at the bottom — which is the
-- shape for something hanging DOWN off the frame's top border, so they are used unflipped (no
-- MakeTopTab crop). Native art is 36 tall; DIFF_TAB_SCALE shrinks every piece and every anchor
-- offset together so the proportions survive.
local DIFF_TAB_NATIVE_H   = 36
local DIFF_TAB_H          = 28
local DIFF_TAB_SCALE      = DIFF_TAB_H / DIFF_TAB_NATIVE_H
local function tabScaled(n) return math.floor(n * DIFF_TAB_SCALE + 0.5) end
-- Native piece widths / anchor overshoots, straight from core/Tabs.lua.
local DIFF_TAB_LEFT_W     = tabScaled(35)
local DIFF_TAB_RIGHT_W    = tabScaled(37)
local DIFF_TAB_LEFT_X     = -tabScaled(3)
local DIFF_TAB_RIGHT_X    = tabScaled(7)

local DIFF_PANEL_PAD      = 8    -- keeps the toggles off the tapered shoulders
local DIFF_PANEL_GAP      = 2
local SIZE_TOGGLE_W       = 36
local HEROIC_TOGGLE_W     = 30
local DIFF_TOGGLE_H       = 18
local DIFF_PANEL_H        = DIFF_TAB_H
local DIFF_TOGGLE_DROP    = 3    -- the taper is at the BOTTOM, so sit above centre
local DIFF_RIGHT_PAD      = DIFF_PANEL_PAD
local function diffPanelWidth(showSize, showHeroic)
  local w = DIFF_PANEL_PAD * 2
  if showSize   then w = w + SIZE_TOGGLE_W   end
  if showHeroic then w = w + HEROIC_TOGGLE_W end
  if showSize and showHeroic then w = w + DIFF_PANEL_GAP end
  return w
end
local DIFF_PANEL_W_BOTH = diffPanelWidth(true, true)

local function sliceTex(parent, slice, layer, setSize)
  local t = parent:CreateTexture(nil, layer or "ARTWORK")
  NE.ej.ApplySlice(t, slice, setSize)
  return t
end

local function makeTab(parent, id, iconSel, iconUnsel, tip)
  local t = CreateFrame("Button", nil, parent)
  t:SetSize(63, 57)
  local n = sliceTex(t, "UI-EJ-Tab-UnSelected"); n:SetAllPoints(t); t:SetNormalTexture(n)
  local h = sliceTex(t, "UI-EJ-Tab-Highlight");  h:SetAllPoints(t); h:SetBlendMode("ADD"); t:SetHighlightTexture(h)
  -- Explicit sublevel: the normal texture above is ARTWORK too, and with both at the default
  -- sublevel the selected art has no guaranteed precedence over the unselected art beneath it.
  t.selBG = sliceTex(t, "UI-EJ-Tab-Selected", "ARTWORK"); t.selBG:SetAllPoints(t); t.selBG:Hide()
  t.selBG:SetDrawLayer("ARTWORK", 2)
  t.unselIcon = sliceTex(t, iconUnsel, "OVERLAY", true); t.unselIcon:SetPoint("RIGHT", t, "RIGHT", -6, 0)
  t.selIcon   = sliceTex(t, iconSel,   "OVERLAY", true); t.selIcon:SetPoint("CENTER", t.unselIcon, "CENTER", 0, 0); t.selIcon:Hide()
  t.tabID = id
  t:SetScript("OnClick", function()
    if PlaySound then pcall(PlaySound, "igCharacterInfoTab") end
    NE.ej.SelectTab(id)
  end)
  if tip then
    NE.tooltip.Wire(t, tip)
  end
  return t
end

-- Left lore/instance panel (the instance landing on the right page)
local function buildLorePanel(enc)
  local p = CreateFrame("Frame", "NE_EncounterJournalInstanceFrame", enc)
  p:SetSize(390, 425)
  p:SetPoint("BOTTOMRIGHT", enc, "BOTTOMRIGHT", -1, 2)
  enc.instance = p

  -- Loading-screen artwork at the TOP (per-instance LoreFileDataID set in PopulateEncounter).
  local loreBG = p:CreateTexture(nil, "BACKGROUND")
  loreBG:SetTexture(NE.tex.localFiles[527422] or 527422)   -- UI-EJ-LOREBG-Default placeholder
  loreBG:SetSize(390, 330)
  loreBG:SetPoint("TOP", p, "TOP", 3, -9)
  loreBG:SetTexCoord(0, 0.7617187, 0, 0.65625)   -- retail crop (same for default + per-instance)
  p.loreBG = loreBG

  -- Name plate + dungeon name near the TOP of the artwork.
  local titleBG = sliceTex(p, "UI-EJ-DungeonNameBg", "ARTWORK", true)   -- 256x64 native
  titleBG:SetPoint("TOP", loreBG, "TOP", 0, -38)
  p.titleBG = titleBG

  local title = p:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
  title:SetWidth(256); title:SetJustifyH("CENTER")
  title:SetPoint("CENTER", titleBG, "CENTER", 0, 1)
  NE.font.Set(title, NE.font.MORPHEUS, 24, "", GameFontNormalHuge or GameFontNormalLarge)
  title:SetShadowColor(0, 0, 0, 1); title:SetShadowOffset(1, -1)
  p.title = title

  -- Show-Map button at the BOTTOM. DOWNPORT: hidden — no dungeon maps for Classic/TBC
  -- instances on the 3.3.5a client. Re-shown automatically if a NE.worldmap.ShowDungeonMap
  -- provider is ported later (see PopulateEncounter).
  local map = CreateFrame("Button", nil, p)
  map:SetSize(48, 32)
  map:SetPoint("BOTTOMLEFT", p, "BOTTOMLEFT", 33, 126)
  local mapBG = sliceTex(map, "UI-EJ-ShowMapBG", "BACKGROUND", true)
  mapBG:SetPoint("LEFT", map, "LEFT", -3, 5)
  local mapTex = map:CreateTexture(nil, "ARTWORK")
  mapTex:SetTexture("Interface\\QuestFrame\\UI-QuestMap_Button")
  mapTex:SetSize(48, 32); mapTex:SetPoint("RIGHT", map, "RIGHT", 0, 0)
  mapTex:SetTexCoord(0.125, 0.875, 0.0, 0.5)
  local mapText = map:CreateFontString(nil, "ARTWORK", "GameFontNormal")
  mapText:SetPoint("LEFT", map, "RIGHT", 2, 0)
  mapText:SetText(ENCOUNTER_JOURNAL_SHOW_MAP or "Show Map")
  map:SetScript("OnClick", function() if NE.ej.ShowMap then NE.ej.ShowMap() end end)
  NE.tooltip.Wire(map, ENCOUNTER_JOURNAL_SHOW_MAP or "Show Map")
  map:Hide()
  p.mapButton = map

  -- Lore text — retail LoreScrollingFont 315x95 BOTTOMLEFT(35,5); arrows-only scrollbar.
  local loreScroll = CreateFrame("ScrollFrame", "NE_EJLoreScroll", p, "UIPanelScrollFrameTemplate")
  loreScroll:SetSize(315, 95)
  loreScroll:SetPoint("BOTTOMLEFT", p, "BOTTOMLEFT", 35, 5)
  loreScroll.ScrollBar = loreScroll.ScrollBar or _G["NE_EJLoreScrollScrollBar"]   -- DOWNPORT
  local loreChild = CreateFrame("Frame", nil, loreScroll)
  loreChild:SetSize(315, 1)
  loreScroll:SetScrollChild(loreChild)
  local lore = loreChild:CreateFontString(nil, "ARTWORK", BLACK_FONT)
  lore:SetWidth(315)
  lore:SetJustifyH("LEFT"); lore:SetJustifyV("TOP")
  lore:SetTextColor(0.25, 0.1484375, 0.02)
  lore:SetPoint("TOPLEFT", loreChild, "TOPLEFT", 0, 0)
  if NE.scrollbar and NE.scrollbar.Reskin then NE.scrollbar.Reskin(loreScroll, { hideIfUnscrollable = true }) end
  -- arrows-only: hide the thumb + track so only the two arrows show (retail lore look)
  local sbb = loreScroll.ScrollBar or _G["NE_EJLoreScrollScrollBar"]
  if sbb then
    local th = sbb.GetThumbTexture and sbb:GetThumbTexture(); if th then th:SetAlpha(0) end
    for _, k in ipairs({ "_neThumbCapTop", "_neThumbCapBot", "_neTrackBegin", "_neTrackEnd", "_neTrackMiddle" }) do
      if sbb[k] then sbb[k]:SetAlpha(0) end
    end
  end
  p.lore = lore
  p.loreChild = loreChild
end

-- Right info panel: book bg, header, info tabs, boss list (scroll), content area
local function buildInfoPanel(enc)
  local p = CreateFrame("Frame", "NE_EncounterJournalInfoFrame", enc)
  p:SetSize(785, 425)
  p:SetPoint("BOTTOMRIGHT", enc, "BOTTOMRIGHT", -1, 2)
  enc.info = p

  local bg = p:CreateTexture(nil, "BACKGROUND")
  bg:SetTexture(NE.tex.localFiles[521750] or 521750)   -- UI-EJ-JournalBG
  bg:SetSize(785, 425)
  bg:SetPoint("BOTTOMRIGHT", p, "BOTTOMRIGHT", 0, 0)
  bg:SetTexCoord(0, 0.766601562, 0, 0.830078125)

  -- Two page-header strips span the full two-page width.
  local lh = sliceTex(p, "UI-EJ-LeftPageHeader", "BACKGROUND", true)
  lh:SetDrawLayer("BACKGROUND", 3)
  lh:SetPoint("TOPLEFT", p, "TOPLEFT", 0, -11)
  local rh = sliceTex(p, "UI-EJ-RightPageHeader", "BACKGROUND", true)
  rh:SetDrawLayer("BACKGROUND", 3)
  rh:SetPoint("TOPRIGHT", p, "TOPRIGHT", 0, -11)
  p.rightHeader = rh

  -- Header titles: dungeon name (left page) + boss name (right page).
  p.instanceTitle = p:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  p.instanceTitle:SetPoint("TOPLEFT", p, "TOPLEFT", 70, -16)
  p.instanceTitle:SetWidth(310); p.instanceTitle:SetJustifyH("LEFT"); p.instanceTitle:SetTextColor(1, 0.82, 0)
  NE.font.Set(p.instanceTitle, NE.font.MORPHEUS, 16, "", GameFontNormal)
  p.encounterTitle = p:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
  p.encounterTitle:SetPoint("TOPLEFT", p, "TOPLEFT", 400, -14)
  p.encounterTitle:SetWidth(360); p.encounterTitle:SetJustifyH("CENTER"); p.encounterTitle:SetTextColor(1, 0.82, 0)
  NE.font.Set(p.encounterTitle, NE.font.MORPHEUS, 15, "", GameFontNormalLarge)

  -- Loot slot-filter dropdown (right page header; shown only on the Loot tab). Fully
  -- pcall-wrapped: non-critical chrome must not abort buildInfoPanel.
  pcall(function()
    local lootFilter = NE.ej.CreateDropdown(p, "NE_EJLootFilterDropdown", 84)   -- 30% off the old 120
    lootFilter:SetPoint("TOPRIGHT", p, "TOPRIGHT", -2, -10)
    lootFilter:SetDefaultText(ALL or "All")
    lootFilter:SetupMenu(function(dropdown, root)
      -- Only offer categories the current loot actually has (retail skips empty ones). `p` is
      -- passed so the list is narrowed to the selected difficulty/size as well — the menu is
      -- rebuilt on every open, so it tracks the toggles without needing to be told.
      local present = NE.ej.PresentLootCategories(p.lootSource, p)
      for _, fl in ipairs(NE.ej.LOOT_FILTERS) do
        local key, label = fl[1], fl[2]
        if key == "ALL" or present[key] then
          root:CreateRadio(label,
            function() return (p.lootSlot or "ALL") == key end,
            function()
              p.lootSlot = key
              if dropdown.SetDefaultText then dropdown:SetDefaultText(label) end
              if NE.ej.SelectTab then NE.ej.SelectTab(p.selectedTab or 2) end
            end)
        end
      end
    end)
    lootFilter:Hide()
    p.lootFilter = lootFilter

    -- Quick-clear "X" — only up while a real slot filter is active, since an unfiltered dropdown
    -- has nothing to clear. Anchored off the dropdown's own arrow BUTTON rather than the frame:
    -- UIDropDownMenuTemplate's frame edges sit ~16px outside the visible box on both sides, so
    -- "RIGHT of the frame" would leave a conspicuous gap. The arrow button is flush with the
    -- visible right edge and already vertically centred on the box.
    local clear = CreateFrame("Button", nil, lootFilter)
    clear:SetSize(16, 16)
    local ddArrow = _G[lootFilter:GetName() .. "Button"]
    clear:SetPoint("LEFT", ddArrow or lootFilter, "RIGHT", 4, 0)
    -- Same clear art as the Professions recipe search and the AH browse box: the
    -- common-search-clearbutton atlas, with their identical minimize-button fallback.
    local ctex = clear:CreateTexture(nil, "OVERLAY")
    ctex:SetAllPoints(clear)
    if not (NE.tex and NE.tex.SetAtlas and NE.tex.SetAtlas(ctex, "common-search-clearbutton", false)) then
      ctex:SetTexture("Interface\\Buttons\\UI-Panel-MinimizeButton-Up")
    end
    ctex:SetAlpha(0.8)
    clear:SetScript("OnEnter", function(self)
      ctex:SetAlpha(1)
      GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
      GameTooltip:SetText(_G.CLEAR_ALL or _G.RESET or "Clear Filter")
      GameTooltip:Show()
    end)
    clear:SetScript("OnLeave", function() ctex:SetAlpha(0.8); GameTooltip:Hide() end)
    clear:SetScript("OnClick", function()
      if PlaySound and SOUNDKIT then PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON) end
      p.ResetLootFilter()
      if NE.ej.SelectTab then NE.ej.SelectTab(p.selectedTab or 2) end
    end)
    clear:Hide()
    p.lootFilterClear = clear
  end)

  -- Drop back to "All Slots". Shared by the clear button and by the difficulty toggles, which
  -- reset it because a 10M table is not the 25H one: a slot filter carried across the switch can
  -- silently empty the loot page and read as "this difficulty drops nothing".
  function p.ResetLootFilter()
    p.lootSlot = "ALL"
    local dd = p.lootFilter
    if dd then
      -- Picking a slot overwrites the dropdown's _defaultText (see SetupMenu above), so put the
      -- "All Slots" label back before asking it to re-read its collapsed text.
      local fl = NE.ej.LOOT_FILTERS
      dd._defaultText = (fl and fl[1] and fl[1][2]) or _G.ALL_INVENTORY_SLOTS or ALL or "All"
      if dd.GenerateMenu then dd:GenerateMenu() end
    end
    if p.lootFilterClear then p.lootFilterClear:Hide() end
  end

  -- DIFFICULTY CONTROLS — two independent toggles, no dropdown anywhere:
  --   * size toggle  ("10M"/"25M") — WotLK RAIDS only.
  --   * heroic skull — 5-man DUNGEONS (p.hasHeroic) AND raidHeroic RAIDS (ICC/RS/ToGC).
  -- A raid's difficulty is really a (size, heroic) PAIR living in p.diffOptions
  -- ({id,size,heroic,label}; id 1=10N 2=25N 3=10H 4=25H). These helpers convert between that pair
  -- and difficultyID so each toggle can flip its own axis and leave the other one alone.
  local function currentDiffOpt()
    if not p.diffOptions then return nil end
    for _, opt in ipairs(p.diffOptions) do
      if opt.id == (p.difficultyID or 1) then return opt end
    end
    return p.diffOptions[1]
  end
  local function setDiffPair(size, heroic)
    if not p.diffOptions then return false end
    for _, opt in ipairs(p.diffOptions) do
      if opt.size == size and ((opt.heroic and true or false) == heroic) then
        p.difficultyID = opt.id
        return true
      end
    end
    return false
  end
  p.CurrentDiffOpt = currentDiffOpt
  -- Does this instance offer a heroic axis at all? Dungeons say so via hasHeroic; raids by having
  -- any heroic entry in diffOptions (only the raidHeroic instances do).
  function p.HasHeroicAxis()
    if p.diffOptions then
      for _, opt in ipairs(p.diffOptions) do if opt.heroic then return true end end
      return false
    end
    return p.hasHeroic and true or false
  end

  -- Only the two difficulty toggles call this, hence the unconditional filter reset: switching
  -- 10M<->25M or Normal<->Heroic swaps the whole drop table, so a slot filter from the old one is
  -- stale by definition and would leave the page looking empty rather than filtered.
  local function reRender()
    if p.ResetLootFilter then p.ResetLootFilter() end
    if NE.ej.SelectTab then NE.ej.SelectTab(p.selectedTab or 2) end
  end

  -- Shared metal tab behind the difficulty toggles — ONE tab that fits whichever toggles are up
  -- (both, the skull alone on 5-mans, or 10M/25M alone on non-heroic raids). Both toggles parent
  -- into it and refreshView sizes it, so there is never a stray empty box.
  --
  -- Same three-piece DF metal art as the Dungeons/Raids bottom tabs, hanging DOWN off the top of
  -- the page instead of up off the bottom of the window. Anchored at p's top with NO rise: p's top
  -- already sits 4px below the window inset's top edge, and the inset's 3px border tile occupies
  -- only the 3px above that, so starting here clears the border instead of overlapping it.
  local dp = CreateFrame("Frame", "NE_EJDiffPanel", p)
  dp:SetPoint("TOPRIGHT", p, "TOPRIGHT", -DIFF_TAB_RIGHT_X, 0)
  dp:SetSize(DIFF_PANEL_W_BOTH, DIFF_PANEL_H)
  -- Piece anchoring mirrors NE.tabs.ReskinClassicTab: Left/Right overshoot dp's edges (scaled from
  -- the -3/+7 the real tabs use) and Middle tiles between them.
  local function dpTab(atlas, w)
    local t = dp:CreateTexture(nil, "BACKGROUND")
    if not (NE.tex and NE.tex.SetAtlas and NE.tex.SetAtlas(t, atlas, false)) then
      t:Hide()
      return nil
    end
    if w then t:SetWidth(w) end
    t:SetHeight(DIFF_TAB_H)
    return t
  end
  local tl = dpTab("uiframe-tab-left",  DIFF_TAB_LEFT_W)
  if tl then tl:SetPoint("TOPLEFT",  dp, "TOPLEFT",  DIFF_TAB_LEFT_X,  0) end
  local tr = dpTab("uiframe-tab-right", DIFF_TAB_RIGHT_W)
  if tr then tr:SetPoint("TOPRIGHT", dp, "TOPRIGHT", DIFF_TAB_RIGHT_X, 0) end
  local tm = dpTab("_uiframe-tab-center")
  if tm and tl and tr then
    tm:SetHorizTile(true)
    tm:SetPoint("TOPLEFT",  tl, "TOPRIGHT", 0, 0)
    tm:SetPoint("TOPRIGHT", tr, "TOPLEFT",  0, 0)
  elseif tm then
    tm:Hide()
  end
  dp.tabLeft, dp.tabMiddle, dp.tabRight = tl, tm, tr
  dp:Hide()
  p.diffPanel = dp

  -- Raid size toggle: "10M" <-> "25M". Sits to the LEFT of the heroic skull (anchored in refreshView).
  pcall(function()
    local sb = CreateFrame("Button", "NE_EJSizeToggle", dp)
    sb:SetSize(SIZE_TOGGLE_W, DIFF_TOGGLE_H)
    sb.label = sb:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    sb.label:SetPoint("CENTER")
    sb.label:SetTextColor(1, 0.82, 0)
    local hl = sb:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints(sb)
    hl:SetTexture("Interface\\Buttons\\UI-Common-MouseHilight")
    hl:SetBlendMode("ADD")
    function sb:SyncVisual()
      local cur = currentDiffOpt()
      self.label:SetText(((cur and cur.size) or 10) .. "M")
    end
    sb:SetScript("OnClick", function(self)
      local cur = currentDiffOpt()
      if not cur then return end
      if PlaySound and SOUNDKIT then PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON) end
      setDiffPair((cur.size == 10) and 25 or 10, cur.heroic and true or false)
      self:SyncVisual()
      if p.heroicToggle and p.heroicToggle.SyncVisual then p.heroicToggle:SyncVisual() end
      reRender()
    end)
    if NE.tooltip and NE.tooltip.Wire then
      NE.tooltip.Wire(sb, _G.RAID_DIFFICULTY or "Raid Size")
    end
    sb:Hide()
    p.sizeToggle = sb
  end)

  -- Heroic TOGGLE — a clickable skull badge (UI-EJ-HeroicTextIcon): lit = Heroic, dimmed +
  -- desaturated = Normal. Used by BOTH difficulty models:
  --   * 5-man dungeons  → flips difficultyID 1<->2 directly.
  --   * raidHeroic raids → flips only the HEROIC axis of the (size, heroic) pair, leaving the
  --     10M/25M choice on the size toggle untouched.
  pcall(function()
    local hb = CreateFrame("Button", "NE_EJHeroicToggle", dp)
    hb:SetSize(HEROIC_TOGGLE_W, DIFF_TOGGLE_H)

    local icon = hb:CreateTexture(nil, "ARTWORK")
    icon:SetSize(16, 16)
    icon:SetPoint("CENTER")
    icon:SetTexture((NE.tex and NE.tex.localFiles and NE.tex.localFiles[521748]) or 521748)
    hb.icon = icon

    local hl = hb:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints(hb)
    hl:SetTexture("Interface\\Buttons\\UI-Common-MouseHilight")
    hl:SetBlendMode("ADD")

    -- Reflect the current difficulty on the badge (called on click AND from refreshView, since the
    -- difficulty resets to Normal whenever a fresh instance is populated).
    function hb:SyncVisual()
      local on
      if p.diffOptions then
        local cur = currentDiffOpt()
        on = (cur and cur.heroic) and true or false
      else
        on = (p.difficultyID or 1) == 2
      end
      if self.icon.SetDesaturated then self.icon:SetDesaturated(not on) end
      self.icon:SetAlpha(on and 1 or 0.4)
    end

    hb:SetScript("OnClick", function(self)
      if PlaySound and SOUNDKIT then PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON) end
      if p.diffOptions then
        local cur = currentDiffOpt()
        if cur then setDiffPair(cur.size, not (cur.heroic and true or false)) end
      else
        p.difficultyID = ((p.difficultyID or 1) == 2) and 1 or 2
      end
      self:SyncVisual()
      if p.sizeToggle and p.sizeToggle.SyncVisual then p.sizeToggle:SyncVisual() end
      reRender()
    end)
    if NE.tooltip and NE.tooltip.Wire then
      NE.tooltip.Wire(hb, _G.PLAYER_DIFFICULTY2 or "Heroic")
    end
    hb:Hide()
    p.heroicToggle = hb
  end)

  -- model/instance button (top-left) → back to the instance overview (retail parity)
  local ib = CreateFrame("Button", nil, p)
  ib:SetSize(64, 61)
  ib:SetPoint("TOPLEFT", p, "TOPLEFT", 0, -3)
  -- dungeon-specific portrait under the UI-EJ-BossModelButton ring (set per-instance)
  ib.icon = ib:CreateTexture(nil, "BACKGROUND")
  ib.icon:SetSize(40, 40)
  ib.icon:SetPoint("CENTER", ib, "CENTER", 0, 1)
  local ibN = sliceTex(ib, "UI-EJ-BossModelButton"); ibN:SetAllPoints(ib); ib:SetNormalTexture(ibN)
  local ibH = sliceTex(ib, "UI-EJ-BossModelButton"); ibH:SetAllPoints(ib); ibH:SetBlendMode("ADD"); ib:SetHighlightTexture(ibH)
  -- step back ONE level: boss → instance overview, instance overview → dungeon grid.
  ib:SetScript("OnClick", function()
    if selBoss and selInst and NE.ej.ShowInstance then
      NE.ej.ShowInstance(selInst)
    elseif NE.ej.ShowList then
      NE.ej.ShowList()
    end
  end)
  NE.tooltip.Wire(ib, BACK or "Back")
  p.instanceButton = ib

  -- Info tabs. Vanilla/TBC-raid content ships NO overview sections, so retail's collapsed
  -- layout applies: tab 1 = lore + abilities (Boss icon), tab 3 hidden, Model below Loot.
  -- Tab 1 holds lore + abilities in one page, so it's labelled "Overview" rather than "Abilities".
  local overview = makeTab(p, 1, "UI-EJ-Tab-BossIcon-Selected",  "UI-EJ-Tab-BossIcon-UnSelected",  "Overview")
  overview:SetPoint("TOPLEFT", p, "TOPRIGHT", -4, -35)
  local loot = makeTab(p, 2, "UI-EJ-Tab-LootIcon-Selected",      "UI-EJ-Tab-LootIcon-UnSelected",  LOOT_NOUN or "Loot")
  loot:SetPoint("TOP", overview, "BOTTOM", 0, 2)
  -- tab 3 created for index stability but never shown/enabled (collapsed into tab 1).
  local boss = makeTab(p, 3, "UI-EJ-Tab-AbilitiesIcon-Selected", "UI-EJ-Tab-AbilitiesIcon-UnSelected", ABILITIES or "Abilities")
  boss:Hide()
  -- Model tab hidden for now (the boss model pane doesn't work reliably) -- still created for
  -- index stability, same as tab 3, so p.tabs/refreshView's tabID-keyed logic doesn't shift.
  local model = makeTab(p, 4, "UI-EJ-Tab-ModelIcon-Selected",    "UI-EJ-Tab-ModelIcon-UnSelected", MODEL or "Model")
  model:SetPoint("TOP", loot, "BOTTOM", 0, 2)
  model:Hide()
  p.tabs = { overview, loot, boss, model }

  -- Boss list (left page) — real scroll viewport + modern reskinned scrollbar.
  local bossScroll = CreateFrame("ScrollFrame", "NE_EJBossScroll", p, "UIPanelScrollFrameTemplate")
  bossScroll:SetSize(330, 382)
  bossScroll:SetPoint("BOTTOMLEFT", p, "BOTTOMLEFT", 25, 1)
  bossScroll.ScrollBar = bossScroll.ScrollBar or _G["NE_EJBossScrollScrollBar"]   -- DOWNPORT
  local bossChild = CreateFrame("Frame", nil, bossScroll)
  bossChild:SetSize(330, 1)
  bossScroll:SetScrollChild(bossChild)
  if NE.scrollbar and NE.scrollbar.Reskin then NE.scrollbar.Reskin(bossScroll, { hideIfUnscrollable = true }) end
  p.bossList = { scroll = bossChild, buttons = {} }

  -- The back button spans y -3..-64 and the boss list starts at -42, so they overlap by ~22px.
  -- ib is created FIRST, so at equal frame levels the boss buttons drew over it. Raise it here,
  -- after bossScroll exists, so the button stays clickable and fully visible.
  ib:SetFrameLevel(bossScroll:GetFrameLevel() + 10)

  -- Content area (right page): a text body, a loot row holder, and a creature model.
  local c = CreateFrame("Frame", nil, p)
  c:SetPoint("TOPLEFT", p, "TOPLEFT", 400, -44)
  c:SetPoint("BOTTOMRIGHT", p, "BOTTOMRIGHT", -16, 16)
  -- DOWNPORT FIX: !!!ClassicAPI's SetClipsChildren shim (Util/WidgetAPI.lua) clips via a
  -- ScrollFrame mask sized from Self:GetSize() AT CALL TIME. `c` is only anchor-positioned (two
  -- opposite corners, no explicit SetSize) — GetSize() can read back 0 before the anchors resolve,
  -- permanently pinning the clip mask to 0x0 and hiding EVERYTHING nested in `c` (abilities,
  -- loot, model) forever after. Give it an explicit size (matches the anchor math: p is 785x425)
  -- before clipping so the mask captures the real bounds.
  c:SetSize(785 - 400 - 16, 425 - 44 - 16)
  if c.SetClipsChildren then c:SetClipsChildren(true) end
  c.text = c:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
  c.text:SetPoint("TOPLEFT"); c.text:SetWidth(360)
  c.text:SetJustifyH("LEFT"); c.text:SetJustifyV("TOP")
  c.text:Hide()
  -- Loot list — scrollable viewport + reskinned bar. c.lootFrame is the scroll CHILD.
  c.lootScroll = CreateFrame("ScrollFrame", "NE_EJLootScroll", c, "UIPanelScrollFrameTemplate")
  c.lootScroll:SetPoint("TOPLEFT", c, "TOPLEFT", 20, 0)
  c.lootScroll:SetPoint("BOTTOMRIGHT", c, "BOTTOMRIGHT", -22, 0)
  c.lootScroll.ScrollBar = c.lootScroll.ScrollBar or _G["NE_EJLootScrollScrollBar"]   -- DOWNPORT
  c.lootFrame = CreateFrame("Frame", nil, c.lootScroll)
  c.lootFrame:SetSize(321, 1)
  c.lootScroll:SetScrollChild(c.lootFrame)
  if NE.scrollbar and NE.scrollbar.Reskin then NE.scrollbar.Reskin(c.lootScroll, { hideIfUnscrollable = true }) end
  c.lootFrame.rows = {}
  c.lootScroll:Hide()
  -- Abilities list (right page) — scrollable icon+title+body cards.
  c.sectionScroll = CreateFrame("ScrollFrame", "NE_EJSectionScroll", c, "UIPanelScrollFrameTemplate")
  c.sectionScroll:SetPoint("TOPLEFT", c, "TOPLEFT", 0, 0)
  c.sectionScroll:SetPoint("BOTTOMRIGHT", c, "BOTTOMRIGHT", -22, 0)
  c.sectionScroll.ScrollBar = c.sectionScroll.ScrollBar or _G["NE_EJSectionScrollScrollBar"]   -- DOWNPORT
  local sc = CreateFrame("Frame", nil, c.sectionScroll)
  sc:SetSize(340, 1)
  c.sectionScroll:SetScrollChild(sc)
  if NE.scrollbar and NE.scrollbar.Reskin then NE.scrollbar.Reskin(c.sectionScroll, { hideIfUnscrollable = true }) end
  c.sectionChild = sc
  c.sectionWidgets = {}
  c.sectionScroll:Hide()
  p.content = c

  -- Model area. DOWNPORT: plain Frame + PlayerModel (no ModelScene on 3.3.5a). Retail layer
  -- order preserved: dungeonBG BACKGROUND/1 → [3D model] → paperFrame OVERLAY → name.
  local ma = CreateFrame("Frame", nil, p)
  ma:SetSize(390, 423)
  ma:SetPoint("BOTTOMRIGHT", p, "BOTTOMRIGHT", -3, 1)
  ma:Hide()
  ma.bg = ma:CreateTexture(nil, "BACKGROUND", nil, 1)
  ma.bg:SetTexture(NE.tex.localFiles[521743] or 521743)   -- UI-EJ-BACKGROUND-Default
  -- dungeonBG: 512x512 file shown 394x425 via a horizontally-flipped crop.
  ma.bg:SetTexCoord(0.76953125, 0, 0, 0.83007813)
  ma.bg:SetSize(394, 425); ma.bg:SetPoint("BOTTOMLEFT", ma, "BOTTOMLEFT", 0, -2)
  ma.model = CreateFrame("PlayerModel", nil, ma)
  ma.model:SetAllPoints(ma)
  -- paper frame OVERLAYS the model (transparent centre frames it); lives on a child frame
  -- ABOVE the PlayerModel (a texture on `ma` would render UNDER the 3D model).
  local pf = CreateFrame("Frame", nil, ma)
  pf:SetAllPoints(ma); pf:SetFrameLevel(ma.model:GetFrameLevel() + 2)
  ma.shadow = pf:CreateTexture(nil, "OVERLAY", nil, 0)
  ma.shadow:SetTexture(NE.tex.localFiles[527690] or 527690)   -- UI-EJ-BossModelPaperFrame
  ma.shadow:SetTexCoord(0.767578125, 0, 0, 0.828125)          -- its OWN flipped crop
  ma.shadow:SetSize(393, 424); ma.shadow:SetPoint("BOTTOMRIGHT", ma, "BOTTOMRIGHT", 3, 0)
  ma.nameShadow = pf:CreateTexture(nil, "OVERLAY", nil, 1)
  NE.ej.ApplySlice(ma.nameShadow, "UI-EJ-BossNameShadow", true)  -- 395x63
  ma.nameShadow:SetPoint("BOTTOM", pf, "BOTTOM", 0, -2)
  ma.name = pf:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
  ma.name:SetSize(380, 10); ma.name:SetJustifyH("CENTER")
  ma.name:SetPoint("BOTTOM", pf, "BOTTOM", 0, 6)
  NE.font.Set(ma.name, NE.font.MORPHEUS, 18, "", GameFontNormalLarge)
  ma.name:SetShadowColor(0, 0, 0, 1); ma.name:SetShadowOffset(1, -1)

  -- "Not seen yet" notice. DOWNPORT: on this client, SetCreature/SetDisplayInfo silently render
  -- nothing for a creature the player hasn't encountered client-side this session (no server
  -- push of unseen display data) — surface that instead of leaving the pane blank.
  ma.unavailable = pf:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  ma.unavailable:SetPoint("CENTER", ma, "CENTER", 0, 10)
  ma.unavailable:SetWidth(300)
  ma.unavailable:SetJustifyH("CENTER")
  ma.unavailable:SetJustifyV("MIDDLE")
  ma.unavailable:SetText("Model will load once seen within this session due to client limitations.")
  ma.unavailable:Hide()

  -- Drag-to-rotate. DOWNPORT: 3.3.5a's generic Model_OnMouseDown/_OnUpdate handlers don't
  -- exist — a cursor-delta OnUpdate drives Model:SetFacing. Mousedown is forwarded from every
  -- frame in the stack (the paper-frame child otherwise eats the clicks).
  local rot = CreateFrame("Frame", nil, ma)
  rot:SetAllPoints(ma)
  rot:SetFrameLevel(pf:GetFrameLevel() + 1)
  ma.rotator = rot
  ma.model.rotation = 0
  local dragging, lastX
  rot:SetScript("OnUpdate", function()
    if not dragging then return end
    local x = GetCursorPosition()
    local dx = x - (lastX or x)
    lastX = x
    ma.model.rotation = (ma.model.rotation or 0) + dx * 0.015
    pcall(ma.model.SetFacing, ma.model, ma.model.rotation)
  end)
  local function fwdDown(_, btn)
    if not btn or btn == "LeftButton" then dragging = true; lastX = nil; ma._userRotated = true end
  end
  local function fwdUp(_, btn)
    if not btn or btn == "LeftButton" then dragging = false end
  end
  for _, fr in ipairs({ ma, ma.model, pf, rot }) do
    fr:EnableMouse(true)
    fr:SetScript("OnMouseDown", fwdDown)
    fr:SetScript("OnMouseUp",   fwdUp)
  end

  p.modelArea = ma
end

-- Boss list population (pooled buttons)
local function acquireBossButton(list, i)
  local b = list.buttons[i]
  if b then return b end
  b = CreateFrame("Button", nil, list.scroll)
  b:SetSize(325, 55)
  local up = sliceTex(b, "UI-EJ-BossButton-Up");        up:SetAllPoints(b); b:SetNormalTexture(up)
  local hi = sliceTex(b, "UI-EJ-BossButton-Highlight"); hi:SetAllPoints(b); hi:SetBlendMode("ADD"); b:SetHighlightTexture(hi)
  local dn = sliceTex(b, "UI-EJ-BossButton-Down");      dn:SetAllPoints(b); b:SetPushedTexture(dn)
  -- creature portrait + name live on a CHILD FRAME above the button's HIGHLIGHT layer.
  local cf = CreateFrame("Frame", nil, b)
  cf:SetFrameLevel(b:GetFrameLevel() + 2)
  cf:SetAllPoints(b)
  b.creature = cf:CreateTexture(nil, "ARTWORK")
  b.creature:SetSize(128, 64)                            -- per EJ.xml:585
  b.creature:SetPoint("TOPLEFT", b, "TOPLEFT", -4, 13)   -- overhangs the button top by 13
  b.name = cf:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
  b.name:SetPoint("LEFT", b, "LEFT", 105, -3); b.name:SetWidth(205); b.name:SetJustifyH("LEFT")
  b.name:SetTextColor(0.827, 0.659, 0.463)
  -- "Defeated this week" checkmark. DOWNPORT: native ReadyCheck art (no retail atlas here);
  -- only ever shown if the per-encounter lockout API exists (it doesn't on stock 3.3.5a).
  b.defeated = cf:CreateTexture(nil, "OVERLAY")
  b.defeated:SetSize(16, 16)
  b.defeated:SetPoint("BOTTOMLEFT", b, "BOTTOMLEFT", 4, 0)
  b.defeated:SetTexture("Interface\\RaidFrame\\ReadyCheck-Ready")
  b.defeated:Hide()
  list.buttons[i] = b
  return b
end

-- Keep the selected boss's row highlighted (retail locks the selected EncounterButton).
local function applyBossHighlight()
  local f = NE.ej.frame
  local bl = f and f.encounter and f.encounter.info and f.encounter.info.bossList
  if not (bl and bl.buttons) then return end
  for _, b in ipairs(bl.buttons) do
    if b.LockHighlight then
      if b.enc and b.enc == selBoss then b:LockHighlight() else b:UnlockHighlight() end
    end
  end
end

-- "Defeated this week" checkmark. DOWNPORT: GetSavedInstanceEncounterInfo is a Cata+ API —
-- absent on 3.3.5a the whole feature degrades to hidden checkmarks.
local function buildDefeatedSet()
  local set = {}
  if not (GetSavedInstanceEncounterInfo and GetNumSavedInstances) then return set end
  local n = GetNumSavedInstances() or 0
  for r = 1, n do
    local _, _, _, _, _, _, _, _, _, _, numBosses = GetSavedInstanceInfo(r)
    for i = 1, (numBosses or 0) do
      local bossName, _, isKilled = GetSavedInstanceEncounterInfo(r, i)
      if bossName and isKilled then set[bossName:lower()] = true end
    end
  end
  return set
end
local function applyDefeatedOverlays()
  local f = NE.ej.frame
  local bl = f and f.encounter and f.encounter.info and f.encounter.info.bossList
  if not (bl and bl.buttons) then return end
  local killed = buildDefeatedSet()
  for _, b in ipairs(bl.buttons) do
    if b.defeated then
      local nm = b.enc and b.enc.name
      setShown(b.defeated, nm ~= nil and killed[nm:lower()] == true)
    end
  end
end
-- RequestRaidInfo's result lands on UPDATE_INSTANCE_INFO (async), so re-apply when it arrives.
local defeatedWatch = CreateFrame("Frame")
defeatedWatch:RegisterEvent("UPDATE_INSTANCE_INFO")
defeatedWatch:SetScript("OnEvent", applyDefeatedOverlays)

local function fillBossList(inst)
  local list = NE.ej.frame.encounter.info.bossList
  local encs = inst.encounters or {}
  if RequestRaidInfo then RequestRaidInfo() end   -- refresh the saved-raid lockout
  for i, enc in ipairs(encs) do
    local b = acquireBossButton(list, i)
    b:ClearAllPoints()
    -- 15px top pad so the first boss's portrait (overhangs +13) isn't clipped.
    if i == 1 then b:SetPoint("TOPLEFT", list.scroll, "TOPLEFT", 0, -15)
    else b:SetPoint("TOPLEFT", list.buttons[i-1], "BOTTOMLEFT", 0, -2) end
    b.name:SetText(enc.name or "?")
    b.enc = enc
    local cr = enc.creatures and enc.creatures[1]
    if cr and cr.file and cr.file > 0 then
      b.creature:SetTexture(NE.tex.localFiles[cr.file] or cr.file)
      b.creature:SetTexCoord(0, 1, 0, 1)
      b.creature:Show()
    else
      b.creature:Hide()
    end
    local encRef = enc
    b:SetScript("OnClick", function()
      if PlaySound and SOUNDKIT then PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON) end
      NE.ej.ShowBoss(encRef)
    end)
    b:Show()
  end
  for i = #encs + 1, #list.buttons do list.buttons[i]:Hide() end
  applyBossHighlight()      -- restore the selected-row highlight after a (re)build
  applyDefeatedOverlays()   -- show "defeated this week" checkmarks (no-op on stock 3.3.5a)
  list.scroll:SetHeight(math.max(1, #encs * 57 + 15))  -- +15 top pad; drives the scroll range
end

-- Loot rendering (resolve via GetItemInfo; cold items primed + re-rendered by a short poll).
-- Loot row = NE.ej.CreateLootRow (EncounterItem.lua): 321x45, icon 42x42, name top, slot
-- bottom-left, armor/weapon type bottom-right, UI-EJ-LootFrame row bg, quality border.
local function lootRow(lf, i)
  local r = lf.rows[i]
  if r then return r end
  r = NE.ej.CreateLootRow(lf)
  lf.rows[i] = r
  return r
end

-- Category header (retail EncounterItemDividerTemplate). Med3 may be absent → GameFontNormal.
local function lootHeader(lf, i)
  lf.headers = lf.headers or {}
  local h = lf.headers[i]
  if h then return h end
  h = CreateFrame("Frame", nil, lf)
  h:SetSize(321, 30)
  h.name = h:CreateFontString(nil, "OVERLAY", _G.GameFontNormalMed3 and "GameFontNormalMed3" or "GameFontNormal")
  h.name:SetJustifyH("LEFT")
  h.name:SetPoint("BOTTOMLEFT", h, "BOTTOMLEFT", 2, 3)
  lf.headers[i] = h
  return h
end

-- Paint one loot row from a resolved item record (see renderLoot's bucketing).
-- WotLK set/tier tokens. GetItemInfo reports these as Miscellaneous/"Junk" (they carry no equip
-- slot), so the type column read "Junk" for every tier piece in the game. There is no runtime flag
-- that separates a tier token from an actual grey vendor item on 3.3.5a, so this is an explicit
-- set, derived from AtlasLoot's own WotLK data: every row it tags `=ds=#e15#` ("Token") that also
-- appears in DataWotLK.lua, minus the three pure currencies in that tag (Champion's Seal 44990,
-- Emblem of Triumph 47241, Emblem of Frost 49426), which are not gear.
--   40610-40639  T7  "of the Lost <archetype>"      (Naxxramas / Sartharion / Malygos)
--   45632-45661  T8  "of the Wayward <archetype>"   (Ulduar)
--   47242        T9  Trophy of the Crusade          (Trial of the Crusader)
--   52025-52030  T10 "<archetype>'s Mark of Sanctification" (Icecrown, normal + heroic)
-- Classic and TBC are NOT covered: AtlasLoot doesn't carry the Token tag for their set pieces, so
-- there is nothing to derive a list from. Those expansions' tokens still read as "Junk".
local TIER_TOKEN = {
  [40610]=1, [40611]=1, [40612]=1, [40613]=1, [40614]=1, [40615]=1, [40616]=1, [40617]=1,
  [40618]=1, [40619]=1, [40620]=1, [40621]=1, [40622]=1, [40623]=1, [40624]=1, [40625]=1,
  [40626]=1, [40627]=1, [40628]=1, [40629]=1, [40630]=1, [40631]=1, [40632]=1, [40633]=1,
  [40634]=1, [40635]=1, [40636]=1, [40637]=1, [40638]=1, [40639]=1, [45632]=1, [45633]=1,
  [45634]=1, [45635]=1, [45636]=1, [45637]=1, [45638]=1, [45639]=1, [45640]=1, [45641]=1,
  [45642]=1, [45643]=1, [45644]=1, [45645]=1, [45646]=1, [45647]=1, [45648]=1, [45649]=1,
  [45650]=1, [45651]=1, [45652]=1, [45653]=1, [45654]=1, [45655]=1, [45656]=1, [45657]=1,
  [45658]=1, [45659]=1, [45660]=1, [45661]=1, [47242]=1, [52025]=1, [52026]=1, [52027]=1,
  [52028]=1, [52029]=1, [52030]=1,
}

-- Quest items — same problem as TIER_TOKEN, same source. Several of these (Shadowfrost Shard
-- 50274, Fragment of Val'anyr 45038, the Ulduar keeper Sigils, Head of Onyxia) are Miscellaneous/
-- "Junk" to GetItemInfo rather than the Quest item class, so the type column read "Junk". Derived
-- from every row AtlasLoot tags `=ds=#m3#` ("Quest Item") across all three of its expansion
-- modules that also appears in our Data/DataTBC/DataWotLK. Items that ARE the Quest class already
-- report "Quest", so the override is a no-op for them and only relabels the mis-classed ones.
local QUEST_ITEM = {
  [4631]=1, [5334]=1, [7670]=1, [7741]=1, [9234]=1, [9471]=1, [10660]=1, [10661]=1, [11325]=1,
  [12335]=1, [12336]=1, [12337]=1, [12534]=1, [12845]=1, [13523]=1, [17203]=1, [17204]=1,
  [18780]=1, [18782]=1, [18784]=1, [19017]=1, [19716]=1, [19717]=1, [19718]=1, [19719]=1,
  [19720]=1, [19721]=1, [19722]=1, [19723]=1, [19724]=1, [19939]=1, [19940]=1, [19941]=1,
  [19942]=1, [20383]=1, [21232]=1, [21237]=1, [22637]=1, [22734]=1, [23723]=1, [23735]=1,
  [23881]=1, [23886]=1, [23933]=1, [24248]=1, [25461]=1, [25462]=1, [27632]=1, [27633]=1,
  [28490]=1, [28769]=1, [29906]=1, [30808]=1, [30827]=1, [30828]=1, [30829]=1, [31085]=1,
  [31086]=1, [31721]=1, [31722]=1, [31744]=1, [31750]=1, [32459]=1, [33330]=1, [33814]=1,
  [33815]=1, [33821]=1, [33826]=1, [33827]=1, [33834]=1, [33835]=1, [33836]=1, [33840]=1,
  [33847]=1, [33858]=1, [33859]=1, [33860]=1, [33861]=1, [34157]=1, [43151]=1, [43411]=1,
  [44569]=1, [44577]=1, [44650]=1, [45038]=1, [45784]=1, [45786]=1, [45787]=1, [45788]=1,
  [45814]=1, [45815]=1, [45816]=1, [45817]=1, [49644]=1, [50226]=1, [50231]=1, [50274]=1,
  [51026]=1,
}

local function fillLootRow(r, it)
  r.itemID = it.id
  r.link = it.link   -- HandleModifiedItemClick needs the link, not the id
  r.icon:SetTexture(it.icon or "Interface\\Icons\\INV_Misc_QuestionMark")
  r.name:SetText(it.name)
  local col = NE.itembtn.TextColor(it.quality or 1)
  if col then
    r.name:SetTextColor(col.r, col.g, col.b)
    r.iconBorder:SetVertexColor(col.r, col.g, col.b); r.iconBorder:Show()
  else
    r.name:SetTextColor(1, 1, 1); r.iconBorder:Hide()
  end
  r.slot:SetText((it.equipLoc and it.equipLoc ~= "" and _G[it.equipLoc]) or "")
  local typeText = it.itemSubType or it.itemType or ""
  if typeText == "Money(OBSOLETE)" or typeText == "Money" then
    typeText = _G.CURRENCY or "Currency"
  end
  if TIER_TOKEN[it.id] then typeText = "Tier" end
  if QUEST_ITEM[it.id] then typeText = "Quest" end
  r.armorType:SetText(typeText)
  -- drop% (NE addition): show only when AtlasLoot recorded a rate (pct>0)
  r.dropPct:SetText(it.pct and it.pct > 0 and string.format("%.1f%%", it.pct) or "")
end

local MAX_LOOT = 100   -- scrollable; the instance-wide aggregate can be large

-- Loot slot filter (retail Enum.ItemSlotFilterType): {key, label}; key "ALL" = no filter.
NE.ej.LOOT_FILTERS = {
  { "ALL",            _G.ALL_INVENTORY_SLOTS or ALL or "All" },
  { "INVTYPE_HEAD",   _G.INVTYPE_HEAD or "Head" },
  { "INVTYPE_NECK",   _G.INVTYPE_NECK or "Neck" },
  { "INVTYPE_SHOULDER", _G.INVTYPE_SHOULDER or "Shoulder" },
  { "INVTYPE_CLOAK",  _G.INVTYPE_CLOAK or "Back" },
  { "INVTYPE_CHEST",  _G.INVTYPE_CHEST or "Chest" },
  { "INVTYPE_WRIST",  _G.INVTYPE_WRIST or "Wrist" },
  { "INVTYPE_HAND",   _G.INVTYPE_HAND or "Hands" },
  { "INVTYPE_WAIST",  _G.INVTYPE_WAIST or "Waist" },
  { "INVTYPE_LEGS",   _G.INVTYPE_LEGS or "Legs" },
  { "INVTYPE_FEET",   _G.INVTYPE_FEET or "Feet" },
  { "MAINHAND",       _G.INVTYPE_WEAPONMAINHAND or "Main Hand" },
  { "OFFHAND",        _G.INVTYPE_WEAPONOFFHAND or "Off Hand" },
  { "INVTYPE_FINGER", _G.INVTYPE_FINGER or "Finger" },
  { "INVTYPE_TRINKET", _G.INVTYPE_TRINKET or "Trinket" },
  { "OTHER",          _G.EJ_LOOT_SLOT_FILTER_OTHER or OTHER or "Other" },
}
local LOOT_DIRECT = { INVTYPE_HEAD=1, INVTYPE_NECK=1, INVTYPE_SHOULDER=1, INVTYPE_CLOAK=1,
  INVTYPE_CHEST=1, INVTYPE_WRIST=1, INVTYPE_HAND=1, INVTYPE_WAIST=1, INVTYPE_LEGS=1, INVTYPE_FEET=1,
  INVTYPE_FINGER=1, INVTYPE_TRINKET=1 }
local function lootCategory(equipLoc)
  if equipLoc == "INVTYPE_ROBE" then return "INVTYPE_CHEST" end
  if LOOT_DIRECT[equipLoc] then return equipLoc end
  if equipLoc == "INVTYPE_WEAPONMAINHAND" or equipLoc == "INVTYPE_2HWEAPON" or equipLoc == "INVTYPE_WEAPON"
     or equipLoc == "INVTYPE_RANGED" or equipLoc == "INVTYPE_RANGEDRIGHT" or equipLoc == "INVTYPE_THROWN" then
    return "MAINHAND"
  end
  if equipLoc == "INVTYPE_WEAPONOFFHAND" or equipLoc == "INVTYPE_SHIELD" or equipLoc == "INVTYPE_HOLDABLE" then
    return "OFFHAND"
  end
  return "OTHER"
end

-- The slot categories actually PRESENT in a loot list (resolved items only). `info` is optional:
-- pass the info panel and the list is narrowed to the difficulty/size currently selected, so the
-- dropdown can't offer a slot that only drops on the OTHER difficulty of the same boss (picking
-- one would render an empty page).
function NE.ej.PresentLootCategories(items, info)
  local present = {}
  if items then
    -- Looked up at call time rather than captured: passesDifficulty is a local declared further
    -- down this file, so it is not in scope here.
    local passes = NE.ej.PassesDifficulty
    for i = 1, #items do
      local entry = items[i]
      local id = (type(entry) == "table") and entry.id or entry
      local ok = true
      if info and passes then
        local dif  = (type(entry) == "table") and entry.diff or nil
        local size = (type(entry) == "table") and entry.size or nil
        ok = passes(info, dif, size)
      end
      if ok then
        local name, _, _, _, _, _, _, _, equipLoc = GetItemInfo(id)
        if name then present[lootCategory(equipLoc or "")] = true end
      end
    end
  end
  return present
end

-- Rarity tiers — OWNER DIVERGENCE (NewEra): equippable gear bucketed by drop chance into four
-- titled tiers; non-equippable goes under "Bonus".
local TIER_EXTREME_MAX  = 1    -- 0 < pct < 1%    → Extremely Rare
local TIER_VERYRARE_MAX = 5    -- 1% ≤ pct < 5%   → Very Rare
local TIER_UNCOMMON_MAX = 15   -- 5% ≤ pct < 15%  → Uncommon ; pct ≥ 15% or unknown → Common
local function lootTier(equipLoc, pct)
  if lootCategory(equipLoc or "") == "OTHER" then return "bonus" end
  if pct and pct > 0 then
    if pct < TIER_EXTREME_MAX  then return "extreme"  end
    if pct < TIER_VERYRARE_MAX then return "veryrare" end
    if pct < TIER_UNCOMMON_MAX then return "uncommon" end
  end
  return "common"
end
local LOOT_TIERS = {
  { key = "extreme",  title = _G.EJ_ITEM_CATEGORY_EXTREMELY_RARE or "Extremely Rare" },
  { key = "veryrare", title = _G.EJ_ITEM_CATEGORY_VERY_RARE or "Very Rare" },
  { key = "uncommon", title = _G.ITEM_QUALITY2_DESC or "Uncommon" },
  { key = "common",   title = _G.ITEM_QUALITY1_DESC or "Common" },
  { key = "bonus",    title = _G.BONUS_LOOT_TOOLTIP_TITLE or "Bonus" },
}

-- Difficulty filter shared by loot rows (size+diff) and ability sections (diff only).
--   * Raids (info.diffOptions present, set in PopulateEncounter): a row's optional `size`
--     (10|25) must match the selected option's size; a row's diff="h" must match the option's
--     heroic-ness EXACTLY (WotLK raid loot is a hard split — a Normal-tagged/untagged item is
--     never also a Heroic drop, unlike the 5-man "applies to both" convention below).
--   * 5-man dungeons: legacy — an untagged row (dif=nil) applies to both Normal and Heroic.
-- `untaggedBoth` opts out of the raid hard-split for ability SECTIONS: no seeded section in
-- AbilitiesEra/TBC/WotLK.lua carries a diff tag at all, so the exact match above would drop every
-- section (and its subtree) the moment Heroic was selected on a raid, blanking the Overview tab.
local function passesDifficulty(info, dif, size, untaggedBoth)
  if info.diffOptions then
    local sel
    for _, opt in ipairs(info.diffOptions) do
      if opt.id == (info.difficultyID or 1) then sel = opt; break end
    end
    sel = sel or info.diffOptions[1]
    if not sel then return true end
    if size and sel.size and size ~= sel.size then return false end
    if dif == nil and untaggedBoth then return true end
    local heroicSel = sel.heroic and true or false
    if (dif == "h") ~= heroicSel then return false end
    return true
  else
    local heroicSel = info.hasHeroic and (info.difficultyID or 1) == 2 or false
    if dif and (dif == "h") ~= heroicSel then return false end
    return true
  end
end
-- Published so NE.ej.PresentLootCategories (defined above this point) can reach it.
NE.ej.PassesDifficulty = passesDifficulty

local function renderLoot(boss, preserveScroll)
  local info = NE.ej.frame.encounter.info
  local lf = info.content.lootFrame
  local items = boss and boss.loot or {}
  -- Remember the list currently shown so the cache poll can re-render THIS view as items
  -- stream in — both the boss page and the instance-landing aggregate.
  info.lootSource = items
  local filter = info.lootSlot or "ALL"

  -- Pass 1 — resolve + slot-filter, bucket into rarity tiers. Cold items are primed (server
  -- item query via hidden tooltip) UNCONDITIONALLY, regardless of the current difficulty/size
  -- filter — otherwise switching Normal<->Heroic or 10<->25 leaves the newly-relevant items
  -- never queried, so loot stays empty until the player toggles the filter back and forth.
  local buckets = { extreme = {}, veryrare = {}, uncommon = {}, common = {}, bonus = {} }
  local count, unresolved = 0, 0
  for i = 1, #items do
    -- loot schema is { {id=ITEMID, pct=DROP%, size=10|25|nil, diff="h"|"n"|nil}, ... }; tolerate
    -- a bare id.
    local entry = items[i]
    local id   = (type(entry) == "table") and entry.id   or entry
    local pct  = (type(entry) == "table") and entry.pct  or 0
    local dif  = (type(entry) == "table") and entry.diff or nil
    local size = (type(entry) == "table") and entry.size or nil
    if id and not GetItemInfo(id) then
      if NE.ej.PrimeItem then NE.ej.PrimeItem(id) end
      if C_Item and C_Item.RequestLoadItemDataByID then pcall(C_Item.RequestLoadItemDataByID, id) end
    end
    if count < MAX_LOOT and passesDifficulty(info, dif, size) then
      local name, link, quality, _, _, itemType, itemSubType, _, equipLoc, icon = GetItemInfo(id)
      if not name then
        unresolved = unresolved + 1
      elseif filter == "ALL" or lootCategory(equipLoc or "") == filter then
        count = count + 1
        local b = buckets[lootTier(equipLoc, pct)]
        b[#b + 1] = { id = id, link = link, name = name, quality = quality, itemType = itemType,
                      itemSubType = itemSubType, equipLoc = equipLoc, icon = icon, pct = pct }
      end
    end
  end

  -- Pass 2 — render tiers in retail order; a header before each non-empty tier.
  local rowN, hdrN, prev, totalH = 0, 0, nil, 0
  local function place(w, h)
    w:ClearAllPoints()
    if not prev then w:SetPoint("TOPLEFT", lf, "TOPLEFT", 0, 0)
    else w:SetPoint("TOPLEFT", prev, "BOTTOMLEFT", 0, -2) end
    prev = w; totalH = totalH + h + 2; w:Show()
  end
  for _, tier in ipairs(LOOT_TIERS) do
    local bucket = buckets[tier.key]
    if #bucket > 0 then
      if tier.title then
        hdrN = hdrN + 1
        local h = lootHeader(lf, hdrN)
        h.name:SetText(tier.title)
        place(h, h:GetHeight())
      end
      for _, it in ipairs(bucket) do
        rowN = rowN + 1
        local r = lootRow(lf, rowN)
        fillLootRow(r, it)
        place(r, 45)   -- row 45 + 2 gap
      end
    end
  end
  for i = rowN + 1, #lf.rows do lf.rows[i]:Hide() end
  if lf.headers then for i = hdrN + 1, #lf.headers do lf.headers[i]:Hide() end end
  lf:SetHeight(math.max(1, totalH))   -- drives the loot scroll range
  -- Reset scroll only when switching into a fresh view; a streaming re-render keeps the
  -- user's place.
  if not preserveScroll and lf:GetParent().SetVerticalScroll then lf:GetParent():SetVerticalScroll(0) end

  -- DOWNPORT: the GET_ITEM_INFO_RECEIVED substitute — poll while this view still has cold
  -- items, re-rendering scroll-preserving as the server answers the item queries.
  if unresolved > 0 and NE.ej.SchedulePrimedRefresh then
    NE.ej.SchedulePrimedRefresh(
      function()
        local inf = NE.ej.frame and NE.ej.frame.encounter and NE.ej.frame.encounter.info
        if not (inf and inf.selectedTab == 2 and inf.lootSource == items) then return false end
        for i = 1, #items do
          local entry = items[i]
          local id = (type(entry) == "table") and entry.id or entry
          if id and not GetItemInfo(id) then return true end
        end
        return false
      end,
      function() renderLoot({ loot = items }, true) end)
  end
end

-- Abilities tab: retail's collapsible PaperHeader sections. Strip unresolved spell-script
-- tokens ($8040d duration, $s1 effect values, $bull; bullets) that the client can't
-- substitute without live spell data — they'd render as raw "$8040d".
local function cleanBody(s)
  s = (s or ""):gsub("%$%d+%a%d*", ""):gsub("%$%a%d*", ""):gsub("%$bull;?", "•")
  return (s:gsub("%s+([%.,])", "%1"):gsub("  +", " "):gsub("^%s+", ""))
end

local SEC_W = 334

-- 3-slice paper-header band (left + stretched mid + right) on `parent` at `layer`.
local function paperBand(parent, state, layer)
  local b = {}
  b.l = parent:CreateTexture(nil, layer); NE.ej.ApplySlice(b.l, "UI-EJ-PaperHeader-" .. state .. "-Left", true)
  b.l:ClearAllPoints(); b.l:SetPoint("LEFT", parent, "LEFT", -1, -1)
  b.r = parent:CreateTexture(nil, layer); NE.ej.ApplySlice(b.r, "UI-EJ-PaperHeader-" .. state .. "-Right", true)
  b.r:ClearAllPoints(); b.r:SetPoint("RIGHT", parent, "RIGHT", 3, -1)
  b.m = parent:CreateTexture(nil, layer); NE.ej.ApplySlice(b.m, "_PaperHeader-" .. state .. "-Mid", false)
  b.m:SetHeight(29); b.m:SetPoint("LEFT", b.l, "RIGHT", -32, 0); b.m:SetPoint("RIGHT", b.r, "LEFT", 32, 0)
  return b
end
local function bandShown(b, on) setShown(b.l, on); setShown(b.m, on); setShown(b.r, on) end

local function acquireSection(c, i)
  local w = c.sectionWidgets[i]
  if w then return w end
  w = CreateFrame("Frame", nil, c.sectionChild)
  w:SetWidth(SEC_W)
  local hb = CreateFrame("Button", nil, w)
  hb:SetPoint("TOPLEFT", w, "TOPLEFT", 0, 0); hb:SetPoint("TOPRIGHT", w, "TOPRIGHT", 0, 0)
  hb:SetHeight(24)
  w.header  = hb
  w.cBand   = paperBand(hb, "UnSelectUp", "BACKGROUND")   -- collapsed
  w.eBand   = paperBand(hb, "SelectDown", "BACKGROUND")   -- expanded
  paperBand(hb, "Highlight", "HIGHLIGHT")                 -- HIGHLIGHT layer = auto hover glow
  w.expandedIcon = hb:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
  w.expandedIcon:SetPoint("LEFT", hb, "LEFT", 5, 0)
  w.abilityIcon = hb:CreateTexture(nil, "OVERLAY")
  w.abilityIcon:SetSize(18, 18); w.abilityIcon:SetPoint("LEFT", w.expandedIcon, "RIGHT", 5, 0)
  w.abilityIcon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
  -- section icon-flag badges on the right (Interruptible/Magic/Enrage/…), right-to-left.
  -- Each badge is a mouse-enabled Frame (a texture can't take OnEnter) + tooltip strings.
  w.flagIcons = {}
  for fi = 1, 6 do
    local ic = CreateFrame("Frame", nil, hb)
    ic:SetSize(16, 16)
    ic.tex = ic:CreateTexture(nil, "OVERLAY"); ic.tex:SetAllPoints(ic)
    if fi == 1 then ic:SetPoint("RIGHT", hb, "RIGHT", -4, 0)
    else ic:SetPoint("RIGHT", w.flagIcons[fi - 1], "LEFT", -2, 0) end
    ic:EnableMouse(true)
    ic:SetScript("OnEnter", function(self)
      if not self.tooltipTitle then return end
      GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
      GameTooltip:SetText(self.tooltipTitle, 1, 1, 1)
      if self.tooltipText and self.tooltipText ~= "" then
        GameTooltip:AddLine(self.tooltipText, nil, nil, nil, true)
      end
      GameTooltip:Show()
    end)
    ic:SetScript("OnLeave", function() GameTooltip:Hide() end)
    ic:Hide()
    w.flagIcons[fi] = ic
  end
  w.title = hb:CreateFontString(nil, "OVERLAY", "GameFontNormal"); w.title:SetJustifyH("LEFT")
  w.desc = w:CreateFontString(nil, "ARTWORK", BLACK_FONT)
  w.desc:SetJustifyH("LEFT"); w.desc:SetJustifyV("TOP"); w.desc:SetTextColor(0.25, 0.1484375, 0.02)
  w.desc:SetWidth(SEC_W - 26); w.desc:SetPoint("TOPLEFT", hb, "BOTTOMLEFT", 13, -9)
  -- parchment inset box behind the description + its bottom border
  w.descBG = w:CreateTexture(nil, "BACKGROUND")
  NE.ej.ApplySlice(w.descBG, "UI-PaperOverlay-AbilityTextBG", false)
  w.descBG:SetPoint("TOPLEFT", w.desc, "TOPLEFT", -9, 12)
  w.descBG:SetPoint("BOTTOMRIGHT", w.desc, "BOTTOMRIGHT", 9, -11)
  w.descBottom = w:CreateTexture(nil, "BACKGROUND")
  NE.ej.ApplySlice(w.descBottom, "UI-PaperOverlay-AbilityTextBottomBorder", false)
  w.descBottom:SetHeight(9)
  w.descBottom:SetPoint("LEFT", w.descBG, "BOTTOMLEFT", 0, 0)
  w.descBottom:SetPoint("RIGHT", w.descBG, "BOTTOMRIGHT", 0, 0)
  hb:SetScript("OnClick", function()
    if PlaySound and SOUNDKIT then PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON) end
    if w.sectionID and c._secExp then c._secExp[w.sectionID] = not c._secExp[w.sectionID] end
    if c._reflow then c._reflow() end
  end)
  c.sectionWidgets[i] = w
  return w
end

local HEADER_INDENT = 15    -- retail Blizzard_EncounterJournal.lua
local SECTION_GAP   = 6

-- IconFlags bitmask → list of set bit indices.
local function flagBits(flags)
  local out = {}
  flags = flags or 0
  for i = 0, 13 do
    if bit.band(flags, bit.lshift(1, i)) ~= 0 then out[#out + 1] = i end
  end
  return out
end
local function flagTexCoord(i)
  local l = (i % 8) / 8
  local t = math.floor(i / 8) / 2
  return l, l + 0.125, t, t + 0.5
end

-- Bit-index → modern flag atlas names (kept from NewEra; the icons_16x16_* atlases are NOT
-- registered on this port, so SetFlagIcon always falls to the legacy UI-EJ-Icons grid).
local FLAG_ATLAS = {
  [0]="icons_16x16_tank",   [1]="icons_16x16_damage",  [2]="icons_16x16_heal",
  [3]="icons_16x16_heroic", [4]="icons_16x16_deadly",  [5]="icons_16x16_important",
  [6]="icons_16x16_inturrupt", [7]="icons_16x16_magic", [8]="icons_16x16_curse",
  [9]="icons_16x16_poison", [10]="icons_16x16_disease", [11]="icons_16x16_enrage",
  [12]="icons_16x16_mythic", [13]="icons_16x16_blood",
}
-- Fallback tooltip titles (the ENCOUNTER_JOURNAL_SECTION_FLAG<i> globals are Cata+).
local FLAG_NAME = {
  [0]="Role: Tank", [1]="Role: Damage", [2]="Role: Healer", [3]="Heroic Difficulty",
  [4]="Deadly", [5]="Important", [6]="Interruptible", [7]="Magic Effect", [8]="Curse Effect",
  [9]="Poison Effect", [10]="Disease Effect", [11]="Enrage Effect", [12]="Mythic Difficulty",
  [13]="Bleed Effect",
}
NE.ej.FLAG_NAME = FLAG_NAME

-- Apply the flag icon for bit-index `i`: named atlas when registered, else retail's legacy
-- UI-EJ-Icons 8x2 grid. NOTE: NE.tex.SetAtlas IS the texcoord set — no trailing SetTexCoord.
function NE.ej.SetFlagIcon(tex, i)
  local atlas = FLAG_ATLAS[i]
  if not (atlas and NE.tex and NE.tex.SetAtlas and NE.tex.SetAtlas(tex, atlas, false)) then
    tex:SetTexture(NE.tex.localFiles[521749] or 521749)
    tex:SetTexCoord(flagTexCoord(i))
  end
end

-- Lay out one section row at `depth` (indented 15px/level). Returns the row's height.
local function layoutSection(w, s, depth, exp)
  local rowW = SEC_W - depth * HEADER_INDENT
  w:SetWidth(rowW)
  w.title:SetFontObject((depth == 0 and _G.GameFontNormalMed3) or _G.GameFontNormal)
  w.title:ClearAllPoints()
  -- left glyph: creature portrait > ability icon (FDID) > spell-resolved icon > none.
  -- DOWNPORT: spell icons resolve via GetSpellInfo (GetSpellTexture can't take arbitrary
  -- ids on 3.3.5a); creature portraits need SetPortraitTextureFromCreatureDisplayID (absent
  -- on stock 3.3.5a → those sub-creature headers render without an icon).
  -- DOWNPORT FIX: 3.3.5a's SetTexture can't read a raw FileDataID (core/Texture.lua) — it
  -- renders the client's "missing texture" glyph (a red square), not a blank. s.icon is a raw
  -- modern FDID from the DB2-extracted dungeon data (Data/DataTBC) and is almost never one of
  -- the 501 EJ BLPs we shipped locally, so only trust it when NE.tex.localFiles actually has an
  -- entry; otherwise fall through to the spell icon (hand-seeded raid data always sets a real
  -- spell id instead of icon) or hide the glyph rather than show a red square.
  local mappedFDID = s.icon and s.icon > 0 and NE.tex.localFiles[s.icon]
  local spellIcon = (not mappedFDID) and s.spell and s.spell > 0 and GetSpellInfo
    and select(3, GetSpellInfo(s.spell)) or nil
  if s.cdisp and s.cdisp > 0 and SetPortraitTextureFromCreatureDisplayID then
    SetPortraitTextureFromCreatureDisplayID(w.abilityIcon, s.cdisp)
    w.abilityIcon:Show(); w.title:SetPoint("LEFT", w.abilityIcon, "RIGHT", 5, 0)
  elseif mappedFDID or spellIcon then
    w.abilityIcon:SetTexture(mappedFDID or spellIcon)
    w.abilityIcon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    w.abilityIcon:Show(); w.title:SetPoint("LEFT", w.abilityIcon, "RIGHT", 5, 0)
  else
    w.abilityIcon:Hide(); w.title:SetPoint("LEFT", w.expandedIcon, "RIGHT", 5, 0)
  end
  -- right-side flag badges (right-to-left); title's RIGHT anchor stops at the leftmost one.
  local bits, last = flagBits(s.flags), 0
  for fi = 1, #w.flagIcons do
    local idx = bits[fi]   -- 0-based bit index
    local ic = w.flagIcons[fi]
    if idx then
      NE.ej.SetFlagIcon(ic.tex, idx)
      ic.tooltipTitle = _G["ENCOUNTER_JOURNAL_SECTION_FLAG" .. idx] or FLAG_NAME[idx]
      ic.tooltipText  = _G["ENCOUNTER_JOURNAL_SECTION_FLAG_DESCRIPTION" .. idx]
      ic:Show(); last = fi
    else
      ic:Hide()
    end
  end
  if last > 0 then w.title:SetPoint("RIGHT", w.flagIcons[last], "LEFT", -5, 0)
  else w.title:SetPoint("RIGHT", w.header, "RIGHT", -8, 0) end
  w.title:SetText(s.title or "")
  w.desc:SetWidth(rowW - 26); w.desc:SetText(cleanBody(s.body))
  local hasBody = (w.desc:GetText() or "") ~= ""
  w.expandedIcon:SetText(exp and "-" or "+")
  bandShown(w.cBand, not exp); bandShown(w.eBand, exp)
  local showDesc = exp and hasBody
  setShown(w.desc, showDesc); setShown(w.descBG, showDesc); setShown(w.descBottom, showDesc)
  local h = 24
  if showDesc then h = h + 9 + (w.desc:GetStringHeight() or 0) + 11 + 9 end  -- gap + text + box pad + border
  w:SetHeight(h)
  return h
end

-- Sections form a tree walked EXACTLY as retail does (ToggleHeaders): start at the boss's
-- rootSection and follow the sibling linked-list (`sib`); an expanded header descends into
-- its `child` chain (indented). Headers expanded by default; `visited` guards cycles.
local function renderSections(boss)
  local c = NE.ej.frame.encounter.info.content
  local byId = {}
  for _, s in ipairs(boss.sections or {}) do byId[s.id] = s end
  c._secExp = c._secExp or {}
  -- Lead lore paragraph: the boss description at the TOP, above the ability sections.
  if not c.leadDesc then
    -- BLACK_FONT, not GameFontHighlight: this is body copy on the parchment, so it matches the
    -- ability descriptions below it (w.desc) and the instance lore on the left page. Highlight is
    -- a size larger, which left the lore paragraph visibly outsized against the rest of the page.
    c.leadDesc = c.sectionChild:CreateFontString(nil, "ARTWORK", BLACK_FONT)
    c.leadDesc:SetJustifyH("LEFT"); c.leadDesc:SetJustifyV("TOP"); c.leadDesc:SetWidth(SEC_W)
    c.leadDesc:SetTextColor(0.25, 0.1484375, 0.02)   -- dark on the parchment page
  end
  c.leadDesc:SetText(cleanBody(boss.desc))
  c._reflow = function()
    local hasLore = (c.leadDesc:GetText() or "") ~= ""
    setShown(c.leadDesc, hasLore)
    local y = -6
    if hasLore then
      c.leadDesc:ClearAllPoints()
      c.leadDesc:SetPoint("TOPLEFT", c.sectionChild, "TOPLEFT", 6, y)
      y = y - (c.leadDesc:GetStringHeight() or 0) - 14   -- gap before the first ability band
    end
    -- Difficulty filter (mirrors renderLoot's passesDifficulty): a section's optional diff tag
    -- must match the selected difficulty; skipping a section skips its subtree.
    local dinfo = NE.ej.frame.encounter.info
    local idx, visited = 0, {}
    local function walk(startID, depth)
      local id = startID
      while id and id ~= 0 and byId[id] and not visited[id] do
        visited[id] = true
        local s = byId[id]
        local dif = s.diff
        if not passesDifficulty(dinfo, dif, nil, true) then
          id = s.sib   -- wrong difficulty: drop this section and its subtree
        else
          idx = idx + 1
          local w = acquireSection(c, idx)
          w.sectionID = s.id
          if c._secExp[s.id] == nil then c._secExp[s.id] = true end   -- expanded by default
          local exp = c._secExp[s.id] and true or false
          local h = layoutSection(w, s, depth, exp)
          w:ClearAllPoints(); w:SetPoint("TOPLEFT", c.sectionChild, "TOPLEFT", 6 + depth * HEADER_INDENT, y)
          w:Show()
          y = y - h - SECTION_GAP
          if exp then walk(s.child, depth + 1) end
          id = s.sib
        end
      end
    end
    local root = boss.rootSection
    if not root or root == 0 then root = boss.sections and boss.sections[1] and boss.sections[1].id end
    walk(root, 0)
    for i = idx + 1, #c.sectionWidgets do c.sectionWidgets[i]:Hide() end
    c.sectionChild:SetHeight(math.max(1, -y + 6))
  end
  c._reflow()
  c.sectionScroll:SetVerticalScroll(0)
end

-- Model display. DOWNPORT: the PRIMARY path is the PlayerModel (no ModelScene on 3.3.5a).
-- Camera: the generated per-boss MODEL_CAM (cdist = camera distance, ctz = look-at height in
-- model units) is emulated by pushing the MODEL away from the fixed default camera (-X) and
-- down (-Z). Mapping constants are globals, tunable in-game via /run DragonUI_NewEra.ej.CAM_*.
-- A hand MODEL_TWEAKS[displayID] = { cdist=, ctz=, facing=, mscale= } outlier always wins.
NE.ej.MODEL_TWEAKS = NE.ej.MODEL_TWEAKS or {}
NE.ej.DEFAULT_MODEL_SCALE = NE.ej.DEFAULT_MODEL_SCALE or 1
NE.ej.DEFAULT_CAM_DIST = NE.ej.DEFAULT_CAM_DIST or 2.2   -- when no MODEL_CAM entry (TBC bosses)
NE.ej.DEFAULT_CAM_TZ   = NE.ej.DEFAULT_CAM_TZ   or 0.35
NE.ej.CAM_X0 = NE.ej.CAM_X0 or 1.0    -- model X offset at cdist 0 (toward camera)
NE.ej.CAM_XK = NE.ej.CAM_XK or 0.55   -- X pushback per cdist unit
NE.ej.CAM_ZK = NE.ej.CAM_ZK or 0.9    -- Z drop per ctz unit

-- NE.ej.NormalizeModel(ma, displayID [, tier])
-- tier: 1 = Classic (display = creature NPC ID → SetCreature), 2+ = TBC/WotLK
--       (display = CreatureDisplayInfoID from retail EJ DB2 → SetDisplayInfo).
-- ma MUST already be shown before this is called — the 3.3.5a engine silently skips
-- model loads while the frame ancestor chain is hidden (cold-start, QuestNpcModel.lua).
function NE.ej.NormalizeModel(ma, displayID, tier)
  if not ma then return end
  local model = ma.model
  if not model then return end
  ma._userRotated = false
  -- Load persisted camera overrides once per session (DOWNPORT: NewEraDB → NE.db).
  if not NE.ej._tweaksLoaded and NE.db then
    for d, t in pairs(NE.db._ejTweaks or {}) do NE.ej.MODEL_TWEAKS[d] = t end
    if NE.db._ejGlobalMScale then NE.ej.DEFAULT_MODEL_SCALE = NE.db._ejGlobalMScale end
    NE.ej._tweaksLoaded = true
  end
  if not (displayID and displayID > 0) then
    pcall(model.ClearModel, model); model:Hide()
    if ma.unavailable then ma.unavailable:Hide() end
    return
  end
  if ma.unavailable then ma.unavailable:Hide() end
  local t = NE.ej.MODEL_TWEAKS[displayID] or {}
  local cam = (NE.ej.MODEL_CAM and NE.ej.MODEL_CAM[displayID]) or {}
  model.rotation = t.facing or 0
  local function applyCamera()
    pcall(function()
      if model.SetModelScale then model:SetModelScale(t.mscale or NE.ej.DEFAULT_MODEL_SCALE or 1) end
      local cdist = t.cdist or cam.cdist or NE.ej.DEFAULT_CAM_DIST
      local ctz   = t.ctz   or cam.ctz   or NE.ej.DEFAULT_CAM_TZ
      local x = (NE.ej.CAM_X0 or 1.0) - cdist * (NE.ej.CAM_XK or 0.55)
      local z = -ctz * (NE.ej.CAM_ZK or 0.9)
      if model.SetPosition then model:SetPosition(x, 0, z) end
      if model.SetFacing and not ma._userRotated then model:SetFacing(model.rotation or 0) end
    end)
  end

  -- API selection: Classic (tier 1) stores creature NPC IDs → SetCreature(npcID).
  -- TBC+ (tier 2+) stores JournalEncounterCreature.CreatureDisplayInfoID from retail EJ DB2
  -- → SetDisplayInfo(creatureDisplayInfoID), which is the standard WoW 3.3.5a API for loading
  -- a model by display ID (confirmed via WeakAuras.lua which calls SetDisplayInfo with display
  -- info IDs, not raw file IDs despite the misleading variable name in that shim).
  -- SetCreature is NOT used for TBC+ because it takes creature NPC IDs, not display info IDs
  -- (confirmed by DBM-GUI/QuestNpcModel usage, and by GetCompanionInfo returning NPC IDs which
  -- ezCollections passes to SetCreature for mount previews).
  local function loadModel()
    pcall(model.ClearModel, model)
    if tier and tier >= 2 then
      pcall(model.SetDisplayInfo, model, displayID)
    else
      pcall(model.SetCreature, model, displayID)
    end
  end

  ma._activeDisplayID = displayID   -- token to detect stale timer callbacks on boss switch
  loadModel()
  applyCamera()
  if model.HasScript and model:HasScript("OnModelLoaded") then
    model:SetScript("OnModelLoaded", applyCamera)
  end
  -- Belt-and-suspenders retry: the first load of a session can race the client's internal
  -- data lookup and come back empty. Re-issue once after a short delay.
  if C_Timer and C_Timer.After then
    C_Timer.After(0.15, function()
      if ma._activeDisplayID ~= displayID then return end   -- boss was switched, ignore
      if model:IsShown() then
        loadModel()
        applyCamera()
      end
    end)
    C_Timer.After(0.5, function()
      if ma._activeDisplayID ~= displayID then return end
      applyCamera()
      -- Final verdict: if the client still has nothing loaded after both retries, this
      -- creature's display data hasn't been seen client-side this session and never will
      -- load on its own — tell the player instead of leaving the pane blank.
      if ma.unavailable then
        local loaded = model.GetModel and model:GetModel()
        ma.unavailable:SetShown(not (loaded and loaded ~= ""))
      end
    end)
  end
  model:Show()
end

-- The single renderer: decides lore-landing vs per-boss content from (selBoss, tab)
local function refreshView()
  local f = NE.ej.frame
  if not (f and f.encounter and f.encounter.info) then return end
  local enc, info = f.encounter, f.encounter.info

  -- Tab availability. Tab 3 (the separate abilities page) is collapsed into tab 1 and never
  -- shown. Model(4) is hidden for now (the boss model pane doesn't work reliably) -- both always
  -- disabled regardless of boss selection.
  local enabled = { [1] = true, [2] = true, [3] = false, [4] = false }

  local tab = info.selectedTab or 1
  if not enabled[tab] then               -- current tab ghosted → jump to first available
    for _, id in ipairs({ 1, 2 }) do if enabled[id] then tab = id; break end end
    info.selectedTab = tab
  end

  for _, t in ipairs(info.tabs) do
    local en = enabled[t.tabID] and true or false
    local on = (t.tabID == tab) and en
    -- Enable/Disable FIRST: a button re-asserts its normal texture on enable, so doing this after
    -- the art below would put the UNSELECTED tab back on top of the selected art we just showed.
    if en then t:Enable() else t:Disable() end   -- DOWNPORT: no Button:SetEnabled on 3.3.5a
    setShown(t.selBG, on); setShown(t.selIcon, on); setShown(t.unselIcon, not on)
    -- And hide the normal (unselected) texture outright on the active tab, so the selected art
    -- never has to win a draw-order tie against it.
    local norm = t.GetNormalTexture and t:GetNormalTexture()
    if norm then setShown(norm, not on) end
    t.unselIcon:SetDesaturated(not en); t.unselIcon:SetAlpha(en and 1 or 0.35)
    if t.selIcon.SetDesaturated then t.selIcon:SetDesaturated(not en) end
  end

  local c = info.content
  c.text:Hide(); c.lootScroll:Hide(); c.sectionScroll:Hide()
  if info.modelArea then info.modelArea:Hide() end
  -- Difficulty controls — computed before the title below so the title can reserve room for them.
  -- Both axes are toggles now (no dropdown): the 10M/25M size toggle shows for RAIDS, and the
  -- heroic skull shows wherever a heroic axis exists (5-man dungeons + raidHeroic raids).
  -- Suppressed on the instance LANDING page (no boss picked) whenever the lore artwork is what's
  -- on screen — the toggles would sit over the dungeon/raid art with nothing to filter. The
  -- landing Loot tab is the exception: it aggregates instance-wide drops, which difficulty does
  -- filter, so the cluster stays for that one.
  local onLandingArt = (not selBoss) and tab ~= 2
  local isRaidDiff = (info.diffOptions and #info.diffOptions > 0) and true or false
  local hasHeroicAxis = info.HasHeroicAxis and info.HasHeroicAxis() or false
  local showSize   = (isRaidDiff and tab ~= 4 and not onLandingArt) and true or false
  local showHeroic = (hasHeroicAxis and tab ~= 4 and not onLandingArt) and true or false
  -- The shared dark well shrinks to fit whatever is up, and hides entirely when neither is.
  local dp = info.diffPanel
  if dp then
    setShown(dp, showSize or showHeroic)
    if showSize or showHeroic then dp:SetWidth(diffPanelWidth(showSize, showHeroic)) end
  end
  if info.heroicToggle then
    setShown(info.heroicToggle, showHeroic)
    if showHeroic then
      -- Always the RIGHTMOST toggle in the well.
      info.heroicToggle:ClearAllPoints()
      info.heroicToggle:SetPoint("RIGHT", dp or info, "RIGHT", -DIFF_RIGHT_PAD, DIFF_TOGGLE_DROP)
      -- difficultyID resets on every fresh instance, so re-sync the badge's lit/dim state here.
      if info.heroicToggle.SyncVisual then info.heroicToggle:SyncVisual() end
    end
  end
  if info.sizeToggle then
    setShown(info.sizeToggle, showSize)
    if showSize then
      -- Sits to the LEFT of the heroic skull when both are up; otherwise takes the well itself.
      info.sizeToggle:ClearAllPoints()
      if showHeroic and info.heroicToggle then
        info.sizeToggle:SetPoint("RIGHT", info.heroicToggle, "LEFT", -DIFF_PANEL_GAP, 0)
      else
        info.sizeToggle:SetPoint("RIGHT", dp or info, "RIGHT", -DIFF_RIGHT_PAD, DIFF_TOGGLE_DROP)
      end
      if info.sizeToggle.SyncVisual then info.sizeToggle:SyncVisual() end
    end
  end
  -- Boss title in the header is shown ONLY on the Abilities tab (hidden on Loot, which uses that
  -- header for the loot filters, and on Model) — matching retail. The title is centre-justified in
  -- its own box, so the box only shrinks by however much the header's right corner is actually
  -- occupied. Both controls are compact toggles now, so the name stays close to centred.
  local hideBossTitle = (tab == 4 or tab == 2)
  if info.encounterTitle then
    info.encounterTitle:SetText(selBoss and selBoss.name or "")
    local showTitle = (selBoss and not hideBossTitle) and true or false
    setShown(info.encounterTitle, showTitle)
    if showTitle then
      -- Shrink by however much the difficulty well actually occupies, so the tiers stay correct if
      -- the cluster's geometry constants change.
      local titleW = 360                                        -- nothing in the corner
      if showSize or showHeroic then
        titleW = 360 - diffPanelWidth(showSize, showHeroic) + 12
      end
      info.encounterTitle:ClearAllPoints()
      info.encounterTitle:SetPoint("TOPLEFT", info, "TOPLEFT", 400, -14)
      info.encounterTitle:SetWidth(titleW)
    end
  end
  if info.rightHeader then setShown(info.rightHeader, tab ~= 4) end
  if info.lootFilter then
    setShown(info.lootFilter, tab == 2)   -- slot filter only on Loot
    -- LEFT-aligned on the loot page. The right page starts at x=400 (where info.content is
    -- anchored); the -16 backs out UIDropDownMenuTemplate's invisible left inset so the visible box
    -- edge — not the frame edge — lands on 400, and the +15 then insets it from that page edge.
    -- Fixed anchor: it no longer trails the difficulty well, since the two are now at opposite ends
    -- of the header and cannot collide.
    info.lootFilter:ClearAllPoints()
    info.lootFilter:SetPoint("TOPLEFT", info, "TOPLEFT", 400 - 16 + 15, -10)
  end
  if info.lootFilterClear then
    -- Clear badge only when there is something to clear. (It parents into the dropdown, so the
    -- tab check is belt-and-braces — but refreshView is also what re-shows it after a reset.)
    setShown(info.lootFilterClear, tab == 2 and (info.lootSlot or "ALL") ~= "ALL")
  end

  if not selBoss then
    if tab == 2 then            -- instance landing Loot = aggregated instance-wide drops
      enc.instance:Hide()       -- don't leave the lore artwork showing beneath the loot
      local agg, seen = {}, {}
      for _, e in ipairs((selInst and selInst.encounters) or {}) do
        for _, entry in ipairs(e.loot or {}) do
          local eid = (type(entry) == "table") and entry.id or entry
          if eid and not seen[eid] then seen[eid] = true; agg[#agg + 1] = entry end
        end
      end
      renderLoot({ loot = agg }); c.lootScroll:Show()
    else
      enc.instance:Show()       -- lore landing on the right page
    end
    return
  end
  enc.instance:Hide()

  if tab == 2 then            -- Loot
    renderLoot(selBoss); c.lootScroll:Show()
  elseif tab == 4 then        -- Model
    local ma = info.modelArea
    if ma then
      -- per-instance model backdrop (JournalInstance.BGFileDataID); default if unshipped
      local bgFD = selInst and selInst.bgFDID
      ma.bg:SetTexture(NE.tex.localFiles[bgFD] or NE.tex.localFiles[521743] or 521743)
      ma.name:SetText(selBoss.name or "")
      -- Show ma BEFORE NormalizeModel: the 3.3.5a engine silently skips SetCreature while the
      -- frame ancestor chain is hidden, so the model would never load if we called it first.
      ma:Show()
      local cr = selBoss.creatures and selBoss.creatures[1]
      NE.ej.NormalizeModel(ma, cr and cr.display, selInst and selInst.tier)
    else
      c.text:SetText("(no model)"); c.text:Show()
    end
  else                        -- tab 1 = lore description + ability sections
    if (selBoss.sections and #selBoss.sections > 0) or (selBoss.desc and selBoss.desc ~= "") then
      renderSections(selBoss); c.sectionScroll:Show()
    else
      c.text:SetText("(No abilities recorded for this encounter.)"); c.text:Show()
    end
  end
end

-- Public API
function NE.ej.SelectTab(id)
  local f = NE.ej.frame
  if not (f and f.encounter and f.encounter.info) then return end
  f.encounter.info.selectedTab = id
  refreshView()
end

function NE.ej.ShowBoss(enc)
  selBoss = enc
  if NE.ej.frame then NE.ej.frame._currentBoss = enc end
  applyBossHighlight()   -- keep the clicked boss row highlighted
  refreshView()
  if NE.ej.RefreshNavBar then NE.ej.RefreshNavBar() end   -- breadcrumb extends to the boss
end

-- "Show Map". DOWNPORT: only live if a NE.worldmap.ShowDungeonMap provider exists (the
-- NewEra dungeon-map overlay hasn't been ported); 3.3.5a has no classic/TBC dungeon maps and
-- no WorldMapFrame:SetMapID, so there is no native fallback.
function NE.ej.ShowMap(inst)
  if InCombatLockdown() then return end
  inst = inst or selInst
  if not inst then return end
  if NE.worldmap and NE.worldmap.ShowDungeonMap and inst.id and NE.worldmap.ShowDungeonMap(inst.id) then
    return
  end
end

function NE.ej.PopulateEncounter(inst)
  selInst, selBoss = inst, nil
  local enc = NE.ej.frame.encounter
  enc.instance.title:SetText(inst.name or "")
  if enc.info.instanceTitle then enc.info.instanceTitle:SetText(inst.name or "") end
  -- Multi-difficulty gate for the difficulty dropdown: TBC/WotLK dungeons run Normal + Heroic
  -- (hasHeroic, static 2-option list built in buildInfoPanel); WotLK raids run 10/25-Player,
  -- plus a separate Heroic mode on ICC/Ruby Sanctum/Trial of the Grand Crusader (inst.raidHeroic)
  -- -- a data-driven diffOptions list instead, since the option COUNT varies per raid.
  -- difficultyID always resets to 1 (Normal / 10-Player Normal) on entering a fresh instance.
  enc.info.difficultyID = 1
  if inst.isRaid and inst.tier == 3 then
    enc.info.hasHeroic = false
    -- retail EJ difficulty-dropdown format: "(10) Normal", not the LFD tool's "10 Player (Normal)".
    local normalLbl, heroicLbl = _G.PLAYER_DIFFICULTY1 or "Normal", _G.PLAYER_DIFFICULTY2 or "Heroic"
    local opts = {
      { id = 1, size = 10, heroic = false, label = ("(%d) %s"):format(10, normalLbl) },
      { id = 2, size = 25, heroic = false, label = ("(%d) %s"):format(25, normalLbl) },
    }
    if inst.raidHeroic then
      opts[3] = { id = 3, size = 10, heroic = true, label = ("(%d) %s"):format(10, heroicLbl) }
      opts[4] = { id = 4, size = 25, heroic = true, label = ("(%d) %s"):format(25, heroicLbl) }
    end
    enc.info.diffOptions = opts
  else
    enc.info.hasHeroic = (NE.flavor == "tbc" and (inst.tier == 2 or inst.tier == 3) and not inst.isRaid) or false
    enc.info.diffOptions = nil
  end
  -- per-instance loading-screen lore background (LoreFileDataID)
  if inst.loreFDID and inst.loreFDID > 0 and enc.instance.loreBG then
    enc.instance.loreBG:SetTexture(NE.tex.localFiles[inst.loreFDID] or inst.loreFDID)
    enc.instance.loreBG:SetTexCoord(0, 0.7617187, 0, 0.65625)
  end
  enc.instance.lore:SetText(inst.desc or "")
  if enc.instance.loreChild then
    enc.instance.loreChild:SetHeight(math.max(1, (enc.instance.lore:GetStringHeight() or 0) + 4))
  end
  -- "Show Map" only when a dungeon-map provider can actually serve this instance.
  if enc.instance.mapButton then
    setShown(enc.instance.mapButton,
      (NE.worldmap and NE.worldmap.ShowDungeonMap and inst.id) and true or false)
  end
  -- dungeon-specific back-button portrait (the instance's splash under the ring)
  local ib = enc.info and enc.info.instanceButton
  if ib and ib.icon and inst.buttonFDID and inst.buttonFDID > 0 then
    ib.icon:SetTexture(NE.tex.localFiles[inst.buttonFDID] or inst.buttonFDID)
    NE.ej.SetButtonTexCoord(ib.icon, inst.buttonFDID, true)
  end
  fillBossList(inst)
  -- Prime the whole instance's loot up front so the very first Loot-tab view of a fresh
  -- session (before any difficulty toggle has run renderLoot's priming loop) isn't empty.
  if NE.ej.PrimeItem and inst.encounters then
    for _, e in ipairs(inst.encounters) do
      for _, entry in ipairs(e.loot or {}) do
        local id = (type(entry) == "table") and entry.id or entry
        if id then NE.ej.PrimeItem(id) end
      end
    end
  end
  enc.info.selectedTab = 1
  refreshView()
end

function NE.ej.BuildEncounterPage(f)
  local enc = f.encounter
  if not enc or enc._neBuilt then return end
  enc._neBuilt = true
  -- pcall each: a failure in one panel must not skip the other.
  local okI = pcall(buildInfoPanel, enc)   -- info first = book backdrop; lore layers on the right
  local okL = pcall(buildLorePanel, enc)
  if not (okI and okL) and NE.Log then NE.Log("EJ", "BuildEncounterPage: info=%s lore=%s", tostring(okI), tostring(okL)) end
  -- retail layers instance ABOVE info; as plain children both default to enc+1 → equal
  -- sibling levels draw non-deterministically. Pin both to reproduce retail's split.
  local lvl = enc:GetFrameLevel()
  if enc.info then enc.info:SetFrameLevel(lvl) end
  if enc.instance then enc.instance:SetFrameLevel(lvl + 1) end
end
