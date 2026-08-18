-- DragonUI_NewEra/modules/cooldownviewer/SettingsCategories.lua — the collapsible category sections
-- inside the /cdm panel's scroll body. Downport of NewEra/CooldownViewerSettings/Categories.lua.
--
-- Each category is a header over a grid: icon categories are a 7-wide grid of 38x38 tiles (8px pad,
-- so 46px pitch), the bar category a single column of 317x38 rows (10px pad, 48px pitch). Those
-- numbers are upstream's, probe-confirmed against retail, and are kept exactly.
--
-- DOWNPORT: upstream builds its header with NE.listheader.Build, a Core helper this addon does not
-- have. Built inline here instead — the same substitution modules/character/Reputation.lua made for
-- the same missing helper, using the client's own +/- buttons for the collapse affordance.
--
-- Phase 4b-2 rendered and tooltipped. 4b-3 made the tiles live: right-click routes to
-- CDS.OnItemClick, and the alert badge / tooltip extras come from SettingsMenu.lua. Both are
-- called through CDS with a nil-guard, so this file stays loadable on its own.

local NE = DragonUI_NewEra
local M  = NE.cooldownviewer

local CDS = NE.cooldownviewersettings
local Adapter = CDS.adapter

local ICON, PAD = 38, 8
local PITCH  = ICON + PAD          -- 46
local STRIDE = 7
local CAT_W  = 344
local CAT_GAP = 18
local CONTAINER_X, CONTAINER_Y = 13, -15
local HEADER_H = 26
local BAR_W, BAR_H, BAR_PITCH = 317, 38, 48

local QUESTION_MARK = "Interface\\Icons\\INV_Misc_QuestionMark"

-- ── Item tiles ──────────────────────────────────────────────────────────────────────────────────

-- Unlearned entries read as unavailable. Since §H.3.21 they are only ever LISTED with Show Unlearned
-- on, so this tint is that setting's whole visual payload rather than a permanent fixture of the
-- catalog — which is what it had degenerated into.
--
-- Asked through IsSpellLearned rather than IsTrackable for the reason SettingsAdapter's catalog gate
-- gives: IsTrackable waves through every id outside the curated tables, so on a picker row it says
-- "learned" for most of the arsenal and the tint lands on an arbitrary subset.
local function applyLearnedTint(item)
  local known = (not M.IsSpellLearned) or M.IsSpellLearned(item.spellID)
  item._unlearned = not known
  if item._unlearned then
    item.Icon:SetDesaturated(true)
    item.Icon:SetVertexColor(1.0, 0.4, 0.4)
  else
    item.Icon:SetDesaturated(false)
    item.Icon:SetVertexColor(1, 1, 1)
  end
end

-- Tiles are POOLED and never destroyed, so a tile that held a trinket last rebuild can be handed a
-- plain spell this one. Every equip field has to be dropped on that transition or the stale token
-- keeps routing the row's right-click and drag through the equip path — which would silently
-- reassign a trinket the player is no longer even looking at.
local function clearEquipBinding(item)
  item.token, item._iconItemID, item._equipHidden = nil, nil, nil
  item._aura = nil
end

-- Shared by both tile shapes: an equip row shows the real ITEM icon (async — nil until the server
-- caches it, re-pulled on GET_ITEM_INFO_RECEIVED), never a learn tint (you either have the trinket
-- equipped or it is not in the list at all), and greys when the player has hidden it.
--
-- The label is the use-spell's name, which is what a 38px tile can actually carry.
local function setEquipEntry(self, entry)
  self._aura        = nil     -- pooled tiles: see clearEquipBinding
  self.spellID      = entry.spellID
  self.token        = entry.token
  self._iconItemID  = entry.itemID
  self._equipHidden = entry.hidden and true or false
  self._unlearned   = false

  self.spellName = entry.label or (entry.spellID and GetSpellInfo(entry.spellID)) or ""
  local icon = (M.ResolveItemIcon and M.ResolveItemIcon(entry.itemID))
    or (entry.spellID and select(3, GetSpellInfo(entry.spellID)))
  self.Icon:SetTexture(icon or QUESTION_MARK)
  self.Icon:SetDesaturated(self._equipHidden)
  self.Icon:SetVertexColor(1, 1, 1)
  if self.Label then self.Label:SetText(self.spellName) end
  if CDS._applyAlertBadge then CDS._applyAlertBadge(self) end
end

-- An aura row (Phase 7b). Three states worth telling apart on sight, because each answers a
-- different question the player is asking:
--
--   assigned    you put it here                                        plain
--   auto        the viewer is deciding this one — drag it to take over  desaturated
--   untalented  a spec-gated catalog row, visible only via Show Unlearned   red, like a spell you
--                                                                          have not learned
--
-- The icon comes from the entry rather than GetSpellInfo, because the seen registry stores one: an
-- aura this client only ever hands us as an aura may have no spellbook entry to look up.
local function setAuraEntry(self, entry)
  clearEquipBinding(self)
  self._aura      = entry
  self.spellID    = entry.spellID
  self.spellName  = entry.label or ""
  self._unlearned = entry.untalented and true or false

  self.Icon:SetTexture(entry.icon or QUESTION_MARK)
  if entry.untalented then
    self.Icon:SetDesaturated(true)
    self.Icon:SetVertexColor(1.0, 0.4, 0.4)
  else
    self.Icon:SetDesaturated(entry.auto and true or false)
    self.Icon:SetVertexColor(1, 1, 1)
  end
  if self.Label then
    self.Label:SetText(self.spellName ~= "" and self.spellName
      or ("Aura " .. tostring(entry.spellID or "?")))
  end
  if CDS._applyAlertBadge then CDS._applyAlertBadge(self) end
end

local function itemOnEnter(self)
  if not (self.spellID or self.token) then return end
  GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
  -- An equip row shows the ITEM tooltip: for a trinket that is the on-use text plus the equip
  -- bonuses, which is what the player is choosing between. The use-spell tooltip alone would drop
  -- the half of the trinket that is not the cooldown.
  if self._iconItemID and GameTooltip.SetItemByID then
    GameTooltip:SetItemByID(self._iconItemID)
  elseif self._iconItemID and GameTooltip.SetHyperlink then
    GameTooltip:SetHyperlink("item:" .. self._iconItemID)
  elseif M.TooltipSetSpellNamed then
    -- NAMED, because this is the surface where the failure hurts most: a 38px grid tile has no
    -- label of its own, so a tooltip the client could not fill leaves the row unidentifiable. Most
    -- of the catalog's aura ids cannot be hyperlinked on 3.3.5a.
    M.TooltipSetSpellNamed(GameTooltip, self.spellID, self.spellName)
  end
  if self._unlearned then
    -- For an aura the gate is a talent, not a level, so say which one. "Not yet learned" on a proc
    -- you cannot ever learn without respeccing tells the player nothing they can act on.
    if self._aura and self._aura.talent then
      GameTooltip:AddLine("Requires the " .. self._aura.talent .. " talent", 1, 0.3, 0.3)
    else
      GameTooltip:AddLine("Not yet learned", 1, 0.3, 0.3)
    end
  end
  if self._aura then
    if self._aura.dur then
      GameTooltip:AddLine(("Lasts %s sec"):format(tostring(self._aura.dur)), 0.7, 0.7, 0.7)
    end
    if self._aura.auto then
      GameTooltip:AddLine("Tracked automatically. Drag it into a section to pin it there.",
        0.6, 0.8, 1)
    end
  end
  if self.token then
    GameTooltip:AddLine(self._equipHidden and "Not displayed on any viewer"
      or "Drag onto Essential or Utility to track it.", 0.6, 0.8, 1)
  end
  -- What the corner badge means for this tile. Provided by SettingsMenu (4b-3).
  if CDS._itemTooltipExtra then CDS._itemTooltipExtra(self, GameTooltip) end
  GameTooltip:Show()
end

local function itemOnLeave() GameTooltip:Hide() end

local function itemOnClick(self, button)
  if CDS.OnItemClick then CDS.OnItemClick(self, button) end
end

local function wireItem(b)
  b:SetScript("OnEnter", itemOnEnter)
  b:SetScript("OnLeave", itemOnLeave)
  b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
  b:SetScript("OnClick", itemOnClick)
  -- Left-drag is retail's primary way to reorder and reassign; the right-click menu is the
  -- keyboard-free alternative. SettingsReorder (4b-4) provides BeginDrag.
  b:RegisterForDrag("LeftButton")
  b:SetScript("OnDragStart", function(self)
    if CDS.BeginDrag then CDS.BeginDrag(self) end
  end)
end

local function makeIconItem(parent)
  local b = CreateFrame("Button", nil, parent)
  b:SetSize(ICON, ICON)

  b.Icon = b:CreateTexture(nil, "ARTWORK")
  b.Icon:SetAllPoints()
  b.Icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)   -- same crop the live viewer uses

  local hl = b:CreateTexture(nil, "HIGHLIGHT")
  hl:SetAllPoints()
  hl:SetTexture("Interface\\Buttons\\ButtonHilight-Square")
  hl:SetBlendMode("ADD")

  function b:SetSpell(spellID)
    clearEquipBinding(self)
    self.spellID = spellID
    local name, _, icon = GetSpellInfo(spellID)
    self.spellName = name
    self.Icon:SetTexture(icon or QUESTION_MARK)
    applyLearnedTint(self)
    if CDS._applyAlertBadge then CDS._applyAlertBadge(self) end
  end

  b.SetEquipEntry = setEquipEntry
  b.SetAuraEntry  = setAuraEntry

  wireItem(b)
  return b
end

local function makeBarItem(parent)
  local b = CreateFrame("Button", nil, parent)
  b:SetSize(BAR_W, BAR_H)

  local bg = b:CreateTexture(nil, "BACKGROUND")
  bg:SetAllPoints()
  bg:SetTexture(0, 0, 0, 0.35)

  b.Icon = b:CreateTexture(nil, "ARTWORK")
  b.Icon:SetSize(BAR_H - 4, BAR_H - 4)
  b.Icon:SetPoint("LEFT", b, "LEFT", 2, 0)
  b.Icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)

  b.Label = b:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  b.Label:SetPoint("LEFT", b.Icon, "RIGHT", 8, 0)
  b.Label:SetPoint("RIGHT", b, "RIGHT", -6, 0)
  b.Label:SetJustifyH("LEFT")

  -- A WIDE-ROW highlight, not the square one the icon tiles use. ButtonHilight-Square is a 64x64
  -- glow drawn for a square button, and stretching it across a 344px row smears it into the
  -- lopsided blue wash that was reported — bright over the icon, bleeding away to the right.
  -- UI-QuestTitleHighlight is built to stretch horizontally, and is what every other wide list row
  -- in this addon uses (character Sidebar, EquipmentManagerPane, TitlesPane), at the same alpha.
  local hl = b:CreateTexture(nil, "HIGHLIGHT")
  hl:SetAllPoints()
  hl:SetTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight")
  hl:SetBlendMode("ADD")
  hl:SetAlpha(0.4)

  function b:SetSpell(spellID)
    clearEquipBinding(self)
    self.spellID = spellID
    local name, _, icon = GetSpellInfo(spellID)
    self.spellName = name
    self.Icon:SetTexture(icon or QUESTION_MARK)
    self.Label:SetText(name or ("Spell " .. tostring(spellID)))
    applyLearnedTint(self)
    if CDS._applyAlertBadge then CDS._applyAlertBadge(self) end
  end

  b.SetEquipEntry = setEquipEntry
  b.SetAuraEntry  = setAuraEntry

  wireItem(b)
  return b
end

-- ── Category section ────────────────────────────────────────────────────────────────────────────

-- Inline collapsible header. NE.listheader does not exist here; this is the same substitution
-- modules/character/Reputation.lua makes, with the client's own +/- collapse buttons.
local function makeHeader(parent, onToggle)
  local h = CreateFrame("Button", nil, parent)
  h:SetHeight(HEADER_H)

  local bg = h:CreateTexture(nil, "BACKGROUND")
  bg:SetAllPoints()
  bg:SetTexture(1, 1, 1, 0.06)

  h.Toggle = h:CreateTexture(nil, "ARTWORK")
  h.Toggle:SetSize(16, 16)
  h.Toggle:SetPoint("LEFT", h, "LEFT", 4, 0)

  h.Text = h:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  h.Text:SetPoint("LEFT", h.Toggle, "RIGHT", 4, 0)

  h.Count = h:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  h.Count:SetPoint("RIGHT", h, "RIGHT", -6, 0)

  h:SetScript("OnClick", onToggle)

  function h:SetExpanded(on)
    self.Toggle:SetTexture(on and "Interface\\Buttons\\UI-MinusButton-Up"
                              or  "Interface\\Buttons\\UI-PlusButton-Up")
  end
  return h
end

local function makeCategory(parent, kind)
  local c = CreateFrame("Frame", nil, parent)
  c:SetWidth(CAT_W)
  c.kind = kind
  c._factory = (kind == "bar") and makeBarItem or makeIconItem
  c.items = {}
  c._expanded = true
  c._count = 0

  c.header = makeHeader(c, function() c:Toggle() end)
  c.header:SetPoint("TOPLEFT")
  c.header:SetPoint("TOPRIGHT")

  c.container = CreateFrame("Frame", nil, c)
  c.container:SetPoint("TOPLEFT", c.header, "BOTTOMLEFT", CONTAINER_X, CONTAINER_Y)
  c.container:SetWidth(kind == "bar" and BAR_W or (STRIDE * PITCH - PAD))

  c.empty = c:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
  c.empty:SetPoint("TOPLEFT", c.container, "TOPLEFT", 2, -2)
  -- Bounded and left-aligned: the empty text is now a sentence rather than "(empty)", and an
  -- unbounded string would run past the panel's right edge instead of wrapping.
  c.empty:SetWidth(CAT_W - 30)
  c.empty:SetJustifyH("LEFT")
  c.empty:SetText("(empty)")
  c.empty:Hide()

  function c:Relayout()
    local n = self._count
    local contH
    if self.kind == "bar" then
      contH = (n > 0) and (n * BAR_PITCH - (BAR_PITCH - BAR_H)) or 0
    else
      local rows = math.ceil(n / STRIDE)
      contH = (rows > 0) and (rows * PITCH - PAD) or 0
    end
    if n == 0 then contH = 14 end
    self.container:SetHeight(math.max(1, contH))

    if self._expanded then self.container:Show() else self.container:Hide() end
    if n == 0 and self._expanded then self.empty:Show() else self.empty:Hide() end

    for i, item in ipairs(self.items) do
      if i <= n and self._expanded then
        item:ClearAllPoints()
        if self.kind == "bar" then
          item:SetPoint("TOPLEFT", self.container, "TOPLEFT", 0, -(i - 1) * BAR_PITCH)
        else
          local col, row = (i - 1) % STRIDE, math.floor((i - 1) / STRIDE)
          item:SetPoint("TOPLEFT", self.container, "TOPLEFT", col * PITCH, -row * PITCH)
        end
        item:Show()
      else
        item:Hide()
      end
    end

    self.header:SetExpanded(self._expanded)
    self:SetHeight(HEADER_H + (self._expanded and (math.abs(CONTAINER_Y) + self.container:GetHeight()) or 0))
  end

  function c:Toggle()
    self._expanded = not self._expanded
    self:Relayout()
    if CDS.RestackCategories then CDS.RestackCategories() end
  end

  -- Fill from a MIXED list: a number is a spellID, a table is an equip entry (see SettingsAdapter's
  -- equipEntry). Tiles are pooled — the pool only ever grows, and surplus tiles are hidden by
  -- Relayout rather than destroyed.
  function c:SetItems(ids)
    self._count = #ids
    for i, id in ipairs(ids) do
      local item = self.items[i]
      if not item then
        item = self._factory(self.container)
        self.items[i] = item
      end
      item._catID = self._catID
      if type(id) == "table" then
        -- Two table shapes now reach here: an aura row (SettingsAdapter's auraRow) and an equip
        -- entry. They are dispatched on a marker field rather than by sniffing for `token`, because
        -- an aura row legitimately has neither a token nor an itemID and would take the equip path.
        if id.aura then item:SetAuraEntry(id) else item:SetEquipEntry(id) end
      else
        item:SetSpell(id)
      end
    end
    self.header.Count:SetText(tostring(#ids))
    self:Relayout()
  end

  return c
end

-- ── Panel wiring ────────────────────────────────────────────────────────────────────────────────

local categories = {}   -- catID -> frame

-- Stack the visible sections top-down and size the scroll child to match, so the scrollbar knows
-- how far it can go.
function CDS.RestackCategories()
  local panel = CDS.panel
  if not panel then return end

  local mode = CDS.GetDisplayMode() or "spells"
  local y = 0
  local prev
  for _, catID in ipairs(Adapter.MODE_ORDER[mode] or {}) do
    local c = categories[catID]
    if c and c._active then
      c:ClearAllPoints()
      if prev then
        c:SetPoint("TOPLEFT", prev, "BOTTOMLEFT", 0, -CAT_GAP)
      else
        c:SetPoint("TOPLEFT", panel.content, "TOPLEFT", 0, 0)
      end
      c:Show()
      y = y + c:GetHeight() + CAT_GAP
      prev = c
    end
  end
  panel.content:SetHeight(math.max(1, y))
end

function CDS.RefreshLayout()
  local panel = CDS.panel
  if not panel then return end

  local _, class = UnitClass("player")
  local mode = CDS.GetDisplayMode() or "spells"

  -- The settings tab is not a grid of anything. Its page is a sibling scroll child owned by
  -- SettingsOptions.lua, so re-reading it is a refresh, not a rebuild — and the panel's event handler
  -- calls this on every SPELL_UPDATE_ICON, which would otherwise deactivate and re-source every
  -- category behind a page the player is not looking at.
  if mode == "settings" then
    if CDS.RefreshSettingsPage then CDS.RefreshSettingsPage() end
    return
  end

  -- Deactivate everything first, so a category that belongs to the other tab can't linger.
  for _, c in pairs(categories) do c._active = false; c:Hide() end

  for _, catID in ipairs(Adapter.MODE_ORDER[mode] or {}) do
    local items = Adapter.GetItems(catID, class)
    -- An EMPTY source pool is skipped outright rather than shown as "(empty)". A player with no
    -- on-use trinket equipped should not be told about a Trinkets section at all — it would read as
    -- a broken feature rather than an absent input. Stored categories still show when empty,
    -- because there an empty list is a state the player put them in.
    if not (Adapter.IsSourcePool and Adapter.IsSourcePool(catID) and #items == 0) then
      local c = categories[catID]
      if not c then
        c = makeCategory(panel.content, Adapter.Kind(catID))
        c._catID = catID
        c.header.Text:SetText(Adapter.Label(catID))
        if Adapter.EmptyText then c.empty:SetText(Adapter.EmptyText(catID)) end
        categories[catID] = c
      end
      c._active = true
      c:SetItems(items)
    end
  end

  CDS.RestackCategories()
  -- Through GetSearchText, never the raw edit box — its idle text is the "Search" placeholder.
  if CDS.ApplyItemFilter and CDS.GetSearchText then CDS.ApplyItemFilter(CDS.GetSearchText()) end
end

-- Search DIMS non-matching tiles rather than reflowing the grid — retail's behaviour, and it keeps
-- an item's position stable while you type.
function CDS.ApplyItemFilter(text)
  text = (text or ""):lower()
  local blank = (text == "")
  for _, c in pairs(categories) do
    if c._active then
      for i, item in ipairs(c.items) do
        if i <= c._count then
          local match = blank or ((item.spellName or ""):lower():find(text, 1, true) ~= nil)
          item:SetAlpha(match and 1 or 0.25)
        end
      end
    end
  end
end

CDS._categories = categories   -- test seam
