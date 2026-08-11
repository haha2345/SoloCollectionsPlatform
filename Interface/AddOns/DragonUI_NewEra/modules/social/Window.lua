-- DragonUI_NewEra/modules/social/Window.lua — modern Social/Friends window shell (NE_FriendsFrame).
--
-- DOWNPORT of NewEra/Social/Social.lua. NewEra RESKINS Classic 1.15's modern ButtonFrameTemplate
-- FriendsFrame in place. 3.3.5a's FriendsFrame is the OLD parchment/stone frame — there is no
-- modern chrome to reskin — so, like the Auction House port, we BUILD a new window from
-- PortraitFrameTemplate and drive it off the classic friends/ignore/who APIs. The Guild tab opens
-- the separate NE_GuildFrame (NE.guild.Toggle) rather than hosting a guild view inline.
--
-- RENDER-BEFORE-WIRE: this file builds the shell (chrome, tabs, empty content panels). The list
-- content wires in Friends.lua (Friends/Ignore) and Who.lua via SO.SetupFriends / SO.SetupWho.

local NE = DragonUI_NewEra
if not NE then return end

NE.social = NE.social or {}
local SO = NE.social

local FRAME_NAME = "NE_FriendsFrame"
local MODULE = "Social"

-- Bottom tabs — the native 3.3.5a Socials set (owner supplied the stock frames as reference
-- 2026-07-16): Friends / Who / Guild / Chat / Raid. Ignore is NOT a bottom tab here; it's a
-- SUB-tab inside the Friends panel (see Friends.lua), exactly as the stock window does it.
-- Guild is an ACTION tab: it opens the standalone NE_GuildFrame instead of hosting a guild view.
local TABS = {
  { mode = "FRIENDS", label = FRIENDS or "Friends", panel = "FriendsPanel" },
  { mode = "WHO",     label = WHO or "Who", panel = "WhoPanel" },
  { mode = "GUILD",   label = GUILD or "Guild", action = true },
  { mode = "CHAT",    label = CHAT or "Chat", panel = "ChatPanel" },
  { mode = "RAID",    label = RAID or "Raid", panel = "RaidPanel" },
}

local function isModuleEnabled()
  return not (NE.modules and NE.modules.IsEnabled) or NE.modules.IsEnabled(MODULE)
end

-- ---------------------------------------------------------------------------
-- Chrome (rock + streaks + nineslice + portrait + title + close) — AH recipe.
-- ---------------------------------------------------------------------------
local function buildChrome(f)
  local body = f:CreateTexture(nil, "BACKGROUND", nil, -8)
  local rockPath = NE.tex and NE.tex.localFiles and NE.tex.localFiles[374155]
  body:SetTexture(rockPath or 374155, "REPEAT", "REPEAT")
  body:SetHorizTile(true); body:SetVertTile(true)
  body:SetPoint("TOPLEFT", f, "TOPLEFT", 0, -21)
  body:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", 0, 0)

  local streaks = f:CreateTexture(nil, "BORDER")
  if NE.tex and NE.tex.SetAtlas then NE.tex.SetAtlas(streaks, "_UI-Frame-TopTileStreaks", false) end
  streaks:SetPoint("TOPLEFT", f, "TOPLEFT", 6, -21)
  streaks:SetPoint("TOPRIGHT", f, "TOPRIGHT", -2, -21)
  streaks:SetHeight(43); streaks:SetHorizTile(true)

  local ns = CreateFrame("Frame", nil, f)
  ns:SetAllPoints(f)
  if NE.nineslice and NE.nineslice.ApplyLayout then NE.nineslice.ApplyLayout(ns, "PortraitFrameTemplate") end
  f.NineSlice = ns

  -- Title. DOWNPORT: PC.SetTitle only writes into frame.TitleContainer.TitleText or frame.Title.
  -- A bare Frame has NEITHER, so SetTitle silently no-op'd and the title bar rendered blank.
  -- Build the band + string ourselves (same as modules/professions/Window.lua) and expose it as
  -- f.Title so every later NE.panelchrome.SetTitle(f, ...) call drives it.
  local tc = CreateFrame("Frame", nil, f)
  tc:SetFrameLevel((ns:GetFrameLevel() or 2) + 10)
  tc:SetPoint("TOPLEFT",  f, "TOPLEFT",  58, -1)
  tc:SetPoint("TOPRIGHT", f, "TOPRIGHT", -24, -1)
  tc:SetHeight(20); tc:EnableMouse(false)
  local titleStr = tc:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  titleStr:SetJustifyH("CENTER")
  titleStr:SetPoint("TOP",   f, "TOP",    0,  -6)
  titleStr:SetPoint("LEFT",  f, "LEFT",   58,  0)
  titleStr:SetPoint("RIGHT", f, "RIGHT", -58,  0)
  titleStr:SetText(FRIENDS_LIST or "Friends List")
  f.TitleContainer = tc
  f.TitleText = titleStr
  f.Title = titleStr

  local close = CreateFrame("Button", FRAME_NAME .. "CloseButton", f, "UIPanelCloseButton")
  close:SetPoint("TOPRIGHT", f, "TOPRIGHT", 1, 0)
  close:SetScript("OnClick", function() SO.Hide() end)
  if NE.panelchrome and NE.panelchrome.ModernizeCloseButton then
    NE.panelchrome.ModernizeCloseButton(close, { frameLevelBump = 10 })
  end

  -- Portrait. DOWNPORT: a bare Frame (no XML template) has no built-in portrait region — build one
  -- explicitly into the nineslice's circular cutout corner (same recipe as modules/professions +
  -- modules/spellbook + modules/guild/Window.lua).
  if not f.PortraitTex then
    f.PortraitTex = ns:CreateTexture(nil, "ARTWORK")
  end
  if NE.portrait and NE.portrait.ApplyCutout then
    -- size 60 -> 54 -> 58 (owner report 2026-07-17: "make it larger"). 54 was the size that fully
    -- hid the ring's opaque-metal gap (see below); 60 was confirmed too big (exposed a grey
    -- frame-colored triangle past the ring at the top-left). This icon has real transparent
    -- corners — unlike the old fully-opaque scroll icon that always painted over that gap
    -- regardless of size — so anything pushed toward 60 risks the same triangle reappearing.
    -- Split the difference; anchor kept solving for the same visual center (25,-22 off the frame's
    -- TOPLEFT) as both prior sizes. If the triangle is back, drop toward 54-56 instead of higher.
    NE.portrait.ApplyCutout(f.PortraitTex, f, { size = 58, anchor = { "TOPLEFT", -4, 7 } })
  end
  -- Owner-supplied 2026-07-17: the real Battlenet-Portrait art (NewEra's own icon here, previously
  -- flagged as unavailable on this client) shipped locally and registered in Assets.lua under fdid
  -- 626421. Falls back to the old scroll icon if the registration is ever missing.
  local battlenetPath = NE.tex and NE.tex.localFiles and NE.tex.localFiles[626421]
  local portraitPath = battlenetPath or "Interface\\FriendsFrame\\FriendsFrameScrollIcon"
  f.PortraitTex:SetTexture(portraitPath)
  -- REVERTED the 0.15-0.85 zoom crop (owner report 2026-07-17: it exposed a square edge — the
  -- source art is a circle with the rest of the square canvas as genuine alpha, not a wide
  -- transparent margin around a smaller circle, so cropping in ate into real pixel content instead
  -- of just trimming padding). Full, uncropped TexCoord is correct for this art.
  f.PortraitTex:SetTexCoord(0, 1, 0, 1)
end

-- ---------------------------------------------------------------------------
-- Content panels (one per non-action tab). Exposed as parentKeys for the list files.
-- ---------------------------------------------------------------------------
local function buildPanels(f)
  -- Top offset 44 -> 56 (owner steer 2026-07-17: the sub-tabs/inset, which sit right at this
  -- panel's top edge, were clipping into the corner portrait). The portrait (ApplyCutout default
  -- size 60, anchored TOPLEFT -5,8 off f) hangs down to y=-52 off the frame top, 8px past the old
  -- 44 offset — push the panel below that, plus a few px of clearance.
  for _, t in ipairs(TABS) do
    if t.panel then
      local p = CreateFrame("Frame", FRAME_NAME .. t.panel, f)
      p:SetPoint("TOPLEFT", f, "TOPLEFT", 12, -56)
      p:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -12, 36)
      p:Hide()
      f[t.panel] = p
    end
  end
end

-- ---------------------------------------------------------------------------
-- Tabs (CharacterFrameTabButtonTemplate + shared reskin, same as AH).
-- ---------------------------------------------------------------------------
local function buildTabs(f)
  f._tabNames = {}
  f._tabIds = {}
  for i, t in ipairs(TABS) do
    local name = FRAME_NAME .. "Tab" .. i
    local tab = CreateFrame("Button", name, f, "CharacterFrameTabButtonTemplate")
    tab:SetID(i)
    tab:SetText(t.label)
    tab._mode = t.mode
    tab._action = t.action
    tab:SetScript("OnClick", function(self) SO.SetMode(self._mode) end)
    f._tabNames[#f._tabNames + 1] = name
    f._tabIds[t.mode] = i
    if NE.tabs and NE.tabs.ReskinClassicTab then NE.tabs.ReskinClassicTab(name) end
  end
  if PanelTemplates_SetNumTabs then PanelTemplates_SetNumTabs(f, #TABS) end
  if NE.tabs and NE.tabs.SizeAndAnchorTabs then
    NE.tabs.SizeAndAnchorTabs(f, f._tabNames, { startX = 16, startY = 2, parentPoint = "BOTTOMLEFT" })
  end
end

-- The Guild bottom tab only makes sense while the player is in a guild. Hide it (and re-flow the
-- remaining tabs so there's no gap) when guildless; show it again on join. This governs ONLY the
-- Social window's tab — the guild WINDOW itself is still openable when guildless (keybind /
-- ToggleGuildFrame, see modules/guild/Open.lua). Guarded so a chatty GUILD_ROSTER_UPDATE only
-- re-anchors when membership actually flips.
function SO.UpdateGuildTab()
  local f = SO.frame
  if not f then return end
  local inGuild = (IsInGuild and IsInGuild()) and true or false
  if f._guildTabInGuild == inGuild then return end
  f._guildTabInGuild = inGuild

  local names = {}
  for i, t in ipairs(TABS) do
    local tab = _G[FRAME_NAME .. "Tab" .. i]
    if t.mode == "GUILD" and not inGuild then
      if tab then tab:Hide() end
    else
      if tab then tab:Show() end
      names[#names + 1] = FRAME_NAME .. "Tab" .. i
    end
  end
  if NE.tabs and NE.tabs.SizeAndAnchorTabs then
    NE.tabs.SizeAndAnchorTabs(f, names, { startX = 16, startY = 2, parentPoint = "BOTTOMLEFT" })
  end
end

-- /who result routing. SetWhoToUI(1) makes the SERVER send who-results to the UI (firing
-- WHO_LIST_UPDATE) instead of printing them to chat. It's a GLOBAL, sticky flag, so we only turn
-- it on while our Who tab is actually the visible tab, and turn it back off otherwise — otherwise
-- every /who the player typed got hijacked into the UI (and Blizzard's WHO_LIST_UPDATE handler
-- then force-showed the old FriendsFrame on top of ours).
function SO.SetWhoRouting(toUI)
  if SetWhoToUI then SetWhoToUI(toUI and 1 or 0) end
end

-- The stock window retitles itself per tab ("Friends List" / "Who List" / "Chat Channels" /
-- "Raid") rather than carrying one static title — mirror that.
local TITLE_BY_MODE = {
  FRIENDS = FRIENDS_LIST or "Friends List",
  WHO     = WHO_LIST or ((WHO or "Who") .. " " .. (LIST_LABEL or "List")),
  CHAT    = CHAT_CHANNELS or "Chat Channels",
  RAID    = RAID or "Raid",
}

local function setTitleForMode(f, mode)
  local t = TITLE_BY_MODE[mode] or (FRIENDS or "Friends")
  if NE.panelchrome and NE.panelchrome.SetTitle then
    NE.panelchrome.SetTitle(f, t)
  elseif f.TitleText then
    f.TitleText:SetText(t)
  end
end

function SO.SetMode(mode)
  local f = SO.frame
  if not f then return end

  -- Guild is an action tab: open the guild window, keep the friends window on its current tab.
  if mode == "GUILD" then
    if NE.guild and NE.guild.Toggle then NE.guild.Toggle() end
    if PanelTemplates_SetTab and f._currentTab then PanelTemplates_SetTab(f, f._currentTab) end
    return
  end

  for _, t in ipairs(TABS) do
    if t.panel and f[t.panel] then f[t.panel]:SetShown(t.mode == mode) end
  end
  f._mode = mode
  local id = f._tabIds[mode]
  if id then
    f._currentTab = id
    if PanelTemplates_SetTab then PanelTemplates_SetTab(f, id) end
  end
  setTitleForMode(f, mode)

  -- Route who-results to the UI only while the Who tab is up (and the window is open).
  SO.SetWhoRouting(mode == "WHO" and f:IsShown())

  if mode == "FRIENDS" then
    if ShowFriends then ShowFriends() end
    if SO.RefreshFriends then SO.RefreshFriends() end
    if SO.RefreshIgnore then SO.RefreshIgnore() end
  elseif mode == "WHO" then
    if SO.RefreshWho then SO.RefreshWho() end
  elseif mode == "CHAT" then
    if SO.RefreshChannels then SO.RefreshChannels() end
  elseif mode == "RAID" then
    if SO.RefreshRaid then SO.RefreshRaid() end
  end
end

-- ---------------------------------------------------------------------------
-- Construction + show/hide.
-- ---------------------------------------------------------------------------
local function createWindow()
  if SO.frame then return SO.frame end

  -- DOWNPORT: bare Frame, not template-inherited — see the comment in modules/guild/Window.lua's
  -- createWindow() for why (the AH module's template-inheritance approach left f.portrait unset).
  local f = CreateFrame("Frame", FRAME_NAME, UIParent)
  -- The red 3-slice is the addon's standard button; Watch keeps this window's panel buttons
  -- skinned as its panes are built (core/ButtonSkin.lua). Opt out per button with _neNoSkin.
  if NE.buttonskin and NE.buttonskin.Watch then pcall(NE.buttonskin.Watch, f) end
  -- Width 620 -> 465 (owner steer 2026-07-17: "narrower by 1/4", 620 * 0.75).
  f:SetSize(465, 560)
  f:SetPoint("LEFT", UIParent, "LEFT", 16, 0)
  f:SetFrameStrata("DIALOG")
  f:SetMovable(true); f:SetClampedToScreen(true); f:EnableMouse(true)
  f:RegisterForDrag("LeftButton")
  f:SetScript("OnDragStart", function(self) self:StartMoving() end)
  f:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() end)
  f:Hide()
  SO.frame = f

  buildChrome(f)
  buildPanels(f)
  buildTabs(f)

  if SO.SetupFriends then SO.SetupFriends(f) end
  if SO.SetupWho then SO.SetupWho(f) end
  if SO.SetupChannels then SO.SetupChannels(f) end
  if SO.SetupRaid then SO.SetupRaid(f) end

  f:HookScript("OnShow", function()
    if ShowFriends then ShowFriends() end
    if SO.RefreshFriends then SO.RefreshFriends() end
    SO.SetWhoRouting(f._mode == "WHO")
    SO.UpdateGuildTab()
  end)
  -- Stop hijacking /who once our window is closed (the flag is global + sticky).
  f:HookScript("OnHide", function() SO.SetWhoRouting(false) end)

  if NE.FrameUtil and NE.FrameUtil.WirePanelSounds then
    NE.FrameUtil.WirePanelSounds(f, "igCharacterInfoOpen", "igCharacterInfoClose")
  end
  if NE.FrameUtil and NE.FrameUtil.EscClose then NE.FrameUtil.EscClose(FRAME_NAME) end
  -- Window scale (owner steer 2026-07-17: "make this user adjustable same as professions etc.") —
  -- NE.scale.Apply is the preferred path (core/Scale.lua's DEFAULTS["social"] = 1.0, plain/
  -- unscaled, now also exposed as a mode dropdown + custom slider in the options panel's "Window
  -- Scaling" section, same as Professions/Spellbook/Talents). PinPixelPerfect(f) is the fallback if
  -- core/Scale.lua isn't loaded for some reason.
  if NE.scale and NE.scale.Apply then
    if NE.scale.SetFrame then NE.scale.SetFrame("social", f) end
    NE.scale.Apply("social")
  elseif NE.panelchrome and NE.panelchrome.PinPixelPerfect then
    NE.panelchrome.PinPixelPerfect(f)
  end

  SO.SetMode("FRIENDS")
  SO.UpdateGuildTab()
  return f
end

function SO.Show()
  if not isModuleEnabled() then return end
  local f = createWindow()
  f:Show()
  -- Mirror of Guild's G.Show() repositioning (modules/guild/Window.lua): both windows default to
  -- the same UIParent LEFT+16 anchor, so opening one after the other stacks them fully overlapped.
  -- Guild already re-anchors itself to our RIGHT when it opens second; this covers the reverse
  -- order — if Guild is already open when we show, push IT to our right instead (owner steer
  -- 2026-07-17: "guild window then social window they overlap... guild window gets pushed to its
  -- right").
  local guild = NE.guild and NE.guild.frame
  if guild and guild:IsShown() then
    guild:ClearAllPoints()
    guild:SetPoint("LEFT", f, "RIGHT", 8, 0)
  end
end
function SO.Hide() if SO.frame then SO.frame:Hide() end end
function SO.Toggle()
  local f = createWindow()
  if f:IsShown() then SO.Hide() else SO.Show() end
end

-- Route the game's "open friends" verb to our window.
local wired = false
local function wireRedirects()
  if wired then return end
  wired = true
  if type(_G.ToggleFriendsFrame) == "function" then
    local orig = _G.ToggleFriendsFrame
    _G.ToggleFriendsFrame = function(tab)
      if isModuleEnabled() then
        SO.Toggle()
        return
      end
      return orig(tab)
    end
  end

  -- Suppress the native FriendsFrame. Blizzard's own WHO_LIST_UPDATE handler calls
  -- FriendsFrame_ShowSubFrame("WhoFrame") + ShowUIPanel(FriendsFrame), which popped the OLD
  -- window up next to ours whenever who-results came back to the UI. Hide it and show ours.
  local ff = _G.FriendsFrame
  if ff and not ff._neSocialHooked then
    ff._neSocialHooked = true
    ff:HookScript("OnShow", function(self)
      if isModuleEnabled() then
        -- HideUIPanel, not a raw self:Hide() (owner report 2026-07-17: "who window takes over
        -- escape after it's closed"). Blizzard opened this frame via ShowUIPanel (its own
        -- WHO_LIST_UPDATE handler), which pushes it onto the panel stack; hiding it without going
        -- back through HideUIPanel leaves that bookkeeping stale, which can wedge the Escape-key
        -- CloseSpecialWindows() chain that native FriendsFrame is registered in.
        if HideUIPanel then HideUIPanel(self) else self:Hide() end
        SO.Show()
      end
    end)
  end
end

local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("PLAYER_LOGIN")
-- Keep the Guild tab in sync with guild membership: PLAYER_GUILD_UPDATE fires on join/leave, and
-- GUILD_ROSTER_UPDATE settles the initial IsInGuild() state after login (it can read false until
-- the roster arrives). SO.UpdateGuildTab no-ops unless membership actually changed.
eventFrame:RegisterEvent("PLAYER_GUILD_UPDATE")
eventFrame:RegisterEvent("GUILD_ROSTER_UPDATE")
eventFrame:SetScript("OnEvent", function(_, event)
  if event == "PLAYER_LOGIN" then
    if isModuleEnabled() then createWindow() end
    wireRedirects()
    if NE.RegisterPanel then
      NE.RegisterPanel({
        id = MODULE,
        title = SOCIALS or FRIENDS or "Social",
        desc = "Modern friends window (Friends / Ignore / Who) with a Guild tab.",
        frame = SO.frame,
        openFn = SO.Show,
        closeFn = SO.Hide,
        order = 55,
      })
    end
    if GuildRoster then GuildRoster() end   -- prompt an initial roster so IsInGuild() settles
  end
  if SO.UpdateGuildTab then SO.UpdateGuildTab() end
end)
