-- DragonUI_NewEra/modules/lfg/Roles.lua — shared role-selection row (Dungeons + Raids panes).
--
-- A Lua rebuild of 3.3.5a's LFGRoleButtonTemplate (FrameXML/LFGFrame.xml:4-66) wearing the
-- modern round role medallions (ui-lfg-roleicon-*, shipped sheet 5171843) instead of the flat
-- UI-LFG-ICON-ROLES strip. Behavior is a straight port of the native trio:
--   LFG_UpdateAvailableRoles / LFG_UpdateRolesChangeable / LFG_UpdateRoleCheckboxes
-- (FrameXML/LFGFrame.lua:209-284) — but applied to OUR buttons; a click writes through the same
-- SetLFGRoles C-call the native checkboxes use, so the native (hidden) frames stay in sync via
-- their own LFG_ROLE_UPDATE handlers.
--
-- Native id → tooltip mapping preserved (ROLE_DESCRIPTION1..4): DPS=1 TANK=2 HEALER=3 LEADER=4.

local NE = DragonUI_NewEra
if not NE then return end

NE.lfg = NE.lfg or {}
local L = NE.lfg

local ROLE_ATLAS = { TANK = "tank", HEALER = "healer", DAMAGER = "dps", LEADER = "leader" }
local ROLE_ID    = { DAMAGER = 1, TANK = 2, HEALER = 3, LEADER = 4 }

-- Modern medallion, with the native UI-LFG-ICON-ROLES strip as the no-art fail-safe.
function L.SetRoleIcon(tex, role, disabled)
  local suffix = ROLE_ATLAS[role]
  if not suffix then return end
  local atlas = "ui-lfg-roleicon-" .. suffix .. (disabled and "-disabled" or "")
  if NE.tex and NE.tex.SetAtlas and NE.tex.SetAtlas(tex, atlas, false) then return end
  tex:SetTexture("Interface\\LFGFrame\\UI-LFG-ICON-ROLES")
  if GetTexCoordsForRole then
    tex:SetTexCoord(GetTexCoordsForRole(role == "LEADER" and "GUIDE" or role))
  end
end

-- One role button: modern medallion + bottom-left checkbox + dim cover (disabled state).
local function makeRoleButton(parent, role, size)
  local b = CreateFrame("Button", nil, parent)
  b:SetSize(size, size)
  b:SetMotionScriptsWhileDisabled(true)
  b.role = role

  local icon = b:CreateTexture(nil, "ARTWORK")
  icon:SetAllPoints(b)
  L.SetRoleIcon(icon, role, false)
  b.icon = icon

  -- Native's `cover` is a half-alpha overlay shown while roles are locked (queued etc.).
  local cover = b:CreateTexture(nil, "OVERLAY")
  cover:SetAllPoints(b)
  cover:SetTexture(0, 0, 0)
  cover:SetAlpha(0.5)
  cover:Hide()
  b.cover = cover

  -- Bare CheckButton with the classic checkbox art (LFGRoleButtonTemplate builds the exact
  -- same thing inline; a bare one needs no global name, unlike UICheckButtonTemplate).
  local cb = CreateFrame("CheckButton", nil, b)
  cb:SetSize(22, 22)
  cb:SetPoint("BOTTOMLEFT", b, "BOTTOMLEFT", -4, -4)
  cb:SetNormalTexture("Interface\\Buttons\\UI-CheckBox-Up")
  cb:SetPushedTexture("Interface\\Buttons\\UI-CheckBox-Down")
  cb:SetCheckedTexture("Interface\\Buttons\\UI-CheckBox-Check")
  cb:SetDisabledCheckedTexture("Interface\\Buttons\\UI-CheckBox-Check-Disabled")
  local hl = cb:CreateTexture(nil, "HIGHLIGHT")
  hl:SetTexture("Interface\\Buttons\\UI-CheckBox-Highlight")
  hl:SetAllPoints(cb); hl:SetBlendMode("ADD")
  b.checkButton = cb

  b:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:SetText(_G["ROLE_DESCRIPTION" .. (ROLE_ID[self.role] or 1)] or _G[self.role] or self.role, nil, nil, nil, nil, 1)
    if self.permDisabled and YOUR_CLASS_MAY_NOT_PERFORM_ROLE then
      GameTooltip:AddLine(YOUR_CLASS_MAY_NOT_PERFORM_ROLE, 1, 0, 0, 1)
    end
    GameTooltip:Show()
  end)
  b:SetScript("OnLeave", function() GameTooltip:Hide() end)
  -- Clicking the medallion clicks the checkbox (native behavior).
  b:SetScript("OnClick", function(self)
    if self.checkButton:IsEnabled() == 1 then self.checkButton:Click() end
  end)
  return b
end

-- State application, port of LFG_Enable/Disable/PermanentlyDisableRoleButton.
local function applyButtonState(b, state)   -- "enabled" | "locked" | "unavailable"
  if state == "unavailable" then
    b.permDisabled = true
    b:Disable()
    -- The "-disabled" atlas variant is already a muted/desaturated medallion (verified: a clean
    -- grey shield, not blank) — it does NOT need the black `cover` dimmer on top. That overlay is
    -- a flat 70%-opacity black square meant for dimming the BRIGHT icon in the "locked" state
    -- below; stacked on the already-dark disabled art it crushed the icon to a solid black square.
    L.SetRoleIcon(b.icon, b.role, true)
    b.cover:Hide()
    b.checkButton:Hide(); b.checkButton:Disable()
  elseif state == "locked" then
    b:Disable()
    b.cover:Show()
    if not b.permDisabled then b.cover:SetAlpha(0.5) end
    b.checkButton:Disable()
  else
    b.permDisabled = false
    b:Enable()
    L.SetRoleIcon(b.icon, b.role, false)
    b.cover:Hide()
    b.checkButton:Show(); b.checkButton:Enable()
  end
end

-- ---------------------------------------------------------------------------
-- L.NewRoleRow(parent, opts) → row frame
--   opts.leader  — include the "willing to lead" button (Dungeons pane; LFR has no leader box)
--   opts.size    — button size (default 40)
--   opts.gap     — spacing (default 10)
-- Row API: row:Refresh() re-reads GetLFGRoles/GetAvailableRoles/GetLFGMode and repaints.
-- A click on any checkbox writes ALL four flags through SetLFGRoles (native pattern —
-- LFDQueueFrame_SetRoles), reading the leader flag from the row's box when present, else
-- preserving the server's current value.
-- ---------------------------------------------------------------------------
function L.NewRoleRow(parent, opts)
  opts = opts or {}
  local size = opts.size or 40
  local gap  = opts.gap or 10

  local order = {}
  if opts.leader then order[#order + 1] = "LEADER" end
  order[#order + 1] = "TANK"
  order[#order + 1] = "HEALER"
  order[#order + 1] = "DAMAGER"

  local row = CreateFrame("Frame", nil, parent)
  row:SetSize(#order * size + (#order - 1) * gap, size)
  row.buttons = {}

  local function applyRoles()
    local leader = select(1, GetLFGRoles())
    if row.buttons.LEADER then
      leader = row.buttons.LEADER.checkButton:GetChecked() and true or false
    end
    SetLFGRoles(leader,
      row.buttons.TANK.checkButton:GetChecked() and true or false,
      row.buttons.HEALER.checkButton:GetChecked() and true or false,
      row.buttons.DAMAGER.checkButton:GetChecked() and true or false)
    if opts.onChange then opts.onChange() end
  end

  local prev
  for _, role in ipairs(order) do
    local b = makeRoleButton(row, role, size)
    if prev then b:SetPoint("LEFT", prev, "RIGHT", gap, 0)
    else b:SetPoint("LEFT", row, "LEFT", 0, 0) end
    b.checkButton:SetScript("OnClick", function(self)
      PlaySound(self:GetChecked() and "igMainMenuOptionCheckBoxOn" or "igMainMenuOptionCheckBoxOff")
      applyRoles()
    end)
    row.buttons[role] = b
    prev = b
  end

  function row:Refresh()
    local leader, tank, healer, dps = GetLFGRoles()
    local checked = { LEADER = leader, TANK = tank, HEALER = healer, DAMAGER = dps }

    local canTank, canHealer, canDPS = true, true, true
    if GetAvailableRoles then canTank, canHealer, canDPS = GetAvailableRoles() end
    local avail = { TANK = canTank, HEALER = canHealer, DAMAGER = canDPS }
    -- Leader box: only the actual party/raid leader (or a solo player) may offer to lead
    -- (port of LFG_UpdateAvailableRoles' canChangeLeader).
    avail.LEADER = (GetNumPartyMembers() == 0 or IsPartyLeader()) and
                   (GetNumRaidMembers() == 0 or IsRaidLeader())

    local mode = GetLFGMode and GetLFGMode()
    local locked = (mode == "queued" or mode == "listed" or mode == "rolecheck" or mode == "proposal")

    for role, b in pairs(self.buttons) do
      b.checkButton:SetChecked(checked[role])
      if not avail[role] then
        applyButtonState(b, "unavailable")
      elseif locked then
        applyButtonState(b, "locked")
      else
        applyButtonState(b, "enabled")
      end
    end
  end

  return row
end
