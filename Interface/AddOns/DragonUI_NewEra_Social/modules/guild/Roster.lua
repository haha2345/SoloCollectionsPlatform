-- DragonUI_NewEra/modules/guild/Roster.lua — the guild roster (ROSTER mode) + member detail.
--
-- DOWNPORT of NewEra/Guild/Roster.lua. NewEra uses retail's WowScrollBoxList + ColumnDisplay +
-- C_GuildInfo. On 3.3.5a we rebuild on the native WotLK kit: a FauxScrollFrame list, manual column
-- headers, and the classic roster API (GuildRoster / GetGuildRosterInfo / SortGuildRoster). Member
-- actions (public/officer notes, promote/demote/remove, party invite) use the WotLK permission
-- checks (CanEditPublicNote / CanViewOfficerNote / CanGuildPromote / CanGuildRemove …).
--
-- Built from Window.lua via G.SetupRoster(f); exposes G.RefreshRoster() (called on open, on
-- GUILD_ROSTER_UPDATE, and when the ROSTER tab is selected).

local NE = DragonUI_NewEra
if not NE then return end

NE.guild = NE.guild or {}
local G = NE.guild

-- Row count is sized to the scroll well's height at the window's fixed size (see Window.lua:
-- 582 tall - 48 top - 34 bottom = 500 panel; scroll insets -46/+2 => ~452 => 25 rows at 18px).
-- Rows are parented to the panel (not clipped by the scroll frame), so overshooting this would
-- spill rows over the bottom buttons — keep it at or under the fitted count.
local NUM_ROWS   = 24
local ROW_HEIGHT = 18

-- Column layout: { key = sort key for SortGuildRoster, title, x (left offset), w, justify }.
-- Follows the reference guild frame (owner 2026-07-16): Lvl | Class | Name | Zone | Rank | Note,
-- with Class rendered as an ICON rather than text. The panel sits to the right of the left
-- GuildColumn (owner 2026-07-17: column moved onto the Roster tab) rather than spanning the full
-- window; the fill-width Note column just gets a bit less room as a result.
local COLUMNS = {
  { key = "level", title = LEVEL_ABBR or "Lvl",  x = 4,   w = 40,  justify = "CENTER" },
  { key = "class", title = CLASS or "Class",     x = 46,  w = 46,  justify = "CENTER", icon = true },
  { key = "name",  title = NAME or "Name",       x = 94,  w = 150, justify = "LEFT" },
  { key = "zone",  title = ZONE or "Zone",       x = 246, w = 150, justify = "LEFT" },
  { key = "rank",  title = RANK or "Rank",       x = 398, w = 120, justify = "LEFT" },
  { key = "note",  title = LABEL_NOTE or "Note", x = 520, w = 0,   justify = "LEFT" },  -- w 0 = fill
}

-- Native 3.3.5a class-icon sheet + coords. CLASS_ICON_TCOORDS is a stock global (modules/talents
-- already relies on it). The addon also ships a CIRCULAR `classicon-<class>` atlas via
-- modules/character/Assets.lua, but the reference frame's icons are the SQUARE stock ones.
local CLASS_ICON_TEX = "Interface\\Glues\\CharacterCreate\\UI-CharacterCreate-Classes"

local function classColor(classFile)
  local c = classFile and RAID_CLASS_COLORS and RAID_CLASS_COLORS[classFile]
  if c then return c.r, c.g, c.b end
  return 1, 0.82, 0
end

-- Point a texture at a class's icon in the stock sheet. Returns false when the class is unknown
-- (so the caller can hide the icon rather than show the whole 4x4 sheet).
local function setClassIcon(tex, classFile)
  local c = classFile and CLASS_ICON_TCOORDS and CLASS_ICON_TCOORDS[classFile]
  if not c then return false end
  tex:SetTexture(CLASS_ICON_TEX)
  tex:SetTexCoord(c[1], c[2], c[3], c[4])
  return true
end

-- Format a last-online tuple (GetGuildRosterLastOnline) into a short string.
-- The localized LASTONLINE_* templates' SHAPE isn't guaranteed on this client (FRIENDS_LIST_TEMPLATE
-- turned out not to match retail's specifiers), and a template wanting more args than we pass makes
-- string.format ERROR — so each format goes through pcall with a plain fallback.
local function safeFormat(tmpl, value, unit)
  local ok, s = pcall(string.format, tmpl or ("%d " .. unit), value)
  return (ok and s) or (tostring(value) .. " " .. unit)
end

local function lastOnlineText(i)
  if not GetGuildRosterLastOnline then return "" end
  local years, months, days, hours = GetGuildRosterLastOnline(i)
  if not years then return "" end
  if years  > 0 then return safeFormat(LASTONLINE_YEARS,  years,  "years")  end
  if months > 0 then return safeFormat(LASTONLINE_MONTHS, months, "months") end
  if days   > 0 then return safeFormat(LASTONLINE_DAYS,   days,   "days")   end
  if hours  > 0 then return safeFormat(LASTONLINE_HOURS,  hours,  "hours")  end
  return "< 1 " .. "hour"
end

-- ---------------------------------------------------------------------------
-- Member detail popup (click a roster row).
-- ---------------------------------------------------------------------------
local function buildMemberDetail(parent)
  local d = CreateFrame("Frame", "NE_GuildMemberDetail", parent)
  d:SetSize(220, 300)
  d:SetFrameStrata("DIALOG")
  d:SetToplevel(true); d:EnableMouse(true)
  d:SetPoint("TOPLEFT", parent, "TOPRIGHT", -6, -40)
  d:Hide()

  -- NE chrome, matching the event log and Guild Control popups (owner steer 2026-08-09) — replaces
  -- the native DialogBox backdrop this used to carry.
  --
  -- Both the rock body and the nineslice live on an UNDERLAY frame one level below the panel, so all
  -- of the chrome draws beneath the panel's own regions. That is what avoids the problem Guild Control
  -- hit, where a nineslice parented to the frame painted its top border over the frame's first line of
  -- text and needed the whole thing lifted to compensate. Below the content, the border sits at the
  -- edges where nothing is drawn anyway, so no offsetting is required.
  if d.SetBackdrop then d:SetBackdrop(nil) end

  local under = CreateFrame("Frame", nil, d)
  under:EnableMouse(false)
  under:SetFrameLevel(math.max(0, (d:GetFrameLevel() or 1) - 1))
  under:SetAllPoints(d)
  d._neUnder = under

  local body = under:CreateTexture(nil, "BACKGROUND")
  local rockPath = NE.tex and NE.tex.localFiles and NE.tex.localFiles[374155]
  body:SetTexture(rockPath or 374155, "REPEAT", "REPEAT")
  body:SetHorizTile(true); body:SetVertTile(true)
  -- Asymmetric insets: the square-edge chrome's left border piece is thicker than the other three, so
  -- an even inset pokes out on the left while falling short on the right and bottom.
  body:SetPoint("TOPLEFT",     under, "TOPLEFT",      5, -4)
  body:SetPoint("BOTTOMRIGHT", under, "BOTTOMRIGHT", -2,  2)

  if NE.nineslice and NE.nineslice.ApplyLayout then
    NE.nineslice.ApplyLayout(under, "ButtonFrameTemplateNoPortrait")
  end

  -- Same close-button treatment and placement as the event log's (modules/guild/Window.lua): the old
  -- -4,-4 inset predates this panel having a title band, and left the X straddling the top border
  -- rather than sitting in it (owner-reported 2026-08-09).
  local close = CreateFrame("Button", nil, d, "UIPanelCloseButton")
  if NE.panelchrome and NE.panelchrome.ModernizeCloseButton then
    pcall(NE.panelchrome.ModernizeCloseButton, close, { frameLevelBump = 10 })
  end
  close:SetPoint("TOPRIGHT", d, "TOPRIGHT", 1, 0)

  -- -30, not -18: the nineslice's title band occupies roughly the top 22px, and at -18 the name sat
  -- on it and read as clipped (owner-reported 2026-08-09). Everything below chains off this anchor,
  -- so moving it moves the whole panel's content, and the height re-fits itself on show.
  d.Name = d:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
  d.Name:SetPoint("TOPLEFT", d, "TOPLEFT", 18, -30)
  d.Name:SetWidth(160); d.Name:SetJustifyH("LEFT")

  d.Level = d:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  d.Level:SetPoint("TOPLEFT", d.Name, "BOTTOMLEFT", 0, -4)

  d.Zone = d:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  d.Zone:SetPoint("TOPLEFT", d.Level, "BOTTOMLEFT", 0, -4)

  d.Rank = d:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  d.Rank:SetPoint("TOPLEFT", d.Zone, "BOTTOMLEFT", 0, -4)

  -- Public note.
  local nlabel = d:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  nlabel:SetPoint("TOPLEFT", d.Rank, "BOTTOMLEFT", 0, -10)
  nlabel:SetText(LABEL_NOTE or "Note")
  local note = CreateFrame("EditBox", nil, d, "InputBoxTemplate")
  note:SetSize(170, 20); note:SetAutoFocus(false)
  note:SetPoint("TOPLEFT", nlabel, "BOTTOMLEFT", 6, -2)
  note:SetScript("OnEnterPressed", function(self)
    if d._index and GuildRosterSetPublicNote then GuildRosterSetPublicNote(d._index, self:GetText()) end
    self:ClearFocus()
  end)
  note:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
  d.NoteEdit = note

  -- Officer note (shown only when viewable).
  local olabel = d:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  olabel:SetPoint("TOPLEFT", nlabel, "BOTTOMLEFT", 0, -46)
  olabel:SetText(GUILD_OFFICERNOTES_LABEL or "Officer Note")
  d.OfficerLabel = olabel
  local onote = CreateFrame("EditBox", nil, d, "InputBoxTemplate")
  onote:SetSize(170, 20); onote:SetAutoFocus(false)
  onote:SetPoint("TOPLEFT", olabel, "BOTTOMLEFT", 6, -2)
  onote:SetScript("OnEnterPressed", function(self)
    if d._index and GuildRosterSetOfficerNote then GuildRosterSetOfficerNote(d._index, self:GetText()) end
    self:ClearFocus()
  end)
  onote:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
  d.OfficerEdit = onote

  -- Both note boxes get the NE recessed well in place of InputBoxTemplate's own Left/Middle/Right
  -- border art. That art was rendering broken on the officer box — its right cap detached and floated
  -- clear of a too-short middle (owner-reported 2026-08-09; visible in earlier screenshots too, so it
  -- predates the chrome change). Rather than chase why one instance of a shared template mis-stretches,
  -- drop the template art on both and use the same flat-fill-plus-inset the Guild Information wells and
  -- the Guild Control dropdown already use — which is also what the rest of this panel now looks like.
  local function wellify(edit)
    for _, r in ipairs({ edit:GetRegions() }) do
      if r.GetObjectType and r:GetObjectType() == "Texture" then r:Hide() end
    end
    local bg = edit:CreateTexture(nil, "BACKGROUND")
    bg:SetTexture("Interface\\Buttons\\WHITE8X8")
    bg:SetVertexColor(0.06, 0.06, 0.07, 0.90)
    bg:SetPoint("TOPLEFT",     edit, "TOPLEFT",     -4,  2)
    bg:SetPoint("BOTTOMRIGHT", edit, "BOTTOMRIGHT",  4, -2)
    if NE.nineslice and NE.nineslice.AttachInset then
      pcall(NE.nineslice.AttachInset, edit, -4, 2, 4, -2)
    end
  end
  wellify(note)
  wellify(onote)

  -- Rank up/down arrows, sitting on the Rank line itself — how stock 3.3.5a presents this (owner
  -- steer 2026-08-09, with a reference screenshot of the native GuildMemberDetailFrame). Replaces the
  -- pair of full-width Promote/Demote buttons that used to sit along the bottom: rank is a property of
  -- the member shown on that row, not a bottom-of-panel action like Remove or Group Invite.
  --
  -- Art is the addon's own minimal-scrollbar arrow atlas (core/NineSliceLayouts.lua), the same set the
  -- list scrollbars use, applied in the same normal/pushed/disabled/highlight pattern as
  -- core/ScrollbarReskin.lua's arrow reskin. 17x11 is that atlas's native size.
  -- Drawn larger than the atlas's native 17x11 and tinted gold: at native size in their default grey
  -- they were hard to pick out against the rock body (owner-reported 2026-08-09). Gold is the accent
  -- this UI already uses for interactive text, and is what the stock client uses for these same arrows.
  local ARROW_W, ARROW_H = 22, 14
  local function rankArrow(normalAtlas, overAtlas, downAtlas, onClick)
    local b = CreateFrame("Button", nil, d)
    b:SetSize(ARROW_W, ARROW_H)
    b:EnableMouse(true)
    local function tex(setter, atlas, desat)
      local t = b:CreateTexture(nil, "ARTWORK")
      if NE.tex and NE.tex.SetAtlas then NE.tex.SetAtlas(t, atlas, false) end
      if desat then t:SetDesaturated(true) end
      t:SetAllPoints(b)
      setter(b, t)
      return t
    end
    tex(b.SetNormalTexture, normalAtlas, false):SetVertexColor(1, 0.82, 0)
    tex(b.SetPushedTexture, downAtlas,   false):SetVertexColor(1, 0.82, 0)
    tex(b.SetDisabledTexture, normalAtlas, true)
    local h = tex(b.SetHighlightTexture, overAtlas, false)
    h:SetBlendMode("ADD")
    b:SetScript("OnClick", onClick)
    return b
  end

  d.Promote = rankArrow("minimal-scrollbar-arrow-top", "minimal-scrollbar-arrow-top-over",
    "minimal-scrollbar-arrow-top-down",
    function() if d._name and GuildPromote then GuildPromote(d._name); G.RefreshRoster() end end)
  d.Promote:SetPoint("LEFT", d.Rank, "RIGHT", 10, 0)

  d.Demote = rankArrow("minimal-scrollbar-arrow-bottom", "minimal-scrollbar-arrow-bottom-over",
    "minimal-scrollbar-arrow-bottom-down",
    function() if d._name and GuildDemote then GuildDemote(d._name); G.RefreshRoster() end end)
  d.Demote:SetPoint("LEFT", d.Promote, "RIGHT", 6, 0)

  -- Action buttons: Remove / Group Invite.
  local function actionButton(text, w)
    local b = CreateFrame("Button", nil, d, "UIPanelButtonTemplate")
    b:SetSize(w or 90, 20); b:SetText(text)
    return b
  end

  -- Anchored under the last visible note box rather than to the panel's bottom edge. The panel had a
  -- fixed 300px height sized for its old two-row button block, which left a large dead gap under the
  -- officer note once that block became the rank arrows (owner-reported 2026-08-09). Hanging the row
  -- off the content also means it follows when the officer note is hidden for members who cannot view
  -- it, instead of stranding the buttons further down.
  d.Invite = actionButton(GROUP_INVITE or "Invite")
  d.Invite:SetPoint("TOPLEFT", onote, "BOTTOMLEFT", -6, -18)
  d.Invite:SetScript("OnClick", function() if d._name and InviteUnit then InviteUnit(d._name) end end)

  d.Remove = actionButton(REMOVE or "Remove")
  d.Remove:SetPoint("LEFT", d.Invite, "RIGHT", 4, 0)
  d.Remove:SetScript("OnClick", function()
    if d._name and GuildUninvite then GuildUninvite(d._name); d:Hide(); G.RefreshRoster() end
  end)

  parent.MemberDetail = d
  return d
end

local function showMemberDetail(f, index)
  local d = f.MemberDetail
  if not d then return end
  local name, rank, rankIndex, level, _, zone, note, officernote, online, _, classFile = GetGuildRosterInfo(index)
  if not name then d:Hide(); return end
  d._index, d._name = index, name
  d.Name:SetText(name); d.Name:SetTextColor(classColor(classFile))
  d.Level:SetText((LEVEL or "Level") .. " " .. tostring(level or ""))
  d.Zone:SetText((online and (zone or "")) or lastOnlineText(index))
  d.Rank:SetText((RANK or "Rank") .. ": " .. tostring(rank or ""))

  d.NoteEdit:SetText(note or "")
  local canEditNote = CanEditPublicNote and CanEditPublicNote()
  d.NoteEdit:SetEnabled(canEditNote and true or false)

  local canViewOfficer = CanViewOfficerNote and CanViewOfficerNote()
  d.OfficerLabel:SetShown(canViewOfficer)
  d.OfficerEdit:SetShown(canViewOfficer)
  if canViewOfficer then
    d.OfficerEdit:SetText(officernote or "")
    d.OfficerEdit:SetEnabled(CanEditOfficerNote and CanEditOfficerNote() and true or false)
  end

  d.Promote:SetShown(CanGuildPromote and CanGuildPromote() and true or false)
  d.Demote:SetShown(CanGuildDemote and CanGuildDemote() and true or false)

  -- Grey out at the ends of the rank ladder, as the stock client does. rankIndex is 0-based with 0 =
  -- guild master, so:
  --   * promote stops at 1 — one more step would make the member guild master, which is a different
  --     action entirely (GuildSetLeader) and would be refused server-side anyway;
  --   * demote stops at the last rank, and the guild master cannot be demoted at all.
  -- GuildControlGetNumRanks() only answers for the guild master, so when it reads 0 the bottom of the
  -- ladder is unknowable and demote is left enabled rather than wrongly greyed for an officer.
  local numRanks = (GuildControlGetNumRanks and GuildControlGetNumRanks()) or 0
  local function setArrowEnabled(btn, ok)
    if ok then btn:Enable() else btn:Disable() end
  end
  setArrowEnabled(d.Promote, rankIndex and rankIndex > 1)
  setArrowEnabled(d.Demote,  rankIndex and rankIndex > 0 and (numRanks <= 0 or rankIndex < numRanks - 1))
  d.Remove:SetShown(CanGuildRemove and CanGuildRemove() and true or false)

  -- Re-anchor the button row under whichever note box is actually the last one visible.
  d.Invite:ClearAllPoints()
  d.Invite:SetPoint("TOPLEFT", canViewOfficer and d.OfficerEdit or d.NoteEdit, "BOTTOMLEFT", -6, -18)

  d:Show()

  -- Fit the panel to its content. Measured after Show rather than computed from the anchor constants,
  -- because the officer note block is conditional — a fixed height is either too tall without it or
  -- too short with it. GetBottom() reports nothing until the frame has been laid out, hence deferred.
  local function fitHeight()
    local top, bottom = d:GetTop(), d.Invite:GetBottom()
    if top and bottom and top > bottom then d:SetHeight(top - bottom + 16) end
  end
  if C_Timer and C_Timer.After then C_Timer.After(0, fitHeight) else fitHeight() end
end

-- ---------------------------------------------------------------------------
-- Right-click context menu (owner steer 2026-07-17: same treatment as the Social Friends rows —
-- rows had no context menu, right-click was never wired up). Native EasyMenu/UIDropDownMenu, same
-- pattern as modules/bags/CombinedBag.lua:CB.OpenMenu and modules/social/Friends.lua.
-- ---------------------------------------------------------------------------
local rosterMenuFrame
local function openRosterMenu(idx)
  if not (EasyMenu and idx) then return end
  local name, rank, _, level, _, zone, note, officernote, online, _, classFile = GetGuildRosterInfo(idx)
  if not name then return end
  if not rosterMenuFrame then
    rosterMenuFrame = CreateFrame("Frame", "NE_GuildRosterMenu", UIParent, "UIDropDownMenuTemplate")
  end
  local menu = { { text = name, isTitle = true, notCheckable = true } }
  if online then
    menu[#menu + 1] = { text = WHISPER or "Whisper", notCheckable = true,
      func = function() if ChatFrame_SendTell then ChatFrame_SendTell(name) end end }
    menu[#menu + 1] = { text = GROUP_INVITE or "Invite", notCheckable = true,
      func = function() if InviteUnit then InviteUnit(name) end end }
  end
  -- Ignore (owner steer 2026-07-17: added to the right-click menu spec; Promote/Demote/Remove kept
  -- as-is per owner confirmation rather than replaced).
  menu[#menu + 1] = { text = IGNORE or "Ignore", notCheckable = true,
    func = function() if AddIgnore then AddIgnore(name) end end }
  if CanGuildPromote and CanGuildPromote() then
    -- Not GUILD_PROMOTE: on this client that global reads "Promote to Guildmaster", which is not what
    -- GuildPromote() does — it moves the member up ONE rank. Promoting to guild master is a separate
    -- action (GuildSetLeader) that this module does not offer.
    menu[#menu + 1] = { text = "Promote", notCheckable = true,
      func = function() if GuildPromote then GuildPromote(name) end; G.RefreshRoster() end }
  end
  if CanGuildDemote and CanGuildDemote() then
    menu[#menu + 1] = { text = GUILD_DEMOTE or "Demote", notCheckable = true,
      func = function() if GuildDemote then GuildDemote(name) end; G.RefreshRoster() end }
  end
  if CanGuildRemove and CanGuildRemove() then
    menu[#menu + 1] = { text = REMOVE or "Remove", notCheckable = true,
      func = function() if GuildUninvite then GuildUninvite(name) end; G.RefreshRoster() end }
  end
  menu[#menu + 1] = { text = CANCEL or "Cancel", notCheckable = true }
  EasyMenu(menu, rosterMenuFrame, "cursor", 0, 0, "MENU")
end

-- ---------------------------------------------------------------------------
-- Roster list.
-- ---------------------------------------------------------------------------
function G.SetupRoster(f)
  local panel = f.RosterFrame
  if not panel or panel._built then return end
  panel._built = true

  -- Dark recessed backdrop behind the whole roster panel (owner steer 2026-07-17: "dark inset
  -- behind the roster"). Created first so it draws behind every child built below.
  local panelBg = panel:CreateTexture(nil, "BACKGROUND")
  panelBg:SetTexture("Interface\\Buttons\\WHITE8X8")
  panelBg:SetVertexColor(0.06, 0.06, 0.07, 0.90)
  panelBg:SetAllPoints(panel)
  panel.Bg = panelBg
  if NE.nineslice and NE.nineslice.AttachInset then pcall(NE.nineslice.AttachInset, panel, 0, 0, 0, 0) end

  -- Show-offline toggle.
  local cb = CreateFrame("CheckButton", "NE_GuildShowOffline", panel, "UICheckButtonTemplate")
  cb:SetPoint("TOPLEFT", panel, "TOPLEFT", 2, -2)
  cb:SetScale(0.9)
  local cbText = _G[cb:GetName() .. "Text"] or cb.Text
  if cbText then cbText:SetText(COMMUNITIES_MEMBER_LIST_SHOW_OFFLINE or GUILD_MEMBERS_SHOW_OFFLINE or "Show Offline") end
  if GetGuildRosterShowOffline then cb:SetChecked(GetGuildRosterShowOffline()) end
  cb:SetScript("OnClick", function(self)
    if SetGuildRosterShowOffline then SetGuildRosterShowOffline(self:GetChecked() and true or false) end
    if GuildRoster then GuildRoster() end
    G.RefreshRoster()
  end)
  panel.ShowOffline = cb

  -- Member count, right-aligned on the checkbox row (it used to live in the removed left column).
  panel.MemberCount = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  panel.MemberCount:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -26, -8)

  -- Column header strip: a dark bar with a recessed border and per-column separators, matching the
  -- reference frame's banded header rather than bare floating labels.
  local header = CreateFrame("Frame", nil, panel)
  header:SetPoint("TOPLEFT", panel, "TOPLEFT", 0, -28)
  header:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -24, -28)
  header:SetHeight(22)
  panel.Header = header

  local hbg = header:CreateTexture(nil, "BACKGROUND")
  hbg:SetTexture("Interface\\Buttons\\WHITE8X8")
  hbg:SetVertexColor(0.10, 0.10, 0.12, 0.95)
  hbg:SetAllPoints(header)
  if NE.nineslice and NE.nineslice.AttachInset then pcall(NE.nineslice.AttachInset, header, 0, 0, 0, 0) end

  for i, col in ipairs(COLUMNS) do
    local btn = CreateFrame("Button", nil, header)
    btn:SetPoint("TOPLEFT", header, "TOPLEFT", col.x, 0)
    btn:SetHeight(22)
    btn:SetWidth(col.w > 0 and col.w or 160)
    local fs = btn:CreateFontString(nil, "OVERLAY", "GameFontNormal")   -- gold header label (bumped 1 size, owner 2026-07-17)
    fs:SetPoint("LEFT", btn, "LEFT", 4, 0)
    fs:SetText(col.title)
    btn._sortKey = col.key
    btn._label = fs
    btn:SetScript("OnClick", function(self)
      if SortGuildRoster then SortGuildRoster(self._sortKey) end
      G.RefreshRoster()
    end)
    btn:SetScript("OnEnter", function(self) self._label:SetTextColor(1, 1, 1) end)
    btn:SetScript("OnLeave", function(self) self._label:SetTextColor(1, 0.82, 0) end)

    -- Vertical separator on the left edge of every column after the first.
    if i > 1 then
      local sep = header:CreateTexture(nil, "ARTWORK")
      sep:SetTexture("Interface\\Buttons\\WHITE8X8")
      sep:SetVertexColor(1, 1, 1, 0.10)
      sep:SetWidth(1)
      sep:SetPoint("TOP", btn, "TOPLEFT", 0, -3)
      sep:SetPoint("BOTTOM", btn, "BOTTOMLEFT", 0, 3)
    end
  end

  -- FauxScrollFrame list.
  local scroll = CreateFrame("ScrollFrame", "NE_GuildRosterScroll", panel, "FauxScrollFrameTemplate")
  scroll:SetPoint("TOPLEFT", panel, "TOPLEFT", 0, -52)
  scroll:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -24, 2)
  scroll:SetScript("OnVerticalScroll", function(self, offset)
    FauxScrollFrame_OnVerticalScroll(self, offset, ROW_HEIGHT, G.RefreshRoster)
  end)
  panel.Scroll = scroll
  scroll.ScrollBar = _G["NE_GuildRosterScrollScrollBar"]   -- 3.3.5a template doesn't set the parentKey
  -- Modern minimal scrollbar. BuildCustom, not Reskin — same reasoning as the Guild Event Log list
  -- a few hundred lines up in Window.lua (Reskin doesn't render for FauxScrollFrame lists).
  -- Full-hide-when-fits (no alwaysShow) proved unreliable in practice (owner report 2026-07-17,
  -- the Show Offline toggle case: "bars not re-hiding after not being needed anymore"). Switched to
  -- alwaysShow = true instead (owner steer: "make them act the same as the profession scrollbars")
  -- — the same convention already working for Professions/Auction House/Guild Event Log: track +
  -- arrows stay visible always, only the thumb hides when content fits. Strata bumped to DIALOG:
  -- this window runs at DIALOG strata (createWindow below), and BuildCustom's bar defaults to HIGH,
  -- which renders BEHIND DIALOG content — the same trap already hit and fixed for the Event Log.
  if NE.scrollbar and NE.scrollbar.BuildCustom then
    -- x = -8 (owner steer 2026-07-17: "move the roster scrollbar right by 10 pixels too" — same
    -- fix as the Friends/Ignore lists). BuildCustom's default inset is x=-2; opts.x is negated
    -- internally (xInset = -opts.x), so -8 yields an actual xInset of 8, 10px right of default.
    local ok, bar = pcall(NE.scrollbar.BuildCustom, scroll, { x = -7, alwaysShow = true })
    if ok and bar then
      bar:SetFrameStrata("DIALOG")
      bar:SetFrameLevel((scroll:GetFrameLevel() or 1) + 10)
      if bar._upBtn then bar._upBtn:SetFrameStrata("DIALOG"); bar._upBtn:SetFrameLevel(bar:GetFrameLevel() + 1) end
      if bar._downBtn then bar._downBtn:SetFrameStrata("DIALOG"); bar._downBtn:SetFrameLevel(bar:GetFrameLevel() + 1) end
    end
  end

  -- Row buttons.
  panel.Rows = {}
  for i = 1, NUM_ROWS do
    local row = CreateFrame("Button", nil, panel)
    row:SetHeight(ROW_HEIGHT)
    if i == 1 then
      row:SetPoint("TOPLEFT", scroll, "TOPLEFT", 0, 0)
    else
      row:SetPoint("TOPLEFT", panel.Rows[i - 1], "BOTTOMLEFT", 0, 0)
    end
    row:SetPoint("RIGHT", scroll, "RIGHT", 0, 0)
    row:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")

    -- Alternating row stripe (reference frame bands its rows; a flat list reads as a wall of text).
    local stripe = row:CreateTexture(nil, "BACKGROUND")
    stripe:SetTexture("Interface\\Buttons\\WHITE8X8")
    stripe:SetVertexColor(1, 1, 1, (i % 2 == 0) and 0.03 or 0)
    stripe:SetAllPoints(row)
    row._stripe = stripe

    row.cells = {}
    for c, col in ipairs(COLUMNS) do
      if col.icon then
        -- Class column renders the class ICON, not text.
        local tex = row:CreateTexture(nil, "OVERLAY")
        tex:SetSize(ROW_HEIGHT - 4, ROW_HEIGHT - 4)
        tex:SetPoint("LEFT", row, "LEFT", col.x + (col.w - (ROW_HEIGHT - 4)) / 2, 0)
        row.cells[c] = tex
      else
        local fs = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")   -- bumped 1 size, owner 2026-07-17
        fs:SetPoint("LEFT", row, "LEFT", col.x, 0)
        if col.w > 0 then fs:SetWidth(col.w) else fs:SetPoint("RIGHT", row, "RIGHT", -2, 0) end
        fs:SetJustifyH(col.justify)
        fs:SetWordWrap(false)
        row.cells[c] = fs
      end
    end

    row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    row:SetScript("OnClick", function(self, button)
      if not self._index then return end
      if button == "RightButton" then
        openRosterMenu(self._index)
        return
      end
      if SetGuildRosterSelection then SetGuildRosterSelection(self._index) end
      showMemberDetail(f, self._index)
    end)
    panel.Rows[i] = row
  end

  buildMemberDetail(f)
end

-- SHOW-OFFLINE FILTERING: read the native APIs directly, exactly as Blizzard's own default guild UI
-- does — no client-side re-filtering, no force-toggling GetGuildRosterShowOffline from in here.
--
-- An earlier version of this file tried to compensate for the checkbox appearing to do nothing by
-- forcing SetGuildRosterShowOffline(true) before every scan and restoring it after. That call
-- synchronously fires GUILD_ROSTER_UPDATE on this client — proven by a live crash (C stack overflow,
-- this function recursing into itself via that very event) — and, worse, that refire fans out into
-- EVERY OTHER addon's handler for the same event, including the base DragonUI addon's version-
-- broadcast system, which sent an unthrottled guild-chat spam storm to every guildmate who had the
-- Roster tab open. Blizzard's default UI never does this: it sets the flag ONLY from the checkbox's
-- own OnClick (see below), then trusts GetNumGuildMembers()/GetGuildRosterInfo() to already reflect
-- it. Matching that removes the entire class of bug rather than working around it.
function G.RefreshRoster()
  local f = G.frame
  local panel = f and f.RosterFrame
  if not (panel and panel._built and panel:IsShown()) then return end
  if not GetNumGuildMembers then return end

  local total = GetNumGuildMembers() or 0
  local offset = FauxScrollFrame_GetOffset(panel.Scroll)

  for i = 1, NUM_ROWS do
    local idx = offset + i
    local row = panel.Rows[i]
    if idx <= total then
      local name, rank, _, level, class, zone, note, _, online, _, classFile = GetGuildRosterInfo(idx)
      row._index = idx
      local dim = online and 1 or 0.5

      row.cells[1]:SetText(level or "")
      row.cells[1]:SetTextColor(1 * dim, 0.82 * dim, 0)

      -- Class ICON (cell 2). Falls back to hidden when the class is unknown, so we never paint
      -- the whole 4x4 sheet into the cell.
      if setClassIcon(row.cells[2], classFile) then
        row.cells[2]:SetAlpha(dim)
        row.cells[2]:Show()
      else
        row.cells[2]:Hide()
      end

      row.cells[3]:SetText(name or "")
      row.cells[3]:SetTextColor(classColor(classFile))
      row.cells[3]:SetAlpha(online and 1 or 0.5)

      row.cells[4]:SetText((online and (zone or "")) or (GUILD_OFFLINE or "Offline"))
      row.cells[5]:SetText(rank or "")
      row.cells[6]:SetText(note or "")
      for c = 4, 6 do row.cells[c]:SetTextColor(dim, dim, dim) end

      row:Show()
    else
      row._index = nil
      row:Hide()
    end
  end

  FauxScrollFrame_Update(panel.Scroll, total, NUM_ROWS, ROW_HEIGHT)
  -- Explicit, synchronous re-sync (owner report 2026-07-17: the scrollbar wasn't reliably
  -- re-hiding when Show Offline shrank the list back to fitting the viewport) — see
  -- NE.scrollbar.SyncCustom's own comment in core/ScrollbarReskin.lua for why this is called
  -- directly here instead of trusting a hook/event/poll to catch it. total/NUM_ROWS passed through
  -- so it can defensively clamp the slider itself when the list fits (thumb-stuck-visible fix).
  if NE.scrollbar and NE.scrollbar.SyncCustom then NE.scrollbar.SyncCustom(panel.Scroll, total, NUM_ROWS) end

  -- Member count on the header row (uses the cached online count — recomputed only on roster
  -- changes, not on every scroll; see recountOnline below).
  if panel.MemberCount then
    if G._onlineCount then
      panel.MemberCount:SetText(string.format("%d/%d %s", G._onlineCount, total, GUILD_MEMBERS or "Members"))
    else
      panel.MemberCount:SetText(string.format("%d %s", total, GUILD_MEMBERS or "Members"))
    end
  end
end

-- Recompute the online member count once (O(n)); cached for the cheap per-scroll refresh. Also
-- feeds the Roster tab's left GuildColumn (Window.lua), which shows the same name/count under its
-- crest badge.
local function recountOnline()
  if not GetNumGuildMembers then return end
  -- Explicit `true`: this client's API dump documents an optional includeOffline arg, so ask for the
  -- FULL total explicitly rather than depending on whatever GetGuildRosterShowOffline() happens to
  -- currently be — this is a pure read, no flag ever touched here.
  local total = GetNumGuildMembers(true) or GetNumGuildMembers() or 0
  local online = 0
  for i = 1, total do
    local _, _, _, _, _, _, _, _, isOnline = GetGuildRosterInfo(i)
    if isOnline then online = online + 1 end
  end
  G._onlineCount = online

  local column = G.frame and G.frame.GuildColumn
  if column and column.SetGuild then
    column.SetGuild(IsInGuild() and GetGuildInfo("player") or nil, online, total)
  end
end

-- Live roster updates.
local ev = CreateFrame("Frame")
ev:RegisterEvent("GUILD_ROSTER_UPDATE")
ev:RegisterEvent("PLAYER_GUILD_UPDATE")
ev:SetScript("OnEvent", function()
  recountOnline()
  if G.RefreshRoster then G.RefreshRoster() end
end)
