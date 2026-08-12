-- DragonUI_NewEra/modules/cooldownviewer/AuraItemMixins.lua — the per-item layer for the two
-- AURA-driven viewers: NE_CooldownViewerAuraItemMixin (BuffIcon tile) and
-- NE_CooldownViewerBuffBarItemMixin (BuffBar row).
--
-- DOWNPORT of the aura half of NewEra/CooldownViewer/ItemMixins.lua (Phase 3). The cooldown item
-- lives in ItemMixins.lua; these two track AURAS instead, so they differ in:
--   * the Cooldown runs in REVERSE (XML reverse="true") — the swipe shows aura time elapsed
--   * an Applications stack-count label instead of ChargeCount
--   * no ready flash and no desaturation (the icon stays bright while the aura is up)
--   * the BuffBar renders a StatusBar that depletes, driven by a per-frame OnUpdate
--
-- DEVIATIONS from the 1.15 source, all forced by the 3.3.5a surface (same set as ItemMixins.lua):
-- MaskTexture removed, SetSwipeTexture/SetSwipeColor dropped or guarded, SetShown replaced with
-- Show/Hide, GameTooltip:SetSpellByID falls back to the spell hyperlink.

local NE = DragonUI_NewEra
NE.cooldownviewer = NE.cooldownviewer or {}
local M = NE.cooldownviewer

-- DOWNPORT: SetShown does not exist on 3.3.5a (CONTRACTS §0).
local function setShown(region, shown)
  if not region then return end
  if shown then region:Show() else region:Hide() end
end

-- Dispel border for aura items. Retail shows the modern debuff-border glow only when the tracked
-- aura is HARMFUL (a player debuff), hidden for buffs. Routes through the shared NE.tex helper.
local function refreshAuraDebuffBorder(item, isHarmful, debuffType)
  local db = item and item.DebuffBorder
  if not db then return end
  if isHarmful and db.Texture and NE.tex and NE.tex.DispelBorder then
    NE.tex.DispelBorder(db.Texture, debuffType, false)
    db:Show()
  else
    db:Hide()
  end
end
M.RefreshAuraDebuffBorder = refreshAuraDebuffBorder

local QUESTION_MARK = "Interface\\Icons\\INV_Misc_QuestionMark"

-- Per-spell settings (alert, ready sound) are stored under the id the PICKER ROW carries, which for
-- a ranked buff is not the id the aura scan hands this item. Shared by both mixins, and memoized per
-- binding: the ticker asks 5x a second, and M.SettingsKeyForAura walks the candidate pool.
--
-- The spell items' own GetSettingsKey (ItemMixins.lua) exists for the same reason one rung along —
-- there it is the trained rank vs the listed rank. Same fault, same shape, different table.
local function auraSettingsKey(self)
  local sid = self.spellID
  if not sid then return nil end
  if self._settingsKeyFor ~= sid then
    self._settingsKeyFor = sid
    self._settingsKey    = M.SettingsKeyForAura and M.SettingsKeyForAura(sid, self.spellName) or sid
  end
  return self._settingsKey
end

-- ════════════════════════════════════════════════════════════════════════════════════════════════
-- BuffIcon tile
-- ════════════════════════════════════════════════════════════════════════════════════════════════

NE_CooldownViewerAuraItemMixin = {}
local AuraItem = NE_CooldownViewerAuraItemMixin

function AuraItem:OnLoad()
  if NE.tex and NE.tex.SetAtlas then
    if self.IconOverlay then NE.tex.SetAtlas(self.IconOverlay, "UI-HUD-CoolDownManager-IconOverlay", false) end
  end
  M.CropIcon(self.Icon)

  NE.cd.ApplyNumbers(self.Cooldown, {
    font = self.cooldownFont or NE.cd.FONT.viewerAura,
  })
  -- REVERSE: the swipe fills as the aura elapses rather than emptying like a cooldown.
  if self.Cooldown and self.Cooldown.SetReverse then self.Cooldown:SetReverse(true) end
end

function AuraItem:SetSpell(spellID)
  self.spellID = spellID
  local name, _, icon = GetSpellInfo(spellID)
  self.spellName = name
  if self.Icon then self.Icon:SetTexture(icon or QUESTION_MARK) end
  self:RefreshAura()
end

function AuraItem:SetTimerShown(shown)
  self.timerShown = shown
  NE.cd.ApplyNumbers(self.Cooldown, { show = shown })
end

function AuraItem:SetTooltipsShown(shown)
  self.tooltipsShown = shown
end

function AuraItem:SetHideWhenInactive(hide)
  self.hideWhenInactive = hide
  self:UpdateShownState()
end

function AuraItem:UpdateShownState()
  if not self.spellID then self:Hide(); return end
  if self._editPreview then self:Show(); return end
  if not self.hideWhenInactive then self:Show(); return end
  if self._auraActive then self:Show() else self:Hide() end
end

-- Refresh from the player's aura matching this item's spell NAME, via the shared one-frame
-- snapshot. Name matching (not spellID) is what lets a down-ranked buff still resolve.
function AuraItem:RefreshAura()
  if not self.spellName then return end
  local aura = M.findPlayerAuraDataByName(self.spellName)
  self._auraActive = aura ~= nil
  refreshAuraDebuffBorder(self, aura and aura.isHarmful, aura and aura.debuffType)

  if aura then
    if aura.duration and aura.duration > 0 and aura.expirationTime and aura.expirationTime > 0 and self.Cooldown then
      CooldownFrame_Set(self.Cooldown, aura.expirationTime - aura.duration, aura.duration, 1)
    elseif self.Cooldown then
      CooldownFrame_Clear(self.Cooldown)
    end
    if self.Applications and self.Applications.Text then
      if aura.count and aura.count > 1 then
        self.Applications.Text:SetText(tostring(aura.count))
        self.Applications.Text:Show()
      else
        self.Applications.Text:Hide()
      end
    end
  else
    if self.Cooldown then CooldownFrame_Clear(self.Cooldown) end
    if self.Applications and self.Applications.Text then self.Applications.Text:Hide() end
  end

  if self.hideWhenInactive then self:UpdateShownState() end
end

function AuraItem:GetSettingsKey() return auraSettingsKey(self) end

-- Forwarding alias so the shared viewer dispatch can call one method name on either item type.
function AuraItem:RefreshCooldown() self:RefreshAura() end

-- Populate directly from a scanned aura (the auto-track path). No curated spellID needed, so
-- trinket/potion/proc buffs render without being enumerable in advance.
function AuraItem:SetAura(name, icon, count, duration, expiration, spellID)
  self._editPreview = false
  self.spellID, self.spellName = spellID, name
  self._auraActive = true
  refreshAuraDebuffBorder(self, false)
  if self.Icon then self.Icon:SetTexture(icon or QUESTION_MARK) end
  if self.Cooldown then
    if duration and duration > 0 and expiration and expiration > 0 then
      CooldownFrame_Set(self.Cooldown, expiration - duration, duration, 1)
    else
      CooldownFrame_Clear(self.Cooldown)
    end
  end
  if self.Applications and self.Applications.Text then
    if count and count > 1 then
      self.Applications.Text:SetText(tostring(count)); self.Applications.Text:Show()
    else
      self.Applications.Text:Hide()
    end
  end
end

function AuraItem:SetPreviewAura(name, icon, duration, remaining, spellID)
  self:SetAura(name, icon, nil, duration, GetTime() + (remaining or duration or 0), spellID)
  self._editPreview = true
end

function AuraItem:OnEnter()
  if not self.spellID then return end
  if self.tooltipsShown == false then return end
  GameTooltip:SetOwner(self, "ANCHOR_TOP")
  -- Named: an aura id this client cannot hyperlink would otherwise show an EMPTY tooltip. See
  -- M.TooltipSetSpellNamed in ItemMixins.lua.
  if M.TooltipSetSpellNamed(GameTooltip, self.spellID, self.spellName) then GameTooltip:Show() end
end

function AuraItem:OnLeave() GameTooltip:Hide() end

-- ════════════════════════════════════════════════════════════════════════════════════════════════
-- BuffBar row
-- ════════════════════════════════════════════════════════════════════════════════════════════════

NE_CooldownViewerBuffBarItemMixin = {}
local BarItem = NE_CooldownViewerBuffBarItemMixin

-- Only animate while an aura (or edit preview) is cached. The inactive state is painted ONCE at
-- the transition — without this gate the OnUpdate re-cleared the same idle bar 60x/sec.
local function buffBarOnUpdate(self)
  if self._auraExpiration then self:RefreshCooldownInfo() end
end

function BarItem:OnLoad()
  local set = NE.tex and NE.tex.SetAtlas
  if set and self.Icon and self.Icon.IconOverlay then
    set(self.Icon.IconOverlay, "UI-HUD-CoolDownManager-IconOverlay", false)
  end
  M.CropIcon(self.Icon and self.Icon.Icon)

  if self.Bar then
    if NE.tex and NE.tex.SetAtlasOnStatusBar then
      NE.tex.SetAtlasOnStatusBar(self.Bar, "UI-HUD-CoolDownManager-Bar")
    end
    self.Bar:SetStatusBarColor(1.0, 0.5, 0.25)   -- retail's BuffBar orange
    -- BarBG is a 3-slice group, not a texture — it textures its own pieces in BuildBarBG (§H.2.9).
    if self.Bar.BarBG and M.ApplyBarBGAtlas then M.ApplyBarBGAtlas(self.Bar.BarBG) end
    if set and self.Bar.Pip then set(self.Bar.Pip, "UI-HUD-CoolDownManager-Bar-Pip", true) end
    -- Pip rides the fill texture's right edge so it slides left as the bar depletes.
    if self.Bar.Pip and self.Bar.GetStatusBarTexture then
      local fillTex = self.Bar:GetStatusBarTexture()
      if fillTex then
        self.Bar.Pip:ClearAllPoints()
        self.Bar.Pip:SetPoint("CENTER", fillTex, "RIGHT", 0, -1)
      end
    end
  end

  self.baseWidth = self:GetWidth()
  self:SetScript("OnUpdate", buffBarOnUpdate)
end

function BarItem:SetSpell(spellID)
  self.spellID = spellID
  local name, _, icon = GetSpellInfo(spellID)
  self.spellName = name
  if self.Icon and self.Icon.Icon then self.Icon.Icon:SetTexture(icon or QUESTION_MARK) end
  if self.Bar and self.Bar.Name then self.Bar.Name:SetText(name or "?") end
  self:RefreshAura()
end

function BarItem:SetAura(name, icon, count, duration, expiration, spellID)
  self._editPreview    = false
  self.spellID         = spellID
  self.spellName       = name
  self._auraExpiration = expiration
  self._auraDuration   = duration
  self._auraCount      = count
  self._auraActive     = true
  refreshAuraDebuffBorder(self, false)
  if self.Icon and self.Icon.Icon then self.Icon.Icon:SetTexture(icon or QUESTION_MARK) end
  if self.Bar and self.Bar.Name then self.Bar.Name:SetText(name or "?") end
  if self.Icon and self.Icon.Applications then
    if count and count > 1 then
      self.Icon.Applications:SetText(tostring(count)); self.Icon.Applications:Show()
    else
      self.Icon.Applications:Hide()
    end
  end
  self:RefreshCooldownInfo()
end

function BarItem:SetTimerShown(shown)
  self.timerShown = shown
  setShown(self.Bar and self.Bar.Duration, shown)
end

function BarItem:SetTooltipsShown(shown) self.tooltipsShown = shown end

function BarItem:SetHideWhenInactive(hide)
  self.hideWhenInactive = hide
  self:UpdateShownState()
end

function BarItem:UpdateShownState()
  -- ignoreInLayout must MIRROR visibility here: the grid counts hidden children too
  -- (includeAsLayoutChildWhenHidden), so a bar hidden without the flag desyncs GetStride from the
  -- layout-child set and wraps the stack into a phantom extra column.
  local show
  if not self.spellID then show = false
  elseif not self.hideWhenInactive then show = true
  else show = self._auraActive and true or false end
  self.ignoreInLayout = not show
  setShown(self, show)
end

function BarItem:SetBarContent(content)
  self.barContent = content
  setShown(self.Icon, content ~= "nameOnly")
  setShown(self.Bar and self.Bar.Name, content ~= "iconOnly")
end

function BarItem:SetBarWidthScale(scale)
  self.barWidthScale = scale
  local base = self.baseWidth or 220
  self:SetWidth(base * (scale or 1.0))
end

-- Capture the active aura's (expiration, duration) on UNIT_AURA so the OnUpdate can poll cheaply
-- without re-scanning auras every frame.
function BarItem:RefreshAura()
  if self._editPreview then return end
  if not self.spellName then return end
  local aura = M.findPlayerAuraDataByName(self.spellName)
  if aura and aura.expirationTime > GetTime() then
    self._auraExpiration = aura.expirationTime
    self._auraDuration   = aura.duration
    self._auraCount      = aura.count
    self._auraActive     = true
    refreshAuraDebuffBorder(self, aura.isHarmful, aura.debuffType)
  else
    self._auraExpiration = nil
    self._auraDuration   = nil
    self._auraCount      = nil
    self._auraActive     = false
    refreshAuraDebuffBorder(self, false)
  end
  if self.Icon and self.Icon.Applications then
    if self._auraActive and self._auraCount and self._auraCount > 1 then
      self.Icon.Applications:SetText(tostring(self._auraCount))
      self.Icon.Applications:Show()
    else
      self.Icon.Applications:Hide()
    end
  end
  self:RefreshCooldownInfo()
  if self.hideWhenInactive then self:UpdateShownState() end
end

function BarItem:SetPreviewAura(name, icon, duration, remaining, spellID)
  self._editPreview     = true
  self._previewDuration = duration
  self.spellID          = spellID
  self.spellName        = name
  self._auraDuration    = duration
  self._auraExpiration  = GetTime() + (remaining or duration)
  self._auraActive      = true
  refreshAuraDebuffBorder(self, false)
  if self.Icon and self.Icon.Icon then self.Icon.Icon:SetTexture(icon or QUESTION_MARK) end
  if self.Bar and self.Bar.Name then self.Bar.Name:SetText(name or "?") end
  if self.Icon and self.Icon.Applications then self.Icon.Applications:Hide() end
  self:RefreshCooldownInfo()
end

-- Called every frame by OnUpdate AND on UNIT_AURA via RefreshAura.
function BarItem:RefreshCooldownInfo()
  if not self.Bar then return end
  local exp, dur = self._auraExpiration, self._auraDuration
  if not (exp and dur and dur > 0) then
    self.Bar:SetMinMaxValues(0, 1)
    self.Bar:SetValue(0)
    if self.Bar.Duration then self.Bar.Duration:SetText(""); self._lastDurTenth = nil end
    setShown(self.Bar.Pip, false)
    return
  end

  local currentTime = exp - GetTime()
  if currentTime <= 0 then
    if self._editPreview then
      -- Loop the preview so it stays animated while the editor is open.
      self._auraExpiration = GetTime() + (self._previewDuration or dur)
      currentTime = self._auraExpiration - GetTime()
    else
      self._auraExpiration = nil
      self._auraDuration   = nil
      self._auraActive     = false
      self.Bar:SetValue(0)
      if self.Bar.Duration then self.Bar.Duration:SetText(""); self._lastDurTenth = nil end
      setShown(self.Bar.Pip, false)
      if self.hideWhenInactive then self:UpdateShownState() end
      return
    end
  end

  self.Bar:SetMinMaxValues(0, dur)
  self.Bar:SetValue(currentTime)
  if self.Bar.Duration and self.Bar.Duration:IsShown() then
    -- Re-format only when the displayed tenth changes: this runs per frame per active bar, and an
    -- unconditional format+SetText allocates a fresh string at 60 Hz.
    local tenth = math.floor(currentTime * 10)
    if tenth ~= self._lastDurTenth then
      self._lastDurTenth = tenth
      self.Bar.Duration:SetText(string.format(COOLDOWN_DURATION_SEC or "%.1f", currentTime))
    end
  end
  setShown(self.Bar.Pip, true)
end

function BarItem:GetSettingsKey() return auraSettingsKey(self) end

function BarItem:RefreshCooldown() self:RefreshAura() end

function BarItem:OnEnter()
  if not self.spellID then return end
  if self.tooltipsShown == false then return end
  GameTooltip:SetOwner(self, "ANCHOR_TOP")
  if M.TooltipSetSpellNamed(GameTooltip, self.spellID, self.spellName) then GameTooltip:Show() end
end

function BarItem:OnLeave() GameTooltip:Hide() end
