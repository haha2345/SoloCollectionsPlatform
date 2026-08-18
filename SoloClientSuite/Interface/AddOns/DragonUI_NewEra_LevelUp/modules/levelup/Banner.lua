-- DragonUI_NewEra/modules/levelup/Banner.lua — the centre-screen "You have reached Level N" banner.
--
-- Ported from retail's Blizzard_LevelUpDisplay (Cata) choreography, via NewEra's vanilla trim.
--
-- DOWNPORT: driven by one OnUpdate state machine instead of the source's nest of AnimationGroups.
-- The original hangs Scale animations off individual textures and chains phases through OnPlay /
-- OnFinished handlers that reach across frames by global name. Two reasons not to reproduce that
-- here: 3.3.5a Scale animations are the one part of the animation API this addon has no precedent
-- for (core and modules use Alpha only, and even that goes through ClassicAPI's SetFromAlpha
-- polyfill — see modules/cooldownviewer/Alerts.lua:324), and the entry parade has a variable
-- length that a fixed animation graph models badly. A single timeline is also the only reason the
-- constants below can be read, and tuned, in one place.
--
-- THE PROBLEM THIS FIXES. The standalone 3.3.5 addon spends 0.5s in + 1.8s hold + 0.5s out on every
-- unlock, one after another, with no cap. Its own data puts 25 entries on a level-80 Shaman: 70
-- seconds of banner across the middle of the screen, and 122 of its 483 level buckets hold more
-- than five. So the parade is capped here (INLINE_MAX) and long lists go to the grid panel in
-- SideDisplay.lua instead, which shows everything at once.

local NE = DragonUI_NewEra
if not NE or NE.disabled then return end

local M = NE.levelup

-- ── Tunables ────────────────────────────────────────────────────────────────────────────────────
-- Seconds. Retail's beats, named.
-- The dead beat before anything draws. Retail uses 1.5s here, and the port carried that over
-- faithfully — but retail is spending it on the engine's own level-up flourish landing first, and
-- a second and a half of a blank screen after /nelevelup just reads as the addon being broken.
-- 0.4 still lets the sound below start before the art moves. Set it back to 1.5 for retail's exact
-- timing.
local LEAD_IN         = 0.4
local LINE_SWEEP      = 0.5    -- gold lines opening out from the centre
local BG_DELAY        = 0.25   -- black backing waits, then snaps open behind them
local BG_GROW         = 0.15
local LEVEL_FADE_IN   = 0.7
local LEVEL_HOLD      = 2.6
local LEVEL_FADE_OUT  = 0.5
local ENTRY_FADE_IN   = 0.5
local ENTRY_HOLD      = 1.8
local ENTRY_FADE_OUT  = 0.5
local BANNER_FADE_OUT = 1.0

-- Above this many unlocks the one-at-a-time parade stops being a celebration and starts being a
-- wait; the whole list goes to the side grid instead.
local INLINE_MAX      = 4

local LEVEL_TEXT_GAP  = 5      -- between "You have reached" and the level line
local ENTRY_TEXT_GAP  = 1      -- between an unlock's flavour line and its name
local ENTRY_TEXT_X    = 10     -- from the icon's right edge to the text

-- Optical correction for the unlock text against its icon. Negative moves DOWN, positive UP.
-- Zero is geometrically centred (see centreEntryText); this exists because the same empty-descent
-- effect described below can make a correctly-centred block read slightly high.
local ENTRY_TEXT_Y_OFFSET = 0

-- Vertical nudge for everything drawn between the gold lines, in banner pixels. Negative moves
-- DOWN, positive moves UP.
--
-- Geometrically, zero is correct: both lines are anchored to opposite edges of the frame and are the
-- same height, so the midpoint between them IS the frame's centre, and that is what the layout below
-- centres on. It still reads high, for a reason worth writing down — a text block's BOX is not its
-- INK. GetStringHeight includes the font's descent, and "level 76" in Morpheus small caps has no
-- descenders at all, so the bottom of the box is empty space and the visible glyphs float above the
-- box's centre. The entry rows share the correction so the two views stay consistent with each other.
--
-- 0 read as too high and -5 (the old bottom-anchored position) read as slightly low, so this splits
-- them. It is the one number to change if it still looks off.
local CONTENT_Y_OFFSET = -3

-- Geometry, from the source XML.
local BANNER_W, BANNER_H = 418, 72
local LINE_W, LINE_H     = 418, 7
local BG_W, BG_H         = 326, 103
local DEFAULT_POINT      = { point = "TOP", relativePoint = "TOP", x = 0, y = -190 }
M.DEFAULT_POINT = DEFAULT_POINT

-- ── Build ───────────────────────────────────────────────────────────────────────────────────────

local banner

local function buildEntryRegions(parent)
  local e = CreateFrame("Frame", nil, parent)
  -- Height 36, not the source's 44, so the frame's box IS its content box and CENTER means what it
  -- says. The icon spans the full 36 from the top; the name sits on the icon's baseline and the
  -- flavour line above it, so neither reaches past the icon. With 44 the content hugged the top of
  -- the frame and centring it would still have left it 4px high.
  e:SetSize(230, 36)
  e:SetPoint("CENTER", 0, CONTENT_Y_OFFSET)
  e:SetAlpha(0)

  e.icon = e:CreateTexture(nil, "ARTWORK")
  e.icon:SetSize(36, 36)
  e.icon:SetPoint("TOPLEFT", 8, 0)

  e.name = e:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
  e.name:SetJustifyH("LEFT")
  -- Placeholder; centreEntryText re-points this once the strings can be measured.
  e.name:SetPoint("BOTTOMLEFT", e.icon, "BOTTOMRIGHT", ENTRY_TEXT_X, 2)

  e.flavorText = e:CreateFontString(nil, "ARTWORK", "GameFontNormal")
  e.flavorText:SetJustifyH("LEFT")
  e.flavorText:SetPoint("BOTTOMLEFT", e.name, "TOPLEFT", 0, ENTRY_TEXT_GAP)
  e.flavorText:SetTextColor(0, 1, 0)

  -- OVERLAY, above the icon it is stamped onto.
  e.subIcon = e:CreateTexture(nil, "OVERLAY")
  e.subIcon:SetTexture(M.TEX)
  e.subIcon:SetSize(22, 22)
  e.subIcon:SetPoint("CENTER", e.icon, "BOTTOMLEFT", 2, 2)
  e.subIcon:Hide()

  return e
end

local function build()
  if banner then return banner end

  local f = CreateFrame("Frame", "NE_LevelUpDisplay", UIParent)
  f:SetSize(BANNER_W, BANNER_H)
  f:SetPoint(DEFAULT_POINT.point, UIParent, DEFAULT_POINT.relativePoint, DEFAULT_POINT.x, DEFAULT_POINT.y)
  f:SetFrameStrata("HIGH")
  f:Hide()

  f.blackBg = f:CreateTexture(nil, "BACKGROUND")
  f.blackBg:SetTexture(M.TEX)
  f.blackBg:SetTexCoord(unpack(M.RECT.blackBg))
  f.blackBg:SetPoint("BOTTOM", 0, 0)
  f.blackBg:SetSize(BG_W, BG_H)
  f.blackBg:SetVertexColor(1, 1, 1, 0.6)

  -- Anchored at their centre point so widening opens them out both ways, which is what the
  -- source's Scale-from-centre achieves.
  f.gLine = f:CreateTexture(nil, "BACKGROUND", nil, 2)
  f.gLine:SetTexture(M.TEX)
  f.gLine:SetTexCoord(unpack(M.RECT.gLine))
  f.gLine:SetPoint("BOTTOM", 0, 0)
  f.gLine:SetSize(LINE_W, LINE_H)

  f.gLine2 = f:CreateTexture(nil, "BACKGROUND", nil, 2)
  f.gLine2:SetTexture(M.TEX)
  f.gLine2:SetTexCoord(unpack(M.RECT.gLine))
  f.gLine2:SetPoint("TOP", 0, 0)
  f.gLine2:SetSize(LINE_W, LINE_H)

  local lf = CreateFrame("Frame", nil, f)
  lf:SetAllPoints(f)
  lf:SetAlpha(0)
  lf.levelText = lf:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
  lf.levelText:SetJustifyH("CENTER")
  -- Placeholder anchor only; centreLevelText re-points this once the strings have measurable
  -- heights. Anchored here so the region is never point-less if Show is somehow skipped.
  lf.levelText:SetPoint("CENTER", 0, 0)
  lf.levelText:SetTextColor(1, 0.82, 0)
  -- GameFont_Gigantic is Morpheus 32 on retail; setting the font directly rather than inheriting
  -- keeps this working if the font object is absent, which NE.font.Set's fallback covers.
  NE.font.Set(lf.levelText, NE.font.MORPHEUS, 32, "", "GameFontNormalLarge")

  lf.reachedText = lf:CreateFontString(nil, "ARTWORK", "SystemFont_Shadow_Large")
  lf.reachedText:SetJustifyH("CENTER")
  lf.reachedText:SetPoint("BOTTOM", lf.levelText, "TOP", 0, LEVEL_TEXT_GAP)
  f.levelFrame = lf

  f.spellFrame = buildEntryRegions(f)

  NE.FrameUtil.PinPixelPerfect(f)
  banner = f
  M.banner = f
  return f
end
M.Build = build

-- ── Timeline ────────────────────────────────────────────────────────────────────────────────────

local function clamp01(v) return (v < 0 and 0) or (v > 1 and 1) or v end

-- Sit the two-line block in the middle of the banner, between the gold lines, instead of on the
-- lower one. The source bottom-anchors it (BOTTOM, 0, 5), which reads as low on this client because
-- our banner keeps the full 72px height while the Morpheus level line renders shorter than retail's
-- GameFont_Gigantic.
--
-- Runs at Show, not build: GetStringHeight answers 0 until the text is set, and the level line's
-- height depends on which font NE.font.Set actually resolved (Morpheus, or the fallback object if
-- the client has no Morpheus).
local function centreLevelText(f)
  local lf = f.levelFrame
  local hReached = lf.reachedText:GetStringHeight() or 0
  local hLevel   = lf.levelText:GetStringHeight() or 0
  local total    = hReached + LEVEL_TEXT_GAP + hLevel
  -- Bottom of the block half its own height below centre; reachedText stacks up from levelText's
  -- top, so the pair ends up spanning centre +/- total/2.
  lf.levelText:ClearAllPoints()
  lf.levelText:SetPoint("BOTTOM", lf, "CENTER", 0, -total / 2 + CONTENT_Y_OFFSET)
end

-- Centre the flavour-line + name pair on the ICON's middle.
--
-- The source anchors the name to the icon's BOTTOM-right corner and stacks the flavour line above
-- it, which is a bottom-alignment wearing a centring's clothes: the pair is ~28px tall against a
-- 36px icon, so wherever the two happen to land is an accident of how tall the two fonts are. Any
-- font or locale that changes those heights slides the text against the icon. Centring on the icon's
-- own midpoint makes the relationship hold whatever the strings measure.
local function centreEntryText(e)
  local hName = e.name:GetStringHeight() or 0
  local hFlav = e.flavorText:GetStringHeight() or 0
  -- An entry with no flavour line contributes neither height nor gap, so a bare name still centres.
  local total = hName + ((hFlav > 0) and (ENTRY_TEXT_GAP + hFlav) or 0)
  e.name:ClearAllPoints()
  -- The icon's RIGHT anchor point is its vertical middle, so the block's bottom goes half its own
  -- height below that and the flavour line stacks up from the name's top.
  e.name:SetPoint("BOTTOMLEFT", e.icon, "RIGHT", ENTRY_TEXT_X, -total / 2 + ENTRY_TEXT_Y_OFFSET)
end

local function showEntry(f, entry)
  local e = f.spellFrame
  e.name:SetText(entry.text or "")
  e.flavorText:SetText(entry.subText or "")
  e.icon:SetTexture(entry.icon or M.FALLBACK_ICON)
  -- Centre now against the heights we have, and again next tick against the ones this text actually
  -- produces. Every entry changes both strings, so every entry needs the second pass.
  centreEntryText(e)
  f.pendingLayout = true
  if entry.subIcon then
    e.subIcon:SetTexCoord(unpack(entry.subIcon))
    e.subIcon:Show()
  else
    e.subIcon:Hide()
  end
end

-- One tick of the whole sequence. Phases are evaluated against a single elapsed clock rather than
-- chained, so a frame drop cannot leave the banner stuck mid-parade with nothing scheduled to
-- finish it.
local function onUpdate(f, elapsed)
  f.t = (f.t or 0) + elapsed
  local t = f.t

  -- Re-measure once, on the first tick after any text changed.
  --
  -- GetStringHeight answers from the widget's LAST LAID-OUT state, not from the string it was just
  -- handed. Measuring in the same call as SetText therefore reads whatever was there before — on a
  -- frame that has never been shown that is nothing, so the first /nelevelup centred against zero
  -- heights and every later one looked right because it was measuring the PREVIOUS run's text. By
  -- the first OnUpdate tick the layout has resolved and the numbers are real.
  if f.pendingLayout then
    centreLevelText(f)
    centreEntryText(f.spellFrame)
    f.pendingLayout = nil
  end

  -- Phase 1: the lead-in. Everything stays hidden.
  if t < LEAD_IN then
    f.gLine:SetAlpha(0); f.gLine2:SetAlpha(0); f.blackBg:SetAlpha(0)
    return
  end

  -- Phase 2: lines sweep, backing grows, level text fades up.
  local since = t - LEAD_IN
  local sweep = clamp01(since / LINE_SWEEP)
  f.gLine:SetAlpha(1); f.gLine2:SetAlpha(1)
  f.gLine:SetWidth(math.max(1, LINE_W * sweep))
  f.gLine2:SetWidth(math.max(1, LINE_W * sweep))

  local bgT = clamp01((since - BG_DELAY) / BG_GROW)
  f.blackBg:SetAlpha(0.6 * bgT)
  f.blackBg:SetHeight(math.max(1, BG_H * bgT))

  if f.phase == "level" then
    local a
    if since < LEVEL_FADE_IN then
      a = since / LEVEL_FADE_IN
    elseif since < LEVEL_FADE_IN + LEVEL_HOLD then
      a = 1
    else
      a = 1 - clamp01((since - LEVEL_FADE_IN - LEVEL_HOLD) / LEVEL_FADE_OUT)
    end
    f.levelFrame:SetAlpha(clamp01(a))
    if since >= LEVEL_FADE_IN + LEVEL_HOLD + LEVEL_FADE_OUT then
      f.levelFrame:SetAlpha(0)
      -- Long lists never parade; the grid panel shows all of them at once instead. The banner goes
      -- straight away rather than fading, because both sit at the same screen position and a
      -- crossfade would put the gold lines through the panel's header for a second.
      if f.overflow then
        M.Hide()
        M.ShowSide(f.level)
        return
      else
        f.phase = "entries"
        f.index = 1
        f.phaseStart = t
      end
    end

  elseif f.phase == "entries" then
    local entry = f.list and f.list[f.index]
    if not entry then
      f.phase = "out"; f.phaseStart = t
      return
    end
    if f.index ~= f.shownIndex then
      showEntry(f, entry)
      f.shownIndex = f.index
    end
    local e = t - (f.phaseStart or t)
    local a
    if e < ENTRY_FADE_IN then
      a = e / ENTRY_FADE_IN
    elseif e < ENTRY_FADE_IN + ENTRY_HOLD then
      a = 1
    else
      a = 1 - clamp01((e - ENTRY_FADE_IN - ENTRY_HOLD) / ENTRY_FADE_OUT)
    end
    f.spellFrame:SetAlpha(clamp01(a))
    if e >= ENTRY_FADE_IN + ENTRY_HOLD + ENTRY_FADE_OUT then
      f.spellFrame:SetAlpha(0)
      f.index = f.index + 1
      f.phaseStart = t
    end

  elseif f.phase == "out" then
    local e = t - (f.phaseStart or t)
    f:SetAlpha(1 - clamp01(e / BANNER_FADE_OUT))
    if e >= BANNER_FADE_OUT then
      M.Hide()
    end
  end
end

-- ── Public ──────────────────────────────────────────────────────────────────────────────────────

function M.Hide()
  if not banner then return end
  banner:SetScript("OnUpdate", nil)
  banner:Hide()
  banner:SetAlpha(1)
  banner.levelFrame:SetAlpha(0)
  banner.spellFrame:SetAlpha(0)
  banner.phase = nil
  banner.shownIndex = nil
end

-- `level` is what to celebrate. Called by the PLAYER_LEVEL_UP handler in Register.lua and by the
-- test command, which is why it takes the level rather than reading UnitLevel — at the moment the
-- event fires, UnitLevel may still report the old one.
function M.Show(level)
  local f = build()
  M.Hide()

  local list = M.Unlocks(level) or {}
  f.level    = level
  f.list     = list
  f.overflow = #list > INLINE_MAX
  f.t        = 0
  f.phase    = "level"
  f.phaseStart = 0
  f.index    = 1

  f.levelFrame.reachedText:SetText(NE.L["You have reached"])
  -- Lower-case "level" deliberately, against retail's LEVEL_GAINED ("Level %d"). Morpheus renders
  -- lower case as small caps, so a capital L came out as an oversized initial next to them; all
  -- lower case gives an even small-caps line. Owner's call, 2026-08-01.
  f.levelFrame.levelText:SetFormattedText(NE.L["level %d"], level or 0)
  centreLevelText(f)
  f.levelFrame:SetAlpha(0)
  f.spellFrame:SetAlpha(0)
  f.gLine:SetWidth(1); f.gLine2:SetWidth(1); f.blackBg:SetHeight(1)

  NE.FrameUtil.PinPixelPerfect(f)
  f:SetAlpha(1)
  f:Show()
  -- Show first, THEN ask for the re-measure: a hidden frame has no laid-out text to measure.
  f.pendingLayout = true
  f:SetScript("OnUpdate", onUpdate)

  -- OFF by default, and the reason is worth recording so nobody turns it back on: stock FrameXML
  -- fires no sound on PLAYER_LEVEL_UP (grepped, there is none), which suggested a gap to fill —
  -- but the ENGINE plays the fanfare below FrameXML, so this only ever doubled it. What the
  -- setting is still good for is /nelevelup, which triggers no engine sound at all.
  if M.IsSoundEnabled and M.IsSoundEnabled() and PlaySound then
    pcall(PlaySound, "LEVELUPSOUND")
  end
end

M.INLINE_MAX = INLINE_MAX
