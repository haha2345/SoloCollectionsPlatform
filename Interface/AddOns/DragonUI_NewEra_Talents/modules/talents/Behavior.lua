-- DragonUI_NewEra/modules/talents/Behavior.lua — real talent data + preview/commit wiring.
--
-- DOWNPORT: NewEra Talents/Behavior.lua (Era/Classic vanilla-grid talent API) -> 3.3.5a (WotLK).
-- Drives the 3 tree frames built in Talents.lua (the scaffold) from the LIVE 3.3.5a talent API:
--   * real nodes (GetTalentInfo) placed by (tier, column) on each per-tree frame
--   * dependency-bar edges (GetTalentPrereqs -> AXIS-ALIGNED strip + arrowhead, NOT rotated lines)
--   * preview/commit: click->AddPreviewTalentPoints, Apply (confirm) / Reset, points readout
--
-- WotLK API REMAP (vs the NewEra Era source):
--   * Era's GetTalentInfo returned a TABLE and C_SpecializationInfo.* wrappers. 3.3.5a has the FLAT
--     globals: GetTalentInfo (10-tuple), GetTalentTabInfo, GetActiveTalentGroup, GetNumTalentTabs,
--     GetNumTalents, GetTalentPrereqs. We re-table GetTalentInfo via talentInfo() below; everything
--     downstream keeps the table shape it expects. There is NO talentID on 3.3.5a, so the tooltip
--     and click paths key on (tab, index) instead.
--   * Preview talents shipped in patch 3.1: previewTalents gate, AddPreviewTalentPoints,
--     LearnPreviewTalents, ResetGroupPreviewTalentPoints, GetGroupPreviewTalentPointsSpent — all
--     native. AddPreviewTalentPoints on 3.3.5a takes NO sign/delta arg (adds +1); right-click
--     "remove a point" is done discard-and-re-add (see nodeRightClick).
--
-- Commit flow mirrors Blizzard's stock 3.3.5a Blizzard_TalentUI.lua: gated on previewTalents
-- (forced on while the window is open, restored on close), LearnPreviewTalents() commits (behind a
-- confirm), discard via ResetGroupPreviewTalentPoints. Nothing is destructive until the confirm.
--
-- EDGES: NewEra rotated arrow textures with atan2/cos/sin + Texture:SetRotation. SetRotation and
-- CreateLine DO NOT EXIST on 3.3.5a (both Cata+). So edges here mirror Blizzard's stock 3.3.5a
-- TalentFrame.lua branch drawing: axis-aligned WHITE8X8 strips (vertical / horizontal segments) +
-- a directional arrowhead via SetTexCoord flips. L-routing (column AND tier differ) is drawn as a
-- vertical drop + horizontal run; see drawEdge.

local NE = DragonUI_NewEra
local T = NE.talents or {}

-- Triumvirate-only realm gate. Triumvirate ships a custom native dual-spec-unlock UI (gold cost +
-- a 3rd/4th spec tier) that other servers (Turtle WoW, Project Epoch, stock 3.3.5a) don't have; any
-- code that assumes it exists must be gated behind this so it doesn't run on a realm without it.
local function IsTriumvirate()
  return (GetRealmName and GetRealmName() or "") == "Triumvirate"
end
T.IsTriumvirate = IsTriumvirate
NE.talents = T

local PER_TIER     = 5   -- tier t needs (t-1)*5 points spent in that tree (WotLK == vanilla rule)
local PET_PER_TIER = 3   -- PET talents gate every 3 points/tier (not 5) — the WotLK pet rule

-- Pet talents exist ONLY for hunter pets (Ferocity / Tenacity / Cunning); GetPetTalentTree returns
-- nil for warlock/quest pets or no pet. This is the gate for showing the Pet tab + rendering it.
local function petHasTalents()
  if not GetPetTalentTree then return false end
  local ok, tree = pcall(GetPetTalentTree)
  return (ok and tree ~= nil and tree ~= "") and true or false
end
T.PetHasTalents = petHasTalents

-- True when the window is currently showing the PET talent view (Pet tab selected AND a talented pet
-- is out). Consumed by SpecTabs (tab art), Glyphs (pane visibility) and Populate.
function T.PetViewActive() return (T._petView and petHasTalents()) and true or false end
function T.SetPetView(on)
  T._petView = on and true or false
  if T._petView and T.GlyphsSetActive then T.GlyphsSetActive(false) end
end

-- Edge tint: yellow (prereq satisfied + invested) vs dim gray (not yet active).
local EDGE_ACTIVE   = { 1.0, 0.82, 0.0,  0.95 }
local EDGE_INACTIVE = { 0.62, 0.58, 0.48, 0.85 }   -- muted tan, visible over the dark spec painting

-- Sound cues (3.3.5a named PlaySound kits; swap any of these to taste). pcall-guarded so a missing
-- name never errors. add/remove are tied to ACTUAL rank changes (see Populate), not raw clicks.
local SOUNDS = {
  add    = "igMainMenuOptionCheckBoxOn",   -- crisp tick when a point lands
  remove = "igCharacterInfoTab",           -- softer click when a point is refunded
  apply  = "gsTitleOptionOK",              -- clean, understated confirm when talents are committed
  spec   = "igMainMenuOpen",               -- whoosh on a successful spec switch
}
local function playSound(key)
  local s = SOUNDS[key]
  if s and PlaySound then pcall(PlaySound, s) end
end

-- ----------------------------------------------------------------------------
-- API adapter: GetTalentInfo (flat 10-tuple) -> the table shape the renderer expects.
-- 3.3.5a: name, iconTexture, tier, column, rank, maxRank, isExceptional, meetsPrereq,
--         previewRank, meetsPreviewPrereq. NO talentID exists (keyed on tab/index).
-- ----------------------------------------------------------------------------
local function talentInfo(tab, i, group, isPet)
  if not GetTalentInfo then return nil end
  local name, icon, tier, column, rank, maxRank, isExceptional,
        meetsPrereq, previewRank, meetsPreviewPrereq = GetTalentInfo(tab, i, false, isPet or false, group)
  if not name then return nil end
  return {
    name               = name,
    icon               = icon,
    tier               = tier,
    column             = column,
    rank               = rank or 0,
    maxRank            = maxRank or 0,
    isExceptional      = isExceptional,
    meetsPrereq        = meetsPrereq,
    previewRank        = previewRank,
    meetsPreviewPrereq = meetsPreviewPrereq,
    talentID           = nil,   -- none on 3.3.5a
  }
end

local function previewOn()
  local ok, v
  if GetCVarBool then ok, v = pcall(GetCVarBool, "previewTalents"); if ok then return v end end
  if GetCVar then ok, v = pcall(GetCVar, "previewTalents"); if ok then return v == "1" end end
  return false
end

local function unspentPoints(group, isPet)
  if GetUnspentTalentPoints then
    local ok, v = pcall(GetUnspentTalentPoints, false, isPet or false, group)
    if ok and v then return v end
  end
  if not isPet and UnitCharacterPoints then return UnitCharacterPoints("player") or 0 end
  return 0
end

local function previewSpent(group, isPet)
  if GetGroupPreviewTalentPointsSpent then
    local ok, v = pcall(GetGroupPreviewTalentPointsSpent, isPet or false, group)
    if ok and v then return v end
  end
  return 0
end

local function discardPreview(group, isPet)
  if InCombatLockdown and InCombatLockdown() then return end
  isPet = isPet or false
  if ResetPreviewTalentPoints then pcall(ResetPreviewTalentPoints) end
  if ResetGroupPreviewTalentPoints then
    pcall(ResetGroupPreviewTalentPoints, isPet, group)
    pcall(ResetGroupPreviewTalentPoints, group)
  end
  if not (AddPreviewTalentPoints and GetTalentInfo and GetNumTalentTabs) then return end
  for _pass = 1, 2 do
    for t = 1, (GetNumTalentTabs(false, isPet) or 0) do
      local n = (GetNumTalents and GetNumTalents(t, false, isPet)) or 0
      for i = n, 1, -1 do
        local info = talentInfo(t, i, group, isPet)
        if info then
          local staged = (info.previewRank or 0) - (info.rank or 0)
          if staged > 0 then pcall(AddPreviewTalentPoints, t, i, -staged, isPet, group) end
        end
      end
    end
  end
end
T.DiscardPreview = discardPreview

-- ----------------------------------------------------------------------------
-- State machine. Map a talentInfo to (state, displayRank).
-- ----------------------------------------------------------------------------
local function computeState(info, tabPointsSpent, preview, available, perTier)
  perTier = perTier or PER_TIER
  local liveRank    = info.rank or 0
  local displayRank = (preview and info.previewRank) or liveRank
  local meets       = (preview and info.meetsPreviewPrereq) or info.meetsPrereq
  local tierUnlocked= ((info.tier or 1) - 1) * perTier <= tabPointsSpent
  local forceDesat  = (available <= 0) and (displayRank == 0)
  local colored     = meets and tierUnlocked and not forceDesat
  local state
  if preview and displayRank < liveRank then
    state = "red"
  elseif not colored then
    state = (not tierUnlocked and displayRank == 0) and "locked" or "gray"
  elseif displayRank == 0 then
    state = "green"
  elseif displayRank >= (info.maxRank or displayRank) then
    state = "yellow"
  else
    state = "yellow"
  end
  return state, displayRank
end

-- ----------------------------------------------------------------------------
-- Node Interactions
-- ----------------------------------------------------------------------------
local function nodeLeftClick(self)
  if not AddPreviewTalentPoints then return end
  if self._isPet then
    pcall(AddPreviewTalentPoints, self._tab, self._index, 1, true, T._activeGroup or 1)
  else
    pcall(AddPreviewTalentPoints, self._tab, self._index, 1)
  end
end

local function nodeRightClick(self)
  if not AddPreviewTalentPoints then return end
  if self._isPet then
    pcall(AddPreviewTalentPoints, self._tab, self._index, -1, true, T._activeGroup or 1)
  else
    pcall(AddPreviewTalentPoints, self._tab, self._index, -1)
  end
end

local function nodeTooltip(self)
  GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
  if self._tab and self._index and GameTooltip.SetTalent then
    local isPet = self._isPet or false
    local group = isPet and (T._activeGroup or 1) or (T._viewGroup or T._activeGroup or 1)
    local ok = pcall(GameTooltip.SetTalent, GameTooltip, self._tab, self._index, false, isPet, group, previewOn())
    if not ok then
      ok = pcall(GameTooltip.SetTalent, GameTooltip, self._tab, self._index, false, isPet, group)
    end
    if ok then
      GameTooltip:Show()
      return
    end
  end
  if self._tipName then
    GameTooltip:SetText(self._tipName, 1, 1, 1, 1, true)
    GameTooltip:Show()
  end
end

local function wireNode(n)
  if n._wired then return end
  n._wired = true
  n:RegisterForClicks("LeftButtonUp", "RightButtonUp")
  n:SetScript("OnClick", function(self, btn)
    if InCombatLockdown and InCombatLockdown() then return end
    if not self._isPet and (T._viewGroup or 1) ~= (T._activeGroup or 1) then return end
    if btn == "LeftButton" then nodeLeftClick(self)
    elseif btn == "RightButton" then nodeRightClick(self) end
    nodeTooltip(self)
  end)
  n:SetScript("OnEnter", function(self)
    if self.ShowHover then self:ShowHover() end
    nodeTooltip(self)
  end)
  n:SetScript("OnLeave", function(self)
    if self.HideHover then self:HideHover() end
    GameTooltip:Hide()
  end)
end
T._WireNode = wireNode

-- ----------------------------------------------------------------------------
-- EDGE DRAWING & FLOW ENGINE
-- ----------------------------------------------------------------------------
local sqrt = math.sqrt
local DOT_SIZE, DOT_GAP, HEAD_SIZE, FLOW_SPEED = 4, 9, 7, 16

local function positionEdge(edge, phase)
  local dots, span, gap = edge.dots, edge.span, edge.gap
  for i = 1, #dots do
    local dist = ((i - 1) * gap + phase) % span
    local d = dots[i]
    d:ClearAllPoints()
    d:SetPoint("CENTER", edge.tf, "TOPLEFT", edge.x0 + edge.ux * dist, edge.y0 + edge.uy * dist)
  end
end

local SHEEN_SWEEP, SHEEN_PEAK = 0.7, 0.40
local GLINT_MIN, GLINT_MAX    = 0.25, 0.95
local sin, pi, random = math.sin, math.pi, math.random

local function updateSheen(node, clock)
  local s = node.sheen
  if not s then return end
  local st = node._sheenStart
  if not st then if s:IsShown() then s:Hide() end return end
  local t = (clock - st) / SHEEN_SWEEP
  if t < 0 or t >= 1 then node._sheenStart = nil; s:Hide(); return end
  local env  = sin(pi * t)
  local full = node._sheenSpan or 28
  local sz = full * env
  if sz < 1 then sz = 1 end
  s:SetSize(sz, sz)
  local d = full * (t - 0.5)
  s:ClearAllPoints()
  s:SetPoint("CENTER", node, "CENTER", d, -d)
  s:SetAlpha(SHEEN_PEAK)
  s:Show()
end

local function ensureFlowDriver(f)
  if f._edgeFlow then return end
  f._edgeFlow = true
  T._edgePhase = 0
  T._sheenClock = 0
  T._nextGlint = 0
  f:HookScript("OnUpdate", function(self, dt)
    dt = dt or 0
    T._edgePhase = (T._edgePhase or 0) + dt * FLOW_SPEED
    if T._edgePhase > 1e6 then T._edgePhase = 0 end
    local clock = (T._sheenClock or 0) + dt
    if clock > 1e6 then clock = 0; T._nextGlint = 0 end
    T._sheenClock = clock
    local trees = self.trees
    if not trees then return end
    for i = 1, 3 do
      local tf = trees[i]
      if tf then
        local el = tf._edgeList
        if el then for j = 1, #el do positionEdge(el[j], T._edgePhase) end end
        local sl = tf._sheenList
        if sl then for j = 1, #sl do updateSheen(sl[j], clock) end end
      end
    end
    if clock >= (T._nextGlint or 0) then
      local cand = {}
      for i = 1, 3 do
        local sl = trees[i] and trees[i]._sheenList
        if sl then for j = 1, #sl do cand[#cand + 1] = sl[j] end end
      end
      local n = #cand
      if n > 0 then
        if n > 1 and T._lastGlint then
          for k = n, 1, -1 do if cand[k] == T._lastGlint then table.remove(cand, k); break end end
        end
        local pick = cand[random(#cand)]
        pick._sheenStart = clock
        T._lastGlint = pick
      end
      local mult = math.max(1, 6 - n)
      T._nextGlint = clock + (GLINT_MIN + random(0, math.floor((GLINT_MAX - GLINT_MIN) * 1000)) / 1000) * mult
    end
  end)
end

local function drawEdge(tf, sTier, sCol, dTier, dCol, color)
  local sx, sy = T.nodeCenter(sTier, sCol)
  local ex, ey = T.nodeCenter(dTier, dCol)
  local dx, dy = ex - sx, ey - sy
  local dist = sqrt(dx * dx + dy * dy)
  if dist < 1 then return end
  local ux, uy = dx / dist, dy / dist
  local half = T.LAYOUT.NODE / 2
  local x0, y0 = sx + ux * half, sy + uy * half
  local span = dist - 2 * half
  if span <= 0 then return end
  local count = math.floor(span / DOT_GAP + 0.5)
  if count < 1 then count = 1 end
  local gap = span / count
  local dots = {}
  for _ = 1, count do
    local d = tf:AcquireDot()
    d:SetSize(DOT_SIZE, DOT_SIZE)
    d:SetVertexColor(color[1], color[2], color[3], color[4])
    dots[#dots + 1] = d
  end
  local edge = { tf = tf, x0 = x0, y0 = y0, ux = ux, uy = uy, span = span, gap = gap, dots = dots }
  tf._edgeList[#tf._edgeList + 1] = edge
  positionEdge(edge, T._edgePhase or 0)
end

-- ----------------------------------------------------------------------------
-- BOTTOM BAR SETUP
-- ----------------------------------------------------------------------------
StaticPopupDialogs["NE_TALENTS_LEARN"] = {
  text = CONFIRM_LEARN_PREVIEW_TALENTS or "Learn the selected talents? Spent points cannot be refunded without a respec.",
  button1 = YES, button2 = NO,
  OnAccept = function()
    if LearnPreviewTalents then pcall(LearnPreviewTalents, T.PetViewActive and T.PetViewActive() or false) end
    playSound("apply")
  end,
  hideOnEscape = 1, timeout = 0, exclusive = 1, whileDead = 1,
}

local function buildBottomBar(f)
  if f._barBuilt then return end
  f._barBuilt = true

  f.pointsText = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  f.pointsText:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", (T.FRAME.CHROME_L or 0) + 24, (T.FRAME.CHROME_B or 0) + 30)
  f.pointsText:SetText("")

  local apply = CreateFrame("Button", "NE_TalentApplyButton", f, "UIPanelButtonTemplate")
  apply:SetSize(120, 26)
  apply:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -((T.FRAME.CHROME_R or 0) + 24), (T.FRAME.CHROME_B or 0) + 27)
  apply:SetText(APPLY or "Apply")
  apply:SetScript("OnClick", function()
    if InCombatLockdown and InCombatLockdown() then return end
    StaticPopup_Show("NE_TALENTS_LEARN")
  end)
  f.apply = apply

  local reset = CreateFrame("Button", "NE_TalentResetButton", f, "UIPanelButtonTemplate")
  reset:SetSize(120, 26)
  reset:SetPoint("RIGHT", apply, "LEFT", -8, 0)
  reset:SetText(RESET or "Reset")
  reset:SetScript("OnClick", function()
    if InCombatLockdown and InCombatLockdown() then return end
    discardPreview(T._activeGroup or 1, T.PetViewActive and T.PetViewActive() or false)
    if T.Refresh then T.Refresh() end
  end)
  f.reset = reset

  local activate = CreateFrame("Button", "NE_TalentActivateButton", f, "UIPanelButtonTemplate")
  activate:SetSize(160, 26)
  activate:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -((T.FRAME.CHROME_R or 0) + 24), (T.FRAME.CHROME_B or 0) + 27)
  activate:SetText("Activate")
  activate:SetScript("OnClick", function()
    if InCombatLockdown and InCombatLockdown() then return end

    if IsTriumvirate() then
      local unlockBtn = _G["TriumvirateSpecActivateButton"]
      local nativeNumGroups = (GetNumTalentGroups and GetNumTalentGroups()) or 2
      local isLocked = (unlockBtn and unlockBtn:IsShown()) or ((T._viewGroup or 1) > nativeNumGroups)

      if isLocked then
        if unlockBtn and unlockBtn.Click then unlockBtn:Click() end
        return
      end
    end

    if SetActiveTalentGroup and T._viewGroup then pcall(SetActiveTalentGroup, T._viewGroup) end
  end)
  activate:Hide()
  f.activate = activate

  f._setSubButtonsEnabled = function(on)
    if apply.SetEnabled then apply:SetEnabled(on) else
      if on then apply:Enable() else apply:Disable() end
    end
    if reset.SetEnabled then reset:SetEnabled(on) else
      if on then reset:Enable() else reset:Disable() end
    end
  end
end

-- ----------------------------------------------------------------------------
-- VISUAL DECORATIONS & BACKGROUNDS
-- ----------------------------------------------------------------------------
local PET_BG_PATH = "Interface\\AddOns\\DragonUI_NewEra\\Textures\\Talents\\"
local PET_BG_FILE = {
  HunterPetFerocity = "Pet_Ferocity",
  HunterPetTenacity = "Pet_Tenacity",
  HunterPetCunning   = "Pet_Cunning",
}
local function applyPetBackground(f, bgName)
  if not f then return end
  if not f.petBg then
    local tx = f:CreateTexture(nil, "BORDER")
    tx:SetPoint("TOPLEFT",     f, "TOPLEFT",     (T.FRAME.CHROME_L or 0), -(T.FRAME.CHROME_T or 0))
    tx:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -(T.FRAME.CHROME_R or 0), (T.FRAME.CHROME_B or 0) + (T.FRAME.BOTTOMBAR_H or 0))
    tx:SetTexCoord(0, 1, 0, 1)
    f.petBg = tx
  end
  local file = bgName and PET_BG_FILE[bgName]
  if file then f.petBg:SetTexture(PET_BG_PATH .. file) end
  if f.bg then f.bg:Hide() end
  f.petBg:Show()
end

local function refreshPetPortrait(f)
  local p = f and f.portrait
  if not (p and SetPortraitTexture) then return end
  if not (T.PetViewActive and T.PetViewActive()) then return end 
  if UnitExists and not UnitExists("pet") then return end
  p:SetTexCoord(0, 1, 0, 1)
  pcall(SetPortraitTexture, p, "pet")
end

local function ensurePetPortrait(f)
  refreshPetPortrait(f)
  if C_Timer and C_Timer.After then
    C_Timer.After(0,   function() refreshPetPortrait(f) end)
    C_Timer.After(0.3, function() refreshPetPortrait(f) end)
  end
  if not f._nePetPortraitWatcher then
    local w = CreateFrame("Frame", nil, f)
    w:RegisterEvent("UNIT_PORTRAIT_UPDATE")
    w:RegisterEvent("UNIT_PET")
    w:SetScript("OnEvent", function(_, _, unit)
      if unit == nil or unit == "pet" or unit == "player" then refreshPetPortrait(f) end
    end)
    f._nePetPortraitWatcher = w
  end
end
T._ApplyPetBackground = applyPetBackground

-- ----------------------------------------------------------------------------
-- MAIN DATA REFRESH MATRIX (T.Populate)
-- ----------------------------------------------------------------------------
function T.Populate()
  local f = T.frame
  if not f or not GetTalentInfo then return end
  buildBottomBar(f)
  ensureFlowDriver(f)

  if T._petView and not petHasTalents() then T._petView = false end
  local isPet   = T._petView and true or false
  local perTier = isPet and PET_PER_TIER or PER_TIER

  local active = (GetActiveTalentGroup and GetActiveTalentGroup()) or 1
  if T._viewGroup == nil or T._lastActive ~= active then T._viewGroup = active end
  T._activeGroup, T._lastActive = active, active
  local numGroups = (GetNumTalentGroups and (GetNumTalentGroups() or 1)) or 1
  if numGroups < 2 then T._viewGroup = active end
  
  local group    = isPet and active or T._viewGroup
  local editable = isPet or (group == active)
  local viewChanged = (T._lastViewGroup ~= group) or (T._lastPetView ~= isPet)
  T._lastViewGroup, T._lastPetView = group, isPet
  T._group = group
  local preview = previewOn() and editable
  local numTabs = (GetNumTalentTabs and GetNumTalentTabs(false, isPet)) or 0

  for i = 1, 3 do
    local tf = f.trees[i]
    if tf and not tf._defPoint then tf._defPoint = { tf:GetPoint() } end
  end
  if isPet and numTabs <= 1 then
    local tf = f.trees[1]
    local dp = tf._defPoint
    local treeW = (T.LAYOUT and T.LAYOUT.TREE_W) or tf:GetWidth() or 0
    tf:ClearAllPoints()
    tf:SetPoint("TOPLEFT", f, "TOPLEFT", (T.FRAME.W - treeW) / 2, dp and dp[5] or -64)
  else
    for i = 1, 3 do
      local tf = f.trees[i]
      local dp = tf and tf._defPoint
      if dp then tf:ClearAllPoints(); tf:SetPoint(unpack(dp)) end
    end
  end

  T._nodeYShift = 0
  if isPet then
    local layTiers = (T.LAYOUT and T.LAYOUT.TIERS) or 11
    local pitchY   = (T.LAYOUT and T.LAYOUT.PITCH_Y) or 44
    local maxTier, nt = 1, (GetNumTalents and GetNumTalents(1, false, true)) or 0
    for i = 1, nt do
      local info = talentInfo(1, i, group, true)
      if info and info.tier and info.tier > maxTier then maxTier = info.tier end
    end
    T._nodeYShift = math.max(0, layTiers - maxTier) * pitchY / 2
  end

  local unspent       = unspentPoints(group, isPet)
  local previewSpentAll = preview and previewSpent(group, isPet) or 0
  local available     = unspent - previewSpentAll

  local domIcon, domSpent, domTab = nil, -1, 1
  local petBgName

  for tabIdx = 1, 3 do
    local tf = f.trees[tabIdx]
    tf:ResetEdges(); tf:ResetGates()
    tf._edgeList = {}
    tf._sheenList = {}
    local used = {}

    if tabIdx <= numTabs then
      local name, icon, spent, _bg, prevSpent = GetTalentTabInfo(tabIdx, false, isPet, group)
      if isPet and _bg then petBgName = _bg end
      local tabPointsSpent = (spent or 0) + (preview and (prevSpent or 0) or 0)
      tf.headerName:SetText(string.upper(name or ("Tree " .. tabIdx)))
      tf.headerPts:SetText(tostring(tabPointsSpent))
      tf.headerPts:SetTextColor((tabPointsSpent > 0) and 0.1 or 0.5, (tabPointsSpent > 0) and 1.0 or 0.5, (tabPointsSpent > 0) and 0.1 or 0.5)
      
      local nameW = (tf.headerName:GetStringWidth() or 0) * 0.9
      local ptsW  = tf.headerPts:GetStringWidth() or 0
      tf.headerName:ClearAllPoints()
      tf.headerName:SetPoint("LEFT", tf, "TOPLEFT", (tf:GetWidth() - (nameW + 8 + ptsW)) / 2, (T.LAYOUT and T.LAYOUT.HEADER_CENTER_Y) or -13)

      if (spent or 0) > domSpent then domSpent = (spent or 0); domIcon = icon; domTab = tabIdx end

      local numTalents = (GetNumTalents and GetNumTalents(tabIdx, false, isPet)) or 0
      local byCell, infos = {}, {}

      local occupied = {}
      for i = 1, numTalents do
        local info = talentInfo(tabIdx, i, group, isPet)
        if info and info.tier and info.column then
          infos[i] = info
          occupied[#occupied + 1] = { tier = info.tier, column = info.column }
        end
      end
      if T.SetCenteredLayout then T.SetCenteredLayout(occupied) end

      for i = 1, numTalents do
        local info = infos[i]
        if info and info.tier and info.column then
          local shape = T.ResolveShape(info)
          local state, displayRank = computeState(info, tabPointsSpent, preview, (editable and available) or 0, perTier)
          local node = tf:AcquireNode(i); used[i] = true
          node._tab, node._index, node._talentID = tabIdx, i, nil
          node._isPet = isPet
          node._tipName = info.name
          local rankText = (info.maxRank and info.maxRank > 0) and (tostring(displayRank) .. "/" .. tostring(info.maxRank)) or ""
          node:SetVisual(shape, state, info.icon, rankText)
          
          if editable and not viewChanged and node._shownRank then
            if displayRank > node._shownRank then
              if node.PlaySpend then node:PlaySpend() end
              playSound("add")
            elseif displayRank < node._shownRank then
              playSound("remove")
            end
          end
          node._shownRank = displayRank
          
          node:SetAlpha(editable and 1 or 0.66)
          if not editable and node.icon and node.icon.SetDesaturated then node.icon:SetDesaturated(true) end
          local x, y = T.nodeCenter(info.tier, info.column)
          node:ClearAllPoints(); node:SetPoint("CENTER", tf, "TOPLEFT", x, y); node:Show()
          wireNode(node)
          
          if editable and (displayRank or 0) > 0 then
            tf._sheenList[#tf._sheenList + 1] = node
          else
            node._sheenStart = nil
            if node.sheen then node.sheen:Hide() end
          end
          byCell[info.tier * 10 + info.column] = info
        end
      end

      if editable then
        for i = 1, numTalents do
          local info = infos[i]
          if info and GetTalentPrereqs then
            local pre = { GetTalentPrereqs(tabIdx, i, false, isPet, group) }
            for p = 1, #pre, 4 do
              local ptier, pcol = pre[p], pre[p + 1]
              local srcInfo = ptier and pcol and byCell[ptier * 10 + pcol]
              if srcInfo then
                local srcRank = (preview and srcInfo.previewRank) or srcInfo.rank or 0
                local meets   = (preview and info.meetsPreviewPrereq) or info.meetsPrereq
                local active  = meets and srcRank > 0
                local color   = active and EDGE_ACTIVE or EDGE_INACTIVE
                drawEdge(tf, ptier, pcol, info.tier, info.column, color)
              end
            end
          end
        end
      end
    else
      tf.headerName:SetText(""); tf.headerPts:SetText("")
    end

    tf:HideUnusedNodes(used)
    tf:HideUnusedEdges()
    tf:HideUnusedGates()
  end

  if f.portrait then
    if isPet then
      ensurePetPortrait(f)
    else
      local _, classFile = UnitClass("player")
      local c = classFile and CLASS_ICON_TCOORDS and CLASS_ICON_TCOORDS[classFile]
      if c then
        f.portrait:SetTexture("Interface\\TargetingFrame\\UI-Classes-Circles")
        f.portrait:SetTexCoord(c[1], c[2], c[3], c[4])
      elseif domIcon then
        f.portrait:SetTexCoord(0, 1, 0, 1); f.portrait:SetTexture(domIcon)
      end
    end
  end

  if isPet then
    applyPetBackground(f, petBgName)
  else
    if f.petBg then f.petBg:Hide() end
    if f.bg then f.bg:Show() end
    if T.SetBackground then T.SetBackground(domTab) end
  end

  if f.pointsText then
    f.pointsText:SetText(("|cffffffff%d|r points available"):format(math.max(0, available)))
  end
  local hasStaged = previewSpentAll > 0
  if f.apply and GlowEmitterFactory and GlowEmitterMixin then
    if hasStaged then
      GlowEmitterFactory:Show(f.apply, GlowEmitterMixin.Anims.NPE_RedButton_GreenGlow)
    else
      GlowEmitterFactory:Hide(f.apply)
    end
  end

  -- Bottom bar: editable (active) spec shows Apply/Reset; a viewed INACTIVE spec shows Activate.
  if editable then
    if f.activate then f.activate:Hide() end
    if f.apply then f.apply:Show() end
    if f.reset then f.reset:Show() end
    if f._setSubButtonsEnabled then f._setSubButtonsEnabled(hasStaged) end
  else
    if f.apply then f.apply:Hide() end
    if f.reset then f.reset:Hide() end
    if f.activate then
      f.activate:Show()

      if IsTriumvirate() then
        -- ---- Triumvirate Gold & Lock Verification ---------------------------------------
        local unlockBtn = _G["TriumvirateSpecActivateButton"]
        local nativeNumGroups = (GetNumTalentGroups and GetNumTalentGroups()) or 2
        local isLocked = (unlockBtn and unlockBtn:IsShown()) or (group > nativeNumGroups)

        local goldCost = 0
        if group == 2 then goldCost = 1
        elseif group == 3 then goldCost = 2000
        elseif group == 4 then goldCost = 5000 end

        local unlockCost  = goldCost * 100 * 100
        local playerMoney = GetMoney() or 0

        if isLocked then
          if playerMoney < unlockCost then
            f.activate:SetText("Locked")
            f.activate:Disable()
            if f.activate.SetAlpha then f.activate:SetAlpha(0.25) end
            local btnText = f.activate:GetFontString()
            if btnText then btnText:SetTextColor(0.4, 0.4, 0.4) end
          else
            f.activate:SetText("Unlock Spec")
            f.activate:Enable()
            if f.activate.SetAlpha then f.activate:SetAlpha(1.0) end
            local btnText = f.activate:GetFontString()
            if btnText then btnText:SetTextColor(1, 0.82, 0) end
          end
        else
          f.activate:SetText("Activate")
          f.activate:Enable()
          if f.activate.SetAlpha then f.activate:SetAlpha(1.0) end
          local btnText = f.activate:GetFontString()
          if btnText then btnText:SetTextColor(1, 1, 1) end
        end
        -- ---------------------------------------------------------------------------------
      else
        -- Non-Triumvirate realms: plain Activate, no gold-unlock system to check against.
        f.activate:SetText("Activate")
        f.activate:Enable()
        if f.activate.SetAlpha then f.activate:SetAlpha(1.0) end
        local btnText = f.activate:GetFontString()
        if btnText then btnText:SetTextColor(1, 1, 1) end
      end
    end
  end

  if f._loBtn then if isPet then f._loBtn:Hide() else f._loBtn:Show() end end

  if T.RefreshSpecTabs then T.RefreshSpecTabs() end
  if T.GlyphsEnsureUI then pcall(T.GlyphsEnsureUI) end
  if T.GlyphsRefresh then pcall(T.GlyphsRefresh) end
  if T.GlyphsApplyPaneVisibility then pcall(T.GlyphsApplyPaneVisibility) end
end

function T.Refresh()
  local f = T.frame
  if not (f and f:IsShown()) then return end
  T.Populate()
end

-- ----------------------------------------------------------------------------
-- INITIALIZATION ROOT BOOT
-- ----------------------------------------------------------------------------
local boot = CreateFrame("Frame")
boot:RegisterEvent("PLAYER_LOGIN")
boot:SetScript("OnEvent", function()
  local f = T.frame
  if not f then return end
  buildBottomBar(f)

  f:HookScript("OnShow", function()
    if GetCVar then pcall(function() T._savedPreviewCVar = GetCVar("previewTalents") end) end
    if SetCVar then pcall(SetCVar, "previewTalents", "1") end
    if T.Populate then T.Populate() end
  end)
  f:HookScript("OnHide", function()
    discardPreview(T._activeGroup or 1, false)
    if petHasTalents() then discardPreview(T._activeGroup or 1, true) end
    if SetCVar and T._savedPreviewCVar then pcall(SetCVar, "previewTalents", T._savedPreviewCVar) end
  end)

  local ev = CreateFrame("Frame")
  for _, e in ipairs({
    "PLAYER_TALENT_UPDATE", "CHARACTER_POINTS_CHANGED", "PREVIEW_TALENT_POINTS_CHANGED",
    "PLAYER_LEVEL_UP", "ACTIVE_TALENT_GROUP_CHANGED",
    "PET_TALENT_UPDATE", "PREVIEW_PET_TALENT_POINTS_CHANGED", "UNIT_PET",
  }) do pcall(function() ev:RegisterEvent(e) end) end
  ev:SetScript("OnEvent", function(_, event, arg1)
    if event == "UNIT_PET" and arg1 ~= "player" then return end
    if event == "ACTIVE_TALENT_GROUP_CHANGED" then playSound("spec") end
    T.Refresh()
  end)
end)