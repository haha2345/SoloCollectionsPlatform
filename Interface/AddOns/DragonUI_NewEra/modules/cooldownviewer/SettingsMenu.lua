-- DragonUI_NewEra/modules/cooldownviewer/SettingsMenu.lua — the right-click item menu and the
-- panel's settings cog. Downport of the menu halves of NewEra/CooldownViewerSettings/Categories.lua
-- (showItemMenu, applyAlertBadge) and Panel.lua (settingsMenuGenerator).
--
-- THIS IS THE PHASE THAT SWITCHES PHASE 4A ON. The alert engine and the ready-sound catalogue have
-- shipped and been running since 4a, but nothing could assign them: every store was reachable only
-- from Lua. This file is the assignment surface. Nothing below is new machinery — it is calls into
-- M.alerts, M.SetReadySoundKit and CDS.adapter, arranged as a menu.
--
-- The Phase 4a ItemMenu.lua was deleted rather than debugged, on the owner's call, because the
-- content belonged here from the start: upstream carries Move-to / Remove / Ready Sound / Alert in
-- ONE generator on the settings item, not on the live HUD icon. That is also why the menu needs
-- three levels (item -> Ready Sound -> category -> entry) and therefore core/Menu.lua's ClassicAPI
-- backend, rather than the native two-level UIDropDownMenu.
--
-- ONE DELIBERATE DIVERGENCE FROM UPSTREAM: the FX enum. Upstream's fx values index
-- NE.groupbuff.VISUAL_ALERT (1 = marching ants, 6 = flash), a Group Buff Filter enum this addon
-- does not have. Ours is AL.FX — 1/2/3 over LibCustomGlow — so the FX submenu is generated FROM
-- AL.FX rather than hardcoding two entries. Hardcoding upstream's 1/6 here would have silently
-- written 6, which AL.FX has no renderer for.

local NE = DragonUI_NewEra
local M  = NE.cooldownviewer

local CDS = NE.cooldownviewersettings
local Adapter = CDS.adapter

local REFRESH_WINDOWS = { 10, 20, 30, 40, 50 }   -- percent; AL clamps to [10, 50]

-- ── Alert badge ─────────────────────────────────────────────────────────────────────────────────
-- A small marker in the corner of any tile that has an alert or a ready sound configured, so the
-- grid shows its own state instead of making the player right-click every icon to find out.
-- Upstream draws the `common-icon-visual` glyph. That atlas is not registered in this addon, so the
-- badge is upstream's own fallback: a gold dot on a dark strip. Ask HasAtlas first rather than
-- letting SetAtlas fail — a failed SetAtlas logs an ATLAS MISS, and this runs once per tile per
-- rebuild, which would bury the log in a message the answer to which is always "no".

local BADGE_ATLAS = "common-icon-visual"

local function applyAlertBadge(item)
  if not item.AlertBG then
    item.AlertBG = item:CreateTexture(nil, "OVERLAY")
    item.AlertBG:SetSize(14, 12)
    item.AlertBG:SetPoint("BOTTOMRIGHT", item, "BOTTOMRIGHT", 0, 0)
    item.AlertBG:SetTexture(0, 0, 0, 0.7)

    item.AlertBadge = item:CreateTexture(nil, "OVERLAY")
    item.AlertBadge:SetSize(6, 6)
    item.AlertBadge:SetPoint("CENTER", item.AlertBG, "CENTER", 0, 0)
    local haveGlyph = NE.tex and NE.tex.HasAtlas and NE.tex.HasAtlas(BADGE_ATLAS)
      and NE.tex.SetAtlas(item.AlertBadge, BADGE_ATLAS, false)
    if not haveGlyph then item.AlertBadge:SetTexture(1, 0.82, 0, 1) end
  end

  local configured = (M.GetReadySoundKit and M.GetReadySoundKit(item.spellID) ~= nil)
    or (M.alerts and M.alerts.GetType and M.alerts.GetType(item.spellID) ~= nil)
  if configured then
    item.AlertBG:Show(); item.AlertBadge:Show()
  else
    item.AlertBG:Hide(); item.AlertBadge:Hide()
  end
end

CDS._applyAlertBadge = applyAlertBadge

-- Extra tooltip lines describing what the badge means for this specific tile. Called by
-- SettingsCategories' OnEnter, after the spell tooltip has been laid down.
function CDS._itemTooltipExtra(item, tooltip)
  if not (item and item.spellID and tooltip) then return end
  local AL = M.alerts
  local t = AL and AL.GetType and AL.GetType(item.spellID)
  if t then
    local fxName
    for _, fx in ipairs((AL and AL.FX) or {}) do
      if fx.id == AL.GetFX(item.spellID) then fxName = fx.name end
    end
    tooltip:AddLine(("Alert: %s (%s)"):format(t, fxName or "?"), 0.4, 1, 0.4)
  end
  local kit = M.GetReadySoundKit and M.GetReadySoundKit(item.spellID)
  if kit then
    tooltip:AddLine("Ready sound: " .. (M.GetSoundKitName(kit) or tostring(kit)), 0.4, 0.8, 1)
  end
end

-- ── The item menu ───────────────────────────────────────────────────────────────────────────────

-- An equip row moves by TOKEN, a spell or aura by spellID. The two stores are genuinely different —
-- a spell move rewrites an editable list, a trinket move writes one assignment value — so the
-- branch is here rather than hidden inside Assign, where a caller could not tell which happened.
local function addMoveEntries(root, item, class)
  for _, target in ipairs(Adapter.GetValidTargets(item._catID)) do
    root:CreateButton("Move to " .. Adapter.Label(target), function()
      if item.token then
        Adapter.AssignEquip(item.token, item._catID, target)
      else
        Adapter.Assign(item.spellID, item._catID, target, class)
      end
      CDS.RefreshLayout()
    end)
  end
end

-- Is this row an AURA row — Tracked Buffs, Tracked Bars, or Not Displayed on the Auras tab?
--
-- It decides which of the four triggers this file is allowed to offer. Two of them are driven by a
-- COOLDOWN finishing (ItemMixin:ConsumeReadyTransition), and an aura item does not define it: there
-- is no cooldown behind a tracked buff to finish. Offering them anyway is what produced the "the FX
-- on tracked buffs doesn't work" report — an alert that stores, badges and previews, and then has no
-- event that could ever fire it.
local function isAuraRow(item)
  local meta = item and item._catID and Adapter.Meta and Adapter.Meta(item._catID)
  return (meta and meta.mode == "auras") and true or false
end

-- One submenu per sound category, a radio per sound, plus None. Selecting previews the cue —
-- retail's "Play Sample" — because a sound you cannot hear before committing is not a choice.
--
-- Not offered on an aura row: the cue plays from FireReadyAlerts, on the cooldown -> ready edge.
-- A stored kit is still clearable there (see the aura branch), because a setting you can reach only
-- to regret is worse than one you were never shown.
local function addSoundEntries(root, item)
  if not (item.spellID and M.SOUND_DATA and M.SOUND_CATEGORY_ORDER and M.SetReadySoundKit) then return end

  if isAuraRow(item) then
    -- Only when something is actually stored — otherwise the row simply has no sound section. This
    -- exists for layouts saved BEFORE the gate, where a kit could be assigned to a buff and then sat
    -- there lighting the badge with nothing behind it and no per-item way to take it off.
    if M.GetReadySoundKit(item.spellID) == nil then return end
    root:CreateDivider()
    root:CreateButton("Clear Ready Sound", function()
      M.SetReadySoundKit(item.spellID, nil)
      applyAlertBadge(item)
    end):SetTooltip("Clear Ready Sound",
      "A ready sound plays when a COOLDOWN finishes.|nA tracked buff has none, so this one can|nnever play. Clearing it also clears the badge.")
    return
  end

  root:CreateDivider()
  local soundRoot = root:CreateButton("Ready Sound")

  soundRoot:CreateRadio("None",
    function() return M.GetReadySoundKit(item.spellID) == nil end,
    function()
      M.SetReadySoundKit(item.spellID, nil)
      applyAlertBadge(item)
    end)

  for _, cat in ipairs(M.SOUND_CATEGORY_ORDER) do
    local catSub = soundRoot:CreateButton(cat)
    for _, e in ipairs(M.SOUND_DATA[cat] or {}) do
      catSub:CreateRadio(e.name,
        function() return M.GetReadySoundKit(item.spellID) == e.kit end,
        function()
          M.SetReadySoundKit(item.spellID, e.kit)
          if M.PlayReadySound then M.PlayReadySound(e.kit) end
          applyAlertBadge(item)
        end)
    end
  end
end

-- Does this spell have an aura of its own name up right now? The same lookup the Refresh alert
-- makes at runtime (Alerts.lua's inRefreshWindow): player first, then target.
--
-- A "yes" here is proof Refresh will work. A "no" is NOT proof it will not — the aura may simply be
-- inactive at the moment you opened the menu. So the tooltip states the REQUIREMENT and adds a live
-- sighting when there is one, rather than greying the entry out on a guess. Knowing for certain
-- would mean shipping a generated "applies an aura named after itself" table out of Spell.dbc; that
-- is a real option, but it is a generator pass, not a menu tweak.
local function auraSeen(name)
  if not (name and NE.aura and NE.aura.FindByName) then return false end
  for _, unit in ipairs({ "player", "target" }) do
    local row = NE.aura.FindByName(unit, name)
    if row and row.duration and row.duration > 0 then return true end
  end
  return false
end

-- Event (None / Available / Refresh / Usable), FX style, and — for Refresh — the window %.
-- Choosing an event or an FX flashes a sample on the tile itself, the same "see it before you
-- commit" contract as the sound preview.
local function addAlertEntries(root, item)
  local AL = M.alerts
  if not (item.spellID and AL and AL.SetType) then return end
  root:CreateDivider()
  local alertRoot = root:CreateButton("Alert")

  local function isType(t) return AL.GetType(item.spellID) == t end
  -- Preview in the alert type's OWN colour. Each type has a distinct tint, so previewing everything
  -- as "usable" showed a yellow flash for a choice that would glow green in play.
  local function pick(t)
    return function()
      AL.SetType(item.spellID, t)
      if t then AL.Preview(item, AL.GetFX(item.spellID), t) elseif AL.ClearFX then AL.ClearFX(item) end
      applyAlertBadge(item)
    end
  end

  alertRoot:CreateRadio("None", function() return AL.GetType(item.spellID) == nil end, pick(nil))

  -- Available is the cooldown -> ready edge, so it is a SPELL trigger only. Its own tooltip used to
  -- promise "Works for every spell", which is true and was being read on rows that hold no spell.
  -- None stays above it, so a layout that stored `available` on a buff before this gate can still be
  -- set back to None or moved onto Refresh.
  if not isAuraRow(item) then
    alertRoot:CreateRadio("Available", function() return isType("available") end, pick("available"))
      :SetTooltip("Available", "Flashes once, the moment the cooldown finishes.|nWorks for every spell.")
  end

  -- Refresh is the one event that genuinely cannot fire for some spells, so it says what it needs.
  local pct = math.floor((AL.GetWindow(item.spellID) or 0.3) * 100 + 0.5)
  local refreshText
  if isAuraRow(item) then
    -- The caveat below is about a COOLDOWN that applies no aura, which cannot be the case here: the
    -- row is the aura. This is the one trigger a tracked buff is built for, and saying so is the
    -- point — it is also the one that was silently doing nothing until the ticker learned to look.
    refreshText = ("Glows during the last %d%% of this buff's|nremaining time."):format(pct)
  else
    refreshText = ("Glows during the last %d%% of this spell's own|nbuff or debuff."):format(pct)
      .. "|n|nA cooldown that applies no aura — Shadowfiend,|nPsychic Scream — can never trigger it."
  end
  refreshText = refreshText .. (auraSeen(item.spellName)
    and "|n|n|cff40ff40Its aura is active now, so this will work.|r"
    or  "|n|n|cffffd200No aura of this name is up right now.|r")
  alertRoot:CreateRadio("Refresh", function() return isType("refresh") end, pick("refresh"))
    :SetTooltip("Refresh", refreshText)

  -- ACTIVE, on aura rows only. The other three all ask questions about a COOLDOWN, and a proc with
  -- no castable spell of its own name can answer "yes" to none of them. Offered first among the
  -- aura-row triggers because for a tracked buff it is the obvious one.
  if isAuraRow(item) then
    alertRoot:CreateRadio("Active", function() return isType("active") end, pick("active"))
      :SetTooltip("Active", "Glows for as long as this buff is on you.|n|nThe one that works for a"
        .. " proc: it asks whether the|nbuff is up, not whether something is castable|nor off cooldown.")
  end

  -- USABLE asks the client whether a spell of this name can be cast. On an aura row that is a real
  -- question for a self-buff you re-cast (Inner Fire, Fortitude) and a meaningless one for a proc —
  -- IsUsableSpell does not know "Surge of Light", so the alert stores, badges, and never fires.
  -- Offered only when the client can actually answer, which it can only do for a spell in the book.
  --
  -- Probed with GetSpellInfo rather than IsUsableSpell: the latter returns nil BOTH for a name it
  -- does not know and for a known spell that is merely unaffordable right now, so reading it here
  -- would hide the entry from anyone who opened the menu out of mana.
  local usableCastable = (not isAuraRow(item)) or (item.spellName and GetSpellInfo(item.spellName) ~= nil)
  if usableCastable then
    local usableText = "Glows for as long as the spell is off cooldown|nand affordable."
    local threshold = M.alertdata and M.alertdata.ExecuteThreshold
      and M.alertdata.ExecuteThreshold(item.spellID, item._rankCDIDs)
    if threshold then
      usableText = usableText .. ("|n|nThis one also waits for a target below %d%% health."):format(threshold * 100)
    end
    if isAuraRow(item) then
      usableText = usableText .. "|n|nOn a buff row this is about RE-CASTING it,|nnot about the buff being up — that is Active."
    end
    alertRoot:CreateRadio("Usable", function() return isType("usable") end, pick("usable"))
      :SetTooltip("Usable", usableText)
  end

  alertRoot:CreateDivider()

  -- Generated from AL.FX, not from upstream's hardcoded pair. See the header.
  local fxSub = alertRoot:CreateButton("FX Style")
  for _, fx in ipairs(AL.FX or {}) do
    fxSub:CreateRadio(fx.name,
      function() return AL.GetFX(item.spellID) == fx.id end,
      function()
        AL.SetFX(item.spellID, fx.id)
        AL.Preview(item, fx.id, AL.GetType(item.spellID) or "available")
      end)
  end

  local winSub = alertRoot:CreateButton("Refresh Window")
  for _, pct in ipairs(REFRESH_WINDOWS) do
    winSub:CreateRadio(pct .. "%",
      function() return math.abs((AL.GetWindow(item.spellID) * 100) - pct) < 0.5 end,
      function() AL.SetWindow(item.spellID, pct / 100) end)
  end
end

-- The generator. Kept separate from the open call so a test can build the tree and drive it without
-- any of UIDropDownMenu present.
function CDS.ItemMenuGenerator(item, class)
  return function(_, root)
    root:CreateTitle(item.spellName or "")
    addMoveEntries(root, item, class)

    -- Remove only appears when the entry is genuinely deletable — a stored user aura. A spell is
    -- never removed, only returned to the catalog, which "Move to Not Displayed" already does; a
    -- trinket is discovered, so it leaves by being unequipped and never by a menu.
    if not item.token and Adapter.IsRemovable and Adapter.IsRemovable(item.spellID, item._catID, class) then
      root:CreateDivider()
      root:CreateButton("|cffff5555Remove|r", function()
        Adapter.Remove(item.spellID, item._catID, class)
        CDS.RefreshLayout()
      end)
    end

    addSoundEntries(root, item)
    addAlertEntries(root, item)
  end
end

-- Called by SettingsCategories for every tile click.
function CDS.OnItemClick(item, button)
  if button ~= "RightButton" then return end
  if not (item and item._catID and (item.spellID or item.token)) then return end
  if not (NE.menu and NE.menu.OpenContext) then return end
  local _, class = UnitClass("player")
  NE.menu.OpenContext(CDS.ItemMenuGenerator(item, class))
end

-- ── The settings cog ────────────────────────────────────────────────────────────────────────────

function CDS.SettingsMenuGenerator(_, root)
  root:CreateCheckbox("Show Unlearned",
    function() return M.GetShowUnlearned and M.GetShowUnlearned() end,
    function()
      M.SetShowUnlearned(not M.GetShowUnlearned())
      CDS.RefreshLayout()
    end)

  root:CreateDivider()
  root:CreateButton("Reset Spell Lists", function() StaticPopup_Show("NE_CDM_RESET_TRACKING") end)
  root:CreateButton("Clear All Alerts",  function() StaticPopup_Show("NE_CDM_RESET_ALERTS") end)
end

-- Both resets are destructive and irreversible (there is no undo store until 4b-5), so both confirm.
StaticPopupDialogs = StaticPopupDialogs or {}
StaticPopupDialogs["NE_CDM_RESET_TRACKING"] = {
  -- Names the scope in the confirm too. This is the last thing read before an irreversible action,
  -- and it used to say nothing about WHOSE lists — while the code behind it cleared every class.
  text = "Reset this class's Cooldown Manager spell and buff lists to their defaults?\n\nOther classes, alerts, sounds and frame positions are not affected.",
  button1 = YES or "Yes",
  button2 = NO or "No",
  OnAccept = function()
    if M.ResetTracking then M.ResetTracking() end
    if CDS.RefreshLayout then CDS.RefreshLayout() end
  end,
  timeout = 0, whileDead = 1, hideOnEscape = 1,
}
StaticPopupDialogs["NE_CDM_RESET_ALERTS"] = {
  text = "Clear every configured alert and ready sound?\n\nSpell lists and frame positions are not affected.",
  button1 = YES or "Yes",
  button2 = NO or "No",
  OnAccept = function()
    if M.ResetAlerts then M.ResetAlerts() end
    if CDS.RefreshLayout then CDS.RefreshLayout() end
  end,
  timeout = 0, whileDead = 1, hideOnEscape = 1,
}

function CDS.ToggleSettingsMenu(cog)
  if not (NE.menu and NE.menu.ToggleAnchored) then return end
  NE.menu.ToggleAnchored(CDS.SettingsMenuGenerator, cog, { point = "TOPRIGHT", relativePoint = "BOTTOMRIGHT", x = 0, y = -2 })
end
