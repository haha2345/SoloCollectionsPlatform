-- DragonUI_NewEra/modules/guild/Info.lua — Guild Information (GUILD_INFO mode): MOTD + info text.
--
-- DOWNPORT of NewEra/Guild/Guild.lua:buildDetails. Both wells are REAL on 3.3.5a
-- (GetGuildRosterMOTD / GetGuildInfoText); edits commit through GuildSetMOTD / SetGuildInfoText
-- when the viewer has the right (CanEditMOTD / CanEditGuildInfo). Rendered over the classic
-- Interface\GuildFrame\GuildFrame parchment for the classic-guild look inside the modern chrome.

local NE = DragonUI_NewEra
if not NE then return end

NE.guild = NE.guild or {}
local G = NE.guild

local GUILDFRAME = "Interface\\GuildFrame\\GuildFrame"

-- A labelled, scrollable, optionally-editable multiline text well. `name` is required so the
-- scroll template's $parent-named scrollbar resolves (3.3.5a templates need a named parent).
local function buildWell(parent, name, labelText, anchorTop, height, commitFn, canEditFn)
  -- Section header BAR (reference frame bands each section: "Guild Message Of The Day:" /
  -- "Guild Information" sit on a gold parchment strip, not as bare floating labels). Texcoords
  -- transcribed from the reference's GuildInfo.xml crop of Interface\GuildFrame\GuildFrame.
  local bar = parent:CreateTexture(nil, "ARTWORK")
  bar:SetTexture(GUILDFRAME)
  bar:SetTexCoord(0.00097656, 0.31445313, 0.93164063, 0.97460938)
  bar:SetHeight(22)
  bar:SetPoint("TOPLEFT",  parent, "TOPLEFT",  6, anchorTop)
  bar:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -6, anchorTop)

  local label = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  label:SetPoint("LEFT", bar, "LEFT", 10, 0)
  label:SetText(labelText)

  local scroll = CreateFrame("ScrollFrame", name, parent, "UIPanelScrollFrameTemplate")
  scroll:SetPoint("TOPLEFT", bar, "BOTTOMLEFT", 10, -8)
  scroll:SetPoint("RIGHT", parent, "RIGHT", -28, 0)
  scroll:SetHeight(height)

  -- Recessed border around the well.
  if NE.nineslice and NE.nineslice.AttachInset then
    pcall(NE.nineslice.AttachInset, scroll, -4, 4, 22, -4)
  end

  -- Modern minimal-scrollbar reskin (same treatment as Roster/Social's list scrollbars).
  scroll.ScrollBar = _G[name .. "ScrollBar"]   -- 3.3.5a template doesn't set the parentKey
  if NE.scrollbar and NE.scrollbar.Reskin then NE.scrollbar.Reskin(scroll) end

  local edit = CreateFrame("EditBox", nil, scroll)
  edit:SetMultiLine(true)
  edit:SetAutoFocus(false)
  edit:SetFontObject("GameFontHighlightSmall")
  -- explicit: scroll:GetWidth() is unresolved (0) at construction time, so derive from the parent
  -- panel's own explicit width instead (InfoFrame is now a narrow 25%-width column, not full-width).
  edit:SetWidth(math.max(150, (parent:GetWidth() or 900) - 50))
  edit:SetJustifyH("LEFT")
  edit:SetTextInsets(4, 4, 4, 4)
  edit:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
  edit:SetScript("OnEditFocusLost", function(self)
    if self._dirty and commitFn then commitFn(self:GetText() or "") end
    self._dirty = false
  end)
  edit:SetScript("OnTextChanged", function(self, userInput) if userInput then self._dirty = true end end)
  scroll:SetScrollChild(edit)

  -- Click anywhere in the well to start editing, not just on the text itself. As a scroll child the
  -- EditBox is only as tall as the text it holds, so every empty row below the last line was dead
  -- space that swallowed clicks. Routing the scroll frame's clicks into the box covers the whole well
  -- without giving the box a fixed height, which would fight the multiline auto-grow the scrolling
  -- depends on. Guarded on enabled state so a read-only well still refuses focus.
  scroll:EnableMouse(true)
  scroll:SetScript("OnMouseDown", function()
    if edit.IsEnabled and not edit:IsEnabled() then return end
    edit:SetFocus()
  end)

  return { label = label, scroll = scroll, edit = edit, canEditFn = canEditFn }
end

function G.SetupInfo(f)
  local panel = f.InfoFrame
  if not panel or panel._built then return end
  panel._built = true

  -- Parchment background (classic GuildInfo look) behind both wells.
  local parch = panel:CreateTexture(nil, "BACKGROUND")
  parch:SetTexture(GUILDFRAME)
  parch:SetTexCoord(0, 0.3154296875, 0, 0.595703125)
  parch:SetPoint("TOPLEFT", panel, "TOPLEFT", 0, 0)
  parch:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", 0, 0)
  parch:SetVertexColor(1, 1, 1, 0.4)

  -- Single full-width column. The reference frame puts "Guild News" in a right-hand column, but
  -- guild news is a Cataclysm system — phantom on 3.3.5a — so it stays CUT (consistent with the
  -- WotLK-real scope), and MOTD + Guild Information take the whole panel instead.
  panel.MOTD = buildWell(panel, "NE_GuildMOTDScroll", GUILD_MOTD or "Guild Message Of The Day", -6, 70,
    function(text) if GuildSetMOTD then GuildSetMOTD(text) end end,
    function() return CanEditMOTD and CanEditMOTD() end)

  panel.Info = buildWell(panel, "NE_GuildInfoScroll", GUILD_INFORMATION or "Guild Information", -114, 300,
    function(text) if SetGuildInfoText then SetGuildInfoText(text) end end,
    function() return CanEditGuildInfo and CanEditGuildInfo() end)
end

-- Apply edit permission to a well, but ONLY on an actual change of state.
--
-- EditBox:SetEnabled is a ClassicAPI shim (!!!ClassicAPI/Util/WidgetAPI.lua) and its Enable() path
-- ends in ClearFocus(). RefreshInfo runs on every GUILD_ROSTER_UPDATE — and this window requests a
-- fresh roster whenever it opens — so re-applying "enabled" unconditionally tore the cursor out of
-- the box mid-sentence and the well read as uneditable. Guarding on change means Enable() fires once,
-- before anyone is typing, instead of on every roster tick.
--
-- Enable() also swaps the font object to GameFontWhite, so the well's own font has to be re-applied
-- after it or the text silently changes size.
local function applyEditable(well, canEdit)
  local want = canEdit and true or false
  if well._editable == want then return end
  well._editable = want

  local edit = well.edit
  if edit.SetEnabled then edit:SetEnabled(want)
  elseif want then edit:Enable()
  else edit:Disable() end

  edit:SetFontObject("GameFontHighlightSmall")
  edit:SetTextColor(1, 1, 1)
end

function G.RefreshInfo()
  local f = G.frame
  local panel = f and f.InfoFrame
  if not (panel and panel._built) then return end

  if panel.MOTD then
    local motd = (GetGuildRosterMOTD and GetGuildRosterMOTD()) or ""
    if not panel.MOTD.edit:HasFocus() then panel.MOTD.edit:SetText(motd) end
    applyEditable(panel.MOTD, panel.MOTD.canEditFn and panel.MOTD.canEditFn())
  end
  if panel.Info then
    local info = (GetGuildInfoText and GetGuildInfoText()) or ""
    if not panel.Info.edit:HasFocus() then panel.Info.edit:SetText(info) end
    applyEditable(panel.Info, panel.Info.canEditFn and panel.Info.canEditFn())
  end
end

local ev = CreateFrame("Frame")
ev:RegisterEvent("GUILD_MOTD")
ev:RegisterEvent("GUILD_ROSTER_UPDATE")
ev:SetScript("OnEvent", function() if G.RefreshInfo then G.RefreshInfo() end end)
