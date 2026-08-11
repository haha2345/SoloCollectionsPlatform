-- DragonUI_NewEra/modules/social/Friends.lua — the Friends tab, with its Friends/Ignore SUB-tabs.
--
-- Structure mirrors the stock 3.3.5a Socials window (owner supplied the stock frames as reference
-- 2026-07-16): the Friends bottom-tab hosts two sub-tabs — Friends and Ignore — each with its own
-- list and its own button row. Entries are TWO-line (status icon + "Name, Level N Class" over the
-- zone), not the single-line rows of the first pass.
--
-- Native WotLK APIs: GetNumFriends / GetFriendInfo / AddFriend / RemoveFriend / SetSelectedFriend
-- and GetNumIgnores / GetIgnoreName / DelIgnore.
-- Built from Window.lua via SO.SetupFriends(f); exposes SO.RefreshFriends() / SO.RefreshIgnore().

local NE = DragonUI_NewEra
if not NE then return end

NE.social = NE.social or {}
local SO = NE.social

-- Two-line entries, sized for a 620px-wide window. Row height 28 -> 34 (owner steer 2026-07-17:
-- text read too small for the frame at 28px/small fonts — bumped the name/info font sizes back up
-- a step, which needs the extra height back; still packed with no dead space beyond what those
-- fonts need, unlike the original 34px rows which had slack on top of small-font text). Fitted to
-- the sub-view's scroll well: the Friends panel is ~480 tall, minus the sub-tab strip (26) and the
-- button row (34) => ~412 => 12 rows at 34px. Rows aren't clipped by the scroll frame, so don't
-- overshoot.
local NUM_ROWS   = 12
local ROW_HEIGHT = 34

-- Ignore rows are single-line, so they fit a smaller extent.
local IGNORE_ROWS   = 25
local IGNORE_HEIGHT = 16

local STATUS_ONLINE  = FRIENDS_TEXTURE_ONLINE  or "Interface\\FriendsFrame\\StatusIcon-Online"
local STATUS_AFK     = FRIENDS_TEXTURE_AFK     or "Interface\\FriendsFrame\\StatusIcon-Away"
local STATUS_DND     = FRIENDS_TEXTURE_DND     or "Interface\\FriendsFrame\\StatusIcon-DnD"
local STATUS_OFFLINE = FRIENDS_TEXTURE_OFFLINE or "Interface\\FriendsFrame\\StatusIcon-Offline"

-- Modern minimal scrollbar. The full-hide-when-fits behavior (opts.alwaysShow not passed) proved
-- unreliable in practice across several fix attempts (owner report 2026-07-17, repeated: "still
-- doesnt hide"). Switched to alwaysShow = true instead (owner steer: "make them act the same as
-- the profession scrollbars") — the SAME convention already used and working for the Professions
-- recipe list, Auction House Browse/Auctions tabs, and the Guild Event Log: track + arrows stay
-- visible always, only the thumb hides when content fits. Simpler and already proven, at the cost
-- of the bar chrome never fully disappearing. The strata bump IS still required: the Social window
-- runs at DIALOG strata (Window.lua), and BuildCustom's bar defaults to HIGH — a HIGH bar renders
-- BEHIND DIALOG content, i.e. invisible. Same trap already documented/fixed for the Guild Event Log.
-- x = -8 (owner steer 2026-07-17: "move the scrollbar right by about 10 pixels"): BuildCustom's
-- own default inset is x=-2 (bar sits 2px LEFT of the scroll's right edge); opts.x is negated
-- internally (xInset = -opts.x), so -8 here yields an actual xInset of 8 — 10px further right than
-- the -2 default.
local function buildModernScrollbar(scroll)
  if not (NE.scrollbar and NE.scrollbar.BuildCustom) then return end
  local ok, bar = pcall(NE.scrollbar.BuildCustom, scroll, { x = -8, alwaysShow = true })
  if not (ok and bar) then return end
  bar:SetFrameStrata("DIALOG")
  bar:SetFrameLevel((scroll:GetFrameLevel() or 1) + 10)
  if bar._upBtn then bar._upBtn:SetFrameStrata("DIALOG"); bar._upBtn:SetFrameLevel(bar:GetFrameLevel() + 1) end
  if bar._downBtn then bar._downBtn:SetFrameStrata("DIALOG"); bar._downBtn:SetFrameLevel(bar:GetFrameLevel() + 1) end
end

local function statusTexture(connected, status)
  if not connected then return STATUS_OFFLINE end
  if status == (CHAT_FLAG_AFK or "<Away>") then return STATUS_AFK end
  if status == (CHAT_FLAG_DND or "<Busy>") then return STATUS_DND end
  return STATUS_ONLINE
end

-- "Name, Level 60 Warlock" — built explicitly rather than through FRIENDS_LIST_TEMPLATE. That
-- global does NOT have retail's "%s, Level %d %s" shape on this 3.3.5a client: feeding it
-- (name, level, class) rendered "- Parkanator 60" (it clearly carries fewer/reordered specifiers,
-- so the class arg was dropped). Concatenation is client-shape-independent.
local function friendNameText(name, level, class)
  local out = tostring(name or "")
  if level and level ~= 0 then
    out = out .. ", " .. (LEVEL or "Level") .. " " .. tostring(level)
  end
  if class and class ~= "" and class ~= UNKNOWN then
    out = out .. " " .. tostring(class)
  end
  return out
end

-- ---------------------------------------------------------------------------
-- Sub-tabs (Friends | Ignore). A SECOND tab group can't share the frame-level PanelTemplates
-- state the bottom tabs use (frame.selectedTab / numTabs is per-frame), so the selected art is
-- driven manually — the same approach modules/spellbook/Spellbook.lua uses. ReskinClassicTab
-- paints the ACTIVE (gold) atlas onto the *Disabled pieces, so SELECTED = show *Disabled.
-- ---------------------------------------------------------------------------
local function setTabArt(tab, selected)
  if not tab then return end
  local n = tab:GetName()
  local function set(suffix, show)
    local t = _G[n .. suffix]
    if t then if show then t:Show() else t:Hide() end end
  end
  set("Left", not selected); set("Middle", not selected); set("Right", not selected)
  set("LeftDisabled", selected); set("MiddleDisabled", selected); set("RightDisabled", selected)
  local hl = tab._neCustomHL
  if hl then
    local a = selected and 0 or 0.4
    if hl.left   then hl.left:SetAlpha(a)   end
    if hl.middle then hl.middle:SetAlpha(a) end
    if hl.right  then hl.right:SetAlpha(a)  end
  end
end

local SUBTABS = {
  { key = "FRIENDS", label = FRIENDS or "Friends" },
  { key = "IGNORE",  label = IGNORE or "Ignore" },
}

local function buildSubTabs(panel)
  panel._subTabs = {}
  local prev
  for i, def in ipairs(SUBTABS) do
    local name = "NE_SocialFriendsSubTab" .. i
    local tab = CreateFrame("Button", name, panel, "CharacterFrameTabButtonTemplate")
    tab:SetID(i)
    tab:SetText(def.label)
    tab._key = def.key
    if prev then
      tab:SetPoint("TOPLEFT", prev, "TOPRIGHT", 1, 0)
    else
      tab:SetPoint("TOPLEFT", panel, "TOPLEFT", 4, 0)
    end
    if NE.tabs and NE.tabs.ReskinClassicTab then NE.tabs.ReskinClassicTab(name) end
    if NE.tabs and NE.tabs.MakeTopTab then NE.tabs.MakeTopTab(name) end   -- these point UP
    tab:SetScript("OnClick", function(self)
      if PlaySound then PlaySound("igCharacterInfoTab") end
      SO.SetFriendsSubTab(self._key)
    end)
    panel._subTabs[i] = tab
    prev = tab
  end
end

-- ---------------------------------------------------------------------------
-- Own status toggle (owner steer 2026-07-17: "friends tab is missing the status toggle" — stock
-- FriendsFrame has an Available/Away/Busy control, ours had none). AFK/DND are TOGGLES on this
-- client, not a direct "set" API — the same primitive the native /afk and /dnd slash commands use
-- (SendChatMessage(msg, "AFK"/"DND")) — so only fire the call when the target state isn't already
-- active, and going "Available" just toggles off whichever flag is currently set.
-- ---------------------------------------------------------------------------
local function setOwnStatus(mode)
  local isAFK = UnitIsAFK and UnitIsAFK("player")
  local isDND = UnitIsDND and UnitIsDND("player")
  if mode == "AFK" then
    if not isAFK then SendChatMessage(AFK_MESSAGE or "", "AFK") end
  elseif mode == "DND" then
    if not isDND then SendChatMessage(DND_MESSAGE or "", "DND") end
  else
    if isAFK then SendChatMessage(AFK_MESSAGE or "", "AFK") end
    if isDND then SendChatMessage(DND_MESSAGE or "", "DND") end
  end
end

local statusMenuFrame
local function openStatusMenu(anchor)
  if not EasyMenu then return end
  if not statusMenuFrame then
    statusMenuFrame = CreateFrame("Frame", "NE_SocialStatusMenu", UIParent, "UIDropDownMenuTemplate")
  end
  local menu = {
    { text = "Available", notCheckable = true, func = function() setOwnStatus("AVAILABLE") end },
    { text = "Away",      notCheckable = true, func = function() setOwnStatus("AFK") end },
    { text = "Busy",      notCheckable = true, func = function() setOwnStatus("DND") end },
  }
  EasyMenu(menu, statusMenuFrame, anchor, 0, 0, "MENU")
end

local function buildStatusButton(panel)
  local btn = CreateFrame("Button", nil, panel)
  btn:SetSize(110, 20)
  btn:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -4, -2)

  local icon = btn:CreateTexture(nil, "ARTWORK")
  icon:SetSize(14, 14)
  icon:SetPoint("LEFT", btn, "LEFT", 2, 0)
  btn.icon = icon

  local label = btn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  label:SetPoint("LEFT", icon, "RIGHT", 4, 0)
  label:SetJustifyH("LEFT")
  btn.label = label

  local arrow = btn:CreateTexture(nil, "OVERLAY")
  arrow:SetTexture("Interface\\ChatFrame\\ChatFrameExpandArrow")
  arrow:SetSize(10, 10)
  arrow:SetPoint("LEFT", label, "RIGHT", 2, 0)

  btn:SetScript("OnClick", function(self) openStatusMenu(self) end)
  panel.StatusButton = btn
end

function SO.RefreshOwnStatus()
  local f = SO.frame
  local btn = f and f.FriendsPanel and f.FriendsPanel.StatusButton
  if not btn then return end
  local isAFK = UnitIsAFK and UnitIsAFK("player")
  local isDND = UnitIsDND and UnitIsDND("player")
  if isDND then
    btn.icon:SetTexture(STATUS_DND); btn.label:SetText("Busy")
  elseif isAFK then
    btn.icon:SetTexture(STATUS_AFK); btn.label:SetText("Away")
  else
    btn.icon:SetTexture(STATUS_ONLINE); btn.label:SetText("Available")
  end
end

function SO.SetFriendsSubTab(key)
  local f = SO.frame
  local panel = f and f.FriendsPanel
  if not (panel and panel._subTabs) then return end
  panel._sub = key
  for _, tab in ipairs(panel._subTabs) do
    setTabArt(tab, tab._key == key)
  end
  if panel.FriendsView then panel.FriendsView:SetShown(key == "FRIENDS") end
  if panel.IgnoreView  then panel.IgnoreView:SetShown(key == "IGNORE") end
  if key == "FRIENDS" then
    if ShowFriends then ShowFriends() end
    SO.RefreshFriends()
  else
    SO.RefreshIgnore()
  end
end

-- ---------------------------------------------------------------------------
-- Right-click context menus (owner steer 2026-07-17: rows had no context menu at all — right-click
-- was never wired up; later expanded to the full Whisper/Invite/Set Note/Ignore/Remove Friend/
-- Cancel spec). Native EasyMenu/UIDropDownMenu, same pattern as
-- modules/bags/CombinedBag.lua:CB.OpenMenu (confirmed working on 3.3.5a).
--
-- SetFriendNotes(name, notes) confirmed via Blizzard's own auto-generated API metadata
-- (Blizzard_APIDocumentationGenerated/FriendListDocumentation.lua, Classic branch of
-- Gethe/wow-ui-source): name-based, distinct from the separate index-based
-- `SetFriendNotesByIndex(index, notes)`. (The !!!ClassicAPI shim aliases both C_FriendList names
-- onto the same raw global, which looks index-suggestive but is just a shim mislabel.)
-- ---------------------------------------------------------------------------
StaticPopupDialogs["NE_SET_FRIEND_NOTE"] = {
  text = "Enter a note for %s:",
  button1 = ACCEPT or "Accept",
  button2 = CANCEL or "Cancel",
  hasEditBox = true,
  maxLetters = 48,
  OnShow = function(self)
    self.editBox:SetText(self.data and self.data.note or "")
    self.editBox:HighlightText()
  end,
  OnAccept = function(self)
    local text = self.editBox:GetText()
    if self.data and self.data.name and SetFriendNotes then SetFriendNotes(self.data.name, text) end
    if SO.RefreshFriends then SO.RefreshFriends() end
  end,
  EditBoxOnEnterPressed = function(self) self:GetParent():Hide() end,
  EditBoxOnEscapePressed = function(self) self:GetParent():Hide() end,
  timeout = 0, whileDead = true, hideOnEscape = true,
}

local friendMenuFrame
local function openFriendMenu(idx)
  if not (EasyMenu and idx) then return end
  if not friendMenuFrame then
    friendMenuFrame = CreateFrame("Frame", "NE_SocialFriendMenu", UIParent, "UIDropDownMenuTemplate")
  end
  local name, _, _, _, connected, _, note = GetFriendInfo(idx)
  local menu = { { text = name or "", isTitle = true, notCheckable = true } }
  if connected then
    menu[#menu + 1] = { text = SEND_MESSAGE or "Whisper", notCheckable = true, func = function()
        if name and ChatFrame_SendTell then ChatFrame_SendTell(name) end
      end }
    menu[#menu + 1] = { text = GROUP_INVITE or "Invite", notCheckable = true, func = function()
        if name and InviteUnit then InviteUnit(name) end
      end }
  end
  menu[#menu + 1] = { text = "Set Note", notCheckable = true, func = function()
      if name then StaticPopup_Show("NE_SET_FRIEND_NOTE", name, nil, { name = name, note = note }) end
    end }
  menu[#menu + 1] = { text = IGNORE or "Ignore", notCheckable = true, func = function()
      if name and AddIgnore then AddIgnore(name) end
    end }
  menu[#menu + 1] = { text = REMOVE_FRIEND or "Remove Friend", notCheckable = true, func = function()
      if RemoveFriend then RemoveFriend(idx) end
      SO.RefreshFriends()
    end }
  menu[#menu + 1] = { text = CANCEL or "Cancel", notCheckable = true }
  EasyMenu(menu, friendMenuFrame, "cursor", 0, 0, "MENU")
end

local ignoreMenuFrame
local function openIgnoreMenu(idx)
  if not (EasyMenu and idx) then return end
  if not ignoreMenuFrame then
    ignoreMenuFrame = CreateFrame("Frame", "NE_SocialIgnoreMenu", UIParent, "UIDropDownMenuTemplate")
  end
  local name = GetIgnoreName and GetIgnoreName(idx)
  local menu = {
    { text = name or "", isTitle = true, notCheckable = true },
    { text = DELETE or "Remove", notCheckable = true, func = function()
        if name and DelIgnore then DelIgnore(name) end
        SO.RefreshIgnore()
      end },
    { text = CANCEL or "Cancel", notCheckable = true },
  }
  EasyMenu(menu, ignoreMenuFrame, "cursor", 0, 0, "MENU")
end

-- ---------------------------------------------------------------------------
-- Friends view.
-- ---------------------------------------------------------------------------
local function setupFriendsView(view)
  view._selected = nil

  -- Periodic re-poll while the tab is actually visible (owner report 2026-07-17: "friends list
  -- location doesn't update if the friend moves zones when the tab is open"). The server doesn't
  -- proactively push a FRIENDLIST_UPDATE when a friend's zone changes — only login/logoff/add/
  -- remove reliably fire that event — so the zone/level/area fields in GetFriendInfo go stale
  -- unless something re-requests them. Stock FriendsFrame does the same thing: an OnUpdate ticker
  -- that re-calls ShowFriends() every few seconds while shown. Scoped to `view` itself (not the
  -- whole window) so it naturally stops ticking once the Friends sub-tab isn't the visible one.
  local FRIENDS_REFRESH_INTERVAL = 5
  view:SetScript("OnUpdate", function(self, elapsed)
    self._refreshElapsed = (self._refreshElapsed or 0) + elapsed
    if self._refreshElapsed >= FRIENDS_REFRESH_INTERVAL then
      self._refreshElapsed = 0
      if ShowFriends then ShowFriends() end
    end
  end)

  local scroll = CreateFrame("ScrollFrame", "NE_SocialFriendsScroll", view, "FauxScrollFrameTemplate")
  -- Inset 3px from the view's edges (owner steer 2026-07-17), on top of the existing scrollbar
  -- clearance (-24). Bottom inset 37 -> 5 (owner steer 2026-07-17: "make sure it extends to the
  -- bottom of the frame") — the 37px used to clear the Add Friend/Ignore Player button that lived
  -- inside `view`; that button now anchors to the panel's outer chrome instead (see below), so this
  -- clearance was stale dead space keeping both the list and its scrollbar short of the bottom.
  scroll:SetPoint("TOPLEFT", view, "TOPLEFT", 3, -5)
  scroll:SetPoint("BOTTOMRIGHT", view, "BOTTOMRIGHT", -27, 5)
  scroll:SetScript("OnVerticalScroll", function(self, o)
    FauxScrollFrame_OnVerticalScroll(self, o, ROW_HEIGHT, SO.RefreshFriends)
  end)
  view._scroll = scroll
  scroll.ScrollBar = _G["NE_SocialFriendsScrollScrollBar"]   -- 3.3.5a template has no parentKey
  buildModernScrollbar(scroll)

  view._rows = {}
  for i = 1, NUM_ROWS do
    local row = CreateFrame("Button", nil, view)
    row:SetHeight(ROW_HEIGHT)
    -- Top padding 0 -> -4 -> -9 (owner steer 2026-07-17: the first row sat flush against the
    -- inset's top edge with no breathing room; then another +5px on top of that).
    if i == 1 then row:SetPoint("TOPLEFT", scroll, "TOPLEFT", 0, -9)
    else row:SetPoint("TOPLEFT", view._rows[i - 1], "BOTTOMLEFT", 0, 0) end
    row:SetPoint("RIGHT", scroll, "RIGHT", 0, 0)
    row:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")

    -- Alternating row stripe (owner steer 2026-07-17: "guild roster has a stripe like effect... can
    -- the friends list also have this?" — same treatment as modules/guild/Roster.lua's row stripe).
    local stripe = row:CreateTexture(nil, "BACKGROUND")
    stripe:SetTexture("Interface\\Buttons\\WHITE8X8")
    stripe:SetVertexColor(1, 1, 1, (i % 2 == 0) and 0.03 or 0)
    stripe:SetAllPoints(row)
    row._stripe = stripe

    local sel = row:CreateTexture(nil, "BACKGROUND")
    sel:SetTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight")
    sel:SetBlendMode("ADD"); sel:SetAllPoints(row); sel:SetAlpha(0.4); sel:Hide()
    row._sel = sel

    -- Icon 12 -> 14, name/info bumped to the next font size up (owner steer 2026-07-17: text read
    -- too small for a 620px-wide window; the shrink toward the reference's plainer dot went a step
    -- too far on the text itself).
    local icon = row:CreateTexture(nil, "ARTWORK")
    icon:SetSize(14, 14)
    icon:SetPoint("TOPLEFT", row, "TOPLEFT", 6, -3)
    row.icon = icon

    local name = row:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    name:SetPoint("TOPLEFT", icon, "TOPRIGHT", 5, 2)
    name:SetPoint("RIGHT", row, "RIGHT", -4, 0)
    name:SetJustifyH("LEFT"); name:SetWordWrap(false)
    row.name = name

    local info = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    info:SetPoint("TOPLEFT", name, "BOTTOMLEFT", 0, -1)
    info:SetPoint("RIGHT", row, "RIGHT", -4, 0)
    info:SetJustifyH("LEFT"); info:SetWordWrap(false)
    row.info = info

    -- Thin row divider (owner steer 2026-07-17, reference NewEra screenshot: entries are separated
    -- by a faint horizontal line, which our rows never had).
    local divider = row:CreateTexture(nil, "ARTWORK")
    divider:SetTexture("Interface\\Buttons\\WHITE8X8")
    divider:SetVertexColor(1, 1, 1, 0.08)
    divider:SetHeight(1)
    divider:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 4, 0)
    divider:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", -4, 0)
    row._divider = divider

    row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    row:SetScript("OnClick", function(self, button)
      if not self._index then return end
      if button == "RightButton" then
        openFriendMenu(self._index)
        return
      end
      view._selected = self._index
      if SetSelectedFriend then SetSelectedFriend(self._index) end
      SO.RefreshFriends()
    end)
    view._rows[i] = row
  end

  local add = CreateFrame("Button", nil, view, "UIPanelButtonTemplate")
  add:SetSize(116, 22); add:SetText(ADD_FRIEND or "Add Friend")
  -- Anchored to the PANEL (view's parent), not `view` itself (owner report 2026-07-17: button was
  -- sitting inside the dark inset, overlapping the last row, instead of the outer grey frame below
  -- it). Panel's own bottom edge sits 36px above the window's true bottom (Window.lua's buildPanels
  -- content-panel offset) — that 36px band is the outer chrome strip the button belongs in. Still
  -- parented to `view` itself (unchanged) so it keeps auto-hiding with the Friends sub-tab; only
  -- the anchor TARGET moves to the panel, which a child's SetPoint can do independent of parentage.
  add:SetPoint("BOTTOMLEFT", view:GetParent(), "BOTTOMLEFT", 0, -29)
  -- Stock Blizzard invite dialog (owner steer 2026-07-17, same fix as the Guild Invite button:
  -- "fix the add friend button to do this also"). REVERTED the inline name-prompt above — that was
  -- built on an unverified assumption that StaticPopup_Show("ADD_FRIEND") silently no-ops here; on a
  -- standard 3.3.5a client this is the same long-standing popup the native FriendsFrame Add Friend
  -- button itself opens (hasEditBox, OnAccept calls AddFriend() with the typed name internally). The
  -- list refresh doesn't need a manual call either — FRIENDLIST_UPDATE (registered below) already
  -- drives SO.RefreshFriends() once the server round-trip lands.
  -- Targeting a player adds them directly (owner steer 2026-07-17: "click add friend while
  -- targeting someone it should add them to my friends list") — skips the popup and its typed
  -- name entirely; AddFriend() itself already reports success/failure via the server's own system
  -- message (already-friends, target list full, etc.), so no extra feedback UI is needed here.
  -- No target (or targeting something that isn't a player) falls back to the manual-entry popup.
  add:SetScript("OnClick", function()
    if UnitExists("target") and UnitIsPlayer("target") and not UnitIsUnit("target", "player") then
      AddFriend(UnitName("target"))
    else
      StaticPopup_Show("ADD_FRIEND")
    end
  end)

  -- Send Message / Remove Friend buttons REMOVED (owner steer 2026-07-17): both actions are
  -- already on the row's right-click menu (openFriendMenu above), so the dedicated buttons were
  -- redundant.
end

function SO.RefreshFriends()
  local f = SO.frame
  local view = f and f.FriendsPanel and f.FriendsPanel.FriendsView
  if not (view and view._rows) then return end

  local total = (GetNumFriends and GetNumFriends()) or 0
  local offset = FauxScrollFrame_GetOffset(view._scroll)

  for i = 1, NUM_ROWS do
    local idx = offset + i
    local row = view._rows[i]
    if idx <= total then
      local name, level, class, area, connected, status, note = GetFriendInfo(idx)
      row._index = idx
      row.icon:SetTexture(statusTexture(connected, status))
      -- Owner report 2026-07-17: "Notes for people on the friend tab dont show up" — Set Note
      -- (added to the row's right-click menu) wrote via SetFriendNotes fine, but GetFriendInfo's
      -- 7th return (the note) was never read here, so nothing on the row ever displayed it.
      -- Appended to the info line, after the zone/offline text.
      local noteSuffix = (note and note ~= "") and ("  |cff40ff40(" .. note .. ")|r") or ""
      if connected then
        row.name:SetText(friendNameText(name, level, class))
        row.name:SetTextColor(1, 0.82, 0)
        row.info:SetText((area or "") .. noteSuffix)
        row.info:SetTextColor(0.5, 0.5, 0.5)
      else
        row.name:SetText(tostring(name or ""))
        row.name:SetTextColor(0.5, 0.5, 0.5)
        row.info:SetText((FRIENDS_LIST_OFFLINE or "Offline") .. noteSuffix)
        row.info:SetTextColor(0.4, 0.4, 0.4)
      end
      if row._sel then row._sel:SetShown(idx == view._selected) end
      row:Show()
    else
      row._index = nil
      if row._sel then row._sel:Hide() end
      row:Hide()
    end

    if i == 1 then
      row:SetPoint("TOPLEFT", view._scroll, "TOPLEFT", 0, -9)
    else
      row:SetPoint("TOPLEFT", view._rows[i - 1], "BOTTOMLEFT", 0, 0)
    end
  end
  FauxScrollFrame_Update(view._scroll, total, NUM_ROWS, ROW_HEIGHT)
  -- Explicit, synchronous re-sync (owner report 2026-07-17, same fix as Guild Roster) — see
  -- NE.scrollbar.SyncCustom's comment in core/ScrollbarReskin.lua. total/NUM_ROWS passed through so
  -- it can defensively clamp the slider itself when the list fits (thumb-stuck-visible fix).
  if NE.scrollbar and NE.scrollbar.SyncCustom then NE.scrollbar.SyncCustom(view._scroll, total, NUM_ROWS) end
end

-- ---------------------------------------------------------------------------
-- Ignore view.
-- ---------------------------------------------------------------------------
local function setupIgnoreView(view)
  view._selected = nil

  local scroll = CreateFrame("ScrollFrame", "NE_SocialIgnoreScroll", view, "FauxScrollFrameTemplate")
  -- Inset 3px from the view's edges (owner steer 2026-07-17), on top of the existing scrollbar
  -- clearance (-24). Bottom inset 37 -> 5 (owner steer 2026-07-17: "make sure it extends to the
  -- bottom of the frame") — the 37px used to clear the Add Friend/Ignore Player button that lived
  -- inside `view`; that button now anchors to the panel's outer chrome instead (see below), so this
  -- clearance was stale dead space keeping both the list and its scrollbar short of the bottom.
  scroll:SetPoint("TOPLEFT", view, "TOPLEFT", 3, -5)
  scroll:SetPoint("BOTTOMRIGHT", view, "BOTTOMRIGHT", -27, 5)
  scroll:SetScript("OnVerticalScroll", function(self, o)
    FauxScrollFrame_OnVerticalScroll(self, o, IGNORE_HEIGHT, SO.RefreshIgnore)
  end)
  view._scroll = scroll
  scroll.ScrollBar = _G["NE_SocialIgnoreScrollScrollBar"]
  buildModernScrollbar(scroll)

  view._rows = {}
  for i = 1, IGNORE_ROWS do
    local row = CreateFrame("Button", nil, view)
    row:SetHeight(IGNORE_HEIGHT)
    -- Top padding 0 -> -4 (owner steer 2026-07-17: the first row sat flush against the inset's top
    -- edge with no breathing room).
    if i == 1 then row:SetPoint("TOPLEFT", scroll, "TOPLEFT", 0, -4)
    else row:SetPoint("TOPLEFT", view._rows[i - 1], "BOTTOMLEFT", 0, 0) end
    row:SetPoint("RIGHT", scroll, "RIGHT", 0, 0)
    row:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")

    local sel = row:CreateTexture(nil, "BACKGROUND")
    sel:SetTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight")
    sel:SetBlendMode("ADD"); sel:SetAllPoints(row); sel:SetAlpha(0.4); sel:Hide()
    row._sel = sel

    local name = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    name:SetPoint("LEFT", row, "LEFT", 6, 0)
    name:SetPoint("RIGHT", row, "RIGHT", -4, 0)
    name:SetJustifyH("LEFT"); name:SetWordWrap(false)
    row.name = name

    row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    row:SetScript("OnClick", function(self, button)
      if not self._index then return end
      if button == "RightButton" then
        openIgnoreMenu(self._index)
        return
      end
      view._selected = self._index; SO.RefreshIgnore()
    end)
    view._rows[i] = row
  end

  local add = CreateFrame("Button", nil, view, "UIPanelButtonTemplate")
  add:SetSize(116, 22); add:SetText(IGNORE_PLAYER or "Ignore Player")
  -- Same outer-chrome anchor fix as the Friends tab's Add Friend button above (owner report
  -- 2026-07-17): anchored to the panel (view's parent), not `view` itself, so it sits in the grey
  -- band below the dark inset instead of overlapping the last row.
  add:SetPoint("BOTTOMLEFT", view:GetParent(), "BOTTOMLEFT", 0, -29)
  -- Stock Blizzard dialog (owner steer 2026-07-17, same fix as the Guild Invite / Add Friend
  -- buttons: "use the blizzard ui not the one you did"). REVERTED the inline name-prompt — same
  -- disproven "StaticPopup_Show silently no-ops here" theory as the other two buttons; on a
  -- standard 3.3.5a client "ADD_IGNORE" is the same long-standing popup the native Ignore tab's
  -- own button opens (hasEditBox, OnAccept calls AddIgnore() with the typed name internally).
  add:SetScript("OnClick", function() StaticPopup_Show("ADD_IGNORE") end)

  -- Remove button REMOVED (owner steer 2026-07-17): already on the row's right-click menu
  -- (openIgnoreMenu above), so the dedicated button was redundant.
end

function SO.RefreshIgnore()
  local f = SO.frame
  local view = f and f.FriendsPanel and f.FriendsPanel.IgnoreView
  if not (view and view._rows) then return end

  local total = (GetNumIgnores and GetNumIgnores()) or 0
  local offset = FauxScrollFrame_GetOffset(view._scroll)

  for i = 1, IGNORE_ROWS do
    local idx = offset + i
    local row = view._rows[i]
    if idx <= total then
      row._index = idx
      row.name:SetText((GetIgnoreName and GetIgnoreName(idx)) or "")
      row.name:SetTextColor(1, 0.82, 0)
      if row._sel then row._sel:SetShown(idx == view._selected) end
      row:Show()
    else
      row._index = nil
      if row._sel then row._sel:Hide() end
      row:Hide()
    end
  end
  FauxScrollFrame_Update(view._scroll, total, IGNORE_ROWS, IGNORE_HEIGHT)
  -- Explicit, synchronous re-sync (owner report 2026-07-17, same fix as Guild Roster) — see
  -- NE.scrollbar.SyncCustom's comment in core/ScrollbarReskin.lua. total/IGNORE_ROWS passed through
  -- so it can defensively clamp the slider itself when the list fits (thumb-stuck-visible fix).
  if NE.scrollbar and NE.scrollbar.SyncCustom then NE.scrollbar.SyncCustom(view._scroll, total, IGNORE_ROWS) end
end

-- SO.SetupFriends builds the Friends panel + BOTH sub-views (Window.lua calls it once).
function SO.SetupFriends(f)
  local panel = f.FriendsPanel
  if not panel or panel._built then return end
  panel._built = true

  buildSubTabs(panel)
  buildStatusButton(panel)
  SO.RefreshOwnStatus()

  local function subView()
    local v = CreateFrame("Frame", nil, panel)
    v:SetPoint("TOPLEFT", panel, "TOPLEFT", 0, -28)   -- below the sub-tab strip
    v:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", 0, 0)
    v:Hide()

    -- Dark recessed backdrop (owner steer 2026-07-17: reference NewEra Friends tab reads much
    -- darker/flatter than our default stone chrome, which was showing straight through with
    -- nothing behind the rows — same treatment already used for the guild chat panel). Alpha
    -- lowered 0.90 -> 0.75 so the stone texture's grain still reads through as subtle mottling,
    -- rather than a flat solid block (reference has visible texture, not a flat fill).
    local bg = v:CreateTexture(nil, "BACKGROUND")
    bg:SetTexture("Interface\\Buttons\\WHITE8X8")
    bg:SetVertexColor(0.06, 0.06, 0.07, 0.75)
    bg:SetAllPoints(v)
    if NE.nineslice and NE.nineslice.AttachInset then pcall(NE.nineslice.AttachInset, v, 0, 0, 0, 0) end

    return v
  end
  panel.FriendsView = subView()
  panel.IgnoreView  = subView()

  setupFriendsView(panel.FriendsView)
  setupIgnoreView(panel.IgnoreView)

  SO.SetFriendsSubTab("FRIENDS")
end

local ev = CreateFrame("Frame")
for _, e in ipairs({ "FRIENDLIST_UPDATE", "IGNORELIST_UPDATE", "PLAYER_FLAGS_CHANGED" }) do
  pcall(ev.RegisterEvent, ev, e)
end
ev:SetScript("OnEvent", function(_, event, unit)
  if event == "FRIENDLIST_UPDATE" and SO.RefreshFriends then SO.RefreshFriends() end
  if event == "IGNORELIST_UPDATE" and SO.RefreshIgnore then SO.RefreshIgnore() end
  if event == "PLAYER_FLAGS_CHANGED" and (not unit or unit == "player") and SO.RefreshOwnStatus then
    SO.RefreshOwnStatus()
  end
end)
