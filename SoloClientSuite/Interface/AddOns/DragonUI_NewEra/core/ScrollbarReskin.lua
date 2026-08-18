-- DragonUI_NewEra/core/ScrollbarReskin.lua — SHARED scrollbar reskin for any UIPanel ScrollFrame.
-- Visual port of retail's MinimalScrollBar over the CLASSIC Slider-based UIPanelScrollBar.
--
-- DOWNPORT: NewEra Core/ScrollbarReskin.lua → 3.3.5a.
--   * NE.scrollbar.Reskin (the Slider/UIPanelScrollBar path) PORTS DIRECTLY — UIPanelScrollFrame
--     Template + Slider + named ScrollUpButton/ScrollDownButton all exist on 3.3.5a. The only
--     change is SetShown → Show/Hide and routing setAtlas through NE.tex.SetAtlas.
--   * NE.scrollbar.AttachMinimal + AttachBottomShadow depend on RETAIL-ONLY infrastructure
--     (WowScrollBox, MinimalScrollBar template, EventFrame, ScrollUtil, BaseScrollBoxEvents,
--     RegisterCallback). None exist on 3.3.5a, so they are FEATURE-GATED v1 STUBS: they detect
--     the missing infra and return nil (no error). When/if a compat layer ships WowScrollBox they
--     light up unchanged. v1 panels use Reskin (the Slider path).
--
-- §2 CONTRACT: NE.scrollbar.* preserved.
--
-- The minimal-scrollbar atlas sheets are NOT in the Sprint-0 set, so even Reskin's art swaps
-- degrade gracefully (NE.tex.SetAtlas returns false → piece untextured) until §3 ships them; the
-- reposition/sizing/wheel-enable still work.

local NE = DragonUI_NewEra
NE.scrollbar = NE.scrollbar or {}

-- AttachMinimal — DOWNPORT STUB. Needs WowScrollBox + MinimalScrollBar (retail-only). No-op on
-- 3.3.5a; returns nil. Guarded so a caller that probes for modern infra degrades cleanly.
function NE.scrollbar.AttachMinimal(scrollBox, opts)
  if not scrollBox then return end
  if not (ScrollUtil and CreateFrame) then return end
  -- DOWNPORT: "EventFrame" frame type + "MinimalScrollBar" template don't exist on 3.3.5a;
  -- pcall the create so a missing template can't error. If it fails, bail (v1 stub).
  opts = opts or {}
  local parent = opts.parent or (scrollBox.GetParent and scrollBox:GetParent())
  local ok, bar = pcall(CreateFrame, "EventFrame", opts.name, parent, "MinimalScrollBar")
  if not ok or not bar then return end
  local x = opts.x or 0
  bar:SetPoint("TOPLEFT",    scrollBox, "TOPRIGHT",    x,  opts.top    or 0)
  bar:SetPoint("BOTTOMLEFT", scrollBox, "BOTTOMRIGHT", x,  opts.bottom or 0)
  if opts.hideIfUnscrollable ~= nil then bar.hideIfUnscrollable = opts.hideIfUnscrollable end
  if ScrollUtil and ScrollUtil.InitScrollBoxWithScrollBar then
    if opts.list and ScrollUtil.InitScrollBoxListWithScrollBar then
      ScrollUtil.InitScrollBoxListWithScrollBar(scrollBox, bar, opts.view)
    else
      local view = opts.view or (CreateScrollBoxLinearView and CreateScrollBoxLinearView(0, 0, 0, 0, 0))
      ScrollUtil.InitScrollBoxWithScrollBar(scrollBox, bar, view)
    end
  end
  return bar
end

local SLIDER_WIDTH = 8
local THUMB_WIDTH  = 8
local THUMB_HEIGHT = 60
local ARROW_W      = 17
local ARROW_H      = 11
local CAP_H          = 8
local VISIBLE_GAP    = 6
local ARROW_GAP      = CAP_H + VISIBLE_GAP     -- 14
local SLIDER_Y_INSET = ARROW_H + ARROW_GAP     -- 25

local function setAtlas(tex, name, useAtlasSize)
  if tex and NE.tex and NE.tex.SetAtlas then
    NE.tex.SetAtlas(tex, name, useAtlasSize)
  end
end

local function reskinArrowButton(button, normalAtlas, overAtlas, downAtlas, anchor)
  if not button then return end
  button:ClearAllPoints()
  local sb = button:GetParent()
  if anchor == "TOP" then
    button:SetPoint("BOTTOM", sb, "TOP", 0, ARROW_GAP)
  else
    button:SetPoint("TOP",    sb, "BOTTOM", 0, -ARROW_GAP)
  end
  local n = button:GetNormalTexture()
  local p = button:GetPushedTexture()
  local d = button:GetDisabledTexture()
  local h = button:GetHighlightTexture()
  if n then setAtlas(n, normalAtlas, false) end
  if p then setAtlas(p, downAtlas,   false) end
  if d then setAtlas(d, normalAtlas, false); d:SetDesaturated(true) end
  if h then
    setAtlas(h, overAtlas, false)
    h:SetBlendMode("ADD")
  end
  button:SetSize(ARROW_W, ARROW_H)
end

local function buildTrack(sb)
  if sb._neTrackBegin then return end

  local begin = sb:CreateTexture(nil, "BACKGROUND")
  setAtlas(begin, "minimal-scrollbar-track-top", true)
  begin:SetPoint("TOP", sb, "TOP", 0, 0)

  local endTex = sb:CreateTexture(nil, "BACKGROUND")
  setAtlas(endTex, "minimal-scrollbar-track-bottom", true)
  endTex:SetPoint("BOTTOM", sb, "BOTTOM", 0, 0)

  local middle = sb:CreateTexture(nil, "BACKGROUND")
  setAtlas(middle, "!minimal-scrollbar-track-middle", false)
  middle:SetPoint("TOPLEFT",     begin,  "BOTTOMLEFT")
  middle:SetPoint("BOTTOMRIGHT", endTex, "TOPRIGHT")

  sb._neTrackBegin, sb._neTrackEnd, sb._neTrackMiddle = begin, endTex, middle
end

local function buildThumb(sb)
  if not sb.SetThumbTexture then return end
  local thumb = sb:GetThumbTexture()
  if not thumb then return end

  setAtlas(thumb, "minimal-scrollbar-small-thumb-middle", false)
  thumb:SetSize(THUMB_WIDTH, THUMB_HEIGHT)

  if not sb._neThumbCapHost then
    local host = CreateFrame("Frame", nil, sb)
    host:SetFrameLevel((sb:GetFrameLevel() or 1) + 5)
    host:SetPoint("TOPLEFT",     thumb, "TOPLEFT",     0, 0)
    host:SetPoint("BOTTOMRIGHT", thumb, "BOTTOMRIGHT", 0, 0)
    sb._neThumbCapHost = host
  end
  if not sb._neThumbCapTop then
    local capTop = sb._neThumbCapHost:CreateTexture(nil, "OVERLAY")
    setAtlas(capTop, "minimal-scrollbar-small-thumb-top", true)
    capTop:SetPoint("TOP", sb._neThumbCapHost, "TOP", 0, 0)
    sb._neThumbCapTop = capTop
  end
  if not sb._neThumbCapBot then
    local capBot = sb._neThumbCapHost:CreateTexture(nil, "OVERLAY")
    setAtlas(capBot, "minimal-scrollbar-small-thumb-bottom", true)
    capBot:SetPoint("BOTTOM", sb._neThumbCapHost, "BOTTOM", 0, 0)
    sb._neThumbCapBot = capBot
  end

  if not sb._neThumbHoverHooked then
    sb._neThumbHoverHooked = true
    local function applyState(suffix)
      setAtlas(thumb,             "minimal-scrollbar-small-thumb-middle" .. suffix, false)
      setAtlas(sb._neThumbCapTop, "minimal-scrollbar-small-thumb-top"    .. suffix, true)
      setAtlas(sb._neThumbCapBot, "minimal-scrollbar-small-thumb-bottom" .. suffix, true)
    end
    sb:HookScript("OnEnter",     function() applyState("-over") end)
    sb:HookScript("OnLeave",     function() applyState("")      end)
    sb:HookScript("OnMouseDown", function() applyState("-down") end)
    sb:HookScript("OnMouseUp",   function() applyState("-over") end)
  end
end

-- DOWNPORT helper: SetShown is absent on 3.3.5a — Show/Hide by a boolean.
local function setShown(obj, on)
  if not obj then return end
  if on then obj:Show() else obj:Hide() end
end

-- Public entry — the classic Slider/UIPanelScrollBar reskin. Works on 3.3.5a.
function NE.scrollbar.Reskin(scroll, opts)
  if not scroll then return end
  local sb = scroll.ScrollBar or scroll.scrollBar
  if not sb then return end
  if not sb.ScrollUpButton then
    local sbName = sb.GetName and sb:GetName()
    if sbName then
      sb.ScrollUpButton   = _G[sbName .. "ScrollUpButton"]
      sb.ScrollDownButton = _G[sbName .. "ScrollDownButton"]
    end
  end

  opts = opts or {}
  local xOffset            = opts.x                  or 7
  local strataHigh         = opts.strataHigh         ~= false
  local hideIfUnscrollable = opts.hideIfUnscrollable == true

  local CLASSIC_TRACK = { "Top", "Bottom", "Middle", "Background", "trackBG", "Track" }
  local function hideClassicTrack()
    for _, key in ipairs(CLASSIC_TRACK) do
      local r = sb[key]
      if r and r ~= sb._neTrackBegin and r ~= sb._neTrackEnd and r ~= sb._neTrackMiddle
         and r.Hide then r:Hide() end
    end
  end
  hideClassicTrack()
  if not sb._neTrackHideHooked then
    sb._neTrackHideHooked = true
    sb:HookScript("OnShow", hideClassicTrack)
  end

  scroll:EnableMouseWheel(true)

  sb:ClearAllPoints()
  sb:SetPoint("TOPLEFT",    scroll, "TOPRIGHT",    xOffset, -SLIDER_Y_INSET)
  sb:SetPoint("BOTTOMLEFT", scroll, "BOTTOMRIGHT", xOffset,  SLIDER_Y_INSET)
  sb:SetWidth(SLIDER_WIDTH)
  sb:SetHitRectInsets(-2, -2, 0, 0)

  if strataHigh then
    sb:SetFrameStrata("HIGH")
    if sb.ScrollUpButton   then sb.ScrollUpButton:SetFrameStrata("HIGH")   end
    if sb.ScrollDownButton then sb.ScrollDownButton:SetFrameStrata("HIGH") end
  end
  sb:EnableMouse(true)

  reskinArrowButton(sb.ScrollUpButton,
    "minimal-scrollbar-arrow-top", "minimal-scrollbar-arrow-top-over",
    "minimal-scrollbar-arrow-top-down", "TOP")
  reskinArrowButton(sb.ScrollDownButton,
    "minimal-scrollbar-arrow-bottom", "minimal-scrollbar-arrow-bottom-over",
    "minimal-scrollbar-arrow-bottom-down", "BOTTOM")
  if sb.ScrollUpButton   then sb.ScrollUpButton:EnableMouse(true)   end
  if sb.ScrollDownButton then sb.ScrollDownButton:EnableMouse(true) end

  buildTrack(sb)
  buildThumb(sb)

  local function refreshThumb()
    local yr = (scroll.GetVerticalScrollRange and scroll:GetVerticalScrollRange()) or 0
    local show = yr and yr > 1
    local thumb = sb.GetThumbTexture and sb:GetThumbTexture()
    setShown(thumb, show)                          -- DOWNPORT: SetShown → setShown helper
    setShown(sb._neThumbCapHost, show)
  end
  scroll:HookScript("OnScrollRangeChanged", refreshThumb)
  if C_Timer and C_Timer.After then C_Timer.After(0, refreshThumb) end

  if hideIfUnscrollable then
    scroll.scrollBarHideable = true
    local function applyVisibility()
      local yrange = scroll.GetVerticalScrollRange and scroll:GetVerticalScrollRange() or 0
      local visible = yrange > 0
      setShown(sb.ScrollUpButton, visible)
      setShown(sb.ScrollDownButton, visible)
      setShown(sb, visible)
    end
    scroll:HookScript("OnScrollRangeChanged", applyVisibility)
    if C_Timer and C_Timer.After then C_Timer.After(0, applyVisibility) end
  else
    scroll.scrollBarHideable = nil
    if sb.ScrollUpButton   then sb.ScrollUpButton:Show()   end
    if sb.ScrollDownButton then sb.ScrollDownButton:Show() end
    sb:Show()
    scroll:HookScript("OnScrollRangeChanged", function()
      if sb.ScrollUpButton   then sb.ScrollUpButton:Show()   end
      if sb.ScrollDownButton then sb.ScrollDownButton:Show() end
      sb:Show()
    end)
  end
end

-- ============================================================================
-- NE.scrollbar.BuildCustom — hand-built minimal scrollbar for a named
-- FauxScrollFrameTemplate. (DOWNPORT: built FROM SCRATCH because Reskin's
-- in-place re-skin of the stock UIPanelScrollBar Slider was not rendering — the
-- user still saw the default Blizzard bar. This widget OWNS its own track+thumb
-- frames and merely DRIVES the FauxScrollFrame's hidden internal slider so all
-- the existing FauxScrollFrame_Update / FauxScrollFrame_GetOffset row logic keeps
-- working untouched.)
--
-- How it syncs: a FauxScrollFrameTemplate contains a hidden Slider named
-- "<name>ScrollBar". FauxScrollFrame_Update() sets that slider's min/max and
-- FauxScrollFrame_GetOffset() reads slider:GetValue()/step. So we:
--   * Hide the stock slider + its two arrow buttons (Hide, not remove — Faux
--     still reads/writes the slider's value).
--   * Poll the slider's GetMinMaxValues / GetValue (cheap, OnUpdate-throttled +
--     OnVerticalScroll/OnScrollRangeChanged hooks) to size & place our thumb.
--   * On thumb drag, map the pixel position back to a slider value and
--     slider:SetValue() — which fires the scrollframe's OnVerticalScroll, i.e.
--     the SAME path the wheel uses. No row logic is duplicated.
--   * Hide the whole bar when the content fits (max <= min).
-- Idempotent via scrollFrame._neCustomBar.
-- ----------------------------------------------------------------------------

local CB_WIDTH      = 8      -- track + thumb width
local CB_CAP_H      = 8      -- top/bottom cap height (track + thumb)
local CB_MIN_THUMB  = 24     -- never let the thumb shrink below this
local CB_X_INSET    = -2     -- bar x relative to the pane's right edge

local function cbSetThumbState(bar, suffix)
  setAtlas(bar._thumbMid, "minimal-scrollbar-small-thumb-middle" .. suffix, false)
  setAtlas(bar._thumbTop, "minimal-scrollbar-small-thumb-top"    .. suffix, true)
  setAtlas(bar._thumbBot, "minimal-scrollbar-small-thumb-bottom" .. suffix, true)
end

-- Read the FauxScrollFrame's hidden slider, size+place the thumb, toggle the bar.
local function cbSync(bar)
  local slider = bar._slider
  if not slider then return end
  local minV, maxV = slider:GetMinMaxValues()
  minV = minV or 0; maxV = maxV or 0
  local range = maxV - minV
  -- Content fits → normally hide the whole custom bar (and keep the stock bits hidden).
  -- opts.alwaysShow keeps the TRACK (+ arrows, if present) always visible even with nothing to
  -- scroll yet -- some lists (e.g. the Auctions tab) want the scrollbar chrome present from the
  -- first render, not popping in once content overflows. Matches the reference's own Reskin()
  -- behavior verbatim: "the arrows and track stay ... [only] the thumb hides when content fits
  -- the viewport" -- arrows are NOT disabled in that state, just the thumb disappears. An earlier
  -- attempt stretched the thumb to fill the whole track instead, which just looked like a solid
  -- highlighted bar rather than an empty groove.
  if range <= 0 then
    if not bar._alwaysShow then
      -- The arrow buttons are reparented OFF the slider onto scrollFrame's parent (see BuildCustom)
      -- so they can outlive the slider's own Hide() -- but that also makes them SIBLINGS of bar,
      -- not children of it, so hiding bar alone doesn't hide them. Have to hide them explicitly or
      -- they're left showing over an otherwise-fully-hidden scrollbar (e.g. the Honor tab when its
      -- list fits the viewport).
      bar:Hide()
      if bar._upBtn then bar._upBtn:Hide() end
      if bar._downBtn then bar._downBtn:Hide() end
      return
    end
    bar:Show()
    if bar._upBtn then bar._upBtn:Show() end
    if bar._downBtn then bar._downBtn:Show() end
    if bar._thumb then bar._thumb:Hide() end
    return
  end
  bar:Show()
  if bar._upBtn then bar._upBtn:Show() end
  if bar._downBtn then bar._downBtn:Show() end
  if bar._thumb then bar._thumb:Show() end

  local trackH = bar:GetHeight() or 0
  if trackH <= 0 then return end

  -- Thumb height ~ proportion of visible:total, but we only know the value
  -- range (in steps). Use a fixed-ish thumb that still shrinks on long lists.
  local thumbH = trackH * 0.40
  if range > 0 then
    -- shrink as the scrollable range grows; clamp to a sane band.
    thumbH = trackH * math.max(0.18, math.min(0.6, 1 / (1 + range / (trackH))))
  end
  if thumbH < CB_MIN_THUMB then thumbH = CB_MIN_THUMB end
  if thumbH > trackH then thumbH = trackH end
  bar._thumb:SetHeight(thumbH)

  local val = slider:GetValue() or minV
  local frac = (val - minV) / range
  if frac < 0 then frac = 0 elseif frac > 1 then frac = 1 end
  local travel = trackH - thumbH
  bar._thumb:ClearAllPoints()
  bar._thumb:SetPoint("TOP", bar, "TOP", 0, -(frac * travel))
end

-- BUG FIX (owner report 2026-07-17, TWICE — the global hook below wasn't enough on its own: "bars
-- still don't hide after not being needed"). cbSync is driven by OnVerticalScroll/
-- OnScrollRangeChanged hooks (which a FauxScrollFrame — a fake/manual pagination widget, not a
-- real scrolled child — may never actually fire), the slider's OnValueChanged (doesn't fire for a
-- pure min/max SHRINK when the current value stays clamped at the same spot, e.g. already scrolled
-- to top going from scrollable to fully-fits), and a 100ms-throttled OnUpdate poll. None of those
-- proved reliable enough in practice. NE.scrollbar.SyncCustom is the deterministic fix: callers
-- that already know exactly when their list's item count changed (every Refresh* function calls
-- FauxScrollFrame_Update with the fresh total right there) call this immediately afterward,
-- synchronously, in the SAME call stack as the data change — no hook/event/poll timing to trust.
-- Optional total/numToDisplay (owner report 2026-07-17, persisted through the alwaysShow switch:
-- "the thumb of the bar stays" after a Show Offline-style toggle shrinks the list back to fitting).
-- Root cause: FauxScrollFrame_Update doesn't reliably reset its hidden slider's min/max to 0 on
-- this client when a list shrinks from scrollable to fitting — stale drag/value state can leave
-- GetMinMaxValues() reporting a nonzero range, so cbSync's range<=0 check never trips and the thumb
-- (sized/positioned off that stale range) never hides. This mirrors the defensive clamp the
-- Professions recipe list and Auction House Browse tab already use for the same reason: when the
-- caller tells us the list fits, force the slider to (0, 0) directly before syncing rather than
-- trusting FauxScrollFrame_Update's own write to have taken effect.
function NE.scrollbar.SyncCustom(scrollFrame, total, numToDisplay)
  if not scrollFrame then return end
  if total ~= nil and numToDisplay ~= nil and total <= numToDisplay then
    local bar = scrollFrame._neCustomBar
    local slider = bar and bar._slider
    if slider then
      if slider.SetMinMaxValues then slider:SetMinMaxValues(0, 0) end
      if slider.SetValue then slider:SetValue(0) end
    end
  end
  if scrollFrame._neCustomBar then
    cbSync(scrollFrame._neCustomBar)
  end
end

-- Kept as a redundant safety net for any caller that doesn't (or can't) call SyncCustom directly.
if not NE.scrollbar._neFauxUpdateHooked and _G.FauxScrollFrame_Update and hooksecurefunc then
  NE.scrollbar._neFauxUpdateHooked = true
  hooksecurefunc("FauxScrollFrame_Update", function(scrollFrame)
    NE.scrollbar.SyncCustom(scrollFrame)
  end)
end

-- Drag handler: convert the thumb's top Y (relative to the track) into a slider
-- value and write it back (which scrolls the rows via OnVerticalScroll).
local function cbOnThumbUpdate(thumb)
  local bar = thumb._bar
  local slider = bar and bar._slider
  if not slider then return end
  local minV, maxV = slider:GetMinMaxValues()
  minV = minV or 0; maxV = maxV or 0
  local range = maxV - minV
  if range <= 0 then return end

  local trackTop = bar:GetTop()
  local thumbTop = thumb:GetTop()
  local trackH   = bar:GetHeight() or 0
  local thumbH   = thumb:GetHeight() or 0
  local travel   = trackH - thumbH
  if not (trackTop and thumbTop) or travel <= 0 then return end

  local frac = (trackTop - thumbTop) / travel
  if frac < 0 then frac = 0 elseif frac > 1 then frac = 1 end
  local newVal = minV + frac * range
  if math.abs(newVal - (slider:GetValue() or minV)) >= 0.5 then
    slider:SetValue(newVal)         -- fires scrollFrame OnVerticalScroll → rows update
  end
end

-- Reskin+reposition a FauxScrollFrame's native arrow button in place, anchored off OUR bar frame
-- (not the stock slider) -- used only when opts.arrows requests the reference's Auctions-tab style
-- (the Buy/Sell tabs' scrollbars have no arrows and don't pass this option, so they're unaffected).
local CB_ARROW_W   = 17
local CB_ARROW_H   = 11
-- Reference's ARROW_GAP = thumb cap height (CB_CAP_H, 8) + a 6px visible buffer = 14 -- the gap
-- between the track's cap and the arrow has to clear the cap's own height or the thumb's rounded
-- corner visually pokes out past the arrow at full scroll. NOT just the 6px buffer alone.
local CB_ARROW_GAP = CB_CAP_H + 6
local function cbReskinArrow(button, normalAtlas, overAtlas, downAtlas, bar, anchor)
  if not button then return end
  local n = button:GetNormalTexture()
  local p = button:GetPushedTexture()
  local d = button:GetDisabledTexture()
  local h = button:GetHighlightTexture()
  if n then setAtlas(n, normalAtlas, false) end
  if p then setAtlas(p, downAtlas,   false) end
  if d then setAtlas(d, normalAtlas, false); d:SetDesaturated(true) end
  if h then setAtlas(h, overAtlas, false); h:SetBlendMode("ADD") end
  button:SetSize(CB_ARROW_W, CB_ARROW_H)
  button:ClearAllPoints()
  if anchor == "TOP" then
    button:SetPoint("BOTTOM", bar, "TOP", 0, CB_ARROW_GAP)
  else
    button:SetPoint("TOP", bar, "BOTTOM", 0, -CB_ARROW_GAP)
  end
  button:EnableMouse(true)
  button:Show()
end

function NE.scrollbar.BuildCustom(scrollFrame, opts)
  if not scrollFrame then return end
  if scrollFrame._neCustomBar then return scrollFrame._neCustomBar end

  local name = scrollFrame.GetName and scrollFrame:GetName()
  -- Locate the FauxScrollFrame's hidden slider + arrow buttons.
  local slider = (name and _G[name .. "ScrollBar"]) or scrollFrame.ScrollBar or scrollFrame.scrollBar
  if not slider then return end
  local sName = slider.GetName and slider:GetName()
  local upBtn   = (sName and _G[sName .. "ScrollUpButton"])
  local downBtn = (sName and _G[sName .. "ScrollDownButton"])

  opts = opts or {}
  local xInset = opts.x ~= nil and -opts.x or CB_X_INSET
  -- The reference addon's minimal scrollbar always has arrow buttons -- that's now the DEFAULT
  -- for every list using this widget, not a per-call opt-in. The vertical clearance the arrows
  -- need is reserved by insetting OUR OWN bar within scrollFrame's existing bounds (below), so
  -- this doesn't require auditing every caller's layout. Pass arrows = false to opt a specific
  -- list out if it genuinely needs the old bare-track look. (Whether the TRACK stays visible with
  -- nothing to scroll, vs. hiding entirely, is the separate opts.alwaysShow -- opt-in, see below.)
  local wantArrows = opts.arrows ~= false

  -- upBtn/downBtn are children of the STOCK SLIDER in FauxScrollFrameTemplate's own hierarchy --
  -- if we want to keep showing them (wantArrows) while hiding the slider itself (its track+thumb
  -- art we never want), they have to be reparented OFF the slider first. A hidden parent hides its
  -- children regardless of the child's own Show()/Hide() state, so leaving them parented to the
  -- now-hidden slider would make them invisible no matter what we do below.
  if wantArrows then
    local newParent = scrollFrame:GetParent() or scrollFrame
    if upBtn then upBtn:SetParent(newParent) end
    if downBtn then downBtn:SetParent(newParent) end

    -- ...but reparenting BREAKS their click handler, so we have to replace it. FauxScrollFrameTemplate
    -- instantiates the arrows with an inline OnClick (UIPanelTemplates.xml) hardcoded to its own
    -- parent, which it assumes IS the slider:
    --     local parent = self:GetParent();
    --     parent:SetValue(parent:GetValue() - (parent:GetHeight() / 2));
    -- Once the button hangs off the scroll frame's parent instead, GetValue is nil there and every
    -- arrow click threw "attempt to call method 'GetValue' (a nil value)" (reported against the
    -- character Skills list, but it affected every list built by this function). Drive the slider we
    -- already captured above instead of whatever the button happens to be parented to.
    --
    -- Step by ONE row rather than stock's half-a-bar-height: FauxScrollFrame_Update calls
    -- slider:SetValueStep(valueStep) with the caller's row height, so GetValueStep() is exactly one
    -- row -- which also matches what the callers' own OnMouseWheel handlers scroll by.
    local function arrowClick(dir)
      return function()
        if not (slider and slider.GetValue) then return end
        local mn, mx = slider:GetMinMaxValues()
        local step = slider.GetValueStep and slider:GetValueStep() or nil
        if not step or step <= 0 then step = (slider:GetHeight() or 32) / 2 end
        local v = slider:GetValue() + dir * step
        if v < mn then v = mn elseif v > mx then v = mx end
        slider:SetValue(v)
        if PlaySound then pcall(PlaySound, "UChatScrollButton") end
      end
    end
    if upBtn   then upBtn:SetScript("OnClick",   arrowClick(-1)) end
    if downBtn then downBtn:SetScript("OnClick", arrowClick(1))  end
  end

  -- Hide the stock scrollbar (do NOT remove — Faux still drives the slider value). If arrows are
  -- wanted, leave upBtn/downBtn alone here -- they're reskinned+repositioned below instead.
  -- Re-hide the slider on any attempt to show it.
  local function hideStock()
    if slider then slider:Hide() end
    if not wantArrows then
      if upBtn then upBtn:Hide() end
      if downBtn then downBtn:Hide() end
    end
  end
  hideStock()
  if slider.HookScript then slider:HookScript("OnShow", function(s) s:Hide() end) end
  if not wantArrows then
    if upBtn and upBtn.HookScript then upBtn:HookScript("OnShow", function(s) s:Hide() end) end
    if downBtn and downBtn.HookScript then downBtn:HookScript("OnShow", function(s) s:Hide() end) end
  end

  -- ---- the custom bar frame (= the track) ----------------------------------
  -- Parented to the scrollFrame's OWN PARENT, not the scrollFrame itself -- a ScrollFrame widget
  -- clips ALL its children to its own rectangle (not just a designated scroll child), and this
  -- bar is deliberately anchored OUTSIDE the scrollFrame's bounds (to its right). Parented to the
  -- scrollFrame directly, it would render fully clipped/invisible regardless of Show()/Hide()
  -- state -- anchors still resolve fine against a non-parent frame, so this changes nothing else.
  local bar = CreateFrame("Frame", nil, scrollFrame:GetParent() or scrollFrame)
  bar:SetWidth(CB_WIDTH)
  -- Anchor to the right edge of the scroll pane, inset a little. Full height normally; when arrows
  -- are wanted, inset top/bottom by the same amount the arrow buttons occupy (CB_ARROW_H +
  -- CB_ARROW_GAP) so the track+arrows stay entirely within scrollFrame's own bounds instead of
  -- needing every caller to carve out extra vertical clearance in its own layout.
  local barYInset = wantArrows and (CB_ARROW_H + CB_ARROW_GAP) or 0
  bar:ClearAllPoints()
  bar:SetPoint("TOPLEFT",     scrollFrame, "TOPRIGHT", xInset, -barYInset)
  bar:SetPoint("BOTTOMLEFT",  scrollFrame, "BOTTOMRIGHT", xInset, barYInset)
  bar:SetFrameStrata("HIGH")
  bar:SetFrameLevel((scrollFrame:GetFrameLevel() or 1) + 6)
  bar._slider = slider
  -- Opt-in, NOT a default -- always-visible-track (even with nothing to scroll) is an Auction
  -- House convention (Browse/Auctions tabs pass this explicitly); other panels keep the normal
  -- "hide entirely when content fits" behavior unless they ask for otherwise.
  bar._alwaysShow = opts.alwaysShow and true or false

  if wantArrows then
    cbReskinArrow(upBtn,   "minimal-scrollbar-arrow-top",    "minimal-scrollbar-arrow-top-over",    "minimal-scrollbar-arrow-top-down",    bar, "TOP")
    cbReskinArrow(downBtn, "minimal-scrollbar-arrow-bottom", "minimal-scrollbar-arrow-bottom-over", "minimal-scrollbar-arrow-bottom-down", bar, "BOTTOM")
    if upBtn then
      upBtn:SetFrameStrata(bar:GetFrameStrata())
      upBtn:SetFrameLevel(bar:GetFrameLevel() + 1)
    end
    if downBtn then
      downBtn:SetFrameStrata(bar:GetFrameStrata())
      downBtn:SetFrameLevel(bar:GetFrameLevel() + 1)
    end
    bar._upBtn, bar._downBtn = upBtn, downBtn

    -- BUG FIX (owner report 2026-07-17, persisted through two prior fix attempts: "bars still
    -- don't hide"). The stock slider gets a PERMANENT re-hide guard above (line ~466) regardless
    -- of wantArrows, but upBtn/downBtn only got one when wantArrows was FALSE — every list in this
    -- addon wants arrows, so neither button ever got that safety net. They're reparented off the
    -- slider (onto scrollFrame's parent) specifically so they can survive the slider's own Hide(),
    -- which means something in the stock FauxScrollFrame/UIPanelScrollBar machinery re-Show()-ing
    -- them independently (e.g. on hover, or Blizzard's own internal update pass) was never caught
    -- by cbSync afterward — explaining the exact asymmetry reported: showing worked (our own
    -- cbSync Show() call), hiding didn't stick (something else's Show() call happened after ours).
    -- Range-aware, not a blanket re-hide like the slider's: re-checks the CURRENT range on every
    -- Show() and only hides if there's genuinely nothing to scroll.
    local function guardArrow(btn)
      if not (btn and btn.HookScript) then return end
      btn:HookScript("OnShow", function(self)
        local slider = bar._slider
        if not slider then return end
        local minV, maxV = slider:GetMinMaxValues()
        minV = minV or 0; maxV = maxV or 0
        if (maxV - minV) <= 0 and not bar._alwaysShow then self:Hide() end
      end)
    end
    guardArrow(upBtn)
    guardArrow(downBtn)
  end

  -- track: top cap + bottom cap + tiled middle
  local tTop = bar:CreateTexture(nil, "BACKGROUND")
  setAtlas(tTop, "minimal-scrollbar-track-top", true)
  tTop:SetWidth(CB_WIDTH); tTop:SetHeight(CB_CAP_H)
  tTop:SetPoint("TOP", bar, "TOP", 0, 0)

  local tBot = bar:CreateTexture(nil, "BACKGROUND")
  setAtlas(tBot, "minimal-scrollbar-track-bottom", true)
  tBot:SetWidth(CB_WIDTH); tBot:SetHeight(CB_CAP_H)
  tBot:SetPoint("BOTTOM", bar, "BOTTOM", 0, 0)

  local tMid = bar:CreateTexture(nil, "BACKGROUND")
  setAtlas(tMid, "!minimal-scrollbar-track-middle", false)
  tMid:SetPoint("TOPLEFT",     tTop, "BOTTOMLEFT",  0, 0)
  tMid:SetPoint("BOTTOMRIGHT", tBot, "TOPRIGHT",    0, 0)

  -- ---- the thumb -----------------------------------------------------------
  local thumb = CreateFrame("Frame", nil, bar)
  thumb:SetWidth(CB_WIDTH)
  thumb:SetHeight(CB_MIN_THUMB)
  thumb:SetPoint("TOP", bar, "TOP", 0, 0)
  thumb:SetFrameLevel((bar:GetFrameLevel() or 1) + 2)
  thumb:EnableMouse(true)
  thumb._bar = bar
  bar._thumb = thumb

  local thMid = thumb:CreateTexture(nil, "ARTWORK")
  setAtlas(thMid, "minimal-scrollbar-small-thumb-middle", false)
  thMid:SetPoint("TOPLEFT",     thumb, "TOPLEFT",     0,  -CB_CAP_H)
  thMid:SetPoint("BOTTOMRIGHT", thumb, "BOTTOMRIGHT", 0,   CB_CAP_H)
  bar._thumbMid = thMid

  local thTop = thumb:CreateTexture(nil, "OVERLAY")
  setAtlas(thTop, "minimal-scrollbar-small-thumb-top", true)
  thTop:SetWidth(CB_WIDTH); thTop:SetHeight(CB_CAP_H)
  thTop:SetPoint("TOP", thumb, "TOP", 0, 0)
  bar._thumbTop = thTop

  local thBot = thumb:CreateTexture(nil, "OVERLAY")
  setAtlas(thBot, "minimal-scrollbar-small-thumb-bottom", true)
  thBot:SetWidth(CB_WIDTH); thBot:SetHeight(CB_CAP_H)
  thBot:SetPoint("BOTTOM", thumb, "BOTTOM", 0, 0)
  bar._thumbBot = thBot

  -- drag: while held, follow the cursor (clamped) and write the slider value.
  thumb:SetScript("OnMouseDown", function(self)
    cbSetThumbState(bar, "-down")
    self._dragging = true
    self:SetScript("OnUpdate", function(s)
      -- Follow the cursor: place the thumb under the mouse Y, clamped to track.
      local trackTop = bar:GetTop()
      local trackH   = bar:GetHeight() or 0
      local thumbH   = s:GetHeight() or 0
      if not trackTop then return end
      local _, cursorY = GetCursorPosition()
      local scale = bar:GetEffectiveScale() or 1
      cursorY = cursorY / scale
      -- desired thumb-top so the grab point stays under cursor (center grab is fine)
      local desiredTop = cursorY + (thumbH / 2)
      local maxTop = trackTop
      local minTop = trackTop - (trackH - thumbH)
      if desiredTop > maxTop then desiredTop = maxTop end
      if desiredTop < minTop then desiredTop = minTop end
      s:ClearAllPoints()
      s:SetPoint("TOP", bar, "TOP", 0, -(maxTop - desiredTop))
      cbOnThumbUpdate(s)
    end)
  end)
  thumb:SetScript("OnMouseUp", function(self)
    self._dragging = false
    self:SetScript("OnUpdate", nil)
    cbSetThumbState(bar, "")
    cbSync(bar)              -- snap the thumb to the canonical slider position
  end)
  thumb:SetScript("OnEnter", function() if not thumb._dragging then cbSetThumbState(bar, "-over") end end)
  thumb:SetScript("OnLeave", function() if not thumb._dragging then cbSetThumbState(bar, "") end end)

  -- keep the wheel working (FauxScrollFrames usually wire it; ensure enabled).
  scrollFrame:EnableMouseWheel(true)

  -- ---- syncing -------------------------------------------------------------
  local function sync() cbSync(bar) end
  scrollFrame:HookScript("OnVerticalScroll",     sync)
  scrollFrame:HookScript("OnScrollRangeChanged", sync)
  -- The slider value is set by FauxScrollFrame_Update (which the row refreshers
  -- call) and by the wheel; mirror those via the slider's own value change.
  if slider.HookScript then slider:HookScript("OnValueChanged", sync) end

  -- Throttled OnUpdate fallback so the thumb tracks (and the bar re-appears when
  -- content grows) even if a refresher updates the slider without firing a hook
  -- we caught. DOWNPORT: driven off the scrollFrame (always shown while the panel
  -- is open) NOT the bar — a hidden frame fires no OnUpdate, so a bar that hid
  -- itself when content fit could never re-show itself. (cheap; ~10/sec)
  local accum = 0
  scrollFrame:HookScript("OnUpdate", function(self, elapsed)
    accum = accum + (elapsed or 0)
    if accum < 0.1 then return end
    accum = 0
    if not thumb._dragging then cbSync(bar) end
  end)

  scrollFrame._neCustomBar = bar
  -- Sync once immediately (bar:GetHeight() etc. may not be resolved on this very first pass
  -- through a long anchor chain -- e.g. this bar's own scrollFrame anchors off a panel that
  -- anchors off a tab whose width comes from GetWidth() on its own text) AND once more deferred
  -- a frame later once layout has fully settled. Without the deferred pass an alwaysShow bar can
  -- get stuck invisible if this first call sees a zero-height track.
  sync()
  if C_Timer and C_Timer.After then C_Timer.After(0, sync) end
  return bar
end

-- ============================================================================
-- NE.scrollbar.CenterIfNoBar(scroll, needsBar) — the secondary-tab faux scroll frames are inset 10
-- on the left and 24 on the right (the scrollbar gutter). When the list fits and NO scrollbar shows,
-- that asymmetry leaves dead space on the right and the content reads left-biased. Balance the L/R
-- insets to their average (17) so the content is centered; restore the gutter when a bar is needed.
-- Same total width either way (10+24 == 17+17), so the rows keep their width and just shift. Host =
-- scroll:GetParent(). NOTE: assumes the shared 10/-12 / -24/+10 inset values the secondary panes use.
-- ============================================================================
function NE.scrollbar.CenterIfNoBar(scroll, needsBar)
  if not scroll then return end
  local host = scroll:GetParent()
  if not host then return end
  local l, r = 10, 24
  if not needsBar then local a = (l + r) / 2; l, r = a, a end
  scroll:ClearAllPoints()
  scroll:SetPoint("TOPLEFT", host, "TOPLEFT", l, -12)
  scroll:SetPoint("BOTTOMRIGHT", host, "BOTTOMRIGHT", -r, 10)
end

-- ============================================================================
-- NE.scrollbar.BuildCustomPixel — DOWNPORT/REPORT: a PIXEL-SCROLL variant of BuildCustom for a
-- plain ScrollFrame (NOT a FauxScrollFrame). The faithful-NewEra stats sidebar builds ALL rows at
-- cumulative Y in one tall content frame and scrolls by PIXELS (NewEra used a retail WowScrollBox,
-- absent on 3.3.5a). This widget OWNS its own track+thumb and drives the ScrollFrame's
-- SetVerticalScroll directly, reading GetVerticalScrollRange()/GetVerticalScroll() for the thumb.
--
-- Reuses the SAME track/thumb art + drag feel as BuildCustom; only the value source/sink differ:
--   * range  = scrollFrame:GetVerticalScrollRange()
--   * value  = scrollFrame:GetVerticalScroll()
--   * set    = scrollFrame:SetVerticalScroll(v)
-- Idempotent via scrollFrame._neCustomBar.
-- ----------------------------------------------------------------------------

-- Read the ScrollFrame's pixel scroll range/value, size+place the thumb, toggle the bar.
local function cbpSync(bar)
  local sf = bar._scrollFrame
  if not sf then return end
  local range = (sf.GetVerticalScrollRange and sf:GetVerticalScrollRange()) or 0
  if range <= 0 then
    bar:Hide()
    -- The arrows are reparented OFF the stock slider (see BuildCustomPixel) so they can outlive its
    -- Hide(), which also makes them SIBLINGS of bar rather than children — hiding bar alone leaves
    -- them floating over nothing. Same trap, same fix as cbSync's.
    if bar._upBtn then bar._upBtn:Hide() end
    if bar._downBtn then bar._downBtn:Hide() end
    return
  end
  bar:Show()
  if bar._upBtn then bar._upBtn:Show() end
  if bar._downBtn then bar._downBtn:Show() end

  local trackH = bar:GetHeight() or 0
  if trackH <= 0 then return end

  -- Thumb height ~ proportion of visible:total. visible = trackH-ish; total = visible + range.
  local visible = (sf.GetHeight and sf:GetHeight()) or trackH
  local total   = visible + range
  local thumbH  = trackH * (visible / total)
  if thumbH < CB_MIN_THUMB then thumbH = CB_MIN_THUMB end
  if thumbH > trackH then thumbH = trackH end
  bar._thumb:SetHeight(thumbH)

  local val  = (sf.GetVerticalScroll and sf:GetVerticalScroll()) or 0
  local frac = val / range
  if frac < 0 then frac = 0 elseif frac > 1 then frac = 1 end
  local travel = trackH - thumbH
  bar._thumb:ClearAllPoints()
  bar._thumb:SetPoint("TOP", bar, "TOP", 0, -(frac * travel))
end

-- Drag handler: convert the thumb's top Y into a pixel scroll value and write it back.
local function cbpOnThumbUpdate(thumb)
  local bar = thumb._bar
  local sf = bar and bar._scrollFrame
  if not sf then return end
  local range = (sf.GetVerticalScrollRange and sf:GetVerticalScrollRange()) or 0
  if range <= 0 then return end

  local trackTop = bar:GetTop()
  local thumbTop = thumb:GetTop()
  local trackH   = bar:GetHeight() or 0
  local thumbH   = thumb:GetHeight() or 0
  local travel   = trackH - thumbH
  if not (trackTop and thumbTop) or travel <= 0 then return end

  local frac = (trackTop - thumbTop) / travel
  if frac < 0 then frac = 0 elseif frac > 1 then frac = 1 end
  sf:SetVerticalScroll(frac * range)
end

function NE.scrollbar.BuildCustomPixel(scrollFrame, opts)
  if not scrollFrame then return end
  if scrollFrame._neCustomBar then return scrollFrame._neCustomBar end

  opts = opts or {}
  local xInset = opts.x ~= nil and -opts.x or CB_X_INSET

  -- ---- the STOCK bar, if this ScrollFrame came from a template -------------
  -- BuildCustomPixel was written for a BARE CreateFrame("ScrollFrame") (the character stats
  -- sidebar), which has no stock scrollbar to get out of the way of — so it never dealt with one.
  -- A UIPanelScrollFrameTemplate ScrollFrame does have one, complete with arrow buttons, and
  -- without this the player gets BOTH bars side by side. BuildCustom has always done this for the
  -- Faux case; this is the same handling for the pixel case.
  --
  -- Resolved by GLOBAL NAME first: 3.3.5a's UIPanelScrollFrameTemplate declares its slider as
  -- `$parentScrollBar` with no parentKey, so `scrollFrame.ScrollBar` is nil on this client and any
  -- `if scrollFrame.ScrollBar` guard silently finds nothing. That is the same shape as the
  -- PortraitFrameTemplate `$parentBg` trap, and it is why NE.scrollbar.Reskin — which checks only
  -- the parentKey — quietly did nothing at all on a frame like this.
  local sfName = scrollFrame.GetName and scrollFrame:GetName()
  local stock  = (sfName and _G[sfName .. "ScrollBar"]) or scrollFrame.ScrollBar or scrollFrame.scrollBar
  local stockName = stock and stock.GetName and stock:GetName()
  local upBtn   = stock and ((stockName and _G[stockName .. "ScrollUpButton"])   or stock.ScrollUpButton)
  local downBtn = stock and ((stockName and _G[stockName .. "ScrollDownButton"]) or stock.ScrollDownButton)
  local wantArrows = opts.arrows ~= false and upBtn and downBtn

  if stock then
    -- Hidden, not removed: the template's own OnScrollRangeChanged still writes to it, and reading
    -- it back is harmless. The re-hide guard is what makes it stay gone.
    stock:Hide()
    if stock.HookScript then stock:HookScript("OnShow", function(s) s:Hide() end) end
  end
  if wantArrows then
    -- The arrows are children of the stock slider, and a hidden parent hides its children whatever
    -- their own state. Reparent them so they survive the Hide above.
    local newParent = scrollFrame:GetParent() or scrollFrame
    upBtn:SetParent(newParent)
    downBtn:SetParent(newParent)
  elseif stock then
    if upBtn then upBtn:Hide() end
    if downBtn then downBtn:Hide() end
  end

  -- ---- the custom bar frame (= the track) ----------------------------------
  -- Parented to the scrollFrame's own parent, not the scrollFrame itself -- see the matching
  -- note in BuildCustom above (a ScrollFrame clips all its children to its own rect, and this bar
  -- is deliberately anchored outside it).
  local bar = CreateFrame("Frame", nil, scrollFrame:GetParent() or scrollFrame)
  bar:SetWidth(CB_WIDTH)
  -- With arrows, inset the track by exactly what they occupy so track + arrows together still fit
  -- the scrollFrame's own bounds — no caller has to carve out extra room. Same arithmetic as
  -- BuildCustom's barYInset.
  local barYInset = wantArrows and (CB_ARROW_H + CB_ARROW_GAP) or 0
  bar:ClearAllPoints()
  bar:SetPoint("TOPLEFT",    scrollFrame, "TOPRIGHT",    xInset, -barYInset)
  bar:SetPoint("BOTTOMLEFT", scrollFrame, "BOTTOMRIGHT", xInset,  barYInset)
  bar:SetFrameStrata("HIGH")
  bar:SetFrameLevel((scrollFrame:GetFrameLevel() or 1) + 6)
  bar._scrollFrame = scrollFrame

  if wantArrows then
    cbReskinArrow(upBtn,   "minimal-scrollbar-arrow-top",    "minimal-scrollbar-arrow-top-over",    "minimal-scrollbar-arrow-top-down",    bar, "TOP")
    cbReskinArrow(downBtn, "minimal-scrollbar-arrow-bottom", "minimal-scrollbar-arrow-bottom-over", "minimal-scrollbar-arrow-bottom-down", bar, "BOTTOM")
    for _, b in ipairs({ upBtn, downBtn }) do
      b:SetFrameStrata(bar:GetFrameStrata())
      b:SetFrameLevel(bar:GetFrameLevel() + 1)
    end
    bar._upBtn, bar._downBtn = upBtn, downBtn

    -- Reparenting breaks the template's inline OnClick, which drives `self:GetParent()` and assumes
    -- that is the slider. Once the button hangs off the panel instead, GetValue is nil there and
    -- every click errors. Scroll the frame directly — the same sink the wheel and the thumb use.
    local function arrowClick(dir)
      return function()
        local range = (scrollFrame.GetVerticalScrollRange and scrollFrame:GetVerticalScrollRange()) or 0
        if range <= 0 then return end
        local cur  = (scrollFrame.GetVerticalScroll and scrollFrame:GetVerticalScroll()) or 0
        local step = opts.wheelStep or 30
        local v = cur + dir * step
        if v < 0 then v = 0 elseif v > range then v = range end
        scrollFrame:SetVerticalScroll(v)
        if PlaySound then pcall(PlaySound, "UChatScrollButton") end
      end
    end
    upBtn:SetScript("OnClick",   arrowClick(-1))
    downBtn:SetScript("OnClick", arrowClick(1))

    -- Range-aware re-hide, not a blanket one: something in the stock machinery can Show() these
    -- back independently of cbpSync, which is the asymmetry BuildCustom hit twice (shown worked,
    -- hidden did not stick).
    for _, b in ipairs({ upBtn, downBtn }) do
      if b.HookScript then
        b:HookScript("OnShow", function(self)
          local range = (scrollFrame.GetVerticalScrollRange and scrollFrame:GetVerticalScrollRange()) or 0
          if range <= 0 then self:Hide() end
        end)
      end
    end
  end

  -- track: top cap + bottom cap + tiled middle
  local tTop = bar:CreateTexture(nil, "BACKGROUND")
  setAtlas(tTop, "minimal-scrollbar-track-top", true)
  tTop:SetWidth(CB_WIDTH); tTop:SetHeight(CB_CAP_H)
  tTop:SetPoint("TOP", bar, "TOP", 0, 0)

  local tBot = bar:CreateTexture(nil, "BACKGROUND")
  setAtlas(tBot, "minimal-scrollbar-track-bottom", true)
  tBot:SetWidth(CB_WIDTH); tBot:SetHeight(CB_CAP_H)
  tBot:SetPoint("BOTTOM", bar, "BOTTOM", 0, 0)

  local tMid = bar:CreateTexture(nil, "BACKGROUND")
  setAtlas(tMid, "!minimal-scrollbar-track-middle", false)
  tMid:SetPoint("TOPLEFT",     tTop, "BOTTOMLEFT",  0, 0)
  tMid:SetPoint("BOTTOMRIGHT", tBot, "TOPRIGHT",    0, 0)

  -- ---- the thumb -----------------------------------------------------------
  local thumb = CreateFrame("Frame", nil, bar)
  thumb:SetWidth(CB_WIDTH)
  thumb:SetHeight(CB_MIN_THUMB)
  thumb:SetPoint("TOP", bar, "TOP", 0, 0)
  thumb:SetFrameLevel((bar:GetFrameLevel() or 1) + 2)
  thumb:EnableMouse(true)
  thumb._bar = bar
  bar._thumb = thumb

  local thMid = thumb:CreateTexture(nil, "ARTWORK")
  setAtlas(thMid, "minimal-scrollbar-small-thumb-middle", false)
  thMid:SetPoint("TOPLEFT",     thumb, "TOPLEFT",     0,  -CB_CAP_H)
  thMid:SetPoint("BOTTOMRIGHT", thumb, "BOTTOMRIGHT", 0,   CB_CAP_H)
  bar._thumbMid = thMid

  local thTop = thumb:CreateTexture(nil, "OVERLAY")
  setAtlas(thTop, "minimal-scrollbar-small-thumb-top", true)
  thTop:SetWidth(CB_WIDTH); thTop:SetHeight(CB_CAP_H)
  thTop:SetPoint("TOP", thumb, "TOP", 0, 0)
  bar._thumbTop = thTop

  local thBot = thumb:CreateTexture(nil, "OVERLAY")
  setAtlas(thBot, "minimal-scrollbar-small-thumb-bottom", true)
  thBot:SetWidth(CB_WIDTH); thBot:SetHeight(CB_CAP_H)
  thBot:SetPoint("BOTTOM", thumb, "BOTTOM", 0, 0)
  bar._thumbBot = thBot

  -- drag: while held, follow the cursor (clamped) and write the scroll value.
  thumb:SetScript("OnMouseDown", function(self)
    cbSetThumbState(bar, "-down")
    self._dragging = true
    self:SetScript("OnUpdate", function(s)
      local trackTop = bar:GetTop()
      local trackH   = bar:GetHeight() or 0
      local thumbH   = s:GetHeight() or 0
      if not trackTop then return end
      local _, cursorY = GetCursorPosition()
      local scale = bar:GetEffectiveScale() or 1
      cursorY = cursorY / scale
      local desiredTop = cursorY + (thumbH / 2)
      local maxTop = trackTop
      local minTop = trackTop - (trackH - thumbH)
      if desiredTop > maxTop then desiredTop = maxTop end
      if desiredTop < minTop then desiredTop = minTop end
      s:ClearAllPoints()
      s:SetPoint("TOP", bar, "TOP", 0, -(maxTop - desiredTop))
      cbpOnThumbUpdate(s)
    end)
  end)
  thumb:SetScript("OnMouseUp", function(self)
    self._dragging = false
    self:SetScript("OnUpdate", nil)
    cbSetThumbState(bar, "")
    cbpSync(bar)
  end)
  thumb:SetScript("OnEnter", function() if not thumb._dragging then cbSetThumbState(bar, "-over") end end)
  thumb:SetScript("OnLeave", function() if not thumb._dragging then cbSetThumbState(bar, "") end end)

  -- mouse wheel scrolls by pixels.
  scrollFrame:EnableMouseWheel(true)
  scrollFrame:HookScript("OnMouseWheel", function(self, delta)
    local range = (self.GetVerticalScrollRange and self:GetVerticalScrollRange()) or 0
    if range <= 0 then return end
    local cur = (self.GetVerticalScroll and self:GetVerticalScroll()) or 0
    local step = opts.wheelStep or 30
    local nv = cur - (delta * step)
    if nv < 0 then nv = 0 elseif nv > range then nv = range end
    self:SetVerticalScroll(nv)
  end)

  -- ---- syncing -------------------------------------------------------------
  local function sync() cbpSync(bar) end
  scrollFrame:HookScript("OnVerticalScroll",     sync)
  scrollFrame:HookScript("OnScrollRangeChanged", sync)

  -- Throttled OnUpdate fallback so the thumb tracks (and the bar re-appears when content grows).
  local accum = 0
  scrollFrame:HookScript("OnUpdate", function(self, elapsed)
    accum = accum + (elapsed or 0)
    if accum < 0.1 then return end
    accum = 0
    if not thumb._dragging then cbpSync(bar) end
  end)

  scrollFrame._neCustomBar = bar
  if C_Timer and C_Timer.After then C_Timer.After(0, sync) else sync() end
  return bar
end

-- ============================================================================
-- NE.scrollbar.BuildCustomMessageFrame — a LINE-SCROLL variant of BuildCustomPixel for a
-- ScrollingMessageFrame (e.g. a chat log). Unlike a ScrollFrame, a ScrollingMessageFrame has no
-- GetVerticalScrollRange/GetVerticalScroll; scroll position is line-based instead:
--   * GetScrollOffset()   -- 0 = scrolled to the BOTTOM (newest message); larger = further up
--                             toward older history.
--   * SetScrollOffset(n)  -- the widget clamps this itself, so an approximate max is fine here.
--   * GetNumMessages() / GetNumLinesDisplayed() -- used only to size/position the thumb; not
--                             authoritative, just enough for a faithful-looking bar.
-- Reuses the same track/thumb art + drag feel as BuildCustom/BuildCustomPixel. frac is inverted
-- relative to BuildCustomPixel's cbpSync: offset 0 (newest, bottom) puts the thumb at the BOTTOM
-- of the track, matching how a normal chat window's scrollbar looks when caught up on chat.
-- No wheel handler is installed here — callers with an existing OnMouseWheel (e.g. guild chat)
-- keep driving ScrollUp/ScrollDown themselves; this widget only mirrors the resulting position.
-- Idempotent via scrollFrame._neCustomBar.
-- ----------------------------------------------------------------------------

-- BUG FIX (owner report: "no scrollbar showing" -- not just a hidden thumb, the whole bar). Root
-- cause: this client's ScrollingMessageFrame doesn't expose GetNumMessages()/GetNumLinesDisplayed()
-- (retail/later-client additions), so both guarded calls silently fell through to 0 with no error,
-- maxOff computed to 0, and cbmSync's bar:Hide() below fired permanently. Neither total nor shown
-- can be trusted from the widget itself on 3.3.5a:
--   * total  -- prefer msg._neTotalLines, a caller-maintained counter (Chat.lua increments it on
--              every AddMessage and zeroes it on Clear) over the possibly-absent GetNumMessages().
--   * shown  -- prefer GetNumLinesDisplayed() if it DOES exist (harmless to keep the fast path for
--              a future/other client where it's present), else estimate visible-line capacity from
--              frame height / font line height -- GetFont() and GetHeight() are plain FontInstance/
--              Region APIs, not ScrollingMessageFrame-specific, so those are safe to rely on here.
local function cbmMaxOffset(msg)
  local total = msg._neTotalLines
  if not total then
    total = (msg.GetNumMessages and msg:GetNumMessages()) or 0
  end

  local shown = msg.GetNumLinesDisplayed and msg:GetNumLinesDisplayed()
  if not shown or shown <= 0 then
    local fontHeight
    if msg.GetFont then
      local _, h = msg:GetFont()
      fontHeight = h
    end
    fontHeight = fontHeight or 14
    local h = (msg.GetHeight and msg:GetHeight()) or 0
    shown = h > 0 and math.max(1, math.floor(h / (fontHeight + 2))) or 1
  end

  local maxOff = total - shown
  if maxOff < 0 then maxOff = 0 end
  return maxOff, total, shown
end

local function cbmSync(bar)
  local msg = bar._scrollFrame
  if not msg then return end
  local maxOff, total, shown = cbmMaxOffset(msg)
  if maxOff <= 0 then
    bar:Hide()
    if bar._upBtn then bar._upBtn:Hide() end
    if bar._downBtn then bar._downBtn:Hide() end
    return
  end
  bar:Show()
  if bar._upBtn then bar._upBtn:Show() end
  if bar._downBtn then bar._downBtn:Show() end

  local trackH = bar:GetHeight() or 0
  if trackH <= 0 then return end

  local visible = shown > 0 and shown or 1
  local totalLines = total > 0 and total or visible
  local thumbH = trackH * math.min(1, visible / totalLines)
  if thumbH < CB_MIN_THUMB then thumbH = CB_MIN_THUMB end
  if thumbH > trackH then thumbH = trackH end
  bar._thumb:SetHeight(thumbH)

  local offset = (msg.GetScrollOffset and msg:GetScrollOffset()) or 0
  local frac = 1 - (offset / maxOff)   -- offset 0 (newest) -> frac 1 (thumb at bottom)
  if frac < 0 then frac = 0 elseif frac > 1 then frac = 1 end
  local travel = trackH - thumbH
  bar._thumb:ClearAllPoints()
  bar._thumb:SetPoint("TOP", bar, "TOP", 0, -(frac * travel))
end

-- Drag handler: convert the thumb's top Y into a line offset and write it back.
local function cbmOnThumbUpdate(thumb)
  local bar = thumb._bar
  local msg = bar and bar._scrollFrame
  if not msg then return end
  local maxOff = cbmMaxOffset(msg)
  if maxOff <= 0 then return end

  local trackTop = bar:GetTop()
  local thumbTop = thumb:GetTop()
  local trackH   = bar:GetHeight() or 0
  local thumbH   = thumb:GetHeight() or 0
  local travel   = trackH - thumbH
  if not (trackTop and thumbTop) or travel <= 0 then return end

  local frac = (trackTop - thumbTop) / travel   -- 0 at top .. 1 at bottom
  if frac < 0 then frac = 0 elseif frac > 1 then frac = 1 end
  if msg.SetScrollOffset then msg:SetScrollOffset(maxOff * (1 - frac)) end
end

-- ScrollingMessageFrame has no native slider/arrow buttons to reparent+reskin (unlike BuildCustom's
-- FauxScrollFrame case), so these are built entirely from scratch: a plain Frame (not a real Button
-- widget, to sidestep any uncertainty over SetNormalTexture/SetPushedTexture accepting texture
-- objects on this client) with one texture region whose atlas key swaps for hover/press, matching
-- the same manual hover-state approach the thumb already uses (cbSetThumbState).
local function cbmArrowSetState(tex, suffix, normalAtlas, overAtlas, downAtlas)
  if suffix == "-over" then setAtlas(tex, overAtlas, false)
  elseif suffix == "-down" then setAtlas(tex, downAtlas, false)
  else setAtlas(tex, normalAtlas, false) end
end

local function cbmBuildArrow(bar, normalAtlas, overAtlas, downAtlas, anchor, onClick)
  local btn = CreateFrame("Frame", nil, bar)
  btn:SetSize(CB_ARROW_W, CB_ARROW_H)
  btn:ClearAllPoints()
  if anchor == "TOP" then
    btn:SetPoint("BOTTOM", bar, "TOP", 0, CB_ARROW_GAP)
  else
    btn:SetPoint("TOP", bar, "BOTTOM", 0, -CB_ARROW_GAP)
  end
  btn:SetFrameStrata(bar:GetFrameStrata())
  btn:SetFrameLevel(bar:GetFrameLevel() + 2)
  btn:EnableMouse(true)

  local tex = btn:CreateTexture(nil, "ARTWORK")
  tex:SetAllPoints(btn)
  setAtlas(tex, normalAtlas, false)

  btn:SetScript("OnEnter", function() cbmArrowSetState(tex, "-over", normalAtlas, overAtlas, downAtlas) end)
  btn:SetScript("OnLeave", function() cbmArrowSetState(tex, "", normalAtlas, overAtlas, downAtlas) end)
  btn:SetScript("OnMouseDown", function() cbmArrowSetState(tex, "-down", normalAtlas, overAtlas, downAtlas) end)
  btn:SetScript("OnMouseUp", function(self)
    cbmArrowSetState(tex, "-over", normalAtlas, overAtlas, downAtlas)
    onClick()
  end)
  return btn
end

function NE.scrollbar.BuildCustomMessageFrame(scrollFrame, opts)
  if not scrollFrame then return end
  if scrollFrame._neCustomBar then return scrollFrame._neCustomBar end

  opts = opts or {}
  local xInset = opts.x ~= nil and -opts.x or CB_X_INSET
  -- Track is inset top/bottom to leave room for the arrow buttons anchored just outside it (same
  -- CB_ARROW_GAP clearance BuildCustom's arrows use), same default-on convention as BuildCustom.
  local wantArrows = opts.arrows ~= false
  local yInset = wantArrows and (CB_ARROW_H + CB_ARROW_GAP) or 0

  local bar = CreateFrame("Frame", nil, scrollFrame:GetParent() or scrollFrame)
  bar:SetWidth(CB_WIDTH)
  bar:ClearAllPoints()
  bar:SetPoint("TOPLEFT",    scrollFrame, "TOPRIGHT",    xInset, -yInset)
  bar:SetPoint("BOTTOMLEFT", scrollFrame, "BOTTOMRIGHT", xInset,  yInset)
  bar:SetFrameStrata("HIGH")
  bar:SetFrameLevel((scrollFrame:GetFrameLevel() or 1) + 6)
  bar._scrollFrame = scrollFrame

  if wantArrows then
    bar._upBtn = cbmBuildArrow(bar,
      "minimal-scrollbar-arrow-top", "minimal-scrollbar-arrow-top-over", "minimal-scrollbar-arrow-top-down",
      "TOP", function() if scrollFrame.ScrollUp then scrollFrame:ScrollUp() end end)
    bar._downBtn = cbmBuildArrow(bar,
      "minimal-scrollbar-arrow-bottom", "minimal-scrollbar-arrow-bottom-over", "minimal-scrollbar-arrow-bottom-down",
      "BOTTOM", function() if scrollFrame.ScrollDown then scrollFrame:ScrollDown() end end)
  end

  -- track: top cap + bottom cap + tiled middle
  local tTop = bar:CreateTexture(nil, "BACKGROUND")
  setAtlas(tTop, "minimal-scrollbar-track-top", true)
  tTop:SetWidth(CB_WIDTH); tTop:SetHeight(CB_CAP_H)
  tTop:SetPoint("TOP", bar, "TOP", 0, 0)

  local tBot = bar:CreateTexture(nil, "BACKGROUND")
  setAtlas(tBot, "minimal-scrollbar-track-bottom", true)
  tBot:SetWidth(CB_WIDTH); tBot:SetHeight(CB_CAP_H)
  tBot:SetPoint("BOTTOM", bar, "BOTTOM", 0, 0)

  local tMid = bar:CreateTexture(nil, "BACKGROUND")
  setAtlas(tMid, "!minimal-scrollbar-track-middle", false)
  tMid:SetPoint("TOPLEFT",     tTop, "BOTTOMLEFT",  0, 0)
  tMid:SetPoint("BOTTOMRIGHT", tBot, "TOPRIGHT",    0, 0)

  -- ---- the thumb -----------------------------------------------------------
  local thumb = CreateFrame("Frame", nil, bar)
  thumb:SetWidth(CB_WIDTH)
  thumb:SetHeight(CB_MIN_THUMB)
  thumb:SetPoint("TOP", bar, "TOP", 0, 0)
  thumb:SetFrameLevel((bar:GetFrameLevel() or 1) + 2)
  thumb:EnableMouse(true)
  thumb._bar = bar
  bar._thumb = thumb

  local thMid = thumb:CreateTexture(nil, "ARTWORK")
  setAtlas(thMid, "minimal-scrollbar-small-thumb-middle", false)
  thMid:SetPoint("TOPLEFT",     thumb, "TOPLEFT",     0,  -CB_CAP_H)
  thMid:SetPoint("BOTTOMRIGHT", thumb, "BOTTOMRIGHT", 0,   CB_CAP_H)
  bar._thumbMid = thMid

  local thTop = thumb:CreateTexture(nil, "OVERLAY")
  setAtlas(thTop, "minimal-scrollbar-small-thumb-top", true)
  thTop:SetWidth(CB_WIDTH); thTop:SetHeight(CB_CAP_H)
  thTop:SetPoint("TOP", thumb, "TOP", 0, 0)
  bar._thumbTop = thTop

  local thBot = thumb:CreateTexture(nil, "OVERLAY")
  setAtlas(thBot, "minimal-scrollbar-small-thumb-bottom", true)
  thBot:SetWidth(CB_WIDTH); thBot:SetHeight(CB_CAP_H)
  thBot:SetPoint("BOTTOM", thumb, "BOTTOM", 0, 0)
  bar._thumbBot = thBot

  -- drag: while held, follow the cursor (clamped) and write the scroll offset.
  thumb:SetScript("OnMouseDown", function(self)
    cbSetThumbState(bar, "-down")
    self._dragging = true
    self:SetScript("OnUpdate", function(s)
      local trackTop = bar:GetTop()
      local trackH   = bar:GetHeight() or 0
      local thumbH   = s:GetHeight() or 0
      if not trackTop then return end
      local _, cursorY = GetCursorPosition()
      local scale = bar:GetEffectiveScale() or 1
      cursorY = cursorY / scale
      local desiredTop = cursorY + (thumbH / 2)
      local maxTop = trackTop
      local minTop = trackTop - (trackH - thumbH)
      if desiredTop > maxTop then desiredTop = maxTop end
      if desiredTop < minTop then desiredTop = minTop end
      s:ClearAllPoints()
      s:SetPoint("TOP", bar, "TOP", 0, -(maxTop - desiredTop))
      cbmOnThumbUpdate(s)
    end)
  end)
  thumb:SetScript("OnMouseUp", function(self)
    self._dragging = false
    self:SetScript("OnUpdate", nil)
    cbSetThumbState(bar, "")
    cbmSync(bar)
  end)
  thumb:SetScript("OnEnter", function() if not thumb._dragging then cbSetThumbState(bar, "-over") end end)
  thumb:SetScript("OnLeave", function() if not thumb._dragging then cbSetThumbState(bar, "") end end)

  -- ---- syncing -------------------------------------------------------------
  -- A ScrollingMessageFrame fires no OnVerticalScroll/OnScrollRangeChanged -- offset and message
  -- count both change via plain method calls (AddMessage, ScrollUp/Down, the caller's own wheel
  -- handler), not events. A throttled OnUpdate poll is the only reliable signal, same approach as
  -- BuildCustom/BuildCustomPixel's fallback.
  local accum = 0
  scrollFrame:HookScript("OnUpdate", function(self, elapsed)
    accum = accum + (elapsed or 0)
    if accum < 0.1 then return end
    accum = 0
    if not thumb._dragging then cbmSync(bar) end
  end)

  scrollFrame._neCustomBar = bar
  cbmSync(bar)
  if C_Timer and C_Timer.After then C_Timer.After(0, function() cbmSync(bar) end) end
  return bar
end

-- ============================================================================
-- NE.scrollbar.SkinSlider — retail's MinimalSliderWithSteppers, for a horizontal Slider.
--
-- NewEra builds every edit-mode slider from MinimalSliderWithSteppersTemplate
-- (EditMode/SettingsPopup.lua:173). The template is retail-only, but the ART is one 32x128 sheet
-- (4567914) carrying the whole widget: both rounded track caps, the ONE-PIXEL run that tiles between
-- them, the little DIAMOND thumb, and both chevron steppers. So the widget is rebuilt here out of its
-- own pieces at their own sizes — no rotation, no substitution.
--
-- (It first shipped built from the vertical scrollbar's pieces turned 90 degrees, because this sheet
-- is absent from the NewEra Art set. The owner supplied it; the workaround came back out.)
--
-- WHAT THIS DELIBERATELY DOES NOT DO IS STATES. The sheet has no hover or pressed variants, because
-- retail's minimal slider does not change art on either — the feedback is the thumb moving. Inventing
-- a tint here would be this addon's idea, not the reference's.
--
-- OptionsSliderTemplate's own groove goes whole: it is a BACKDROP (bgFile UI-SliderBar-Background
-- inside edgeFile UI-SliderBar-Border), not a region that could be re-pointed at other art.
--
-- Idempotent via slider._neMinimalSlider. Fail-safe: SetAtlas returns false when the art is missing,
-- leaving the piece untextured rather than erroring, so a stripped Textures/ still boots.
-- ============================================================================

local SL_TRACK_H = 17   -- native height of the track pieces
local SL_CAP_W   = 11   -- native width of one rounded cap
local SL_THUMB_W = 20   -- the diamond, at its own size
local SL_THUMB_H = 19

function NE.scrollbar.SkinSlider(slider)
  if not slider then return end
  if slider._neMinimalSlider then return slider._neMinimalSlider end

  if slider.SetBackdrop then pcall(slider.SetBackdrop, slider, nil) end
  -- Sized to the DIAMOND, not the track: the thumb is two pixels taller than the bar it rides, which
  -- is what makes it read as a knob rather than as part of the groove.
  slider:SetHeight(SL_THUMB_H)

  local d = {}

  d.Left = slider:CreateTexture(nil, "BACKGROUND")
  NE.tex.SetAtlas(d.Left, "minimal_sliderbar_left", true)
  d.Left:SetPoint("LEFT", slider, "LEFT", 0, 0)

  d.Right = slider:CreateTexture(nil, "BACKGROUND")
  NE.tex.SetAtlas(d.Right, "minimal_sliderbar_right", true)
  d.Right:SetPoint("RIGHT", slider, "RIGHT", 0, 0)

  -- Only the middle stretches, and it is one pixel of source, so it stretches invisibly. The caps keep
  -- their own width or the rounded ends smear — the same rule as the dropdown's textholder.
  d.Middle = slider:CreateTexture(nil, "BACKGROUND")
  NE.tex.SetAtlas(d.Middle, "_minimal_sliderbar_middle", false)
  d.Middle:SetHeight(SL_TRACK_H)
  d.Middle:SetPoint("LEFT",  d.Left,  "RIGHT")
  d.Middle:SetPoint("RIGHT", d.Right, "LEFT")

  local thumb = slider.GetThumbTexture and slider:GetThumbTexture()
  if thumb then
    NE.tex.SetAtlas(thumb, "minimal_sliderbar_button", true)
    thumb:SetSize(SL_THUMB_W, SL_THUMB_H)
    d.Thumb = thumb
  end

  slider._neMinimalSlider = d
  return d
end

-- AttachBottomShadow — DOWNPORT STUB. Needs WowScrollBox callbacks (BaseScrollBoxEvents,
-- RegisterCallback, GetDerivedScrollRange) — retail-only. Returns nil on 3.3.5a.
function NE.scrollbar.AttachBottomShadow(scrollBox, host, opts)
  if not scrollBox then return end
  if not (scrollBox.RegisterCallback and _G.BaseScrollBoxEvents and scrollBox.GetDerivedScrollRange) then
    return   -- DOWNPORT: modern scroll-box infra absent; v1 stub.
  end
  opts = opts or {}
  local holder = CreateFrame("Frame", nil, host or scrollBox)
  holder:SetPoint("BOTTOMLEFT",  scrollBox, "BOTTOMLEFT",  0, 0)
  holder:SetPoint("BOTTOMRIGHT", scrollBox, "BOTTOMRIGHT", 0, 0)
  holder:SetHeight(opts.height or 66)
  holder:SetFrameLevel((scrollBox:GetFrameLevel() or 1) + 5)
  local tex = holder:CreateTexture(nil, "OVERLAY")
  tex:SetAllPoints(holder)
  NE.tex.SetAtlas(tex, "questlog-frame-gradient-bottom", false)
  holder:SetAlpha(0)

  local function update()
    local range = (scrollBox.GetDerivedScrollRange and scrollBox:GetDerivedScrollRange()) or 0
    if range <= 0 then holder:SetAlpha(0); return end
    local pct = (scrollBox.GetScrollPercentage and scrollBox:GetScrollPercentage()) or 0
    local delta = (1 - pct) * range
    holder:SetAlpha(math.max(0, math.min(1, delta / holder:GetHeight())))
  end
  scrollBox:RegisterCallback(BaseScrollBoxEvents.OnScroll, update, holder)
  scrollBox:RegisterCallback(BaseScrollBoxEvents.OnLayout, update, holder)
  if C_Timer and C_Timer.After then C_Timer.After(0, update) end
  holder.Update = update
  return holder
end
