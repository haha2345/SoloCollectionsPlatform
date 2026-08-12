-- DragonUI_NewEra/modules/cooldownviewer/Viewers.lua — frame construction + the viewer mixin.
--
-- DOWNPORT of NewEra/CooldownViewer/CooldownViewer.xml (templates) and the BaseViewerMixin half of
-- CooldownViewer.lua. The XML is NOT ported; the frames are built in Lua instead. Two reasons, both
-- hard blockers rather than preferences:
--
--   1. <MaskTexture> — a Legion widget. It does not exist on 3.3.5a, cannot be polyfilled, and an
--      unrecognised XML node risks failing the parse of the WHOLE file, taking every template with
--      it. CONTRACTS §0 lists SetMask as a hard rule.
--   2. inherits="GridLayoutFrame" — retail FrameXML's layout template. Absent here; core/GridLayout.lua
--      provides the same surface as a Lua mixin, applied at creation.
--
-- Geometry is transcribed from the source XML so the tiles keep retail's proportions:
--   Essential 50x50, IconOverlay inset -9/+8, GameFontHighlightHugeOutline-class number font
--   Utility   30x30, IconOverlay inset -6/+5, smaller number font
--
-- PHASE 1: Essential + Utility only.

local NE = DragonUI_NewEra
local M  = NE.cooldownviewer

-- ── Item tile construction ──────────────────────────────────────────────────────────────────────

local ITEM_SPEC = {
  essential = {
    size = 50,
    overlayInset = { 9, 8 },          -- TOPLEFT -9,+8 / BOTTOMRIGHT +9,-8
    cooldownFont = NE.cd.FONT.viewerEssential,
  },
  utility = {
    size = 30,
    overlayInset = { 6, 5 },
    cooldownFont = NE.cd.FONT.viewerUtility,
  },
}

local function createItem(parent, category)
  local spec = ITEM_SPEC[category] or ITEM_SPEC.essential
  local item = CreateFrame("Frame", nil, parent)
  item:SetSize(spec.size, spec.size)

  -- Tooltips need mouse input. Retail's tiles are mouse-enabled for exactly this.
  item:EnableMouse(true)

  item.Icon = item:CreateTexture(nil, "ARTWORK")

  -- DOWNPORT: the source anchors this with setAllPoints and masks it with a MaskTexture. The mask is
  -- unavailable, but it was doing two jobs and one of them is reproducible: it inset the icon by 3/64
  -- of the tile before rounding it. M.AnchorMaskedIcon applies that inset, which is what puts the
  -- icon's edge under the IconOverlay's border line instead of out past it. See the derivation there.
  -- The rounding itself is still gone; CropIcon (ItemMixins.applyItemAtlases) trims the baked border.
  M.AnchorMaskedIcon(item.Icon, item, spec.size)
  item.IconOverlay = item:CreateTexture(nil, "OVERLAY")
  local ox, oy = spec.overlayInset[1], spec.overlayInset[2]
  item.IconOverlay:SetPoint("TOPLEFT", item, "TOPLEFT", -ox, oy)
  item.IconOverlay:SetPoint("BOTTOMRIGHT", item, "BOTTOMRIGHT", ox, -oy)
  -- The frame art peaks at 42% black, which reads as a bevel rather than a border. Extra copies in
  -- the same rect deepen it; M.GetFrameStrength decides how many are shown.
  M.BuildFrameStack(item, ox, oy)

  -- DOWNPORT: the three regions below are `setAllPoints` on the TILE upstream, and are anchored to the
  -- ICON's rect here. Retail can use the tile because its swipe, shadow and flash are rounded art cut
  -- to the masked icon; ours are the engine's plain sweep, a flat shade and a square-ish sprite, so at
  -- tile size each one draws proud of the icon and re-advertises the old, larger footprint. That was
  -- visible the moment the frame art shipped: the swipe "sits at the old icon size".
  item.OutOfRange = item:CreateTexture(nil, "OVERLAY")
  M.AnchorMaskedIcon(item.OutOfRange, item, spec.size)
  item.OutOfRange:SetVertexColor(1, 1, 1, 0.5)
  item.OutOfRange:Hide()

  item.Cooldown = CreateFrame("Cooldown", nil, item)
  M.AnchorMaskedIcon(item.Cooldown, item, spec.size)
  -- DOWNPORT: the XML attaches <SwipeTexture>/<EdgeTexture> here. 3.3.5a's Cooldown has no
  -- SetSwipeTexture/SetEdgeTexture, so we take the engine's built-in sweep (PORT_PLAN §C3).

  item.CooldownFlash = CreateFrame("Frame", nil, item)
  M.AnchorMaskedIcon(item.CooldownFlash, item, spec.size)
  -- Above the Cooldown swipe: the ready burst plays as the swipe finishes, and would otherwise be
  -- competing with it for the same draw layer.
  item.CooldownFlash:SetFrameLevel((item.Cooldown:GetFrameLevel() or 1) + 2)
  item.CooldownFlash:Hide()
  item.CooldownFlash.Flipbook = item.CooldownFlash:CreateTexture(nil, "ARTWORK")
  item.CooldownFlash.Flipbook:SetAllPoints(item.CooldownFlash)
  item.CooldownFlash.Flipbook:SetAlpha(0)

  -- DOWNPORT (§H.2 8c): retail marks a spell whose own buff is up by tinting its swipe gold, and
  -- SetSwipeColor is WoD+. The substitute is a gold halo. Built LAST and hosted in its own frame so
  -- it can outrank the Cooldown — see M.BuildBuffGlow for why a draw layer could never do it.
  item.BuffGlow = M.BuildBuffGlow(item, spec.size)

  -- XML KeyValues.
  item.cooldownFont = spec.cooldownFont
  item.includeAsLayoutChildWhenHidden = true
  -- Essential/Utility templates do not set allowHideWhenInactive, so their items always show.
  item.allowHideWhenInactive = M.PER_FRAME_DEFAULT_OVERRIDES[M.FRAME_ID[category]]
    and M.PER_FRAME_DEFAULT_OVERRIDES[M.FRAME_ID[category]].allowHideWhenInactive or false

  -- Apply the mixin, then run the XML <OnLoad>.
  for k, v in pairs(NE_CooldownViewerItemMixin) do item[k] = v end
  item:SetScript("OnEnter", item.OnEnter)
  item:SetScript("OnLeave", item.OnLeave)
  item:OnLoad()

  return item
end

-- ── Viewer mixin ────────────────────────────────────────────────────────────────────────────────

local BaseViewerMixin = {}
M.BaseViewerMixin = BaseViewerMixin

function BaseViewerMixin:GetCategoryFrameID() return M.FRAME_ID[self.category] end
function BaseViewerMixin:GetCategoryOpt(key)
  return M.GetOpt(self:GetCategoryFrameID(), key)
end

function BaseViewerMixin:OnLoad()
  self.items = {}
  self:RegisterEvent("PLAYER_ENTERING_WORLD")
  self:RegisterEvent("SPELL_UPDATE_COOLDOWN")
  self:RegisterEvent("SPELLS_CHANGED")
  self:RegisterEvent(NE.EV_LEARNED_SPELL)
  self:RegisterEvent("PLAYER_LEVEL_UP")
  -- Dual spec: the layout, the curated list and the talent gate all change on a group swap.
  self:RegisterEvent("ACTIVE_TALENT_GROUP_CHANGED")
  self:RegisterEvent("PLAYER_TALENT_UPDATE")
  -- For VisibleSetting = In Combat.
  self:RegisterEvent("PLAYER_REGEN_DISABLED")
  self:RegisterEvent("PLAYER_REGEN_ENABLED")
  -- Cast end signals — re-evaluate so the cast-lockout filter clears and items return to their
  -- real-CD state.
  self:RegisterUnitEvent("UNIT_SPELLCAST_STOP", "player")
  self:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player")
  self:RegisterUnitEvent("UNIT_SPELLCAST_CHANNEL_STOP", "player")
  self:RegisterUnitEvent("UNIT_SPELLCAST_INTERRUPTED", "player")
  -- Aura transitions, for the aura-precedence path in RefreshCooldown.
  self:RegisterUnitEvent("UNIT_AURA", "player")
  -- Live totem timers (Shaman).
  self:RegisterEvent("PLAYER_TOTEM_UPDATE")
  -- Target change flips spell range/usability -> recolour icons.
  self:RegisterEvent("PLAYER_TARGET_CHANGED")
  -- Item cooldown ticks + async icon resolve.
  self:RegisterEvent("BAG_UPDATE_COOLDOWN")
  self:RegisterEvent("GET_ITEM_INFO_RECEIVED")
  -- Trinket swaps change the discovered equip set, so they need a full Rebuild, not a refresh.
  self:RegisterUnitEvent("UNIT_INVENTORY_CHANGED", "player")
end

function BaseViewerMixin:OnShow()
  self:Rebuild()
end

function BaseViewerMixin:RefreshAllItems()
  for _, item in ipairs(self.items) do
    if item:IsShown() or item.hideWhenInactive then item:RefreshCooldown() end
  end
end

-- Coalesce a burst of high-frequency refresh events to ONE pass per viewer per frame. During aura
-- bursts UNIT_AURA(player) can fire many times in a single frame, and each viewer would otherwise
-- re-loop ALL its items on every fire. A dirty flag + one deferred pass collapses that —
-- coalesced, never dropped.
function BaseViewerMixin:QueueRefreshAll()
  if self._refreshQueued then return end
  self._refreshQueued = true
  C_Timer.After(0, function()
    self._refreshQueued = false
    self:RefreshAllItems()
  end)
end

function BaseViewerMixin:HandleEvent(event, ...)
  -- Dual spec. Three separate things go stale at once here: the layout bucket the lists come from
  -- (per talent group since the per-spec change), the cached curated list, and the talent gate. None
  -- of the events already handled below fires on a group swap, which is why abilities from the old
  -- spec sat in the window looking castable until the player happened to drag one — any interaction
  -- that rebuilt the viewer hid the fault, and nothing else did.
  if event == "ACTIVE_TALENT_GROUP_CHANGED" or event == "PLAYER_TALENT_UPDATE" then
    if M.InvalidateCuratedCache then M.InvalidateCuratedCache() end
    if M.InvalidateTalentCache then M.InvalidateTalentCache() end
    self:Rebuild()
    return
  end

  if event == "PLAYER_ENTERING_WORLD"
     or event == "SPELLS_CHANGED"
     or event == NE.EV_LEARNED_SPELL
     or event == "PLAYER_LEVEL_UP"
     or event == "UNIT_INVENTORY_CHANGED" then
    self:Rebuild()
  elseif event == "SPELL_UPDATE_COOLDOWN"
     or event == "BAG_UPDATE_COOLDOWN"
     or event == "PLAYER_TOTEM_UPDATE"
     or event == "UNIT_SPELLCAST_STOP"
     or event == "UNIT_SPELLCAST_SUCCEEDED"
     or event == "UNIT_SPELLCAST_CHANNEL_STOP"
     or event == "UNIT_SPELLCAST_INTERRUPTED"
     or event == "UNIT_AURA"
     or event == "PLAYER_TARGET_CHANGED" then
    self:QueueRefreshAll()
  elseif event == "GET_ITEM_INFO_RECEIVED" then
    local itemID = ...
    for _, item in ipairs(self.items) do
      if item._iconItemID and (itemID == nil or item._iconItemID == itemID) then item:RefreshIcon() end
    end
  elseif event == "PLAYER_REGEN_DISABLED" or event == "PLAYER_REGEN_ENABLED" then
    self:UpdateVisibility()
  end
end

-- Fail-safe: this event path touches live cooldown/aura/inventory reads, and a single bad read must
-- never error in combat. Contain it, and capture the site to NE.Log so it stays diagnosable.
--
-- AND: nothing to update while the module is off, which is now the DEFAULT (see M.IsEnabled). Without
-- this gate every player who never turns the Cooldown Manager on still pays for SPELL_UPDATE_COOLDOWN,
-- UNIT_AURA, BAG_UPDATE_COOLDOWN and the rest for the whole session, re-reading cooldowns to repaint
-- tiles that are not on screen. Registration is left alone rather than deferred: these are frame
-- events, and unregistering four frames' worth on a toggle is more moving parts than one early return.
--
-- SAFE TO DROP rather than queue. Switching on runs through UpdateVisibility, whose Show fires OnShow,
-- and OnShow is Rebuild — so the catch-up is a full re-read from scratch, the same one a viewer gets
-- when its category is re-enabled. Deliberately NOT gated on IsShown(): a viewer hidden by its own
-- category or by "In Combat" still has to track state, or it would come back wrong.
function BaseViewerMixin:OnEvent(event, ...)
  if not M.IsEnabled() then return end
  local ok, err = pcall(self.HandleEvent, self, event, ...)
  if not ok and NE.Log then
    NE.Log("CDM", "viewer event '" .. tostring(event) .. "' error: " .. tostring(err))
  end
end

function BaseViewerMixin:GetClassSpellList(includeUnlearned)
  return M.GetActiveSpellList(self.category, includeUnlearned)
end

-- ── Settings application ────────────────────────────────────────────────────────────────────────

function BaseViewerMixin:SetOrientation(v)
  self.orientationSetting = v
  self.isHorizontal = (v ~= "vertical")
end

function BaseViewerMixin:SetIconLimit(v)
  self.iconLimit = v
  self.stride = v
end

function BaseViewerMixin:GetStride()
  return self.iconLimit or 1
end

function BaseViewerMixin:SetIconDirection(v)
  self.iconDirection = v
end

function BaseViewerMixin:SetIconSize(percent)
  self.iconScale = (percent or 100) / 100
end

-- Retail offsets the configured padding by a fixed negative amount so icons sit closer; the slider
-- max was bumped to compensate. At the default padding 2 this yields -2 (icons overlap slightly),
-- matching retail's tighter rows.
function BaseViewerMixin:GetAdditionalPaddingOffset()
  return -4
end

function BaseViewerMixin:SetIconPadding(px)
  self.iconPadding = px or 2
  local pad = self.iconPadding + self:GetAdditionalPaddingOffset()
  self.childXPadding = pad
  self.childYPadding = pad
end

function BaseViewerMixin:SetOpacity(percent)
  self.opacity = (percent or 100) / 100
  self:SetAlpha(self.opacity)
end

function BaseViewerMixin:SetVisibleSetting(v)
  self.visibleSetting = v
  self:UpdateVisibility()
end

function BaseViewerMixin:SetHideWhenInactive(hide)
  self.hideWhenInactive = hide
  for _, item in ipairs(self.items) do item:SetHideWhenInactive(hide) end
end

function BaseViewerMixin:SetTimerShown(shown)
  self.timerShown = shown
  for _, item in ipairs(self.items) do item:SetTimerShown(shown) end
end

function BaseViewerMixin:SetTooltipsShown(shown)
  self.tooltipsShown = shown
  for _, item in ipairs(self.items) do item:SetTooltipsShown(shown) end
end

function BaseViewerMixin:UpdateVisibility()
  if not M.IsEnabled() then self:Hide(); return end
  if not M.IsCategoryEnabled(self.category) then self:Hide(); return end
  local mode = self.visibleSetting or M.DEFAULTS.visibleSetting
  if mode == "hidden" then
    self:Hide()
  elseif mode == "incombat" then
    if InCombatLockdown() then self:Show() else self:Hide() end
  else
    self:Show()
  end
end

function BaseViewerMixin:RefreshLayout()
  self:SetOrientation(self:GetCategoryOpt("orientation"))
  self:SetIconLimit(self:GetCategoryOpt("iconLimit"))
  self:SetIconDirection(self:GetCategoryOpt("iconDirection"))
  self:SetIconSize(self:GetCategoryOpt("iconSize"))
  self:SetIconPadding(self:GetCategoryOpt("iconPadding"))
  self:SetOpacity(self:GetCategoryOpt("opacity"))
  self:SetVisibleSetting(self:GetCategoryOpt("visibleSetting"))
  self:SetHideWhenInactive(self:GetCategoryOpt("hideWhenInactive"))
  self:SetTimerShown(self:GetCategoryOpt("showTimer"))
  self:SetTooltipsShown(self:GetCategoryOpt("showTooltips"))

  local scale = self.iconScale or 1.0
  for _, item in ipairs(self.items) do
    item:SetScale(scale)
  end

  -- Vertical: stride is items per column. Horizontal: items per row. (Retail CooldownViewer.lua
  -- RefreshLayout.)
  self.layoutFramesGoingRight = (not self.isHorizontal) or (self.iconDirection == "right")
  self.layoutFramesGoingUp = self.growUpward or ((not self.isHorizontal) and (self.iconDirection == "right"))
  self.alwaysUpdateLayout = true
  -- A trailing short row centres under the full rows above it rather than hugging the start edge:
  -- 12 essential icons at an icon limit of 9 lay out as 9 + a centred 3.
  self.centerPartialLines = true
  -- Set stride AFTER SetIconLimit (which defaults it to iconLimit) so a per-viewer GetStride
  -- override takes effect.
  self.stride = self:GetStride()

  if self.Layout then self:Layout() end
end

-- ── Rebuild ─────────────────────────────────────────────────────────────────────────────────────

function BaseViewerMixin:Rebuild()
  -- Re-entrancy guard. Rebuild ends in RefreshLayout, which calls SetVisibleSetting ->
  -- UpdateVisibility -> Show(); if the viewer was hidden, that Show fires OnShow, whose handler is
  -- Rebuild. The client only fires OnShow on a hidden->shown TRANSITION so it would settle at depth
  -- two, but depending on that is fragile (and a stubbed harness recurses forever). Guarding is
  -- cheap and makes the cycle structurally impossible.
  if self._rebuilding then return end
  self._rebuilding = true

  local ok, err = pcall(self.RebuildInner, self)
  self._rebuilding = false
  if not ok then
    if NE.Log then NE.Log("CDM", "rebuild failed for '" .. tostring(self.category) .. "': " .. tostring(err)) end
  end
end

function BaseViewerMixin:RebuildInner()
  local list = self:GetClassSpellList(self._editPreview)
  local visible = 0

  for _, spellID in ipairs(list) do
    -- DOWNPORT: the source gates each entry again here with IsPlayerSpell, which 3.3.5a does not
    -- have. It is redundant anyway — GetActiveSpellList has already applied the learn-gate
    -- (M.IsTrackable) to this list, and user-added on-use items are deliberately exempt from it
    -- because their use-spell is never a "known" player spell. All that is left to verify is that
    -- the ID resolves to a real spell, so a bad curated entry can't create a broken tile.
    if GetSpellInfo(spellID) ~= nil then
      visible = visible + 1
      local item = self.items[visible]
      if not item then
        item = createItem(self, self.category)
        item.viewerFrame = self
        self.items[visible] = item
      end
      item.layoutIndex = visible
      item.ignoreInLayout = false
      item._editPreview = self._editPreview and true or false
      item:SetSpell(spellID)
      item:Show()
    end
  end

  -- Equip items assigned to this viewer. PHASE 1: GetEquipItemsForCategory returns empty, so this
  -- is a no-op; the loop is kept so Phase 2's CooldownViewerEquip port is a drop-in.
  if not self._editPreview then
    for _, e in ipairs(M.GetEquipItemsForCategory(self.category)) do
      visible = visible + 1
      local item = self.items[visible]
      if not item then
        item = createItem(self, self.category)
        item.viewerFrame = self
        self.items[visible] = item
      end
      item.layoutIndex    = visible
      item.ignoreInLayout = false
      item._editPreview   = false
      if e.source == "trinket" then
        item:SetEquipSlot(e.slot, e.itemID, e.spellID)
      else
        item:SetBagItem(e.itemID, e.spellID)
      end
      item:Show()
    end
  end

  -- Retire unused slots. Clearing spellID is REQUIRED, not just Hide(): RefreshLayout runs
  -- UpdateShownState on every item, and Essential/Utility items ALWAYS show while they still hold a
  -- spellID — so a leftover tile would be re-shown.
  for i = visible + 1, #self.items do
    local it = self.items[i]
    it._editPreview = false
    it.spellID      = nil
    it.spellName    = nil
    it._equipSlot   = nil
    it._bagItemID   = nil
    it._itemCDID    = nil
    it._iconItemID  = nil
    it.ignoreInLayout = true
    -- The glow is driven from RefreshCooldown, which returns early without a spellID — so a recycled
    -- tile would keep the previous spell's gold border the next time it is shown.
    if it.SetBuffGlow then it:SetBuffGlow(false) end
    -- Same for an alert FX, and for the same reason. The 5Hz ticker does clear a retired tile on its
    -- next pass, but "next pass" is up to 200ms of the old spell's pandemic ring on the new one.
    if M.alerts and M.alerts.ClearFX then M.alerts.ClearFX(it) end
    it:Hide()
  end

  self:RefreshLayout()

  -- Edit-mode safety net: a viewer with nothing to show collapses to 1x1 (GridLayout refuses a
  -- zero size), which leaves no grab target in the editor. A Death Knight hits this on both
  -- viewers today, since the WotLK data is Phase 2. Give the frame a placeholder footprint so it
  -- can still be positioned.
  if self._editPreview and visible == 0 then
    local tile = (ITEM_SPEC[self.category] or ITEM_SPEC.essential).size
    self:SetSize(tile * 4, tile)
  end
end

-- ── Frame construction ──────────────────────────────────────────────────────────────────────────

local VIEWER_GLOBAL = {
  essential = "DragonUI_NewEra_EssentialCooldownViewer",
  utility   = "DragonUI_NewEra_UtilityCooldownViewer",
}

-- Build one viewer frame. Named globally so DragonUI's MoversSystem (which persists by frame) and
-- the QA harness can find it.
function M.CreateViewer(category)
  if M.viewers[category] then return M.viewers[category] end

  local frame = CreateFrame("Frame", VIEWER_GLOBAL[category], UIParent)
  frame.category = category
  frame:SetSize(1, 1)
  frame:SetPoint("BOTTOM", UIParent, "BOTTOM", 0, M.VIEWER_DEFAULT_Y[category] or 300)
  frame:Hide()

  NE.gridlayout.Apply(frame)
  for k, v in pairs(BaseViewerMixin) do frame[k] = v end

  frame:SetScript("OnEvent", frame.OnEvent)
  frame:SetScript("OnShow", frame.OnShow)
  frame:OnLoad()

  M.RegisterViewer(category, frame)
  return frame
end
