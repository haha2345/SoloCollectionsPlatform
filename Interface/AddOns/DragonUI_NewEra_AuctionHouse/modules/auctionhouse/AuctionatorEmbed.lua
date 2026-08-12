-- DragonUI_NewEra/modules/auctionhouse/AuctionatorEmbed.lua
-- Full embed + reskin of Auctionator's UI inside the NE Auction House shell.
--
-- Auctionator builds ALL of its Buy/Sell/More UI as ONE frame -- Atr_Main_Panel, parented to the
-- legacy AuctionFrame at TOPLEFT (210, 0), with its left-column controls hanging off at negative
-- x offsets (down to -195) and a few pieces poking past the panel's right edge (+66). The old
-- TabBridge behavior for its tabs was to UNCLOAK the legacy AuctionFrame and dismiss the shell,
-- dropping the player back into the stock Blizzard window.
--
-- This module instead reparents Atr_Main_Panel INTO the shell's ExternalPane and keeps the legacy
-- AuctionFrame permanently cloaked. That works because the cloak never :Hide()s AuctionFrame --
-- it stays :IsShown() == true, which is the only thing Auctionator's own logic ever checks (its
-- scans, shift-click search, tab state all test AuctionFrame:IsShown(), never alpha). The panel's
-- children keep their panel-relative anchors, so the whole three-tab UI moves as one unit; only
-- the handful of pieces that overflow the shell's 800px width get re-anchored individually.
--
-- The reskin pass then swaps Auctionator's parchment/tooltip-border chrome for the same treatment
-- the shell's own panes use: uniform dark fill (WHITE8X8 0.06/0.06/0.07) + gold-trim AttachInset
-- panels, minimal-scrollbar BuildCustom bars, zebra-striped rows with additive gold hover, the
-- Browse-style dark search box, and reskinned Current/History/Other top tabs.
--
-- Everything is fail-safe: each step is pcall'd and nil-guarded, so a different Auctionator build
-- missing a frame just skips that step; if Atr_Main_Panel never appears at all, ATR.IsEmbedded()
-- stays false and TabBridge falls back to the old uncloak-and-dismiss behavior untouched.

local NE = DragonUI_NewEra
if not NE then return end

NE.ah = NE.ah or {}
local AH = NE.ah
AH.atr = AH.atr or {}
local ATR = AH.atr

----------------------------------------------------------------------
-- Layout knobs. Auctionator was designed to sit in the legacy AuctionFrame, whose content area is
-- ~820px wide (its own modal mask is 820 wide) -- WIDER than the shell's default 800. So while an
-- Auctionator tab is active the shell is grown to ATR_W x ATR_H (SetWindowForExternal below) and
-- restored to the shell's own BASE_W x BASE_H when a base Buy/Sell/Auctions tab is selected.
--
-- PANEL_X centers Auctionator's content (which spans panel x -195 .. +588, width ~783) inside the
-- grown window: panel + 196 == ATR_W/2. PANEL_Y = -8 lifts the layout so the search row (panel
-- y -45) lands near the shell's own top-bar controls and the 447-tall layout clears the money bar.
----------------------------------------------------------------------
local BASE_W, BASE_H = 800, 538      -- shell's own default (Window.lua createWindow)
local ATR_W,  ATR_H  = 840, 538      -- footprint while an Auctionator tab is active (tunable)
local PANEL_X, PANEL_Y = 223, -8
-- Auctionator sizes its drop-target highlight 805px wide -- wider than the shell. Clamp.
local HILITE_MAX_W = 780

-- Auctionator natively anchors the Buy/More left column's dropdown at panel y=-49. The Sell tab's
-- VISIBLE background box (the "wrap" frame built in reskinSellControls) sits 6px above
-- Atr_SellControls' own XML top (-72), i.e. at panel y=-66 -- that's the box Buy/More needs to
-- match, not sc's raw anchor. Shifting the column down by 17 lands the dropdown's top at -66,
-- flush with that box's top edge; matching sc's own -72 (a 23px shift, the previous value here)
-- overshot by 6px and made the whole column -- and its background box below -- sit visibly lower
-- than the Sell tab's.
local BUYMORE_SHIFT_Y = -17

-- Auctionator anchors the Buy/More left column 5px further LEFT than the Sell tab's controls
-- (its shopping-list buttons sit at panel x=-195, the Hlist at -193, vs Sell's sc at -190). To let
-- the Buy/More backing box use the SAME left edge as the Sell box (LEFTCOL_L below == the Sell
-- wrap's -192) without the buttons poking out its left side, nudge the whole column right by this
-- much first. +3 lands the widest buttons flush inside the box's left edge (their 195px width is a
-- hair wider than the ~194px box interior, so the far-right button edge sits ~1-2px into the dark
-- gutter before the results list -- well clear of the list's own border at panel x=6).
local BUYMORE_SHIFT_X = 3

-- Extra downward nudge applied ON TOP of BUYMORE_SHIFT_Y to ONLY the shopping-list buttons
-- (the `extra` field below), so the button cluster drops to the bottom of the left-column box and
-- the last one (New Shopping List) lands just above LEFTCOL_B (-450) -- native New bottoms at
-- panel y~-409 with the -17 shift, ~40px short of the box bottom, leaving dead space beneath it.
-- The dropdown/list/Active-Items text (extra=0) stay top-aligned, and Atr_CheckActiveButton (the
-- More tab's lone button) is deliberately left OUT of this nudge: it already sits at the box bottom
-- on its own, so nudging it would push it past LEFTCOL_B.
local BUYMORE_BTN_EXTRA_Y = -20

-- Widgets making up the Buy/More left column. alignBuyMoreColumn() re-anchors each to
-- Atr_Main_Panel; y is always (native y + BUYMORE_SHIFT_Y + extra).
--
-- Two x conventions:
--   * No `w` (dropdown/list/Active-Items text): x is the widget's ORIGINAL XML anchor, and gets
--     BUYMORE_SHIFT_X added so the column tucks inside the Sell-width box.
--   * With `w` (the shopping-list buttons): the button is RESIZED to `w` and its x is a FINAL
--     panel coord (BUYMORE_SHIFT_X is NOT added). Auctionator sizes these buttons 195px wide --
--     1px wider than the box interior (LEFTCOL_L..LEFTCOL_R == -192..+2 == 194) -- so they filled
--     it edge-to-edge and looked stretched. Sizing them to 180 and left-anchoring at x=-185 (the
--     Add/Remove pair split into two 86px halves) centres them with a ~7px margin each side.
-- `center = true` (Atr_DropDownSL, Atr_ActiveItems_Text) overrides BOTH x and point: the widget
-- is horizontally centered on the left column box (LEFTCOL_L..LEFTCOL_R) instead of using its
-- native XML x, via alignBuyMoreColumn's own GetWidth()-based centering below.
local BUYMORE_WIDGETS = {
  { name = "Atr_DropDownSL",         point = "TOPLEFT", x = -200, y = -49 },
  { name = "Atr_Hlist_ScrollFrame",  point = "TOPLEFT", x = -193, y = -75  },
  { name = "Atr_Hlist",              point = "TOPLEFT", x = -193, y = -75  },
  { name = "Atr_ActiveItems_Text",   point = "TOP",      x = -360, y = -55, center = true },
  { name = "Atr_AddToSListButton",   point = "TOPLEFT", x = -185, y = -329, extra = BUYMORE_BTN_EXTRA_Y, w = 86  },
  { name = "Atr_RemFromSListButton", point = "TOPLEFT", x = -91,  y = -329, extra = BUYMORE_BTN_EXTRA_Y, w = 86  },
  { name = "Atr_SrchSListButton",    point = "TOPLEFT", x = -160, y = -349, extra = BUYMORE_BTN_EXTRA_Y, w = 130, center = true },
  { name = "Atr_MngSListsButton",    point = "TOPLEFT", x = -170, y = -369, extra = BUYMORE_BTN_EXTRA_Y, w = 145, center = true },
  { name = "Atr_NewSListButton",     point = "TOPLEFT", x = -160, y = -389, extra = BUYMORE_BTN_EXTRA_Y, w = 125, center = true },
  { name = "Atr_CheckActiveButton",  point = "TOPLEFT", x = -175, y = -409, w = 160, center = true },
}

-- Left-column dark backing (Buy & More tabs), in Atr_Main_Panel-relative coords.
--   TOP (-66): matches the Sell tab's own background box top (the "wrap" in reskinSellControls,
--     sc y=-72 + 6), so the two tabs' left panels start at the same height.
--   LEFT (-192): EXACTLY the Sell tab's own background box left edge, so the panels are the same
--     width. The Buy/More content natively sits 5px left of this, so it's shifted right first by
--     BUYMORE_SHIFT_X to fit inside; without that shift a -192 box would clip the buttons' left
--     edge (an earlier symptom), and a box widened to -197 to avoid clipping made the Buy/More
--     panel visibly wider than the Sell tab's.
--   RIGHT (2): flush with the seam before the right results list (its border starts at panel x=6).
--   BOTTOM (-450): EXACTLY the Sell tab's own background box bottom (the "wrap" in
--     reskinSellControls resolves to panel y=-450), so all three tabs share one identical panel
--     footprint. A previous value (-478) ran the box well past the last shopping-list button and
--     past where the Sell box ends, leaving a big empty gap below the buttons on the Buy/More tabs.
--     (The Buy/More content is shorter than the Sell tab's, so a little empty space at the bottom
--     is unavoidable with a shared footprint -- but the box no longer extends beyond Sell's.)
local LEFTCOL_L, LEFTCOL_T = -192, -66
local LEFTCOL_R, LEFTCOL_B = 2, -450

local WHITE = "Interface\\Buttons\\WHITE8X8"

local function isAddonLoaded(name)
  if NE.IsAddOnLoaded then return NE.IsAddOnLoaded(name) end
  if _G.IsAddOnLoaded then
    local ok, loaded = pcall(_G.IsAddOnLoaded, name)
    return ok and loaded and true or false
  end
  return false
end

function ATR.IsEmbedded()
  return ATR._embedded and true or false
end

-- Grow the shell to Auctionator's native footprint while one of its tabs is active, and restore
-- the shell's own size on the base tabs. Called from Window.lua's setMode. The shell's chrome
-- (rock bg, streaks, nineslice, close button, money bar, base tabs) all anchor to the frame's
-- edges, so it reflows cleanly on resize; the base panes are hidden while external, so their
-- resize is invisible.
function ATR.SetWindowForExternal(active)
  local f = AH.frame
  if not (f and ATR._embedded) then return end
  if active then
    if not ATR._sizedForAtr then
      ATR._sizedForAtr = true
      f:SetSize(ATR_W, ATR_H)
    end
  elseif ATR._sizedForAtr then
    ATR._sizedForAtr = nil
    f:SetSize(BASE_W, BASE_H)
  end
end

----------------------------------------------------------------------
-- Shared styling helpers (mirroring the conventions in Browse.lua/Sell.lua/Window.lua).
----------------------------------------------------------------------

-- Reverse of Window.lua's cloak, which may already have run over Atr_Main_Panel while it was
-- still a child of AuctionFrame (AH.Show cloaks the whole legacy tree before this module gets to
-- reparent on the same event): alpha back to 1, plus mouse re-enabled ONLY on the interactive
-- widget types. Show/Hide states are intentionally untouched.
--
-- Why type-aware (not the blanket EnableMouse(true) that Window.lua's restoreFrameTree uses):
-- Auctionator's containers -- Atr_Main_Panel itself, Atr_Hlist, Atr_HeadingsBar, Atr_SellControls
-- -- are plain <Frame>s with NO enableMouse in the XML, i.e. mouse-TRANSPARENT by design so clicks
-- fall through to the row/heading buttons layered over them. Blanket-enabling mouse turned the
-- full-area Atr_Main_Panel into a click-eater sitting over its own AuctionatorEntry/HEntry rows, so
-- NO list row was clickable on ANY tab. The cloak only ever disabled mouse on widgets that HAD it
-- (Auctionator's Buttons/EditBoxes/ScrollFrames -- verified: every drop target in Auctionator.xml
-- is a Button), so re-enabling just those restores exactly the original interactivity and leaves
-- the containers transparent.
local function restoreTree(frame, depth)
  if not frame or (depth or 0) > 10 then return end
  if frame.SetAlpha then pcall(frame.SetAlpha, frame, 1) end
  local ot = frame.GetObjectType and frame:GetObjectType()
  if ot == "Button" or ot == "CheckButton" or ot == "EditBox" or ot == "Slider"
     or ot == "ScrollFrame" then
    if frame.EnableMouse then pcall(frame.EnableMouse, frame, true) end
  end
  if ot == "ScrollFrame" or ot == "Slider" then
    if frame.EnableMouseWheel then pcall(frame.EnableMouseWheel, frame, true) end
  end
  if frame.GetChildren then
    local kids = { frame:GetChildren() }
    for i = 1, #kids do restoreTree(kids[i], (depth or 0) + 1) end
  end
end

local function darkFill(host, r, g, b, a)
  local t = host:CreateTexture(nil, "BACKGROUND")
  t:SetTexture(WHITE)
  t:SetVertexColor(r or 0.06, g or 0.06, b or 0.07, a or 0.95)
  t:SetAllPoints(host)
  return t
end

-- Textured panel background that fills `host` at the art's TRUE proportions: it shows a centered
-- sub-region of the atlas whose aspect matches the host, instead of stretching the whole art to
-- fit (which squashes the wide sell-panel art when the host is a different shape -- e.g.
-- Auctionator's tall-narrow left column). Re-crops on size change; falls back to the flat dark
-- fill if the atlas isn't registered.
local function croppedInsetBg(host, atlasName)
  local t = host:CreateTexture(nil, "BACKGROUND")
  t:SetAllPoints(host)
  local entry = NE.tex and NE.tex._atlasEntry and NE.tex._atlasEntry(atlasName)
  if not (entry and NE.tex.SetAtlas and NE.tex.SetAtlas(t, atlasName, false)) then
    t:SetTexture(WHITE)
    t:SetVertexColor(0.06, 0.06, 0.07, 0.95)
    return t
  end
  local uL, uR = entry.left or 0, entry.right or 1
  local vT, vB = entry.top or 0, entry.bottom or 1
  local artAspect = (entry.width or 1) / (entry.height or 1)
  local function recrop()
    local fw, fh = host:GetWidth(), host:GetHeight()
    if not (fw and fh and fw > 0 and fh > 0) then return end
    local fa = fw / fh
    if fa < artAspect then
      -- host narrower than the art: keep full height, crop width to a centered vertical slice.
      local keep = fa / artAspect
      local m = (uR - uL) * (1 - keep) / 2
      t:SetTexCoord(uL + m, uR - m, vT, vB)
    else
      -- host wider than the art: keep full width, crop height to a centered horizontal band.
      local keep = artAspect / fa
      local m = (vB - vT) * (1 - keep) / 2
      t:SetTexCoord(uL, uR, vT + m, vB - m)
    end
  end
  recrop()
  if C_Timer and C_Timer.After then C_Timer.After(0, recrop) end
  host:HookScript("OnSizeChanged", recrop)
  return t
end

local function attachInset(host, tlx, tly, brx, bry)
  if NE.nineslice and NE.nineslice.AttachInset then
    local ok, ns = pcall(NE.nineslice.AttachInset, host, tlx or 0, tly or 0, brx or 0, bry or 0)
    if ok then return ns end
  end
end

-- Hide a frame's own texture regions whose file path contains any of the given substrings
-- (plain find). Used to kill parchment/dialog-header art baked into Auctionator's XML that has
-- no global name to address directly.
local function hideTexturesByFile(frame, ...)
  if not (frame and frame.GetRegions) then return end
  local pats = { ... }
  local regions = { frame:GetRegions() }
  for i = 1, #regions do
    local r = regions[i]
    if r and r.IsObjectType and r:IsObjectType("Texture") and r.GetTexture then
      local file = r:GetTexture()
      if type(file) == "string" then
        for j = 1, #pats do
          if string.find(file, pats[j], 1, true) then
            r:SetTexture(nil)
            r:Hide()
            break
          end
        end
      end
    end
  end
end

-- Browse.lua's search-box treatment for a stock InputBoxTemplate-style EditBox: hide the gold
-- input art, dark tooltip backdrop instead. Handles both named pieces ($parentLeft/Middle/Right)
-- and unnamed Common-Input-Border regions.
--
-- `flat` (used for MoneyInputFrameTemplate's Gold/Silver/Copper boxes) draws a plain dark fill and
-- NO border edge. The bordered backdrop's tiled edge (12px per side) is wider than the ~25px
-- Silver/Copper boxes can hold, so it overflowed the box bounds and bled over the denomination
-- coin icons anchored just past each box's right edge -- making the coins look like they sat under
-- the boxes. A borderless fill stays strictly within the box (the coins, drawn on a higher layer,
-- read cleanly beside it) and keeps all three money boxes looking consistent with each other.
local function reskinInput(eb, flat)
  if not eb or eb._neAtrSkinned then return end
  eb._neAtrSkinned = true
  local n = eb.GetName and eb:GetName()
  local found = false
  if n then
    for _, s in ipairs({ "Left", "Middle", "Right" }) do
      local t = _G[n .. s]
      if t and t.Hide then t:Hide(); found = true end
    end
  end
  if not found then
    hideTexturesByFile(eb, "Common-Input-Border")
  end
  if flat then
    if eb.SetBackdrop then eb:SetBackdrop(nil) end
    -- Sublevel -8 (BACKGROUND's lowest) so this always draws BEHIND Auctionator's own coin-icon
    -- texture on the same box: Auctionator creates that icon at BACKGROUND/0 during its own
    -- frame setup (before this reskin pass ever runs), and WoW draws same-layer/sublevel
    -- textures in creation order -- our fill, being newer, would otherwise paint OVER the coin
    -- (exactly what silver/copper showed: the coin half-hidden under the fill's right edge).
    local fill = eb:CreateTexture(nil, "BACKGROUND", nil, -8)
    fill:SetTexture(WHITE)
    fill:SetVertexColor(0, 0, 0, 0.5)
    fill:SetAllPoints(eb)
    return
  end
  if eb.SetBackdrop then
    eb:SetBackdrop({
      bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
      edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
      tile = true, tileSize = 16, edgeSize = 12,
      insets = { left = 3, right = 3, top = 3, bottom = 3 },
    })
    eb:SetBackdropColor(0, 0, 0, 0.6)
    eb:SetBackdropBorderColor(0.4, 0.4, 0.4, 1)
  end
end

-- NE list-row treatment (zebra stripe + additive gold hover/pressed) for Auctionator's row
-- buttons. Replacing the highlight texture keeps LockHighlight-based selection working -- the
-- locked state just shows our gold wash instead of the stock blue.
local function reskinRow(btn, i)
  if not btn or btn._neAtrSkinned then return end
  btn._neAtrSkinned = true
  local bg = btn:CreateTexture(nil, "BACKGROUND")
  bg:SetTexture(WHITE)
  bg:SetAllPoints(btn)
  bg:SetVertexColor(0.07, 0.07, 0.08, (i % 2 == 0) and 0.30 or 0.20)
  btn:SetHighlightTexture(WHITE)
  local hl = btn:GetHighlightTexture()
  if hl then hl:SetVertexColor(1, 0.82, 0, 0.12); hl:SetBlendMode("ADD") end
  btn:SetPushedTexture(WHITE)
  local pt = btn:GetPushedTexture()
  if pt then pt:SetVertexColor(1, 0.82, 0, 0.20); pt:SetBlendMode("ADD") end
end

-- Minimal scrollbar for a FauxScrollFrame, with the same strata fix every list in this window
-- needs (see Browse.lua): the shell is DIALOG, BuildCustom's bar defaults to HIGH -- behind the
-- rows -- and the arrows were leveled against the bar's build-time strata.
local function buildBar(scroll, opts)
  if not (scroll and NE.scrollbar and NE.scrollbar.BuildCustom) then return end
  local ok, bar = pcall(NE.scrollbar.BuildCustom, scroll, opts)
  if ok and bar then
    -- Keep Auctionator's FauxScroll container mouse-transparent so entry buttons behind/around it
    -- remain the primary click target even when overflow enables scrolling.
    if scroll.EnableMouse then pcall(scroll.EnableMouse, scroll, false) end
    if scroll.EnableMouseWheel then pcall(scroll.EnableMouseWheel, scroll, true) end
    if not scroll._neAtrMouseHooked then
      scroll._neAtrMouseHooked = true
      scroll:HookScript("OnShow", function(s)
        if s.EnableMouse then pcall(s.EnableMouse, s, false) end
        if s.EnableMouseWheel then pcall(s.EnableMouseWheel, s, true) end
      end)
    end

    -- FauxScrollFrameTemplate still owns an internal slider (<name>ScrollBar) even when we draw a
    -- custom bar. If that stock slider pops back shown while overflow exists, it can sit as an
    -- invisible mouse layer over row buttons. Keep it non-interactive and hidden at all times.
    local sName = scroll.GetName and scroll:GetName()
    local stock = sName and _G[sName .. "ScrollBar"]
    if stock then
      if stock.EnableMouse then pcall(stock.EnableMouse, stock, false) end
      stock:SetAlpha(0)
      if not stock._neAtrHideHooked then
        stock._neAtrHideHooked = true
        stock:HookScript("OnShow", function(s) s:Hide() end)
      end
      stock:Hide()
    end

    -- Keep the row buttons explicitly interactive; this is idempotent and avoids regressions if
    -- an external cloak/restore pass touched click-enable state earlier.
    if sName and string.find(sName, "AuctionatorScrollFrame", 1, true) then
      for i = 1, 15 do
        local row = _G["AuctionatorEntry" .. i]
        if row and row.EnableMouse then row:EnableMouse(true) end
      end
    end

    bar:SetFrameStrata("DIALOG")
    bar:SetFrameLevel((scroll:GetFrameLevel() or 1) + 10)
    if bar._upBtn then bar._upBtn:SetFrameStrata("DIALOG"); bar._upBtn:SetFrameLevel(bar:GetFrameLevel() + 1) end
    if bar._downBtn then bar._downBtn:SetFrameStrata("DIALOG"); bar._downBtn:SetFrameLevel(bar:GetFrameLevel() + 1) end

    -- BuildCustom parents the bar to the scroll frame's PARENT (Atr_Main_Panel), not the scroll
    -- frame, so it does NOT inherit Hide() when Auctionator hides a list on tabs that don't use
    -- it -- the left Hlist is hidden on the Sell tab, but its bar was left floating over the sell
    -- controls (cutting off the copper money box). Its self-sync only runs on the scroll frame's
    -- OnUpdate, which doesn't fire while hidden, so it never corrected itself. Tie the bar's
    -- visibility to the scroll frame's own shown state.
    if not scroll._neAtrBarVis then
      scroll._neAtrBarVis = true
      local function setBarShown(on)
        if on then bar:Show() else bar:Hide() end
        if bar._upBtn then if on then bar._upBtn:Show() else bar._upBtn:Hide() end end
        if bar._downBtn then if on then bar._downBtn:Show() else bar._downBtn:Hide() end end
      end
      scroll:HookScript("OnShow", function() setBarShown(true) end)
      scroll:HookScript("OnHide", function() setBarShown(false) end)
      if not scroll:IsShown() then setBarShown(false) end
    end
  end
end

----------------------------------------------------------------------
-- Embed steps
----------------------------------------------------------------------

local function embedPanel()
  local p = _G.Atr_Main_Panel
  local pane = AH.frame.ExternalPane
  p:SetParent(pane)
  p:ClearAllPoints()
  p:SetPoint("TOPLEFT", pane, "TOPLEFT", PANEL_X, PANEL_Y)
  p:SetFrameLevel((pane:GetFrameLevel() or 1) + 3)
  restoreTree(p, 0)
end

-- Re-anchor the pieces whose XML positions poke past the shell's 800px width (they were tuned
-- for the 832-wide legacy AuctionFrame). All of these are positioned ONLY in XML -- Auctionator's
-- Lua never re-anchors them -- so a one-time re-anchor here is stable.
local function anchorExtras()
  local pane = AH.frame.ExternalPane

  -- "Options" button (Atr_FullScanButton chains off its LEFT in XML and follows automatically).
  -- Its XML slot (165px right of the Search button) lands at shell x ~809 -- off the frame.
  local opt = _G.Auctionator1Button
  if opt then
    opt:ClearAllPoints()
    opt:SetPoint("TOPRIGHT", pane, "TOPRIGHT", -10, PANEL_Y - 46)
  end

  -- The CLOSE button duplicates the shell's own close X, and its OnClick
  -- (HideUIPanel(parent:GetParent())) would now target the shell's ContentRoot. Retire it.
  local close = _G.AuctionatorCloseButton
  if close then
    close:Hide()
    if not close._neAtrHideHooked then
      close._neAtrHideHooked = true
      close:HookScript("OnShow", function(s) s:Hide() end)
    end
  end

  -- "Cancel Auctions" becomes the right anchor of the bottom cluster (Atr_Buy1_Button chains off
  -- its LEFT in XML). XML put the cluster 66px past the panel's right edge.
  local cancel = _G.Atr_CancelSelectionButton
  if cancel then
    cancel:ClearAllPoints()
    cancel:SetPoint("BOTTOMRIGHT", pane, "BOTTOMRIGHT", -10, 33)
  end

  -- Current/History/Other tabs hang off Atr_HeadingsBar's TOPRIGHT, which (605 wide at panel x+6
  -- inside a 548-wide panel) pokes ~10px past the shell's right edge. Pull them back inside.
  local tabs = _G.Atr_ListTabs
  if tabs and _G.Atr_HeadingsBar then
    tabs:ClearAllPoints()
    tabs:SetPoint("BOTTOMRIGHT", _G.Atr_HeadingsBar, "TOPRIGHT", -25, -22)
  end

  -- Drop-target highlight: XML anchors it 66px past the panel's right edge and code SetSize()s
  -- it 805 wide (sell-tab whole-pane drop) or 610 wide (item slotted). Re-anchor inside the
  -- shell and clamp any future SetSize to the shell's width.
  local hilite = _G.Atr_Hilite1
  if hilite then
    hilite:ClearAllPoints()
    hilite:SetPoint("TOPRIGHT", _G.Atr_Main_Panel, "TOPRIGHT", 34, -70)
  end
  for _, name in ipairs({ "Atr_Hilite1", "Atr_Hilite1_btn" }) do
    local h = _G[name]
    if h and not h._neAtrClamp then
      h._neAtrClamp = true
      hooksecurefunc(h, "SetSize", function(s, w, hh)
        if s._neAtrClamping then return end
        if w and w > HILITE_MAX_W then
          s._neAtrClamping = true
          s:SetSize(HILITE_MAX_W, hh)
          s._neAtrClamping = nil
        end
      end)
      local w, hh = h:GetSize()
      if w and w > HILITE_MAX_W then h:SetSize(HILITE_MAX_W, hh) end
    end
  end
end

-- Push the Buy/More left column (dropdown/list/shopping-list buttons) down by BUYMORE_SHIFT_Y so
-- its top lines up with the Sell tab's sell-controls frame (see the constant's comment above).
-- Each widget keeps its ORIGINAL x and its position relative to the others -- only the shared
-- panel-relative y changes, so this can't disturb anything about their own internal layout
-- (list row spacing, button widths, dropdown menu content), just where the group sits vertically.
local LEFTCOL_CENTER_X = (LEFTCOL_L + LEFTCOL_R) / 2

local function alignBuyMoreColumn()
  local p = _G.Atr_Main_Panel
  if not p then return end
  for i = 1, #BUYMORE_WIDGETS do
    local w = BUYMORE_WIDGETS[i]
    local f = _G[w.name]
    if f then
      -- Buttons (w.w) carry their own explicit width; everything else keeps its native width.
      -- Applied BEFORE the center/x branches below so `center` still respects a manual `w` if
      -- both are ever set on the same entry, instead of silently ignoring it.
      if w.w and f.SetWidth then f:SetWidth(w.w) end

      local point = w.point
      local x
      if w.center then
        -- Horizontally center the widget's own width on the left column box, regardless of its
        -- native XML anchor -- always via TOPLEFT so the box-relative math (LEFTCOL_L/R) applies.
        point = "TOPLEFT"
        local fw = (f.GetWidth and f:GetWidth()) or 0
        x = LEFTCOL_CENTER_X - (fw / 2)
      elseif w.w then
        x = w.x
      else
        x = w.x + BUYMORE_SHIFT_X
      end
      f:ClearAllPoints()
      f:SetPoint(point, p, point, x, w.y + BUYMORE_SHIFT_Y + (w.extra or 0))
    end
  end
end

-- Auctionator's dialogs + modal mask are parented to UIParent at fixed offsets tuned for the
-- legacy frame's screen position; the shell is centered. Re-anchor them over the shell.
local function anchorDialogs()
  local f = AH.frame

  local mask = _G.Atr_Mask
  if mask then
    local function layoutMask()
      mask:ClearAllPoints()
      mask:SetPoint("TOPLEFT", f, "TOPLEFT", 4, -20)
      mask:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -4, 4)
      -- FULLSCREEN sits above the shell's DIALOG but below the dialogs' FULLSCREEN_DIALOG.
      mask:SetFrameStrata("FULLSCREEN")
      if mask.SetBackdropColor then mask:SetBackdropColor(0, 0, 0, 0.6) end
    end
    layoutMask()
    -- Same issue as the dialogs below: Auctionator re-anchors/resizes Atr_Mask (tuned for the
    -- legacy standalone AuctionFrame) itself each time it shows one, which only covered part of
    -- this bigger shell -- leaving the uncovered strip look like a stray shadow/seam next to
    -- whatever dialog was open. Re-apply on every OnShow so it always covers the full shell.
    if not mask._neAtrLayoutHooked then
      mask._neAtrLayoutHooked = true
      mask:HookScript("OnShow", layoutMask)
    end
  end

  local dialogNames = {
    "Atr_Buy_Confirm_Frame", "Atr_CheckActives_Frame", "Atr_CancelAuction_Confirm_Frame",
    "Atr_FullScanFrame", "Atr_Adv_Search_Dialog", "Atr_Error_Frame", "Atr_Confirm_Frame",
  }
  local function centerDialog(d)
    d:ClearAllPoints()
    d:SetPoint("CENTER", f, "CENTER", 0, 0)
    d:SetFrameStrata("FULLSCREEN_DIALOG")
  end
  for i = 1, #dialogNames do
    local d = _G[dialogNames[i]]
    if d then
      centerDialog(d)
      -- Auctionator re-anchors some of these to UIParent CENTER (its own default, tuned for a
      -- standalone frame) every time it opens them, undoing the one-time anchor above -- Full
      -- Scan in particular reset to the screen's center instead of the shell's on each open.
      -- Re-apply on every OnShow so it always lands on the shell no matter who last moved it.
      if not d._neAtrCenterHooked then
        d._neAtrCenterHooked = true
        d:HookScript("OnShow", function(self) centerDialog(self) end)
      end
    end
  end
end

----------------------------------------------------------------------
-- Reskin steps
----------------------------------------------------------------------

local function reskinLists()
  local p = _G.Atr_Main_Panel

  -- Results list: one gold-trim inset wrapping the headings bar + the 15 row buttons, dark fill
  -- behind -- replacing the CharacterCreate parchment label bar.
  local headings = _G.Atr_HeadingsBar
  local lastRow = _G.AuctionatorEntry15
  if headings and lastRow and not ATR._listInset then
    local inset = CreateFrame("Frame", nil, p)
    inset:SetPoint("TOPLEFT", headings, "TOPLEFT", 0, -14)
    inset:SetPoint("BOTTOMRIGHT", lastRow, "BOTTOMRIGHT", 6, -4)
    inset:EnableMouse(false)
    -- Created AFTER the row buttons (same default level, later creation order = drawn on top),
    -- so without this the dark fill would paint OVER the rows. Drop to the panel's own level;
    -- AttachInset's border pieces live on a child a level up, which keeps the gold trim visible.
    inset:SetFrameLevel(p:GetFrameLevel() or 1)
    -- Right-hand list uses the shell Sell tab's own right-panel background art (shared across
    -- Auctionator's Buy/Sell/More tabs, since it's one frame), cropped to the list's proportions
    -- so the art isn't stretched.
    croppedInsetBg(inset, "auctionhouse-background-sell-right")
    attachInset(inset)
    ATR._listInset = inset

    -- Headings bar: kill the parchment sheet, draw the shell's header-strip tone behind the
    -- column-heading buttons instead. The strip spans the vertical band the column text/buttons
    -- occupy (the parchment was 64 tall with the labels vertically centered).
    local mid = _G.Atr_HeadingsBarMiddle
    if mid then mid:SetTexture(nil); mid:Hide() end
    local strip = headings:CreateTexture(nil, "BACKGROUND")
    strip:SetTexture(WHITE)
    strip:SetVertexColor(0.06, 0.06, 0.07, 0.95)
    strip:SetPoint("TOPLEFT", headings, "TOPLEFT", 0, -14)
    strip:SetPoint("RIGHT", inset, "RIGHT", -1, 0)
    strip:SetHeight(32)
  end
  for i = 1, 15 do reskinRow(_G["AuctionatorEntry" .. i], i) end
  if _G.AuctionatorScrollFrame then
    -- x=-12 pushes the bar (and its wider arrows) OUT toward the scroll frame's right edge, closer
    -- to the results panel's right gold border, over the empty margin past the last column's text.
    -- x=8 sat noticeably too far left/inward of the border (the 584px rows overhang the 588px
    -- scroll frame slightly, and the bordered inset sits ~6px further out again, but that left a
    -- visible gap between the bar and the border).
    buildBar(_G.AuctionatorScrollFrame, { x = -12, alwaysShow = false })
  end

  -- Left column (recent searches / active items / shopping lists). Strip the list's own
  -- parchment backdrop + tooltip-border divider; the unified column panel below provides the
  -- background instead.
  local hl = _G.Atr_Hlist
  if hl and not hl._neAtrSkinned then
    hl._neAtrSkinned = true
    if hl.SetBackdrop then hl:SetBackdrop(nil) end
    hideTexturesByFile(hl, "Tooltip-Border")
  end

  -- Dark textured backing for the whole left column -- dropdown + list + shopping-list buttons --
  -- with the same recessed inset border as the right-hand results list.
  -- Toggled with the list's shown state so it doesn't paint over the Sell tab's sell-controls box
  -- (the left column is empty on the Sell tab).
  if hl and p and not ATR._leftCol then
    local col = CreateFrame("Frame", nil, p)
    col:SetFrameLevel(p:GetFrameLevel() or 1)
    col:EnableMouse(false)
    col:SetPoint("TOPLEFT", p, "TOPLEFT", LEFTCOL_L, LEFTCOL_T)
    col:SetPoint("BOTTOMRIGHT", p, "TOPLEFT", LEFTCOL_R, LEFTCOL_B)
    croppedInsetBg(col, "auctionhouse-background-sell-left")
    attachInset(col)
    ATR._leftCol = col
    local function setColShown(on) if on then col:Show() else col:Hide() end end
    hl:HookScript("OnShow", function() setColShown(true) end)
    hl:HookScript("OnHide", function() setColShown(false) end)
    if not hl:IsShown() then col:Hide() end
  end
  if _G.Atr_Hlist_ScrollFrame then
    -- x=-9 centres the bar (+ its 17px-wide arrows) in the ~18px gutter between the Hlist rows'
    -- right edge (~panel x-16) and the left-column box's right edge (+2). x=-15 pushed the arrows
    -- ~5px past the box; x=-9 keeps the whole scrollbar inside it.
    buildBar(_G.Atr_Hlist_ScrollFrame, { x = -9 })
    -- Nudge the built bar DOWN 6px. BuildCustom anchors it flush to the scroll frame's top/bottom
    -- (inset 25px for arrow clearance); dropping it a touch keeps the up-arrow clear of the list's
    -- top row and sits the whole bar more comfortably inside the box.
    local sf = _G.Atr_Hlist_ScrollFrame
    local bar = sf._neCustomBar
    if bar and not bar._neHlistDrop then
      bar._neHlistDrop = true
      bar:ClearAllPoints()
      bar:SetPoint("TOPLEFT",    sf, "TOPRIGHT",    9, -25 - 6)
      bar:SetPoint("BOTTOMLEFT", sf, "BOTTOMRIGHT", 9,  25 - 6)
    end
  end

  -- Left-list rows are created lazily inside Atr_DisplayHlist -- restyle current ones now and
  -- any new ones after every display pass.
  local function reskinHEntries()
    local i = 1
    while _G["AuctionatorHEntry" .. i] do
      reskinRow(_G["AuctionatorHEntry" .. i], i)
      i = i + 1
    end
  end
  reskinHEntries()
  if type(_G.Atr_DisplayHlist) == "function" and not ATR._hlistHook then
    ATR._hlistHook = true
    hooksecurefunc("Atr_DisplayHlist", reskinHEntries)
  end
end

local function reskinSellControls()
  local p = _G.Atr_Main_Panel
  local sc = _G.Atr_SellControls
  if sc and p and not sc._neAtrSkinned then
    sc._neAtrSkinned = true
    if sc.SetBackdrop then sc:SetBackdrop(nil) end
    -- Fill + gold inset on a LOW frame parented to the panel (not sc), so it draws BEHIND sc's
    -- own controls (a child of sc created later would paint over the money boxes). Extended
    -- past sc's bottom by 40px so the Deposit line -- which Auctionator anchors just below sc's
    -- own edge -- sits inside the border instead of hanging beneath it.
    local wrap = CreateFrame("Frame", nil, p)
    wrap:SetPoint("TOPLEFT", sc, "TOPLEFT", -2, 6)
    wrap:SetPoint("BOTTOMRIGHT", sc, "BOTTOMRIGHT", 2, -40)
    wrap:SetFrameLevel(p:GetFrameLevel() or 1)
    wrap:EnableMouse(false)
    -- Sell-left background art, cropped to the sell-controls column's tall-narrow proportions so
    -- the wide art shows an undistorted slice instead of being squashed, plus the same recessed
    -- inset border as the Buy/More left column so all three tabs' left panels match.
    croppedInsetBg(wrap, "auctionhouse-background-sell-left")
    attachInset(wrap)
    ATR._sellWrap = wrap
    -- Item slot: the shell Sell pane's empty-slot plate behind the 37px drop button, framed by
    -- the same "itemheaderframe" plate the normal (non-Auctionator) Sell tab wraps around its
    -- icon+name row (Sell.lua's `disp`/`hf`, native art 342x72 around a 54px icon inset 12,9).
    -- Scaled down to THIS icon's actual size (queried at runtime, not hardcoded) so the plate's
    -- proportions stay correct regardless of exactly how big Auctionator's own icon button is,
    -- and clamped so the plate can never poke past `wrap`'s own right edge. Drawn on `wrap`
    -- (parented to the panel, not sc) so it sits BEHIND sc's own icon/text, same as the rest of
    -- this wrap's background art. Only shown while an item is actually slotted for sale -- like
    -- the native Sell tab's item row, an empty slot shows no header plate.
    local slot = _G.Atr_SellControls_Tex
    if slot and NE.tex and NE.tex.SetAtlas then
      local bg = slot:CreateTexture(nil, "BACKGROUND")
      bg:SetAllPoints(slot)
      NE.tex.SetAtlas(bg, "auctionhouse-itemicon-empty", false)

      local hf = wrap:CreateTexture(nil, "ARTWORK")
      if NE.tex.SetAtlas(hf, "auctionhouse-itemheaderframe", false) then
        -- Extra native-art px added to the plate's height (top edge stays put, so this all lands
        -- at the bottom) -- at the plain 72-tall scale the icon's bottom edge touched/overlapped
        -- the plate's own bottom border line.
        local HEIGHT_PAD = 10
        local function layoutHf()
          local iconW = slot:GetWidth()
          if not (iconW and iconW > 0) then iconW = 37 end
          local scale = iconW / 54
          local maxW = wrap:GetWidth()
          if maxW and maxW > 0 then
            local capScale = (maxW - 4) / 342
            if capScale > 0 and scale > capScale then scale = capScale end
          end
          hf:SetSize(342 * scale, (72 + HEIGHT_PAD) * scale)
          hf:ClearAllPoints()
          hf:SetPoint("TOPLEFT", slot, "TOPLEFT", -18 * scale, 9 * scale)
        end
        layoutHf()
        if C_Timer and C_Timer.After then C_Timer.After(0, layoutHf) end
        wrap:HookScript("OnSizeChanged", layoutHf)

        -- Gate on an item being slotted AND the Sell tab itself actually being the active tab.
        -- GetAuctionSellItemInfo() stays populated even while Buy/More are active (the slotted
        -- item persists across tabs), and sc:IsShown() alone isn't reliable -- Auctionator keeps
        -- Atr_SellControls in the shown state even off the Sell tab. Atr_Hlist (the Buy/More
        -- results/search list) IS reliably toggled per-tab elsewhere in this file, so use its
        -- shown state as the tab signal instead: Sell is active exactly when Hlist is hidden.
        local hl = _G.Atr_Hlist
        local function updateHfShown()
          local sellActive = sc:IsShown() and not (hl and hl:IsShown())
          if sellActive and GetAuctionSellItemInfo and GetAuctionSellItemInfo() then
            hf:Show()
          else
            hf:Hide()
          end
        end
        hf:Hide()
        sc:HookScript("OnShow", updateHfShown)
        sc:HookScript("OnHide", updateHfShown)
        if hl then
          hl:HookScript("OnShow", updateHfShown)
          hl:HookScript("OnHide", updateHfShown)
        end
        if not ATR._sellHfWatcher then
          local watcher = CreateFrame("Frame")
          watcher:RegisterEvent("NEW_AUCTION_UPDATE")
          watcher:RegisterEvent("AUCTION_HOUSE_SHOW")
          watcher:SetScript("OnEvent", updateHfShown)
          ATR._sellHfWatcher = watcher
        end
        updateHfShown()
      end
    end
  end
  -- MoneyInputFrame gold/silver/copper boxes get the borderless flat fill (see reskinInput's
  -- `flat`) so the backdrop border can't overflow the narrow boxes onto their coin icons.
  for _, base in ipairs({ "Atr_StackPrice", "Atr_ItemPrice", "Atr_StartingPrice" }) do
    for _, den in ipairs({ "Gold", "Silver", "Copper" }) do
      reskinInput(_G[base .. den], true)
    end
  end
  reskinInput(_G.Atr_Batch_NumAuctions)
  reskinInput(_G.Atr_Batch_Stacksize)
end

local function reskinSearchRow()
  local box = _G.Atr_Search_Box
  if box and not box._neAtrSearch then
    box._neAtrSearch = true
    reskinInput(box)
    box:SetTextInsets(20, 8, 0, 0)
    local icon = box:CreateTexture(nil, "OVERLAY")
    icon:SetSize(14, 14)
    icon:SetPoint("LEFT", box, "LEFT", 5, 0)
    icon:SetTexture("Interface\\Common\\UI-Searchbox-Icon")
  end
  -- EditBoxes inside the dialogs get the same input treatment.
  reskinInput(_G.Atr_Buy_Confirm_Numstacks)
  for _, n in ipairs({ "Atr_AS_Searchtext", "Atr_AS_Minlevel", "Atr_AS_Maxlevel",
                       "Atr_AS_MinItemlevel", "Atr_AS_MaxItemlevel" }) do
    reskinInput(_G[n])
  end
end

-- Current/History/Other are stock TabButtonTemplate tabs (same 6-piece art as the classic
-- bottom tabs) sitting on TOP of the list -- reskin then flip upward.
local function reskinListTabs()
  if not (NE.tabs and NE.tabs.ReskinClassicTab) then return end
  for i = 1, 3 do
    local name = "Atr_ListTabsTab" .. i
    if _G[name] then
      NE.tabs.ReskinClassicTab(name)
      if NE.tabs.MakeTopTab then NE.tabs.MakeTopTab(name) end
    end
  end
end

local function reskinDialogs()
  local names = {
    "Atr_Buy_Confirm_Frame", "Atr_CheckActives_Frame", "Atr_CancelAuction_Confirm_Frame",
    "Atr_FullScanFrame", "Atr_Adv_Search_Dialog", "Atr_Error_Frame", "Atr_Confirm_Frame",
  }
  for i = 1, #names do
    local d = _G[names[i]]
    if d and not d._neAtrSkinned then
      d._neAtrSkinned = true
      if d.SetBackdrop then d:SetBackdrop(nil) end
      -- the "Full Scan" / "Advanced Search" parchment banner texture
      hideTexturesByFile(d, "UI-DialogBox-Header")
      darkFill(d, 0.06, 0.06, 0.07, 0.97)
      attachInset(d)
      -- Red 3-slice on the dialogs' own buttons (Full Scan's Start Scanning/DONE/Reload,
      -- Advanced Search's Search/Cancel, the buy/cancel confirmations). Window.lua Watches the
      -- SHELL frame, which covers everything under ExternalPane -- but these dialogs are parented
      -- to UIParent, not to the shell, so that sweep never reaches them and they kept the stock
      -- UIPanelButtonTemplate art. Watch (rather than a one-shot sweep) re-runs on every OnShow,
      -- which also picks up anything Auctionator builds into a dialog lazily.
      if NE.buttonskin and NE.buttonskin.Watch then pcall(NE.buttonskin.Watch, d) end
    end
  end
  -- Nested results box inside the Full Scan dialog: border only (no second fill on a fill).
  local fsr = _G.Atr_FullScanResults
  if fsr and not fsr._neAtrSkinned then
    fsr._neAtrSkinned = true
    if fsr.SetBackdrop then fsr:SetBackdrop(nil) end
    attachInset(fsr)
  end
end

----------------------------------------------------------------------
-- Behaviour hooks
----------------------------------------------------------------------

-- Auctionator writes "Auctionator+ - Buy/Sell/More..." into its own in-panel title fontstring on
-- every tab switch. Hide the fontstring and mirror the text into the shell's title bar instead
-- (Window.lua's setTitleForMode also reads ATR._lastTitle for external modes).
local function hookTitle()
  local t = _G.AuctionatorTitle
  if not t or ATR._titleHooked then return end
  ATR._titleHooked = true
  t:SetAlpha(0)
  ATR._lastTitle = t:GetText()
  hooksecurefunc(t, "SetText", function(_, txt)
    ATR._lastTitle = txt
    local f = AH.frame
    if f and f:IsShown() and type(f._mode) == "string"
       and string.find(f._mode, "external:", 1, true) == 1 then
      if NE.panelchrome and NE.panelchrome.SetTitle then
        NE.panelchrome.SetTitle(f, txt or "")
      end
    end
  end)
end

-- Keep the shell's tab state in sync when Auctionator switches its own pane WITHOUT going
-- through our tabs -- e.g. alt-clicking a bag item or dropping an item on the sell pane both
-- call Atr_SelectPane(SELL_TAB) internally. ATR._clicking guards the reverse direction (our
-- TabBridge onSelect clicking the native tab would otherwise bounce back through here).
local function hookTabSync()
  if ATR._tabHooked or type(_G.Atr_AuctionFrameTab_OnClick) ~= "function" then return end
  ATR._tabHooked = true
  hooksecurefunc("Atr_AuctionFrameTab_OnClick", function(self, index)
    if not ATR._embedded or ATR._clicking then return end
    if type(index) ~= "number" then
      index = self and self.GetID and self:GetID()
    end
    if not index or index < 4 then return end
    local f = AH.frame
    if not (f and f:IsShown() and f.ExternalTabDefs) then return end
    local key = "AuctionatorNative" .. index
    local mode = "external:" .. key
    if f._mode == mode or not f.ExternalTabDefs[key] then return end
    -- Auctionator already switched its pane; mirror it in the shell without a second click
    -- (TabBridge's onSelect skips the click while ATR._syncing is set).
    ATR._syncing = true
    if AH.SetMode then pcall(AH.SetMode, mode) end
    ATR._syncing = nil
  end)
end

local function hookRowClickSafety()
  if ATR._rowClickHooked then return end
  ATR._rowClickHooked = true

  local function apply()
    local sf = _G.AuctionatorScrollFrame
    if sf then
      if sf.EnableMouse then pcall(sf.EnableMouse, sf, false) end
      if sf.EnableMouseWheel then pcall(sf.EnableMouseWheel, sf, true) end
      local rowLevel = (sf:GetFrameLevel() or 1) + 2
      for i = 1, 15 do
        local row = _G["AuctionatorEntry" .. i]
        if row then
          if row.SetFrameLevel and (row:GetFrameLevel() or 1) < rowLevel then
            row:SetFrameLevel(rowLevel)
          end
          if row.EnableMouse then row:EnableMouse(true) end
          if row.RegisterForClicks then row:RegisterForClicks("LeftButtonUp") end
        end
      end
    end
  end

  apply()
  if type(_G.Atr_RedisplayAuctions) == "function" then
    hooksecurefunc("Atr_RedisplayAuctions", apply)
  end
  if _G.AuctionatorScrollFrame and not _G.AuctionatorScrollFrame._neAtrClickSafetyHook then
    _G.AuctionatorScrollFrame._neAtrClickSafetyHook = true
    _G.AuctionatorScrollFrame:HookScript("OnShow", apply)
  end
end

----------------------------------------------------------------------
-- Driver
----------------------------------------------------------------------

local function tryEmbed()
  if ATR._embedded then return end
  if not isAddonLoaded("Auctionator") then return end
  if not (_G.Atr_Main_Panel and AH.frame and AH.frame.ExternalPane) then return end

  local steps = {
    embedPanel, anchorExtras, alignBuyMoreColumn, anchorDialogs,
    reskinLists, reskinSellControls, reskinSearchRow, reskinListTabs, reskinDialogs,
    hookTitle, hookTabSync, hookRowClickSafety,
  }
  for i = 1, #steps do pcall(steps[i]) end

  ATR._embedded = true
  -- Window.lua reads this to keep the legacy AuctionFrame cloaked on external tabs.
  AH._atrEmbedded = true

  if AH.RefreshExternalTabs then pcall(AH.RefreshExternalTabs) end
end
ATR.TryEmbed = tryEmbed

local ev = CreateFrame("Frame")
ev:RegisterEvent("PLAYER_LOGIN")
ev:RegisterEvent("ADDON_LOADED")
ev:RegisterEvent("AUCTION_HOUSE_SHOW")
ev:SetScript("OnEvent", function(_, event, arg1)
  if event == "ADDON_LOADED" and arg1 ~= "Auctionator" and arg1 ~= "Blizzard_AuctionUI" then
    return
  end
  tryEmbed()
  -- Atr_Init (which creates Atr_Main_Panel) runs off Blizzard_AuctionUI's ADDON_LOADED, which
  -- lands in the same frame as the first AUCTION_HOUSE_SHOW -- retry shortly after, same as
  -- Window.lua's native-tab rescans.
  if event == "AUCTION_HOUSE_SHOW" and C_Timer and C_Timer.After then
    C_Timer.After(0, tryEmbed)
    C_Timer.After(0.2, tryEmbed)
  end
end)
