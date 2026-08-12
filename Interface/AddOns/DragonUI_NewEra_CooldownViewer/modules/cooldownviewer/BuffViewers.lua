-- DragonUI_NewEra/modules/cooldownviewer/BuffViewers.lua — the two AURA-driven viewers.
--
-- DOWNPORT of the BuffIcon/BuffBar half of NewEra/CooldownViewer/CooldownViewer.lua plus their XML
-- templates (Phase 3). As in Phase 1, frames are built in Lua rather than porting the XML:
-- MaskTexture is a Legion widget absent here, and GridLayoutFrame is supplied by core/GridLayout.lua.
--
-- These differ from Essential/Utility in kind, not just degree. Those read SPELL COOLDOWNS from a
-- curated per-class list. These read LIVE AURAS: any player buff inside the auto-track window
-- (<= M.BUFF_TRACK_MAX_DURATION), plus explicitly assigned auras from the tracked-aura pool, plus
-- tracked DoTs on the current target. So they need no class data at all — which is why Phase 3 does
-- not depend on the Phase 2 WotLK spell tables.
--
-- !! THE ARG-SHIFT TRAP: the 1.15 source scans with
--      local name, icon, count, _, duration, expiration, _, _, _, spellID = UnitBuff("player", i)
-- which is the MODERN return layout. On 3.3.5a `rank` sits at index 2, shifting everything after
-- it by one — ported verbatim, `icon` would receive the rank string and `duration` the caster.
-- All scanning here goes through NE.aura (core/AuraSnapshot.lua), which owns that correction and
-- also collapses the repeated per-frame walks into one.

local NE = DragonUI_NewEra
local M  = NE.cooldownviewer
local BaseViewerMixin = M.BaseViewerMixin

local QUESTION_MARK = "Interface\\Icons\\INV_Misc_QuestionMark"

-- ── Item construction ───────────────────────────────────────────────────────────────────────────

-- BuffIcon tile: 40x40 (vs Essential 50, Utility 30), overlay inset -8/+7.
local function createBuffIconItem(parent)
  local item = CreateFrame("Frame", nil, parent)
  item:SetSize(40, 40)
  item:EnableMouse(true)

  item.Icon = item:CreateTexture(nil, "ARTWORK")
  -- The mask's inset, which is what fits the icon inside the overlay's border — see
  -- M.AnchorMaskedIcon in ItemMixins.lua.
  M.AnchorMaskedIcon(item.Icon, item, 40)

  item.IconOverlay = item:CreateTexture(nil, "OVERLAY")
  item.IconOverlay:SetPoint("TOPLEFT", item, "TOPLEFT", -8, 7)
  item.IconOverlay:SetPoint("BOTTOMRIGHT", item, "BOTTOMRIGHT", 8, -7)
  M.BuildFrameStack(item, 8, 7)

  item.Cooldown = CreateFrame("Cooldown", nil, item)
  -- Icon rect, not the tile: the sweep would otherwise overhang the icon by the mask inset. See
  -- M.AnchorMaskedIcon.
  M.AnchorMaskedIcon(item.Cooldown, item, 40)

  -- Stack count.
  item.Applications = CreateFrame("Frame", nil, item)
  item.Applications:SetAllPoints(item)
  item.Applications.Text = item.Applications:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
  item.Applications.Text:SetPoint("BOTTOMRIGHT", item, "BOTTOMRIGHT", -2, 2)
  item.Applications.Text:Hide()

  -- Dispel-coloured border, shown only for tracked DEBUFFS.
  item.DebuffBorder = CreateFrame("Frame", nil, item)
  item.DebuffBorder:SetPoint("TOPLEFT", item, "TOPLEFT", -3, 3)
  item.DebuffBorder:SetPoint("BOTTOMRIGHT", item, "BOTTOMRIGHT", 3, -3)
  item.DebuffBorder.Texture = item.DebuffBorder:CreateTexture(nil, "OVERLAY")
  item.DebuffBorder.Texture:SetAllPoints(item.DebuffBorder)
  item.DebuffBorder:Hide()

  item.cooldownFont = NE.cd.FONT.viewerAura
  item.includeAsLayoutChildWhenHidden = true
  item.allowHideWhenInactive = true     -- XML KeyValue: BuffIcon honours HideWhenInactive

  for k, v in pairs(NE_CooldownViewerAuraItemMixin) do item[k] = v end
  item:SetScript("OnEnter", item.OnEnter)
  item:SetScript("OnLeave", item.OnLeave)
  item:OnLoad()
  return item
end

-- BuffBar row: 220x30 — a 30x30 icon on the left, a 19px-tall StatusBar filling the rest.
local function createBuffBarItem(parent)
  local item = CreateFrame("Frame", nil, parent)
  item:SetSize(220, 30)
  item:EnableMouse(true)

  local icon = CreateFrame("Frame", nil, item)
  icon:SetSize(30, 30)
  icon:SetPoint("LEFT", item, "LEFT", 0, 0)
  icon.Icon = icon:CreateTexture(nil, "ARTWORK")
  M.AnchorMaskedIcon(icon.Icon, icon, 30)
  icon.IconOverlay = icon:CreateTexture(nil, "OVERLAY")
  icon.IconOverlay:SetPoint("TOPLEFT", icon, "TOPLEFT", -6, 5)
  icon.IconOverlay:SetPoint("BOTTOMRIGHT", icon, "BOTTOMRIGHT", 6, -5)
  M.BuildFrameStack(icon, 6, 5)
  icon.Applications = icon:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmall")
  icon.Applications:SetPoint("BOTTOMRIGHT", icon, "BOTTOMRIGHT", -5, 5)
  icon.Applications:SetJustifyH("RIGHT")
  icon.Applications:Hide()
  item.Icon = icon

  local bar = CreateFrame("StatusBar", nil, item)
  bar:SetHeight(19)
  bar:SetPoint("LEFT", icon, "RIGHT", 2, 0)
  bar:SetPoint("RIGHT", item, "RIGHT", 0, 0)
  bar:SetMinMaxValues(0, 1)
  bar:SetValue(0)
  -- Retail's -2/+2, +4/-7 anchors live inside BuildBarBG: the group owns its own rect because the
  -- cap widths are derived from it.
  bar.BarBG = M.BuildBarBG(bar)
  bar.Pip = bar:CreateTexture(nil, "OVERLAY")
  bar.Name = bar:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
  bar.Name:SetPoint("TOPLEFT", bar, "TOPLEFT", 5, 0)
  bar.Name:SetPoint("BOTTOMRIGHT", bar, "BOTTOMRIGHT", -25, 0)
  bar.Name:SetJustifyH("LEFT")
  bar.Name:SetJustifyV("MIDDLE")
  bar.Duration = bar:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
  bar.Duration:SetPoint("RIGHT", bar, "RIGHT", -8, 0)
  bar.Duration:SetJustifyH("LEFT")
  item.Bar = bar

  item.DebuffBorder = CreateFrame("Frame", nil, item)
  item.DebuffBorder:SetPoint("TOPLEFT", icon, "TOPLEFT", -3, 3)
  item.DebuffBorder:SetPoint("BOTTOMRIGHT", icon, "BOTTOMRIGHT", 3, -3)
  item.DebuffBorder.Texture = item.DebuffBorder:CreateTexture(nil, "OVERLAY")
  item.DebuffBorder.Texture:SetAllPoints(item.DebuffBorder)
  item.DebuffBorder:Hide()

  item.includeAsLayoutChildWhenHidden = true
  item.allowHideWhenInactive = true

  for k, v in pairs(NE_CooldownViewerBuffBarItemMixin) do item[k] = v end
  item:SetScript("OnEnter", item.OnEnter)
  item:SetScript("OnLeave", item.OnLeave)
  item:OnLoad()
  return item
end

local ITEM_FACTORY = {
  buffIcon = createBuffIconItem,
  buffBar  = createBuffBarItem,
}

-- ── Shared aura-scan rebuild ────────────────────────────────────────────────────────────────────

-- Both viewers run the identical scan and differ only in presentation, so it lives here once.
-- Returns the number of items populated.
local function rebuildFromAuras(self)
  local category = self.category
  local include, exclude = M.GetBuffOverrides(category)
  local factory = ITEM_FACTORY[category]
  local n = 0
  local shownNames = {}

  local function acquire()
    n = n + 1
    local item = self.items[n]
    if not item then
      item = factory(self)
      item.viewerFrame = self
      self.items[n] = item
    end
    item.layoutIndex = n
    item.ignoreInLayout = false
    return item
  end

  -- Player self-buffs. DOWNPORT: via NE.aura, not a raw UnitBuff loop — see the arg-shift note in
  -- the file header.
  local snap = NE.aura and NE.aura.GetSnapshot("player", "HELPFUL")
  if snap then
    for i = 1, snap.n do
      local row = snap.list[i]
      -- Record it BEFORE deciding whether to show it. This is the whole of Phase 7a's write path:
      -- the picker's Tracked Buffs/Bars/Not Displayed sections are fed from here, and recording
      -- after the decision would mean hiding an aura also removed the row that could unhide it.
      if M.NoteSeenAura then
        M.NoteSeenAura(row.spellID, row.name, row.icon, row.duration)
      end
      if M.ShouldTrackBuff(row.spellID, row.duration, include, exclude, category, row.name) then
        local item = acquire()
        item:SetAura(row.name, row.icon, row.count, row.duration, row.expiration, row.spellID)
        item:Show()
        shownNames[row.name] = true
      end
    end
  end

  -- Tracked DoTs on the target (explicit assignments only, never the auto window).
  for _, a in ipairs(M.ScanTargetTrackedAuras(include, shownNames)) do
    local item = acquire()
    item:SetAura(a.name, a.icon, a.count, a.duration, a.expiration, a.spellID)
    item:Show()
  end

  -- Retire the extra slots. Clearing _auraActive AND the spell identity is REQUIRED, not just
  -- Hide(): the RefreshLayout below runs SetHideWhenInactive -> UpdateShownState on every item,
  -- which re-shows any slot whose cached _auraActive is still true (duplicate bars when a buff
  -- falls off) or — with HideWhenInactive off — any slot still holding a spellID (a permanent
  -- empty bar).
  for i = n + 1, #self.items do
    local it = self.items[i]
    it._auraActive     = false
    it._editPreview    = false
    it._auraExpiration = nil
    it._auraDuration   = nil
    it.spellID         = nil
    it.spellName       = nil
    it.ignoreInLayout  = true
    it:Hide()
  end
  return n
end

-- Re-layout only when the visible COUNT changes. UNIT_AURA fires constantly in combat; when the
-- set is stable the bars' own OnUpdate already animates them and SetAura refreshed durations, so
-- skipping Layout avoids a combat hitch. A same-count swap reuses the slot in place.
local function rebuildAndMaybeLayout(self)
  local n = rebuildFromAuras(self)
  if n ~= self._lastShownCount then
    self._lastShownCount = n
    self:RefreshLayout()
  end
end

-- Contained rebuild: the aura viewers call Rebuild directly from their hottest path (UNIT_AURA), so
-- an error here would otherwise spam every aura tick in combat.
local function safeRebuild(self)
  local ok, err = pcall(self.Rebuild, self)
  if not ok and NE.Log then
    NE.Log("CDM", "buff viewer '" .. tostring(self.category) .. "' rebuild error: " .. tostring(err))
  end
end

-- Shared event surface for both aura viewers: aura churn on player/target, plus the base's
-- visibility/level events.
local function auraViewerOnLoad(self)
  self.items = {}
  self:RegisterEvent("PLAYER_ENTERING_WORLD")
  -- player + target ONLY, engine-side. An unfiltered UNIT_AURA delivers every raid/party/nameplate
  -- unit's churn to the handler, per plate per tick in big pulls.
  self:RegisterUnitEvent("UNIT_AURA", "player", "target")
  self:RegisterEvent("SPELLS_CHANGED")
  self:RegisterEvent(NE.EV_LEARNED_SPELL)
  self:RegisterEvent("PLAYER_LEVEL_UP")
  -- Dual spec: aura assignments live in the per-talent-group layout bucket too.
  self:RegisterEvent("ACTIVE_TALENT_GROUP_CHANGED")
  self:RegisterEvent("PLAYER_TALENT_UPDATE")
  self:RegisterEvent("PLAYER_REGEN_DISABLED")
  self:RegisterEvent("PLAYER_REGEN_ENABLED")
  self:RegisterEvent("PLAYER_TARGET_CHANGED")
end

local function auraViewerOnEvent(self, event, ...)
  -- The same master-enable gate BaseViewerMixin:OnEvent carries, repeated because the two hottest
  -- events on this client — UNIT_AURA and PLAYER_TARGET_CHANGED — are answered here and never reach it.
  -- A gate only in the base would have left an off Cooldown Manager rebuilding both aura viewers on
  -- every aura tick, which is the one path where that cost is actually measurable.
  if not M.IsEnabled() then return end
  if event == "UNIT_AURA" then
    local unit = ...
    if unit == "player" or unit == "target" then safeRebuild(self) end
    return
  elseif event == "PLAYER_TARGET_CHANGED" then
    safeRebuild(self)
    return
  end
  BaseViewerMixin.OnEvent(self, event, ...)
end

-- ── BuffIcon viewer ─────────────────────────────────────────────────────────────────────────────

local BuffIconMixin = {}
for k, v in pairs(BaseViewerMixin) do BuffIconMixin[k] = v end
BuffIconMixin.category = "buffIcon"

BuffIconMixin.OnLoad  = auraViewerOnLoad
BuffIconMixin.OnEvent = auraViewerOnEvent
function BuffIconMixin:OnShow() safeRebuild(self) end

-- All icons share ONE row/column, like the bars. The retail preset keeps IconLimit=1 for this
-- viewer, so the BASE GetStride (= iconLimit = 1) would wrap every icon onto its own row —
-- inverting Horizontal into a vertical column. Using the live count lays them out in one row.
function BuffIconMixin:GetStride()
  local c = 0
  for _, it in ipairs(self.items) do
    if it.layoutIndex and not it.ignoreInLayout then c = c + 1 end
  end
  return math.max(c, 1)
end

local BUFFICON_PREVIEW = {
  { "Power Infusion", "Interface\\Icons\\Spell_Holy_PowerInfusion", 15, 11, 10060 },
  { "Berserking",     "Interface\\Icons\\Spell_Nature_BloodLust",   20, 14, 20554 },
  { "Crusader",       "Interface\\Icons\\Spell_Holy_HolySmite",     15,  6, 20007 },
  { "Recklessness",   "Interface\\Icons\\Ability_CriticalStrike",   15,  9, 1719  },
}

local BUFFBAR_PREVIEW = BUFFICON_PREVIEW   -- same archetypes; the bar renders them differently

local function rebuildPreview(self, samples)
  local factory = ITEM_FACTORY[self.category]
  for i, e in ipairs(samples) do
    local item = self.items[i]
    if not item then
      item = factory(self)
      item.viewerFrame = self
      self.items[i] = item
    end
    item.layoutIndex = i
    item.ignoreInLayout = false
    if item.SetPreviewAura then item:SetPreviewAura(e[1], e[2], e[3], e[4], e[5]) end
    item:Show()
  end
  for i = #samples + 1, #self.items do
    local it = self.items[i]
    it._auraActive = false
    it._editPreview = false
    it.ignoreInLayout = true
    it:Hide()
  end
  self._lastShownCount = #samples
  self:RefreshLayout()
end

function BuffIconMixin:Rebuild()
  if self._editPreview then return rebuildPreview(self, BUFFICON_PREVIEW) end
  rebuildAndMaybeLayout(self)
end

-- ── BuffBar viewer ──────────────────────────────────────────────────────────────────────────────

local BuffBarMixin = {}
for k, v in pairs(BaseViewerMixin) do BuffBarMixin[k] = v end
BuffBarMixin.category = "buffBar"
-- Grow upward from the BOTTOM anchor so existing bars stay put as bars are added or removed; new
-- bars stack on top.
BuffBarMixin.growUpward = true

BuffBarMixin.OnLoad  = auraViewerOnLoad
BuffBarMixin.OnEvent = auraViewerOnEvent
function BuffBarMixin:OnShow() safeRebuild(self) end

-- All bars share ONE column. Count what the GRID will lay out (has layoutIndex, not
-- ignoreInLayout) rather than only SHOWN bars: hidden-but-not-retired bars still occupy a cell via
-- includeAsLayoutChildWhenHidden, and counting only shown ones lets stride fall below the
-- layout-child count, wrapping the stack into a phantom second column.
function BuffBarMixin:GetStride()
  local c = 0
  for _, it in ipairs(self.items) do
    if it.layoutIndex and not it.ignoreInLayout then c = c + 1 end
  end
  return math.max(c, 1)
end

-- Bars sit closer together than icons.
function BuffBarMixin:GetAdditionalPaddingOffset() return -2 end

function BuffBarMixin:SetBarContent(content)
  self.barContent = content
  for _, item in ipairs(self.items) do
    if item.SetBarContent then item:SetBarContent(content) end
  end
end

function BuffBarMixin:SetBarWidthScale(percent)
  self.barWidthScale = (percent or 100) / 100
  for _, item in ipairs(self.items) do
    if item.SetBarWidthScale then item:SetBarWidthScale(self.barWidthScale) end
  end
end

-- Bar content/width must land BEFORE the base call: the base runs Layout(), and item frames are
-- plain Frames whose width changes don't re-dirty the grid — applying width afterwards leaves the
-- frame size stale until the next relayout.
function BuffBarMixin:RefreshLayout()
  self:SetBarContent(self:GetCategoryOpt("barContent"))
  self:SetBarWidthScale(self:GetCategoryOpt("barWidthScale"))
  BaseViewerMixin.RefreshLayout(self)
end

function BuffBarMixin:Rebuild()
  if self._editPreview then return rebuildPreview(self, BUFFBAR_PREVIEW) end
  rebuildAndMaybeLayout(self)
end

-- ── Frame construction ──────────────────────────────────────────────────────────────────────────

local VIEWER_MIXIN = { buffIcon = BuffIconMixin, buffBar = BuffBarMixin }
local VIEWER_GLOBAL = {
  buffIcon = "DragonUI_NewEra_BuffIconCooldownViewer",
  buffBar  = "DragonUI_NewEra_BuffBarCooldownViewer",
}

function M.CreateBuffViewer(category)
  if M.viewers[category] then return M.viewers[category] end
  local mixin = VIEWER_MIXIN[category]
  if not mixin then return nil end

  local frame = CreateFrame("Frame", VIEWER_GLOBAL[category], UIParent)
  frame.category = category
  frame:SetSize(1, 1)
  frame:SetPoint("BOTTOM", UIParent, "BOTTOM",
                 category == "buffBar" and 420 or 0,
                 M.VIEWER_DEFAULT_Y[category] or 370)
  frame:Hide()

  NE.gridlayout.Apply(frame)
  for k, v in pairs(mixin) do frame[k] = v end

  frame:SetScript("OnEvent", frame.OnEvent)
  frame:SetScript("OnShow", frame.OnShow)
  frame:OnLoad()

  M.RegisterViewer(category, frame)
  return frame
end
