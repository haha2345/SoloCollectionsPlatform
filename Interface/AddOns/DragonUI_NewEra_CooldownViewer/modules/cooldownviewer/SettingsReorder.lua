-- DragonUI_NewEra/modules/cooldownviewer/SettingsReorder.lua — drag to reorder and reassign in the
-- /cdm panel. Downport of NewEra/CooldownViewerSettings/Reorder.lua (212 lines).
--
-- The flow, which is retail's:
--   OnDragStart  → lock and dim the source tile, show an icon on the cursor, start the driver.
--   OnUpdate     → the tile under the cursor is the drop target; a caret marks before/after it,
--                  and both caret and cursor icon go red over a category the move cannot reach.
--   release      → same category = reorder at the caret; different category = reassign at the
--                  caret; right button at any point = cancel.
--
-- THE ONE REAL DOWNPORT: `GLOBAL_MOUSE_UP` does not exist here (retail 9.x), and upstream uses it
-- six times to end the drag. But a drag ALREADY runs an OnUpdate to follow the cursor, so the
-- release is detected there instead, by watching IsMouseButtonDown transitions. Same two outcomes,
-- no event needed. `GetMouseFoci` → `GetMouseFocus` was already fallback-handled upstream.
--
-- EQUIP ROWS. A tile backed by a discovered trinket carries a `token`, and its move goes through
-- Adapter.AssignEquip rather than the spellID-keyed list rewrite. Reorder does not apply to one:
-- an equip row has no stored position — the viewer appends discovered items after the spells — so
-- dropping it inside its own category is a no-op rather than a silent nothing-happened-but-we-said-
-- it-did. Dragging a spell ONTO an equip row still reorders relative to the spells around it.
--
-- WHAT IS NOT PORTED: CDS.SetDragActive, which illuminates the "+" drop slots that this panel does
-- not have. Dropping on empty space therefore does nothing; drop onto a TILE, or onto a category's
-- HEADER, which resolves to that category on the walk up.

local NE = DragonUI_NewEra
local M  = NE.cooldownviewer

local CDS = NE.cooldownviewersettings
local Adapter = CDS.adapter

local state = { active = false, offset = 0 }
local dragFrame, marker

local QUESTION_MARK = "Interface\\Icons\\INV_Misc_QuestionMark"

-- 3.3.5a's SOUNDKIT carries a handful of names; the retail cursor kits are not among them. These
-- three are confirmed present in this client's own FrameXML. pcall + the willPlay return means an
-- unknown name is silence, never an error.
local function cue(name, fallback)
  if not (name and PlaySound) then return end
  local ok, willPlay = pcall(PlaySound, name)
  if not (ok and willPlay) and fallback then pcall(PlaySound, fallback) end
end

local CUE_PICKUP = "igMainMenuOptionCheckBoxOn"
local CUE_DROP   = "igMainMenuOptionCheckBoxOff"
local CUE_DENIED = "igQuestFailed"

local function mouseFocus()
  if GetMouseFoci then local t = GetMouseFoci(); return t and t[1] end
  if GetMouseFocus then return GetMouseFocus() end
  return nil
end

-- Walk up from the moused frame to the nearest tagged item, then category. A tile carries both a
-- spellID and a _catID; a category frame (and so its header, one level down) carries only _catID.
local function resolveUnderCursor()
  local f = mouseFocus()
  local item, cat
  while f do
    if (f.spellID or f.token) and f._catID then item = f; cat = f._catID; break end
    if f._catID then cat = f._catID; break end
    f = f.GetParent and f:GetParent()
  end
  return cat, item
end

local function ensureFrames()
  if dragFrame then return end

  dragFrame = CreateFrame("Frame", nil, UIParent)
  dragFrame:SetSize(38, 38)
  dragFrame:SetFrameStrata("TOOLTIP")
  dragFrame:Hide()
  dragFrame.icon = dragFrame:CreateTexture(nil, "OVERLAY")
  dragFrame.icon:SetAllPoints()
  dragFrame.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
  dragFrame.icon:SetAlpha(0.85)

  -- The caret. Retail uses its dock-highlight glow on ADD, which this client also ships.
  marker = (CDS.panel or UIParent):CreateTexture(nil, "OVERLAY")
  marker:SetTexture("Interface\\ChatFrame\\UI-ChatFrame-DockHighlight")
  marker:SetBlendMode("ADD")
  marker:Hide()

  CDS._dragFrame, CDS._dragMarker = dragFrame, marker   -- test seams
end

-- Put the caret before or after `target` depending on which side of its centre the cursor is on.
-- Icon grids split left/right; bar rows split top/bottom. Returns 0 = before, 1 = after.
local function placeMarker(target)
  local cx, cy = target:GetCenter()
  local mx, my = GetCursorPosition()
  local s = UIParent:GetEffectiveScale()
  if not (cx and mx and s and s > 0) then marker:Hide(); return 0 end
  mx, my = mx / s, my / s

  local w, h = target:GetWidth() or 38, target:GetHeight() or 38
  local isBar = w > 100
  marker:ClearAllPoints()
  marker:SetParent(target:GetParent())

  local after
  if isBar then
    after = my < cy                    -- lower half → drop below
    marker:SetSize(w, 6)
    marker:SetPoint("CENTER", target, "CENTER", 0, after and -(h / 2 + 3) or (h / 2 + 3))
  else
    after = mx > cx                    -- right half → drop after
    marker:SetSize(8, h + 8)
    marker:SetPoint("CENTER", target, "CENTER", after and (w / 2 + 4) or -(w / 2 + 4), 0)
  end
  marker:Show()
  return after and 1 or 0
end

-- Same category is always a legal drop (that is a reorder). No target at all is a no-op, so legal.
local function dropLegal(cat)
  if not cat or cat == state.fromCat then return true end
  return (Adapter.CanTarget and Adapter.CanTarget(state.fromCat, cat)) and true or false
end

local function updateMarker()
  local cat, item = resolveUnderCursor()
  state.targetCat, state.targetItem = cat, item

  -- Red cursor icon and red caret over a category this move cannot reach — retail's
  -- ReorderMarkerMixin:SetIsLegalTarget. Feedback before the drop, not an error after it.
  local legal = dropLegal(cat)
  local g, b = legal and 1 or 0.2, legal and 1 or 0.2
  if dragFrame and dragFrame.icon then dragFrame.icon:SetVertexColor(1, g, b) end

  if item and item ~= state.source then
    state.offset = placeMarker(item)
    if marker then marker:SetVertexColor(1, g, b) end
  else
    state.offset = 0
    if marker then marker:Hide() end
  end
end

local function clear()
  state.active = false
  if state.source then
    state.source:SetAlpha(1)
    if state.source.Icon and state.source.Icon.SetDesaturated then
      state.source.Icon:SetDesaturated(state.source._unlearned and true or false)
    end
  end
  state.source, state.spellID, state.token, state.fromCat = nil, nil, nil, nil
  state.targetCat, state.targetItem = nil, nil
  if dragFrame then
    dragFrame:SetScript("OnUpdate", nil)
    dragFrame:Hide()
    dragFrame.icon:SetVertexColor(1, 1, 1)
  end
  if marker then marker:Hide(); marker:SetVertexColor(1, 1, 1) end
end

CDS.CancelDrag = clear

local function endChange()
  local _, class = UnitClass("player")
  local targetCat, targetItem = state.targetCat, state.targetItem

  -- Illegal drop: a cue and no commit. The caret was already red, so this only confirms it.
  if targetCat and targetCat ~= state.fromCat and not dropLegal(targetCat) then
    cue(CUE_DENIED, CUE_DROP)
    clear()
    if CDS.RefreshLayout then CDS.RefreshLayout() end
    return
  end

  cue(CUE_DROP)

  local spellID, token, fromCat, offset = state.spellID, state.token, state.fromCat, state.offset
  local sameRow = targetItem and targetItem == state.source
  if targetCat and not sameRow then
    if token then
      -- An equip row: one assignment write, and only across a category boundary. It has no stored
      -- position, so a same-category drop has nothing to reorder.
      if targetCat ~= fromCat then Adapter.AssignEquip(token, fromCat, targetCat) end
    elseif targetCat == fromCat then
      -- Reorder relative to the target — but only against a row that HAS a stored position. An
      -- equip row is not in the list, so dropping a spell on one would find no index and no-op.
      if targetItem and targetItem.spellID and not targetItem.token then
        Adapter.ReorderTo(fromCat, spellID, targetItem.spellID, offset, class)
      end
    else
      -- Carry the drop POSITION across the category boundary: dropping onto a tile inserts at that
      -- caret, dropping onto a header appends.
      local dropID = targetItem and not targetItem.token and targetItem.spellID or nil
      Adapter.AssignAt(spellID, fromCat, targetCat, dropID, offset, class)
    end
  end

  clear()
  if CDS.RefreshLayout then CDS.RefreshLayout() end
end

-- The driver. Follows the cursor, tracks the drop target, and — the downport — decides when the
-- drag ended, because there is no GLOBAL_MOUSE_UP to tell us.
local function onUpdate(self)
  if not state.active then self:SetScript("OnUpdate", nil); return end

  -- Right button cancels outright, matching upstream's GLOBAL_MOUSE_UP RightButton branch.
  if IsMouseButtonDown and IsMouseButtonDown("RightButton") then clear(); return end

  local leftDown = IsMouseButtonDown and IsMouseButtonDown("LeftButton")
  if state.leftWasDown and not leftDown then endChange(); return end
  state.leftWasDown = leftDown

  local x, y = GetCursorPosition()
  local s = UIParent:GetEffectiveScale()
  if x and s and s > 0 then
    self:ClearAllPoints()
    self:SetPoint("CENTER", UIParent, "BOTTOMLEFT", x / s, y / s)
  end
  updateMarker()
end

CDS._dragOnUpdate = onUpdate   -- test seam
CDS._dragState    = state

function CDS.BeginDrag(item)
  if state.active then return end
  -- A trinket row has a token and may have no resolvable use-spell yet, so the token alone is
  -- enough to drag. A spell row needs its id.
  if not (item and (item.spellID or item.token) and item._catID) then return end
  ensureFrames()

  state.active, state.spellID, state.token, state.fromCat, state.source, state.offset =
    true, item.spellID, item.token, item._catID, item, 0
  state.targetCat, state.targetItem = item._catID, item
  -- OnDragStart only fires while the button is held, so the drag begins mid-press by definition.
  state.leftWasDown = true

  dragFrame.icon:SetTexture((item.Icon and item.Icon:GetTexture()) or QUESTION_MARK)
  dragFrame:Show()
  dragFrame:SetScript("OnUpdate", onUpdate)

  -- Lock the source so it reads as "in flight" rather than still sitting there.
  item:SetAlpha(0.5)
  if item.Icon and item.Icon.SetDesaturated then item.Icon:SetDesaturated(true) end

  cue(CUE_PICKUP)
end
