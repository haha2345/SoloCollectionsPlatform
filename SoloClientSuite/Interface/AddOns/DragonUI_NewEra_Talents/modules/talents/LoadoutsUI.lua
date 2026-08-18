-- DragonUI_NewEra/modules/talents/LoadoutsUI.lua — talent loadouts UI (Phase 2a).
--
-- The user-facing layer over Loadouts.lua (the data layer): a "Loadouts" button on the talent
-- window's bottom bar that opens a panel listing saved builds, with Save current / Import / Export /
-- Load / Rename / Delete, plus the "Server uses custom talents" guard toggle + server label.
--
-- Apply path: Load stages the build into the live preview (Loadouts.T.LO_StageBuild) and the user
-- commits with the existing bottom-bar Apply button. Import runs the compatibility guard
-- (T.LO_ImportString) and routes a mismatch through a confirm dialog before saving.

local NE = DragonUI_NewEra
local T = NE.talents or {}
NE.talents = T

local ROWS  = 9      -- visible saved-build rows
local ROW_H = 22

-- ----------------------------------------------------------------------------
-- StaticPopups (text I/O — single-line edit boxes, the untainted 3.3.5a way).
-- ----------------------------------------------------------------------------
local function refresh() if T.LO_RefreshPanel then T.LO_RefreshPanel() end end
local function msg(s) DEFAULT_CHAT_FRAME:AddMessage("|cff66ccffLoadouts|r: " .. tostring(s)) end

StaticPopupDialogs["NE_TALENT_LO_SAVE"] = {
  text = "Name this loadout (saves your current spec):",
  button1 = SAVE or "Save", button2 = CANCEL or "Cancel",
  hasEditBox = 1, maxLetters = 40, timeout = 0, whileDead = 1, hideOnEscape = 1,
  OnAccept = function(self)
    local name = (self.editBox or self.EditBox):GetText()
    if name and name ~= "" then
      if T.LO_SaveCurrent(name) then msg("saved '" .. name .. "'.") else msg("could not save.") end
      refresh()
    end
  end,
  EditBoxOnEnterPressed = function(self) self:GetParent().button1:Click() end,
}

StaticPopupDialogs["NE_TALENT_LO_RENAME"] = {
  text = "Rename loadout:",
  button1 = OKAY or "OK", button2 = CANCEL or "Cancel",
  hasEditBox = 1, maxLetters = 40, timeout = 0, whileDead = 1, hideOnEscape = 1,
  OnShow = function(self) (self.editBox or self.EditBox):SetText(T._loSelected or "") end,
  OnAccept = function(self)
    local newName = (self.editBox or self.EditBox):GetText()
    if T._loSelected and newName and newName ~= "" then
      if T.LO_Rename(T._loSelected, newName) then T._loSelected = newName else msg("rename failed (name taken?).") end
      refresh()
    end
  end,
  EditBoxOnEnterPressed = function(self) self:GetParent().button1:Click() end,
}

StaticPopupDialogs["NE_TALENT_LO_DELETE"] = {
  text = "Delete loadout '%s'?",
  button1 = DELETE or "Delete", button2 = CANCEL or "Cancel",
  timeout = 0, whileDead = 1, hideOnEscape = 1, showAlert = 1,
  OnAccept = function() if T._loSelected then T.LO_Delete(T._loSelected); T._loSelected = nil; refresh() end end,
}

StaticPopupDialogs["NE_TALENT_LO_EXPORT"] = {
  text = "Copy this build string (Ctrl+C). Talented & the WoWhead/wotlkdb calculators import it too:",
  button1 = CLOSE or "Close",
  hasEditBox = 1, editBoxWidth = 260, timeout = 0, whileDead = 1, hideOnEscape = 1,
  OnShow = function(self)
    local eb = self.editBox or self.EditBox
    eb:SetText(T._loExportText or "")
    eb:HighlightText(); eb:SetFocus()
  end,
  EditBoxOnEscapePressed = function(self) self:GetParent():Hide() end,
}

StaticPopupDialogs["NE_TALENT_LO_IMPORT"] = {
  text = "Paste a talent string or calculator URL (Talented / WoWhead / wotlkdb):",
  button1 = OKAY or "OK", button2 = CANCEL or "Cancel",
  hasEditBox = 1, editBoxWidth = 260, maxLetters = 400, timeout = 0, whileDead = 1, hideOnEscape = 1,
  OnAccept = function(self) if T.LO_ImportFromText then T.LO_ImportFromText((self.editBox or self.EditBox):GetText()) end end,
  EditBoxOnEnterPressed = function(self) self:GetParent().button1:Click() end,
}

StaticPopupDialogs["NE_TALENT_LO_IMPORT_WARN"] = {
  text = "%s\n\nImport anyway?",
  button1 = YES or "Yes", button2 = NO or "No",
  timeout = 0, whileDead = 1, hideOnEscape = 1, showAlert = 1,
  OnAccept = function() StaticPopup_Show("NE_TALENT_LO_IMPORT_NAME") end,
}

StaticPopupDialogs["NE_TALENT_LO_IMPORT_NAME"] = {
  text = "Name this imported loadout:",
  button1 = SAVE or "Save", button2 = CANCEL or "Cancel",
  hasEditBox = 1, maxLetters = 40, timeout = 0, whileDead = 1, hideOnEscape = 1,
  OnAccept = function(self)
    local name = (self.editBox or self.EditBox):GetText()
    if name and name ~= "" and T._loPendingImport then
      T.LO_Save(name, T._loPendingImport); T._loPendingImport = nil; refresh()
      msg("imported '" .. name .. "'.")
    end
  end,
  EditBoxOnEnterPressed = function(self) self:GetParent().button1:Click() end,
}

StaticPopupDialogs["NE_TALENT_LO_CONFLICT"] = {
  text = "%s",
  button1 = OKAY or "OK",
  timeout = 0, whileDead = 1, hideOnEscape = 1, showAlert = 1,
}

-- ----------------------------------------------------------------------------
-- Flow helpers (referenced by the popups + buttons).
-- ----------------------------------------------------------------------------
function T.LO_ImportFromText(text)
  local build, verdict = T.LO_ImportString(text)
  if not build then msg(verdict and verdict.error or "could not read that string."); return end
  T._loPendingImport = build
  if verdict.warn then
    StaticPopupDialogs["NE_TALENT_LO_IMPORT_WARN"].text = verdict.reason .. "\n\nImport anyway?"
    StaticPopup_Show("NE_TALENT_LO_IMPORT_WARN")
  else
    StaticPopup_Show("NE_TALENT_LO_IMPORT_NAME")
  end
end

local function exportText(name)
  local code, url, tagged
  if name then code, url, tagged = T.LO_Encode(T.LO_Get(name)) else code, url, tagged = T.LO_ExportCurrent() end
  T._loExportText = tagged or code
  if T._loExportText then StaticPopup_Show("NE_TALENT_LO_EXPORT") else msg("nothing to export.") end
end

local function loadBuild(name)
  local b = T.LO_Get(name); if not b then return end
  local ok, conflicts = T.LO_StageBuild(b)
  if T.LO_HidePanel then T.LO_HidePanel() end
  if not ok and conflicts and #conflicts > 0 then
    local lines = {}
    for i = 1, math.min(#conflicts, 6) do
      local c = conflicts[i]; lines[#lines + 1] = ("  %s: have %d, build wants %d"):format(c.name, c.have or 0, c.want or 0)
    end
    StaticPopupDialogs["NE_TALENT_LO_CONFLICT"].text =
      "This loadout has fewer points in some talents than you've already spent, so it needs a respec first:\n"
      .. table.concat(lines, "\n")
      .. "\n\nReset at a class trainer, then load again. (The rest has been staged — click Apply to learn it.)"
    StaticPopup_Show("NE_TALENT_LO_CONFLICT")
  else
    msg("staged '" .. name .. "' — review the highlighted talents and click Apply to learn.")
  end
end

-- ----------------------------------------------------------------------------
-- The panel.
-- ----------------------------------------------------------------------------
local panel

local function styleButton(b)
  return b   -- UIPanelButtonTemplate already matches the bottom-bar Apply/Reset look
end

local function buildPanel()
  if panel then return panel end
  local host = T.frame or UIParent
  panel = CreateFrame("Frame", "NE_TalentLoadouts", host)
  panel:SetSize(380, 460)
  panel:SetPoint("CENTER", host, "CENTER", 0, 10)
  panel:SetFrameStrata("DIALOG")
  panel:EnableMouse(true)
  if panel.SetBackdrop then
    panel:SetBackdrop({
      bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
      edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
      tile = true, tileSize = 16, edgeSize = 16,
      insets = { left = 5, right = 5, top = 5, bottom = 5 },
    })
  end
  panel:Hide()

  local title = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
  title:SetPoint("TOP", 0, -14)
  title:SetText("Loadouts")

  local close = CreateFrame("Button", nil, panel, "UIPanelCloseButton")
  close:SetPoint("TOPRIGHT", -4, -4)

  -- Top actions: Save current, Import.
  local save = styleButton(CreateFrame("Button", nil, panel, "UIPanelButtonTemplate"))
  save:SetSize(150, 24); save:SetPoint("TOPLEFT", 16, -44); save:SetText("Save current spec…")
  save:SetScript("OnClick", function() StaticPopup_Show("NE_TALENT_LO_SAVE") end)

  local import = styleButton(CreateFrame("Button", nil, panel, "UIPanelButtonTemplate"))
  import:SetSize(150, 24); import:SetPoint("TOPRIGHT", -16, -44); import:SetText("Import…")
  import:SetScript("OnClick", function() StaticPopup_Show("NE_TALENT_LO_IMPORT") end)

  -- Saved-build list (FauxScrollFrame — must be NAMED on 3.3.5a).
  local listBG = CreateFrame("Frame", nil, panel)
  listBG:SetPoint("TOPLEFT", 16, -78)
  listBG:SetPoint("TOPRIGHT", -16, -78)
  listBG:SetHeight(ROWS * ROW_H + 8)
  if listBG.SetBackdrop then
    listBG:SetBackdrop({
      bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
      edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
      tile = true, tileSize = 16, edgeSize = 12, insets = { left = 3, right = 3, top = 3, bottom = 3 },
    })
    listBG:SetBackdropColor(0, 0, 0, 0.5)
  end

  local scroll = CreateFrame("ScrollFrame", "NE_TalentLoadoutsScroll", listBG, "FauxScrollFrameTemplate")
  scroll:SetPoint("TOPLEFT", 4, -4)
  scroll:SetPoint("BOTTOMRIGHT", -26, 4)
  scroll:SetScript("OnVerticalScroll", function(self, offset)
    FauxScrollFrame_OnVerticalScroll(self, offset, ROW_H, T.LO_RefreshPanel)
  end)
  panel.scroll = scroll

  panel.rows = {}
  for i = 1, ROWS do
    local row = CreateFrame("Button", nil, listBG)
    row:SetHeight(ROW_H)
    row:SetPoint("TOPLEFT", scroll, "TOPLEFT", 0, -((i - 1) * ROW_H))
    row:SetPoint("RIGHT", scroll, "RIGHT", 0, 0)
    local hl = row:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints(); hl:SetTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight")
    hl:SetBlendMode("ADD"); hl:SetAlpha(0.4)
    local sel = row:CreateTexture(nil, "ARTWORK")
    sel:SetAllPoints(); sel:SetTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight")
    sel:SetBlendMode("ADD"); sel:SetAlpha(0.55); sel:Hide()
    row.sel = sel
    row.name = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    row.name:SetPoint("LEFT", 6, 0)
    row.pts = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    row.pts:SetPoint("RIGHT", -8, 0)
    row:SetScript("OnClick", function(self)
      T._loSelected = self._name
      T.LO_RefreshPanel()
    end)
    panel.rows[i] = row
  end

  -- Per-selection actions.
  local function actBtn(label, x, w, onClick)
    local b = styleButton(CreateFrame("Button", nil, panel, "UIPanelButtonTemplate"))
    b:SetSize(w, 24)
    b:SetPoint("TOPLEFT", 16 + x, -(78 + ROWS * ROW_H + 16))
    b:SetText(label); b:SetScript("OnClick", onClick)
    return b
  end
  panel.bLoad   = actBtn("Load",   0,   84, function() if T._loSelected then loadBuild(T._loSelected) end end)
  panel.bExport = actBtn("Export", 88,  84, function() if T._loSelected then exportText(T._loSelected) end end)
  panel.bRename = actBtn("Rename", 176, 84, function() if T._loSelected then StaticPopup_Show("NE_TALENT_LO_RENAME") end end)
  panel.bDelete = actBtn("Delete", 264, 84, function() if T._loSelected then StaticPopup_Show("NE_TALENT_LO_DELETE", T._loSelected) end end)

  -- Custom-talent guard toggle. (The server label in exports/warnings is taken automatically from
  -- the realm name — see T.LO_ServerLabel — so there's no manual field to get wrong.)
  local cb = CreateFrame("CheckButton", "NE_TalentLoadoutsCustomCB", panel, "UICheckButtonTemplate")
  cb:SetPoint("BOTTOMLEFT", 14, 34)
  cb:SetSize(24, 24)
  local cbText = cb:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  cbText:SetPoint("LEFT", cb, "RIGHT", 2, 0)
  cbText:SetText("Server uses custom talents")
  cb:SetChecked(T.LO_IsCustomServer())
  cb:SetScript("OnClick", function(self) T.LO_SetCustomServer(self:GetChecked() and true or false) end)
  panel.cb = cb

  local hint = panel:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  hint:SetPoint("BOTTOMLEFT", 16, 16)
  hint:SetPoint("BOTTOMRIGHT", -16, 16)
  hint:SetJustifyH("LEFT")
  hint:SetText("Tags exported builds with this realm so imports onto other layouts warn first.")

  return panel
end

-- Rebuild the visible list + selection state from the store.
function T.LO_RefreshPanel()
  if not panel or not panel:IsShown() then return end
  local names = T.LO_List()
  local offset = FauxScrollFrame_GetOffset(panel.scroll) or 0
  FauxScrollFrame_Update(panel.scroll, #names, ROWS, ROW_H)
  for i = 1, ROWS do
    local row = panel.rows[i]
    local idx = i + offset
    local name = names[idx]
    if name then
      row._name = name
      row.name:SetText(name)
      row.pts:SetText(T.LO_Summary(T.LO_Get(name) or { ranks = {} }))
      if name == T._loSelected then row.sel:Show() else row.sel:Hide() end   -- no SetShown on 3.3.5a
      row:Show()
    else
      row._name = nil
      row:Hide()
    end
  end
  -- enable/disable per-selection buttons
  local has = T._loSelected and T.LO_Get(T._loSelected) and true or false
  for _, b in ipairs({ panel.bLoad, panel.bExport, panel.bRename, panel.bDelete }) do
    if b then if has then b:Enable() else b:Disable() end end
  end
  -- keep the guard widgets in sync
  if panel.cb then panel.cb:SetChecked(T.LO_IsCustomServer()) end
end

function T.LO_HidePanel() if panel then panel:Hide() end end
function T.LO_TogglePanel()
  buildPanel()
  if panel:IsShown() then panel:Hide() else
    panel:Show()
    T.LO_RefreshPanel()
  end
end

-- ----------------------------------------------------------------------------
-- Bottom-bar "Loadouts" button. Created lazily on the talent frame once it exists.
-- ----------------------------------------------------------------------------
local function ensureBarButton()
  local f = T.frame
  if not f or f._loBtn then return end
  local b = CreateFrame("Button", "NE_TalentLoadoutsButton", f, "UIPanelButtonTemplate")
  b:SetSize(120, 26)
  b:SetPoint("BOTTOM", f, "BOTTOM", 0, ((T.FRAME and T.FRAME.CHROME_B) or 0) + 27)
  b:SetText("Loadouts")
  b:SetScript("OnClick", function() T.LO_TogglePanel() end)
  f._loBtn = b
end

-- The scaffold calls T.Populate on show; piggyback to make sure our button exists. We wrap it once.
local function hookPopulate()
  if T._loPopulateHooked then return end
  local orig = T.Populate
  if type(orig) ~= "function" then return end
  T._loPopulateHooked = true
  T.Populate = function(...)
    local r = orig(...)
    ensureBarButton()
    return r
  end
end

-- Loadouts.lua + Behavior.lua load before us (toc order), so T.Populate already exists.
hookPopulate()
