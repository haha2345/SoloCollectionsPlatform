-- DragonUI_NewEra/modules/lfg/Raids.lua — the Raids pane: 3.3.5a Raid Browser (LFR) in the
-- Group Finder window's right side, with two sub-modes matching the native LFRParentFrame tabs:
--   QUEUE  — list yourself (or your group) for raids: raid multi-select + comment + List Me
--   BROWSE — browse players/groups listed for one raid: dropdown + results + whisper/invite
--
-- Same architecture as Dungeons.lua: the native hidden LFRParentFrame family stays the state
-- machine. We mutate through NATIVE helpers (LFRList_SetRaidEnabled / LFRList_SetHeaderEnabled /
-- LFRList_SetHeaderCollapsed / LFRQueueFrame_Join / LeaveLFG / SearchLFGJoin / SearchLFGLeave)
-- and mirror NATIVE state fields other code reads (LFRQueueFrame.selectedLFM for the in-group
-- radio pick, LFRBrowseFrame.selectedName/.selectedType for the browse selection, and the
-- native LFRQueueFrameComment editbox text that LFRQueueFrame_Join submits).
--
-- 3.3.5a rules honored: FauxScrollFrames are NAMED, no SetShown, no MaskTexture.

local NE = DragonUI_NewEra
if not NE then return end

NE.lfg = NE.lfg or {}
local L = NE.lfg

local NUM_RAID_ROWS, ROW_H = 15, 16
local NUM_BROWSE_ROWS = 15
local RAID_SCROLL = "NE_LFGRaidListScrollFrame"
local BROWSE_SCROLL = "NE_LFGBrowseListScrollFrame"
local BROWSE_DROPDOWN = "NE_LFGRaidBrowseDropDown"
local AUTO_REFRESH = LFR_BROWSE_AUTO_REFRESH_TIME or 20

local pane

local function lfrEmpowered()
  if type(LFR_IsEmpowered) == "function" then return LFR_IsEmpowered() end
  return true
end

local function skinButton(btn)
  if NE.buttonskin and NE.buttonskin.Skin then pcall(NE.buttonskin.Skin, btn) end
end

-- ===========================================================================
-- QUEUE sub-mode
-- ===========================================================================

-- Raid list rows — port of LFRQueueFrameSpecificListButton_SetDungeon, including the
-- checkbox↔radio flip: solo players multi-select (checkboxes), grouped players pick ONE raid
-- to advertise for (radio → LFRQueueFrame.selectedLFM, the native field LFRQueueFrame_Join reads).
local function raidCheck_OnClick(self)
  local parent = self:GetParent()
  local dungeonID = parent.id
  local isChecked = self:GetChecked() and true or false
  PlaySound(isChecked and "igMainMenuOptionCheckBoxOn" or "igMainMenuOptionCheckBoxOff")
  if LFGIsIDHeader(dungeonID) then
    LFRList_SetHeaderEnabled(dungeonID, isChecked)
  elseif LFR_CanQueueForMultiple() then
    LFRList_SetRaidEnabled(dungeonID, isChecked)
    LFGListUpdateHeaderEnabledAndLockedStates(LFRRaidList, LFGEnabledList, LFGLockList, LFRHiddenByCollapseList)
  else
    LFRQueueFrame.selectedLFM = dungeonID
  end
  L.RefreshRaids()
end

local function makeRaidRow(parent)
  local b = CreateFrame("Button", nil, parent)
  b:SetSize(298, ROW_H)

  local expand = CreateFrame("Button", nil, b)
  expand:SetSize(14, 14)
  expand:SetPoint("LEFT", b, "LEFT", 0, 0)
  expand:SetNormalTexture("Interface\\Buttons\\UI-MinusButton-UP")
  expand:SetHighlightTexture("Interface\\Buttons\\UI-PlusButton-Hilight")
  expand:SetScript("OnClick", function(self)
    local p = self:GetParent()
    LFRList_SetHeaderCollapsed(p.id, not p.isCollapsed)
    L.RefreshRaids()
  end)
  b.expandOrCollapseButton = expand

  local check = CreateFrame("CheckButton", nil, b)
  check:SetSize(ROW_H, ROW_H)
  check:SetPoint("LEFT", b, "LEFT", 16, 0)
  check:SetScript("OnClick", raidCheck_OnClick)
  local chl = check:CreateTexture(nil, "HIGHLIGHT")
  chl:SetTexture("Interface\\Buttons\\UI-CheckBox-Highlight")
  chl:SetAllPoints(check); chl:SetBlendMode("ADD")
  if LFGSpecificChoiceEnableButton_SetIsRadio then
    LFGSpecificChoiceEnableButton_SetIsRadio(check, false)
  end
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
  lock:SetScript("OnEnter", function(self)
    -- Raid lockout tooltip: same INSTANCE_UNAVAILABLE_ codes as the dungeon list.
    local dungeonID = self:GetParent().id
    if LFGIsIDHeader(dungeonID) then return end
    GameTooltip:SetOwner(self, "ANCHOR_TOP")
    GameTooltip:AddLine(YOU_MAY_NOT_QUEUE_FOR_DUNGEON or "You may not list for this raid", 1, 1, 1)
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
  end)
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

local function paintRaidRow(b, dungeonID, mode)
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
    if mode == "rolecheck" or mode == "queued" or mode == "listed" or not lfrEmpowered() then
      b.instanceName:SetFontObject(QuestDifficulty_Header or GameFontNormal)
    else
      b.instanceName:SetFontObject(difficultyColor.font)
    end
    b.expandOrCollapseButton:Hide()
    b.isCollapsed = false
  end

  -- Lock/checkbox visibility — grouped players may list for locked raids (native rule).
  if not LFR_CanQueueForLockedInstances() and LFGLockList and LFGLockList[dungeonID] then
    b.enableButton:Hide()
    b.lockedIndicator:Show()
  else
    if LFR_CanQueueForMultiple() then
      b.enableButton:Show()
      LFGSpecificChoiceEnableButton_SetIsRadio(b.enableButton, false)
    else
      if LFGIsIDHeader(dungeonID) then
        b.enableButton:Hide()
      else
        b.enableButton:Show()
        LFGSpecificChoiceEnableButton_SetIsRadio(b.enableButton, true)
      end
    end
    b.lockedIndicator:Hide()
  end

  local enableState
  if mode == "queued" or mode == "listed" then
    enableState = LFGQueuedForList and LFGQueuedForList[dungeonID]
  elseif not LFR_CanQueueForMultiple() then
    enableState = (dungeonID == (LFRQueueFrame and LFRQueueFrame.selectedLFM))
  else
    enableState = LFGEnabledList and LFGEnabledList[dungeonID]
  end

  if LFR_CanQueueForMultiple() then
    if enableState == 1 then
      b.enableButton:SetCheckedTexture("Interface\\Buttons\\UI-MultiCheck-Up")
      b.enableButton:SetDisabledCheckedTexture("Interface\\Buttons\\UI-MultiCheck-Disabled")
    else
      b.enableButton:SetCheckedTexture("Interface\\Buttons\\UI-CheckBox-Check")
      b.enableButton:SetDisabledCheckedTexture("Interface\\Buttons\\UI-CheckBox-Check-Disabled")
    end
    b.enableButton:SetChecked(enableState and enableState ~= 0)
  else
    b.enableButton:SetChecked(enableState)
  end

  if mode == "rolecheck" or mode == "queued" or mode == "listed" or not lfrEmpowered() then
    b.enableButton:Disable()
  else
    b.enableButton:Enable()
  end
end

local function updateRaidList()
  local scroll = pane.raidScroll
  FauxScrollFrame_Update(scroll, LFRGetNumDungeons and LFRGetNumDungeons() or 0, NUM_RAID_ROWS, ROW_H)
  local offset = FauxScrollFrame_GetOffset(scroll)
  local mode = GetLFGMode()
  for i = 1, NUM_RAID_ROWS do
    local dungeonID = LFRRaidList and LFRRaidList[i + offset]
    if dungeonID then
      paintRaidRow(pane.raidRows[i], dungeonID, mode)
    else
      pane.raidRows[i]:Hide()
    end
  end
  if LFRRaidList and LFRRaidList[1] then
    pane.noRaids:Hide()
  else
    pane.noRaids:Show()
  end
end

-- Comment sync — port of LFRFrame_OnEvent's LFG_UPDATE branch. Our editbox mirrors into the
-- native LFRQueueFrameComment (which LFRQueueFrame_Join submits) and pulls the server value in
-- when idle.
local function syncCommentFromServer()
  local eb = pane.comment
  local _, joined, _, _, _, lfgComment = GetLFGInfoServer()
  if not lfrEmpowered() or (not eb:HasFocus() and eb:GetText() == "") then
    if joined and lfgComment then
      eb:SetText(lfgComment)
    end
    eb:ClearFocus()
  end
end

local function updateListButton()
  local btn = pane.listButton
  local mode = GetLFGMode()
  local grouped = GetNumPartyMembers() > 0 or GetNumRaidMembers() > 0
  if mode == "listed" then
    btn:SetText(grouped and (UNLIST_MY_GROUP or "Unlist My Group") or (UNLIST_ME or "Unlist Me"))
  else
    btn:SetText(grouped and (LIST_MY_GROUP or "List My Group") or (LIST_ME or "List Me"))
  end
  if lfrEmpowered() and mode ~= "proposal" and mode ~= "queued" and mode ~= "rolecheck"
     and (not LFRRaidList or LFRRaidList[1]) then
    btn:Enable()
  else
    btn:Disable()
  end

  local status = pane.queueStatus
  if mode == "queued" or mode == "rolecheck" or mode == "proposal" then
    status:SetText("|cffff2020" .. (NO_LFR_WHILE_LFD or "You cannot list for raids while in the Dungeon Finder queue.") .. "|r")
  elseif mode == "listed" then
    status:SetText(LFR_QUEUE_PENDING_MESSAGE or "You are listed in the Raid Browser.")
  else
    status:SetText("")
  end
end

-- ===========================================================================
-- BROWSE sub-mode
-- ===========================================================================

-- Raid picker — port of LFRBrowseFrameRaidDropDown_Initialize (two menu levels). Reuses the
-- native GetFullRaidList() builder + selection via SearchLFGGetJoinedID.
local fullRaidHeaderOrder, fullRaidList

local function browseDropDown_OnClick(self)
  UIDropDownMenu_SetSelectedValue(_G[BROWSE_DROPDOWN], self.value)
  if HideDropDownMenu then HideDropDownMenu(1) end
  if self.value == "none" then
    SearchLFGLeave()
  else
    local info = LFGGetDungeonInfoByID(self.value)
    SearchLFGJoin(info[LFG_RETURN_VALUES.typeID], self.value)
  end
end

local function browseDropDown_Initialize(self, level)
  if LFGDungeonList_Setup then LFGDungeonList_Setup() end
  if not fullRaidHeaderOrder and GetFullRaidList then
    fullRaidHeaderOrder, fullRaidList = GetFullRaidList()
  end
  if not fullRaidHeaderOrder then return end

  local activeSearching = (SearchLFGGetJoinedID and SearchLFGGetJoinedID()) or "none"
  local info = UIDropDownMenu_CreateInfo()

  if not level or level == 1 then
    info.text = NONE or "None"
    info.value = "none"
    info.func = browseDropDown_OnClick
    info.checked = activeSearching == info.value
    UIDropDownMenu_AddButton(info)

    for _, groupID in ipairs(fullRaidHeaderOrder) do
      info.text = LFGGetDungeonInfoByID(groupID)[LFG_RETURN_VALUES.name]
      info.value = groupID
      info.func = nil
      info.hasArrow = true
      info.checked = false
      UIDropDownMenu_AddButton(info, 1)
    end
  elseif level == 2 then
    for _, dungeonID in ipairs(fullRaidList[UIDROPDOWNMENU_MENU_VALUE] or {}) do
      local dinfo = LFGGetDungeonInfoByID(dungeonID)
      local maxPlayers = format(LFD_LEVEL_FORMAT_SINGLE or "(%d)", dinfo[LFG_RETURN_VALUES.maxPlayers])
      info.text = maxPlayers .. " " .. dinfo[LFG_RETURN_VALUES.name]
      info.value = dungeonID
      info.func = browseDropDown_OnClick
      info.hasArrow = nil
      info.checked = activeSearching == dungeonID
      UIDropDownMenu_AddButton(info, level)
    end
  end
end

-- Result rows — the reference LFGList row look (screenshot rows: class-colored name, level,
-- role/party icons at right), data from SearchLFGGetResults. Tooltip + selection mirror the
-- native handlers; the tooltip IS the native handler (only needs self.index).
local function browseRow_OnClick(self)
  if not LFRBrowseFrame then return end
  if LFRBrowseFrame.selectedName == self.unitName then
    PlaySound("igMainMenuOptionCheckBoxOff")
    LFRBrowseFrame.selectedName = nil
    LFRBrowseFrame.selectedType = nil
  else
    PlaySound("igMainMenuOptionCheckBoxOn")
    LFRBrowseFrame.selectedName = self.unitName
    LFRBrowseFrame.selectedType = self.type
  end
  L.RefreshRaids()
end

local function makeBrowseRow(parent)
  local b = CreateFrame("Button", nil, parent)
  b:SetSize(298, ROW_H)

  local name = b:CreateFontString(nil, "ARTWORK", "GameFontNormal")
  name:SetPoint("LEFT", b, "LEFT", 4, 0)
  name:SetWidth(110); name:SetJustifyH("LEFT")
  b.name = name

  local level = b:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
  level:SetPoint("LEFT", b, "LEFT", 118, 0)
  level:SetWidth(24); level:SetJustifyH("RIGHT")
  b.level = level

  local class = b:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
  class:SetPoint("LEFT", level, "RIGHT", 6, 0)
  class:SetWidth(78); class:SetJustifyH("LEFT")
  b.class = class

  -- Role / party icons, right-aligned (modern micro icons; party keeps the native eye-group art).
  local function microIcon(atlas, natCoords)
    local t = b:CreateTexture(nil, "ARTWORK")
    t:SetSize(14, 14)
    if not (NE.tex and NE.tex.SetAtlas and NE.tex.SetAtlas(t, atlas, false)) then
      t:SetTexture("Interface\\LFGFrame\\LFGRole")
      t:SetTexCoord(unpack(natCoords))
    end
    t:Hide()
    return t
  end
  b.damageIcon = microIcon("groupfinder-icon-role-micro-dps",  { 0.25, 0.5, 0, 1 })
  b.damageIcon:SetPoint("RIGHT", b, "RIGHT", -4, 0)
  b.healerIcon = microIcon("groupfinder-icon-role-micro-heal", { 0.75, 1, 0, 1 })
  b.healerIcon:SetPoint("RIGHT", b.damageIcon, "LEFT", -2, 0)
  b.tankIcon = microIcon("groupfinder-icon-role-micro-tank",   { 0.5, 0.75, 0, 1 })
  b.tankIcon:SetPoint("RIGHT", b.healerIcon, "LEFT", -2, 0)
  local party = b:CreateTexture(nil, "ARTWORK")
  party:SetSize(14, 14)
  party:SetTexture("Interface\\LFGFrame\\LFGRole")
  party:SetTexCoord(0, 0.25, 0, 1)
  party:SetPoint("RIGHT", b, "RIGHT", -4, 0)
  party:Hide()
  b.partyIcon = party

  local hl = b:CreateTexture(nil, "HIGHLIGHT")
  hl:SetTexture(0.3, 0.45, 0.8)
  hl:SetAlpha(0.25)
  hl:SetAllPoints(b)

  local sel = b:CreateTexture(nil, "BACKGROUND")
  sel:SetTexture(0.3, 0.45, 0.8)
  sel:SetAlpha(0.35)
  sel:SetAllPoints(b)
  sel:Hide()
  b.selected = sel

  b:SetScript("OnClick", browseRow_OnClick)
  b:SetScript("OnEnter", function(self)
    if LFRBrowseButton_OnEnter and self.index then LFRBrowseButton_OnEnter(self) end
  end)
  b:SetScript("OnLeave", function() GameTooltip:Hide() end)
  return b
end

-- Port of LFRBrowseFrameListButton_SetData.
local function paintBrowseRow(b, index)
  local name, level, _, className, _, partyMembers, _, class, _, _, _, isTank, isHealer, isDamage = SearchLFGGetResults(index)
  b.index = index
  b.unitName = name
  b:Show()

  if LFRBrowseFrame and LFRBrowseFrame.selectedName == name then b.selected:Show() else b.selected:Hide() end

  b.name:SetText(name)
  b.level:SetText(level)
  local classColor = (class and RAID_CLASS_COLORS[class]) or NORMAL_FONT_COLOR
  b.class:SetText(className or "")
  b.class:SetTextColor(classColor.r, classColor.g, classColor.b)

  if partyMembers and partyMembers > 0 then
    b.type = "party"
    b.partyIcon:Show()
    b.tankIcon:Hide(); b.healerIcon:Hide(); b.damageIcon:Hide()
  else
    b.type = "individual"
    b.partyIcon:Hide()
    if isTank then b.tankIcon:Show() else b.tankIcon:Hide() end
    if isHealer then b.healerIcon:Show() else b.healerIcon:Hide() end
    if isDamage then b.damageIcon:Show() else b.damageIcon:Hide() end
  end

  if name == UnitName("player") then
    b:Disable()
    b.name:SetTextColor(GRAY_FONT_COLOR.r, GRAY_FONT_COLOR.g, GRAY_FONT_COLOR.b)
  else
    b:Enable()
    b.name:SetTextColor(classColor.r, classColor.g, classColor.b)
  end
end

local function updateBrowseList()
  local scroll = pane.browseScroll
  local numResults = SearchLFGGetNumResults and SearchLFGGetNumResults() or 0
  FauxScrollFrame_Update(scroll, numResults, NUM_BROWSE_ROWS, ROW_H)
  local offset = FauxScrollFrame_GetOffset(scroll)
  for i = 1, NUM_BROWSE_ROWS do
    if i + offset <= numResults then
      paintBrowseRow(pane.browseRows[i], i + offset)
    else
      pane.browseRows[i]:Hide()
    end
  end

  -- Drop a selection whose row left the results (native behavior).
  if LFRBrowseFrame and LFRBrowseFrame.selectedName then
    local stillThere = false
    for i = 1, numResults do
      if SearchLFGGetResults(i) == LFRBrowseFrame.selectedName then stillThere = true break end
    end
    if not stillThere then
      LFRBrowseFrame.selectedName = nil
      LFRBrowseFrame.selectedType = nil
    end
  end

  local joined = (SearchLFGGetJoinedID and SearchLFGGetJoinedID()) or "none"
  UIDropDownMenu_SetSelectedValue(pane.browseDropdown, joined)
  local ddText = _G[BROWSE_DROPDOWN .. "Text"]
  if ddText then
    -- Direct label write — see native LFRFrame.lua:391 (SetSelectedValue's refresh only works
    -- while the shared DropDownList still holds our buttons).
    if joined == "none" then
      ddText:SetText(NONE or "None")
    else
      local info = LFGGetDungeonInfoByID and LFGGetDungeonInfoByID(joined)
      ddText:SetText(info and info[LFG_RETURN_VALUES.name] or "")
    end
  end

  -- Port of LFRBrowse_UpdateButtonStates.
  local playerName = UnitName("player")
  local selectedName = LFRBrowseFrame and LFRBrowseFrame.selectedName
  if selectedName and selectedName ~= playerName then
    pane.messageButton:Enable()
  else
    pane.messageButton:Disable()
  end
  if selectedName and selectedName ~= playerName and (LFRBrowseFrame and LFRBrowseFrame.selectedType) ~= "party"
     and CanGroupInvite() then
    pane.inviteButton:Enable()
  else
    pane.inviteButton:Disable()
  end
end

-- ===========================================================================
-- Sub-mode switching + refresh entry
-- ===========================================================================

local function setSubMode(mode)   -- "QUEUE" | "BROWSE"
  pane.subMode = mode
  local queue = (mode == "QUEUE")
  if queue then
    pane.queuePanel:Show(); pane.browsePanel:Hide()
    pane.listButton:Show(); pane.queueStatus:Show()
    pane.messageButton:Hide(); pane.inviteButton:Hide()
  else
    pane.queuePanel:Hide(); pane.browsePanel:Show()
    pane.listButton:Hide(); pane.queueStatus:Hide()
    pane.messageButton:Show(); pane.inviteButton:Show()
    if RefreshLFGList then RefreshLFGList() end
  end
  -- Tab highlight states.
  pane.queueTab:SetEnabled(not queue)
  pane.browseTab:SetEnabled(queue)
  L.RefreshRaids()
end

function L.RefreshRaids()
  if not (pane and pane:IsVisible()) then return end

  if LFRQueueFrame_Update then LFRQueueFrame_Update() end

  if pane.subMode == "BROWSE" then
    updateBrowseList()
  else
    updateRaidList()
    syncCommentFromServer()
    pane.roleRow:Refresh()
    updateListButton()
  end
end

-- ===========================================================================
-- Pane construction
-- ===========================================================================

local function makeSubTab(parent, text)
  local b = CreateFrame("Button", nil, parent)
  b:SetSize(90, 22)
  local fs = b:CreateFontString(nil, "ARTWORK", "GameFontNormal")
  fs:SetPoint("CENTER")
  fs:SetText(text)
  b:SetFontString(fs)
  b:SetNormalFontObject(GameFontNormal)
  b:SetHighlightFontObject(GameFontHighlight)
  b:SetDisabledFontObject(GameFontHighlight)   -- "disabled" = the ACTIVE tab → white text
  local underline = b:CreateTexture(nil, "ARTWORK")
  underline:SetHeight(2)
  underline:SetPoint("BOTTOMLEFT", b, "BOTTOMLEFT", 8, 0)
  underline:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", -8, 0)
  underline:SetTexture(1, 0.82, 0)
  underline:Hide()
  b.underline = underline
  -- The active tab shows the gold underline; SetEnabled drives it (see setSubMode).
  b.SetEnabled = function(self, enabled)
    if enabled then self:Enable(); self.underline:Hide()
    else self:Disable(); self.underline:Show() end
  end
  return b
end

local function buildPane(host)
  pane = CreateFrame("Frame", nil, host)
  pane:SetAllPoints(host)
  pane:Hide()

  -- Header: sub-tabs (left) + role row (right — LFR has no leader box, native parity).
  local queueTab = makeSubTab(pane, LFR_QUEUE_TAB or QUEUE or "Queue")
  queueTab:SetPoint("TOPLEFT", pane, "TOPLEFT", 2, -10)
  queueTab:SetScript("OnClick", function() PlaySound("igCharacterInfoTab"); setSubMode("QUEUE") end)
  pane.queueTab = queueTab

  local browseTab = makeSubTab(pane, LFR_BROWSE_TAB or BROWSE or "Browse")
  browseTab:SetPoint("LEFT", queueTab, "RIGHT", 4, 0)
  browseTab:SetScript("OnClick", function() PlaySound("igCharacterInfoTab"); setSubMode("BROWSE") end)
  pane.browseTab = browseTab

  local roleRow = L.NewRoleRow(pane, { size = 30, gap = 6, onChange = L.RefreshRaids })
  roleRow:SetPoint("TOPRIGHT", pane, "TOPRIGHT", -6, -8)
  pane.roleRow = roleRow

  -- Content inset (same rect as the Dungeons pane, same retail dark fill).
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

  -- ---------------- QUEUE sub-panel ----------------
  local qp = CreateFrame("Frame", nil, inset)
  qp:SetAllPoints(inset)
  pane.queuePanel = qp

  local raidScroll = CreateFrame("ScrollFrame", RAID_SCROLL, qp, "FauxScrollFrameTemplate")
  raidScroll:SetPoint("TOPLEFT", qp, "TOPLEFT", 4, -4)
  raidScroll:SetPoint("BOTTOMRIGHT", qp, "BOTTOMRIGHT", -26, 66)
  raidScroll:SetScript("OnVerticalScroll", function(self, offset)
    FauxScrollFrame_OnVerticalScroll(self, offset, ROW_H, updateRaidList)
  end)
  raidScroll.ScrollBar = _G[RAID_SCROLL .. "ScrollBar"]   -- 3.3.5a template doesn't set the parentKey
  -- Hand-built minimal scrollbar (same as the character window's lists). NE.scrollbar.Reskin's
  -- stock-slider re-skin leaves the bar untextured/invisible on 3.3.5a; BuildCustom draws a
  -- visible bar. See modules/character/Reputation.lua.
  -- Via L.BuildListBar, not BuildCustom directly -- it adds the DIALOG strata bump this window
  -- needs for the bar to render in front of its own background at all (see Window.lua).
  L.BuildListBar(raidScroll, { x = -8, alwaysShow = true })
  raidScroll:EnableMouseWheel(true)
  raidScroll:SetScript("OnMouseWheel", function(self, delta)
    local sb = self.ScrollBar
    if not sb then return end
    local mn, mx = sb:GetMinMaxValues()
    local v = sb:GetValue() - delta * ROW_H
    if v < mn then v = mn elseif v > mx then v = mx end
    sb:SetValue(v)
  end)
  pane.raidScroll = raidScroll

  pane.raidRows = {}
  for i = 1, NUM_RAID_ROWS do
    local row = makeRaidRow(qp)
    if i == 1 then row:SetPoint("TOPLEFT", qp, "TOPLEFT", 6, -5)
    else row:SetPoint("TOPLEFT", pane.raidRows[i - 1], "BOTTOMLEFT", 0, 0) end
    pane.raidRows[i] = row
  end

  local noRaids = qp:CreateFontString(nil, "ARTWORK", "GameFontDisable")
  noRaids:SetPoint("CENTER", qp, "CENTER", 0, 30)
  noRaids:SetText(NO_RAIDS_AVAILABLE or "There are no raids available for your level.")
  noRaids:Hide()
  pane.noRaids = noRaids

  -- Comment box (mirrors into the native LFRQueueFrameComment — see syncCommentFromServer).
  local commentLabel = qp:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
  commentLabel:SetPoint("BOTTOMLEFT", qp, "BOTTOMLEFT", 8, 46)
  commentLabel:SetText(LFG_COMMENT or COMMENT or "Comment")

  local commentBox = CreateFrame("Frame", nil, qp)
  commentBox:SetPoint("BOTTOMLEFT", qp, "BOTTOMLEFT", 6, 6)
  commentBox:SetPoint("BOTTOMRIGHT", qp, "BOTTOMRIGHT", -6, 6)
  commentBox:SetHeight(38)
  commentBox:SetBackdrop({
    bgFile = "Interface\\ChatFrame\\ChatFrameBackground",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    tile = true, tileSize = 16, edgeSize = 12,
    insets = { left = 3, right = 3, top = 3, bottom = 3 },
  })
  commentBox:SetBackdropColor(0, 0, 0, 0.5)
  commentBox:SetBackdropBorderColor(0.5, 0.5, 0.5)

  local comment = CreateFrame("EditBox", nil, commentBox)
  comment:SetPoint("TOPLEFT", commentBox, "TOPLEFT", 8, -6)
  comment:SetPoint("BOTTOMRIGHT", commentBox, "BOTTOMRIGHT", -8, 6)
  comment:SetAutoFocus(false)
  comment:SetMaxLetters(64)
  comment:SetFontObject(GameFontHighlightSmall)
  comment:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
  comment:SetScript("OnEnterPressed", function(self)
    self:ClearFocus()
    if SetLFGComment then SetLFGComment(self:GetText()) end
  end)
  comment:SetScript("OnTextChanged", function(self)
    -- Mirror into the native editbox that LFRQueueFrame_Join submits.
    if _G.LFRQueueFrameComment and _G.LFRQueueFrameComment:GetText() ~= self:GetText() then
      _G.LFRQueueFrameComment:SetText(self:GetText())
    end
  end)
  pane.comment = comment

  -- ---------------- BROWSE sub-panel ----------------
  local bp = CreateFrame("Frame", nil, inset)
  bp:SetAllPoints(inset)
  bp:Hide()
  pane.browsePanel = bp

  local ddLabel = bp:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
  ddLabel:SetPoint("TOPLEFT", bp, "TOPLEFT", 10, -12)
  ddLabel:SetText(RAID or "Raid")

  local bdd = CreateFrame("Frame", BROWSE_DROPDOWN, bp, "UIDropDownMenuTemplate")
  bdd:SetPoint("TOPLEFT", bp, "TOPLEFT", 24, -4)
  UIDropDownMenu_SetWidth(bdd, 150)
  UIDropDownMenu_Initialize(bdd, browseDropDown_Initialize)
  UIDropDownMenu_SetSelectedValue(bdd, "none")
  pane.browseDropdown = bdd

  local refresh = CreateFrame("Button", nil, bp, "UIPanelButtonTemplate")
  refresh:SetSize(80, 22)
  refresh:SetPoint("TOPRIGHT", bp, "TOPRIGHT", -8, -8)
  refresh:SetText(REFRESH or "Refresh")
  refresh:SetScript("OnClick", function()
    if RefreshLFGList then RefreshLFGList() end
  end)
  skinButton(refresh)

  local browseScroll = CreateFrame("ScrollFrame", BROWSE_SCROLL, bp, "FauxScrollFrameTemplate")
  browseScroll:SetPoint("TOPLEFT", bp, "TOPLEFT", 4, -34)
  browseScroll:SetPoint("BOTTOMRIGHT", bp, "BOTTOMRIGHT", -26, 4)
  browseScroll:SetScript("OnVerticalScroll", function(self, offset)
    FauxScrollFrame_OnVerticalScroll(self, offset, ROW_H, updateBrowseList)
  end)
  browseScroll.ScrollBar = _G[BROWSE_SCROLL .. "ScrollBar"]   -- 3.3.5a template doesn't set the parentKey
  -- Hand-built minimal scrollbar (same as the character window's lists) — see raidScroll above.
  L.BuildListBar(browseScroll, { x = -8, alwaysShow = true })
  browseScroll:EnableMouseWheel(true)
  browseScroll:SetScript("OnMouseWheel", function(self, delta)
    local sb = self.ScrollBar
    if not sb then return end
    local mn, mx = sb:GetMinMaxValues()
    local v = sb:GetValue() - delta * ROW_H
    if v < mn then v = mn elseif v > mx then v = mx end
    sb:SetValue(v)
  end)
  pane.browseScroll = browseScroll

  pane.browseRows = {}
  for i = 1, NUM_BROWSE_ROWS do
    local row = makeBrowseRow(bp)
    if i == 1 then row:SetPoint("TOPLEFT", bp, "TOPLEFT", 6, -35)
    else row:SetPoint("TOPLEFT", pane.browseRows[i - 1], "BOTTOMLEFT", 0, 0) end
    pane.browseRows[i] = row
  end

  -- Browse auto-refresh (native LFR_BROWSE_AUTO_REFRESH_TIME cadence, only while visible).
  local acc = 0
  bp:SetScript("OnUpdate", function(_, elapsed)
    acc = acc + elapsed
    if acc >= AUTO_REFRESH then
      acc = 0
      if RefreshLFGList then RefreshLFGList() end
    end
  end)

  -- ---------------- Bottom band ----------------
  local list = CreateFrame("Button", nil, pane, "UIPanelButtonTemplate")
  list:SetSize(135, 22)
  list:SetPoint("BOTTOMRIGHT", pane, "BOTTOMRIGHT", -2, 6)
  list:SetScript("OnClick", function()
    local mode = GetLFGMode()
    if mode == "listed" then
      LeaveLFG()
    else
      LFRQueueFrame_Join()
    end
    L.RefreshRaids()
    if L.frame and L.frame.UpdateEye then L.frame.UpdateEye() end
  end)
  skinButton(list)
  pane.listButton = list

  local queueStatus = pane:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
  queueStatus:SetPoint("BOTTOMLEFT", pane, "BOTTOMLEFT", 6, 8)
  queueStatus:SetPoint("RIGHT", list, "LEFT", -6, 0)
  queueStatus:SetJustifyH("LEFT")
  pane.queueStatus = queueStatus

  local message = CreateFrame("Button", nil, pane, "UIPanelButtonTemplate")
  message:SetSize(110, 22)
  message:SetPoint("BOTTOMLEFT", pane, "BOTTOMLEFT", 4, 6)
  message:SetText(SEND_MESSAGE or "Send Message")
  message:SetScript("OnClick", function()
    PlaySound("UChatScrollButton")
    if LFRBrowseFrame and LFRBrowseFrame.selectedName and ChatFrame_SendTell then
      ChatFrame_SendTell(LFRBrowseFrame.selectedName)
    end
  end)
  skinButton(message)
  message:Hide()
  pane.messageButton = message

  local invite = CreateFrame("Button", nil, pane, "UIPanelButtonTemplate")
  invite:SetSize(90, 22)
  invite:SetPoint("LEFT", message, "RIGHT", 4, 0)
  invite:SetText(INVITE or "Invite")
  invite:SetScript("OnClick", function()
    PlaySound("UChatScrollButton")
    if LFRBrowseFrame and LFRBrowseFrame.selectedName and InviteUnit then
      InviteUnit(LFRBrowseFrame.selectedName)
    end
  end)
  skinButton(invite)
  invite:Hide()
  pane.inviteButton = invite

  -- Live wiring (gated on visibility inside L.RefreshRaids).
  local ev = CreateFrame("Frame")
  ev:RegisterEvent("UPDATE_LFG_LIST")
  ev:RegisterEvent("LFG_UPDATE")
  ev:RegisterEvent("LFG_LOCK_INFO_RECEIVED")
  ev:RegisterEvent("LFG_ROLE_UPDATE")
  ev:RegisterEvent("PARTY_MEMBERS_CHANGED")
  ev:RegisterEvent("PLAYER_ENTERING_WORLD")
  ev:SetScript("OnEvent", function()
    L.RefreshRaids()
    if L.frame and L.frame.UpdateEye then L.frame.UpdateEye() end
  end)

  setSubMode("QUEUE")
  pane.OnPaneShow = function() L.RefreshRaids() end
  return pane
end

if L.RegisterPane then L.RegisterPane("RAIDS", buildPane) end
