-- DragonUI_NewEra/modules/social/Raid.lua — the Raid tab (raid roster + convert-to-raid).
--
-- The native 3.3.5a Socials window carries a Raid tab. NewEra RESKINS the native RaidFrame that
-- Era claims into its FriendsFrame; we can't do that here (our window is a rebuild, and the native
-- frame's classic art would clash with the modern chrome), so the roster is built natively on the
-- classic API: GetNumRaidMembers / GetRaidRosterInfo / ConvertToRaid. Built from Window.lua via
-- SO.SetupRaid(f); exposes SO.RefreshRaid().

local NE = DragonUI_NewEra
if not NE then return end

NE.social = NE.social or {}
local SO = NE.social

local function classColor(classFile)
  local c = classFile and RAID_CLASS_COLORS and RAID_CLASS_COLORS[classFile]
  if c then return c.r, c.g, c.b end
  return 1, 0.82, 0
end

-- ---------------------------------------------------------------------------
-- Right-click context menu on a group slot (owner steer 2026-07-17: no menu existed on the group
-- grid at all). Same EasyMenu/UIDropDownMenu pattern as Friends.lua/Roster.lua/Who.lua.
--
-- Owner report 2026-08-02: Main Tank / Main Assist threw Blizzard errors. These calls take ONE
-- positional target on 3.3.5a -- a unit token OR a name -- with exactMatch after it:
--   PromoteToLeader("unit"|"name" [, exactMatch])
--   PromoteToAssistant("unit"|"name" [, exactMatch])
--   SetPartyAssignment("assignment", "unit"|"name" [, exactMatch])
-- They were being called in the (unit, name, exactMatch) form, i.e. with nil where the target
-- belongs and the name landing in exactMatch. That form is Cataclysm-and-later, which is what the
-- on-client APIDocumentation addon documents -- it ships retail signatures and does NOT describe
-- this client, so it can't be used to confirm an argument list on its own. The earlier comment here
-- also credited AddOns/Cell_Wrath/Utilities/RaidRosterFrame.lua with the same form; it does not use
-- it -- that file calls PromoteToAssistant(unit) / DemoteAssistant(unit) / UninviteUnit(name), one
-- argument each, and DBM-Core/DBM-InfoFrame.lua reads the assignments back as
-- GetPartyAssignment("MAINTANK", unit, 1) with exactMatch in the THIRD slot. Both are live and
-- working on this server, so that's the shape trusted here.
--
-- Owner report 2026-08-02, with a screenshot of ADDON_ACTION_BLOCKED ("blocked from an action only
-- available to the Blizzard UI"): with the signature corrected, Main Tank / Main Assist STILL fail,
-- because SetPartyAssignment is a PROTECTED function on this client. That's not something a call
-- site can fix -- addon code is tainted the moment it runs, hardware event or not, and a protected
-- function refuses a tainted execution path. There's no way around it either: 3.3.5a's secure
-- attribute list covers target/focus/assist/spell/item/macro/action/pet and has nothing for party
-- assignments, and routing through a Blizzard dropdown still carries our taint into the call.
-- So the two items are gone rather than left in to throw a popup every time.
--
-- Set Focus went with them, same cause -- FocusUnit is protected too. Nothing on this client calls
-- it directly; Cell_Wrath reaches focus through SetAttribute("unit", "focus") on a secure button
-- (RaidFrames/Groups/SpotlightFrame.lua), which is the only supported route and needs the slot
-- itself to be a SecureActionButton, not a menu entry.
--
-- What's left is what's actually callable. The APIDocumentation addon flags the protected ones with
-- a (commented-out) IsProtectedFunction line -- present on SetPartyAssignment/ClearPartyAssignment/
-- FocusUnit, absent on PromoteToLeader/PromoteToAssistant/UninviteUnit -- and that split matches
-- which calls live addons on this client are willing to make. Check that marker before adding
-- anything to this menu.
--
-- Promote/Remove items are only offered to a leader/assist, matching stock permission gating.
-- ---------------------------------------------------------------------------
local raidSlotMenuFrame

-- The unit token is the more precise target (no name collisions, no realm/locale quirks), but
-- "raidN" indices shift the moment anyone leaves, and the menu's closures run some time after the
-- right-click that built them. Take the token only while it still resolves to the name the menu was
-- opened on; otherwise fall back to the name, which stays valid regardless of roster order.
-- `name` is the one captured when the menu opened, not slot._name -- RefreshRaid blanks the slot's
-- copy on every roster change, and a nil target is what raised the Blizzard error in the first place.
local function raidTarget(slot, name)
  if slot._unit and UnitName and UnitName(slot._unit) == name then return slot._unit end
  return name
end

local function openRaidSlotMenu(slot)
  if not (EasyMenu and slot and slot._name) then return end
  if not raidSlotMenuFrame then
    raidSlotMenuFrame = CreateFrame("Frame", "NE_SocialRaidSlotMenu", UIParent, "UIDropDownMenuTemplate")
  end
  -- Everything the menu still offers is leader/assist-only, so for a rank-and-file member it would
  -- be a name and a Cancel button. Don't open it at all rather than pop an empty one.
  if not ((IsRaidLeader and IsRaidLeader()) or (IsRaidOfficer and IsRaidOfficer())) then return end

  local name = slot._name
  local menu = { { text = name, isTitle = true, notCheckable = true } }
  menu[#menu + 1] = { text = "Promote to Raid Leader", notCheckable = true, func = function()
      if PromoteToLeader then PromoteToLeader(raidTarget(slot, name), true) end
      SO.RefreshRaid()
    end }
  menu[#menu + 1] = { text = "Promote to Assistant", notCheckable = true, func = function()
      if PromoteToAssistant then PromoteToAssistant(raidTarget(slot, name), true) end
      SO.RefreshRaid()
    end }
  menu[#menu + 1] = { text = REMOVE or "Remove", notCheckable = true, func = function()
      -- Name, not the token, matching Cell_Wrath: an uninvite that lands on the wrong raid index
      -- is the one misfire here you can't take back.
      if UninviteUnit then UninviteUnit(name) end
      SO.RefreshRaid()
    end }
  menu[#menu + 1] = { text = CANCEL or "Cancel", notCheckable = true }
  EasyMenu(menu, raidSlotMenuFrame, "cursor", 0, 0, "MENU")
end

-- ---------------------------------------------------------------------------
-- Saved Instances (raid lockouts) — a toggled POPUP hung off a "Raid Info" button, the way stock
-- 3.3.5a does it (RaidFrameRaidInfoButton toggles RaidInfoFrame, parked off the Socials window's
-- right edge).
--
-- Owner report 2026-07-29 (issue #45, "Too many raid lockouts overflow"): the previous pass drew
-- lockouts INLINE at the top of the Raid tab as one wrapped FontString inside a fixed 60px block.
-- A FontString isn't clipped by its parent frame, so a player saved to more instances than fit
-- simply drew past the block's bottom edge and over the group grid below. A SCROLLING list in its
-- own window can't overflow no matter how many lockouts there are, which is why stock put this
-- behind a button in the first place.
--
-- 3.3.5a API (confirmed via the on-client APIDocumentation addon,
-- Documentation/InstanceDocumentation.lua -- this build's GetSavedInstanceInfo has no
-- numEncounters/encounterProgress, that's a later/retail addition to the same-named API):
--   GetNumSavedInstances() -> count
--   GetSavedInstanceInfo(index) -> name, id, reset, difficulty, locked, extended,
--                                   instanceIDMostSig, isRaid, maxPlayers, difficultyName
-- RequestRaidInfo() asks the server to (re)send this; UPDATE_INSTANCE_INFO fires on arrival.
-- SetSavedInstanceExtend(index, extend) backs the Extend button (documented on this client under
-- Documentation/UncategorizedDocumentation.lua, args undocumented there — stock's signature).
-- Probed at runtime like every other optional API in this addon: where it doesn't exist the
-- button (and row selection with it) is simply never built and the popup stays a read-only list.
-- ---------------------------------------------------------------------------
local INFO_W, INFO_H = 340, 330
local INFO_ROWS      = 12
local INFO_ROW_H     = 18
local INFO_BOTTOM    = 44   -- clearance for the Extend button; trimmed when the API is missing

local function formatReset(seconds)
  seconds = tonumber(seconds) or 0
  if seconds <= 0 then return "Expired" end
  local h = math.floor(seconds / 3600)
  local d = math.floor(h / 24)
  if d > 0 then return string.format("%dd %dh", d, h - d * 24) end
  if h > 0 then return string.format("%dh %dm", h, math.floor((seconds % 3600) / 60)) end
  return string.format("%dm", math.floor(seconds / 60))
end

local function canExtend()
  return type(SetSavedInstanceExtend) == "function"
end

-- Stock RaidInfoFrame lists every saved instance the server sent, raids AND heroic dungeons, not
-- just raids (the inline block filtered to isRaid because it had ~3 lines of room; the popup
-- doesn't). Entries that are neither locked nor extended are dead rows — skip those.
local function collectSavedInstances()
  local out = {}
  if not (GetNumSavedInstances and GetSavedInstanceInfo) then return out end
  local n = GetNumSavedInstances() or 0
  for i = 1, n do
    local name, id, reset, _, locked, extended, _, isRaid, maxPlayers, difficultyName = GetSavedInstanceInfo(i)
    if name and (locked or extended) then
      out[#out + 1] = {
        index = i, name = name, id = id, reset = reset, extended = extended and true or false,
        isRaid = isRaid, maxPlayers = maxPlayers, difficultyName = difficultyName,
      }
    end
  end
  return out
end

local function instanceLabel(e)
  if e.difficultyName and e.difficultyName ~= "" then
    return e.name .. " (" .. e.difficultyName .. ")"
  end
  if e.maxPlayers and e.maxPlayers > 0 then
    return string.format("%s (%d)", e.name, e.maxPlayers)
  end
  return e.name
end

local function buildRaidInfoFrame(f, panel)
  -- Parented to `panel` (the Raid tab) so it hides with the tab and the window, exactly like the
  -- Ready Check button below; anchored off the WINDOW's right edge, which is where stock parks
  -- RaidInfoFrame. Frame level is lifted well clear of the window (and of the Guild window, which
  -- auto-anchors into this same space when both are open — see SO.Show in Window.lua).
  local frame = CreateFrame("Frame", "NE_SocialRaidInfoFrame", panel)
  frame:SetSize(INFO_W, INFO_H)
  frame:SetPoint("TOPLEFT", f, "TOPRIGHT", 4, -24)
  frame:SetFrameStrata("DIALOG")
  frame:SetFrameLevel((f:GetFrameLevel() or 1) + 30)
  frame:EnableMouse(true)
  frame:Hide()

  if NE.chrome and NE.chrome.Apply then
    NE.chrome.Apply(frame, {
      layout = "ButtonFrameTemplateNoPortrait",
      title = RAID_INFO or "Raid Info",
      noPortrait = true,
    })
  end
  -- Square-corner chrome, left-edge sliver (owner report 2026-07-29, "as per previous times when we
  -- use the square corners the frames background is sticking out 4px to the left"). PC's ensureBg
  -- insets the rock fill by 1px on each side, which is tuned for PortraitFrameTemplate; the
  -- ButtonFrameTemplateNoPortrait metal draws its corners/edges at x=-8 (left) vs x=+4 (right), so
  -- its opaque coverage falls INSIDE the frame's nominal left edge and the fill pokes out past it.
  -- 4px is the measured left inset that fixes it — same value, same layout, as
  -- modules/guild/Window.lua:buildChrome (which also confirmed pushing the fill OUTWARD makes the
  -- sliver bigger, not smaller). Right/bottom stay at PC's defaults; no sliver reported there.
  -- Outer frame area (owner steer 2026-07-29): the tiled UI-Background-Rock STONE fill every other
  -- NE window carries — see this module's own Window.lua:buildChrome, and guild/AH, which all lay
  -- the sheet down untinted starting 21px below the frame top (the top metal band + streaks own
  -- that strip). PC.ApplyModernChrome's own Bg is the same sheet but pulled to 32% brightness for
  -- panels that sit UNDER a dark content inset, which next to those windows reads as flat black.
  if frame.Bg then
    local rockPath = NE.tex and NE.tex.localFiles and NE.tex.localFiles[374155]
    frame.Bg:SetTexture(rockPath or 374155, "REPEAT", "REPEAT")
    frame.Bg:SetHorizTile(true); frame.Bg:SetVertTile(true)
    frame.Bg:SetVertexColor(1, 1, 1)
    frame.Bg:ClearAllPoints()
    frame.Bg:SetPoint("TOPLEFT", frame, "TOPLEFT", 4, -21)
    frame.Bg:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -1, 2)
  end
  if frame.CloseButton then
    frame.CloseButton:SetScript("OnClick", function() frame:Hide() end)
  end
  -- PC.TitleBand starts at x+58 to clear a portrait cutout this window doesn't have, which on a
  -- frame only 340 wide throws the centred title visibly right. Re-centre it on the frame itself.
  if frame.Title then
    frame.Title:ClearAllPoints()
    frame.Title:SetPoint("TOP",   frame, "TOP",    0, -6)
    frame.Title:SetPoint("LEFT",  frame, "LEFT",  24,  0)
    frame.Title:SetPoint("RIGHT", frame, "RIGHT", -24, 0)
  end

  local bottom = canExtend() and INFO_BOTTOM or 16

  -- Column headers, sitting just above the list inset.
  -- Literal English labels, like the rest of this file's own strings: the plausible-looking
  -- globals here (INSTANCE / TIME_REMAINING / RAID_INFO_EXTEND) are NOT confirmed to exist on this
  -- client, and a global that turns out to be a format template would render as a raw "%s".
  -- RAID_INFO is the exception — it's a real 3.3.5a string ("Raid Info").
  local hName = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  hName:SetPoint("TOPLEFT", frame, "TOPLEFT", 18, -30)
  hName:SetText("Instance")
  hName:SetTextColor(1, 0.82, 0)

  local hReset = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  hReset:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -34, -30)
  hReset:SetText("Resets In")
  hReset:SetTextColor(1, 0.82, 0)

  -- Dark recessed list well, same treatment as the tab panels themselves.
  local content = CreateFrame("Frame", nil, frame)
  content:SetPoint("TOPLEFT", frame, "TOPLEFT", 12, -46)
  content:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -12, bottom)
  local contentBg = content:CreateTexture(nil, "BACKGROUND")
  contentBg:SetTexture("Interface\\Buttons\\WHITE8X8")
  contentBg:SetVertexColor(0.06, 0.06, 0.07, 0.75)
  contentBg:SetAllPoints(content)
  if NE.nineslice and NE.nineslice.AttachInset then pcall(NE.nineslice.AttachInset, content, 0, 0, 0, 0) end

  local scroll = CreateFrame("ScrollFrame", "NE_SocialRaidInfoScroll", content, "FauxScrollFrameTemplate")
  scroll:SetPoint("TOPLEFT", content, "TOPLEFT", 4, -4)
  scroll:SetPoint("BOTTOMRIGHT", content, "BOTTOMRIGHT", -26, 4)
  scroll:SetScript("OnVerticalScroll", function(self, o)
    FauxScrollFrame_OnVerticalScroll(self, o, INFO_ROW_H, SO.RefreshSavedInstances)
  end)
  frame.Scroll = scroll
  scroll.ScrollBar = _G["NE_SocialRaidInfoScrollScrollBar"]   -- 3.3.5a template sets no parentKey
  if NE.scrollbar and NE.scrollbar.Reskin then NE.scrollbar.Reskin(scroll) end

  -- Rows are children of `content`, NOT of the scroll frame, so they are not clipped — the usual
  -- caveat for this addon's FauxScrollFrame lists: INFO_ROWS * INFO_ROW_H must stay inside the
  -- well (236px tall with the Extend button present; 12 * 18 = 216).
  frame.Rows = {}
  for i = 1, INFO_ROWS do
    local row = CreateFrame("Button", nil, content)
    row:SetHeight(INFO_ROW_H)
    if i == 1 then row:SetPoint("TOPLEFT", scroll, "TOPLEFT", 0, 0)
    else row:SetPoint("TOPLEFT", frame.Rows[i - 1], "BOTTOMLEFT", 0, 0) end
    row:SetPoint("RIGHT", scroll, "RIGHT", 0, 0)
    row:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")

    local sel = row:CreateTexture(nil, "BACKGROUND")
    sel:SetTexture("Interface\\Buttons\\WHITE8X8")
    sel:SetVertexColor(1, 0.82, 0, 0.18)
    sel:SetAllPoints(row)
    sel:Hide()
    row.Sel = sel

    local nameFS = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    nameFS:SetPoint("LEFT", row, "LEFT", 4, 0)
    nameFS:SetPoint("RIGHT", row, "RIGHT", -78, 0)
    nameFS:SetJustifyH("LEFT"); nameFS:SetWordWrap(false)
    row.Name = nameFS

    local resetFS = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    resetFS:SetPoint("RIGHT", row, "RIGHT", -4, 0)
    resetFS:SetJustifyH("RIGHT")
    row.Reset = resetFS

    -- Stock carries an ID column; this window is too narrow for one, so the raid ID (what players
    -- actually need when linking/verifying a lockout) goes in the row tooltip instead.
    row:SetScript("OnEnter", function(self)
      if not (self._entry and GameTooltip) then return end
      GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
      GameTooltip:SetText(instanceLabel(self._entry), 1, 0.82, 0)
      if self._entry.id then GameTooltip:AddLine("ID: " .. tostring(self._entry.id), 1, 1, 1) end
      GameTooltip:AddLine(formatReset(self._entry.reset), 1, 1, 1)
      if self._entry.extended then GameTooltip:AddLine("Extended", 0.25, 1, 0.25) end
      GameTooltip:Show()
    end)
    row:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)

    if canExtend() then
      row:SetScript("OnClick", function(self)
        if not self._entry then return end
        frame._selected = self._entry.index
        SO.RefreshSavedInstances()
      end)
    else
      row:EnableMouse(true)   -- tooltip only; no selection without the extend API
    end

    row:Hide()
    frame.Rows[i] = row
  end

  local empty = content:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  empty:SetPoint("TOP", content, "TOP", 0, -12)
  empty:SetText("You are not saved to any instances.")
  empty:Hide()
  frame.Empty = empty

  if canExtend() then
    local ext = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    ext:SetSize(140, 22)
    ext:SetPoint("BOTTOM", frame, "BOTTOM", 0, 12)
    ext:SetText("Extend")
    ext:Disable()
    ext:SetScript("OnClick", function()
      local e = frame._selectedEntry
      if not e then return end
      pcall(SetSavedInstanceExtend, e.index, not e.extended)
      if RequestRaidInfo then RequestRaidInfo() end   -- UPDATE_INSTANCE_INFO re-runs the refresh
      SO.RefreshSavedInstances()
    end)
    frame.Extend = ext
  end

  panel.RaidInfo = frame
  f.RaidInfo = frame
  return frame
end

function SO.RefreshSavedInstances()
  local f = SO.frame
  local frame = f and f.RaidInfo
  if not (frame and frame.Rows) then return end

  local list = collectSavedInstances()
  local offset = FauxScrollFrame_GetOffset(frame.Scroll) or 0

  -- Drop a selection whose lockout has since gone away (expired, or the list re-indexed).
  local selectedEntry
  for _, e in ipairs(list) do
    if e.index == frame._selected then selectedEntry = e end
  end
  if not selectedEntry then frame._selected = nil end
  frame._selectedEntry = selectedEntry

  for i = 1, INFO_ROWS do
    local row = frame.Rows[i]
    local e = list[offset + i]
    row._entry = e
    if e then
      row.Name:SetText(instanceLabel(e))
      row.Reset:SetText(formatReset(e.reset))
      if e.extended then
        row.Name:SetTextColor(0.25, 1, 0.25)
        row.Reset:SetTextColor(0.25, 1, 0.25)
      else
        row.Name:SetTextColor(1, 1, 1)
        row.Reset:SetTextColor(0.8, 0.8, 0.8)
      end
      -- Explicit Show/Hide rather than the retail one-call setter, which qa/staticcheck flags as a
      -- 3.3.5a trap (it only works here at all because ClassicAPI shims it onto every region).
      if frame._selected == e.index then row.Sel:Show() else row.Sel:Hide() end
      row:Show()
    else
      row.Sel:Hide()
      row:Hide()
    end
  end
  FauxScrollFrame_Update(frame.Scroll, #list, INFO_ROWS, INFO_ROW_H)
  if #list == 0 then frame.Empty:Show() else frame.Empty:Hide() end

  if frame.Extend then
    if selectedEntry then
      frame.Extend:Enable()
      frame.Extend:SetText(selectedEntry.extended and "Cancel Extend" or "Extend")
    else
      frame.Extend:Disable()
      frame.Extend:SetText("Extend")
    end
  end
end

-- Toggled by the Raid tab's Raid Info button (and re-asked from the server on each open, since
-- lockout timers only advance client-side between UPDATE_INSTANCE_INFO pushes).
function SO.ToggleRaidInfo()
  local f = SO.frame
  local frame = f and f.RaidInfo
  if not frame then return end
  if frame:IsShown() then
    frame:Hide()
  else
    if RequestRaidInfo then RequestRaidInfo() end
    SO.RefreshSavedInstances()
    frame:Show()
  end
end

-- ---------------------------------------------------------------------------
-- Raid roster: grouped grid (owner report 2026-07-17, with a screenshot of the default UI: "The
-- raid tab should be in groups" -- the flat Name/Level/Class/Group/Zone table didn't match the
-- stock RaidFrame's Group 1-8 layout). 8 groups x 5 slots (the WotLK 40-man raid cap), laid out 2
-- columns x 4 rows -- odd groups (1/3/5/7) left, even groups (2/4/6/8) right -- matching the
-- reference screenshot. Always visible (not swapped for an empty-state blurb): the stock frame
-- shows all 8 groups, slots reading "Empty", even with zero raid members.
-- ---------------------------------------------------------------------------
local NUM_GROUPS      = 8
local SLOTS_PER_GROUP = 5
local GROUP_HEADER_H  = 16
-- SLOT_H 13->12, GROUP_GAP_Y 6->4->3 (owner report 2026-07-17: the class summary strip moved below
-- the grid, and later enlarged + pushed down further, needs pixels reclaimed from the grid each
-- time to avoid overlapping the outer-chrome buttons). 2026-07-29: the inline lockout block moved
-- out to the Raid Info popup, handing 60px back — spent on the rows, which had been squeezed
-- tightest of anything here. 4 * (16 + 5*14) + 3 * 6 = 362px of content in the 374px the grid now
-- spans (panel 468 tall, less the 22 top offset and the 72 reserved for the class strip below).
local SLOT_H          = 14
local GROUP_BOX_H     = GROUP_HEADER_H + SLOTS_PER_GROUP * SLOT_H
local GROUP_GAP_Y     = 6
local COL_GAP_X       = 8
local LEFT_GROUPS  = { 1, 3, 5, 7 }
local RIGHT_GROUPS = { 2, 4, 6, 8 }

local LEADER_ICON  = "Interface\\GroupFrame\\UI-Group-LeaderIcon"
local ASSIST_ICON  = "Interface\\GroupFrame\\UI-Group-AssistantIcon"
local EMPTY_LABEL  = EMPTY or "Empty"

-- ---------------------------------------------------------------------------
-- Drag-and-drop group assignment, matching the stock RaidFrame: pick a name up off a slot and drop
-- it on another group. Leader/assist only -- the server rejects the move either way, but gating the
-- drag itself stops everyone else dragging names around to no visible effect.
--
-- Resolves the drop target with GetMouseFocus() in OnDragStop, the way Blizzard's own
-- RaidGroupButton does, rather than OnReceiveDrag -- that event is for things the cursor is
-- literally holding (items, spells, macros), not frame-to-frame drags, and never fires here.
-- Since we don't detach and float the slot itself the way the stock frame does, a small ghost
-- label follows the cursor instead so there's something to see mid-drag.
--
-- The two moves are different API calls: an empty target slot means the group has room, so the
-- player just changes subgroup (SetRaidSubgroup); an occupied one means the two trade places
-- (SwapRaidSubgroup). Both take raid roster indices (slot._index, set in RefreshRaid), not names.
-- ---------------------------------------------------------------------------
local dragSource     -- slot the drag started from, nil when no drag is in progress
local dropGlowSlot   -- slot currently showing the drop-target tint
local dragGhost

local function canManageRaid()
  return ((IsRaidLeader and IsRaidLeader()) or (IsRaidOfficer and IsRaidOfficer())) and true or false
end

local function getDragGhost()
  if dragGhost then return dragGhost end
  local g = CreateFrame("Frame", nil, UIParent)
  g:SetFrameStrata("TOOLTIP")
  g:SetHeight(16)
  g:EnableMouse(false)   -- must never come back from the GetMouseFocus() in onSlotDragStop
  g:Hide()
  local bg = g:CreateTexture(nil, "BACKGROUND")
  bg:SetTexture("Interface\\Buttons\\WHITE8X8")
  bg:SetVertexColor(0, 0, 0, 0.7)
  bg:SetAllPoints(g)
  g.text = g:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  g.text:SetPoint("CENTER", g, "CENTER", 0, 0)
  -- Cursor coords come back in screen pixels; divide by the frame's effective scale to place it.
  g:SetScript("OnUpdate", function(self)
    local x, y = GetCursorPosition()
    local scale = self:GetEffectiveScale()
    self:ClearAllPoints()
    self:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", x / scale + 14, y / scale - 8)
  end)
  dragGhost = g
  return g
end

local function setDropGlow(slot)
  if dropGlowSlot == slot then return end
  if dropGlowSlot and dropGlowSlot.dropGlow then dropGlowSlot.dropGlow:Hide() end
  dropGlowSlot = slot
  if slot and slot.dropGlow then slot.dropGlow:Show() end
end

-- Dropping inside the source's own group is a no-op (slot order within a box is just our fill
-- order, not anything the server tracks), so those slots don't light up as targets.
local function isDropTarget(slot)
  return dragSource ~= nil
     and slot ~= dragSource
     and slot._group ~= dragSource._group
end

local function endDrag()
  setDropGlow(nil)
  if dragSource then
    dragSource:SetAlpha(1)
    dragSource = nil
  end
  if dragGhost then dragGhost:Hide() end
end

-- Roster indices are only good for as long as the roster holds still; someone leaving mid-drag
-- shifts everyone below them up. Re-check the name at each index before acting on it so a
-- stale index can't move the wrong player.
local function indexStillHolds(slot)
  if not (slot and slot._index and slot._name) then return false end
  local name = GetRaidRosterInfo and GetRaidRosterInfo(slot._index)
  return name == slot._name
end

local function onSlotDragStart(self)
  if not (self._name and self._index) then return end
  if not canManageRaid() then return end
  dragSource = self
  self:SetAlpha(0.4)
  local ghost = getDragGhost()
  ghost.text:SetText(self._name)
  ghost:SetWidth(ghost.text:GetStringWidth() + 12)
  ghost:Show()
end

local function onSlotDragStop(self)
  local source = dragSource
  local target = GetMouseFocus and GetMouseFocus()
  endDrag()

  if not (source and target and target._isRaidSlot) then return end
  if target == source or target._group == source._group then return end
  if not canManageRaid() then return end
  if not indexStillHolds(source) then return end

  if target._name then
    if indexStillHolds(target) and SwapRaidSubgroup then
      SwapRaidSubgroup(source._index, target._index)
    end
  elseif SetRaidSubgroup then
    SetRaidSubgroup(source._index, target._group)
  end
  -- No manual refresh: the move fires RAID_ROSTER_UPDATE, which repaints the grid (see `ev` below).
end

local function buildGroupBox(col, groupIndex, stackPos)
  local box = CreateFrame("Frame", nil, col)
  local y = -(stackPos - 1) * (GROUP_BOX_H + GROUP_GAP_Y)
  box:SetPoint("TOPLEFT", col, "TOPLEFT", 0, y)
  box:SetPoint("TOPRIGHT", col, "TOPRIGHT", 0, y)
  box:SetHeight(GROUP_BOX_H)

  local hdrBg = box:CreateTexture(nil, "BACKGROUND")
  hdrBg:SetTexture("Interface\\Buttons\\WHITE8X8")
  hdrBg:SetVertexColor(0.10, 0.10, 0.12, 0.95)
  hdrBg:SetPoint("TOPLEFT", box, "TOPLEFT", 0, 0)
  hdrBg:SetPoint("TOPRIGHT", box, "TOPRIGHT", 0, 0)
  hdrBg:SetHeight(GROUP_HEADER_H)

  local label = box:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  label:SetPoint("LEFT", box, "TOPLEFT", 4, -GROUP_HEADER_H / 2)
  label:SetText((GROUP or "Group") .. " " .. groupIndex)
  label:SetTextColor(1, 0.82, 0)

  local bodyBg = box:CreateTexture(nil, "BACKGROUND")
  bodyBg:SetTexture("Interface\\Buttons\\WHITE8X8")
  bodyBg:SetVertexColor(0.04, 0.04, 0.05, 0.6)
  bodyBg:SetPoint("TOPLEFT", box, "TOPLEFT", 0, -GROUP_HEADER_H)
  bodyBg:SetPoint("BOTTOMRIGHT", box, "BOTTOMRIGHT", 0, 0)

  box.slots = {}
  for s = 1, SLOTS_PER_GROUP do
    -- Button, not a plain Frame (owner steer 2026-07-17: right-click menu needs click detection).
    local slot = CreateFrame("Button", nil, box)
    slot:SetHeight(SLOT_H)
    slot:SetPoint("TOPLEFT", box, "TOPLEFT", 0, -GROUP_HEADER_H - (s - 1) * SLOT_H)
    slot:SetPoint("TOPRIGHT", box, "TOPRIGHT", 0, -GROUP_HEADER_H - (s - 1) * SLOT_H)
    slot._isRaidSlot = true     -- GetMouseFocus() sentinel for the drop handler
    slot._group = groupIndex
    slot:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    slot:RegisterForDrag("LeftButton")
    slot:SetScript("OnClick", function(self, button)
      if button == "RightButton" and self._name then openRaidSlotMenu(self) end
    end)
    slot:SetScript("OnDragStart", onSlotDragStart)
    slot:SetScript("OnDragStop", onSlotDragStop)
    -- Hover highlight on the slot itself (owner report 2026-07-17: slots had none — every other
    -- list in this addon highlights on hover, e.g. Friends/Who/Guild Roster rows via this same
    -- texture+ADD). Also shows the unit's tooltip, using the real raid-roster unit token (set in
    -- RefreshRaid as slot._unit — "raidN") so GameTooltip:SetUnit resolves health/buffs/etc.
    slot:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
    slot:SetScript("OnEnter", function(self)
      if isDropTarget(self) then setDropGlow(self) end
      if self._unit and UnitExists and UnitExists(self._unit) and GameTooltip then
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetUnit(self._unit)
      end
    end)
    slot:SetScript("OnLeave", function(self)
      if dropGlowSlot == self then setDropGlow(nil) end
      if GameTooltip then GameTooltip:Hide() end
    end)

    if s % 2 == 0 then
      local stripe = slot:CreateTexture(nil, "ARTWORK")
      stripe:SetTexture("Interface\\Buttons\\WHITE8X8")
      stripe:SetVertexColor(1, 1, 1, 0.03)
      stripe:SetAllPoints(slot)
    end

    -- Drop-target tint. Its own texture rather than poking the highlight one, which the button
    -- re-drives off its mouseover state and would clear out from under us. ARTWORK (created before
    -- the name fontstring, which is OVERLAY) so it tints behind the text.
    local dropGlow = slot:CreateTexture(nil, "ARTWORK")
    dropGlow:SetTexture("Interface\\Buttons\\WHITE8X8")
    dropGlow:SetVertexColor(1, 0.82, 0, 0.28)
    dropGlow:SetAllPoints(slot)
    dropGlow:Hide()
    slot.dropGlow = dropGlow

    local icon = slot:CreateTexture(nil, "OVERLAY")
    icon:SetSize(10, 10)
    icon:SetPoint("LEFT", slot, "LEFT", 3, 0)
    icon:Hide()
    slot.icon = icon

    local fs = slot:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    fs:SetPoint("LEFT", slot, "LEFT", 15, 0)
    fs:SetPoint("RIGHT", slot, "RIGHT", -3, 0)
    fs:SetJustifyH("LEFT"); fs:SetWordWrap(false)
    slot.text = fs

    box.slots[s] = slot
  end

  return box
end

-- Class icon summary strip. Owner report 2026-07-17: parked just outside the window's right edge
-- (the first placement), it was "very hard to see" — moved to a horizontal row directly below the
-- group grid instead, fully inside the visible panel. Still non-interactive: one icon per class
-- with a count of how many raid members are that class, no click/filter behavior. Reuses the same
-- class-icon sheet + coords as Guild Roster's class column (CLASS_ICON_TCOORDS is a stock global).
-- Sizes bumped (owner report 2026-07-17: "move the class icons down a bit and make them a little
-- larger") — icon 16->20, gap below the grid 4->10, strip/item sizes grown to match.
local CLASS_ICON_TEX  = "Interface\\Glues\\CharacterCreate\\UI-CharacterCreate-Classes"
local CLASS_ICON_SIZE = 20
local CLASS_STRIP_H   = 28
local CLASS_STRIP_GAP = 10
local CLASS_ITEM_W    = 40
local ORDERED_CLASSES = {
  "WARRIOR", "PALADIN", "HUNTER", "ROGUE", "PRIEST",
  "DEATHKNIGHT", "SHAMAN", "MAGE", "WARLOCK", "DRUID",
}

local function buildClassSummary(panel, grid)
  local strip = CreateFrame("Frame", nil, panel)
  strip:SetSize(CLASS_ITEM_W * #ORDERED_CLASSES, CLASS_STRIP_H)
  strip:SetPoint("TOP", grid, "BOTTOM", 0, -CLASS_STRIP_GAP)
  panel.ClassSummaryStrip = strip

  panel._classIcons = {}
  local prev
  for _, classFile in ipairs(ORDERED_CLASSES) do
    local row = CreateFrame("Frame", nil, strip)
    row:SetSize(CLASS_ITEM_W, CLASS_STRIP_H)
    row:EnableMouse(true)
    if prev then row:SetPoint("LEFT", prev, "RIGHT", 0, 0)
    else row:SetPoint("LEFT", strip, "LEFT", 0, 0) end
    prev = row

    local icon = row:CreateTexture(nil, "ARTWORK")
    icon:SetSize(CLASS_ICON_SIZE, CLASS_ICON_SIZE)
    icon:SetPoint("LEFT", row, "LEFT", 2, 0)
    local c = CLASS_ICON_TCOORDS and CLASS_ICON_TCOORDS[classFile]
    if c then
      icon:SetTexture(CLASS_ICON_TEX)
      icon:SetTexCoord(c[1], c[2], c[3], c[4])
    end

    local count = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    count:SetPoint("LEFT", icon, "RIGHT", 2, 0)

    row:SetScript("OnEnter", function(self)
      GameTooltip:SetOwner(self, "ANCHOR_TOP")
      GameTooltip:SetText((LOCALIZED_CLASS_NAMES_MALE and LOCALIZED_CLASS_NAMES_MALE[classFile]) or classFile)
      GameTooltip:Show()
    end)
    row:SetScript("OnLeave", function() GameTooltip:Hide() end)

    panel._classIcons[classFile] = { icon = icon, count = count }
  end

  return strip
end

-- Owner steer 2026-07-17: "the group frames on the raid tab should sit inside the inset by 15px" —
-- the boxes were flush against the panel's own dark-inset border on the left/right.
local GRID_SIDE_INSET = 15

local function buildGroupGrid(panel)
  local grid = CreateFrame("Frame", nil, panel)
  grid:SetPoint("TOPLEFT", panel, "TOPLEFT", GRID_SIDE_INSET, -22)
  grid:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -GRID_SIDE_INSET, 34 + CLASS_STRIP_GAP + CLASS_STRIP_H)
  panel.Grid = grid

  local leftCol = CreateFrame("Frame", nil, grid)
  leftCol:SetPoint("TOPLEFT", grid, "TOPLEFT", 0, 0)
  leftCol:SetPoint("BOTTOMLEFT", grid, "BOTTOMLEFT", 0, 0)
  leftCol:SetPoint("RIGHT", grid, "CENTER", -COL_GAP_X / 2, 0)

  local rightCol = CreateFrame("Frame", nil, grid)
  rightCol:SetPoint("TOPRIGHT", grid, "TOPRIGHT", 0, 0)
  rightCol:SetPoint("BOTTOMRIGHT", grid, "BOTTOMRIGHT", 0, 0)
  rightCol:SetPoint("LEFT", grid, "CENTER", COL_GAP_X / 2, 0)

  panel._groupBoxes = {}
  for i, g in ipairs(LEFT_GROUPS) do
    panel._groupBoxes[g] = buildGroupBox(leftCol, g, i)
  end
  for i, g in ipairs(RIGHT_GROUPS) do
    panel._groupBoxes[g] = buildGroupBox(rightCol, g, i)
  end

  return grid
end

function SO.SetupRaid(f)
  local panel = f.RaidPanel
  if not panel or panel._built then return end
  panel._built = true

  -- Dark recessed backdrop (owner steer 2026-07-17: "Who, Chat and Raid tabs should have the dark
  -- inset frames" — same treatment already used for Friends/Roster).
  local panelBg = panel:CreateTexture(nil, "BACKGROUND")
  panelBg:SetTexture("Interface\\Buttons\\WHITE8X8")
  panelBg:SetVertexColor(0.06, 0.06, 0.07, 0.75)
  panelBg:SetAllPoints(panel)
  panel.Bg = panelBg
  if NE.nineslice and NE.nineslice.AttachInset then pcall(NE.nineslice.AttachInset, panel, 0, 0, 0, 0) end

  local grid = buildGroupGrid(panel)
  buildClassSummary(panel, grid)
  buildRaidInfoFrame(f, panel)

  -- Ready Check (owner steer 2026-07-17, marked with a screenshot annotation in the chrome gap
  -- under the title). Parented to `panel` (so it shows/hides with the Raid tab like everything
  -- else here) but anchored off the WINDOW frame, since that gap sits above the panel's own top
  -- edge (panel content starts 56px down; the title text itself only runs to about -20).
  -- DoReadyCheck() (confirmed via the on-client APIDocumentation addon, PartyDocumentation.lua /
  -- RaidDocumentation.lua) works for both a party and a raid; only the leader/an assist can call it,
  -- so the button is enabled/disabled the same way Convert to Raid already is.
  -- Owner steer 2026-07-29 (issue #45): Raid Info sits to its RIGHT, so the pair is centered as a
  -- unit rather than Ready Check staying centered with Raid Info hanging off to one side.
  -- (110 + 6 + 100 = 216 wide; Ready Check's center lands at -216/2 + 110/2 = -53.)
  local ready = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
  ready:SetSize(110, 20)
  ready:SetText(READY_CHECK or "Ready Check")
  ready:SetPoint("TOP", f, "TOP", -53, -33)
  ready:SetScript("OnClick", function()
    if DoReadyCheck then DoReadyCheck() end
  end)
  panel.ReadyCheck = ready

  -- Raid Info — toggles the lockout popup (see buildRaidInfoFrame above). Always enabled: reading
  -- your own saved instances needs no group and no rank.
  local info = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
  info:SetSize(100, 20)
  info:SetText(RAID_INFO or "Raid Info")
  info:SetPoint("LEFT", ready, "RIGHT", 6, 0)
  info:SetScript("OnClick", function() SO.ToggleRaidInfo() end)
  panel.RaidInfoButton = info

  -- Raid Browser (owner report 2026-07-17: "doesn't open anything" — ToggleRaidBrowser isn't a real
  -- 3.3.5a global, it doesn't exist on this client and the call was silently no-op'ing. Patch 3.3's
  -- actual Icecrown Raid Finder frame is LFRParentFrame, toggled with ToggleLFRParentFrame — confirmed
  -- as the live, working call via AddOns/DragonUI/modules/micromenu.lua:2649, which drives the same
  -- frame from the minimap LFG eye's "listed" mode.) Moved into the bottom outer-chrome band
  -- alongside Convert to Raid (owner steer 2026-07-17: the group grid replaced the old empty-state
  -- blurb it used to live inside).
  local browser = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
  browser:SetSize(140, 22); browser:SetText(RAID_BROWSER_BUTTON or "Raid Browser")
  browser:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", 0, -29)
  browser:SetScript("OnClick", function()
    if ToggleLFRParentFrame then ToggleLFRParentFrame() end
  end)
  panel.Browser = browser

  -- Convert to Raid (party leader, not already a raid). Anchored 29px below panel's own bottom
  -- edge, not +4 (owner report 2026-07-17, same fix as the Friends/Who tab buttons: panel's dark
  -- inset covers its full extent down to its own bottom edge, which already sits 36px above the
  -- window's true bottom — +4 sat the button inside the dark inset instead of the outer grey
  -- chrome band below it).
  local convert = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
  convert:SetSize(140, 22); convert:SetText(CONVERT_TO_RAID or "Convert to Raid")
  convert:SetPoint("BOTTOMLEFT", panel, "BOTTOMLEFT", 0, -29)
  convert:SetScript("OnClick", function()
    if ConvertToRaid then ConvertToRaid() end
    SO.RefreshRaid()
  end)
  panel.Convert = convert

  -- Leaving the Raid tab (or closing the window) takes the lockout popup with it — it's a child of
  -- `panel`, so it would otherwise pop back into view when the tab is re-selected.
  panel:HookScript("OnHide", function()
    if panel.RaidInfo then panel.RaidInfo:Hide() end
    -- Tab switched / window closed mid-drag: OnDragStop won't reach a hidden frame, so the ghost
    -- would be left following the cursor with nothing to drop it on.
    endDrag()
  end)

  if RequestRaidInfo then RequestRaidInfo() end
  SO.RefreshSavedInstances()
  SO.RefreshRaid()
end

function SO.RefreshRaid()
  local f = SO.frame
  local panel = f and f.RaidPanel
  if not (panel and panel._groupBoxes) then return end

  -- A repaint means the roster moved, so every slot's _index/_name pairing is about to be rewritten
  -- underneath any drag in flight. Drop it rather than let it finish against stale bookkeeping;
  -- OnDragStop still fires on the source afterwards and bails out on the now-nil dragSource.
  endDrag()

  for g = 1, NUM_GROUPS do
    local box = panel._groupBoxes[g]
    for s = 1, SLOTS_PER_GROUP do
      local slot = box.slots[s]
      slot.icon:Hide()
      slot.text:SetText(EMPTY_LABEL)
      slot.text:SetTextColor(0.5, 0.5, 0.5)
      slot.text:SetAlpha(1)
      slot._name = nil
      slot._unit = nil
      slot._index = nil
      slot:SetAlpha(1)
      -- Owner steer 2026-07-17: match Channels roster — no hover glow on empty slots. Done by
      -- zeroing the highlight's alpha rather than EnableMouse(false), which is what it used to be:
      -- an empty slot is the drop target for moving someone into that group, and a mouse-disabled
      -- frame never comes back from GetMouseFocus(). Nothing else keys off hover here — the
      -- tooltip needs _unit and the right-click menu needs _name, both nil on an empty slot.
      local hl = slot:GetHighlightTexture()
      if hl then hl:SetAlpha(0) end
    end
  end

  local total = (GetNumRaidMembers and GetNumRaidMembers()) or 0
  -- Fill position within each group tracked independently of raid roster index (subgroup members
  -- aren't guaranteed contiguous/in-order in the GetRaidRosterInfo iteration).
  local fillPos = {}
  local classCounts = {}
  for i = 1, total do
    local name, rank, subgroup, level, _, fileName, zone, online = GetRaidRosterInfo(i)
    if fileName then classCounts[fileName] = (classCounts[fileName] or 0) + 1 end
    if name and subgroup and subgroup >= 1 and subgroup <= NUM_GROUPS then
      fillPos[subgroup] = (fillPos[subgroup] or 0) + 1
      local pos = fillPos[subgroup]
      if pos <= SLOTS_PER_GROUP then
        local slot = panel._groupBoxes[subgroup].slots[pos]
        slot._name = name
        slot._unit = "raid" .. i
        slot._index = i     -- SetRaidSubgroup/SwapRaidSubgroup take roster indices, not names
        local hl = slot:GetHighlightTexture()
        if hl then hl:SetAlpha(1) end
        if rank == 2 then
          slot.icon:SetTexture(LEADER_ICON); slot.icon:Show()
        elseif rank == 1 then
          slot.icon:SetTexture(ASSIST_ICON); slot.icon:Show()
        else
          slot.icon:Hide()
        end
        local className = fileName and LOCALIZED_CLASS_NAMES_MALE and LOCALIZED_CLASS_NAMES_MALE[fileName]
        slot.text:SetText(string.format("%s  %d  %s", name, level or 0, className or ""))
        local r, gC, b = classColor(fileName)
        slot.text:SetTextColor(r, gC, b)
        slot.text:SetAlpha(online and 1 or 0.5)
      end
    end
  end

  -- Class summary strip: count + full-color icon when present in the raid, desaturated/dimmed and
  -- blank count otherwise.
  if panel._classIcons then
    for classFile, entry in pairs(panel._classIcons) do
      local n = classCounts[classFile] or 0
      if n > 0 then
        entry.icon:SetDesaturated(false)
        entry.icon:SetAlpha(1)
        entry.count:SetText(tostring(n))
        entry.count:SetTextColor(1, 1, 1)
      else
        entry.icon:SetDesaturated(true)
        entry.icon:SetAlpha(0.4)
        entry.count:SetText("")
      end
    end
  end

  -- Convert only makes sense as a party leader who isn't already in a raid. The stock window
  -- keeps the button visible-but-disabled rather than hiding it.
  local inRaid = total > 0
  local canConvert = not inRaid
    and (GetNumPartyMembers and GetNumPartyMembers() or 0) > 0
    and (IsPartyLeader and IsPartyLeader())
  if canConvert then panel.Convert:Enable() else panel.Convert:Disable() end

  -- Ready Check: only the raid leader/an assist (or the party leader, pre-conversion) can call it.
  local canReadyCheck
  if inRaid then
    canReadyCheck = (IsRaidLeader and IsRaidLeader()) or (IsRaidOfficer and IsRaidOfficer())
  else
    canReadyCheck = (GetNumPartyMembers and GetNumPartyMembers() or 0) > 0
      and (IsPartyLeader and IsPartyLeader())
  end
  if panel.ReadyCheck then
    if canReadyCheck then panel.ReadyCheck:Enable() else panel.ReadyCheck:Disable() end
  end
end

local ev = CreateFrame("Frame")
for _, e in ipairs({ "RAID_ROSTER_UPDATE", "PARTY_MEMBERS_CHANGED", "PARTY_LEADER_CHANGED" }) do
  pcall(ev.RegisterEvent, ev, e)
end
ev:SetScript("OnEvent", function() if SO.RefreshRaid then SO.RefreshRaid() end end)

-- Saved-instance lockouts are independent of raid roster/party state (UPDATE_INSTANCE_INFO fires
-- whenever the server (re)sends lockout data, e.g. after RequestRaidInfo() or on zoning into/out
-- of an instance) -- kept on its own event frame rather than folded into `ev` above so a lockout
-- refresh doesn't require also touching the roster rows.
local savedEv = CreateFrame("Frame")
pcall(savedEv.RegisterEvent, savedEv, "UPDATE_INSTANCE_INFO")
savedEv:SetScript("OnEvent", function() if SO.RefreshSavedInstances then SO.RefreshSavedInstances() end end)
