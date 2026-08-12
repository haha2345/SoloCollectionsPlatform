-- DragonUI_NewEra/modules/lfg/Dungeons.lua — the Dungeons pane: 3.3.5a Dungeon Finder (LFD)
-- queue UI in the Group Finder window's right side.
--
-- Straight port of FrameXML/LFDFrame.lua's queue surface onto our chrome. The native hidden
-- LFDQueueFrame stays the state machine (see Window.lua header): this pane
--   * mirrors LFDQueueFrame.type through the NATIVE LFDQueueFrame_SetType (so gossip-opened
--     dungeons, LFG_UPDATE_RANDOM_INFO best-choice etc. keep working),
--   * mutates the shared lists through the NATIVE LFDList_SetDungeonEnabled /
--     LFDList_SetHeaderEnabled / LFDList_SetHeaderCollapsed helpers,
--   * joins/leaves through the NATIVE LFDQueueFrame_Join / LeaveLFG (the join reads
--     LFDQueueFrame.type + LFGEnabledList — exactly what we maintained above).
-- Rendering (rows, rewards, status) is rebuilt here from the same shared lists.
--
-- 3.3.5a rules honored: FauxScrollFrame is NAMED, no SetShown, no MaskTexture.

local NE = DragonUI_NewEra
if not NE then return end

NE.lfg = NE.lfg or {}
local L = NE.lfg

local NUM_ROWS, ROW_H = 19, 16
local SCROLL_NAME = "NE_LFGDungeonListScrollFrame"
local DROPDOWN_NAME = "NE_LFGDungeonTypeDropDown"

local pane   -- the pane frame, built once via L.RegisterPane

-- ---------------------------------------------------------------------------
-- Small shared helpers
-- ---------------------------------------------------------------------------

local function lfdEmpowered()
  -- LFD_IsEmpowered is a live global on the 3.3.5a client (Blizzard's own always-loaded
  -- FrameXML calls it bare); guard anyway so a weird core can't hard-error us.
  if type(LFD_IsEmpowered) == "function" then return LFD_IsEmpowered() end
  return true
end

local function skinButton(btn)
  if NE.buttonskin and NE.buttonskin.Skin then pcall(NE.buttonskin.Skin, btn) end
end

-- ---------------------------------------------------------------------------
-- Type dropdown (port of LFDQueueFrameTypeDropDown_Initialize; selection routes through the
-- NATIVE LFDQueueFrame_SetType so every native consumer of LFDQueueFrame.type stays correct).
-- ---------------------------------------------------------------------------

local function isRandomDungeonDisplayable(id)
  local name, _, minLevel, maxLevel, _, _, _, expansionLevel = GetLFGDungeonInfo(id)
  local myLevel = UnitLevel("player")
  return myLevel >= minLevel and myLevel <= maxLevel and (EXPANSION_LEVEL or 2) >= expansionLevel
end

local function typeDropDown_OnClick(self)
  if LFDQueueFrame_SetType then LFDQueueFrame_SetType(self.value) end
  L.RefreshDungeons()
end

local function typeDropDown_Initialize()
  local info = UIDropDownMenu_CreateInfo()

  info.text = SPECIFIC_DUNGEONS or "Specific Dungeons"
  info.value = "specific"
  info.func = typeDropDown_OnClick
  info.checked = LFDQueueFrame and LFDQueueFrame.type == info.value
  UIDropDownMenu_AddButton(info)

  for i = 1, GetNumRandomDungeons() do
    local id, name = GetLFGRandomDungeonInfo(i)
    if isRandomDungeonDisplayable(id) then
      if IsLFGDungeonJoinable(id) then
        info.text = name
        info.value = id
        info.func = typeDropDown_OnClick
        info.disabled = nil
        info.checked = (LFDQueueFrame and LFDQueueFrame.type == id)
        info.tooltipWhileDisabled = nil
        info.tooltipOnButton = nil
        info.tooltipTitle = nil
        info.tooltipText = nil
        UIDropDownMenu_AddButton(info)
      else
        info.text = name
        info.value = id
        info.func = nil
        info.disabled = 1
        info.checked = nil
        info.tooltipWhileDisabled = 1
        info.tooltipOnButton = 1
        info.tooltipTitle = YOU_MAY_NOT_QUEUE_FOR_THIS or "You may not queue for this"
        info.tooltipText = LFDConstructDeclinedMessage and LFDConstructDeclinedMessage(id)
        UIDropDownMenu_AddButton(info)
      end
    end
  end
end

-- ---------------------------------------------------------------------------
-- Specific-dungeon list rows (port of LFDQueueFrameSpecificListButton_SetDungeon).
-- ---------------------------------------------------------------------------

local function rowCheck_OnClick(self)
  local parent = self:GetParent()
  local dungeonID = parent.id
  local isChecked = self:GetChecked() and true or false
  PlaySound(isChecked and "igMainMenuOptionCheckBoxOn" or "igMainMenuOptionCheckBoxOff")
  if LFGIsIDHeader(dungeonID) then
    LFDList_SetHeaderEnabled(dungeonID, isChecked)
  else
    LFDList_SetDungeonEnabled(dungeonID, isChecked)
    LFGListUpdateHeaderEnabledAndLockedStates(LFDDungeonList, LFGEnabledList, LFGLockList, LFDHiddenByCollapseList)
  end
  L.RefreshDungeons()
end

local function rowLock_OnEnter(self)
  local dungeonID = self:GetParent().id
  if LFGIsIDHeader(dungeonID) then return end
  GameTooltip:SetOwner(self, "ANCHOR_TOP")
  GameTooltip:AddLine(YOU_MAY_NOT_QUEUE_FOR_DUNGEON or "You may not queue for this dungeon", 1, 1, 1)
  for i = 1, GetLFDLockPlayerCount() do
    local playerName, lockedReason = GetLFDLockInfo(dungeonID, i)
    if lockedReason ~= 0 then
      local who = (i == 1) and "SELF_" or "OTHER_"
      local code = LFG_INSTANCE_INVALID_CODES and LFG_INSTANCE_INVALID_CODES[lockedReason] or "OTHER"
      local msg = _G["INSTANCE_UNAVAILABLE_" .. who .. code]
      if msg then GameTooltip:AddLine(format(msg, playerName)) end
    end
  end
  GameTooltip:Show()
end

local function makeRow(parent, i)
  local b = CreateFrame("Button", nil, parent)
  b:SetSize(298, ROW_H)

  local expand = CreateFrame("Button", nil, b)
  expand:SetSize(14, 14)
  expand:SetPoint("LEFT", b, "LEFT", 0, 0)
  expand:SetNormalTexture("Interface\\Buttons\\UI-MinusButton-UP")
  expand:SetHighlightTexture("Interface\\Buttons\\UI-PlusButton-Hilight")
  expand:SetScript("OnClick", function(self)
    local p = self:GetParent()
    LFDList_SetHeaderCollapsed(p.id, not p.isCollapsed)   -- native: also rebuilds the lists
    L.RefreshDungeons()
  end)
  b.expandOrCollapseButton = expand

  local check = CreateFrame("CheckButton", nil, b)
  check:SetSize(ROW_H, ROW_H)
  check:SetPoint("LEFT", b, "LEFT", 16, 0)
  check:SetNormalTexture("Interface\\Buttons\\UI-CheckBox-Up")
  check:SetPushedTexture("Interface\\Buttons\\UI-CheckBox-Down")
  check:SetCheckedTexture("Interface\\Buttons\\UI-CheckBox-Check")
  check:SetDisabledCheckedTexture("Interface\\Buttons\\UI-CheckBox-Check-Disabled")
  local chl = check:CreateTexture(nil, "HIGHLIGHT")
  chl:SetTexture("Interface\\Buttons\\UI-CheckBox-Highlight")
  chl:SetAllPoints(check); chl:SetBlendMode("ADD")
  check:SetScript("OnClick", rowCheck_OnClick)
  b.enableButton = check

  local lock = CreateFrame("Button", nil, b)
  lock:SetSize(14, 16)
  lock:SetPoint("LEFT", b, "LEFT", 17, 0)
  local lockTex = lock:CreateTexture(nil, "ARTWORK")
  lockTex:SetAllPoints(lock)
  if not (NE.tex and NE.tex.SetAtlas and NE.tex.SetAtlas(lockTex, "groupfinder-icon-lock", false)) then
    lockTex:SetTexture("Interface\\LFGFrame\\UI-LFG-ICON-LOCK")
    lockTex:SetTexCoord(0, 0.5, 0, 0.5)
  end
  lock:SetScript("OnEnter", rowLock_OnEnter)
  lock:SetScript("OnLeave", function() GameTooltip:Hide() end)
  lock:Hide()
  b.lockedIndicator = lock

  local heroic = b:CreateTexture(nil, "ARTWORK")
  heroic:SetSize(16, 13)
  heroic:SetTexture("Interface\\LFGFrame\\UI-LFG-ICON-HEROIC")
  heroic:SetTexCoord(0, 0.5, 0, 0.625)   -- 16x20px art on the 32x32 sheet (native inline-icon crop)
  heroic:SetPoint("LEFT", b, "LEFT", 38, 0)
  heroic:Hide()
  b.heroicIcon = heroic

  local level = b:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
  level:SetPoint("RIGHT", b, "RIGHT", -4, 0)
  level:SetJustifyH("RIGHT")
  b.level = level

  local name = b:CreateFontString(nil, "ARTWORK", "GameFontNormal")
  name:SetPoint("LEFT", b, "LEFT", 40, 0)
  name:SetPoint("RIGHT", level, "LEFT", -6, 0)
  name:SetJustifyH("LEFT")
  b.instanceName = name

  return b
end

local function paintRow(b, dungeonID, mode)
  local info = LFGGetDungeonInfoByID(dungeonID)
  if not info then b:Hide(); return end
  b.id = dungeonID
  b:Show()

  if LFGIsIDHeader(dungeonID) then
    b.instanceName:SetText(info[LFG_RETURN_VALUES.name])
    b.instanceName:SetFontObject(QuestDifficulty_Header or GameFontNormal)
    b.level:Hide()
    if info[LFG_RETURN_VALUES.typeID] == TYPEID_HEROIC_DIFFICULTY then
      b.heroicIcon:Show()
      b.instanceName:SetPoint("LEFT", b.heroicIcon, "RIGHT", 2, 0)
    else
      b.heroicIcon:Hide()
      b.instanceName:SetPoint("LEFT", b, "LEFT", 40, 0)
    end
    b.expandOrCollapseButton:Show()
    local isCollapsed = LFGCollapseList and LFGCollapseList[dungeonID]
    b.isCollapsed = isCollapsed
    b.expandOrCollapseButton:SetNormalTexture(isCollapsed
      and "Interface\\Buttons\\UI-PlusButton-UP" or "Interface\\Buttons\\UI-MinusButton-UP")
  else
    b.heroicIcon:Hide()
    b.instanceName:SetText(info[LFG_RETURN_VALUES.name])
    b.instanceName:SetPoint("LEFT", b, "LEFT", 40, 0)
    local minLevel, maxLevel = info[LFG_RETURN_VALUES.minLevel], info[LFG_RETURN_VALUES.maxLevel]
    if minLevel == maxLevel then
      b.level:SetText(format(LFD_LEVEL_FORMAT_SINGLE or "(%d)", minLevel))
    else
      b.level:SetText(format(LFD_LEVEL_FORMAT_RANGE or "(%d - %d)", minLevel, maxLevel))
    end
    b.level:Show()
    local difficultyColor = GetQuestDifficultyColor(info[LFG_RETURN_VALUES.recLevel])
    b.level:SetFontObject(difficultyColor.font)
    if mode == "rolecheck" or mode == "queued" or mode == "listed" or not lfdEmpowered() then
      b.instanceName:SetFontObject(QuestDifficulty_Header or GameFontNormal)
    else
      b.instanceName:SetFontObject(difficultyColor.font)
    end
    b.expandOrCollapseButton:Hide()
    b.isCollapsed = false
  end

  if LFGLockList and LFGLockList[dungeonID] then
    b.enableButton:Hide()
    b.lockedIndicator:Show()
  else
    b.enableButton:Show()
    b.lockedIndicator:Hide()
  end

  local enableState
  if mode == "queued" or mode == "listed" then
    enableState = LFGQueuedForList and LFGQueuedForList[dungeonID]
  else
    enableState = LFGEnabledList and LFGEnabledList[dungeonID]
  end
  if enableState == 1 then   -- partially-checked header
    b.enableButton:SetCheckedTexture("Interface\\Buttons\\UI-MultiCheck-Up")
    b.enableButton:SetDisabledCheckedTexture("Interface\\Buttons\\UI-MultiCheck-Disabled")
  else
    b.enableButton:SetCheckedTexture("Interface\\Buttons\\UI-CheckBox-Check")
    b.enableButton:SetDisabledCheckedTexture("Interface\\Buttons\\UI-CheckBox-Check-Disabled")
  end
  b.enableButton:SetChecked(enableState and enableState ~= 0)

  if mode == "rolecheck" or mode == "queued" or mode == "listed" or not lfdEmpowered() then
    b.enableButton:Disable()
  else
    b.enableButton:Enable()
  end
end

local function updateSpecificList()
  local scroll = pane.scroll
  FauxScrollFrame_Update(scroll, LFDGetNumDungeons and LFDGetNumDungeons() or 0, NUM_ROWS, ROW_H)
  local offset = FauxScrollFrame_GetOffset(scroll)
  local mode = GetLFGMode()
  for i = 1, NUM_ROWS do
    local dungeonID = LFDDungeonList and LFDDungeonList[i + offset]
    if dungeonID then
      paintRow(pane.rows[i], dungeonID, mode)
    else
      pane.rows[i]:Hide()
    end
  end
end

-- ---------------------------------------------------------------------------
-- Random-dungeon reward panel (port of LFDQueueFrameRandom_UpdateFrame, simplified layout:
-- our reward buttons flow 2-per-row; money/XP render as text lines via NE.money.Text).
-- ---------------------------------------------------------------------------

local function makeRewardButton(parent, i)
  local b = CreateFrame("Button", nil, parent)
  b:SetSize(143, 32)
  local icon = b:CreateTexture(nil, "ARTWORK")
  icon:SetSize(30, 30)
  icon:SetPoint("LEFT", b, "LEFT", 0, 0)
  b.icon = icon
  local border = b:CreateTexture(nil, "OVERLAY")
  border:SetSize(52, 52)
  border:SetPoint("CENTER", icon, "CENTER", 0, 0)
  border:SetTexture("Interface\\Buttons\\UI-Quickslot2")
  border:SetAlpha(0.7)
  b.border = border
  local count = b:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmall")
  count:SetPoint("BOTTOMRIGHT", icon, "BOTTOMRIGHT", -1, 1)
  b.count = count
  local name = b:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
  name:SetPoint("LEFT", icon, "RIGHT", 5, 0)
  name:SetPoint("RIGHT", b, "RIGHT", 0, 0)
  name:SetJustifyH("LEFT")
  name:SetHeight(30)
  b.name = name
  b:SetScript("OnEnter", function(self)
    if self.dungeonID and self.rewardIndex and GameTooltip.SetLFGDungeonReward then
      GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
      GameTooltip:SetLFGDungeonReward(self.dungeonID, self.rewardIndex)
      GameTooltip:Show()
    end
  end)
  b:SetScript("OnLeave", function() GameTooltip:Hide() end)
  return b
end

local function updateRandomPanel()
  local rp = pane.randomPanel
  local dungeonID = LFDQueueFrame and LFDQueueFrame.type
  if type(dungeonID) ~= "number" then return end

  local dungeonName, _, _, _, _, _, _, _, _, _, difficulty, _, dungeonDescription, isHoliday = GetLFGDungeonInfo(dungeonID)
  local doneToday, moneyBase, moneyVar, experienceBase, experienceVar, numRewards = GetLFGDungeonRewards(dungeonID)
  local numRandoms = 4 - GetNumPartyMembers()
  local moneyAmount = moneyBase + moneyVar * numRandoms
  local experienceGained = experienceBase + experienceVar * numRandoms

  if isHoliday then
    rp.title:SetText(dungeonName)
    rp.description:SetText(dungeonDescription or "")
    rp.rewardsDescription:SetText((doneToday and LFD_HOLIDAY_REWARD_EXPLANATION2 or LFD_HOLIDAY_REWARD_EXPLANATION1) or "")
  else
    rp.title:SetText(LFG_TYPE_RANDOM_DUNGEON or "Random Dungeon")
    rp.description:SetText(LFD_RANDOM_EXPLANATION or "")
    rp.rewardsDescription:SetText((doneToday and LFD_RANDOM_REWARD_EXPLANATION2 or LFD_RANDOM_REWARD_EXPLANATION1) or "")
  end

  rp.rewards = rp.rewards or {}
  local lastAnchor = rp.rewardsDescription
  for i = 1, numRewards do
    local btn = rp.rewards[i]
    if not btn then
      btn = makeRewardButton(rp, i)
      rp.rewards[i] = btn
      if i % 2 == 0 then
        btn:SetPoint("LEFT", rp.rewards[i - 1], "RIGHT", 8, 0)
      else
        btn:SetPoint("TOPLEFT", (i == 1) and rp.rewardsDescription or rp.rewards[i - 2], "BOTTOMLEFT", 0, -6)
      end
    end
    local name, texture, numItems = GetLFGDungeonRewardInfo(dungeonID, i)
    btn.dungeonID = dungeonID
    btn.rewardIndex = i
    btn.name:SetText(name or RETRIEVING_ITEM_INFO or "…")
    -- Reward icons sit inside a square UI-Quickslot2 border (like quest/vendor reward slots) —
    -- SetPortraitToTexture crops to a CIRCLE, which reads as a square-with-a-circle-cutout inside
    -- that square border. Plain SetTexture + the standard icon-border trim crop is what every
    -- other item-icon slot in this codebase uses (bags, glyphs, professions).
    if texture then
      btn.icon:SetTexture(texture)
      btn.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    end
    btn.count:SetText(numItems and numItems > 1 and numItems or "")
    btn:Show()
  end
  for i = numRewards + 1, #rp.rewards do rp.rewards[i]:Hide() end
  if numRewards > 0 then
    lastAnchor = rp.rewards[numRewards - ((numRewards + 1) % 2)] or rp.rewards[numRewards]
  end

  local showRewardHeader = numRewards > 0 or moneyAmount > 0 or experienceGained > 0
  if showRewardHeader then rp.rewardsLabel:Show(); rp.rewardsDescription:Show()
  else rp.rewardsLabel:Hide(); rp.rewardsDescription:Hide() end

  if moneyAmount > 0 then
    rp.moneyLine:SetText((REWARD_MONEY or "Money") .. ": " ..
      (NE.money and NE.money.Text and NE.money.Text(moneyAmount) or tostring(moneyAmount)))
    rp.moneyLine:SetPoint("TOPLEFT", lastAnchor, "BOTTOMLEFT", 0, -8)
    rp.moneyLine:Show()
    lastAnchor = rp.moneyLine
  else
    rp.moneyLine:Hide()
  end
  if experienceGained > 0 then
    rp.xpLine:SetText((REWARD_EXPERIENCE or "Experience") .. ": " .. experienceGained)
    rp.xpLine:SetPoint("TOPLEFT", lastAnchor, "BOTTOMLEFT", 0, -4)
    rp.xpLine:Show()
  else
    rp.xpLine:Hide()
  end
end

-- ---------------------------------------------------------------------------
-- Bottom band: Find-Group button + status line (queue stats / deserter / backfill).
-- ---------------------------------------------------------------------------

local function updateJoinButton()
  local btn = pane.joinButton
  local mode = GetLFGMode()
  if mode == "queued" or mode == "rolecheck" or mode == "proposal" then
    btn:SetText(LEAVE_QUEUE or "Leave Queue")
  elseif mode == "listed" then
    btn:SetText((GetNumPartyMembers() > 0 or GetNumRaidMembers() > 0) and (UNLIST_MY_GROUP or "Unlist My Group") or (UNLIST_ME or "Unlist Me"))
  elseif GetNumPartyMembers() > 0 or GetNumRaidMembers() > 0 then
    btn:SetText(JOIN_AS_PARTY or "Join as Party")
  else
    btn:SetText(FIND_A_GROUP or "Find Group")
  end

  -- Port of LFDQueueFrameFindGroupButton_Update's enable gate; the native "backfill panel
  -- visible" check becomes the raw CanPartyLFGBackfill state.
  local backfillOffered = CanPartyLFGBackfill and CanPartyLFGBackfill()
  if lfdEmpowered() and mode ~= "proposal" then
    if mode == "queued" or mode == "rolecheck" or mode == "listed" or not backfillOffered then
      btn:Enable()
    else
      btn:Disable()
    end
  else
    btn:Disable()
  end
end

local function updateStatus()
  local fs = pane.status
  local mode = GetLFGMode()

  -- Deserter / random-cooldown notes outrank everything (simplified port of
  -- LFDQueueFrameRandomCooldownFrame_Update — the full party breakdown lives in tooltips there;
  -- here one line covers the common solo case).
  local deserter = GetLFGDeserterExpiration and GetLFGDeserterExpiration()
  local cooldown = not deserter and GetLFGRandomCooldownExpiration and GetLFGRandomCooldownExpiration()
  if deserter and GetTime() < deserter then
    fs:SetFormattedText("|cffff2020%s|r", (LFG_DESERTER_YOU or "You recently deserted a dungeon.") ..
      " (" .. SecondsToTime(math.ceil(deserter - GetTime())) .. ")")
    return
  elseif cooldown and GetTime() < cooldown then
    fs:SetFormattedText("|cffff2020%s|r", (LFG_RANDOM_COOLDOWN_YOU or "Random dungeon cooldown") ..
      " (" .. SecondsToTime(math.ceil(cooldown - GetTime())) .. ")")
    return
  end

  if mode == "queued" then
    local hasData, _, tankNeeds, healerNeeds, dpsNeeds, _, _, averageWait, _, _, _, myWait, queuedTime = GetLFGQueueStats()
    local lines = {}
    if hasData and queuedTime then
      local elapsed = GetTime() - queuedTime
      lines[#lines + 1] = format(TIME_IN_QUEUE or "Time in queue: %s",
        (elapsed >= 60) and SecondsToTime(elapsed) or (LESS_THAN_ONE_MINUTE or "< 1 min"))
      if myWait and myWait ~= -1 then
        lines[#lines + 1] = format(LFG_STATISTIC_AVERAGE_WAIT or "Average wait: %s", SecondsToTime(myWait, false, false, 1))
      end
      lines[#lines + 1] = format("%s |cffffffff%d|r  %s |cffffffff%d|r  %s |cffffffff%d|r",
        TANK or "Tank", tankNeeds or 0, HEALER or "Healer", healerNeeds or 0, DAMAGER or "Damage", dpsNeeds or 0)
    else
      lines[#lines + 1] = format(TIME_IN_QUEUE or "Time in queue: %s", LESS_THAN_ONE_MINUTE or "< 1 min")
    end
    fs:SetText(table.concat(lines, "\n"))
  elseif mode == "rolecheck" then
    fs:SetText(ROLE_CHECK_IN_PROGRESS or "Role check in progress…")
  elseif mode == "listed" then
    fs:SetText(LOOKING_FOR_RAID or "Listed in the Raid Browser")
  elseif CanPartyLFGBackfill and CanPartyLFGBackfill() then
    local name = GetPartyLFGBackfillInfo and GetPartyLFGBackfillInfo()
    fs:SetFormattedText(LFG_OFFER_CONTINUE or "Continue %s?", HIGHLIGHT_FONT_COLOR_CODE .. (name or "") .. "|r")
    pane.backfillButton:Show()
    return
  else
    fs:SetText("")
  end
  pane.backfillButton:Hide()
end

-- ---------------------------------------------------------------------------
-- The refresh entry (event-driven + on-show).
-- ---------------------------------------------------------------------------

function L.RefreshDungeons()
  if not (pane and pane:IsVisible()) then return end

  -- Rebuild the shared lists through native code (also runs LFGDungeonList_Setup the first time).
  if LFDQueueFrame_Update then LFDQueueFrame_Update() end

  -- Mirror the native type selection. SetSelectedValue's text refresh only works while the
  -- shared DropDownList still holds OUR buttons, so write the label fontstring directly —
  -- the same trick native LFRFrame.lua:391 uses (LFRBrowseFrameRaidDropDownText:SetText).
  local t = LFDQueueFrame and LFDQueueFrame.type
  UIDropDownMenu_SetSelectedValue(pane.dropdown, t)
  local ddText = _G[DROPDOWN_NAME .. "Text"]
  if ddText then
    if t == "specific" then
      ddText:SetText(SPECIFIC_DUNGEONS or "Specific Dungeons")
    elseif type(t) == "number" then
      ddText:SetText((GetLFGDungeonInfo(t)) or "")
    else
      ddText:SetText("")
    end
  end
  if t == "specific" then
    pane.randomPanel:Hide()
    pane.specificPanel:Show()
    updateSpecificList()
  else
    pane.specificPanel:Hide()
    pane.randomPanel:Show()
    updateRandomPanel()
  end

  pane.roleRow:Refresh()
  updateJoinButton()
  updateStatus()
end

-- ---------------------------------------------------------------------------
-- Pane construction (called lazily by Window.lua's showPane).
-- ---------------------------------------------------------------------------

local function buildPane(host)
  pane = CreateFrame("Frame", nil, host)
  pane:SetAllPoints(host)
  pane:Hide()

  -- Header: type dropdown (left) + role row (right).
  local ddLabel = pane:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
  ddLabel:SetPoint("TOPLEFT", pane, "TOPLEFT", 4, -6)
  ddLabel:SetText(TYPE or "Type")

  local dd = CreateFrame("Frame", DROPDOWN_NAME, pane, "UIDropDownMenuTemplate")
  dd:SetPoint("TOPLEFT", pane, "TOPLEFT", -12, -18)
  UIDropDownMenu_SetWidth(dd, 150)
  UIDropDownMenu_Initialize(dd, typeDropDown_Initialize)
  pane.dropdown = dd

  local roleRow = L.NewRoleRow(pane, { leader = true, size = 30, gap = 6, onChange = L.RefreshDungeons })
  roleRow:SetPoint("TOPRIGHT", pane, "TOPRIGHT", -6, -8)
  pane.roleRow = roleRow

  -- Content inset with the retail groupfinder dark fill.
  local inset = CreateFrame("Frame", nil, pane)
  inset:SetPoint("TOPLEFT", pane, "TOPLEFT", 0, -52)
  inset:SetPoint("BOTTOMRIGHT", pane, "BOTTOMRIGHT", 0, 34)
  -- "InsetFrameTemplate" here is OUR custom Lua nineslice layout name (NineSliceLayouts.lua), not
  -- a real Blizzard XML inherits template — must go through NE.nineslice.ApplyLayout.
  if NE.nineslice and NE.nineslice.ApplyLayout then NE.nineslice.ApplyLayout(inset, "InsetFrameTemplate") end
  local insetBg = inset:CreateTexture(nil, "BACKGROUND", nil, -4)
  if NE.tex and NE.tex.SetAtlas and NE.tex.SetAtlas(insetBg, "groupfinder-background", false) then
    insetBg:SetPoint("TOPLEFT", inset, "TOPLEFT", 2, -2)
    insetBg:SetPoint("BOTTOMRIGHT", inset, "BOTTOMRIGHT", -2, 2)
  end
  pane.inset = inset

  -- Specific list (NAMED FauxScrollFrame — 3.3.5a hard rule).
  local specific = CreateFrame("Frame", nil, inset)
  specific:SetAllPoints(inset)
  pane.specificPanel = specific

  local scroll = CreateFrame("ScrollFrame", SCROLL_NAME, specific, "FauxScrollFrameTemplate")
  scroll:SetPoint("TOPLEFT", specific, "TOPLEFT", 4, -4)
  scroll:SetPoint("BOTTOMRIGHT", specific, "BOTTOMRIGHT", -26, 4)
  scroll:SetScript("OnVerticalScroll", function(self, offset)
    FauxScrollFrame_OnVerticalScroll(self, offset, ROW_H, updateSpecificList)
  end)
  scroll.ScrollBar = _G[SCROLL_NAME .. "ScrollBar"]   -- 3.3.5a template doesn't set the parentKey
  -- Hand-built minimal scrollbar (same as the character window's lists). NE.scrollbar.Reskin's
  -- stock-slider re-skin leaves the bar untextured/invisible on 3.3.5a (its atlas sheets aren't
  -- shipped); BuildCustom draws a visible bar. See modules/character/Reputation.lua.
  -- Via L.BuildListBar, not BuildCustom directly -- it adds the DIALOG strata bump this window
  -- needs for the bar to render in front of its own background at all (see Window.lua).
  L.BuildListBar(scroll, { x = -8, alwaysShow = true })
  scroll:EnableMouseWheel(true)
  scroll:SetScript("OnMouseWheel", function(self, delta)
    local sb = self.ScrollBar
    if not sb then return end
    local mn, mx = sb:GetMinMaxValues()
    local v = sb:GetValue() - delta * ROW_H
    if v < mn then v = mn elseif v > mx then v = mx end
    sb:SetValue(v)
  end)
  pane.scroll = scroll

  pane.rows = {}
  for i = 1, NUM_ROWS do
    local row = makeRow(specific, i)
    if i == 1 then row:SetPoint("TOPLEFT", specific, "TOPLEFT", 6, -5)
    else row:SetPoint("TOPLEFT", pane.rows[i - 1], "BOTTOMLEFT", 0, 0) end
    pane.rows[i] = row
  end

  -- Random reward panel.
  local rp = CreateFrame("Frame", nil, inset)
  rp:SetAllPoints(inset)
  rp:Hide()
  rp.title = rp:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
  rp.title:SetPoint("TOPLEFT", rp, "TOPLEFT", 10, -10)
  rp.description = rp:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
  rp.description:SetPoint("TOPLEFT", rp.title, "BOTTOMLEFT", 0, -6)
  rp.description:SetJustifyH("LEFT")
  -- Explicit width (not a RIGHT anchor) forces a concrete wrap boundary immediately, so the text
  -- flows to new lines instead of truncating with "...". Window is fixed-size, so a constant is
  -- safe: right pane ≈ 331px wide, less the title's 10px left inset and a 10px right margin.
  rp.description:SetWidth(300)
  if rp.description.SetWordWrap then rp.description:SetWordWrap(true) end
  rp.rewardsLabel = rp:CreateFontString(nil, "ARTWORK", "GameFontNormal")
  rp.rewardsLabel:SetPoint("TOPLEFT", rp.description, "BOTTOMLEFT", 0, -12)
  rp.rewardsLabel:SetText(REWARDS or "Rewards")
  rp.rewardsDescription = rp:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
  rp.rewardsDescription:SetPoint("TOPLEFT", rp.rewardsLabel, "BOTTOMLEFT", 0, -4)
  rp.rewardsDescription:SetJustifyH("LEFT")
  rp.rewardsDescription:SetWidth(300)
  if rp.rewardsDescription.SetWordWrap then rp.rewardsDescription:SetWordWrap(true) end
  rp.moneyLine = rp:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
  rp.xpLine = rp:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
  pane.randomPanel = rp

  -- Bottom band.
  local join = CreateFrame("Button", nil, pane, "UIPanelButtonTemplate")
  join:SetSize(135, 22)
  join:SetPoint("BOTTOMRIGHT", pane, "BOTTOMRIGHT", -2, 6)
  join:SetScript("OnClick", function()
    local mode = GetLFGMode()
    if mode == "queued" or mode == "listed" or mode == "rolecheck" then
      LeaveLFG()
    else
      LFDQueueFrame_Join()
    end
    L.RefreshDungeons()
    if L.frame and L.frame.UpdateEye then L.frame.UpdateEye() end
  end)
  skinButton(join)
  pane.joinButton = join

  local backfill = CreateFrame("Button", nil, pane, "UIPanelButtonTemplate")
  backfill:SetSize(90, 22)
  backfill:SetPoint("RIGHT", join, "LEFT", -6, 0)
  backfill:SetText(LFG_OFFER_CONTINUE_BUTTON or YES or "Backfill")
  backfill:SetScript("OnClick", function()
    if StaticPopup_Hide then StaticPopup_Hide("LFG_OFFER_CONTINUE") end
    if PartyLFGStartBackfill then PartyLFGStartBackfill() end
    L.RefreshDungeons()
  end)
  skinButton(backfill)
  backfill:Hide()
  pane.backfillButton = backfill

  local status = pane:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
  status:SetPoint("BOTTOMLEFT", pane, "BOTTOMLEFT", 6, 2)
  status:SetPoint("RIGHT", backfill, "LEFT", -6, 0)
  status:SetJustifyH("LEFT")
  pane.status = status

  -- Live wiring: same events the native LFD surface listens for, gated on visibility.
  local ev = CreateFrame("Frame")
  ev:RegisterEvent("LFG_UPDATE")
  ev:RegisterEvent("LFG_LOCK_INFO_RECEIVED")
  ev:RegisterEvent("LFG_UPDATE_RANDOM_INFO")
  ev:RegisterEvent("LFG_ROLE_UPDATE")
  ev:RegisterEvent("LFG_QUEUE_STATUS_UPDATE")
  ev:RegisterEvent("LFG_PROPOSAL_UPDATE")
  ev:RegisterEvent("LFG_PROPOSAL_SHOW")
  ev:RegisterEvent("LFG_PROPOSAL_FAILED")
  ev:RegisterEvent("LFG_PROPOSAL_SUCCEEDED")
  ev:RegisterEvent("LFG_ROLE_CHECK_SHOW")
  ev:RegisterEvent("LFG_ROLE_CHECK_HIDE")
  ev:RegisterEvent("PARTY_MEMBERS_CHANGED")
  ev:RegisterEvent("PLAYER_ENTERING_WORLD")
  ev:SetScript("OnEvent", function()
    L.RefreshDungeons()
    if L.frame and L.frame.UpdateEye then L.frame.UpdateEye() end
  end)

  -- Elapsed-queue-time ticker (0.5s throttle, only does work while queued + visible).
  local acc = 0
  pane:SetScript("OnUpdate", function(_, elapsed)
    acc = acc + elapsed
    if acc < 0.5 then return end
    acc = 0
    local mode = GetLFGMode()
    if mode == "queued" then updateStatus() end
  end)

  pane.OnPaneShow = function() L.RefreshDungeons() end
  return pane
end

if L.RegisterPane then L.RegisterPane("DUNGEONS", buildPane) end
