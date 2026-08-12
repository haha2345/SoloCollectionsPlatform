-- DragonUI_NewEra/modules/guild/Chat.lua — Guild chat (CHAT mode).
--
-- DOWNPORT of NewEra/Guild/Chat.lua. NewEra uses retail's C_Club stream + CommunitiesChatFrame.
-- On 3.3.5a there is no C_Club: guild chat is the CHAT_MSG_GUILD / CHAT_MSG_OFFICER channels. We
-- mirror those into a ScrollingMessageFrame and send via SendChatMessage(msg, "GUILD").
--
-- HISTORY SYNC (owner steer 2026-07-18): 3.3.5a has no server-side chat log, so a fresh /reload or
-- login shows an empty window. We keep a small rolling log per guild in SavedVariables and, on
-- login, ask other online guildmates (SendAddonMessage over the "GUILD" distribution) for anything
-- newer than what we already have. Two problems the owner flagged up front, and how this avoids
-- both:
--   * Dedup: identity is author+kind+message text, deliberately WITHOUT the epoch timestamp (see
--     dedupKeyFor() below) — CHAT_MSG_GUILD is a broadcast, so every online client independently
--     stamps the same message with its OWN local time() the instant it sees it, and those can
--     differ by a second or more between clients. An epoch-keyed dedup let the same message land
--     under two different keys and show up twice once synced; text-keyed dedup can't split that way.
--     When two copies of the same message DO show up with different epochs, remember() keeps
--     whichever is earliest (closest to the true origin time) rather than whichever arrived first.
--   * Timezones: we never do manual TZ math. epoch is a plain time() value (already UTC-based on
--     any sane system clock); each client formats it for display with its OWN date() call, so
--     everyone sees times in their own computer's local time automatically.
-- Scope/safety: only regular guild chat (kind "G") is ever relayed over the addon channel. Officer
-- chat (kind "O") is still logged+restored locally (so YOUR OWN officer scrollback survives a
-- reload) but is never broadcast — CHAT_MSG_OFFICER only ever fires for clients already privileged
-- to see it, and relaying it over the guild-wide "GUILD" addon distribution would leak it to
-- non-officers. There is no sync request/response for officer chat in this version.
--
-- 3.3.5a API notes: SendAddonMessage/CHAT_MSG_ADDON(prefix, message, channel, sender) and time()/
-- date() are unchanged core APIs in this era. RegisterAddonMessagePrefix does not exist yet (a
-- later-expansion addition), so the prefix is just used directly with no registration step.

local NE = DragonUI_NewEra
if not NE then return end

NE.guild = NE.guild or {}
local G = NE.guild

-- Guild/officer channel colours (ChatTypeInfo, with sane fallbacks).
local function chanColor(kind)
  local info = ChatTypeInfo and ChatTypeInfo[kind]
  if info then return info.r, info.g, info.b end
  if kind == "OFFICER" then return 0.4, 0.78, 0.94 end
  return 0.25, 1, 0.25
end

-- The ScrollingMessageFrame, if the guild window's Chat tab has been built this session.
local function logFrame()
  return G.frame and G.frame.ChatFrame and G.frame.ChatFrame.Log
end

-- ----------------------------------------------------------------------------
-- Class-coloured names (owner ask 2026-07-18). name -> classFileName, rebuilt from
-- GetGuildRosterInfo() on GUILD_ROSTER_UPDATE — same roster API Roster.lua already uses.
-- ----------------------------------------------------------------------------
local nameClass = {}

-- Forward-declared: assigned once printBacklogLine()/store() exist below. refreshRosterClasses
-- only ever CALLS this from an event handler (never at file-load time), so by the time it runs
-- the assignment further down has already happened — this is just working around Lua's top-to-
-- bottom local scoping, not a real ordering hazard.
local repaintLog

-- Backlog is replayed exactly once, the first time the chat panel is built (see G.SetupChat) —
-- which can easily happen before GUILD_ROSTER_UPDATE has fired even once (window opened right
-- after login, before the roster request completes). That first replay falls back to the "unknown
-- class" colour for everyone since nameClass is still empty. G.SetupChat flags
-- panel._needsRecolor in that case; once we actually get roster data, repaint the log so history
-- picks up real class colours instead of staying stuck on the fallback forever.
-- Populates nameClass from GetGuildRosterInfo() for every member GetNumGuildMembers() currently
-- reports; returns the total scanned. Whether OFFLINE members come back with real data depends
-- entirely on GetGuildRosterShowOffline()'s CURRENT value at call time — this function never
-- touches that flag itself. The two callers below handle that in two deliberately different ways.
local function scanRosterClasses()
  if not GetNumGuildMembers or not GetGuildRosterInfo then return 0 end
  local total = GetNumGuildMembers() or 0
  for i = 1, total do
    local name, _, _, _, _, _, _, _, _, _, classFile = GetGuildRosterInfo(i)
    if name then
      -- CHAT_MSG_GUILD author names are never realm-qualified on 3.3.5a's single-realm chat,
      -- but the roster can list "Name-Realm" on some servers — key on the bare name either way.
      nameClass[name:match("^([^%-]+)") or name] = classFile
    end
  end
  return total
end

-- Reads directly, with NO SetGuildRosterShowOffline call — matching how Blizzard's own default
-- guild UI works: that flag is set only by an explicit user action (the Roster tab's checkbox,
-- Roster.lua:265) or by scanOfflineClassesOnce below, never automatically from an event handler.
-- This is what makes it safe to run on every GUILD_ROSTER_UPDATE (it's registered on that event
-- below): it can't recurse, because it never writes the flag that would re-trigger it.
--
-- An earlier version DID force the flag here, which caused a live crash (C stack overflow — this
-- function recursing into itself via the very event its own flag-write re-fired) and spammed every
-- guildmate who had the Roster tab open, because that re-fire also fans out into every OTHER
-- addon's GUILD_ROSTER_UPDATE handler, including the base DragonUI addon's unthrottled
-- version-broadcast system (modules/versioncheck.lua).
local function refreshRosterClasses()
  local total = scanRosterClasses()
  local panel = G.frame and G.frame.ChatFrame
  if total > 0 and panel and panel._needsRecolor then
    panel._needsRecolor = nil
    if repaintLog then repaintLog() end
  end
end

-- ONE-SHOT: brings OFFLINE guildmates' class colours back for chat history — something
-- refreshRosterClasses alone can't do, since GetGuildRosterInfo only returns complete data for an
-- offline member's slot while GetGuildRosterShowOffline() is true. Runs exactly once per session,
-- and — critically — from a plain timer callback that is NOT itself registered on
-- GUILD_ROSTER_UPDATE (see where this is scheduled, PLAYER_ENTERING_WORLD below), so even though
-- SetGuildRosterShowOffline synchronously re-fires that event on this client, nothing here can
-- recurse: the re-fire just re-enters refreshRosterClasses, which is passive and never writes the
-- flag.
--
-- STILL NOT SIDE-EFFECT-FREE, BY ACCEPTED DESIGN: the base DragonUI addon's versioncheck.lua also
-- listens for GUILD_ROSTER_UPDATE and sends an unthrottled guild-chat message on every firing.
-- Each SetGuildRosterShowOffline call below re-fires the event once, so this puts one or two
-- "DUI_Version" lines in guild chat, once, at login — an accepted, bounded tradeoff for getting
-- offline colours back automatically. DragonUI itself is out of scope for this addon to modify.
local hasScannedOffline = false
local function scanOfflineClassesOnce()
  if hasScannedOffline then return end
  if not (IsInGuild and IsInGuild()) then return end
  if not (SetGuildRosterShowOffline and GetGuildRosterShowOffline) then return end
  hasScannedOffline = true

  local prevShowOffline = GetGuildRosterShowOffline()
  if not prevShowOffline then SetGuildRosterShowOffline(true) end
  local total = scanRosterClasses()
  if not prevShowOffline then SetGuildRosterShowOffline(false) end

  local panel = G.frame and G.frame.ChatFrame
  if total > 0 and panel and repaintLog then repaintLog() end
end

-- Same RAID_CLASS_COLORS convention as Roster.lua's classColor(), just hex-packed for inline
-- |cffRRGGBB codes instead of separate r,g,b floats.
local function classColorHex(classFile)
  local c = classFile and RAID_CLASS_COLORS and RAID_CLASS_COLORS[classFile]
  local r, g, b = 1, 0.82, 0
  if c then r, g, b = c.r, c.g, c.b end
  return string.format("%02x%02x%02x", math.floor(r * 255 + 0.5), math.floor(g * 255 + 0.5), math.floor(b * 255 + 0.5))
end

-- Builds the "[Author]: " lead-in with the author's name (only) class-coloured; the rest of the
-- line keeps using AddMessage's own r,g,b (the channel colour), same as before this feature.
local function nameSegment(author)
  return string.format("|cff%s[%s]|r: ", classColorHex(nameClass[author]), author or "?")
end

-- ----------------------------------------------------------------------------
-- Rolling per-guild log (NE.db.guildChat[guildKey]) + history sync protocol.
-- ----------------------------------------------------------------------------
local PREFIX     = "DUINE_GCH"
local FS         = "\1"   -- field separator: a control byte normal chat text can't type
local MAX_STORED = 300    -- ring buffer cap per guild
local MAX_RELAY  = 30     -- most entries we'll hand a single sync requester
local MAX_MSG    = 200    -- truncate relayed message text to this before adding protocol overhead

local function guildKey()
  local name = GetGuildInfo and GetGuildInfo("player")
  if not name then return nil end
  return (GetRealmName() or "?") .. "-" .. name
end

local function store()
  local db = NE.db
  if not db then return nil end
  db.guildChat = db.guildChat or {}
  local key = guildKey()
  if not key then return nil end
  local s = db.guildChat[key]
  if not s then s = { entries = {}, seen = {}, newest = 0 }; db.guildChat[key] = s end
  return s
end

-- Identifies a message for dedup purposes. Deliberately EPOCH-FREE: CHAT_MSG_GUILD is a broadcast,
-- so every online client independently "first witnesses" the same message and stamps it with its
-- OWN local time() — there is no single shared origin timestamp. Two clients' clocks (or just
-- event-processing jitter) only need to differ by a second for the same message to land under two
-- different epochs, which silently defeated an epoch-keyed dedup and let synced history show real
-- duplicates (owner report 2026-07-18). Author+kind+text alone is stable no matter whose clock
-- first logged it. Tradeoff: the exact same text from the exact same person won't be stored twice
-- while it's still within the MAX_STORED window — an acceptable, rare cost for guaranteed dedup.
local function dedupKeyFor(kind, author, message)
  return (author or "?") .. FS .. kind .. FS .. (message or "")
end

-- Insert (kind, author, message, epoch) if not already known. If it IS already known, keep
-- whichever epoch is EARLIEST: two guildmates with slightly different system clocks (or just
-- event-processing jitter) can each "first witness" the same live broadcast a moment apart and
-- store it under two different epochs — the smaller one is the better guess at when it actually
-- happened. Returns true only for a genuinely new message.
local function remember(kind, author, message, epoch)
  local s = store()
  if not s then return false end
  local dedupKey = dedupKeyFor(kind, author, message)
  local knownEpoch = s.seen[dedupKey]
  if knownEpoch then
    if epoch < knownEpoch then
      s.seen[dedupKey] = epoch
      for _, e in ipairs(s.entries) do
        if e.kind == kind and e.author == author and e.message == message then
          e.epoch = epoch
          break
        end
      end
    end
    return false
  end
  s.seen[dedupKey] = epoch

  -- Insert in epoch order rather than blind-appending. Live messages are almost always the
  -- newest thing we know about (a short scan from the tail), but a sync reply can hand us an
  -- older backlog entry out of arrival order — position must reflect WHEN it happened, not when
  -- we heard about it, or the MAX_STORED eviction below (which drops index 1, "oldest") could
  -- evict genuinely recent chat to make room for old backlog that arrived after it.
  local entries = s.entries
  local i = #entries
  while i > 0 and entries[i].epoch > epoch do
    i = i - 1
  end
  table.insert(entries, i + 1, { kind = kind, author = author, message = message, epoch = epoch })

  if epoch > s.newest then s.newest = epoch end
  if #entries > MAX_STORED then
    local drop = table.remove(entries, 1)
    s.seen[dedupKeyFor(drop.kind, drop.author, drop.message)] = nil
  end
  return true
end

-- Shared line text: a dim [HH:MM] stamp + the class-coloured name segment + the message. Used for
-- BOTH backlog and live lines so the timestamp is always there either way (owner report 2026-07-18:
-- history had timestamps but live-session lines didn't — inconsistent); only the base AddMessage
-- colour (full brightness live vs toned-down for backlog) still tells the two apart.
local function formatLine(author, message, epoch)
  local stamp = date and date("%H:%M", epoch) or ""
  return string.format("|cff888888[%s]|r ", stamp) .. nameSegment(author) .. (message or "")
end

-- Tracks how many lines are currently in `log`, for NE.scrollbar.BuildCustomMessageFrame (this
-- 3.3.5a client's ScrollingMessageFrame has no GetNumMessages() to ask directly — see the fix note
-- in ScrollbarReskin.lua). Clamped to the widget's own SetMaxLines(500) cap so the count stays
-- accurate indefinitely: AddMessage past that cap silently drops the widget's own oldest line, so
-- an uncapped counter would drift high over a long play session and make the scrollbar think there
-- was more history than the widget actually still holds.
local function trackLine(log)
  local n = (log._neTotalLines or 0) + 1
  local cap = log.GetMaxLines and log:GetMaxLines()
  if cap and cap > 0 and n > cap then n = cap end
  log._neTotalLines = n
end

-- Render one line into the log's ScrollingMessageFrame with the dim "backlog" treatment: toned-
-- down channel colour, distinguishing it from freshly-arriving lines.
local function printBacklogLine(log, kind, author, message, epoch)
  local r, g, b = chanColor(kind == "O" and "OFFICER" or "GUILD")
  log:AddMessage(formatLine(author, message, epoch), r * 0.75, g * 0.75, b * 0.75)
  trackLine(log)
end

-- Every live message is also `remember()`-ed (see the event handler below), so the stored log is
-- always a complete record of everything ever shown — safe to wipe and fully replay at any time.
repaintLog = function()
  local log = logFrame()
  local s = store()
  if not log or not s then return end
  log:Clear()
  log._neTotalLines = 0
  for _, e in ipairs(s.entries) do
    printBacklogLine(log, e.kind, e.author, e.message, e.epoch)
  end
end

-- Retries the backlog replay G.SetupChat had to skip because guildKey() (GetGuildInfo("player"))
-- wasn't resolved yet. Safe to call speculatively any time guild info might have just become
-- available; it's a no-op unless SetupChat actually left the flag set.
local function tryReplayBacklog()
  local panel = G.frame and G.frame.ChatFrame
  if not panel or not panel._needsBacklog then return end
  local s = store()
  if not s then return end -- guild info still not resolved; keep waiting
  panel._needsBacklog = nil
  if next(nameClass) == nil then panel._needsRecolor = true end
  repaintLog()
end

function G.SetupChat(f)
  local panel = f.ChatFrame
  if not panel or panel._built then return end
  panel._built = true

  -- Dark recessed backdrop behind the whole chat panel (same treatment as the Roster panel,
  -- owner steer 2026-07-17: "add that same dark background inset behind the guild chat").
  local panelBg = panel:CreateTexture(nil, "BACKGROUND")
  panelBg:SetTexture("Interface\\Buttons\\WHITE8X8")
  panelBg:SetVertexColor(0.06, 0.06, 0.07, 0.90)
  panelBg:SetAllPoints(panel)
  panel.Bg = panelBg
  if NE.nineslice and NE.nineslice.AttachInset then pcall(NE.nineslice.AttachInset, panel, 0, 0, 0, 0) end

  -- Recessed message well.
  local well = CreateFrame("Frame", nil, panel)
  well:SetPoint("TOPLEFT", panel, "TOPLEFT", 2, -2)
  well:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -2, 30)
  if NE.nineslice and NE.nineslice.AttachInset then pcall(NE.nineslice.AttachInset, well, 0, 0, 0, 0) end

  local msg = CreateFrame("ScrollingMessageFrame", "NE_GuildChatLog", well)
  msg:SetPoint("TOPLEFT", well, "TOPLEFT", 8, -6)
  msg:SetPoint("BOTTOMRIGHT", well, "BOTTOMRIGHT", -24, 6)
  msg:SetFontObject(ChatFontNormal or GameFontHighlightSmall)
  msg:SetJustifyH("LEFT")
  msg:SetFading(false)
  msg:SetMaxLines(500)
  msg:EnableMouseWheel(true)
  if msg.SetHyperlinksEnabled then msg:SetHyperlinksEnabled(true) end
  msg:SetScript("OnMouseWheel", function(self, delta)
    if delta > 0 then
      if IsShiftKeyDown() and self.ScrollToTop then self:ScrollToTop() else self:ScrollUp() end
    else
      if IsShiftKeyDown() and self.ScrollToBottom then self:ScrollToBottom() else self:ScrollDown() end
    end
  end)
  msg:SetScript("OnHyperlinkClick", function(self, link, text, button)
    if SetItemRef then SetItemRef(link, text, button) end
  end)
  panel.Log = msg

  -- Visible scrollbar (owner ask 2026-07-24), same minimal-scrollbar art as the rest of the guild
  -- window. `well`'s right inset (24px, see msg's BOTTOMRIGHT point above) is the gutter this bar
  -- lives in. ScrollingMessageFrame isn't a ScrollFrame, so this uses the dedicated line-scroll
  -- variant rather than Reskin/BuildCustom(Pixel); wheel handling stays on msg's own OnMouseWheel
  -- above, this only mirrors the resulting scroll position.
  if NE.scrollbar and NE.scrollbar.BuildCustomMessageFrame then
    -- x = -8, same value Window.lua's GuildEventLog scrollbar uses (BuildCustom's default -2 is
    -- sized for the bare 8px track; the arrow buttons are 17px wide and centered on that track, so
    -- they overhang ~4.5px past each edge -- at the default inset that overhang pokes back into
    -- msg's own text area and visibly overlaps chat lines that run to the right edge).
    local ok, bar = pcall(NE.scrollbar.BuildCustomMessageFrame, msg, { x = -8 })
    if ok and bar then
      -- Same DIALOG-strata trap as Window.lua's GuildEventLog scrollbar (see its comment at
      -- ~line 516) and the Auction House lists: the guild window frame `f` is unconditionally
      -- DIALOG strata (Window.lua:649), so every descendant (well/msg included) inherits DIALOG
      -- too -- a HIGH-strata bar (BuildCustomMessageFrame's default) renders BEHIND that content,
      -- i.e. invisible. Force it up to match, same as the established fix elsewhere in this addon.
      bar:SetFrameStrata("DIALOG")
      bar:SetFrameLevel((well:GetFrameLevel() or 1) + 10)
      if bar._upBtn then bar._upBtn:SetFrameStrata("DIALOG"); bar._upBtn:SetFrameLevel(bar:GetFrameLevel() + 1) end
      if bar._downBtn then bar._downBtn:SetFrameStrata("DIALOG"); bar._downBtn:SetFrameLevel(bar:GetFrameLevel() + 1) end
    end
  end

  -- Send edit box.
  local edit = CreateFrame("EditBox", "NE_GuildChatEdit", panel, "InputBoxTemplate")
  edit:SetHeight(20)
  edit:SetPoint("BOTTOMLEFT", panel, "BOTTOMLEFT", 8, 6)
  edit:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -8, 6)
  edit:SetAutoFocus(false)
  edit:SetScript("OnEnterPressed", function(self)
    local text = self:GetText()
    if text and text ~= "" and SendChatMessage then
      SendChatMessage(text, "GUILD")
    end
    self:SetText("")
    self:ClearFocus()
  end)
  edit:SetScript("OnEscapePressed", function(self) self:SetText(""); self:ClearFocus() end)
  panel.Edit = edit

  -- Replay whatever we already have logged (earlier THIS or a DIFFERENT character on the same
  -- account, or synced from a guildmate) so opening the window doesn't start blank. Backlog lines
  -- get the dim timestamp treatment; live lines arriving from here on print with the plain style
  -- via appendGuild() below.
  local s = store()
  if s then
    if next(nameClass) == nil then panel._needsRecolor = true end -- roster not loaded yet
    for _, e in ipairs(s.entries) do
      printBacklogLine(msg, e.kind, e.author, e.message, e.epoch)
    end
  else
    -- guildKey() came back nil — GetGuildInfo("player") hasn't resolved yet this soon after
    -- login/char-switch (owner report 2026-07-18: history from another character on the same
    -- account "isn't there" if the window's opened quickly). SetupChat only ever runs once
    -- (panel._built), so flag it for tryReplayBacklog() to retry once guild info is available.
    panel._needsBacklog = true
  end
end

local function appendGuild(kind, message, author, epoch)
  local log = logFrame()
  if not log then return end
  local r, g, b = chanColor(kind)
  log:AddMessage(formatLine(author, message, epoch), r, g, b)
  trackLine(log)
end
G.AppendGuildMessage = appendGuild

-- ----------------------------------------------------------------------------
-- Outbound send throttle: a sync reply can be several messages back-to-back; space them out so we
-- don't trip a private server's chat-flood protection (addon messages share that same queue).
-- ----------------------------------------------------------------------------
local sendQueue = {}
local function pumpQueue()
  local job = table.remove(sendQueue, 1)
  if not job then return end
  SendAddonMessage(PREFIX, job, "GUILD")
  if #sendQueue > 0 then C_Timer.After(0.2, pumpQueue) end
end
local function queueSend(payload)
  sendQueue[#sendQueue + 1] = payload
  if #sendQueue == 1 then pumpQueue() end
end

-- Reply to a sync request: hand over our newest guild-chat (kind "G" only) entries after `since`.
local function replyWithHistory(since)
  local s = store()
  if not s then return end
  local out = {}
  for _, e in ipairs(s.entries) do
    if e.kind == "G" and e.epoch > since then out[#out + 1] = e end
  end
  if #out == 0 then return end
  if #out > MAX_RELAY then
    -- A huge gap shouldn't turn into a message storm; keep the newest. Relies on s.entries being
    -- epoch-ordered (remember()'s sorted insert), so a straight tail-slice is correct here.
    local trimmed = {}
    for i = #out - MAX_RELAY + 1, #out do trimmed[#trimmed + 1] = out[i] end
    out = trimmed
  end
  for _, e in ipairs(out) do
    local text = e.message or ""
    -- Truncation only happens here, on the relaying side — a peer who gets this via sync stores
    -- the shortened "..." text permanently, while whoever was online for the live message kept
    -- the full text. A known, accepted asymmetry given the 200-char cap; not worth chunking
    -- single messages across multiple addon messages just to avoid it.
    if #text > MAX_MSG then text = text:sub(1, MAX_MSG) .. "..." end
    queueSend("H" .. FS .. (e.author or "?") .. FS .. e.epoch .. FS .. text)
  end
end

-- Split on FS but cap the piece count, so message text (the last piece) is taken verbatim even if
-- it happens to contain a stray FS byte — it's never chopped up looking for more separators.
local function splitFields(payload, maxParts)
  local parts, from = {}, 1
  for i = 1, maxParts - 1 do
    local at = payload:find(FS, from, true)
    if not at then return nil end
    parts[i] = payload:sub(from, at - 1)
    from = at + 1
  end
  parts[maxParts] = payload:sub(from)
  return parts
end

local hasSynced = false
local function requestSync()
  if hasSynced or not IsInGuild or not IsInGuild() then return end
  hasSynced = true
  local s = store()
  local since = s and s.newest or 0
  SendAddonMessage(PREFIX, "R" .. FS .. since, "GUILD")
end

local ev = CreateFrame("Frame")
ev:RegisterEvent("CHAT_MSG_GUILD")
ev:RegisterEvent("CHAT_MSG_OFFICER")
ev:RegisterEvent("CHAT_MSG_ADDON")
ev:RegisterEvent("PLAYER_ENTERING_WORLD")
ev:RegisterEvent("GUILD_ROSTER_UPDATE")
ev:RegisterEvent("PLAYER_GUILD_UPDATE")   -- fires once our own guild membership info resolves
ev:SetScript("OnEvent", function(_, event, a1, a2, a3, a4)
  if event == "GUILD_ROSTER_UPDATE" then
    refreshRosterClasses()
    tryReplayBacklog()
    return
  end

  if event == "PLAYER_GUILD_UPDATE" then
    tryReplayBacklog()
    return
  end

  if event == "PLAYER_ENTERING_WORLD" then
    refreshRosterClasses()
    tryReplayBacklog()
    if GuildRoster then GuildRoster() end   -- request a fresh roster so classes resolve promptly
    -- Belt-and-braces retry: PLAYER_GUILD_UPDATE/GUILD_ROSTER_UPDATE normally beat this to it, but
    -- if guild info resolved without either firing again this session, don't leave history stuck.
    C_Timer.After(5, function() tryReplayBacklog(); requestSync() end)
    -- Deliberately its OWN timer, not folded into the one above: scanOfflineClassesOnce writes
    -- SetGuildRosterShowOffline, and calling that from a callback that's ALSO doing other things is
    -- fine, but keeping it a separate, clearly-named scheduled call makes it obvious at a glance
    -- that this is the one deliberate place in the file where that flag gets touched.
    C_Timer.After(8, scanOfflineClassesOnce)
    return
  end

  if event == "CHAT_MSG_GUILD" or event == "CHAT_MSG_OFFICER" then
    local message, author = a1, a2
    local kind = event == "CHAT_MSG_OFFICER" and "OFFICER" or "GUILD"
    local epoch = time()
    remember(kind == "OFFICER" and "O" or "G", author, message, epoch)
    appendGuild(kind, message, author, epoch)
    return
  end

  -- CHAT_MSG_ADDON: prefix, message, channel, sender
  local prefix, payload, channel, sender = a1, a2, a3, a4
  if prefix ~= PREFIX or channel ~= "GUILD" then return end
  -- Cheap insurance: if this server core ever echoes our own SendAddonMessage back to us (varies
  -- by core), don't let a self-received "R" schedule a pointless reply to ourselves.
  if sender and UnitName and sender == UnitName("player") then return end
  local tag = payload:sub(1, 1)

  if tag == "R" then
    local since = tonumber(payload:sub(3))
    if since then
      -- Stagger replies so a login doesn't make every online guildmate answer at once.
      C_Timer.After(0.5 + math.random() * 2.5, function() replyWithHistory(since) end)
    end
  elseif tag == "H" then
    local parts = splitFields(payload:sub(3), 3)
    if not parts then return end
    local author, epoch, text = parts[1], tonumber(parts[2]), parts[3]
    if author and epoch and text then
      local isNew = remember("G", author, text, epoch)
      if isNew then
        local log = logFrame()
        if log then printBacklogLine(log, "G", author, text, epoch) end
      end
    end
  end
end)
