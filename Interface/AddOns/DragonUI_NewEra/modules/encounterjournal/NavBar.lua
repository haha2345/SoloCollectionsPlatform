-- DragonUI_NewEra/modules/encounterjournal/NavBar.lua — breadcrumb navbar + search box.
--
-- DOWNPORT of NewEra/EncounterJournal/NavBar.lua. NewEra reuses Era's shipped NavBarTemplate
-- via its Core NE.navbar wrapper; neither exists on 3.3.5a, so the breadcrumb is REBUILT here as
-- a from-scratch text-button trail: [Home] > [Instance ▾] > [Boss]. Same behaviours:
--   * Home            → back to the instance-select grid (NE.ej.ShowList)
--   * Instance crumb  → back to the instance overview (clears the selected boss)
--   * Instance ▾      → boss-jump menu (EasyMenu — native 3.3.5a)
--   * Boss crumb      → re-shows that boss
--   * Search box      → filters the instance grid by name (SearchBoxTemplate via ClassicAPI,
--                       pcall'd with an InputBoxTemplate fallback)
--
-- COLLAPSE/OVERFLOW (ported from retail's real NavigationBar.lua NavBar_CheckLength, supplied by
-- the user): when the crumb trail is wider than the bar, the OLDEST/leftmost crumbs fold into a
-- "…" overflow button (leftmost position) instead of spilling past the bar or clipping, and the
-- CURRENT/deepest crumb always stays visible.
--
-- ART (user-supplied 2026-07-23, from the same retail NavigationBar.xml), real retail FDIDs:
--   516763 `Textures/EncounterJournal/516763-cs-helptextures.blp`      (512×128, non-tiled CS_HelpTextures)
--   516764 `Textures/EncounterJournal/516764-cs-helptextures-tile.blp` (128×512, tiled CS_HelpTextures_Tile)
--   423808 `Textures/Common/423808-squarebuttontextures.blp`           (64×64,  Interface\Buttons\SquareButtonTextures)
-- The third one is retail's ACTUAL ▾ dropdown-arrow icon source (MenuArrowButton's `Art` texture)
-- — NOT the CS_HelpTextures NavMenu-Arrow piece we mistakenly tried earlier.
--
-- COLOR RULE, faithful to how the real art is actually built (verified by decoding both sheets):
-- ONLY the Home chevron piece has the pointed ">" notch, so ONLY Home uses it (cropped to fit its
-- short label). The selection glow and hover glow are FLAT bars with no notch, deliberately made
-- to STRETCH to any width. So: Home = red chevron (always). Every other crumb = flat grey tile
-- (stretches to full width) + a red "selected" glow (also stretched) laid over it ONLY while it's
-- the current/last crumb (retail's `if i<#navList then selected:Hide() else selected:Show()`).
-- A crumb drops the glow the moment a newer crumb is appended after it, so e.g. "The Voidspire"
-- goes from red-tinted (current) to plain grey once "Imperator Averzian" becomes the new current.
--
-- Because the tile AND both glows all STRETCH (no 128px cap), a long boss name like "Argent
-- Confessor Paletress" is fully backed — earlier versions cropped/capped the current crumb's art
-- at 128px, which is exactly what left the tail of long names running onto black. Only Home is
-- still capped (via cropChevron, retail's own Home-button OnLoad math) — harmless, "Home" is short.
--
-- retail anchors (EJ.xml:1209-1213, 1196-1206): navBar TOPLEFT(61,-22) 500×34;
-- searchBox TOPRIGHT(-10,-32) 210×20.

local NE = DragonUI_NewEra
if not NE then return end

NE.ej = NE.ej or {}

-- ---------------------------------------------------------------------------------------
-- Art registration. FDIDs match the user-sourced real retail FileDataIDs (renamed files).
-- ---------------------------------------------------------------------------------------
local NAVBAR_FDID = 516763
NE.tex.RegisterLocal(NAVBAR_FDID,
  "Interface\\AddOns\\DragonUI_NewEra\\Textures\\EncounterJournal\\516763-cs-helptextures.blp")

-- Fixed-rect pieces (measured off the 512×128 sheet; see NavBar.lua header). Static size, no
-- per-width crop needed.
NE.tex.RegisterAtlas("ej-navbar-overflow-up", {
  file = NAVBAR_FDID, left = 0.54296875, right = 0.62890625, top = 0.75781250, bottom = 0.99218750,
  width = 44, height = 30,
})
NE.tex.RegisterAtlas("ej-navbar-overflow-down", {
  file = NAVBAR_FDID, left = 0.45312500, right = 0.53906250, top = 0.75781250, bottom = 0.99218750,
  width = 44, height = 30,
})

-- The companion TILED sheet (user-supplied 2026-07-23): the plain grey bar every NON-Home crumb
-- uses as its base (retail NavButtonTemplate's own Normal/PushedTexture), plus the navBar's own
-- dark backing plate (BACKGROUND bar + OVERLAY sheen) instead of floating text over nothing.
local TILE_FDID = 516764
NE.tex.RegisterLocal(TILE_FDID,
  "Interface\\AddOns\\DragonUI_NewEra\\Textures\\EncounterJournal\\516764-cs-helptextures-tile.blp")
NE.tex.RegisterAtlas("ej-navbar-button-tile", {
  file = TILE_FDID, left = 0, right = 1, top = 0.06250000, bottom = 0.12109375, height = 30,
})
NE.tex.RegisterAtlas("ej-navbar-barbg-tile", {
  file = TILE_FDID, left = 0, right = 1, top = 0.18750000, bottom = 0.25390625, height = 34,
})
NE.tex.RegisterAtlas("ej-navbar-baroverlay-tile", {
  file = TILE_FDID, left = 0, right = 1, top = 0.25781250, bottom = 0.32421875, height = 34,
})

-- SquareButtonTextures: retail's real ▾ dropdown-arrow icon (MenuArrowButton's "Art" texture).
-- NOTE the top/bottom SWAP vs the source is intentional and copied verbatim from the retail
-- XML (`bottom="0.01562500" top="0.20312500"`) — the sheet stores this glyph as an UPWARD
-- triangle (confirmed by decoding the BLP), and retail flips it vertically into the ▾ we want by
-- reversing which edge is "top" vs "bottom" in the SetTexCoord call, instead of shipping a
-- separate downward-pointing glyph.
local SQBTN_FDID = 423808
NE.tex.RegisterLocal(SQBTN_FDID,
  "Interface\\AddOns\\DragonUI_NewEra\\Textures\\Common\\423808-squarebuttontextures.blp")
NE.tex.RegisterAtlas("ej-navbar-dropdown-arrow", {
  file = SQBTN_FDID, left = 0.45312500, right = 0.64062500, top = 0.20312500, bottom = 0.01562500,
  width = 12, height = 12,
})

-- Apply a horizontally-tiled atlas piece stretched to an arbitrary `width` (unlike cropChevron,
-- not capped at 128px — the whole point of having the tile sheet).
local function applyTiled(tex, atlasName, width, height)
  local entry = NE.tex._atlasEntry(atlasName)
  local src = entry and NE.tex.localFiles[entry.file]
  if not (tex and entry and src) then if tex then tex:Hide() end; return end
  tex:SetTexture(src)
  tex:SetTexCoord(entry.left, entry.right, entry.top, entry.bottom)
  tex:SetHorizTile(true)
  tex:SetSize(math.max(width or 0, 1), height or entry.height or 30)
  tex:Show()
end

-- ART REGIONS (all measured off the two decoded sheets; see NavBar.lua header):
--   Home chevron  : the ONLY piece with the pointed ">" notch. Native 128px, cropped for Home.
--   Selection glow: a FLAT red glow bar (no notch) — retail STRETCHES it across the whole (wide)
--                   selected button. This is the fix for long names: it covers any width.
--   Hover glow    : a FLAT blue glow bar (no notch), same stretch treatment.
local BANNER_W       = 128                        -- native px width of the Home chevron piece
local BANNER_RIGHT   = 0.70312500                  -- chevron span: right edge fixed, crop from left
local BANNER_UP_Y    = { 0.00781250, 0.24218750 }
local GLOW_LEFT      = 0.00195313                  -- selection/hover glow span (left/right, stretched)
local GLOW_RIGHT     = 0.25195313
local GLOW_SELECT_Y  = { 0.37500000, 0.64062500 }  -- red "this crumb is current" glow
local GLOW_HOVER_Y   = { 0.65625000, 0.92187500 }  -- blue transient mouseover glow

-- THE REAL GREY ENDCAP (user-identified 2026-07-23): retail's `NavMenu-Arrow-up`/`-down`. These
-- are NOT the dropdown ▾ (that's SquareButtonTextures) — in NavButtonTemplate they're anchored
-- `point="LEFT" relativePoint="RIGHT"`, i.e. a 21x30 GREY chevron connector sitting just off each
-- crumb's RIGHT edge, bridging into the next crumb. arrowUp = normal, arrowDown = pressed (the
-- pair reads slightly lighter/darker). Already grey in the art — no desaturating/tinting needed,
-- which is what made the earlier red-notch-derived endcaps read dark.
NE.tex.RegisterAtlas("ej-navbar-endcap-up", {
  file = NAVBAR_FDID, left = 0.88867188, right = 0.92968750, top = 0.29687500, bottom = 0.53125000,
  width = 21, height = 30,
})
NE.tex.RegisterAtlas("ej-navbar-endcap-down", {
  file = NAVBAR_FDID, left = 0.63281250, right = 0.67382813, top = 0.75781250, bottom = 0.99218750,
  width = 21, height = 30,
})
local ENDCAP_W  = 21   -- native size of the connector
local ENDCAP_H  = 30

local function bannerSource()
  return NE.tex.Local(NAVBAR_FDID)
end

-- Lay the grey chevron connector on the crumb's right edge. Straight atlas draw — it ships grey.
local function applyEndcap(tex)
  if not tex then return end
  if NE.tex.SetAtlas(tex, "ej-navbar-endcap-up", false) then
    tex:SetSize(ENDCAP_W, ENDCAP_H)
    tex:SetHorizTile(false)
    if tex.SetDesaturated then tex:SetDesaturated(false) end
    tex:SetVertexColor(1, 1, 1)
    tex:Show()
  else
    tex:Hide()
  end
end

-- Crop the Home chevron to `width` px, keeping its RIGHT edge (the notch) fixed and cropping from
-- the left — mirrors retail's own Home-button OnLoad math. Only Home uses this; "Home" is short
-- so the 128px cap never bites in practice.
local function cropChevron(tex, width)
  local src = bannerSource()
  if not (tex and src) then if tex then tex:Hide() end; return end
  width = math.min(width or 0, BANNER_W)
  if width <= 0 then tex:Hide(); return end
  tex:SetTexture(src)
  tex:SetHorizTile(false)   -- clear any stale tile flag from a prior applyTiled on this texture
  local offsetFrac = (width / BANNER_W) * 0.25
  tex:SetTexCoord(BANNER_RIGHT - offsetFrac, BANNER_RIGHT, BANNER_UP_Y[1], BANNER_UP_Y[2])
  tex:SetWidth(width)
  tex:Show()
end

-- Stretch a FLAT glow bar (selection or hover) across the texture's whole anchored area — the glow
-- art has no notch and is meant to scale to any width, so unlike cropChevron there is NO 128px cap
-- and NO black gap on long crumb names. Anchor is set by the caller (fills the crumb); we only
-- swap the texture + texcoords here.
local function applyGlow(tex, topFrac, botFrac)
  local src = bannerSource()
  if not (tex and src) then if tex then tex:Hide() end; return end
  tex:SetTexture(src)
  tex:SetHorizTile(false)
  tex:SetTexCoord(GLOW_LEFT, GLOW_RIGHT, topFrac, botFrac)
  tex:Show()
end

-- Dropdown contents for the instance breadcrumb button: jump to a boss.
local function bossJumpList()
  local f = NE.ej.frame
  local inst = f and f._currentInstance
  local list = {}
  if inst and inst.encounters then
    for _, enc in ipairs(inst.encounters) do
      local e = enc
      list[#list + 1] = {
        text = e.name,
        func = function() if NE.ej.ShowBoss then NE.ej.ShowBoss(e) end end,
        notCheckable = true,
      }
    end
  end
  return list
end

-- Shared context menu host for the ▾ boss-jump AND the overflow dropdown (EasyMenu just needs
-- *a* named dropdown frame to anchor from; it's modal, so one shared host is fine).
local menuHost
local function openMenu(anchor, list)
  if not menuHost then
    menuHost = CreateFrame("Frame", "NE_EJNavBarMenu", UIParent, "UIDropDownMenuTemplate")
  end
  if #list > 0 and EasyMenu then EasyMenu(list, menuHost, anchor, 0, 0, "MENU") end
end

-- Shared ▾ arrow builder — retail's real MenuArrowButton icon: a 12×12 chevron
-- ("ej-navbar-dropdown-arrow", the flipped-triangle piece above) that nudges down-left on press.
-- DOWNPORT: retail's Normal/PushedTexture are an "invisible until hover" ghost square
-- (Interface\Buttons\UI-SquareButton-Up/Down at alpha=0) — on this client they rendered as solid
-- BLACK squares instead of staying transparent, so they're dropped entirely; the stock
-- Interface\Buttons\UI-Common-MouseHilight highlight (kept below) already gives clear hover
-- feedback on its own.
local function buildArrow(parent)
  local a = CreateFrame("Button", nil, parent)
  a:SetSize(27, 31)

  a.highlightTex = a:CreateTexture(nil, "HIGHLIGHT")
  a.highlightTex:SetSize(32, 32)
  a.highlightTex:SetPoint("CENTER")
  a.highlightTex:SetTexture("Interface\\Buttons\\UI-Common-MouseHilight")
  a.highlightTex:SetBlendMode("ADD")

  a.art = a:CreateTexture(nil, "OVERLAY")
  a.art:SetSize(12, 12)
  a.art:SetPoint("CENTER", a, "CENTER", 0, -1)
  NE.tex.SetAtlas(a.art, "ej-navbar-dropdown-arrow", true)

  a:SetScript("OnMouseDown", function(self) self.art:SetPoint("CENTER", -1, -2) end)
  a:SetScript("OnMouseUp",   function(self) self.art:SetPoint("CENTER", 0, -1) end)
  return a
end

-- One crumb. Home is a bespoke always-red chevron button (the only piece with the pointed notch,
-- cropped to fit its short "Home" label). Every OTHER crumb is a FLAT grey tile that stretches to
-- any width — with a red "selected" glow (also flat, also stretched) laid over it ONLY while it's
-- the current/last crumb in the trail (retail's `if i<#navList then selected:Hide() else Show()`).
-- Because the tile + both glows all STRETCH (no 128px crop cap), long boss names like "Argent
-- Confessor Paletress" are fully covered — no black gap running off the end.
local function acquireCrumb(navBar, i)
  local c = navBar.crumbs[i]
  if c then return c end
  c = CreateFrame("Button", nil, navBar)
  c:SetHeight(24)
  c._isHome = (i == 1)
  -- Base background. Home's chevron is right-anchored (notch pinned to the right edge) + sized by
  -- cropChevron; a non-Home tile fills the crumb and is sized by applyTiled. Anchor set per-refresh.
  c.bg = c:CreateTexture(nil, "BACKGROUND")
  c.bg:SetHeight(30)
  -- Red "selected" glow — shown only while this crumb is current/last. Sits BELOW the endcap and
  -- reaches only to the point base, so the glow's own right-hand fade tapers the red out as it
  -- approaches the point (a soft fade, not a hard stop) and the grey endcap then draws cleanly on
  -- top (so the red never bleeds past/around the point — that was the "red goes too far" look).
  -- Glows fill the crumb body and fade out at its right edge — the grey connector lives entirely
  -- OUTSIDE that edge now, so the red simply tapers off as the body ends (no hard line, and it
  -- can't bleed past/around the connector).
  c.selectedGlow = c:CreateTexture(nil, "ARTWORK", nil, 0)
  c.selectedGlow:SetPoint("TOPLEFT", c, "TOPLEFT", -2, 4)
  c.selectedGlow:SetPoint("BOTTOMRIGHT", c, "BOTTOMRIGHT", 0, -4)
  c.selectedGlow:Hide()
  -- Blue transient mouseover glow — same fill, just above the selected glow.
  c.glow = c:CreateTexture(nil, "ARTWORK", nil, 1)
  c.glow:SetPoint("TOPLEFT", c, "TOPLEFT", -2, 4)
  c.glow:SetPoint("BOTTOMRIGHT", c, "BOTTOMRIGHT", 0, -4)
  c.glow:SetBlendMode("ADD")
  c.glow:Hide()
  -- Grey chevron connector, anchored LEFT at the crumb's RIGHT (retail's own anchoring) so it sits
  -- wholly outside the body and bridges into the next crumb. Sublevel 2 keeps it above the glows.
  c.endcap = c:CreateTexture(nil, "ARTWORK", nil, 2)
  c.endcap:SetSize(ENDCAP_W, ENDCAP_H)
  c.endcap:SetPoint("LEFT", c, "RIGHT", 0, 0)
  c.endcap:Hide()
  -- text LEFT inset is set per-refresh (Home vs sub-crumb differ — a sub-crumb's text must clear
  -- the previous crumb's endcap point).
  c.text = c:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  c:SetScript("OnEnter", function(self)
    self.text:SetTextColor(1, 1, 0.6)
    applyGlow(self.glow, GLOW_HOVER_Y[1], GLOW_HOVER_Y[2])
  end)
  c:SetScript("OnLeave", function(self)
    if self._isLast then self.text:SetTextColor(1, 1, 1) else self.text:SetTextColor(1, 0.82, 0) end
    self.glow:Hide()
  end)
  -- ▾ arrow (shown only for crumbs carrying a listFunc)
  c.arrow = buildArrow(navBar)
  c.arrow:SetScript("OnClick", function(self)
    if not self._listFunc then return end
    openMenu(self, self._listFunc())
  end)
  -- separator BEFORE this crumb (hidden for the first visible crumb)
  c.sep = navBar:CreateFontString(nil, "OVERLAY", "GameFontDisable")
  c.sep:SetText(">")
  navBar.crumbs[i] = c
  return c
end

-- The "…" overflow crumb: a fixed-size icon button standing in for however many OLDEST crumbs
-- didn't fit. Its click opens a menu of just those collapsed entries (retail
-- NavBar_ListOverFlowButtons), oldest first; clicking one jumps straight there exactly like
-- clicking the real crumb would have.
local function acquireOverflow(navBar)
  if navBar._neOverflow then return navBar._neOverflow end
  local c = CreateFrame("Button", nil, navBar)
  c:SetSize(44, 30)
  c.idleTex = c:CreateTexture(nil, "ARTWORK")
  c.idleTex:SetAllPoints(c)
  NE.tex.SetAtlas(c.idleTex, "ej-navbar-overflow-up", true)
  c.pressTex = c:CreateTexture(nil, "ARTWORK")
  c.pressTex:SetAllPoints(c)
  NE.tex.SetAtlas(c.pressTex, "ej-navbar-overflow-down", true)
  c.pressTex:Hide()
  c:SetScript("OnMouseDown", function(self) self.idleTex:Hide(); self.pressTex:Show() end)
  c:SetScript("OnMouseUp",   function(self) self.pressTex:Hide(); self.idleTex:Show() end)
  c:SetScript("OnClick", function(self)
    local list = {}
    for _, e in ipairs(self._hidden or {}) do
      list[#list + 1] = {
        text = e.name,
        func = function() if e.OnClick then e.OnClick() end end,
        notCheckable = true,
      }
    end
    openMenu(self, list)
  end)
  -- separator BEFORE the « (it now sits AFTER Home, never at the very start).
  c.sep = navBar:CreateFontString(nil, "OVERLAY", "GameFontDisable")
  c.sep:SetText(">")
  navBar._neOverflow = c
  return c
end

function NE.ej.BuildNavBar(f)
  if f._neNavBar then return f._neNavBar end

  -- Bar width: fill the header from just past the portrait (x60) to just before the search box.
  -- The frame is 800 wide; the search box sits at TOPRIGHT(-30) width 180 → starts at x~590, so a
  -- 520px bar (ends at x580) uses the whole gap. Wider than the old 500 so a normal 3-crumb trail
  -- (Home > Instance > Boss) fits WITHOUT collapsing Home into the overflow "«".
  local NAVBAR_W = 520
  local navBar = CreateFrame("Frame", "NE_EncounterJournalNavBar", f)
  navBar:SetSize(NAVBAR_W, 34)
  -- DOWNPORT FIX: PortraitFrameTemplate's round portrait (60x60 @ TOPLEFT(-6,7)) reaches out to
  -- x~54 from the frame's top-left corner; a 14px navbar start sat the "Home" crumb text right on
  -- top of that icon art. Start the crumb trail past the icon instead.
  navBar:SetPoint("TOPLEFT", f, "TOPLEFT", 60, -24)
  local lvl = (f.NineSlice and f.NineSlice:GetFrameLevel() or f:GetFrameLevel()) + 6
  navBar:SetFrameLevel(lvl)
  navBar.crumbs = {}
  f._neNavBar = navBar

  -- The bar's own dark backing plate (retail NavBarTemplate: BACKGROUND bar + an OVERLAY sheen on
  -- top), tiled to the bar's full width so crumb buttons sit on a proper dark strip instead of
  -- floating over whatever's behind the navBar.
  navBar.barBG = navBar:CreateTexture(nil, "BACKGROUND")
  navBar.barBG:SetPoint("TOPLEFT", navBar, "TOPLEFT", 0, 0)
  applyTiled(navBar.barBG, "ej-navbar-barbg-tile", NAVBAR_W, 34)
  navBar.barOverlay = navBar:CreateTexture(nil, "OVERLAY")
  navBar.barOverlay:SetPoint("TOPLEFT", navBar, "TOPLEFT", 0, 0)
  applyTiled(navBar.barOverlay, "ej-navbar-baroverlay-tile", NAVBAR_W, 34)

  -- Recessed inset border around the whole bar — same DF nineslice idiom the EJ content inset uses.
  -- AttachInset builds it on a mouse-transparent CHILD frame. Raise it ABOVE the crumbs (which get
  -- frame levels up to ~navBar+2+depth per-refresh) so the border OVERLAYS everything — the frame
  -- reads as a single recessed strip with the crumbs inside it, not crumbs spilling over the edge.
  if NE.nineslice and NE.nineslice.AttachInset then
    navBar.NineSlice = NE.nineslice.AttachInset(navBar, 0, 0, 0, 0)
    if navBar.NineSlice then navBar.NineSlice:SetFrameLevel((navBar:GetFrameLevel() or 1) + 40) end
  end

  -- Search box (filters the instance grid). pcall the ClassicAPI template; fall back to a
  -- plain InputBoxTemplate if a future build renames it — the journal works without search.
  local ok, sb = pcall(CreateFrame, "EditBox", "NE_EncounterJournalSearchBox", f, "SearchBoxTemplate")
  if not (ok and sb) then
    ok, sb = pcall(CreateFrame, "EditBox", "NE_EncounterJournalSearchBox", f, "InputBoxTemplate")
    if ok and sb then sb:SetAutoFocus(false) end
  end
  if ok and sb then
    sb:SetSize(180, 20)
    sb:SetPoint("TOPRIGHT", f, "TOPRIGHT", -30, -32)
    sb:SetFrameLevel(lvl)
    -- DOWNPORT: SearchBoxTemplate_OnLoad/OnEditFocusLost (!!!ClassicAPI) write the literal
    -- SEARCH placeholder into the box's real text (no retail overlay watermark), so OnTextChanged
    -- fires with that placeholder both on load and on every blur -- NE.ej.ReadSearchText treats
    -- it as "no search" instead of a literal filter string that matches zero instances.
    sb:HookScript("OnTextChanged", function(self)
      if NE.ej.FilterGrid then
        NE.ej.FilterGrid(NE.ej.ReadSearchText and NE.ej.ReadSearchText(self) or self:GetText())
      end
    end)
    sb:HookScript("OnEscapePressed", function(self) self:ClearFocus() end)
    f._neSearchBox = sb
  end
  return navBar
end

-- Per-crumb WIDTH = text width + a fixed pad. The pad splits into a LEFT text inset + right room;
-- a NON-Home crumb needs a big enough left inset that its text starts PAST the previous crumb's
-- endcap point (which reaches TEXT_LPAD_SUB in), or the point clips the first letters (the "e
-- Nexus" / "and Magus Telestra" bug). Home is the first crumb (nothing overlaps it) so it uses a
-- small left inset and a tighter overall pad (it was reading too wide).
local TEXT_LPAD_HOME = 12
local TEXT_LPAD_SUB  = 26   -- must clear the previous crumb's 21px connector overlapping this one's left
local HOME_PAD   = 25   -- Home: 25px total padding around its label (12 left inset + ~13 right)
local PLAIN_PAD  = 34   -- plain crumb: 26 left inset + text + ~8 right (connector lives OUTSIDE the body)
local ARROW_PAD  = 56   -- arrow crumb: 26 left inset + text + ~30 right (inside ▾)
local WIDTH_BUFFER = 20   -- retail's NAVBAR_WIDTHBUFFER
local OVERFLOW_W   = 44   -- matches the fixed overflow-badge width

local function crumbWidth(isHome, hasArrow, textW)
  return textW + (isHome and HOME_PAD or (hasArrow and ARROW_PAD or PLAIN_PAD))
end

-- Rebuild the breadcrumb trail. Entry shape mirrors NewEra's NE.navbar hierarchy:
-- { name, OnClick, listFunc }. Home is implicit (index 0).
function NE.ej.RefreshNavBar()
  local f = NE.ej.frame
  local navBar = f and f._neNavBar
  if not navBar then return end

  local hierarchy = {}
  local inst = f._currentInstance
  if inst then
    hierarchy[#hierarchy + 1] = {
      name     = inst.name,
      OnClick  = function() if NE.ej.ShowInstance then NE.ej.ShowInstance(inst) end end,
      listFunc = bossJumpList,   -- the ▾ boss-jump dropdown
    }
  end
  local boss = f._currentBoss
  if boss then
    hierarchy[#hierarchy + 1] = {
      name    = boss.name,
      OnClick = function() if NE.ej.ShowBoss then NE.ej.ShowBoss(boss) end end,
    }
  end

  -- crumb 1 is always Home; then the hierarchy.
  local entries = { { name = HOME or "Home", OnClick = function() if NE.ej.ShowList then NE.ej.ShowList() end end } }
  for _, e in ipairs(hierarchy) do entries[#entries + 1] = e end

  -- Acquire a crumb per entry up front and measure its own footprint (text is set here so
  -- GetStringWidth reflects the real label).
  local widths = {}
  for i, e in ipairs(entries) do
    local c = acquireCrumb(navBar, i)
    c.text:SetWidth(0); c.text:SetText(e.name or "?")
    widths[i] = crumbWidth(i == 1, e.listFunc ~= nil, c.text:GetStringWidth() or 0)
  end

  -- COLLAPSE (user request 2026-07-23): Home NEVER collapses. Home (index 1) and the current/last
  -- crumb (#entries) are ALWAYS shown; only the MIDDLE crumbs (2 .. #entries-1) fold into the
  -- overflow «, which sits right AFTER Home. (EJ is only ever 3 deep, so at most one instance
  -- crumb ever collapses.)
  local maxWidth = navBar:GetWidth() - WIDTH_BUFFER
  local total = 0
  for i = 1, #entries do total = total + widths[i] end
  local needOverflow = (total > maxWidth) and (#entries > 2)
  -- Budget for the crumbs after Home (reserving the « slot up front if we'll need it). Walk from
  -- the deepest crumb back toward index 2; whatever no longer fits stays collapsed.
  local budget = maxWidth - widths[1] - (needOverflow and OVERFLOW_W or 0)
  local firstMid, run = #entries, 0
  for i = #entries, 2, -1 do
    run = run + widths[i]
    if run > budget then break end
    firstMid = i
  end
  needOverflow = firstMid > 2   -- refine: overflow only if a middle crumb actually got hidden

  -- The trailing (after-Home) crumbs actually rendered: firstMid..#entries, but NEVER index 1
  -- (Home is rendered once, explicitly, below). When only Home exists (#entries==1) firstMid is 1,
  -- so clamp to 2 → the trailing loop renders nothing and Home is not re-rendered onto itself
  -- (that self-anchor was blanking the bar on first load and detaching it after going back Home).
  local trailStart  = math.max(firstMid, 2)
  local trailCount  = (#entries >= trailStart) and (#entries - trailStart + 1) or 0

  -- Count the visible chain so we can assign DESCENDING frame levels (leftmost highest) — that's
  -- what lets each crumb's ">" endcap point draw OVER the next crumb, interlocking with no black
  -- transition gap (retail's own `SetFrameLevel(lastButton+1)` on the left neighbour).
  local nVisible = 1 + (needOverflow and 1 or 0) + trailCount
  local baseLevel = (navBar:GetFrameLevel() or 1) + 2
  local visualPos = 0
  local function nextLevel()
    local lvl = baseLevel + (nVisible - visualPos)
    visualPos = visualPos + 1
    return lvl
  end

  -- Render one crumb by index, chained off `prevWidget` (nil = first, flush to the bar left).
  -- Chaining is uniform: every crumb sits flush after the previous one, whose overhanging piece
  -- (Home's built-in notch, or a regular crumb's 21px grey connector) — drawn at a higher frame
  -- level — overlaps this one's left padding, never its text (the text inset clears it).
  local function renderCrumb(i, prevWidget)
    local e = entries[i]
    local c = navBar.crumbs[i]
    c._isLast = (i == #entries)
    c:SetFrameLevel(nextLevel())
    c.sep:Hide()   -- the grey connectors ARE the separators now
    c.text:ClearAllPoints()
    c.text:SetPoint("LEFT", c, "LEFT", c._isHome and TEXT_LPAD_HOME or TEXT_LPAD_SUB, 0)
    c.text:SetTextColor(c._isLast and 1 or 1, c._isLast and 1 or 0.82, c._isLast and 1 or 0)
    c:SetScript("OnClick", function()
      if PlaySound and SOUNDKIT then PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON) end
      if e.OnClick then e.OnClick() end
    end)
    c:ClearAllPoints()
    if prevWidget then
      -- Flush after the previous crumb: its overhanging connector (or Home's overhanging notch)
      -- covers this crumb's left padding, and the text inset clears it.
      c:SetPoint("LEFT", prevWidget, "RIGHT", 0, 0)
    else
      c:SetPoint("LEFT", navBar, "LEFT", 0, 0)
    end
    local w = widths[i]   -- full crumb width (text + pad)
    c:SetWidth(w)
    c.bg:ClearAllPoints()
    if c._isHome then
      -- Home: the whole pointed chevron (body + its own built-in notch). It OVERHANGS the crumb's
      -- right edge by ENDCAP_W so the notch lands OUTSIDE the body — exactly where every other
      -- crumb's connector sits. Sizing it to the bare crumb width instead let the notch (the
      -- rightmost ~30px of the art) eat into the label and swallow Home's padding.
      c._bgWidth = w + ENDCAP_W
      c.bg:SetPoint("RIGHT", c, "RIGHT", ENDCAP_W, 0)
      cropChevron(c.bg, c._bgWidth)
      c.endcap:Hide()
    else
      -- Everyone else: flat grey tile (stretches to full width, no cap) + the real grey chevron
      -- connector just off the right edge.
      c._bgWidth = w
      c.bg:SetPoint("CENTER", c, "CENTER", 0, 0)
      applyTiled(c.bg, "ej-navbar-button-tile", w, 30)
      applyEndcap(c.endcap)
    end
    -- Red "selected" glow over the current/last NON-Home crumb — stretched to fill, so it covers
    -- any width. Home already reads as active via its red chevron.
    if c._isLast and not c._isHome then
      applyGlow(c.selectedGlow, GLOW_SELECT_Y[1], GLOW_SELECT_Y[2])
    else
      c.selectedGlow:Hide()
    end
    -- ▾ arrow moved INSIDE the crumb (just left of the endcap point), matching retail, so the
    -- endcap stays the rightmost element and the chain interlocks cleanly.
    if e.listFunc then
      c.arrow._listFunc = e.listFunc
      c.arrow:ClearAllPoints()
      c.arrow:SetPoint("RIGHT", c, "RIGHT", -6, 1)   -- inside the crumb, just left of the endcap point
      c.arrow:SetFrameLevel(c:GetFrameLevel() + 1)
      c.arrow:Show()
    else
      c.arrow:Hide()
    end
    c:Show()
    return c
  end

  -- Lay out left→right: Home, then « (if collapsing), then the trailing crumbs.
  local prev = renderCrumb(1, nil)

  if needOverflow then
    local ov = acquireOverflow(navBar)
    ov._hidden = {}
    for k = 2, firstMid - 1 do ov._hidden[#ov._hidden + 1] = entries[k] end
    ov.sep:Hide()
    ov:SetFrameLevel(nextLevel())
    ov:ClearAllPoints()
    ov:SetPoint("LEFT", prev, "RIGHT", 0, 0)   -- « chains flush, same as a crumb
    ov:Show()
    prev = ov
  elseif navBar._neOverflow then
    navBar._neOverflow:Hide(); navBar._neOverflow.sep:Hide()
  end

  for i = trailStart, #entries do
    prev = renderCrumb(i, prev)
  end

  -- Hide any crumb not in the visible set: the collapsed middles (2 .. trailStart-1) and leftovers
  -- pooled from a previously deeper trail (> #entries). Home (1) and trailStart..#entries stay shown.
  for i = 1, #navBar.crumbs do
    if (i > 1 and i < trailStart) or i > #entries then
      local c = navBar.crumbs[i]
      c:Hide(); c.arrow:Hide(); c.sep:Hide(); c.endcap:Hide()
    end
  end
end
