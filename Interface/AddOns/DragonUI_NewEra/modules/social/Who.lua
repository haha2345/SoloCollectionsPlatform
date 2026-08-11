-- DragonUI_NewEra/modules/social/Who.lua — the Who tab for NE_FriendsFrame.
--
-- Native WotLK APIs: SetWhoToUI(1) routes /who results to the UI (not chat); SendWho(filter)
-- queries; GetNumWhoResults / GetWhoInfo read them; WHO_LIST_UPDATE fires on arrival. Built from
-- Window.lua via SO.SetupWho(f); exposes SO.RefreshWho().

local NE = DragonUI_NewEra
if not NE then return end

NE.social = NE.social or {}
local SO = NE.social

-- Fitted to the panel's scroll well (scroll insets -46/+34 of a 480-tall panel => ~400 => 25 rows
-- at 16px); rows aren't clipped by the scroll frame, so don't overshoot.
local NUM_ROWS   = 23
local ROW_HEIGHT = 16

-- Columns, in the STOCK 3.3.5a order (owner supplied the stock frames as reference 2026-07-16):
-- Name | Zone | Lvl | Class — NOT the Name/Level/Class/Zone of the first pass.
-- { title, x, w, justify }; w 0 = fill to the row's right edge.
-- `sort` = the SortWho() criterion this header sorts by (nil = not a sort header). Column 2 is the
-- switchable Zone/Guild/Race field, so its sort key follows the selected field (see WHO_FIELDS).
local COLUMNS = {
  { title = NAME or "Name",        x = 4,   w = 150, justify = "LEFT",   sort = "name" },
  { title = ZONE or "Zone",        x = 156, w = 170, justify = "LEFT" },
  { title = LEVEL_ABBR or "Lvl",   x = 328, w = 40,  justify = "CENTER", sort = "level" },
  { title = CLASS or "Class",      x = 370, w = 0,   justify = "LEFT",   sort = "class" },
}

-- Column 2 is SWITCHABLE (owner steer 2026-07-17: "who list needs to be able to show
-- zone/guild/race" — the stock Who tab's 2nd column is a single variable field toggled via a
-- dropdown on its header, not three separate columns; GetWhoInfo already returns guild/race
-- alongside zone, we just weren't exposing the switch). COLUMNS[2].title stays "Zone" as the
-- built-in default label.
local WHO_FIELDS = {
  { key = "ZONE",  label = ZONE or "Zone" },
  { key = "GUILD", label = GUILD or "Guild" },
  { key = "RACE",  label = RACE or "Race" },
}

local whoFieldMenuFrame
local function openWhoFieldMenu(panel, anchor)
  if not EasyMenu then return end
  if not whoFieldMenuFrame then
    whoFieldMenuFrame = CreateFrame("Frame", "NE_SocialWhoFieldMenu", UIParent, "UIDropDownMenuTemplate")
  end
  local menu = {}
  for _, fdef in ipairs(WHO_FIELDS) do
    menu[#menu + 1] = {
      text = fdef.label, notCheckable = true,
      func = function()
        panel._field = fdef.key
        if panel._fieldHeaderFS then panel._fieldHeaderFS:SetText(fdef.label) end
        -- Selecting a field also sorts by it (SortWho keys are lowercase: zone/guild/race).
        if SortWho then SortWho(fdef.key:lower()) end
        SO.RefreshWho()
      end,
    }
  end
  EasyMenu(menu, whoFieldMenuFrame, anchor, 0, 0, "MENU")
end

local function classColor(classFile)
  local c = classFile and RAID_CLASS_COLORS and RAID_CLASS_COLORS[classFile]
  if c then return c.r, c.g, c.b end
  return 1, 0.82, 0
end

-- Right-click context menu (owner steer 2026-07-17: Who tab had no context menu). Same
-- EasyMenu/UIDropDownMenu pattern as Friends.lua/Roster.lua. TargetUnit(unit, name) accepting a
-- name lookup (not just a unit token) is confirmed via the on-client APIDocumentation addon's
-- TargetingDocumentation.lua.
local whoMenuFrame
local function openWhoMenu(idx)
  if not (EasyMenu and idx) then return end
  if not whoMenuFrame then
    whoMenuFrame = CreateFrame("Frame", "NE_SocialWhoMenu", UIParent, "UIDropDownMenuTemplate")
  end
  local name = GetWhoInfo and GetWhoInfo(idx)
  local menu = {
    { text = name or "", isTitle = true, notCheckable = true },
    { text = WHISPER or "Whisper", notCheckable = true, func = function()
        if name and ChatFrame_SendTell then ChatFrame_SendTell(name) end
      end },
    { text = GROUP_INVITE or "Invite", notCheckable = true, func = function()
        if name and InviteUnit then InviteUnit(name) end
      end },
    { text = TARGET or "Target", notCheckable = true, func = function()
        if name and TargetUnit then TargetUnit(nil, name) end
      end },
    { text = IGNORE or "Ignore", notCheckable = true, func = function()
        if name and AddIgnore then AddIgnore(name) end
      end },
    { text = CANCEL or "Cancel", notCheckable = true },
  }
  EasyMenu(menu, whoMenuFrame, "cursor", 0, 0, "MENU")
end

function SO.SetupWho(f)
  local panel = f.WhoPanel
  if not panel or panel._built then return end
  panel._built = true
  panel._selected = nil
  panel._field = "ZONE"

  -- Dark recessed backdrop (owner steer 2026-07-17: "Who, Chat and Raid tabs should have the dark
  -- inset frames" — same treatment already used for Friends/Roster).
  local panelBg = panel:CreateTexture(nil, "BACKGROUND")
  panelBg:SetTexture("Interface\\Buttons\\WHITE8X8")
  panelBg:SetVertexColor(0.06, 0.06, 0.07, 0.75)
  panelBg:SetAllPoints(panel)
  panel.Bg = panelBg
  if NE.nineslice and NE.nineslice.AttachInset then pcall(NE.nineslice.AttachInset, panel, 0, 0, 0, 0) end

  -- NOTE: SetWhoToUI is deliberately NOT set here. It's a global, sticky flag — setting it at
  -- build time (login) hijacked every /who the player typed into the UI for the whole session.
  -- Window.lua's SO.SetWhoRouting toggles it with the Who tab's visibility instead.

  -- Search box + button. Parented to `panel` (shows/hides with the Who tab) but anchored off the
  -- WINDOW frame, same recipe as Raid's Ready Check (modules/social/Raid.lua): the chrome gap above
  -- the panel's own top edge (panel content starts 56px down; the title text only runs to about
  -- -21) has room for a control row, and the owner marked it there with a screenshot annotation
  -- 2026-07-18 rather than have it sit as the first row inside the dark inset list.
  local box = CreateFrame("EditBox", nil, panel, "InputBoxTemplate")
  box:SetSize(200, 20); box:SetAutoFocus(false)
  box:SetPoint("TOPLEFT", f, "TOPLEFT", 58, -34)
  box:SetScript("OnEnterPressed", function(self)
    if SetWhoToUI then SetWhoToUI(1) end
    if SendWho then SendWho(self:GetText() or "") end
    self:ClearFocus()
  end)
  box:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
  panel._box = box

  local search = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
  search:SetSize(80, 22); search:SetText(SEARCH or "Search")
  search:SetPoint("LEFT", box, "RIGHT", 6, 0)
  search:SetScript("OnClick", function()
    if SetWhoToUI then SetWhoToUI(1) end
    if SendWho then SendWho(box:GetText() or "") end
  end)

  -- Refresh — re-runs the last query (stock window has this bottom-left).
  local refresh = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
  refresh:SetSize(90, 22); refresh:SetText(REFRESH or "Refresh")
  refresh:SetPoint("LEFT", search, "RIGHT", 6, 0)
  refresh:SetScript("OnClick", function()
    if SetWhoToUI then SetWhoToUI(1) end
    if SendWho then SendWho(box:GetText() or "") end
  end)

  -- "N People Found" readout (stock WhoFrameTotals).
  panel.Totals = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  panel.Totals:SetPoint("BOTTOM", panel, "BOTTOM", 0, 30)

  -- Column header strip.
  local header = CreateFrame("Frame", nil, panel)
  header:SetPoint("TOPLEFT", panel, "TOPLEFT", 0, -4)
  header:SetPoint("TOPRIGHT", panel, "TOPRIGHT", 0, -4)
  header:SetHeight(16)
  for ci, col in ipairs(COLUMNS) do
    if ci == 2 then
      -- Switchable Zone/Guild/Race header (see WHO_FIELDS above) — a clickable button instead of
      -- a plain label, matching the stock WhoFrameDropdown's spot on this exact column.
      local btn = CreateFrame("Button", nil, header)
      btn:SetPoint("LEFT", header, "LEFT", col.x, 0)
      btn:SetSize(col.w, 16)
      local fs = btn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
      fs:SetPoint("LEFT", btn, "LEFT", 2, 0)
      fs:SetText(col.title)
      panel._fieldHeaderFS = fs
      local arrow = btn:CreateTexture(nil, "OVERLAY")
      arrow:SetTexture("Interface\\ChatFrame\\ChatFrameExpandArrow")
      arrow:SetSize(10, 10)
      arrow:SetPoint("LEFT", fs, "RIGHT", 2, 0)
      btn:SetScript("OnClick", function(self) openWhoFieldMenu(panel, self) end)
    else
      -- Clickable sort header: SortWho() reorders the current results (and reverses on a repeat
      -- click by the same criterion), then we repaint. A hover tint signals it's clickable.
      local btn = CreateFrame("Button", nil, header)
      btn:SetPoint("LEFT", header, "LEFT", col.x, 0)
      if col.w > 0 then
        btn:SetSize(col.w, 16)
      else
        btn:SetPoint("RIGHT", header, "RIGHT", 0, 0)
        btn:SetHeight(16)
      end
      local fs = btn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
      fs:SetPoint("LEFT", btn, "LEFT", 2, 0)
      fs:SetText(col.title)
      fs:SetJustifyH(col.justify)
      if col.sort then
        btn:SetScript("OnClick", function()
          if SortWho then SortWho(col.sort) end
          if SO.RefreshWho then SO.RefreshWho() end
        end)
        -- Brighten on hover to signal the header is clickable; restore the default highlight tint.
        btn:SetScript("OnEnter", function() fs:SetTextColor(1, 1, 0.6) end)
        btn:SetScript("OnLeave", function() fs:SetTextColor(1, 1, 1) end)
      end
    end
  end

  -- List. Inset 3px from the panel's edges (owner steer 2026-07-17), on top of the existing header
  -- clearance (-46), scrollbar clearance (-24), and button-row clearance (34).
  local scroll = CreateFrame("ScrollFrame", "NE_SocialWhoScroll", panel, "FauxScrollFrameTemplate")
  scroll:SetPoint("TOPLEFT", panel, "TOPLEFT", 3, -24)
  scroll:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -27, 37)
  scroll:SetScript("OnVerticalScroll", function(self, o)
    FauxScrollFrame_OnVerticalScroll(self, o, ROW_HEIGHT, SO.RefreshWho)
  end)
  panel._scroll = scroll
  scroll.ScrollBar = _G["NE_SocialWhoScrollScrollBar"]   -- 3.3.5a template doesn't set the parentKey
  if NE.scrollbar and NE.scrollbar.Reskin then NE.scrollbar.Reskin(scroll) end

  panel._rows = {}
  for i = 1, NUM_ROWS do
    local row = CreateFrame("Button", nil, panel)
    row:SetHeight(ROW_HEIGHT)
    if i == 1 then row:SetPoint("TOPLEFT", scroll, "TOPLEFT", 0, 0)
    else row:SetPoint("TOPLEFT", panel._rows[i - 1], "BOTTOMLEFT", 0, 0) end
    row:SetPoint("RIGHT", scroll, "RIGHT", 0, 0)
    row:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")

    -- Selection highlight (owner steer 2026-07-17: "Who should allow me to click on a user" — the
    -- click handler already set panel._selected, but nothing ever showed it, so a click looked
    -- like it did nothing).
    local sel = row:CreateTexture(nil, "BACKGROUND")
    sel:SetTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight")
    sel:SetBlendMode("ADD"); sel:SetAllPoints(row); sel:SetAlpha(0.4); sel:Hide()
    row._sel = sel

    row.cells = {}
    for c, col in ipairs(COLUMNS) do
      local fs = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
      fs:SetPoint("LEFT", row, "LEFT", col.x, 0)
      if col.w > 0 then fs:SetWidth(col.w) else fs:SetPoint("RIGHT", row, "RIGHT", -2, 0) end
      fs:SetJustifyH(col.justify); fs:SetWordWrap(false)
      row.cells[c] = fs
    end
    row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    row:SetScript("OnClick", function(self, button)
      panel._selected = self._index
      SO.RefreshWho()
      if button == "RightButton" then openWhoMenu(self._index) end
    end)
    panel._rows[i] = row
  end

  -- Buttons: Add Friend / Group Invite / Whisper on the selected result.
  local function selectedName()
    if not panel._selected then return nil end
    return (GetWhoInfo and (GetWhoInfo(panel._selected)))
  end

  -- Anchored 29px below panel's own bottom edge, not +4 (owner report 2026-07-17, same fix as the
  -- Friends tab's buttons: panel's dark inset background covers its full extent down to its own
  -- bottom edge, and panel's bottom already sits 36px above the window's true bottom — so +4 sat
  -- the buttons inside the dark inset instead of the outer grey chrome band below it).
  local addf = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
  addf:SetSize(110, 22); addf:SetText(ADD_FRIEND or "Add Friend")
  addf:SetPoint("BOTTOMLEFT", panel, "BOTTOMLEFT", 0, -29)
  addf:SetScript("OnClick", function() local n = selectedName(); if n and AddFriend then AddFriend(n) end end)

  local invite = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
  invite:SetSize(110, 22); invite:SetText(GROUP_INVITE or "Invite")
  invite:SetPoint("LEFT", addf, "RIGHT", 4, 0)
  invite:SetScript("OnClick", function() local n = selectedName(); if n and InviteUnit then InviteUnit(n) end end)

  local whisper = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
  whisper:SetSize(90, 22); whisper:SetText(WHISPER or "Whisper")
  whisper:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", 0, -29)
  whisper:SetScript("OnClick", function()
    local n = selectedName(); if n and ChatFrame_SendTell then ChatFrame_SendTell(n) end
  end)
end

function SO.RefreshWho()
  local f = SO.frame
  local panel = f and f.WhoPanel
  if not (panel and panel._rows) then return end
  local total = (GetNumWhoResults and GetNumWhoResults()) or 0
  local offset = FauxScrollFrame_GetOffset(panel._scroll)

  for i = 1, NUM_ROWS do
    local idx = offset + i
    local row = panel._rows[i]
    if idx <= total then
      local name, guild, level, race, class, zone, classFile = GetWhoInfo(idx)
      row._index = idx
      row.cells[1]:SetText(name or "")
      local field2 = (panel._field == "GUILD" and guild) or (panel._field == "RACE" and race) or zone
      row.cells[2]:SetText(field2 or "")
      row.cells[3]:SetText(level or "")
      row.cells[4]:SetText(class or "")
      row.cells[1]:SetTextColor(classColor(classFile))
      if row._sel then row._sel:SetShown(idx == panel._selected) end
      row:Show()
    else
      row._index = nil
      if row._sel then row._sel:Hide() end
      row:Hide()
    end
  end
  FauxScrollFrame_Update(panel._scroll, total, NUM_ROWS, ROW_HEIGHT)

  -- Stock readout: "N People Found". The localized template's SHAPE isn't guaranteed on this
  -- client (FRIENDS_LIST_TEMPLATE turned out not to match retail's specifiers — it silently
  -- dropped an arg), and a template expecting more args than we pass would make string.format
  -- ERROR. So try the localized one under pcall and fall back to a plain built string.
  if panel.Totals then
    local shown, totalFound = GetNumWhoResults()
    local n = tonumber(totalFound) or tonumber(shown) or total or 0
    local ok, s = pcall(string.format, WHO_FRAME_TOTAL_TEMPLATE or "%d People Found", n)
    panel.Totals:SetText((ok and s) or (tostring(n) .. " People Found"))
  end
end

local ev = CreateFrame("Frame")
ev:RegisterEvent("WHO_LIST_UPDATE")
ev:SetScript("OnEvent", function() if SO.RefreshWho then SO.RefreshWho() end end)
