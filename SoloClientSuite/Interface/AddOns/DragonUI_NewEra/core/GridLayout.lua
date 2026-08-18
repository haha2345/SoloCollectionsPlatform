-- DragonUI_NewEra/core/GridLayout.lua — Lua reimplementation of retail's GridLayoutFrame.
--
-- DOWNPORT: retail FrameXML ships LayoutFrame.{lua,xml} providing the `GridLayoutFrame` virtual
-- template. NewEra's CooldownViewer.xml inherits it on all four viewer frames and drives it through
-- `layoutIndex` / `stride` / `childXPadding` / `layoutFramesGoingRight` / `:Layout()`. 3.3.5a has
-- none of it, and !!!ClassicAPI ships only the AnchorUtil.GridLayout *helpers* (Util/AnchorUtil.lua)
-- — not the template. So we provide the same surface as a mixin applied in Lua at frame creation.
--
-- PUBLIC:
--   NE.gridlayout.Apply(frame)   -- installs the mixin; frame:Layout() then works
--
-- FIELDS the owner sets (all read fresh on every Layout, same as retail):
--   frame.isHorizontal            -- true: fill rows first. false: fill columns first.
--   frame.stride                  -- items per row (horizontal) / per column (vertical)
--   frame.childXPadding           -- px between columns (MAY BE NEGATIVE — the viewers use -2)
--   frame.childYPadding           -- px between rows
--   frame.layoutFramesGoingRight  -- false mirrors the grid horizontally
--   frame.layoutFramesGoingUp     -- true anchors from the BOTTOM edge and stacks upward
--   frame.centerPartialLines      -- centre a line that doesn't fill `stride` (see Layout)
--   child.layoutIndex             -- sort key; children without one are skipped
--   child.ignoreInLayout          -- skip this child (retired pool slots set this)
--   child.includeAsLayoutChildWhenHidden -- a hidden child still occupies its grid cell
--
-- Retail resizes the frame to the laid-out bounds every pass when `alwaysUpdateLayout` is set; the
-- viewers always set it, so we unconditionally resize. That is what keeps a mover/drag handle
-- tracking the live size as icons are learned.

local NE = DragonUI_NewEra
NE.gridlayout = NE.gridlayout or {}

local GridLayoutMixin = {}

-- Collect the children that participate, ordered by layoutIndex.
--
-- DOWNPORT: retail's LayoutMixin:GetLayoutChildren walks `self.layoutChildren` maintained by the
-- XML template. We have no such bookkeeping, so we walk GetChildren() and filter — the viewers keep
-- their items in `self.items` but ALSO parent them to the frame, and going through GetChildren()
-- means this mixin works for any caller, not just the cooldown viewers.
local function layoutChildren(self)
  local out = {}
  local n = 0
  for i = 1, select("#", self:GetChildren()) do
    local child = select(i, self:GetChildren())
    -- `ignoreInLayout` is the authoritative skip (retired pool slots set it). A merely HIDDEN child
    -- is skipped too, unless it opts into holding its cell via includeAsLayoutChildWhenHidden —
    -- retail's LayoutFrame key, which the Essential/Utility item templates set so a row doesn't
    -- reflow as individual icons come and go.
    local participates = child and child.layoutIndex and not child.ignoreInLayout
      and (child:IsShown() or child.includeAsLayoutChildWhenHidden)
    if participates then
      n = n + 1
      out[n] = child
    end
  end
  table.sort(out, function(a, b) return a.layoutIndex < b.layoutIndex end)
  return out, n
end

-- A child's size in the PARENT's coordinate units.
--
-- 3.3.5a gotcha (the one that silently breaks every scaled grid): a frame's SetPoint offsets are
-- interpreted in the CHILD's own scale units, while GetWidth/GetHeight also return child units. The
-- viewers call item:SetScale(iconScale) per item (CooldownViewer.lua RefreshLayout), so a 50px icon
-- at scale 1.5 occupies 75px of the parent. We convert to parent units for the arithmetic, then
-- convert the final offsets back to child units at SetPoint time.
local function childScale(child)
  local s = child.GetScale and child:GetScale() or 1
  if not s or s <= 0 then return 1 end
  return s
end

local function childExtent(child)
  local s = childScale(child)
  return (child:GetWidth() or 0) * s, (child:GetHeight() or 0) * s
end

function GridLayoutMixin:Layout()
  local children, count = layoutChildren(self)
  if count == 0 then
    -- Nothing to show. Collapse to a 1x1 so the frame has a legal (non-zero) size — SetSize(0,0)
    -- is rejected by the 3.3.5a widget API and leaves the previous size stuck.
    self:SetSize(1, 1)
    return
  end

  local horizontal = self.isHorizontal ~= false
  local stride     = self.stride
  if not stride or stride < 1 then stride = count end
  local xPad = self.childXPadding or 0
  local yPad = self.childYPadding or 0

  -- Grid coordinates per child. `stride` counts along the fill axis: rows fill first when
  -- horizontal, columns fill first when vertical.
  local rowOf, colOf = {}, {}
  local numRows, numCols = 0, 0
  for i = 1, count do
    local major = math.floor((i - 1) / stride)   -- which row (horizontal) / column (vertical)
    local minor = (i - 1) % stride               -- position along the fill axis
    local r, c
    if horizontal then r, c = major, minor else r, c = minor, major end
    rowOf[i], colOf[i] = r, c
    if r + 1 > numRows then numRows = r + 1 end
    if c + 1 > numCols then numCols = c + 1 end
  end

  -- Column widths / row heights as maxima, so mixed-size children (the BuffBar's wide bars vs the
  -- icon viewers' square tiles) still line up instead of overlapping.
  local colW, rowH = {}, {}
  for i = 1, count do
    local w, h = childExtent(children[i])
    local c, r = colOf[i], rowOf[i]
    if not colW[c] or w > colW[c] then colW[c] = w end
    if not rowH[r] or h > rowH[r] then rowH[r] = h end
  end

  -- Running offsets to the start of each column/row.
  local colX, rowY = {}, {}
  local acc = 0
  for c = 0, numCols - 1 do
    colX[c] = acc
    acc = acc + (colW[c] or 0) + xPad
  end
  local totalW = acc - xPad
  acc = 0
  for r = 0, numRows - 1 do
    rowY[r] = acc
    acc = acc + (rowH[r] or 0) + yPad
  end
  local totalH = acc - yPad

  -- Negative padding (the viewers default to iconPadding 2 + additionalPaddingOffset -4 = -2) can
  -- drive a single-item axis negative. Clamp so SetSize never receives <= 0.
  if totalW < 1 then totalW = 1 end
  if totalH < 1 then totalH = 1 end

  -- Centre a SHORT line. 12 icons at a stride of 9 wrap to 9 + 3, and the trailing 3 would otherwise
  -- sit flush against the start edge, visibly off-centre under the full row above. `centerPartialLines`
  -- shifts each line by half its shortfall against the laid-out bounds.
  --
  -- A line here is a row when horizontal and a column when vertical — the same axis `stride` counts
  -- along. A line that IS full measures the full extent and so gets an offset of 0, which is what
  -- keeps the columns of a multi-row grid aligned with each other.
  local lineOffset = {}
  if self.centerPartialLines then
    -- The line's own extent, taken as the furthest child edge rather than a sum of cell sizes, so a
    -- line of mixed-width children (the BuffBar's bars) measures what it actually occupies.
    local extent = {}
    for i = 1, count do
      local w, h = childExtent(children[i])
      local line = horizontal and rowOf[i] or colOf[i]
      local e = horizontal and ((colX[colOf[i]] or 0) + w) or ((rowY[rowOf[i]] or 0) + h)
      if not extent[line] or e > extent[line] then extent[line] = e end
    end
    local total = horizontal and totalW or totalH
    for line, e in pairs(extent) do
      lineOffset[line] = (total - e) / 2
    end
  end

  local goingRight = self.layoutFramesGoingRight ~= false
  local goingUp    = self.layoutFramesGoingUp and true or false
  local anchor     = goingUp and "BOTTOMLEFT" or "TOPLEFT"

  for i = 1, count do
    local child = children[i]
    local w, h  = childExtent(child)
    local s     = childScale(child)

    local x = colX[colOf[i]] or 0
    local y = rowY[rowOf[i]] or 0

    -- Centring offset, applied BEFORE the mirror below. Mirroring reflects the line about the
    -- frame's centre and the centring offset is symmetric about that same centre, so folding it in
    -- first is exactly what flips its sign for a leftward grid — no separate case needed.
    local off = lineOffset[horizontal and rowOf[i] or colOf[i]]
    if off then
      if horizontal then x = x + off else y = y + off end
    end

    -- Mirror horizontally: the row grows leftward from the right edge. Uses this child's own width
    -- so a mixed-width row stays flush against the correct edge.
    if not goingRight then x = totalW - x - w end

    child:ClearAllPoints()
    -- Offsets back into child units (see childScale above). Y is negative when anchoring from the
    -- top (grid grows downward) and positive from the bottom (grows upward).
    if goingUp then
      child:SetPoint(anchor, self, anchor, x / s, y / s)
    else
      child:SetPoint(anchor, self, anchor, x / s, -y / s)
    end
  end

  self:SetSize(totalW, totalH)
end

-- Retail name for "resize me to my laid-out contents". Our Layout always resizes, so this is an
-- alias kept so ported call sites don't need editing.
function GridLayoutMixin:ResizeLayout()
  self:Layout()
end

-- Install onto a frame. Safe to call twice.
function NE.gridlayout.Apply(frame)
  if not frame or frame._neGridLayout then return frame end
  for k, v in pairs(GridLayoutMixin) do
    frame[k] = v
  end
  frame._neGridLayout = true
  return frame
end

NE.gridlayout.Mixin = GridLayoutMixin
