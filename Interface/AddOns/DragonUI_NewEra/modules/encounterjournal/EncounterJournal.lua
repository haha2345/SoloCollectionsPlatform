-- DragonUI_NewEra/modules/encounterjournal/EncounterJournal.lua — the NE_EncounterJournal
-- window shell. Builds the journal window chrome + the instance-select grid (Dungeons/Raids
-- tabs, expansion-tier filter, search). The encounter view (boss list, ability/loot/model
-- tabs) lives in EncounterPage.lua; the breadcrumb navbar in NavBar.lua.
--
-- DOWNPORT of NewEra/EncounterJournal/EncounterJournal.lua (Classic 1.15) onto 3.3.5a:
--   * Window chrome: NewEra's NE_PortraitWindowTemplate → the AH/Guild recipe (ClassicAPI
--     PortraitFrameTemplate + DF metal nineslice overlay + title + modernized close).
--   * Inset: retail InsetFrameTemplate → plain frame + NE.nineslice "InsetFrameTemplate"
--     layout (the character-panel InsetFrames pattern).
--   * Expansion dropdown: retail DropdownButton/WowStyle1 → NE.ej.CreateDropdown (Support.lua,
--     native UIDropDownMenu underneath).
--   * NE.flavor is pinned "tbc" (Assets.lua): this WotLK server serves Classic + TBC content,
--     so the dropdown is the expansion-TIER selector and TBC dungeons get Normal/Heroic.
--     The Era-only continent/phase filter path is kept (dead) for parity with the source.
--   * No NE.panelmgr on 3.3.5a (guarded call stays); ESC-close via UISpecialFrames.
--   * Opens via /aguide (/adventureguide, /ej), the ToggleEncounterJournal global we CREATE
--     (3.3.5a ships none — the EJ is a Cataclysm feature), and a Bindings.xml entry.
--
-- Layout transcribed from retail Cata Blizzard_EncounterJournal.xml:1190-1300 (12.0.5.67451):
--   Frame "EncounterJournal" PortraitFrameTemplate 800x496 CENTER
--   inset  InsetFrameTemplate  TOPRIGHT(-4,-60) BOTTOMLEFT(4,5)
--   instanceSelect -> inset TOPLEFT(0,-2)/BOTTOMRIGHT(-3,0); bg, Title TOPLEFT(20,-15),
--                     ExpansionDropdown TOPRIGHT(-24,-10), ScrollBox 748x367 TOPLEFT(14,-50)

local NE = DragonUI_NewEra
if not NE then return end

NE.ej = NE.ej or {}

local FRAME_W, FRAME_H = 800, 496
local MODULE = "EncounterJournal"

-- Pixel-perfect scale (pin to 768/physH, never raw SetScale numbers). This is THE scale knob for
-- the whole window (chrome + every nested panel) — PinPixelPerfect folds it into the frame's
-- SetScale without touching any internal layout math. A raw frame:SetScale() elsewhere is useless:
-- pinScale() runs on build/show/reposition and overwrites it, so change the window size HERE.
-- 2026-07-23: bumped 1.25 → 1.5 (user asked for +20% on top of the previous 1.25).
--
-- 2026-08-09: that 1.5 moved into core/Scale.lua as BASE_SCALE["encounterjournal"], and the window
-- became a normal entry in the options tab's Window Scaling list (mode: ui / none / custom). Its
-- default mode is "none", which IS PinPixelPerfect(f, 1.5) — so the shipped look is unchanged, and
-- pinScale() below still means "put this window at whatever size it should currently be", called
-- from the same three places as before. WINDOW_USER_SCALE stays as the no-NE.scale fallback.
local WINDOW_USER_SCALE = 1.5
local function pinScale(f)
  if not f then return end
  if NE.scale and NE.scale.Apply then
    if NE.scale.SetFrame then NE.scale.SetFrame("encounterjournal", f) end
    NE.scale.Apply("encounterjournal")
    return
  end
  NE.FrameUtil.PinPixelPerfect(f, WINDOW_USER_SCALE)
end

-- Options gate. The boot registry reads DragonUI's canonical profile.modules.ne_* entry.
local function isModuleEnabled()
  return not (NE.modules and NE.modules.IsEnabled) or NE.modules.IsEnabled(MODULE)
end

-- Classic content classification for the instance-select filter dropdown (Era flavor only;
-- dead on this 3.3.5a port where NE.flavor=="tbc" — kept verbatim for source parity).
local EJ_CONTINENT = {
  -- Kalimdor
  [226]="Kalimdor", [240]="Kalimdor", [227]="Kalimdor", [234]="Kalimdor", [233]="Kalimdor",
  [232]="Kalimdor", [241]="Kalimdor", [230]="Kalimdor", [1276]="Kalimdor", [1277]="Kalimdor",
  -- Eastern Kingdoms
  [63]="EK", [64]="EK", [231]="EK", [238]="EK", [316]="EK", [239]="EK", [246]="EK",
  [228]="EK", [237]="EK", [229]="EK", [236]="EK", [1292]="EK",
}
local EJ_PHASE = {
  [741]=1, [760]=1,   -- Phase 1: Molten Core, Onyxia's Lair
  [742]=3,            -- Phase 3: Blackwing Lair
  [76]=4,             -- Phase 4: Zul'Gurub
  [743]=5, [744]=5,   -- Phase 5: Ruins of Ahn'Qiraj, Temple of Ahn'Qiraj
  [754]=6,            -- Phase 6: Naxxramas
}
local EJ_CONTINENT_OPTS = {
  { key="all",      label = ALL or "All" },
  { key="EK",       label = "Eastern Kingdoms" },
  { key="Kalimdor", label = "Kalimdor" },
}
local EJ_PHASE_OPTS = {
  { key="all", label = ALL or "All" },
  { key=1, label="Phase 1" }, { key=3, label="Phase 3" }, { key=4, label="Phase 4" },
  { key=5, label="Phase 5" }, { key=6, label="Phase 6" },
}

-- Expansion-tier grouping (the NE.flavor=="tbc" path — LIVE here). Each instance carries
-- inst.tier (vanilla DATA has none → Classic/1; DataTBC tags its instances tier=2). Mirrors
-- retail Cata's EJ_TIER_DATA (Blizzard_EncounterJournal.lua:89-96).
-- tier 3 (Wrath) now has real instances (bosses + loot, hand-seeded from AtlasLoot — see
-- DataWotLK.lua header for what's still missing), so tierHasInstances() below shows it.
local EJ_TIER = {
  [1] = { label = EXPANSION_NAME0 or "Classic",             bg = 605327 },  -- UI-EJ-Classic
  [2] = { label = EXPANSION_NAME1 or "The Burning Crusade", bg = 605326 },  -- UI-EJ-BurningCrusade
  [3] = { label = EXPANSION_NAME2 or "Wrath of the Lich King", bg = 605329 },  -- UI-EJ-WrathoftheLichKing
}
local EJ_DEFAULT_TIER = 1

-- True once DataWotLK.lua (or any future tier) actually has at least one instance — keeps an
-- empty scaffolded tier out of the dropdown instead of showing a permanently-blank grid.
local function tierHasInstances(tier)
  local D = NE.ej.DATA
  if not D then return false end
  for _, inst in ipairs(D.instances or {}) do
    if (inst.tier or 1) == tier then return true end
  end
  return false
end

-- Window chrome — the AH/Guild recipe (modules/auctionhouse/Window.lua buildChrome), EJ
-- portrait/title. The ClassicAPI PortraitFrameTemplate supplies rock body + f.portrait +
-- f.TitleText; we overlay the DF metal nineslice + streaks + modernized close on top.
local function buildChrome(f)
  -- Modern grey window body: the same untinted UI-Background-Rock fill every other from-scratch
  -- standalone window builds (Guild/LFG/Professions/AuctionHouse/Social).
  --
  -- DOWNPORT FIX: we own a DEDICATED texture rather than re-texturing the template's own fill.
  --
  -- ClassicAPI's PortraitFrameTemplate declares that fill as `$parentBg` with NO parentKey
  -- (Templates/UIPanelTemplates.xml), so `f.Bg` is NIL on 3.3.5a and any `if f.Bg` guard silently
  -- no-ops — it has to be resolved by GLOBAL NAME. It is also the OLD stone
  -- (!!!ClassicAPI\Texture\FrameGeneral\UI-Background-Rock) at BACKGROUND subLevel -6, so a body
  -- texture below that draws behind it. Hence both halves of the fix: hide it by name, and sit
  -- ABOVE -6 so we still win if anything re-shows it. Re-applied on OnShow for the same reason.
  local rockPath = (NE.tex and NE.tex.localFiles and NE.tex.localFiles[374155]) or 374155
  local function templateBg()
    if f.Bg and f.Bg ~= f._neBody then return f.Bg end
    local n = f.GetName and f:GetName()
    local t = n and _G[n .. "Bg"]
    if t and t ~= f._neBody then return t end
  end
  local function applyBody()
    local old = templateBg()
    if old and old.Hide then old:Hide() end
    local body = f._neBody
    if not body then
      body = f:CreateTexture(nil, "BACKGROUND", nil, -5)
      body:SetPoint("TOPLEFT",     f, "TOPLEFT",      4, -21)
      body:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT",  0,   0)
      f._neBody = body
    end
    body:SetTexture(rockPath, "REPEAT", "REPEAT")
    body:SetHorizTile(true); body:SetVertTile(true)
    body:SetVertexColor(1, 1, 1)   -- untinted / full brightness (the "modern grey", not a dimmed wash)
    body:Show()
  end
  applyBody()
  f:HookScript("OnShow", applyBody)

  local streaks = f:CreateTexture(nil, "BORDER")
  if NE.tex and NE.tex.SetAtlas then NE.tex.SetAtlas(streaks, "_UI-Frame-TopTileStreaks", false) end
  streaks:SetPoint("TOPLEFT", f, "TOPLEFT", 6, -21)
  streaks:SetPoint("TOPRIGHT", f, "TOPRIGHT", -2, -21)
  streaks:SetHeight(43); streaks:SetHorizTile(true)

  local ns = CreateFrame("Frame", nil, f)
  ns:SetAllPoints(f)
  if NE.nineslice and NE.nineslice.ApplyLayout then
    NE.nineslice.ApplyLayout(ns, "PortraitFrameTemplate")
  end
  f.NineSlice = ns

  local title = ADVENTURE_JOURNAL or "Adventure Guide"
  -- Pass the template's TitleText explicitly: PC.SetTitle only auto-finds
  -- frame.TitleContainer.TitleText / frame.Title, neither of which PortraitFrameTemplate has.
  if NE.panelchrome and NE.panelchrome.SetTitle and f.TitleText then
    NE.panelchrome.SetTitle(f, title, f.TitleText)
  elseif f.TitleText and f.TitleText.SetText then
    f.TitleText:SetText(title)
  end

  local close = CreateFrame("Button", "NE_EncounterJournalCloseButton", f, "UIPanelCloseButton")
  close:SetPoint("TOPRIGHT", f, "TOPRIGHT", 1, 0)
  close:SetScript("OnClick", function() NE.ej.Close() end)
  if NE.panelchrome and NE.panelchrome.ModernizeCloseButton then
    NE.panelchrome.ModernizeCloseButton(close, { frameLevelBump = 10 })
  end

  -- Round portrait: the journal book icon (UI-EJ-PortraitIcon), seated in the metal corner
  -- cutout. CORRECTION: a prior attempt hosted this on its own frame leveled ABOVE `ns` — that
  -- put the square icon ON TOP of the ring with nothing left to crop its corners (confirmed
  -- worse in-game: a fully exposed square over the ring, not a partial crop). The ring can only
  -- mask the icon's corners if the icon is BELOW the ring's corner art within the SAME frame —
  -- exactly the pattern spellbook/Window.lua uses ("host the portrait on f.NineSlice too, at
  -- ARTWORK (< BORDER): that puts it over the wood yet under the ring. A separate high-level
  -- holder drew it OVER the ring."). NineSliceLayouts.lua's PortraitFrameTemplate.TopLeftCorner
  -- is layer OVERLAY, so ARTWORK on the same frame (`ns`) sits under it. Size/anchor come from
  -- NE.portrait.ApplyCutout's own defaults (60x60 @ TOPLEFT -5,8), matching every other window's
  -- corner portrait so the ring's opaque corner pixels line up with the icon's edges.
  if not f.portrait then
    f.portrait = ns:CreateTexture(nil, "ARTWORK")
  end
  if NE.portrait and NE.portrait.ApplyCutout then
    NE.portrait.ApplyCutout(f.portrait, f)
  else
    f.portrait:ClearAllPoints()
    f.portrait:SetSize(60, 60)
    f.portrait:SetPoint("TOPLEFT", f, "TOPLEFT", -5, 8)
  end
  f.portrait:SetTexture(NE.tex.localFiles[521753] or "Interface\\Icons\\INV_Misc_Book_09")
  f.Portrait = f.portrait
end

-- Instance-select page (the dungeon/raid grid landing).
local function buildInstanceSelect(f)
  local page = CreateFrame("Frame", "NE_EncounterJournalInstanceSelect", f)
  page:SetPoint("TOPLEFT",     f.inset, "TOPLEFT",      0, -2)
  page:SetPoint("BOTTOMRIGHT", f.inset, "BOTTOMRIGHT", -3,  0)
  -- DOWNPORT: pin above the inset's nineslice pieces (sibling frames at equal level draw
  -- non-deterministically on 3.3.5a — the nineslice frame-level pitfall).
  page:SetFrameLevel(f.inset:GetFrameLevel() + 2)
  f.instanceSelect = page

  -- On this port the dropdown is always the expansion-tier selector (NE.flavor pinned "tbc").
  local isTBC = (NE.flavor == "tbc")
  page._isTBC = isTBC

  local bg = page:CreateTexture(nil, "BACKGROUND")
  bg:SetTexture(NE.tex.localFiles[605327] or 605327)   -- UI-EJ-Classic
  bg:SetAllPoints(page)
  bg:SetTexCoord(0, 1, 0, 1)
  page.bg = bg

  -- Per-tier background swap (tier dropdown). Both tier backgrounds are standalone
  -- full-image BLPs, so the crop matches the Classic default exactly.
  function page.SetTierBackground(tier)
    local td = EJ_TIER[tier]; if not (td and td.bg) then return end   -- no bg yet (e.g. tier 3 scaffold) -> keep current art
    bg:SetTexture(NE.tex.localFiles[td.bg] or td.bg)
    bg:SetTexCoord(0, 1, 0, 1)
  end

  -- Page title — retail "DUNGEONS" TOPLEFT(20,-15).
  local title = page:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
  title:SetJustifyH("LEFT")
  title:SetPoint("TOPLEFT", page, "TOPLEFT", 20, -15)
  title:SetText(DUNGEONS or "Dungeons")
  page.Title = title

  -- Filter dropdown (expansion tier here; continent/phase on Era). DOWNPORT: the retail
  -- DropdownButton → NE.ej.CreateDropdown; the UIDropDownMenuTemplate art carries ~16px of
  -- side padding, so the anchor compensates vs retail's (-24,-10).
  if not InCombatLockdown() then
    local dd = NE.ej.CreateDropdown(page, "NE_EncounterJournalExpansionDropdown", 150)
    dd:SetPoint("TOPRIGHT", page, "TOPRIGHT", -8, -8)
    page.ExpansionDropdown = dd
  end

  -- Real scroll viewport + modern reskinned scrollbar. retail: ScrollBox 748×367 at
  -- TOPLEFT(14,-50), bar in the right-hand gutter.
  local scrollFrame = CreateFrame("ScrollFrame", "NE_EJInstanceScroll", page, "UIPanelScrollFrameTemplate")
  scrollFrame:SetPoint("TOPLEFT", page, "TOPLEFT", 14, -50)
  scrollFrame:SetSize(748, 367)
  -- DOWNPORT: the 3.3.5a template exposes the bar only as a $parentScrollBar global.
  scrollFrame.ScrollBar = scrollFrame.ScrollBar or _G["NE_EJInstanceScrollScrollBar"]
  local scroll = CreateFrame("Frame", nil, scrollFrame)
  scroll:SetSize(748, 1)
  scrollFrame:SetScrollChild(scroll)
  if NE.scrollbar and NE.scrollbar.Reskin then NE.scrollbar.Reskin(scrollFrame, { hideIfUnscrollable = true, x = 12 }) end
  page.gridScrollFrame, page.gridScroll = scrollFrame, scroll

  -- Instance grid (pooled buttons) split by Dungeons / Raids bottom tabs.
  -- EncounterInstanceButtonTemplate = 174x96 (EJ.xml:319); 4-col grid.
  local COLS, BW, BH, GX, GY = 4, 174, 96, 9, 8
  local GRID_X_PAD = 4
  page.instButtons = {}

  local dungeons, raids, D = {}, {}, NE.ej.DATA
  if D then
    for _, inst in ipairs(D.instances or {}) do
      local e = { name = inst.name, inst = inst, minLevel = inst.minLevel or 0 }
      -- Shell instances (no encounter data) render deferred-style: greyed, non-clickable.
      if inst.shell then e.deferred = true; e.deferredText = "Data coming soon" end
      if inst.isRaid then raids[#raids + 1] = e else dungeons[#dungeons + 1] = e end
    end
    for _, d in ipairs(D.deferred or {}) do
      dungeons[#dungeons + 1] = { name = d.name, deferred = true, buttonFDID = d.buttonFDID, minLevel = d.minLevel or 0 }
    end
    table.sort(dungeons, function(a, b) return (a.minLevel or 0) < (b.minLevel or 0) end)  -- level order
    table.sort(raids,    function(a, b) return (a.minLevel or 0) < (b.minLevel or 0) end)
  end

  local function poolButton(i)
    local b = page.instButtons[i]
    if b then return b end
    b = CreateFrame("Button", nil, scroll)
    b:SetSize(BW, BH)
    -- per-instance splash at BACKGROUND (the dominant visual). Crop texcoord (0,0.6836,0,0.7422).
    -- Inset 1px left/right + 3px off the bottom: the "Up" frame border art's opaque edge is a
    -- touch narrower/shorter than the button's full 174x96 rect, so a full SetAllPoints splash
    -- peeked out past the card border on the sides and into the row gap below. Pulling the
    -- splash's edges in hides the overhang behind the border, which still covers the full
    -- button rect at ARTWORK on top.
    b.bgImage = b:CreateTexture(nil, "BACKGROUND")
    b.bgImage:SetPoint("TOPLEFT", b, "TOPLEFT", 1, 0)
    b.bgImage:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", -1, 3)
    b.bgImage:SetTexCoord(0, 0.68359375, 0, 0.7421875)
    -- UI-EJ-DungeonButton frame at ARTWORK (over the splash; its center is transparent).
    b.up = b:CreateTexture(nil, "ARTWORK"); NE.ej.ApplySlice(b.up, "UI-EJ-DungeonButton-Up");        b.up:SetAllPoints(b); b:SetNormalTexture(b.up)
    b.hi = b:CreateTexture(nil, "HIGHLIGHT"); NE.ej.ApplySlice(b.hi, "UI-EJ-DungeonButton-Highlight"); b.hi:SetAllPoints(b); b:SetHighlightTexture(b.hi)
    b.dn = b:CreateTexture(nil, "ARTWORK"); NE.ej.ApplySlice(b.dn, "UI-EJ-DungeonButton-Down");      b.dn:SetAllPoints(b); b:SetPushedTexture(b.dn)
    b.label = b:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    b.label:SetPoint("BOTTOM", b, "BOTTOM", 0, 10); b.label:SetWidth(BW - 16); b.label:SetJustifyH("CENTER")
    NE.font.Set(b.label, NE.font.MORPHEUS, 13, "", GameFontNormal)
    b.label:SetShadowColor(0, 0, 0, 1); b.label:SetShadowOffset(1, -1)
    page.instButtons[i] = b
    return b
  end

  function page.renderGrid(entries)
    for _, b in ipairs(page.instButtons) do b:Hide() end
    for i, e in ipairs(entries) do
      local b = poolButton(i)
      local col, row = (i - 1) % COLS, math.floor((i - 1) / COLS)
      b:ClearAllPoints()
      b:SetPoint("TOPLEFT", scroll, "TOPLEFT", GRID_X_PAD + col * (BW + GX), -row * (BH + GY))
      b.label:SetText(e.name)
      b.up:SetDesaturated(e.deferred and true or false)
      local fdid = e.buttonFDID or (e.inst and e.inst.buttonFDID)
      if fdid and fdid > 0 then
        b.bgImage:SetTexture(NE.tex.localFiles[fdid] or fdid)
        NE.ej.SetButtonTexCoord(b.bgImage, fdid, false)
        b.bgImage:SetDesaturated(e.deferred and true or false)
        b.bgImage:Show()
      else
        b.bgImage:Hide()
      end
      b:SetScript("OnClick", nil); b:SetScript("OnEnter", nil); b:SetScript("OnLeave", nil)
      if e.deferred then
        b.label:SetTextColor(0.5, 0.5, 0.5)
        NE.tooltip.Wire(b, function(_, tip)
          -- DOWNPORT: GameTooltip_SetTitle/AddColoredLine are retail-only.
          tip:SetText(e.name, 1, 1, 1)
          tip:AddLine(e.deferredText or "Data coming soon", 0.5, 0.5, 0.5, true)
        end)
      else
        b.label:SetTextColor(1, 0.82, 0)
        b:SetScript("OnClick", function()
          if PlaySound and SOUNDKIT then PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON) end
          NE.ej.ShowInstance(e.inst)
        end)
      end
      b:Show()
    end
    scroll:SetHeight(math.max(1, math.ceil(#entries / COLS) * (BH + GY)))  -- drives scroll range
  end

  -- Apply the filter dropdown (tier here; continent/phase on Era) to the active category.
  function page.applyInstanceFilter()
    local cat = page._category or dungeons
    local out
    if page._isTBC then
      local tier = page._tier or EJ_DEFAULT_TIER
      out = {}
      for _, e in ipairs(cat) do
        if ((e.inst and e.inst.tier) or 1) == tier then out[#out + 1] = e end
      end
    else
      local key = page._filterKey or "all"
      if key == "all" then
        out = cat
      else
        out = {}
        for _, e in ipairs(cat) do
          local id  = e.inst and e.inst.id
          local cls = id and (page._isRaid and EJ_PHASE[id] or EJ_CONTINENT[id]) or nil
          if cls == key then out[#out + 1] = e end
        end
      end
    end
    page._activeEntries = out
    page.renderGrid(out)
    -- keep the grid in sync with any live search text (NE.ej.ReadSearchText treats the
    -- SearchBoxTemplate placeholder as "no search" -- see Support.lua).
    local sb = f._neSearchBox
    local txt = NE.ej.ReadSearchText and NE.ej.ReadSearchText(sb) or ""
    if NE.ej.FilterGrid then NE.ej.FilterGrid(txt) end
  end

  -- Menu generator reads page state each open; one SetupMenu serves both categories.
  if page.ExpansionDropdown and page.ExpansionDropdown.SetupMenu then
    page.ExpansionDropdown:SetupMenu(function(_, root)
      if page._isTBC then
        for tier = 1, #EJ_TIER do
          local t = tier
          if tierHasInstances(t) then
            root:CreateRadio(EJ_TIER[t].label,
              function() return (page._tier or EJ_DEFAULT_TIER) == t end,
              function()
                page._tier = t
                if NE.db then NE.db.ej = NE.db.ej or {}; NE.db.ej.tier = t end  -- persist the chosen tier
                page.SetTierBackground(t)
                page.applyInstanceFilter()
                if C_Timer and C_Timer.After then
                  C_Timer.After(0, function() page.ExpansionDropdown:GenerateMenu() end)
                end
              end)
          end
        end
        return
      end
      local opts = page._isRaid and EJ_PHASE_OPTS or EJ_CONTINENT_OPTS
      for _, o in ipairs(opts) do
        local k = o.key
        root:CreateRadio(o.label,
          function() return (page._filterKey or "all") == k end,
          function()
            page._filterKey = k
            page.applyInstanceFilter()
            if C_Timer and C_Timer.After then
              C_Timer.After(0, function() page.ExpansionDropdown:GenerateMenu() end)
            end
          end)
      end
    end)
  end

  -- Dungeons / Raids bottom tabs — DF metal reskin via the shared NE.tabs walker (core/Tabs.lua),
  -- the same CharacterFrameTabButtonTemplate + ReskinClassicTab pattern used by the character panel,
  -- Collections, Social, Spellbook, Talents and Auction House. Art/height/level are driven manually
  -- (setTabArt below) rather than PanelTemplates_SelectTab, matching those modules.
  local TAB_H_INACTIVE, TAB_H_ACTIVE = 36, 42

  local dunTab = CreateFrame("Button", "NE_EJDungeonsTab", f, "CharacterFrameTabButtonTemplate")
  dunTab:SetText(DUNGEONS or "Dungeons")
  local raidTab = CreateFrame("Button", "NE_EJRaidsTab", f, "CharacterFrameTabButtonTemplate")
  raidTab:SetText(RAIDS or "Raids")
  page.dunTab, page.raidTab = dunTab, raidTab

  if NE.tabs and NE.tabs.ReskinClassicTab then
    pcall(NE.tabs.ReskinClassicTab, "NE_EJDungeonsTab", {})
    pcall(NE.tabs.ReskinClassicTab, "NE_EJRaidsTab", {})
  end

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
    if text then text:SetWidth(0); w = math.max(70, math.floor((text:GetWidth() or 0) + 24)) end
    tab:SetWidth(w)
  end

  local function rechainTabs()
    dunTab:ClearAllPoints(); dunTab:SetPoint("TOPLEFT", f, "BOTTOMLEFT", 11, 2)
    raidTab:ClearAllPoints(); raidTab:SetPoint("TOPLEFT", dunTab, "TOPRIGHT", 1, 0)
  end

  sizeTab(dunTab); dunTab:SetHeight(TAB_H_INACTIVE)
  sizeTab(raidTab); raidTab:SetHeight(TAB_H_INACTIVE)
  rechainTabs()

  local function selectCat(isRaid)
    -- a bottom tab always returns to the instance grid (retail) — works from a boss page
    f._currentInstance = nil; f._currentBoss = nil
    if f.encounter then f.encounter:Hide() end
    page:Show()
    if NE.ej.RefreshNavBar then NE.ej.RefreshNavBar() end
    page._category = isRaid and raids or dungeons
    page._isRaid   = isRaid
    if page._isTBC then
      -- the expansion tier persists across the Dungeons↔Raids toggle (retail parity)
      page._tier = page._tier or (NE.db and NE.db.ej and NE.db.ej.tier) or EJ_DEFAULT_TIER
      page.SetTierBackground(page._tier)
    else
      page._filterKey = "all"
    end
    if page.ExpansionDropdown and page.ExpansionDropdown.GenerateMenu then
      page.ExpansionDropdown:GenerateMenu()
    end
    page.applyInstanceFilter()

    -- selected -> gold/active art, taller body, raised above its neighbour (DF metal look).
    setTabArt(dunTab, not isRaid); setTabArt(raidTab, isRaid)
    dunTab:SetHeight(isRaid and TAB_H_INACTIVE or TAB_H_ACTIVE)
    raidTab:SetHeight(isRaid and TAB_H_ACTIVE or TAB_H_INACTIVE)
    sizeTab(dunTab); sizeTab(raidTab)
    rechainTabs()
    local base = f:GetFrameLevel()
    dunTab:SetFrameLevel(base + (isRaid and 4 or 10))
    raidTab:SetFrameLevel(base + (isRaid and 10 or 4))
    local dunTxt, raidTxt = _G["NE_EJDungeonsTabText"], _G["NE_EJRaidsTabText"]
    if dunTxt  then dunTxt:ClearAllPoints();  dunTxt:SetPoint("CENTER", dunTab, "CENTER", 0, isRaid and 0 or -3) end
    if raidTxt then raidTxt:ClearAllPoints(); raidTxt:SetPoint("CENTER", raidTab, "CENTER", 0, isRaid and -3 or 0) end
    if page.Title then page.Title:SetText(isRaid and (RAIDS or "Raids") or (DUNGEONS or "Dungeons")) end
  end
  local function playPageTurn()
    if PlaySound then pcall(PlaySound, "igCharacterInfoTab") end
  end
  dunTab:SetScript("OnClick",  function() playPageTurn(); selectCat(false) end)
  raidTab:SetScript("OnClick", function() playPageTurn(); selectCat(true) end)
  page.SelectCategory = selectCat
  selectCat(false)   -- default to Dungeons

  -- Text measurement is unreliable until the frame has been shown once: this runs during the LAZY
  -- build, while `f` is still hidden, and the template's Text reports its XML width rather than the
  -- string width until then. So the build-time sizeTab() overshoots and the tabs visibly shrink on
  -- the first click (which re-runs sizeTab via selectCat, now that the frame is up). Re-size on
  -- show — NE.tabs.SizeAndAnchorTabs hooks OnShow for this same reason, but we can't use that
  -- helper here because the art/height/level are driven manually.
  f:HookScript("OnShow", function()
    sizeTab(dunTab); sizeTab(raidTab)
    rechainTabs()
  end)
end

-- Build + toggle
local frame
local function build()
  if frame then return frame end
  frame = CreateFrame("Frame", "NE_EncounterJournal", UIParent, "PortraitFrameTemplate")
  -- The red 3-slice is the addon's standard button; Watch keeps this window's panel buttons
  -- skinned as its panes are built (core/ButtonSkin.lua). Opt out per button with _neNoSkin.
  if NE.buttonskin and NE.buttonskin.Watch then pcall(NE.buttonskin.Watch, frame) end
  frame:SetSize(FRAME_W, FRAME_H)
  frame:SetPoint("CENTER")
  if NE.panelmgr then NE.panelmgr.Register(frame) end   -- absent on 3.3.5a; guarded
  frame:SetFrameStrata("MEDIUM")
  frame:SetToplevel(true)
  NE.FrameUtil.WirePanelSounds(frame,
    SOUNDKIT and SOUNDKIT.IG_CHARACTER_INFO_OPEN, SOUNDKIT and SOUNDKIT.IG_CHARACTER_INFO_CLOSE,
    "igCharacterInfoOpen", "igCharacterInfoClose")
  frame:EnableMouse(true)       -- panel: swallow clicks so they don't fall through
  frame:SetClampedToScreen(true)
  frame:SetMovable(true)
  frame:RegisterForDrag("LeftButton")
  frame:SetScript("OnDragStart", function(self) self:StartMoving() end)
  frame:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() end)
  frame:Hide()

  buildChrome(frame)

  -- retail EJ inset geometry. DOWNPORT: plain frame + nineslice layout (see header).
  local inset = CreateFrame("Frame", "NE_EncounterJournalInset", frame)
  inset:SetPoint("TOPRIGHT",   frame, "TOPRIGHT",   -4, -60)
  inset:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT",  4,  5)
  local insetBg = inset:CreateTexture(nil, "BACKGROUND", nil, -5)
  insetBg:SetTexture(0, 0, 0, 0.85)
  insetBg:SetPoint("TOPLEFT", inset, "TOPLEFT", 2, -2)
  insetBg:SetPoint("BOTTOMRIGHT", inset, "BOTTOMRIGHT", -2, 2)
  if NE.nineslice and NE.nineslice.ApplyLayout then
    NE.nineslice.ApplyLayout(inset, "InsetFrameTemplate")
  end
  frame.inset = inset

  buildInstanceSelect(frame)

  -- Encounter view (hidden until an instance is picked). retail: anchored to the inset.
  local enc = CreateFrame("Frame", "NE_EncounterJournalEncounter", frame)
  enc:SetPoint("TOPLEFT",     frame.inset, "TOPLEFT",      0, 0)
  enc:SetPoint("BOTTOMRIGHT", frame.inset, "BOTTOMRIGHT", -3, 0)
  enc:SetFrameLevel(frame.inset:GetFrameLevel() + 2)
  enc:Hide()
  frame.encounter = enc
  NE.ej.frame = frame
  if NE.ej.BuildEncounterPage then NE.ej.BuildEncounterPage(frame) end
  if NE.ej.BuildNavBar then NE.ej.BuildNavBar(frame) end
  if NE.ej.RefreshNavBar then NE.ej.RefreshNavBar() end

  pinScale(frame)

  -- ESC closes it (ToggleGameMenu walks UISpecialFrames first).
  NE.FrameUtil.EscClose("NE_EncounterJournal")
  return frame
end

function NE.ej.Toggle()
  if not isModuleEnabled() then return end
  local f = build()
  if f:IsShown() then
    f:Hide()
  else
    pinScale(f)
    f:Show()
  end
end

function NE.ej.Open()
  if not isModuleEnabled() then return end
  build():Show()
end
function NE.ej.Close() if frame then frame:Hide() end end

-- Navigation between the instance-select grid and the encounter view.
function NE.ej.ShowList()
  local f = build()
  f._currentInstance = nil
  f._currentBoss = nil
  if f.encounter then f.encounter:Hide() end
  if f.instanceSelect then f.instanceSelect:Show() end
  if NE.ej.RefreshNavBar then NE.ej.RefreshNavBar() end
end

function NE.ej.ShowInstance(inst)
  local f = build()
  f._currentInstance = (type(inst) == "table") and inst or nil
  f._currentBoss = nil   -- entering an instance clears the boss breadcrumb level
  if f.instanceSelect then f.instanceSelect:Hide() end
  if f.encounter then f.encounter:Show() end
  if NE.ej.PopulateEncounter and type(inst) == "table" then
    NE.ej.PopulateEncounter(inst)   -- fills lore (name/desc) + the real boss list
  end
  if NE.ej.RefreshNavBar then NE.ej.RefreshNavBar() end
end

-- Filter the instance grid by name substring (the search box).
function NE.ej.FilterGrid(text)
  local f = NE.ej.frame
  local page = f and f.instanceSelect
  if not (page and page.renderGrid and page._activeEntries) then return end
  text = (text or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
  if text == "" then page.renderGrid(page._activeEntries); return end
  local filtered = {}
  for _, e in ipairs(page._activeEntries) do
    if e.name and e.name:lower():find(text, 1, true) then filtered[#filtered + 1] = e end
  end
  page.renderGrid(filtered)
end

-- Bindings.xml labels (the 3.3.5a Bindings.xml schema has no header/name text of its own;
-- the guild module seeds the shared header the same way).
BINDING_HEADER_DRAGONUI_NEWERA = BINDING_HEADER_DRAGONUI_NEWERA or "DragonUI New Era"
BINDING_NAME_NEWERA_TOGGLEEJ = BINDING_NAME_NEWERA_TOGGLEEJ or "Toggle Adventure Guide"

-- Boot: create the ToggleEncounterJournal global + slashes at login; lazy-build on first
-- open. Re-pin on scale changes.
local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("PLAYER_LOGIN")
eventFrame:RegisterEvent("UI_SCALE_CHANGED")
eventFrame:RegisterEvent("DISPLAY_SIZE_CHANGED")
eventFrame:SetScript("OnEvent", function(_, event)
  if event == "PLAYER_LOGIN" then
    -- TAINT: safe (and additive). 3.3.5a ships no ToggleEncounterJournal (the EJ is Cata+),
    -- so this CREATES a global rather than overwriting Blizzard's.
    if type(_G.ToggleEncounterJournal) ~= "function" then
      _G.ToggleEncounterJournal = function() NE.ej.Toggle() end
    end
    SLASH_NEWERAEJ1 = "/aguide"
    SLASH_NEWERAEJ2 = "/adventureguide"
    SLASH_NEWERAEJ3 = "/ej"
    SlashCmdList["NEWERAEJ"] = function() NE.ej.Toggle() end
    if NE.RegisterPanel then
      NE.RegisterPanel({
        id = MODULE,
        title = ADVENTURE_JOURNAL or "Adventure Guide",
        desc = "The Adventure Guide: bosses, abilities, and loot for Classic and Burning Crusade dungeons and raids (/aguide).",
        frame = frame,          -- nil until first open (lazy build); mover skipped silently
        -- No openFn: RegisterPanel wires this into both NE.modules' onBoot dispatcher AND
        -- DragonUI's ModuleRegistry Enable/Refresh hooks, either of which can end up calling
        -- openFn() unconditionally as soon as the module's enabled flag is true (the default) --
        -- which was popping the Adventure Guide window open on every login. The micro button
        -- (MicroButton.lua) and the /aguide slash command both call NE.ej.Toggle()/Open()
        -- directly, bypassing this registry entirely, so nothing user-facing needs openFn here.
        closeFn = NE.ej.Close,
        order = 70,
      })
    end
  elseif frame then
    pinScale(frame)
  end
end)
