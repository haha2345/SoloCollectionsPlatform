-- DragonUI_NewEra/modules/talents/SpecTabs.lua — dual-spec BOTTOM tabs (+ rename cog).
--
-- Two tabs along the bottom of NE_TalentFrame (same DF metal tab art as the spellbook/character
-- panel, via NE.tabs.ReskinClassicTab) switch the VIEWED spec. Behavior owns the data:
--   * T._activeGroup — the live spec (GetActiveTalentGroup); the ONLY editable one.
--   * T._viewGroup   — the spec currently displayed; set here on click.
--
-- Each tab shows the spec NAME: a CUSTOM name (set via the cog button, persisted per-character) or
-- the default "Primary"/"Secondary". The tab auto-sizes to its text. Names are letters-only, capped
-- at 16 chars. Tabs only appear when GetNumTalentGroups() >= 2 (Dual Talent Specialization learned).

local NE = DragonUI_NewEra
local T  = NE.talents or {}
NE.talents = T

-- Triumvirate-only realm gate (mirrors Behavior.lua's; reuses T.IsTriumvirate if it's already set,
-- so this still works regardless of file load order).
local function IsTriumvirate()
  if T.IsTriumvirate then return T.IsTriumvirate() end
  return (GetRealmName and GetRealmName() or "") == "Triumvirate"
end

local MAX_NAME = 16

-- ---- per-character custom names: NE.db.talentSpecNames[charKey][group] = "name" -------------------
local function charKey()
  if NE.CharKey then return NE.CharKey() end
  return (UnitName("player") or "?") .. "-" .. (GetRealmName() or "?")
end
local function customName(group)
  local db = NE.db
  local c = db and db.talentSpecNames and db.talentSpecNames[charKey()]
  return c and c[group]
end
local function setCustomName(group, name)
  local db = NE.db
  if not db then return end
  name = (name or ""):gsub("[^%a ]", "")            -- letters + spaces only
  name = name:gsub("^%s+", ""):gsub("%s+$", "")     -- trim
  if #name > MAX_NAME then name = name:sub(1, MAX_NAME) end
  db.talentSpecNames = db.talentSpecNames or {}
  local key = charKey()
  db.talentSpecNames[key] = db.talentSpecNames[key] or {}
  db.talentSpecNames[key][group] = (name ~= "") and name or nil   -- blank clears -> default
end
local function defaultName(group)
  if group == 1 then return "Primary"
  elseif group == 2 then return "Secondary"
  elseif group == 3 then return "Tertiary"    -- or "Third"
  elseif group == 4 then return "Quaternary"  -- or "Fourth"
  end
  return "Spec " .. group
end
local function specName(group) return customName(group) or defaultName(group) end

-- ---- rename dialog (opened by the cog) ------------------------------------------------------------
StaticPopupDialogs["NE_TALENT_RENAME_SPEC"] = {
  text = "Rename this specialization (letters only, max " .. MAX_NAME .. "):",
  button1 = ACCEPT or "Accept", button2 = CANCEL or "Cancel",
  hasEditBox = 1, maxLetters = MAX_NAME,
  OnShow = function(self)
    local eb = self.editBox or _G[(self:GetName() or "") .. "EditBox"]
    if not eb then return end
    eb:SetText((self.data and self.data.current) or "")
    eb:HighlightText()
    -- strip any non-letter as it's typed/pasted (keeps spaces)
    eb:SetScript("OnTextChanged", function(box)
      local txt = box:GetText()
      local clean = txt:gsub("[^%a ]", "")
      if clean ~= txt then box:SetText(clean) end
    end)
  end,
  OnAccept = function(self)
    local eb = self.editBox or _G[(self:GetName() or "") .. "EditBox"]
    if self.data and self.data.group then
      setCustomName(self.data.group, eb and eb:GetText() or "")
      if T.RefreshSpecTabs then T.RefreshSpecTabs() end
    end
  end,
  EditBoxOnEnterPressed = function(editBox)
    local d = editBox:GetParent()
    if d.data and d.data.group then
      setCustomName(d.data.group, editBox:GetText() or "")
      if T.RefreshSpecTabs then T.RefreshSpecTabs() end
    end
    d:Hide()
  end,
  EditBoxOnEscapePressed = function(editBox) editBox:GetParent():Hide() end,
  timeout = 0, whileDead = 1, hideOnEscape = 1, exclusive = 1,
}

-- ---- selected/deselected tab art (mirrors character/TabButtons setTabArt) --------------------------
local function setTabArt(tab, selected)
  if not tab then return end
  local n = tab:GetName()
  local function set(suffix, show)
    local t = _G[n .. suffix]
    if t then if show then t:Show() else t:Hide() end end
  end
  set("Left",  not selected); set("Middle",  not selected); set("Right",  not selected)
  set("LeftDisabled", selected); set("MiddleDisabled", selected); set("RightDisabled", selected)
  local hl = tab._neCustomHL
  if hl then
    local a = selected and 0 or 0.4
    if hl.left   and hl.left.SetAlpha   then hl.left:SetAlpha(a)   end
    if hl.middle and hl.middle.SetAlpha then hl.middle:SetAlpha(a) end
    if hl.right  and hl.right.SetAlpha  then hl.right:SetAlpha(a)  end
  end
end

local TAB_NAMES = { "NE_TalentSpecTab1", "NE_TalentSpecTab2", "NE_TalentSpecTab3", "NE_TalentSpecTab4" }
local GLYPH_TAB_NAME = "NE_TalentSpecTabGlyphs"
local PET_TAB_NAME   = "NE_TalentSpecTabPet"

local function buildTab(g)
  local f = T.frame
  local name = TAB_NAMES[g]
  local tab = _G[name]
  if tab then return tab end
  local ok, t = pcall(CreateFrame, "Button", name, f, "CharacterFrameTabButtonTemplate")
  if ok and t then tab = t else
    tab = CreateFrame("Button", name, f, "UIPanelButtonTemplate"); tab._nePlain = true
  end
  tab:SetID(g)
  tab:SetScript("OnClick", function(self)
    if PlaySound then pcall(PlaySound, "igCharacterInfoTab") end
    local id = self:GetID()
    T._viewGroup = id
    T._petView = false                        -- a player-spec tab leaves pet view
    if T.GlyphsSetActive then T.GlyphsSetActive(false) end
    if T.GlyphsApplyPaneVisibility then T.GlyphsApplyPaneVisibility() end
  
    -- TRIUMVIRATE COMPATIBILITY: Pass the click to the server's hidden native tab
    if IsTriumvirate() then
      local triumvirateTab = _G["TriumvirateSpecTab" .. id]
      if triumvirateTab and triumvirateTab.Click then
        triumvirateTab:Click()
      end
    end

    if T.RefreshSpecTabs then T.RefreshSpecTabs() end
    if T.Refresh then T.Refresh() end
  end)
  if not tab._nePlain and NE.tabs and NE.tabs.ReskinClassicTab then
    pcall(NE.tabs.ReskinClassicTab, name, {})
  end
  return tab
end

local function buildGlyphTab()
  local f = T.frame
  local name = GLYPH_TAB_NAME
  local tab = _G[name]
  if tab then return tab end
  local ok, t = pcall(CreateFrame, "Button", name, f, "CharacterFrameTabButtonTemplate")
  if ok and t then tab = t else
    tab = CreateFrame("Button", name, f, "UIPanelButtonTemplate"); tab._nePlain = true
  end
  tab:SetScript("OnClick", function()
    if PlaySound then pcall(PlaySound, "igCharacterInfoTab") end
    T._petView = false                       -- glyphs leaves pet view
    if T.GlyphsSetActive then T.GlyphsSetActive(true) end
    if T.GlyphsRefresh then T.GlyphsRefresh() end
    if T.GlyphsApplyPaneVisibility then T.GlyphsApplyPaneVisibility() end
    if T.RefreshSpecTabs then T.RefreshSpecTabs() end
  end)
  if not tab._nePlain and NE.tabs and NE.tabs.ReskinClassicTab then
    pcall(NE.tabs.ReskinClassicTab, name, {})
  end
  return tab
end

-- Pet-talents tab: only present for a hunter with a talented pet out. Switches the window into pet
-- view (the single Ferocity/Tenacity/Cunning tree), leaving glyphs/player-spec views.
local function buildPetTab()
  local f = T.frame
  local name = PET_TAB_NAME
  local tab = _G[name]
  if tab then return tab end
  local ok, t = pcall(CreateFrame, "Button", name, f, "CharacterFrameTabButtonTemplate")
  if ok and t then tab = t else
    tab = CreateFrame("Button", name, f, "UIPanelButtonTemplate"); tab._nePlain = true
  end
  tab:SetScript("OnClick", function()
    if PlaySound then pcall(PlaySound, "igCharacterInfoTab") end
    if T.SetPetView then T.SetPetView(true) else T._petView = true end
    if T.GlyphsSetActive then T.GlyphsSetActive(false) end
    if T.GlyphsApplyPaneVisibility then T.GlyphsApplyPaneVisibility() end
    if T.RefreshSpecTabs then T.RefreshSpecTabs() end
    if T.Refresh then T.Refresh() end
  end)
  if not tab._nePlain and NE.tabs and NE.tabs.ReskinClassicTab then
    pcall(NE.tabs.ReskinClassicTab, name, {})
  end
  return tab
end

-- Rename cog: a gear seated to the right of the tab row; opens the rename dialog for the VIEWED spec.
local function buildCog()
  local f = T.frame
  if T._specCog then return T._specCog end
  local cog = CreateFrame("Button", "NE_TalentSpecCog", f)
  cog:SetSize(18, 18)
  cog.Icon = cog:CreateTexture(nil, "ARTWORK")
  if not (NE.tex and NE.tex.SetAtlas and NE.tex.SetAtlas(cog.Icon, "questlog-icon-setting", true)) then
    cog.Icon:SetTexture("Interface\\Buttons\\UI-OptionsButton"); cog.Icon:SetSize(16, 16)
  end
  cog.Icon:SetPoint("CENTER")
  cog.Hi = cog:CreateTexture(nil, "HIGHLIGHT")
  if not (NE.tex and NE.tex.SetAtlas and NE.tex.SetAtlas(cog.Hi, "questlog-icon-setting", true)) then
    cog.Hi:SetTexture("Interface\\Buttons\\UI-OptionsButton"); cog.Hi:SetSize(16, 16)
  end
  cog.Hi:SetPoint("CENTER"); cog.Hi:SetBlendMode("ADD"); cog.Hi:SetAlpha(0.4)
  cog:SetFrameLevel((f:GetFrameLevel() or 1) + 10)
  -- top-right of the button anchored to the top-right of the talent BACKGROUND (inside the chrome),
  -- with a small buffer so it isn't touching the window border.
  cog:SetPoint("TOPRIGHT", f.bg or f, "TOPRIGHT", -8, -8)
  cog:SetScript("OnClick", function()
    local g = T._viewGroup or 1
    StaticPopup_Show("NE_TALENT_RENAME_SPEC", nil, nil, { group = g, current = customName(g) or "" })
  end)
  cog:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:SetText("Rename specialization", 1, 1, 1)
    GameTooltip:Show()
  end)
  cog:SetScript("OnLeave", function() GameTooltip:Hide() end)
  T._specCog = cog
  return cog
end

-- Build-once + update. Called from Behavior.Populate (and the tabs' own click). No-op with 1 spec.
function T.RefreshSpecTabs()
  local f = T.frame
  if not f then return end
  
  -- Triumvirate bypasses the default Blizzard 2-spec limit (up to 4 specs). Everywhere else, respect
  -- the real GetNumTalentGroups() so we don't show unlock tabs for specs the server doesn't support.
  local num = IsTriumvirate() and 4
    or ((GetNumTalentGroups and (GetNumTalentGroups() or 1)) or 1)
  
  local hasGlyph = (type(T.GlyphsSetActive) == "function")
  local viewG = T._viewGroup or T._activeGroup or 1
  local glyphActive = T.GlyphsIsActive and T.GlyphsIsActive() or false
  local petAvail    = T.PetHasTalents and T.PetHasTalents() or false
  local petActive   = T.PetViewActive and T.PetViewActive() or false
  local needTalentsTab = hasGlyph or petAvail
  local tabsToSize = {}

  -- Loop through all 4 specs instead of stopping at 2
  if num >= 2 then
    for g = 1, num do
      local tab = buildTab(g)
      local txt = _G[TAB_NAMES[g] .. "Text"]
      if txt then txt:SetText(specName(g)) elseif tab.SetText then tab:SetText(specName(g)) end
      tab:Show()
      tabsToSize[#tabsToSize + 1] = TAB_NAMES[g]
    end
  else
    local tab = buildTab(1)
    local txt = _G[TAB_NAMES[1] .. "Text"]
    if needTalentsTab then
      if txt then txt:SetText("Talents") elseif tab.SetText then tab:SetText("Talents") end
      tab:Show()
      tabsToSize[#tabsToSize + 1] = TAB_NAMES[1]
    else
      if txt then txt:SetText(specName(1)) elseif tab.SetText then tab:SetText(specName(1)) end
      tab:Hide()
    end

    for g = 2, 4 do
      local t2 = _G[TAB_NAMES[g]]
      if t2 then t2:Hide() end
    end
  end

  -- Pet tab (between the player-spec tabs and Glyphs)
  if petAvail then
    local ptab = buildPetTab()
    local ptxt = _G[PET_TAB_NAME .. "Text"]
    if ptxt then ptxt:SetText("Pet") elseif ptab.SetText then ptab:SetText("Pet") end
    ptab:Show()
    tabsToSize[#tabsToSize + 1] = PET_TAB_NAME
  else
    local ptab = _G[PET_TAB_NAME]
    if ptab then ptab:Hide() end
  end

  -- Glyph Tab
  if hasGlyph then
    local gtab = buildGlyphTab()
    local gtxt = _G[GLYPH_TAB_NAME .. "Text"]
    if gtxt then gtxt:SetText("Glyphs") elseif gtab.SetText then gtab:SetText("Glyphs") end
    gtab:Show()
    tabsToSize[#tabsToSize + 1] = GLYPH_TAB_NAME
  else
    local gtab = _G[GLYPH_TAB_NAME]
    if gtab then gtab:Hide() end
  end

  if #tabsToSize == 0 then
    if T._specCog then T._specCog:Hide() end
    return
  end

  -- Auto-size and chain all tabs horizontally along the bottom edge
  if NE.tabs and NE.tabs.SizeAndAnchorTabs then
    NE.tabs.SizeAndAnchorTabs(f, tabsToSize, { startX = 14, startY = 0, parentPoint = "BOTTOMLEFT" })
  end

  -- Update selected tab art for all 4 specs
  local specTurn = (not glyphActive) and (not petActive)
  if num >= 2 then
    for g = 1, num do 
      local tab = _G[TAB_NAMES[g]]
      if tab then setTabArt(tab, specTurn and (g == viewG)) end 
    end
    if glyphActive or petActive then
      if T._specCog then T._specCog:Hide() end
    else
      buildCog():Show()
    end
  else
    if T._specCog then T._specCog:Hide() end
    local t1 = _G[TAB_NAMES[1]]
    if t1 then setTabArt(t1, specTurn) end
  end

  if petAvail then
    setTabArt(_G[PET_TAB_NAME], petActive)
  end
  if hasGlyph then
    local gtab = _G[GLYPH_TAB_NAME]
    setTabArt(gtab, glyphActive)
  end
end