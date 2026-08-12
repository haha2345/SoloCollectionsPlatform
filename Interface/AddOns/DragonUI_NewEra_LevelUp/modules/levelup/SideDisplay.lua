-- DragonUI_NewEra/modules/levelup/SideDisplay.lua — the full unlock list, all at once, in a grid.
--
-- In retail this is a vertical list hanging off the left of the banner, opened from a chat
-- hyperlink. Two things about that do not survive the trip:
--
--   * Nothing ever opened it. LevelUpDisplay_ShowSideDisplay has no caller in EITHER prior port —
--     not in NewEra, not in the standalone 3.3.5 addon. The frame, its animations and its template
--     are dead code in both. Here it is the overflow path, so it is reachable by simply levelling.
--   * A vertical list is the wrong shape. On this client a single level routinely grants 8-25
--     unlocks (see Banner.lua's header), and one 44px row each runs off the screen. NewEra hit the
--     same wall on Classic and answered with a 3-column grid; that answer ports directly.
--
-- Centred on screen rather than retail's hang-off-the-banner anchor, for NewEra's reason: the grid
-- is wider than the vertical list it replaces, so hanging it to one side puts the combined mass
-- badly off-centre.

local NE = DragonUI_NewEra
if not NE or NE.disabled then return end

local M = NE.levelup

-- ── Tunables ────────────────────────────────────────────────────────────────────────────────────
local GRID_COLS    = 3
local CELL_W       = 120
local CELL_H       = 40
local CELL_GAP_X   = 4
local CELL_GAP_Y   = 4
local GRID_TOP_PAD = 10     -- below the goldBG header
local HEADER_H     = 65
local PANEL_MIN_W  = 270
local BOTTOM_PAD   = 10

local FADE_IN      = 0.5
local CELL_STAGGER = 0.06   -- cells arrive in sequence rather than all at once
local AUTO_DISMISS = 12.0   -- seconds on screen before it fades itself out
local FADE_OUT     = 1.0

local panel

-- ── Build ───────────────────────────────────────────────────────────────────────────────────────

local function buildCell(parent, i)
  local c = CreateFrame("Frame", nil, parent)
  c:SetSize(CELL_W, CELL_H)
  c:SetAlpha(0)

  c.icon = c:CreateTexture(nil, "ARTWORK")
  c.icon:SetSize(28, 28)
  c.icon:SetPoint("LEFT", 2, 0)

  -- Width 84 = cell 120 - icon 28 - gap 4 - margin 4. Height 36 gives a second line to wrap into.
  -- Multi-line wrapping on 3.3.5a needs an explicit width plus a single anchor (CLAUDE.md);
  -- opposing LEFT+RIGHT anchors truncate the last line.
  c.name = c:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
  c.name:SetSize(84, CELL_H - 4)
  c.name:SetJustifyH("LEFT")
  c.name:SetPoint("LEFT", c.icon, "RIGHT", 4, 0)

  c.subIcon = c:CreateTexture(nil, "OVERLAY")
  c.subIcon:SetTexture(M.TEX)
  c.subIcon:SetSize(14, 14)
  c.subIcon:SetPoint("CENTER", c.icon, "BOTTOMLEFT", 1, 1)
  c.subIcon:Hide()

  parent.cells[i] = c
  return c
end

local function build()
  if panel then return panel end

  -- A Button so the whole surface dismisses on click, which is retail's behaviour for this frame.
  local p = CreateFrame("Button", "NE_LevelUpDisplaySide", UIParent)
  p:SetSize(PANEL_MIN_W, HEADER_H)
  p:SetPoint("TOP", UIParent, "TOP", 0, -190)
  p:SetFrameStrata("HIGH")
  p:Hide()
  p.cells = {}

  p.goldBG = p:CreateTexture(nil, "BACKGROUND")
  p.goldBG:SetTexture(M.TEX)
  p.goldBG:SetTexCoord(unpack(M.RECT.goldBG))
  p.goldBG:SetSize(223, 115)
  p.goldBG:SetPoint("TOP", 0, 53)

  p.blackBg = p:CreateTexture(nil, "BACKGROUND")
  p.blackBg:SetTexture(M.TEX)
  p.blackBg:SetTexCoord(unpack(M.RECT.sideBg))
  p.blackBg:SetPoint("TOP", p.goldBG, "BOTTOM")
  p.blackBg:SetVertexColor(1, 1, 1, 0.6)

  p.dot = p:CreateTexture(nil, "BACKGROUND", nil, 2)
  p.dot:SetTexture(M.TEX)
  p.dot:SetTexCoord(unpack(M.RECT.dot))
  p.dot:SetSize(21, 22)
  p.dot:SetPoint("CENTER", p.goldBG, "BOTTOM", 0, 0)

  p.levelText = p:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
  p.levelText:SetJustifyH("CENTER")
  p.levelText:SetPoint("BOTTOM", p.goldBG, "BOTTOM", 0, 5)
  p.levelText:SetTextColor(1, 0.82, 0)
  NE.font.Set(p.levelText, NE.font.MORPHEUS, 32, "", "GameFontNormalLarge")

  p.reachedText = p:CreateFontString(nil, "ARTWORK", "SystemFont_Shadow_Large")
  p.reachedText:SetJustifyH("CENTER")
  p.reachedText:SetPoint("BOTTOM", p.levelText, "TOP", 0, 5)

  p:SetScript("OnClick", function() M.HideSide() end)

  NE.FrameUtil.PinPixelPerfect(p)
  panel = p
  M.side = p
  return p
end
M.BuildSide = build

-- ── Show / hide ─────────────────────────────────────────────────────────────────────────────────

local function clamp01(v) return (v < 0 and 0) or (v > 1 and 1) or v end

local function onUpdate(p, elapsed)
  p.t = (p.t or 0) + elapsed
  local t = p.t

  if p.fading then
    local a = 1 - clamp01((t - p.fadeStart) / FADE_OUT)
    p:SetAlpha(a)
    if a <= 0 then M.HideSide() end
    return
  end

  -- Panel fades up, then cells arrive one after another.
  p:SetAlpha(clamp01(t / FADE_IN))
  for i, c in ipairs(p.cells) do
    if c:IsShown() then
      local start = FADE_IN + (i - 1) * CELL_STAGGER
      c:SetAlpha(clamp01((t - start) / FADE_IN))
    end
  end

  local settled = FADE_IN + (p.shownList and #p.shownList or 0) * CELL_STAGGER + FADE_IN
  if t >= settled + AUTO_DISMISS then
    p.fading   = true
    p.fadeStart = t
  end
end

function M.HideSide()
  if not panel then return end
  panel:SetScript("OnUpdate", nil)
  panel:Hide()
  panel:SetAlpha(1)
  panel.fading = nil
end

function M.ShowSide(level)
  local p = build()
  M.HideSide()

  local list = M.Unlocks(level) or {}
  p.shownList = list
  p.level     = level
  p.t         = 0

  p.reachedText:SetText(NE.L["You have reached"])
  -- Lower case to match the banner; see Banner.lua's note at the same call.
  p.levelText:SetFormattedText(NE.L["level %d"], level or 0)

  local count = #list
  local rows  = math.max(1, math.ceil(count / GRID_COLS))
  local gridW = GRID_COLS * CELL_W + (GRID_COLS - 1) * CELL_GAP_X
  p:SetWidth(math.max(PANEL_MIN_W, gridW + 20))
  local leftOffset = -gridW / 2      -- centre the grid under the panel's centre line

  for i = 1, count do
    local c = p.cells[i] or buildCell(p, i)
    local entry = list[i]
    local col, row = (i - 1) % GRID_COLS, math.floor((i - 1) / GRID_COLS)
    c:ClearAllPoints()
    c:SetPoint("TOPLEFT", p.goldBG, "BOTTOM",
               leftOffset + col * (CELL_W + CELL_GAP_X),
               -GRID_TOP_PAD - row * (CELL_H + CELL_GAP_Y))
    c.name:SetText(entry.text or "")
    c.icon:SetTexture(entry.icon or M.FALLBACK_ICON)
    if entry.subIcon then
      c.subIcon:SetTexCoord(unpack(entry.subIcon))
      c.subIcon:Show()
    else
      c.subIcon:Hide()
    end
    c:SetAlpha(0)
    c:Show()
  end

  -- Retire cells left over from a longer list last time.
  for i = count + 1, #p.cells do
    p.cells[i]:Hide()
    p.cells[i]:SetAlpha(0)
  end

  local gridH = rows * CELL_H + (rows - 1) * CELL_GAP_Y
  p:SetHeight(HEADER_H + GRID_TOP_PAD + gridH + BOTTOM_PAD)
  p.blackBg:SetSize(math.max(PANEL_MIN_W, gridW + 20) + 14, GRID_TOP_PAD + gridH + BOTTOM_PAD + 40)

  NE.FrameUtil.PinPixelPerfect(p)
  p:SetAlpha(0)
  p:Show()
  p:SetScript("OnUpdate", onUpdate)
end
