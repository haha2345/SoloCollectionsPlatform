-- DragonUI_NewEra/modules/encounterjournal/Support.lua — 3.3.5a stand-ins for the NewEra
-- Core pieces the Encounter Journal leans on that this addon hasn't ported elsewhere.
--
-- DOWNPORT (new file, no 1.15 counterpart):
--   * NE.tooltip.Wire       — NewEra's shared tooltip wiring helper (feature-gated there; we
--                             provide the minimal surface the EJ uses).
--   * NE.ej.CreateDropdown  — replaces retail's CreateFrame("DropdownButton", ...,
--                             "WowStyle1DropdownTemplate"). Wraps 3.3.5a's native
--                             UIDropDownMenu machinery behind the retail-ish surface the
--                             ported call sites use: SetupMenu(generator) with
--                             root:CreateRadio(label, isSelected, onSelect), GenerateMenu()
--                             (refreshes the collapsed text), SetDefaultText(text).
--   * NE.ej.PrimeItem / NE.ej.SchedulePrimedRefresh — item-cache warming. 3.3.5a has no
--                             GET_ITEM_INFO_RECEIVED event; an uncached GetItemInfo(id) stays
--                             nil until the server answers an item query. Touching the item
--                             via a hidden tooltip's SetHyperlink issues that query; a short
--                             C_Timer poll re-renders the loot list as answers stream in.

local NE = DragonUI_NewEra
if not NE then return end

NE.ej = NE.ej or {}

-- ---------------------------------------------------------------------------------------
-- Instance button splash art: retail's bgFDID/buttonFDID textures are 256x128 widescreen
-- splashes with padding baked in, hence the shared 0.68x0.74 TexCoord crop every call site
-- used to hardcode. The 23 WotLK button BLPs hand-shipped into Textures/EncounterJournal
-- (Textures/ASSETS.md) are a DIFFERENT source (128x128 square dungeon-finder-style icons,
-- confirmed via BLP2 header dims) — reusing that same crop over-crops them into a near-square
-- sliver and then stretches it to fill the widescreen 174x96 grid button, producing visible
-- horizontal stretching. This set lists exactly those 23 square FDIDs so callers can pick the
-- correct crop per texture instead of one hardcoded constant.
-- ---------------------------------------------------------------------------------------
NE.ej.SQUARE_BUTTON_FDID = {
  [237592] = true, [237593] = true, [237594] = true, [237595] = true, [237596] = true,
  [237598] = true, [237599] = true, [237600] = true, [237601] = true, [237602] = true,
  [237603] = true, [237604] = true, [237605] = true, [237606] = true, [303841] = true,
  [304502] = true, [311220] = true, [311221] = true, [336389] = true, [336390] = true,
  [336391] = true, [336392] = true, [366689] = true,
}

-- Apply the right TexCoord for an instance button splash texture given its fileID: retail's
-- widescreen crop for old-format art, or a centered "cover" crop (full width, vertical band)
-- for the square WotLK icons so a 174x96-ish widescreen target isn't stretched. Square-source
-- textures placed into a roughly-square target (e.g. the 40x40 back-button portrait) get the
-- full, uncropped texture instead — no crop needed when source and target aspect already match.
function NE.ej.SetButtonTexCoord(tex, fdid, targetIsSquare)
  if NE.ej.SQUARE_BUTTON_FDID[fdid] then
    if targetIsSquare then
      tex:SetTexCoord(0, 1, 0, 1)
    else
      tex:SetTexCoord(0, 1, 0.2241379, 0.7758621)
    end
  else
    tex:SetTexCoord(0, 0.68359375, 0, 0.7421875)
  end
end

-- ---------------------------------------------------------------------------------------
-- Tooltip wiring (subset of NewEra Core/Tooltip.lua used by the EJ: text or callback form).
-- ---------------------------------------------------------------------------------------
NE.tooltip = NE.tooltip or {}
if not NE.tooltip.Wire then
  function NE.tooltip.Wire(frame, tip, opts)
    local anchor = (opts and opts.anchor) or "ANCHOR_RIGHT"
    frame:SetScript("OnEnter", function(self)
      GameTooltip:SetOwner(self, anchor)
      if type(tip) == "function" then
        tip(self, GameTooltip)
      else
        GameTooltip:SetText(tip, 1, 1, 1)
      end
      GameTooltip:Show()
    end)
    frame:SetScript("OnLeave", function() GameTooltip:Hide() end)
  end
end

-- ---------------------------------------------------------------------------------------
-- Dropdown: retail SetupMenu/CreateRadio surface over 3.3.5a UIDropDownMenu.
-- UIDropDownMenuTemplate REQUIRES a global name (its children are found via _G lookups).
-- ---------------------------------------------------------------------------------------
local ddSerial = 0
function NE.ej.CreateDropdown(parent, name, menuWidth)
  if not name then
    ddSerial = ddSerial + 1
    name = "NE_EJDropdown" .. ddSerial
  end
  local dd = CreateFrame("Frame", name, parent, "UIDropDownMenuTemplate")
  dd._menuWidth = menuWidth or 130

  -- The probe root: runs the generator only to find the selected radio's label.
  local function selectedLabel()
    if not dd._generator then return nil end
    local chosen
    local probe = {
      CreateRadio = function(_, label, isSelected)
        if not chosen and type(isSelected) == "function" then
          local ok, sel = pcall(isSelected)
          if ok and sel then chosen = label end
        end
      end,
    }
    pcall(dd._generator, dd, probe)
    return chosen
  end

  -- Refresh the collapsed text from the generator's selected radio (retail's auto text).
  function dd:GenerateMenu()
    local label = selectedLabel() or self._defaultText
    if label then UIDropDownMenu_SetText(self, label) end
  end

  function dd:SetDefaultText(text)
    self._defaultText = text
    if not selectedLabel() then UIDropDownMenu_SetText(self, text) end
  end

  function dd:SetupMenu(generator)
    self._generator = generator
    UIDropDownMenu_Initialize(self, function()
      local root = {
        CreateRadio = function(_, label, isSelected, onSelect)
          local info = UIDropDownMenu_CreateInfo()
          info.text = label
          local ok, sel = pcall(isSelected)
          info.checked = (ok and sel) and true or false
          info.func = function()
            if onSelect then onSelect() end
            dd:GenerateMenu()
          end
          UIDropDownMenu_AddButton(info)
        end,
      }
      generator(self, root)
    end)
    UIDropDownMenu_SetWidth(self, self._menuWidth)
    self:GenerateMenu()
  end

  return dd
end

-- ---------------------------------------------------------------------------------------
-- Search box text: SearchBoxTemplate_OnLoad (!!!ClassicAPI/Templates/UIPanelTemplates.lua)
-- sets the box's literal text to SEARCH as an old-style placeholder (no retail overlay
-- watermark), and OnEditFocusLost restores it whenever the box is empty on blur. So an
-- untouched/blurred box reads back as the localized "Search" string, not "" -- callers that
-- filter the grid by GetText() must treat that placeholder the same as empty.
-- ---------------------------------------------------------------------------------------
function NE.ej.ReadSearchText(sb)
  local t = sb and sb.GetText and sb:GetText()
  if not t or t == "" or t == (SEARCH or "Search") then return "" end
  return t
end

-- ---------------------------------------------------------------------------------------
-- Item-cache warming (the GET_ITEM_INFO_RECEIVED substitute).
-- ---------------------------------------------------------------------------------------
local primeTip   -- hidden tooltip whose SetHyperlink forces the client to query the item
local primed = {}
function NE.ej.PrimeItem(id)
  if not id or primed[id] then return end
  primed[id] = true
  if not primeTip then
    primeTip = CreateFrame("GameTooltip", "NE_EJItemPrimeTooltip", UIParent, "GameTooltipTemplate")
    primeTip:SetOwner(UIParent, "ANCHOR_NONE")
  end
  -- pcall: a bogus id must never error out of a render pass (the server just won't answer).
  pcall(primeTip.SetHyperlink, primeTip, "item:" .. id)
end

-- Poll while a loot view has unresolved items: `check()` returns true when another pass is
-- wanted; `render()` re-renders. Bounded so a permanently-unanswered id can't tick forever.
local pollTicket = 0
function NE.ej.SchedulePrimedRefresh(check, render)
  pollTicket = pollTicket + 1
  local ticket, tries = pollTicket, 0
  local function tick()
    if ticket ~= pollTicket then return end     -- superseded by a newer view
    if not check() then return end
    render()
    tries = tries + 1
    if tries < 20 and check() and C_Timer and C_Timer.After then
      C_Timer.After(0.3, tick)
    end
  end
  if C_Timer and C_Timer.After then C_Timer.After(0.3, tick) end
end
