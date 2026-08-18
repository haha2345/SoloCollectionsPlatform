-- DragonUI_NewEra/core/Menu.lua — a MenuUtil-shaped context-menu builder over 3.3.5a's
-- UIDropDownMenu.
--
-- WHY THIS EXISTS. Every menu in the NewEra source is written against retail's MenuUtil builder
-- API: a generator function receives a root description and calls `root:CreateTitle`,
-- `CreateButton`, `CreateRadio`, `CreateCheckbox`, `CreateDivider`, nesting freely by adding
-- children to a returned description. None of that exists here. Reimplementing the *API* once, in
-- ~200 lines, lets each of those generators port close to verbatim instead of being hand-rewritten
-- into UIDropDownMenu's init-callback idiom — which is both more code overall and a fresh chance to
-- get the level plumbing wrong at every site.
--
-- WHICH BACKEND. Prefer ClassicAPI's `C_UIDropDownMenu_*`. The native 3.3.5a one hard-caps at
-- C_UIDROPDOWNMENU_MAXLEVELS = 2, and the Cooldown Manager's ready-sound menu is three deep
-- (item -> Ready Sound -> category -> entry). ClassicAPI's copy grows the cap on demand inside
-- C_UIDropDownMenu_CreateFrames, which is exactly the constraint that decides this. The native
-- functions are kept as a fallback so the shim still works (two levels deep) if ClassicAPI is
-- absent; the two APIs are otherwise the same shape, differing only in the list-frame name prefix.
--
-- THE TREE IS SEPARATE FROM THE RENDER. `NE.menu.BuildRoot` runs a generator and returns a plain
-- node tree with no widget touched. That is what makes menu CONTENT testable offline: a test can
-- build the tree, walk it, and invoke a leaf's callback to assert the wiring, without stubbing any
-- of UIDropDownMenu.
--
-- SUBMENU PARENTS ARE `notClickable`. A row with children gets hasArrow + notClickable, not a
-- no-op func. UIDropDownMenu's OnClick toggles the row's Check texture *before* it looks at func,
-- so a clickable-but-inert parent paints a stray checkmark on itself. What that costs, and what
-- `openOnHover` below pays back, is the row's ability to see the mouse at all: notClickable means
-- disabled, and a disabled row neither fires the OnEnter that opens the submenu nor keeps the
-- invisible button — whose OnEnter CLOSES the submenu — out of the way.
--
-- RADIOS REFRESH THEMSELVES. C_UIDropDownMenu_Refresh keys off frame.selectedName/ID/Value, which
-- says nothing about function-valued `checked`, so it cannot be used here. Instead a radio's click
-- re-evaluates every sibling's predicate and repaints the check textures directly.
--
-- AND `info.checked` IS ALWAYS A BOOLEAN, NEVER A FUNCTION. UIDropDownMenu accepts a predicate
-- there, but it reads the result through the classic `and`/`or` idiom:
--
--     local checked = type(info.checked) == "function" and info.checked() or info.checked
--
-- which collapses when the predicate returns FALSE: `(true and false)` is false, so the `or` falls
-- through to `info.checked` — the function itself, which is truthy. Every function-valued radio
-- therefore renders as selected, and a menu where everything is ticked shows nothing at all. We
-- snapshot the predicate to a boolean at build time instead. Nothing is lost: the menu is rebuilt
-- from the generator on every open, and refreshChecks re-reads the predicate on every click.

local NE = DragonUI_NewEra
NE.menu = NE.menu or {}

-- ── node tree ───────────────────────────────────────────────────────────────────────────────────

local Node = {}
Node.__index = Node

local function newNode(kind, text)
  return setmetatable({ kind = kind, text = text, children = {} }, Node)
end

function Node:Add(node)
  self.children[#self.children + 1] = node
  return node
end

function Node:CreateTitle(text)
  return self:Add(newNode("title", text))
end

function Node:CreateDivider()
  return self:Add(newNode("divider"))
end

-- A button with children becomes a submenu; the callback is then ignored, matching MenuUtil.
function Node:CreateButton(text, onClick, data)
  local n = newNode("button", text)
  n.onClick, n.data = onClick, data
  return self:Add(n)
end

function Node:CreateRadio(text, isSelected, onClick, data)
  local n = newNode("radio", text)
  n.isSelected, n.onClick, n.data = isSelected, onClick, data
  return self:Add(n)
end

function Node:CreateCheckbox(text, isSelected, onClick, data)
  local n = newNode("checkbox", text)
  n.isSelected, n.onClick, n.data = isSelected, onClick, data
  return self:Add(n)
end

-- Hover text for one row. UIDropDownMenu shows this from the row's own OnEnter, and shows it on
-- disabled rows too when tooltipWhileDisabled is set — which is what lets an entry explain why it
-- cannot do anything rather than just sitting there inert.
function Node:SetTooltip(title, text)
  self.tipTitle, self.tipText = title, text
  return self
end

-- First child with this exact text. For callers that want to drive a built menu (tests, mostly)
-- without counting indices.
function Node:Child(text)
  for _, c in ipairs(self.children) do
    if c.text == text then return c end
  end
  return nil
end

function Node:Invoke()
  if self.onClick then self.onClick(self.data) end
end

NE.menu.Node = Node

-- generator(owner, root, ...) — MenuUtil's signature. Our generators ignore `owner`.
function NE.menu.BuildRoot(generator, owner, ...)
  if type(generator) ~= "function" then return nil end
  local root = newNode("root")
  generator(owner, root, ...)
  NE.menu._lastRoot = root   -- test seam
  return root
end

-- ── backend ─────────────────────────────────────────────────────────────────────────────────────

local B   -- resolved on first use; the globals do not exist until ClassicAPI has loaded

local function backend()
  if B ~= nil then return B or nil end
  if _G.C_UIDropDownMenu_AddButton and _G.C_ToggleDropDownMenu then
    B = {
      prefix     = "C_DropDownList",
      template   = "C_UIDropDownMenuTemplate",
      openVar    = "C_UIDROPDOWNMENU_OPEN_MENU",
      CreateInfo = _G.C_UIDropDownMenu_CreateInfo,
      AddButton  = _G.C_UIDropDownMenu_AddButton,
      Initialize = _G.C_UIDropDownMenu_Initialize,
      Toggle     = _G.C_ToggleDropDownMenu,
      CloseAll   = _G.C_CloseDropDownMenus,
    }
  elseif _G.UIDropDownMenu_AddButton and _G.ToggleDropDownMenu then
    -- Two levels only. Enough for a flat menu, not for the sound picker.
    B = {
      prefix     = "DropDownList",
      template   = "UIDropDownMenuTemplate",
      openVar    = "UIDROPDOWNMENU_OPEN_MENU",
      CreateInfo = _G.UIDropDownMenu_CreateInfo,
      AddButton  = _G.UIDropDownMenu_AddButton,
      Initialize = _G.UIDropDownMenu_Initialize,
      Toggle     = _G.ToggleDropDownMenu,
      CloseAll   = _G.CloseDropDownMenus,
    }
  else
    B = false
  end
  return B or nil
end

local function listButton(level, index)
  local b = backend()
  return b and _G[b.prefix .. level .. "Button" .. index] or nil
end

-- Repaint the check/radio marks for one open level from their predicates. Called after a radio or
-- checkbox fires, because the built-in OnClick only knows how to toggle the row you clicked.
local function refreshChecks(level)
  local b = backend()
  local list = b and _G[b.prefix .. level]
  if not list then return end
  for i = 1, (list.numButtons or 0) do
    local btn = listButton(level, i)
    local node = btn and btn._neNode
    if node and node.isSelected then
      local on = node.isSelected(node.data) and true or false
      local check = _G[btn:GetName() .. "Check"]
      if check then
        if node.kind == "radio" then
          check:SetTexture("Interface\\Buttons\\UI-RadioButton")
          check:SetTexCoord(on and 0.25 or 0, on and 0.5 or 0.25, 0, 1)
          if check.SetDesaturated then check:SetDesaturated(not on) end
          check:SetAlpha(on and 1 or 0.25)
          check:Show()
        elseif on then
          check:Show()
        else
          check:Hide()
        end
      end
      if on then btn:LockHighlight() else btn:UnlockHighlight() end
      btn.checked = on   -- keeps the built-in OnClick's next toggle pointing the right way
    end
  end
end

-- ── render ──────────────────────────────────────────────────────────────────────────────────────

-- Let a submenu row take the mouse across its whole width, instead of only on its 16px arrow.
--
-- `notClickable` (see the header) makes the row a DISABLED button — C_UIDropDownMenu.lua:172 turns it
-- into `info.disabled`. Two things follow from that on this client, and both of them fight the player:
--
--   1. A disabled Button fires no OnEnter unless it is told to. The row's own OnEnter is the thing
--      that opens a `hasArrow` submenu, so it never ran.
--   2. Disabling also SHOWS `$parentInvisibleButton`, which covers the row and whose OnEnter calls
--      CloseDropDownMenus(level + 1) — so hovering the row body actively shut the submenu again.
--
-- That left `$parentExpandArrow` as the only way in, and any approach to it that crossed the row
-- first slammed the door. Reported as "I have to specifically mouse over the arrow which makes
-- navigating annoying", on the alert menu's FX Style submenu.
--
-- The tooltip the invisible button existed to serve is on the row's own OnEnter too, so nothing is
-- lost by taking it down; AddButton re-shows it on the next build anyway.
--
-- SET ON EVERY ROW, not only the submenu ones. These list buttons are shared with every other
-- C_UIDropDownMenu in the game, so a row left motion-enabled is one that some later menu's disabled
-- title could hover-highlight. Passing `false` back is what keeps the leak from spreading.
--
-- …and then put the submenu where the row is, because letting the row open it exposed a second fault
-- underneath the first. ClassicAPI picks a level-2+ list's anchor like this (C_UIDropDownMenu.lua:397):
--
--     local anchorFrame = (strsub(button:GetParent():GetName(), 1, 12) == listFramePrefix)
--                          and button or button:GetParent()
--
-- Blizzard's original compared against the LITERAL "DropDownList" — exactly 12 characters. ClassicAPI
-- renamed the prefix to "C_DropDownList", which is 14, and left the 12 alone, so the test can never be
-- true and the anchor is always `button:GetParent()`. That stayed invisible while the arrow was the
-- only way in: an arrow's parent IS its row, which is the right answer by accident. A row's parent is
-- the whole LIST — so the submenu appeared pinned to the top of the parent menu, and only dropped into
-- place once the mouse crossed the arrow and re-opened it from there.
--
-- We re-anchor to the ARROW, not to the row that was actually hovered. The arrow is a 16x16 child
-- centred in a 16px row, so its TOPRIGHT is the row's TOPRIGHT and the placement is the same either
-- way — but the arrow's own OnEnter re-opens the menu unless it finds ITSELF as the anchor already
-- (C_UIDropDownMenu.xml:94), and anchoring to the row would rebuild the whole submenu every time the
-- mouse crossed the arrow on its way there.
local function anchorSubmenu(list, arrow)
  list:ClearAllPoints()
  list:SetPoint("TOPLEFT", arrow, "TOPRIGHT", 0, 0)

  -- The screen-bounds correction from ToggleDropDownMenu's own tail (line 429). It runs there against
  -- the wrong anchorFrame, so it has to run again here against the right one.
  local x, y = list:GetCenter()
  if not (x and y) then return end
  local offY = (y - list:GetHeight() / 2) < 0
  local offX = list:GetRight() > GetScreenWidth()
  if offY or offX then
    list:ClearAllPoints()
    list:SetPoint(offY and "BOTTOMRIGHT" or "TOPRIGHT", arrow, offY and "BOTTOMLEFT" or "TOPLEFT",
                  offX and -11 or 0, offY and -14 or 14)
  end
end

local function openOnHover(btn, level, wanted)
  if btn.SetMotionScriptsWhileDisabled then
    btn:SetMotionScriptsWhileDisabled(wanted and true or false)
  end
  if not wanted then return end

  local name = btn.GetName and btn:GetName()
  local inv = name and _G[name .. "InvisibleButton"]
  if inv then inv:Hide() end

  -- Hooked once and never removed — HookScript has no inverse — so the hook itself has to ask whose
  -- menu is open before it moves anything. The level is closed over rather than read back off the
  -- parent: a given button belongs to exactly one list forever, its name says which, and asking would
  -- mean depending on GetID for a number we already have.
  if name and not btn._neSubAnchor then
    btn._neSubAnchor = true
    btn:HookScript("OnEnter", function(self)
      local b = backend()
      if not (b and _G[b.openVar] == NE.menu._frame) then return end
      local list, arrow = _G[b.prefix .. (level + 1)], _G[self:GetName() .. "ExpandArrow"]
      if list and arrow and list:IsShown() and arrow:IsShown() then anchorSubmenu(list, arrow) end
    end)
  end
end

-- UIDropDownMenu calls this once per open level, handing back whatever we stashed in info.menuList
-- for the parent row. Stashing the node itself is what gives us arbitrary nesting for free.
local function initLevel(frame, level, menuList)
  local b = backend()
  if not b then return end
  level = level or 1
  local node = menuList or frame._neRoot
  if not node then return end

  for _, child in ipairs(node.children) do
    local info = b.CreateInfo()
    local kind = child.kind
    local hasKids = #child.children > 0

    if kind == "divider" then
      -- No divider primitive on this client. A disabled blank row reads as one.
      info.text, info.isTitle, info.notCheckable, info.disabled = " ", true, true, 1
    elseif kind == "title" then
      info.text, info.isTitle, info.notCheckable, info.disabled = child.text, true, true, 1
    elseif hasKids then
      info.text = child.text
      info.notCheckable = true
      info.hasArrow = true
      info.notClickable = true    -- see header: keeps OnClick from painting a stray check
      info.menuList = child
    elseif child.isSelected then
      info.text = child.text
      info.isRadio = (kind == "radio") or nil
      info.isNotRadio = (kind ~= "radio") or nil
      info.checked = child.isSelected(child.data) and true or false   -- boolean, see header
      info.keepShownOnClick = true
      info.func = function()
        if child.onClick then child.onClick(child.data) end
        refreshChecks(level)
      end
    else
      info.text = child.text
      info.notCheckable = true
      info.func = function() if child.onClick then child.onClick(child.data) end end
    end

    if child.tipTitle then
      info.tooltipTitle = child.tipTitle
      info.tooltipText = child.tipText
      info.tooltipOnButton = true
      info.tooltipWhileDisabled = true
    end

    b.AddButton(info, level)

    -- AddButton bumps numButtons; that is the index of the row it just wrote.
    local list = _G[b.prefix .. level]
    local btn = list and listButton(level, list.numButtons or 0)
    if btn then
      btn._neNode = child
      openOnHover(btn, level, hasKids)
    end
  end
end

-- One shared, never-shown anchor frame. UIDropDownMenu needs a "dropdown" object to hang the
-- initialize function and the open state off; it is not the thing the player sees.
local function anchorFrame()
  local b = backend()
  if not b then return nil end
  if NE.menu._frame then return NE.menu._frame end
  local f = CreateFrame("Frame", "NE_ContextMenu", UIParent, b.template)
  f:Hide()
  NE.menu._frame = f
  return f
end

function NE.menu.Close(level)
  local b = backend()
  if b and b.CloseAll then b.CloseAll(level or 1) end
end

-- ── Click-away to dismiss ───────────────────────────────────────────────────────────────────────
--
-- An open menu had exactly two ways out: pick a row, or press Escape. Clicking anywhere else left it
-- hanging, which is not how any other menu in the game behaves — Blizzard's own dropdowns are
-- dismissed by the click that lands outside them.
--
-- Nothing in the dropdown backend does this for us. ClassicAPI's C_DropDownList frames sit at
-- FULLSCREEN_DIALOG with SetToplevel, and the only auto-close they carry is the mouse-off timer that
-- applies to menus opened in MENU mode from a parent that is itself hovered — not to a menu opened by
-- clicking a button. So the dismiss is a full-screen mouse catcher, parked ONE frame level under the
-- open list: the list still takes its own clicks, and everything else on screen hits the catcher.
--
-- The click is CONSUMED, which is deliberate and is what Blizzard's dropdowns do — clicking away from
-- an open menu should close it, not close it and also press whatever was underneath.

local catcher

local function ensureCatcher()
  if catcher then return catcher end
  local f = CreateFrame("Frame", "NE_MenuClickCatcher", UIParent)
  f:SetAllPoints(UIParent)
  f:EnableMouse(true)
  f:Hide()
  f:SetScript("OnMouseDown", function(self)
    self:Hide()
    NE.menu.Close(1)
  end)
  catcher = f
  return f
end

-- Arm the catcher for whatever is open now. Called after a toggle, so it also has to notice that the
-- toggle CLOSED the menu — ToggleAnchored is a toggle, and arming a catcher over a screen with no
-- menu on it would eat one click for nothing.
local function armCatcher()
  local b = backend()
  local list = b and _G[b.prefix .. "1"]
  if not (list and list.IsShown and list:IsShown()) then
    if catcher then catcher:Hide() end
    return
  end
  local f = ensureCatcher()
  -- STRICTLY below the list, which means clamping the LIST up rather than the catcher down: at equal
  -- frame levels the click resolves by creation order, and a catcher that ties with the menu it is
  -- protecting would sometimes swallow the row the player was aiming at.
  local lvl = list:GetFrameLevel() or 2
  if lvl < 1 then list:SetFrameLevel(1); lvl = 1 end
  f:SetFrameStrata(list:GetFrameStrata())
  f:SetFrameLevel(lvl - 1)
  f:Show()
  -- The menu can close without going through us — a row picked, Escape, CloseAll from elsewhere — and
  -- a catcher left up would silently eat the next click anywhere on screen.
  if not list._neCatcherHooked then
    list._neCatcherHooked = true
    list:HookScript("OnHide", function() if catcher then catcher:Hide() end end)
  end
end

NE.menu._catcher = function() return catcher end   -- test seam

-- Open a cursor-anchored context menu. Always opens: closing first means right-clicking a second
-- item while the first item's menu is up switches to it instead of just dismissing.
function NE.menu.OpenContext(generator, owner, ...)
  local b, f = backend(), anchorFrame()
  if not (b and f) then return nil end
  f._neRoot = NE.menu.BuildRoot(generator, owner, ...)
  if not f._neRoot then return nil end
  f._neAnchor = nil
  b.CloseAll(1)
  b.Initialize(f, initLevel, "MENU")
  b.Toggle(1, nil, f, "cursor", 0, 0)
  armCatcher()
  return f
end

-- Open anchored to a frame, with toggle semantics — the cog-button behaviour, where clicking the
-- same button again dismisses. `spec` = { point, relativePoint, x, y }.
function NE.menu.ToggleAnchored(generator, anchor, spec, owner, ...)
  local b, f = backend(), anchorFrame()
  if not (b and f and anchor) then return nil end
  spec = spec or {}

  -- Reusing one anchor frame means "is a menu open?" is global. If the open one belongs to some
  -- other trigger, this click should switch to us, not dismiss theirs.
  if f._neAnchor ~= anchor then b.CloseAll(1) end
  f._neAnchor = anchor

  f._neRoot = NE.menu.BuildRoot(generator, owner, ...)
  if not f._neRoot then return nil end

  -- C_ToggleDropDownMenu reads these off the dropdown frame in preference to its arguments.
  f.point         = spec.point or "TOPRIGHT"
  f.relativePoint = spec.relativePoint or "BOTTOMRIGHT"
  f.relativeTo    = nil
  f.xOffset       = spec.x or 0
  f.yOffset       = spec.y or -2

  b.Initialize(f, initLevel, "MENU")
  b.Toggle(1, nil, f, anchor, f.xOffset, f.yOffset)
  armCatcher()
  return f
end

function NE.menu.IsAvailable() return backend() ~= nil end
