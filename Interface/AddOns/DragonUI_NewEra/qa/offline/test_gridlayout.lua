-- Exercise core/GridLayout.lua against a stubbed widget API.
-- Verifies the cell arithmetic, wrapping, direction mirroring, scale handling and frame resize.

DragonUI_NewEra = {}

-- ── minimal widget stub ─────────────────────────────────────────────────────
local function newFrame()
  local f = {
    _w = 0, _h = 0, _scale = 1, _shown = true, _children = {}, _points = {},
  }
  function f:SetSize(w, h) self._w, self._h = w, h end
  function f:GetWidth() return self._w end
  function f:GetHeight() return self._h end
  function f:GetScale() return self._scale end
  function f:SetScale(s) self._scale = s end
  function f:IsShown() return self._shown end
  function f:Hide() self._shown = false end
  function f:Show() self._shown = true end
  function f:ClearAllPoints() self._points = {} end
  function f:SetPoint(p, rel, relP, x, y)
    self._points[#self._points + 1] = { p = p, relP = relP, x = x, y = y }
  end
  function f:GetChildren() return unpack(self._children) end
  return f
end

-- Addon root; see test_boot.lua. Run as: luajit qa/offline/test_gridlayout.lua
local ADDON = os.getenv("NE_ADDON_ROOT") or "./"
dofile(ADDON .. "core/GridLayout.lua")
local GL = DragonUI_NewEra.gridlayout

local fails = 0
local function check(label, got, want)
  local ok = math.abs(got - want) < 0.001
  if not ok then
    fails = fails + 1
    print(string.format("  FAIL %-40s got %s want %s", label, tostring(got), tostring(want)))
  else
    print(string.format("  ok   %-40s %s", label, tostring(got)))
  end
end

local function build(n, size, scale)
  local parent = newFrame()
  GL.Apply(parent)
  for i = 1, n do
    local c = newFrame()
    c:SetSize(size, size)
    c._scale = scale or 1
    c.layoutIndex = i
    parent._children[i] = c
  end
  return parent
end

-- ── 1. horizontal row, 4 icons of 50px, padding -2 ──────────────────────────
print("\n[1] horizontal, 4x50px, pad -2, stride 12, going right")
local p = build(4, 50)
p.isHorizontal = true; p.stride = 12
p.childXPadding, p.childYPadding = -2, -2
p.layoutFramesGoingRight = true
p:Layout()
-- widths: 4*50 + 3*(-2) = 194
check("frame width", p._w, 194)
check("frame height", p._h, 50)
check("child1 x", p._children[1]._points[1].x, 0)
check("child2 x", p._children[2]._points[1].x, 48)
check("child4 x", p._children[4]._points[1].x, 144)
check("child1 y", p._children[1]._points[1].y, 0)
check("anchor is TOPLEFT", p._children[1]._points[1].p == "TOPLEFT" and 1 or 0, 1)

-- ── 2. wrapping: 5 icons, stride 3 ──────────────────────────────────────────
print("\n[2] horizontal wrap, 5x50px, stride 3, pad 0")
p = build(5, 50)
p.isHorizontal = true; p.stride = 3
p.childXPadding, p.childYPadding = 0, 0
p.layoutFramesGoingRight = true
p:Layout()
check("frame width (3 cols)", p._w, 150)
check("frame height (2 rows)", p._h, 100)
check("child4 x (row 2, col 1)", p._children[4]._points[1].x, 0)
check("child4 y (row 2)", p._children[4]._points[1].y, -50)
check("child5 x (row 2, col 2)", p._children[5]._points[1].x, 50)

-- ── 3. direction mirroring ──────────────────────────────────────────────────
print("\n[3] going LEFT mirrors the row")
p = build(3, 50)
p.isHorizontal = true; p.stride = 12
p.childXPadding, p.childYPadding = 0, 0
p.layoutFramesGoingRight = false
p:Layout()
check("frame width", p._w, 150)
-- child1 should sit at the RIGHT edge: total(150) - 0 - width(50) = 100
check("child1 x (mirrored)", p._children[1]._points[1].x, 100)
check("child3 x (mirrored)", p._children[3]._points[1].x, 0)

-- ── 4. scale: offsets must be expressed in CHILD units ──────────────────────
print("\n[4] iconSize 200% (scale 2) - parent px vs child units")
p = build(3, 50, 2)
p.isHorizontal = true; p.stride = 12
p.childXPadding, p.childYPadding = 0, 0
p.layoutFramesGoingRight = true
p:Layout()
-- each child occupies 50*2 = 100 parent px, so total = 300
check("frame width (scaled)", p._w, 300)
-- child2 sits 100 parent px along, but SetPoint offsets are in child units: 100/2 = 50
check("child2 x in child units", p._children[2]._points[1].x, 50)

-- ── 5. vertical orientation, both stack directions ──────────────────────────
-- The viewer's RefreshLayout derives goingUp from orientation+direction:
--   layoutFramesGoingUp = growUpward or ((not isHorizontal) and iconDirection == "right")
-- so vertical+right stacks UP (BOTTOMLEFT anchor, +y) and vertical+left stacks DOWN.
print("\n[5a] vertical stacking DOWN (goingUp=false)")
p = build(3, 50)
p.isHorizontal = false; p.stride = 3
p.childXPadding, p.childYPadding = 0, 0
p.layoutFramesGoingRight = true
p.layoutFramesGoingUp = false
p:Layout()
check("frame width (1 col)", p._w, 50)
check("frame height (3 rows)", p._h, 150)
check("child2 y (downward)", p._children[2]._points[1].y, -50)
check("anchor TOPLEFT", p._children[1]._points[1].p == "TOPLEFT" and 1 or 0, 1)

print("\n[5b] vertical stacking UP (goingUp=true, as vertical+right derives)")
p = build(3, 50)
p.isHorizontal = false; p.stride = 3
p.childXPadding, p.childYPadding = 0, 0
p.layoutFramesGoingRight = true
p.layoutFramesGoingUp = true
p:Layout()
check("frame height (3 rows)", p._h, 150)
check("child2 y (upward)", p._children[2]._points[1].y, 50)
check("anchor BOTTOMLEFT", p._children[1]._points[1].p == "BOTTOMLEFT" and 1 or 0, 1)

-- ── 6. retired / hidden children ────────────────────────────────────────────
print("\n[6] ignoreInLayout + hidden children")
p = build(4, 50)
p.isHorizontal = true; p.stride = 12
p.childXPadding, p.childYPadding = 0, 0
p.layoutFramesGoingRight = true
p._children[3].ignoreInLayout = true
p._children[3]:Hide()
p._children[4].ignoreInLayout = true
p._children[4]:Hide()
p:Layout()
check("frame width (2 live)", p._w, 100)

print("\n[7] hidden but includeAsLayoutChildWhenHidden holds its cell")
p = build(3, 50)
p.isHorizontal = true; p.stride = 12
p.childXPadding, p.childYPadding = 0, 0
p.layoutFramesGoingRight = true
p._children[2]:Hide()
p._children[2].includeAsLayoutChildWhenHidden = true
p:Layout()
check("frame width (cell held)", p._w, 150)
check("child3 x (not reflowed)", p._children[3]._points[1].x, 100)

-- ── 8. empty + degenerate ───────────────────────────────────────────────────
print("\n[8] empty viewer and negative-padding clamp")
p = build(0, 50)
p.isHorizontal = true; p.stride = 12
p:Layout()
check("empty frame width >= 1", p._w, 1)
check("empty frame height >= 1", p._h, 1)

p = build(1, 50)
p.isHorizontal = true; p.stride = 12
p.childXPadding, p.childYPadding = -2, -2
p:Layout()
check("single item unaffected by pad", p._w, 50)

-- ── 9. centred short lines ──────────────────────────────────────────────────
-- The owner's case: 12 icons at an icon limit of 9 wrap to 9 + 3, and the 3 must sit centred under
-- the 9 instead of hugging the left edge. Every viewer sets centerPartialLines in RefreshLayout.
print("\n[9a] horizontal, 12x50px, stride 9, pad 0 - short row centred")
p = build(12, 50)
p.isHorizontal = true; p.stride = 9
p.childXPadding, p.childYPadding = 0, 0
p.layoutFramesGoingRight = true
p.centerPartialLines = true
p:Layout()
check("frame width (9 cols)", p._w, 450)
check("full row 1 not shifted", p._children[1]._points[1].x, 0)
check("full row 1 last col", p._children[9]._points[1].x, 400)
-- row 2 holds 3 icons = 150px inside 450px, so it starts at (450-150)/2 = 150
check("row 2 first is centred", p._children[10]._points[1].x, 150)
check("row 2 last is centred", p._children[12]._points[1].x, 250)
check("row 2 y unchanged", p._children[10]._points[1].y, -50)

print("\n[9b] off by default - the same grid stays flush left")
p = build(12, 50)
p.isHorizontal = true; p.stride = 9
p.childXPadding, p.childYPadding = 0, 0
p.layoutFramesGoingRight = true
p:Layout()
check("row 2 flush left", p._children[10]._points[1].x, 0)

print("\n[9c] mirrored: centring is symmetric about the frame centre")
p = build(12, 50)
p.isHorizontal = true; p.stride = 9
p.childXPadding, p.childYPadding = 0, 0
p.layoutFramesGoingRight = false
p.centerPartialLines = true
p:Layout()
-- Mirrored, child10 is the RIGHTMOST of row 2: 450 - 150 - 50 = 250
check("row 2 first (mirrored)", p._children[10]._points[1].x, 250)
check("row 2 last (mirrored)", p._children[12]._points[1].x, 150)

print("\n[9d] a grid that divides evenly gets no offset at all")
p = build(9, 50)
p.isHorizontal = true; p.stride = 3
p.childXPadding, p.childYPadding = 0, 0
p.layoutFramesGoingRight = true
p.centerPartialLines = true
p:Layout()
check("row 2 aligned with row 1", p._children[4]._points[1].x, 0)
check("row 3 aligned with row 1", p._children[7]._points[1].x, 0)

print("\n[9e] vertical: the short COLUMN centres along Y")
p = build(5, 50)
p.isHorizontal = false; p.stride = 3
p.childXPadding, p.childYPadding = 0, 0
p.layoutFramesGoingRight = true
p.layoutFramesGoingUp = false
p.centerPartialLines = true
p:Layout()
check("frame height (3 rows)", p._h, 150)
check("full column 1 not shifted", p._children[1]._points[1].y, 0)
-- column 2 holds 2 icons = 100px inside 150px, so it starts 25px down
check("column 2 first centred", p._children[4]._points[1].y, -25)
check("column 2 second centred", p._children[5]._points[1].y, -75)

print("\n[9f] vertical stacking UP centres the same way from the bottom")
p = build(5, 50)
p.isHorizontal = false; p.stride = 3
p.childXPadding, p.childYPadding = 0, 0
p.layoutFramesGoingRight = true
p.layoutFramesGoingUp = true
p.centerPartialLines = true
p:Layout()
check("column 2 first centred (up)", p._children[4]._points[1].y, 25)
check("column 2 second centred (up)", p._children[5]._points[1].y, 75)

print("\n[9g] scale: the centring offset is in CHILD units too")
p = build(4, 50, 2)
p.isHorizontal = true; p.stride = 3
p.childXPadding, p.childYPadding = 0, 0
p.layoutFramesGoingRight = true
p.centerPartialLines = true
p:Layout()
-- 3 cols of 100 parent px = 300; row 2 holds one 100px child, centred at 100 parent px = 50 child
check("frame width (scaled)", p._w, 300)
check("row 2 lone icon centred", p._children[4]._points[1].x, 50)

print("")
if fails == 0 then print("ALL GRIDLAYOUT CHECKS PASSED") else print(fails .. " FAILURE(S)") end
os.exit(fails == 0 and 0 or 1)
