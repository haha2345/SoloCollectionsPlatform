-- DragonUI_NewEra/modules/guild/Window.lua — modern Guild panel shell (NE_GuildFrame).
--
-- DOWNPORT of NewEra/Guild/Guild.lua. NewEra clones retail's Blizzard_Communities window using
-- retail-only kit (WowScrollBoxList / ColumnDisplayTemplate / WowStyle1DropdownTemplate /
-- NE_PortraitWindowTemplate / min-max / C_GuildInfo). None of that exists on 3.3.5a, so this is a
-- REBUILD on the same recipe the Auction House port uses (modules/auctionhouse/Window.lua):
--   rock body + TopTileStreaks + PortraitFrameTemplate nineslice + portrait + title + close.
--
-- WotLK-real scope (owner decision 2026-07-15): keep the modern Communities LOOK, but only ship
-- what 3.3.5a actually serves — Roster / Guild Info (+ Guild Chat, sharing that same tab) + guild
-- control buttons. The retail Benefits/Rewards/Reputation tab, ClubFinder recruitment, calendar and
-- minimize-to-chat are CUT (all Cata+ systems, phantom here) — same philosophy NewEra applies for
-- vanilla Era.
--
-- RENDER-BEFORE-WIRE: this file builds the shell (chrome, side tabs, mode switching, empty content
-- panels exposed as parentKeys). Live data wires in Roster.lua / Info.lua / Chat.lua via
-- G.SetupRoster / G.SetupInfo / G.SetupChat, guarded so load order can't crash.

local NE = DragonUI_NewEra
if not NE then return end

NE.guild = NE.guild or {}
local G = NE.guild

local FRAME_NAME = "NE_GuildFrame"
local MODULE = "Guild"

-- Display modes → the content panel parentKeys shown for each. ROSTER opens first (owner steer
-- 2026-07-15 — retail itself defaults to Chat, but Roster is more useful as the first thing seen).
-- GUILD_INFO now shows BOTH InfoFrame and ChatFrame side by side (owner steer 2026-07-17: "combine
-- the chat and guild info tabs... guild info on the left, chat on the right, chat gets 75%") — the
-- tab keeps its original name/tooltip ("Guild Information"), it just also holds Chat now. ROSTER is
-- the ONE mode that shows the left GuildColumn (owner steer 2026-07-17: "I actually wanted this
-- blue left pane only on the roster tab") — the column isn't a per-mode content panel like the
-- other two, it's a persistent sidebar toggled separately in SetDisplayMode below.
local MODE = {
  ROSTER     = { "RosterFrame" },
  GUILD_INFO = { "InfoFrame", "ChatFrame" },
}
local ALL_PANELS = { "RosterFrame", "InfoFrame", "ChatFrame" }

-- Side tabs (right edge). WotLK-available icons only (retail's guild-perk icons are Cata+).
-- Only 2 tabs now — Chat was folded into the Guild Info tab (see MODE above), so there's no
-- separate ChatTab side button anymore.
local TAB_DEFS = {
  { key = "RosterTab", mode = "ROSTER",     icon = "Interface\\Icons\\INV_Misc_GroupLooking", tip = GUILD_ROSTER_TITLE or "Roster" },
  { key = "InfoTab",   mode = "GUILD_INFO", icon = "Interface\\Icons\\INV_Scroll_03",         tip = GUILD_INFORMATION or "Guild Information" },
}

-- Gated entirely by the options panel's single "Social (Friends/Who/Guild/Chat/Raid)" checkbox
-- (id "Social") — there is no separate Guild row, so Guild has no enable flag of its own; consult
-- ONLY modules.Social. (A short-lived separate "Guild" toggle briefly existed and was removed —
-- do NOT resurrect a modules[MODULE] check here, or a stray leftover modules.Guild.enabled=false
-- from that toggle's use would wedge Guild disabled forever with no control left to undo it.)
local function isModuleEnabled()
  return not (NE.modules and NE.modules.IsEnabled) or NE.modules.IsEnabled("Social")
end

-- ---------------------------------------------------------------------------
-- Chrome (rock body + streaks + nineslice + portrait + title + close).
-- Lifted from modules/auctionhouse/Window.lua:buildChrome, guild-specific title/portrait.
-- ---------------------------------------------------------------------------
local function buildChrome(f)
  local body = f:CreateTexture(nil, "BACKGROUND", nil, -8)
  local rockPath = NE.tex and NE.tex.localFiles and NE.tex.localFiles[374155]
  body:SetTexture(rockPath or 374155, "REPEAT", "REPEAT")
  body:SetHorizTile(true); body:SetVertTile(true)
  -- Left edge inset 4px (owner steer 2026-07-17, measured from a cropped screenshot: "it sticks out
  -- 4 pixels"). An 8px OUTWARD overhang was tried first and made the sliver bigger, not smaller —
  -- confirming the border's opaque coverage falls INSIDE the frame's nominal left edge, not past
  -- it, so body needs to be pulled IN (positive x), not pushed out. Right/bottom left flush — no
  -- sliver reported there at this baseline, only the left edge.
  body:SetPoint("TOPLEFT", f, "TOPLEFT", 4, -21)
  body:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", 0, 0)

  local ns = CreateFrame("Frame", nil, f)
  ns:SetAllPoints(f)
  -- Flat (non-portrait) corner — no circular cutout (owner steer 2026-07-17: "remove the circle
  -- again"). The guild crest already has a proper home in the GuildColumn banner (buildGuildColumn
  -- below), so this window doesn't need a corner portrait at all.
  if NE.nineslice and NE.nineslice.ApplyLayout then NE.nineslice.ApplyLayout(ns, "ButtonFrameTemplateNoPortrait") end
  f.NineSlice = ns

  -- The streaks band needs to sit in a NARROW gap in the stack, and neither obvious placement works:
  --   on `f`            -> underneath the nineslice child frame, invisible (draw layers don't help;
  --                        a child frame always beats its parent's textures)
  --   on `ns`           -> above the nineslice, but also above the guild column, so it covered the
  --                        crest
  -- So it gets its own frame, explicitly levelled ABOVE the nineslice and BELOW the guild column
  -- (which buildGuildColumn pins to base+10). Explicit levels rather than creation order, because
  -- same-level frames resolve by creation sequence — which is exactly the fragile, hard-to-see
  -- coupling that made this take several attempts.
  -- Sized to just the top strip the band actually occupies (SetPoint TOPLEFT/TOPRIGHT + height),
  -- NOT SetAllPoints(f) — a full-window frame at this level had no measurable reason to interfere
  -- with anything below it (it never calls EnableMouse, and neither does ApplyTopTileStreaks), but
  -- the Roster tab's "Show Offline" checkbox stopped responding to clicks right after that frame was
  -- introduced, in a build using an in-house 3.3.5a client + compat layer whose mouse-hit-testing
  -- defaults aren't guaranteed to match retail's. Rather than lean on an assumption about this
  -- client's EnableMouse semantics, remove the possibility outright: this frame now physically
  -- cannot cover the checkbox (or anything else past the title band), regardless of what it does or
  -- doesn't intercept.
  local sf = CreateFrame("Frame", nil, f)
  sf:SetPoint("TOPLEFT", f, "TOPLEFT", 0, 0)
  sf:SetPoint("TOPRIGHT", f, "TOPRIGHT", 0, 0)
  sf:SetHeight(70)
  sf:SetFrameLevel((ns:GetFrameLevel() or 1) + 1)
  f.StreaksHost = sf
  if NE.nineslice and NE.nineslice.ApplyTopTileStreaks then
    NE.nineslice.ApplyTopTileStreaks(f, { parent = sf })
  end

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
  titleStr:SetText(GUILD or "Guild")
  f.TitleContainer = tc
  f.TitleText = titleStr
  f.Title = titleStr

  local close = CreateFrame("Button", FRAME_NAME .. "CloseButton", f, "UIPanelCloseButton")
  close:SetPoint("TOPRIGHT", f, "TOPRIGHT", 1, 0)
  close:SetScript("OnClick", function() G.Hide() end)
  if NE.panelchrome and NE.panelchrome.ModernizeCloseButton then
    NE.panelchrome.ModernizeCloseButton(close, { frameLevelBump = 10 })
  end

  -- No corner portrait (owner steer 2026-07-17: reverted the round cutout for good — every attempt
  -- to fill it cleanly on this client either left it transparent, black, or otherwise wrong). The
  -- guild crest already lives in the GuildColumn banner, so there's no second copy needed here.
end

-- ---------------------------------------------------------------------------
-- Right-edge side tabs (native SpellBook-SkillLineTab plate + centered icon). WotLK-reliable
-- (retail CommunitiesFrameTabTemplate art + WowScrollBox side-tab kit don't exist here).
-- ---------------------------------------------------------------------------
local SKILLTAB = "Interface\\SpellBook\\SpellBook-SkillLineTab"

local function buildSideTabs(f)
  f.SideTabs = {}
  local prev
  for i, d in ipairs(TAB_DEFS) do
    local tab = CreateFrame("Button", FRAME_NAME .. d.key, f)
    tab:SetSize(32, 32)
    if prev then
      -- Gap tightened 34 -> 14 (owner-reported 2026-07-17: "closer together" / "heap of space
      -- between them" — the 28 math assumed the plate's opaque art fills its whole 64x60 bounding
      -- box, but the sprite clearly has transparent padding, so that theoretical overlap floor
      -- doesn't match the real visible art). Going empirical instead: drop it further if there's
      -- still a gap after /reload.
      tab:SetPoint("TOPLEFT", prev, "BOTTOMLEFT", 0, -14)
    else
      -- x nudged -2 -> 3 (owner-measured 2026-07-17: "moved over to the right about 5 pixels").
      -- Subsequent tabs inherit this x via their 0-offset anchor to prev, so all tabs shift together.
      tab:SetPoint("TOPLEFT", f, "TOPRIGHT", 3, -44)
    end

    -- Height cropped 64 -> 60 (owner-measured 2026-07-17: "reduced by about 3 pixels, remove this
    -- from the bottom"; adjusted to 60 after review). Re-anchored TOP instead of CENTER so the top
    -- edge stays put and only the bottom edge moves up — a plain SetSize under the old CENTER anchor
    -- would have trimmed both edges equally.
    local plate = tab:CreateTexture(nil, "BACKGROUND")
    plate:SetTexture(SKILLTAB)
    plate:SetSize(64, 60)
    plate:SetPoint("TOP", tab, "CENTER", 12, 24)
    tab._plate = plate

    -- REVERTED 2026-07-17: tried centering on `plate` instead of `tab`, assuming the plate art's
    -- icon-hole sat at its geometric center — it didn't (owner: "that broke it a lot"), so the icon
    -- ended up spilling outside the tab shape entirely. Back to centering on `tab`; the plate's icon
    -- slot isn't at its own center, so anchoring to the tab's center (not the plate's) was actually
    -- closer. Fill-size/offset still needs a screenshot-measured tweak per the owner's original
    -- "icons dont fully fill them" report.
    local icon = tab:CreateTexture(nil, "ARTWORK")
    icon:SetSize(28, 28); icon:SetPoint("CENTER")
    icon:SetTexture(d.icon)
    icon:SetTexCoord(0.06, 0.94, 0.06, 0.94)
    tab.Icon = icon

    -- Active-state glow below the icon (CheckedTexture would draw over it).
    local glow = tab:CreateTexture(nil, "ARTWORK", nil, -1)
    glow:SetTexture("Interface\\Buttons\\CheckButtonHilight")
    glow:SetBlendMode("ADD"); glow:SetAllPoints(tab); glow:Hide()
    tab._glow = glow

    tab:SetHighlightTexture("Interface\\Buttons\\CheckButtonHilight", "ADD")

    tab._mode = d.mode
    tab:SetScript("OnClick", function(self)
      G.SetDisplayMode(self._mode)
      if PlaySound then PlaySound("igMainMenuOptionCheckBoxOn") end
    end)
    tab:SetScript("OnEnter", function(self)
      GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
      GameTooltip:SetText(d.tip)
      GameTooltip:Show()
    end)
    tab:SetScript("OnLeave", function() GameTooltip:Hide() end)

    f[d.key] = tab
    f.SideTabs[i] = tab
    prev = tab
  end
end

-- ---------------------------------------------------------------------------
-- Content panels + the Roster-only left GuildColumn.
--
-- The left guild column (the single-guild "CommunitiesList" analogue) was removed entirely
-- 2026-07-16, restored the same day scoped to the Chat tab, then moved to the Roster tab
-- 2026-07-17 (owner: "I actually wanted this blue left pane only on the roster tab" — the Chat
-- placement was a mistake made while combining Info and Chat into one tab). Info and Chat stay
-- full-width — the column only shows next to Roster now.
-- ---------------------------------------------------------------------------
local function inset(parent, tlx, tly, brx, bry)
  local ns = CreateFrame("Frame", nil, parent)
  ns:SetPoint("TOPLEFT", parent, "TOPLEFT", tlx or 0, tly or 0)
  ns:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", brx or 0, bry or 0)
  ns:EnableMouse(false)
  if NE.nineslice and NE.nineslice.ApplyLayout then NE.nineslice.ApplyLayout(ns, "InsetFrameTemplate") end
  parent._inset = ns
  return ns
end
G.Inset = inset

-- Full-width content panel (Roster / Info).
local function contentPanel(f, key)
  local p = CreateFrame("Frame", FRAME_NAME .. key, f)
  p:SetPoint("TOPLEFT", f, "TOPLEFT", 12, -48)
  p:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -12, 34)
  p:Hide()
  f[key] = p
  return p
end

local GUILD_COLUMN_WIDTH = 180

-- The Roster-only left column: bluemenu decorative frame (owner: "reference NewEra for any missing
-- art" — pulled from ReferenceAddons/NewEra/Art/LFG/, the exact 3 files NewEra's own
-- Guild.lua:buildCommunitiesList reuses for this same panel) + a single static "entry" (there's
-- only ever one guild): banner plate + tabard crest badge + guild name + member count.
-- Texcoords transcribed verbatim from NewEra/Guild/Guild.lua:186-236 (raw SetTexture+SetTexCoord,
-- not atlas nicknames — matched here 1:1, see modules/guild/Assets.lua).
local function buildGuildColumn(f)
  local list = CreateFrame("Frame", FRAME_NAME .. "GuildColumn", f)
  -- Explicitly above the chrome's nineslice (base+1) and streaks host (base+2), so the crest and the
  -- column art are never painted over by window decoration. Previously this relied on being created
  -- later than those frames at the same level, which is invisible coupling and broke as soon as the
  -- streaks moved.
  list:SetFrameLevel((f:GetFrameLevel() or 0) + 10)
  list:SetPoint("TOPLEFT", f, "TOPLEFT", 12, -48)
  list:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 12, 34)
  list:SetWidth(GUILD_COLUMN_WIDTH)
  list:Hide()   -- shown only in ROSTER mode (SetDisplayMode)
  f.GuildColumn = list

  local function localTex(fdid) return NE.tex and NE.tex.localFiles and NE.tex.localFiles[fdid] end
  local BLUEMENU = localTex(593918)
  local BLUEVERT = localTex(593919)
  local BLUEGOLD = localTex(593917)

  if BLUEMENU then
    local bg = list:CreateTexture(nil, "ARTWORK", nil, 1)
    bg:SetTexture(BLUEMENU)
    bg:SetTexCoord(0.00390625, 0.82421875, 0.18554688, 0.58984375)
    bg:SetPoint("TOPLEFT",     list, "TOPLEFT",      2, 0)
    bg:SetPoint("BOTTOMRIGHT", list, "BOTTOMRIGHT", -2, 0)
    list.Bg = bg

    local topF = list:CreateTexture(nil, "ARTWORK", nil, 2)
    topF:SetTexture(BLUEMENU); topF:SetSize(155, 55)
    topF:SetTexCoord(0.00390625, 0.72656250, 0.12988281, 0.18359375)
    topF:SetPoint("TOPLEFT", list, "TOPLEFT", 14, -6)

    local botF = list:CreateTexture(nil, "ARTWORK", nil, 2)
    botF:SetTexture(BLUEMENU); botF:SetSize(155, 55)
    botF:SetTexCoord(0.26171875, 0.98437500, 0.06542969, 0.11914063)
    botF:SetPoint("BOTTOMLEFT", list, "BOTTOMLEFT", 14, 1)
  end

  inset(list, 3, 1, 0, -3)

  -- FilligreeOverlay — the gold corner frame around the list.
  if BLUEMENU and BLUEVERT and BLUEGOLD then
    local fo = CreateFrame("Frame", nil, list)
    fo:SetFrameLevel(list:GetFrameLevel() + 5)
    fo:SetPoint("TOPLEFT", list, "TOPLEFT", 3, -1)
    fo:SetPoint("BOTTOMRIGHT", list, "BOTTOMRIGHT", -2, 0)
    list.FilligreeOverlay = fo

    local function corner(tc, p, x, y)
      local t = fo:CreateTexture(nil, "OVERLAY"); t:SetTexture(BLUEMENU); t:SetSize(64, 64)
      t:SetTexCoord(tc[1], tc[2], tc[3], tc[4]); t:SetPoint(p, fo, p, x, y); return t
    end
    local tl = corner({ 0.00390625, 0.25390625, 0.00097656, 0.06347656 }, "TOPLEFT", 3, 2)
    local tr = corner({ 0.51953125, 0.76953125, 0.00097656, 0.06347656 }, "TOPRIGHT", -1, 2)
    local br = corner({ 0.51171875, 0.26171875, 0.00097656, 0.06347656 }, "BOTTOMRIGHT", 0, 0)
    local bl = corner({ 0.26171875, 0.51171875, 0.00097656, 0.06347656 }, "BOTTOMLEFT", 3, 0)

    local leftBar = fo:CreateTexture(nil, "OVERLAY"); leftBar:SetTexture(BLUEVERT); leftBar:SetVertTile(true)
    leftBar:SetTexCoord(0.0625, 0.3984375, 0, 1); leftBar:SetSize(43, 247)
    leftBar:SetPoint("TOPLEFT", fo, "TOPLEFT", 3, -62)

    local rightBar = fo:CreateTexture(nil, "OVERLAY"); rightBar:SetTexture(BLUEVERT)
    rightBar:SetVertTile(true); rightBar:SetWidth(43)
    rightBar:SetTexCoord(0.4140625, 0.75, 0, 1)
    rightBar:SetPoint("TOPRIGHT", tr, "BOTTOMRIGHT", 0, 0)
    rightBar:SetPoint("BOTTOMRIGHT", br, "TOPRIGHT", 0, 0)

    local topBar = fo:CreateTexture(nil, "BORDER"); topBar:SetTexture(BLUEGOLD)
    topBar:SetHorizTile(true); topBar:SetHeight(43)
    topBar:SetTexCoord(0, 1, 0.0078125, 0.34375)
    topBar:SetPoint("TOPLEFT", tl, "TOPRIGHT", 0, 0); topBar:SetPoint("TOPRIGHT", tr, "TOPLEFT", 0, 0)

    local botBar = fo:CreateTexture(nil, "BORDER"); botBar:SetTexture(BLUEGOLD)
    botBar:SetHorizTile(true); botBar:SetHeight(43)
    botBar:SetTexCoord(0, 1, 0.359375, 0.6953125)
    botBar:SetPoint("BOTTOMLEFT", bl, "BOTTOMRIGHT", 0, 0); botBar:SetPoint("BOTTOMRIGHT", br, "BOTTOMLEFT", 0, 0)
  end

  -- The single guild "entry": banner plate (communities atlas — already registered) + tabard
  -- crest (real design via Tabard.lua when it resolves, else the static NoLogo crest) + name.
  local banner = list:CreateTexture(nil, "ARTWORK", nil, 3)
  -- SetAtlas RETURNS FALSE when the atlas entry or its bundled BLP can't be resolved, and on failure
  -- it applies neither texture nor size (size is only set on success). Ignoring that left a 0x0
  -- untextured banner — invisible, and useless to anchor against, which is what made the tabard
  -- crest render as an emblem floating over bare panel. Give it an explicit size so it is at least a
  -- valid anchor target, and record the outcome; Tabard.lua retries the atlas and falls back to the
  -- NoLogo crest as its plate while this stays false.
  banner:SetSize(74, 69)
  list.BannerAtlasOK = (NE.tex and NE.tex.SetAtlas
    and NE.tex.SetAtlas(banner, "communities-guildbanner-background", true)) or false
  banner:SetPoint("TOP", list, "TOP", 0, -46)
  list.Banner = banner

  local crest = list:CreateTexture(nil, "OVERLAY", nil, 4)
  crest:SetTexture("Interface\\GuildFrame\\GuildLogo-NoLogo")
  crest:SetSize(44, 44)
  crest:SetPoint("CENTER", banner, "CENTER", 0, 2)
  list.Crest = crest
  list.CrestSize = 40   -- box Tabard.lua sizes the emblem against; just inside the crest's edge

  local name = list:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
  name:SetPoint("TOP", banner, "BOTTOM", 0, -12)
  name:SetPoint("LEFT", list, "LEFT", 8, 0)
  name:SetPoint("RIGHT", list, "RIGHT", -8, 0)
  name:SetJustifyH("CENTER")
  name:SetText(GUILD or "Guild")
  list.Name = name

  list.MemberCount = list:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  list.MemberCount:SetPoint("TOP", name, "BOTTOM", 0, -6)

  list.SetGuild = function(gname, online, total)
    name:SetText(gname or (GUILD or "Guild"))
    if online and total then
      list.MemberCount:SetText(string.format("%d/%d %s", online, total, GUILD_MEMBERS or "Members"))
    elseif total then
      list.MemberCount:SetText(string.format("%d %s", total, GUILD_MEMBERS or "Members"))
    else
      list.MemberCount:SetText("")
    end
  end

  if G.SetupTabard then G.SetupTabard(list) end
end

-- Guild Info gets the left 25% of the GUILD_INFO tab, Chat the remaining 75% (owner 2026-07-17).
-- Computed off the shared content area's width (990 frame - 12/-12 side margins = 966), minus the
-- 10px gap between the two panes.
local INFO_PANE_WIDTH = math.floor((966 - 10) * 0.25 + 0.5)

local function buildPanels(f)
  buildGuildColumn(f)

  -- Roster sits to the RIGHT of the (Roster-only) GuildColumn, not full-width.
  local roster = contentPanel(f, "RosterFrame")
  roster:ClearAllPoints()
  roster:SetPoint("TOPLEFT", f.GuildColumn, "TOPRIGHT", 10, 0)
  roster:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -12, 34)

  -- Guild Info (narrow left column) + Chat (the rest) share the GUILD_INFO tab.
  local info = contentPanel(f, "InfoFrame")
  info:ClearAllPoints()
  info:SetPoint("TOPLEFT", f, "TOPLEFT", 12, -48)
  info:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 12, 34)
  info:SetWidth(INFO_PANE_WIDTH)

  local chat = contentPanel(f, "ChatFrame")
  chat:ClearAllPoints()
  chat:SetPoint("TOPLEFT", info, "TOPRIGHT", 10, 0)
  chat:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -12, 34)
end

-- ---------------------------------------------------------------------------
-- Bottom controls (Invite / Guild Control / View Log). Per-mode visibility mirrors retail.
-- ---------------------------------------------------------------------------
local function buildControls(f)
  -- Gap between the guild window's right edge and either popup that opens beside it — the event log
  -- and Guild Control both use it, so they stay in line with each other. Wide enough to clear the
  -- guild window's side tab strip, which they were sitting on top of at the old 4px (owner-reported
  -- 2026-08-09). Declared up here because the log button below closes over it.
  local POPUP_X_GAP = 24

  local log = CreateFrame("Button", FRAME_NAME .. "LogButton", f, "UIPanelButtonTemplate")
  log:SetSize(120, 22)
  log:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 12, 6)
  log:SetText(GUILD_EVENT_LOG or "View Log")
  -- 3.3.5a ships GuildEventLogFrame inside FriendsFrame (FriendsFrame.xml), so it exists but its
  -- default anchor is the old GuildControlPopupFrame — off-screen from our window. We reparent it,
  -- re-anchor it to the RIGHT of our guild frame, and skin it to match the NewEra chrome (once).
  local function skinEventLog(elf)
    if elf._neSkinned then return end
    elf._neSkinned = true

    -- Strip the default parchment backdrop.
    if elf.SetBackdrop then elf:SetBackdrop(nil) end

    -- Hide any leftover native chrome baked directly onto the frame by its own XML template (the
    -- classic dialog corner/border art) — SetBackdrop(nil) above only clears an actual Backdrop, it
    -- doesn't touch plain Texture regions. One of those was showing as a stray gold-bordered square
    -- peeking out from behind our modernized close button (owner-reported 2026-07-17: "weird extra
    -- texture frame underneath the X"). Everything visual is redrawn by body/streaks/ns below, so any
    -- pre-existing Texture region on the frame itself is safe to hide outright (FontStrings, like the
    -- title, are left alone).
    for _, region in ipairs({ elf:GetRegions() }) do
      if region.GetObjectType and region:GetObjectType() == "Texture" then
        region:Hide()
      end
    end

    -- Rock body (same as every other NE window).
    local body = elf:CreateTexture(nil, "BACKGROUND", nil, -8)
    local rockPath = NE.tex and NE.tex.localFiles and NE.tex.localFiles[374155]
    body:SetTexture(rockPath or 374155, "REPEAT", "REPEAT")
    body:SetHorizTile(true); body:SetVertTile(true)
    -- Left edge inset 5px (owner-adjusted from the 4px in buildChrome's identical body texture
    -- above). Bottom edge inset 1px (owner-measured: "1 pixel sliver on the bottom"). Right left
    -- flush — no sliver reported there.
    body:SetPoint("TOPLEFT",  elf, "TOPLEFT",  5, -21)
    body:SetPoint("BOTTOMRIGHT", elf, "BOTTOMRIGHT", 0, 1)

    -- TopTileStreaks banner (shared helper: same geometry, plus retry on atlas failure).
    if NE.nineslice and NE.nineslice.ApplyTopTileStreaks then
      NE.nineslice.ApplyTopTileStreaks(elf)
    end

    -- NineSlice chrome: no-portrait layout so the top-left corner is flat (no circular cutout).
    local ns = CreateFrame("Frame", nil, elf)
    ns:SetAllPoints(elf)
    if NE.nineslice and NE.nineslice.ApplyLayout then NE.nineslice.ApplyLayout(ns, "ButtonFrameTemplateNoPortrait") end

    -- Re-skin the title to sit in our title bar (no portrait, so left offset matches centre).
    local titleStr = _G.GuildEventLogTitle
    if titleStr then
      titleStr:ClearAllPoints()
      titleStr:SetPoint("TOP",   elf, "TOP",    0,  -6)
      titleStr:SetPoint("LEFT",  elf, "LEFT",   12,  0)
      titleStr:SetPoint("RIGHT", elf, "RIGHT", -12,  0)
      titleStr:SetFontObject(GameFontNormal)
      titleStr:SetJustifyH("CENTER")
    end

    -- Replace the old stone close button with our modernized one.
    local oldClose = _G.GuildEventLogCloseButton
    if oldClose then
      if NE.panelchrome and NE.panelchrome.ModernizeCloseButton then
        NE.panelchrome.ModernizeCloseButton(oldClose, { frameLevelBump = 10 })
      end
      oldClose:ClearAllPoints()
      oldClose:SetPoint("TOPRIGHT", elf, "TOPRIGHT", 1, 0)
    end

    -- Strip the inner frame's parchment backdrop.
    local inner = _G.GuildEventFrame
    if inner and inner.SetBackdrop then inner:SetBackdrop(nil) end
    if inner then
      -- Dark recessed backdrop behind the log text (owner steer 2026-07-17: "the dark background
      -- should be behind the text in the guild log") — same WHITE8X8 fill as the Roster/Chat
      -- panels, drawn first so the log lines sit on top of it.
      local logBg = inner:CreateTexture(nil, "BACKGROUND")
      logBg:SetTexture("Interface\\Buttons\\WHITE8X8")
      logBg:SetVertexColor(0.06, 0.06, 0.07, 0.90)
      logBg:SetAllPoints(inner)
      inner._neBg = logBg

      -- Recessed inset well around the scroll area.
      if NE.nineslice and NE.nineslice.AttachInset then
        pcall(NE.nineslice.AttachInset, inner, 0, 0, 0, 0)
      end
    end

    -- Modern minimal-scrollbar for the log's list (owner steer 2026-07-17: "the scrollbar in it
    -- rethemed to the modern one"). Names confirmed via /dump GuildEventFrame:GetChildren() in-game
    -- (owner-supplied): the real FauxScrollFrame is the global "GuildEventLogScrollFrame", with its
    -- hidden slider at "GuildEventLogScrollFrameScrollBar" + ...ScrollUpButton/...ScrollDownButton —
    -- exactly the shape NE.scrollbar.BuildCustom expects (name .. "ScrollBar", then
    -- sliderName .. "ScrollUpButton"/"ScrollDownButton"). An earlier attempt used
    -- NE.scrollbar.Reskin (in-place reskin of the stock Slider) and reverted 2026-07-17 — it made the
    -- bar disappear entirely, matching this same file's own documented reason BuildCustom exists at
    -- all ("Reskin ... was not rendering"). BuildCustom is the hand-built bar every other FauxScroll
    -- list in this addon already uses, so this now matches that established pattern instead.
    local logScroll = _G.GuildEventLogScrollFrame
    if logScroll and NE.scrollbar and NE.scrollbar.BuildCustom then
      local ok, bar = pcall(NE.scrollbar.BuildCustom, logScroll, { x = -8, alwaysShow = true })
      if ok and bar then
        -- Same strata trap hit repeatedly in the Auction House lists (see ScrollbarReskin.lua
        -- callers in modules/auctionhouse/Browse.lua): BuildCustom's bar defaults to "HIGH", but
        -- `elf` gets explicitly promoted to "DIALOG" strata whenever the log is shown (this file's
        -- OnClick handler below), so every descendant frame (inner/logScroll included) inherits
        -- DIALOG too — a HIGH-strata bar renders BEHIND that content, i.e. invisible. Force it up.
        bar:SetFrameStrata("DIALOG")
        bar:SetFrameLevel((inner and inner:GetFrameLevel() or 1) + 10)
        if bar._upBtn then bar._upBtn:SetFrameStrata("DIALOG"); bar._upBtn:SetFrameLevel(bar:GetFrameLevel() + 1) end
        if bar._downBtn then bar._downBtn:SetFrameStrata("DIALOG"); bar._downBtn:SetFrameLevel(bar:GetFrameLevel() + 1) end
      end
    end

    -- Register with UISpecialFrames so Escape closes the log on its own (once, after skin applied).
    if _G.UISpecialFrames then
      tinsert(_G.UISpecialFrames, "GuildEventLogFrame")
    end

    -- Hide the redundant bottom "Close" button — the corner X is sufficient.
    local cancelBtn = _G.GuildEventLogCancelButton
    if cancelBtn then cancelBtn:Hide() end

    -- Trim the empty rock-textured strip left below the list where that Cancel button used to sit
    -- (owner-reported 2026-07-17, screenshot with the strip circled: "the actual log area should
    -- either extend into the ... area or that area should be removed. Removing it might be
    -- better"). Measured live off the real content's bottom edge rather than a hardcoded offset,
    -- since the scroll frame's own size/anchors come from Blizzard's native XML, not this addon.
    -- Pulls the window's own bottom edge up to hug the content; body/streaks/ns are all anchored to
    -- elf itself, so they follow this resize automatically.
    if inner and logScroll then
      local innerBottom = inner:GetBottom()
      local scrollBottom = logScroll:GetBottom()
      local frameBottom = elf:GetBottom()
      if innerBottom and scrollBottom and frameBottom then
        local contentBottom = math.min(innerBottom, scrollBottom)
        local margin = 10
        local trim = (contentBottom - margin) - frameBottom
        if trim > 0 then
          elf:SetHeight(elf:GetHeight() - trim)
        end
      end
    end
  end

  log:SetScript("OnClick", function()
    local elf = _G.GuildEventLogFrame
    if not elf then return end
    if elf:IsShown() then
      elf:Hide()
    else
      if QueryGuildEventLog then QueryGuildEventLog() end
      elf:SetParent(UIParent)
      elf:SetFrameStrata("DIALOG")
      elf:SetToplevel(true)
      elf:ClearAllPoints()
      elf:SetPoint("TOPLEFT", f, "TOPRIGHT", POPUP_X_GAP, 0)
      skinEventLog(elf)
      elf:Show()
    end
  end)
  f.LogButton = log

  local control = CreateFrame("Button", FRAME_NAME .. "ControlButton", f, "UIPanelButtonTemplate")
  control:SetSize(120, 22)
  control:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -12, 6)
  control:SetText(GUILDCONTROL or "Guild Control")
  -- The original handler here was ported verbatim from the retail NewEra source and targeted
  -- GuildControlUI_LoadUI()/GuildControlUI — the Cataclysm-era Blizzard_GuildControlUI LoD addon.
  -- That addon does not exist on 3.3.5a (no Blizzard_GuildControlUI folder in Interface\AddOns), so
  -- both nil-guards failed and the button was a silent no-op for everyone, guild leader included
  -- (owner-reported 2026-08-09: "nothing happens when pressed and I am the guild leader").
  --
  -- The 3.3.5a equivalent is GuildControlPopupFrame, baked into FriendsFrame.xml (same file that
  -- ships GuildEventLogFrame — see the log button above, whose comment already names this frame as
  -- GuildEventLogFrame's default anchor, i.e. it is confirmed present on this client). Its API set
  -- is the WotLK one: GuildControlSetRank / GuildControlGetRankFlags / GuildControlSetRankFlag /
  -- GuildControlSaveRank / GuildControlAddRank / GuildControlDelRank.
  --
  -- Same anchoring problem as the log: the popup's XML anchor is relative to the native GuildFrame,
  -- which this module suppresses (modules/guild/Open.lua), so left alone it opens detached from our
  -- window. Reparent to UIParent and pin it to the RIGHT of our frame, identical to the event log
  -- (owner steer 2026-08-09). The two therefore stack in the same place — acceptable, since Guild
  -- Control is a modal-ish commit dialog you finish with rather than something you read alongside the
  -- log. Clamped to screen so it can never land off the edge when the window is dragged hard right.
  --
  -- Showing it is NOT enough on its own, though. Suppressing the native GuildFrame also suppresses
  -- the code that seeds the popup's selected-rank state, so its OnShow ran Blizzard's updater with
  -- no rank selected and threw (owner-reported 2026-08-09):
  --   FriendsFrame.lua:1586: Usage: GuildControlGetRankName(index)   -- locals: rankID = nil
  -- We seed that state ourselves in primeGuildControl below, before Show.
  --
  -- Note the lowercase 'f' in GuildControlPopupframe_Update — that is a genuine Blizzard typo in
  -- 3.3.5a FrameXML, confirmed by the owner's traceback. An earlier attempt here guarded on the
  -- correctly-cased GuildControlPopupFrame_Update, which does not exist, so the guard was dead code.

  -- Everything here is pcall/nil-guarded: on a build where one of these helpers is absent or shaped
  -- differently, priming degrades to a no-op instead of throwing on the way to Show.
  local function primeGuildControl()
    -- Server-side edit target.
    if GuildControlSetRank then pcall(GuildControlSetRank, 1) end
    -- GuildControlPopupframe_Update takes its rankID from this dropdown's selection; an unset
    -- selection is exactly the nil that reached GuildControlGetRankName above.
    local dd = _G.GuildControlPopupFrameDropDown
    if dd then
      if UIDropDownMenu_Initialize and _G.GuildControlPopupFrameDropDown_Initialize then
        pcall(UIDropDownMenu_Initialize, dd, _G.GuildControlPopupFrameDropDown_Initialize)
      end
      if UIDropDownMenu_SetSelectedID then pcall(UIDropDownMenu_SetSelectedID, dd, 1) end
    end
  end

  -- Accept/Cancel run Blizzard's native handlers, which sign off by returning the player to the stock
  -- guild UI — and on 3.3.5a that UI is a TAB INSIDE FriendsFrame, not a window of its own. So saving
  -- a rank change popped the social window open behind ours (owner-reported 2026-08-09). Open.lua
  -- only suppresses GuildFrame, the tab's inner content frame; FriendsFrame is its parent and stays up
  -- on its own.
  --
  -- SetScript-wrap rather than HookScript: a hook runs only AFTER the native handler, by which point
  -- FriendsFrame is already shown and there is no way left to tell whether this click opened it or it
  -- was already sitting there. Wrapping lets us sample IsShown() first, so we close only what the
  -- click itself opened and never a social window the player had up on purpose.
  -- Both windows have to be checked, and this is what the first attempt got wrong. Watching only the
  -- native FriendsFrame never fired, because modules/social/Window.lua hooks its OnShow and does
  -- HideUIPanel(self) + SO.Show() — swapping in the addon's own NE_FriendsFrame. So by the time we
  -- looked, the native frame was already hidden again and the window actually on screen was
  -- NE.social.frame (owner-reported 2026-08-09: "the social window still gets opened").
  local function socialWindows()
    return _G.FriendsFrame, (NE.social and NE.social.frame)
  end

  -- Hide whichever social window this click brought up, leaving anything the player already had open
  -- alone. Deliberately state-based rather than unconditional: closing a social window the player
  -- opened themselves would be its own bug.
  local function closePoppedOut(wasNative, wasNE)
    local ff, sw = socialWindows()
    if ff and ff:IsShown() and not wasNative then
      if HideUIPanel then HideUIPanel(ff) else ff:Hide() end
    end
    if sw and sw:IsShown() and not wasNE then sw:Hide() end
  end

  -- Closing the social window after the fact was the wrong shape: it still ran SO.Show() in full, so
  -- the player got the open sound, our close sound, and — worst of it — SO.Show's repositioning rule
  -- (modules/social/Window.lua:325, "if Guild is already open when we show, push IT to our right")
  -- fired and dragged the guild window sideways. That reposition is correct behaviour when the player
  -- opens social themselves; it is just wrong for a window that was never meant to appear.
  --
  -- So don't let it open at all. Neuter SO.Show/SO.Toggle across the click and briefly after, then
  -- put them back. Nothing shows, nothing moves, nothing plays (owner-reported 2026-08-09: "multiple
  -- close noises and moves the guild window").
  local function suppressSocial(seconds)
    local SO = NE.social
    if not SO or SO._neGuildSuppressed then return end
    SO._neGuildSuppressed = true
    local realShow, realToggle = SO.Show, SO.Toggle
    SO.Show, SO.Toggle = function() end, function() end
    local function restore()
      if not SO._neGuildSuppressed then return end
      SO._neGuildSuppressed = false
      SO.Show, SO.Toggle = realShow, realToggle
    end
    -- Tail covers a pop-out that arrives on the server's rank-update reply rather than in the click.
    -- No timer available means restore immediately — the synchronous path is still covered, and
    -- leaving the real functions swapped out indefinitely would be far worse than one stray window.
    if C_Timer and C_Timer.After then C_Timer.After(seconds or 0.6, restore) else restore() end
  end

  local function tameSocialPopOut(btn)
    if not btn or btn._neSocialTamed then return end
    btn._neSocialTamed = true
    local orig = btn:GetScript("OnClick")
    btn:SetScript("OnClick", function(self, ...)
      local ff, sw = socialWindows()
      local wasNative, wasNE = ff and ff:IsShown(), sw and sw:IsShown()
      suppressSocial(0.6)
      if orig then orig(self, ...) end
      -- Checked three times because the pop-out is not reliably synchronous: the native handler may
      -- show the frame during the click, or it may land on the server's GUILD_RANKS_UPDATE reply a
      -- moment later. Re-checking costs nothing — closePoppedOut is a no-op unless a window that was
      -- down before the click is up now.
      closePoppedOut(wasNative, wasNE)
      if C_Timer and C_Timer.After then
        C_Timer.After(0,   function() closePoppedOut(wasNative, wasNE) end)
        C_Timer.After(0.5, function() closePoppedOut(wasNative, wasNE) end)
      end
      -- A saved rank rename/permission change is visible in our roster's rank column, so refresh it.
      if G.RefreshRoster then G.RefreshRoster() end
    end)
  end

  -- Modern art for the rank dropdown. UIDropDownMenuTemplate's own look is the glue-screen
  -- CharacterCreate-LabelFrame strip in $parentLeft/$parentMiddle/$parentRight — gold-on-parchment,
  -- and the last stock-art holdout in this popup. There is no shared dropdown skinner in the addon
  -- (core/Menu.lua wraps UIDropDownMenu's BEHAVIOUR, not its textures), so this recreates the same
  -- recessed dark well the Roster/Chat panels and the event log use: drop the strip, fill flat, then
  -- AttachInset for the bevel. The arrow button keeps its own art — it reads fine against the well.
  local function skinDropDown(dd)
    if not dd or dd._neSkinned then return end
    dd._neSkinned = true
    local name = dd.GetName and dd:GetName()
    if name then
      for _, piece in ipairs({ "Left", "Middle", "Right" }) do
        local t = _G[name .. piece]
        if t and t.Hide then t:Hide() end
      end
    end
    -- The template pads ~16px either side of the visible strip; inset to match so the well lines up
    -- with the text rather than the frame's hit area.
    local fill = dd:CreateTexture(nil, "BACKGROUND")
    fill:SetTexture("Interface\\Buttons\\WHITE8X8")
    fill:SetVertexColor(0.06, 0.06, 0.07, 0.90)
    fill:SetPoint("TOPLEFT", dd, "TOPLEFT", 16, -5)
    fill:SetPoint("BOTTOMRIGHT", dd, "BOTTOMRIGHT", -16, 7)
    if NE.nineslice and NE.nineslice.AttachInset then
      pcall(NE.nineslice.AttachInset, dd, 16, -5, -16, 7)
    end
  end

  -- Rock body behind the popup — the one piece of chrome it genuinely lacks.
  --
  -- The gap was masked until this window moved. While the popup was anchored to the LEFT of a 990px
  -- guild window it got clamped back on top of it, so the guild window's rock body showed through and
  -- the popup read as fully skinned. Re-anchoring it to the RIGHT (owner steer 2026-08-09) put it over
  -- open world and exposed the transparency — it had been see-through the whole time.
  -- Clearance between the nineslice top border and the popup's first line of content — the fix for
  -- "the items in the frame look to sit too high". The border art is ~20px tall and the caption sits
  -- at y=-39 from the frame's top (owner dump 2026-08-09), so the two overlapped.
  --
  -- Applied by lifting the CHROME upward, NOT by pushing content down. Rewriting the content anchors
  -- was the obvious approach and it silently did nothing, twice: the sweep reported hits — but it was
  -- counting the body and nineslice created moments earlier, which is exactly why the frame resized
  -- while every label stayed at its original offset. Raising the chrome needs no cooperation from
  -- Blizzard's layout at all; the border simply starts above where the text begins, and there is no
  -- anchor rewrite that can quietly fail. The popup's own anchor is offset by the same amount below,
  -- so its visible top edge still lines up with the guild window's.
  local CHROME_LIFT = 16

  -- How far the right border comes in from the popup's own right edge. Applied to the CHROME, exactly
  -- like CHROME_LIFT, and for the same reason: calling SetWidth on the frame dragged the content left
  -- with it and pushed the left column outside the border (owner-reported 2026-08-09), because the
  -- content is not anchored in a way that survives a resize. Insetting the border instead leaves every
  -- anchor untouched and simply stops the frame being drawn across dead space on the right.
  local WIDTH_TRIM = 29

  -- POPUP_X_GAP lives at the top of buildControls now — the event log closes over it too.

  -- Dead space left below the Accept/Cancel row. Measured live rather than hardcoded — the row's
  -- position comes from Blizzard's XML, not from this addon — using the same approach skinEventLog
  -- uses to trim the log's leftover strip. Runs deferred, after the popup has actually been shown:
  -- GetBottom() has nothing to report on a frame that has never been laid out.
  -- Gap left below the Accept/Cancel row. Lowering this IS how you drop the buttons (owner steer
  -- 2026-08-09, 12 → 7): the trim normalises the gap to exactly this value, so nudging the buttons
  -- down by hand would just be measured away on the next pass and come out unchanged.
  local BOTTOM_MARGIN = 7
  local function trimBottom(gc)
    if gc._neBottomTrimmed then return end
    local accept, cancel = _G.GuildControlPopupAcceptButton, _G.GuildControlPopupFrameCancelButton
    if not (accept and cancel) then return end
    local ab, cb, fb = accept:GetBottom(), cancel:GetBottom(), gc:GetBottom()
    if not (ab and cb and fb) then return end   -- not laid out yet; retry on the next open
    gc._neBottomTrimmed = true

    local trim = math.min(ab, cb) - fb - BOTTOM_MARGIN
    if trim <= 0 then return end

    -- Anything anchored to the frame's BOTTOM rides the edge upward when it shrinks, which would
    -- close the gap ABOVE it and leave the one below untouched — the opposite of the point. Pulling
    -- those offsets down by the same amount first holds them still while the edge rises.
    --
    -- This has to sweep EVERY child and region, not just the two buttons. Compensating the buttons
    -- alone is what squashed the Guild Bank Tab block up into the Max Gold/Day row (owner-reported
    -- 2026-08-09): that section is bottom-anchored too and nothing was holding it in place.
    --
    -- Chained anchors take care of themselves and must not be touched: an object hanging off another
    -- object moves with it, and its own point does not reference `gc`, so the rel test skips it. That
    -- is what keeps a section and the buttons beneath it from both being shifted by the same trim.
    -- Our own chrome is the one thing that must NOT hold position — the body and nineslice are
    -- anchored to the frame's BOTTOMRIGHT precisely so they track its size. Holding them pinned the
    -- border at the old height while the frame shrank underneath, which read as the trim silently
    -- failing: the excess space under Accept/Cancel simply reappeared inside a border that had not
    -- moved (owner-reported 2026-08-09).
    local function holdPosition(obj)
      if obj == gc._neUnder or obj == gc._neNineSlice then return end
      local n = obj and obj.GetNumPoints and obj:GetNumPoints() or 0
      if n == 0 then return end
      local pts, touched = {}, false
      for i = 1, n do
        local p, rel, rp, x, y = obj:GetPoint(i)
        if type(rel) == "string" then rel = _G[rel] end
        rel = rel or (obj.GetParent and obj:GetParent())
        if rel == gc and type(rp) == "string" and string.find(rp, "BOTTOM", 1, true) then
          y = (y or 0) - trim
          touched = true
        end
        pts[i] = { p, rel, rp, x or 0, y or 0 }
      end
      if not touched then return end
      obj:ClearAllPoints()
      for i = 1, n do
        local q = pts[i]
        obj:SetPoint(q[1], q[2], q[3], q[4], q[5])
      end
    end

    for _, c in ipairs({ gc:GetChildren() }) do holdPosition(c) end
    for _, r in ipairs({ gc:GetRegions() })  do holdPosition(r) end

    gc:SetHeight(gc:GetHeight() - trim)
  end

  -- Well around the permission checkboxes, matching the Guild Bank Tab block (owner steer 2026-08-09).
  --
  -- Built from the checkboxes' MEASURED bounds rather than from GuildControlPopupFrameCheckboxes,
  -- because that frame is not the grid its name suggests — it spans nearly the whole popup interior,
  -- and filling it directly is what put a dark sheet over the entire dialog last time. A box derived
  -- from where the checkboxes actually sit cannot over-cover. Deferred like the trim, since GetLeft()
  -- and friends report nothing until the frame has been laid out.
  local WELL_PAD = 6
  local function wellAroundCheckboxes(gc)
    if gc._neCheckWell then return end
    local section = _G.GuildControlPopupFrameCheckboxes
    if not section then return end

    local l, r, t, b
    local function absorb(o)
      local ol, orr, ot, ob = o:GetLeft(), o:GetRight(), o:GetTop(), o:GetBottom()
      if not (ol and orr and ot and ob) then return end
      l = l and math.min(l, ol) or ol
      r = r and math.max(r, orr) or orr
      t = t and math.max(t, ot) or ot
      b = b and math.min(b, ob) or ob
    end

    -- CheckButtons only. Taking every child swept in the rank dropdown and the Rank Label editbox,
    -- which are parented here too, so the well swallowed both rows and left the "Allow this rank to:"
    -- heading rendering underneath it (owner-reported 2026-08-09). The permission checkboxes alone
    -- give the block the caller actually means.
    for _, k in ipairs({ section:GetChildren() }) do
      if k.IsShown and k:IsShown() and k.GetObjectType and k:GetObjectType() == "CheckButton" then
        absorb(k)
      end
    end
    if not (l and r and t and b) then return end   -- not laid out yet; retry next open

    -- Rank Label belongs inside (owner steer 2026-08-09). Named directly rather than swept up by type,
    -- which is what keeps the rank dropdown above it OUT — both would match any "editbox near the top"
    -- rule, and only this one is wanted.
    local rankLabel = _G.GuildControlPopupFrameEditBox
    if rankLabel and rankLabel:IsShown() then absorb(rankLabel) end

    local tab = _G.GuildControlPopupFrameTabPermissions
    local tabTop = tab and tab:GetTop()

    -- Bottom edge: stop just above the "Guild Bank Tab:" heading, which puts the Max Gold/Day row
    -- inside the well. Chasing that row's own widget did not work — it is not a direct EditBox child of
    -- either frame, so a type scan never saw it. Measuring from the heading BELOW it needs no knowledge
    -- of what the row is built from. Of the labels sitting between the checkboxes and the bank block,
    -- the heading is the lowest, hence the min-top pick.
    local headingTop
    for _, rg in ipairs({ gc:GetRegions() }) do
      if rg.GetObjectType and rg:GetObjectType() == "FontString" and rg:IsShown() then
        local rt = rg:GetTop()
        if rt and rt < b and (not tabTop or rt > tabTop) then
          headingTop = headingTop and math.min(headingTop, rt) or rt
        end
      end
    end
    if headingTop then
      b = headingTop + 4
    elseif tabTop then
      b = tabTop + 22   -- no heading found: leave room for one line of text above the bank block
    end

    -- Match the Guild Bank Tab block's width exactly (owner steer 2026-08-09) rather than hugging the
    -- checkboxes, so the two wells line up as a pair.
    if tab and tab:GetLeft() and tab:GetRight() then
      l, r = tab:GetLeft(), tab:GetRight()
    end

    local gl, gt = gc:GetLeft(), gc:GetTop()
    if not (gl and gt) then return end
    gc._neCheckWell = true

    -- Offsets are screen-space deltas against the popup's own corner; everything here shares an
    -- effective scale, so no conversion is needed. Horizontal edges are used as-is (they are the bank
    -- block's, and matching it is the point); only the top gets padding, and the bottom is already
    -- positioned against the heading below it.
    local function place(obj)
      obj:SetPoint("TOPLEFT",     gc, "TOPLEFT", l - gl, (t + WELL_PAD) - gt)
      obj:SetPoint("BOTTOMRIGHT", gc, "TOPLEFT", r - gl, b - gt)
    end

    -- Drawn on the UNDERLAY, which sits a frame level below the popup — so this cannot bury the
    -- "Allow this rank to:" heading or the Rank Label box art the way a child-frame fill did. BORDER
    -- puts it above the underlay's own BACKGROUND rock body, which is the ordering the (unsupported)
    -- sublevel argument was supposed to provide.
    local under = gc._neUnder
    if not under then return end
    local fill = under:CreateTexture(nil, "BORDER")
    fill:SetTexture("Interface\\Buttons\\WHITE8X8")
    fill:SetVertexColor(0.06, 0.06, 0.07, 0.90)
    place(fill)

    -- The border still has to be a frame, since AttachInset builds one — but a thin ring around the
    -- edges cannot swallow content the way a full-rect fill does.
    local ring = CreateFrame("Frame", nil, gc)
    ring:EnableMouse(false)
    ring:SetFrameLevel(math.max(0, gc:GetFrameLevel() or 1))
    place(ring)
    if NE.nineslice and NE.nineslice.AttachInset then
      pcall(NE.nineslice.AttachInset, ring, 0, 0, 0, 0)
    end
    gc._neCheckWellFill, gc._neCheckWellRing = fill, ring
  end

  -- Guild Bank Tab row shows the MAX tab count until a tab is clicked. Re-running Blizzard's updater
  -- did not help (owner-reported 2026-08-09) — the count is not what a plain no-argument update fixes,
  -- and the tab click is passing the updater state we cannot reproduce from outside. So correct the
  -- display directly: hide the buttons past the guild's real tab count.
  --
  -- The buttons are found by their visible "1".."6" text rather than by name, since they appear under
  -- no name this module can rely on. Permission checkboxes are CheckButtons and cannot match. Hooked
  -- onto the updater so it survives every later refresh, not just the one at open, and it no-ops
  -- whenever the count reads 0 so a cold cache never hides everything.
  local function fixBankTabCount()
    local n = GetNumGuildBankTabs and GetNumGuildBankTabs()
    if not n or n <= 0 then return end
    local maxTabs = _G.MAX_GUILD_BANK_TABS or 6
    local function scan(parent)
      if not parent or not parent.GetChildren then return end
      for _, k in ipairs({ parent:GetChildren() }) do
        if k.GetObjectType and k:GetObjectType() == "Button" and k.GetText then
          local idx = tonumber(k:GetText() or "")
          if idx and idx >= 1 and idx <= maxTabs then
            if idx <= n then k:Show() else k:Hide() end
          end
        end
      end
    end
    scan(_G.GuildControlPopupFrame)
    scan(_G.GuildControlPopupFrameTabPermissions)
  end

  local function skinGuildControl(gc)
    if gc._neSkinned then return end
    gc._neSkinned = true

    if gc.SetBackdrop then gc:SetBackdrop(nil) end

    -- Direct Texture regions only — the frame's own stock dialog art, including the flat grey band
    -- along the bottom. FontStrings (every label in here) are left alone, and the checkbox and
    -- tab-permission panels are child FRAMES, so neither is touched by this.
    for _, region in ipairs({ gc:GetRegions() }) do
      if region.GetObjectType and region:GetObjectType() == "Texture" then
        region:Hide()
      end
    end

    -- An UNDERLAY frame one level below the popup, carrying both the rock body and (later) the
    -- checkbox well's fill. This exists purely to get the draw order right, and it is the only shape
    -- that works on 3.3.5a: CreateTexture's sublevel argument does not exist here, so the -7/-8 pair
    -- these two used was silently ignored and the well's fill landed in the same layer as the body
    -- instead of above it, which is why it vanished (owner-reported 2026-08-09). Frame level puts the
    -- whole underlay below the popup's own regions — so every label stays visible — and within it,
    -- plain BACKGROUND/BORDER layers order the body against the fill, which 3.3.5a does support.
    local under = CreateFrame("Frame", nil, gc)
    under:EnableMouse(false)
    under:SetFrameLevel(math.max(0, (gc:GetFrameLevel() or 1) - 1))
    under:SetPoint("TOPLEFT",     gc, "TOPLEFT",                0, CHROME_LIFT)
    under:SetPoint("BOTTOMRIGHT", gc, "BOTTOMRIGHT", -WIDTH_TRIM, 0)
    gc._neUnder = under

    local body = under:CreateTexture(nil, "BACKGROUND")
    local rockPath = NE.tex and NE.tex.localFiles and NE.tex.localFiles[374155]
    body:SetTexture(rockPath or 374155, "REPEAT", "REPEAT")
    body:SetHorizTile(true); body:SetVertTile(true)
    -- Asymmetric on purpose, and this is the recurring square-edge (no-portrait) quirk rather than
    -- anything specific to this frame: its left border art is thicker than the other three, so an even
    -- inset leaves the fill poking out past it on the left while falling 2px short on the right and
    -- bottom (owner-measured 2026-08-09; same 5px left correction skinEventLog above already carries).
    -- Top also takes the lift, so the body covers the strip the raised border now spans.
    -- Insets are against the underlay, which already carries the lift and the width trim.
    body:SetPoint("TOPLEFT",     under, "TOPLEFT",   5, -4)
    body:SetPoint("BOTTOMRIGHT", under, "BOTTOMRIGHT", -2,  2)

    -- No-portrait layout, so the top-left corner stays flat. No TopTileStreaks: that banner belongs
    -- under a title bar and this popup has no title, just the rank-picker caption. Anchored point by
    -- point rather than SetAllPoints so the top edge can carry the lift.
    local ns = CreateFrame("Frame", nil, gc)
    ns:SetPoint("TOPLEFT",     gc, "TOPLEFT",                0, CHROME_LIFT)
    ns:SetPoint("BOTTOMRIGHT", gc, "BOTTOMRIGHT", -WIDTH_TRIM, 0)
    if NE.nineslice and NE.nineslice.ApplyLayout then
      NE.nineslice.ApplyLayout(ns, "ButtonFrameTemplateNoPortrait")
    end
    gc._neNineSlice = ns

    -- Recessed dark wells on the two content blocks, matching the Roster/Chat panels and the event
    -- log (owner steer 2026-08-09). Both are real frames, so each takes a flat fill plus an inset
    -- directly; their checkboxes and labels are children and draw on top of the fill.
    local function insetSection(section)
      if not section or section._neInset then return end
      section._neInset = true
      local bg = section:CreateTexture(nil, "BACKGROUND")
      bg:SetTexture("Interface\\Buttons\\WHITE8X8")
      bg:SetVertexColor(0.06, 0.06, 0.07, 0.90)
      bg:SetAllPoints(section)
      if NE.nineslice and NE.nineslice.AttachInset then
        pcall(NE.nineslice.AttachInset, section, 0, 0, 0, 0)
      end
    end
    -- ONLY TabPermissions. GuildControlPopupFrameCheckboxes is not the checkbox grid it sounds like —
    -- it spans nearly the whole popup interior, so filling it laid a 90%-opaque sheet over the rock
    -- body and dimmed both captions ("Select guild rank to modify:", "Allow this rank to:" are regions
    -- of the POPUP, and a child frame's texture draws above its parent's regions), while its inset drew
    -- a border around the entire content area. Owner 2026-08-09: "that seemingly brought back the old
    -- frame". A well around just the checkbox grid needs the grid's measured bounds, not this frame.
    insetSection(_G.GuildControlPopupFrameTabPermissions)

    -- Open/close sounds, via a child watcher rather than scripts on the frame itself (house pattern —
    -- the frame's own OnShow/OnHide belong to Blizzard here). Cancel went silent once the social
    -- window stopped opening behind it, since that stray window was what had been making the noise
    -- (owner-reported 2026-08-09).
    if NE.FrameUtil and NE.FrameUtil.WirePanelSounds then
      NE.FrameUtil.WirePanelSounds(gc, "igCharacterInfoOpen", "igCharacterInfoClose")
    end
  end

  local function openGuildControl()
    local gc = _G.GuildControlPopupFrame
    if not gc then return end

    primeGuildControl()

    gc:SetParent(UIParent)
    gc:SetFrameStrata("DIALOG")
    gc:SetToplevel(true)
    gc:SetClampedToScreen(true)
    gc:ClearAllPoints()
    -- Dropped by CHROME_LIFT so that the chrome's raised top edge — not the popup's own frame top —
    -- is what lines up with the guild window's top edge.
    gc:SetPoint("TOPLEFT", f, "TOPRIGHT", POPUP_X_GAP, -CHROME_LIFT)

    -- No corner X here, deliberately (owner steer 2026-08-09): unlike the event log, this popup is a
    -- commit/discard dialog and Accept/Cancel are the only correct ways out of it. An X would be a
    -- third exit with ambiguous semantics — does it save? — so the frame keeps just the two.

    -- Red 3-slice on Accept/Cancel. Watch walks the frame skinning any Button whose normal texture is
    -- the stock ui-panel-button-up art, which is what UIPanelButtonTemplate gives these two; the rank
    -- checkboxes are CheckButtons and are skipped by object type. Idempotent (latches _neSkinWatched),
    -- so calling it on every open is free.
    if NE.buttonskin and NE.buttonskin.Watch then pcall(NE.buttonskin.Watch, gc) end
    pcall(skinGuildControl, gc)
    pcall(skinDropDown, _G.GuildControlPopupFrameDropDown)
    tameSocialPopOut(_G.GuildControlPopupAcceptButton)
    tameSocialPopOut(_G.GuildControlPopupFrameCancelButton)

    -- Show fires the native OnShow, which runs Blizzard's updater. If that still errors on some
    -- build, swallow it and report once in chat rather than spamming red text with no context —
    -- the frame itself stays shown either way, so a partial popup beats a dead button.
    local ok, err = pcall(gc.Show, gc)
    if not ok and DEFAULT_CHAT_FRAME then
      DEFAULT_CHAT_FRAME:AddMessage("|cffff7f3fDragonUI:|r guild control: " .. tostring(err))
    end
    if _G.GuildControlPopupframe_Update then pcall(_G.GuildControlPopupframe_Update) end

    -- Deferred a frame so the layout these measure has actually resolved. Trim first — it can move
    -- bottom-anchored content — then fit the well to wherever the checkboxes ended up.
    -- Keep the tab row corrected through every later refresh, not just this open.
    if not gc._neTabHooked and _G.GuildControlPopupframe_Update and hooksecurefunc then
      gc._neTabHooked = true
      pcall(hooksecurefunc, "GuildControlPopupframe_Update", fixBankTabCount)
    end

    local function measured()
      pcall(fixBankTabCount)
      pcall(trimBottom, gc)
      pcall(wellAroundCheckboxes, gc)
    end
    if C_Timer and C_Timer.After then C_Timer.After(0, measured) else measured() end

    -- Escape closes it. FrameXML may already register this in its own OnLoad, so de-dupe.
    if _G.UISpecialFrames and not gc._neEscRegistered then
      gc._neEscRegistered = true
      local already = false
      for _, name in ipairs(_G.UISpecialFrames) do
        if name == "GuildControlPopupFrame" then already = true break end
      end
      if not already then tinsert(_G.UISpecialFrames, "GuildControlPopupFrame") end
    end
  end

  -- Cold-click path: rank data is pushed by the server, and with the native GuildFrame suppressed
  -- nothing else asks for it. If GuildControlGetNumRanks() is still 0 we request a roster and open
  -- as soon as the data lands, instead of showing an empty popup or erroring. GUILD_RANKS_UPDATE is
  -- registered defensively (pcall) since not every 3.3.5a-derived build declares it.
  -- Editing ranks is guild-leader only on 3.3.5a — every GuildControl* call the popup makes is
  -- rejected server-side for anyone else — so the button greys out rather than opening a dialog whose
  -- every control would silently fail (owner steer 2026-08-09).
  --
  -- IsGuildLeader() reads false until the roster arrives, which is why this is event-driven rather
  -- than evaluated once: a cold login would otherwise latch the button disabled for a guild leader.
  -- ButtonSkin hooks OnEnable/OnDisable (core/ButtonSkin.lua), so the red 3-slice follows by itself.
  local function updateControlEnabled()
    if not control then return end
    local leader = IsGuildLeader and IsGuildLeader()
    if leader then control:Enable() else control:Disable() end
  end
  f.UpdateControlEnabled = updateControlEnabled

  -- No "why is this greyed out" tooltip: a disabled Button stops firing OnEnter on 3.3.5a, and the
  -- retail opt-out for that (SetMotionScriptsWhileDisabled) does not exist here. Showing one would
  -- mean leaving the button enabled and faking the disabled look, which is not worth it for a hint.

  local rankWaiter = CreateFrame("Frame")
  pcall(rankWaiter.RegisterEvent, rankWaiter, "GUILD_RANKS_UPDATE")
  pcall(rankWaiter.RegisterEvent, rankWaiter, "GUILD_ROSTER_UPDATE")
  pcall(rankWaiter.RegisterEvent, rankWaiter, "PLAYER_GUILD_UPDATE")
  rankWaiter:SetScript("OnEvent", function(self)
    updateControlEnabled()
    -- Leadership can change while the popup is open (a /gquit or a guild leader transfer), and the
    -- popup's own controls would go dead without any visible reason. Close it instead.
    if not (IsGuildLeader and IsGuildLeader()) then
      local gc = _G.GuildControlPopupFrame
      if gc and gc:IsShown() then gc:Hide() end
    end
    if not self.pending then return end
    if (GuildControlGetNumRanks and GuildControlGetNumRanks() or 0) <= 0 then return end
    self.pending = nil
    openGuildControl()
  end)

  control:SetScript("OnClick", function()
    local gc = _G.GuildControlPopupFrame
    if not gc then
      -- Don't fail silently a second time: if a custom client stripped the frame, say so.
      if DEFAULT_CHAT_FRAME then
        DEFAULT_CHAT_FRAME:AddMessage("|cffff7f3fDragonUI:|r GuildControlPopupFrame is missing on this client.")
      end
      return
    end
    if gc:IsShown() then
      gc:Hide()
      rankWaiter.pending = nil
      return
    end
    if (GuildControlGetNumRanks and GuildControlGetNumRanks() or 0) > 0 then
      openGuildControl()
    else
      rankWaiter.pending = true
      if GuildRoster then GuildRoster() end
    end
  end)
  f.ControlButton = control

  local invite = CreateFrame("Button", FRAME_NAME .. "InviteButton", f, "UIPanelButtonTemplate")
  invite:SetSize(120, 22)
  invite:SetPoint("RIGHT", control, "LEFT", -4, 0)
  invite:SetText(GUILD_INVITE_MEMBER or COMMUNITIES_INVITE_MEMBERS or "Invite")
  f.InviteButton = invite

  -- Stock Blizzard invite dialog (owner steer 2026-07-17: "should trigger the default blizzard
  -- invite window not its own"). REVERTED the inline name-prompt tried earlier — that was built on
  -- an unverified assumption that StaticPopup_Show("ADD_GUILDMEMBER") silently no-ops here; on a
  -- standard 3.3.5a client this is the same long-standing popup the native GuildFrame invite button
  -- itself opens (hasEditBox, OnAccept calls GuildInvite() with the typed name internally).
  invite:SetScript("OnClick", function() StaticPopup_Show("ADD_GUILDMEMBER") end)
end

-- ---------------------------------------------------------------------------
-- Display-mode switching (retail CommunitiesFrameMixin:SetDisplayMode, guild subset).
-- ---------------------------------------------------------------------------
function G.SetDisplayMode(mode)
  local f = G.frame
  if not f or not MODE[mode] then return end
  f.displayMode = mode
  for _, key in ipairs(ALL_PANELS) do if f[key] then f[key]:Hide() end end
  for _, key in ipairs(MODE[mode]) do if f[key] then f[key]:Show() end end

  for _, d in ipairs(TAB_DEFS) do
    local tab = f[d.key]
    if tab then
      local active = (d.mode == mode)
      if tab._glow then tab._glow:SetShown(active) end
    end
  end

  -- The left GuildColumn is Roster-only (owner steer 2026-07-17) — it isn't one of the per-mode
  -- content panels swapped above, so toggle it separately.
  if f.GuildColumn then f.GuildColumn:SetShown(mode == "ROSTER") end

  -- Bottom controls per mode. Chat no longer has its own mode (folded into GUILD_INFO), so Invite
  -- is just shown in both remaining modes now; Guild Control and the log button unchanged.
  if f.InviteButton  then f.InviteButton:SetShown(mode == "ROSTER" or mode == "GUILD_INFO") end
  if f.ControlButton then f.ControlButton:SetShown(mode == "ROSTER" or mode == "GUILD_INFO") end
  -- Re-check leadership whenever the button comes back into view, in case the roster settled while a
  -- different tab was up and no event is due.
  if f.UpdateControlEnabled then f.UpdateControlEnabled() end
  if f.LogButton     then f.LogButton:SetShown(mode == "GUILD_INFO") end

  if mode == "ROSTER" and G.RefreshRoster then G.RefreshRoster() end
  if mode == "GUILD_INFO" and G.RefreshInfo then G.RefreshInfo() end
  if mode == "ROSTER" and G.UpdateTabard then G.UpdateTabard() end
end

-- ---------------------------------------------------------------------------
-- Construction + show/hide.
-- ---------------------------------------------------------------------------
local function createWindow()
  if G.frame then return G.frame end

  -- DOWNPORT: a bare Frame (no "PortraitFrameTemplate" widget-template inheritance) — matches
  -- modules/professions + modules/spellbook + modules/character, NOT the Auction House module's
  -- template-inherited approach. On this client, inheriting the template didn't yield a usable
  -- f.portrait region and left the chrome looking flat; every OTHER window in this addon builds
  -- 100% of its chrome (body/streaks/nineslice/portrait) manually on a plain frame, which is the
  -- proven-working pattern.
  local f = CreateFrame("Frame", FRAME_NAME, UIParent)
  -- The red 3-slice is the addon's standard button; Watch keeps this window's panel buttons
  -- skinned as its panes are built (core/ButtonSkin.lua). Opt out per button with _neNoSkin.
  if NE.buttonskin and NE.buttonskin.Watch then pcall(NE.buttonskin.Watch, f) end
  f:SetSize(990, 582)   -- owner steer: ~30% larger than the first pass
  f:SetPoint("LEFT", UIParent, "LEFT", 16, 0)
  f:SetFrameStrata("DIALOG")
  f:SetMovable(true); f:SetClampedToScreen(true); f:EnableMouse(true)
  f:RegisterForDrag("LeftButton")
  f:SetScript("OnDragStart", function(self) self:StartMoving() end)
  f:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() end)
  f:Hide()
  G.frame = f

  buildChrome(f)
  buildPanels(f)
  buildSideTabs(f)
  buildControls(f)

  -- Data layers (each guarded; built once, before the first SetDisplayMode).
  if G.SetupRoster then G.SetupRoster(f) end
  if G.SetupInfo   then G.SetupInfo(f) end
  if G.SetupChat   then G.SetupChat(f) end

  f:HookScript("OnShow", function()
    local gname = IsInGuild and IsInGuild() and GetGuildInfo("player")
    if NE.panelchrome and NE.panelchrome.SetTitle then NE.panelchrome.SetTitle(f, gname or (GUILD or "Guild")) end
    -- Best-effort immediate paint (cached count, may be stale) — GuildRoster()'s response below
    -- fires GUILD_ROSTER_UPDATE, which re-syncs it for real via Roster.lua's recountOnline.
    -- BUG FIX 2026-07-17: this used to omit `total`, so SetGuild's `online and total` check always
    -- failed and blanked the member count on every open — self-healing only if GUILD_ROSTER_UPDATE
    -- happened to refire while shown, which GuildRoster()'s server-side throttle makes unreliable
    -- (owner report: crest/count "doesn't always load"). GetNumGuildMembers() is always immediately
    -- available (no roster scan needed), unlike G._onlineCount which requires recountOnline to have
    -- run at least once.
    local total = GetNumGuildMembers and GetNumGuildMembers()
    if f.GuildColumn and f.GuildColumn.SetGuild then f.GuildColumn.SetGuild(gname, G._onlineCount, total) end
    if GuildRoster then GuildRoster() end   -- request a fresh roster on open
    if G.RefreshRoster then G.RefreshRoster() end
    if G.RefreshInfo then G.RefreshInfo() end
  end)

  -- Close the popups this window owns whenever the window itself hides — neither is reachable once
  -- their launcher is gone, so leaving one floating orphans it (owner-reported 2026-08-09 for Guild
  -- Control; the event log was already handled the same way).
  f:HookScript("OnHide", function()
    if _G.GuildEventLogFrame and _G.GuildEventLogFrame:IsShown() then
      _G.GuildEventLogFrame:Hide()
    end
    if _G.GuildControlPopupFrame and _G.GuildControlPopupFrame:IsShown() then
      _G.GuildControlPopupFrame:Hide()
    end
  end)

  if NE.FrameUtil and NE.FrameUtil.WirePanelSounds then
    NE.FrameUtil.WirePanelSounds(f, "igCharacterInfoOpen", "igCharacterInfoClose")
  end
  if NE.FrameUtil and NE.FrameUtil.EscClose then NE.FrameUtil.EscClose(FRAME_NAME) end
  -- Window scale (owner steer 2026-07-17: "the guild tab [needs] to follow the same scaling" as
  -- the Social window). NE.scale.Apply is the preferred path (core/Scale.lua's DEFAULTS["guild"]
  -- matches Social's 1.0 default, and is exposed as a mode dropdown + custom slider in the options
  -- panel's "Window Scaling" section, same as Professions/Spellbook/Talents/Social).
  -- PinPixelPerfect(f) is the fallback if core/Scale.lua isn't loaded for some reason.
  if NE.scale and NE.scale.Apply then
    if NE.scale.SetFrame then NE.scale.SetFrame("guild", f) end
    NE.scale.Apply("guild")
  elseif NE.panelchrome and NE.panelchrome.PinPixelPerfect then
    NE.panelchrome.PinPixelPerfect(f)
  end

  G.SetDisplayMode("ROSTER")   -- owner steer 2026-07-15: Roster is the default tab, not Chat
  return f
end

function G.Show()
  if not isModuleEnabled() then return end
  local f = createWindow()
  -- If the Social/Friends window is open (its Guild tab is what usually launches us), open to its
  -- RIGHT instead of stacking on the same default LEFT anchor (both windows default to
  -- UIParent LEFT +16 -- identical spots -- so without this they land fully overlapped).
  local social = NE.social and NE.social.frame
  if social and social:IsShown() then
    f:ClearAllPoints()
    f:SetPoint("LEFT", social, "RIGHT", 8, 0)
  end
  f:Show()
end
function G.Hide() if G.frame then G.frame:Hide() end end
function G.Toggle()
  local f = createWindow()
  if f:IsShown() then G.Hide() else G.Show() end
end

-- Boot: build the shell at login so it's warm, register with the options/QA seams.
local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("PLAYER_LOGIN")
eventFrame:SetScript("OnEvent", function()
  if isModuleEnabled() then createWindow() end
  if NE.RegisterPanel then
    NE.RegisterPanel({
      id = MODULE,
      title = GUILD or "Guild",
      desc = "Modern Communities-style guild window (Roster / Info / Chat).",
      frame = G.frame,
      openFn = G.Show,
      closeFn = G.Hide,
      order = 60,
    })
  end
end)
