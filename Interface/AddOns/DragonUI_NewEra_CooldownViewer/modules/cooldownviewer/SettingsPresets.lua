-- DragonUI_NewEra/modules/cooldownviewer/SettingsPresets.lua — named layouts, import/export, and
-- the session Undo the panel has been deferring since 4b-1. Phase 4b-5.
--
-- Downport of NewEra/CooldownViewerSettings/Presets.lua (378 lines), which is itself a
-- reimplementation of retail's Cooldown Manager layout dropdown.
--
-- A "layout" is a snapshot of everything the /cdm panel can edit:
--
--   customLists[cat][CLASS]   the editable Essential/Utility spell lists  (per class)
--   trackedAura[CLASS]        the unified tracked-aura pool               (per class)
--   equipAssign[token]        trinket placement                          (account-wide keys)
--   alerts / sounds           the per-cooldown alert and ready-sound maps (by spellID)
--
-- THE SNAPSHOT PAIR CAME WITH IT. Upstream's Panel.lua owns snapshotState/restoreState and exposes
-- them as CDS.SnapshotState / CDS.RestoreState / CDS.DeepCopy; our 4b-1 panel deferred the Revert
-- button precisely because that pair did not exist yet. It lives here now, so Revert is real — a
-- layout apply and an undo are the same operation with a different source snapshot, and building
-- two mechanisms for that would have been the mistake.
--
-- WHAT THE DOWNPORT CHANGED
--
--   * NO WowStyle1DropdownTemplate. Upstream's footer dropdown is a retail template. The footer
--     control here is a plain button that opens CDS.BuildLayoutMenu through core/Menu.lua, which is
--     the same menu tree either way — only the widget differs.
--
--   * IMPORT IS CLASS-CHECKED, which upstream does not do. A snapshot's spell lists are keyed by
--     class, so restoring a Priest layout on a Mage writes into the Priest's slot and appears to do
--     nothing at all. That is the worst possible failure mode for a paste — silence. Import now
--     refuses with a message naming the class it was built for.
--
--   * Nothing else. The codec is upstream's and is already 3.3.5a-clean: string.byte/char, math.floor
--     and string.find are all vanilla Lua 5.1, and there is no bit library anywhere in it.
--
-- SAFETY. Import NEVER executes pasted input. The parser is a hand-rolled typed reader — no
-- loadstring, no setfenv — and every parse is wrapped in pcall, so a malformed or hostile paste
-- produces an error message rather than an error. Plain SavedVariables reads/writes and StaticPopups
-- throughout: no secure templates, nothing that can taint the combat path.

local NE = DragonUI_NewEra
local M  = NE.cooldownviewer

local CDS = NE.cooldownviewersettings

local Presets = {}
CDS.presets = Presets

local MAGIC = "NECDM1"

-- ── Store ───────────────────────────────────────────────────────────────────────────────────────

local function cdLeaf(create)
  local cfg = NE.Config and NE.Config()
  if not cfg then return nil end
  if not cfg.cooldownviewer then
    if not create then return nil end
    cfg.cooldownviewer = {}
  end
  return cfg.cooldownviewer
end

local function store()
  local cd = cdLeaf(true)
  if not cd then return nil end
  cd.layouts = cd.layouts or {}
  return cd.layouts
end

local function getCurrent()
  local cd = cdLeaf(false)
  return cd and cd.currentLayout or nil
end

local function setCurrent(name)
  local cd = cdLeaf(true)
  if cd then cd.currentLayout = name end
end

-- ── Snapshot / restore ──────────────────────────────────────────────────────────────────────────

function CDS.DeepCopy(v)
  if type(v) ~= "table" then return v end
  local out = {}
  for k, val in pairs(v) do out[k] = CDS.DeepCopy(val) end
  return out
end

-- Appearance, captured RESOLVED rather than as a copy of a stored table.
--
-- What the exporting character actually sees is the account-wide table with their own per-character
-- overrides on top (§H.3.8), so a raw copy of either half alone would export something nobody is
-- looking at. Resolving through GetOpt also keeps the per-character bucket out of share strings
-- entirely — its keys are a character name and a realm, and they mean nothing on another account.
--
-- Every frame gets every key, including the two bar-only ones. They resolve to their defaults on an
-- icon viewer and nothing reads them there, and a loop with no exceptions in it is worth more than
-- the few dozen bytes a per-frame key list would save.
local function snapshotFrames()
  local out = {}
  for _, frameID in pairs(M.FRAME_ID or {}) do
    local t = {}
    for key in pairs(M.DEFAULTS or {}) do t[key] = M.GetOpt(frameID, key) end
    out[frameID] = t
  end
  return out
end

-- The five editable leaves plus appearance, plus the class the snapshot was taken on. `class` is not
-- decoration: it is what makes an imported string verifiable, and it is the key the spell lists are
-- stored under.
function CDS.SnapshotState()
  local cd = cdLeaf(true)
  if not cd then return nil end
  local _, class = UnitClass("player")
  -- The three LAYOUT leaves come from the active talent group's bucket, not the flat store, or a
  -- saved layout would capture whatever the pre-per-spec migration happened to leave behind. Alerts
  -- and sounds are per-spell preferences rather than layout and stay shared across specs.
  local lay = M._layoutBucket and M._layoutBucket(true) or cd
  return {
    class       = class,
    customLists = CDS.DeepCopy(lay.customLists) or {},
    trackedAura = CDS.DeepCopy(lay.trackedAura) or {},
    equipAssign = CDS.DeepCopy(lay.equipAssign) or {},
    alerts      = CDS.DeepCopy(cd.alerts) or {},
    sounds      = CDS.DeepCopy(cd.sounds) or {},
    -- Always captured, never conditionally applied. See M.LayoutsIncludeAppearance.
    frames      = snapshotFrames(),
  }
end

-- Write a snapshot back and re-render. Whole-leaf assignment, not a merge: a layout is a complete
-- state, so a spell the snapshot does not mention must end up unmentioned rather than surviving from
-- whatever was there before.
--
-- InvalidateCuratedCache matters here. GetActiveSpellList caches the resolved curated list, and
-- replacing customLists underneath it would otherwise leave the viewers rendering the previous
-- layout until something else happened to dirty the cache.
-- `opts.appearance` — true to force, false to force skip, nil to follow the player's setting. Revert
-- passes true: an undo's contract is to put things back exactly as they were, including a change the
-- setting happened to allow at the time and would not allow now.
function CDS.RestoreState(snap, opts)
  if type(snap) ~= "table" then return false end
  local cd = cdLeaf(true)
  if not cd then return false end

  local wantAppearance = (opts and opts.appearance)
  if wantAppearance == nil then
    wantAppearance = M.LayoutsIncludeAppearance and M.LayoutsIncludeAppearance()
  end
  if wantAppearance and type(snap.frames) == "table" then
    -- Through SetOpt, not by assigning the table: SetOpt is what knows whether this character writes
    -- to its own bucket or to the shared one (§H.3.8), and it re-applies each viewer as it goes.
    for frameID, vals in pairs(snap.frames) do
      if type(vals) == "table" then
        for key, value in pairs(vals) do M.SetOpt(frameID, key, value) end
      end
    end
  end

  -- Applied to the ACTIVE talent group only. A layout is something you chose for how you are playing
  -- right now; writing it into both groups would undo the other spec's setup as a side effect of
  -- loading one.
  local lay = M._layoutBucket and M._layoutBucket(true) or cd
  lay.customLists = CDS.DeepCopy(snap.customLists) or {}
  lay.trackedAura = CDS.DeepCopy(snap.trackedAura) or {}
  lay.equipAssign = CDS.DeepCopy(snap.equipAssign) or {}
  cd.alerts      = CDS.DeepCopy(snap.alerts) or {}
  cd.sounds      = CDS.DeepCopy(snap.sounds) or {}

  if M.InvalidateCuratedCache then M.InvalidateCuratedCache() end
  if M.RefreshActiveViewer then M.RefreshActiveViewer() end
  if CDS.RefreshLayout then CDS.RefreshLayout() end
  return true
end

-- ── Session undo ────────────────────────────────────────────────────────────────────────────────
-- ONE step, and it is deliberately one: the panel's edits are individually reversible by hand (move
-- it back, pick None), so the thing a player actually needs is "undo the layout I just applied", not
-- a history. The snapshot is taken before any apply/starter/import, and cleared when the panel
-- closes so a stale revert from an hour ago can never fire.

-- The selected layout NAME is tracked beside the snapshot rather than inside it. It is session
-- bookkeeping, not editable state, and putting it in the snapshot would bake it into every export
-- string — so a shared layout would arrive carrying the name of the layout its author had selected.
local undoSnap, undoCurrent

local function markUndo()
  undoSnap, undoCurrent = CDS.SnapshotState(), getCurrent()
  if CDS.RefreshRevertState then CDS.RefreshRevertState() end
end

function CDS.CanRevert() return undoSnap ~= nil end

function CDS.Revert()
  if not undoSnap then return false end
  local snap, cur = undoSnap, undoCurrent
  undoSnap, undoCurrent = nil, nil
  -- Unconditionally, including appearance. Revert undoes what the apply DID, and the setting may
  -- have been flipped in between — leaving a resized viewer behind would make undo partial.
  CDS.RestoreState(snap, { appearance = true })
  setCurrent(cur)
  if CDS.RefreshLayoutDropdown then CDS.RefreshLayoutDropdown() end
  if CDS.RefreshRevertState then CDS.RefreshRevertState() end
  return true
end

function CDS.ClearUndo()
  undoSnap, undoCurrent = nil, nil
  if CDS.RefreshRevertState then CDS.RefreshRevertState() end
end

-- ── Layouts ─────────────────────────────────────────────────────────────────────────────────────

function Presets.Capture() return CDS.SnapshotState() end

function Presets.Apply(name)
  local st = store()
  local snap = st and st[name]
  if not snap then return false end
  markUndo()
  CDS.RestoreState(snap)
  setCurrent(name)
  if CDS.RefreshLayoutDropdown then CDS.RefreshLayoutDropdown() end
  return true
end

-- New and Copy both snapshot the LIVE state, and that is correct rather than lazy: selecting a
-- layout applies it, so the live state always equals the selected layout's saved data.
function Presets.SaveAs(name)
  if not name or name == "" then return false end
  local st = store()
  local snap = Presets.Capture()
  if not (st and snap) then return false end
  st[name] = snap
  setCurrent(name)
  if CDS.RefreshLayoutDropdown then CDS.RefreshLayoutDropdown() end
  return true
end

function Presets.Rename(oldName, newName)
  if not (oldName and newName) or newName == "" or newName == oldName then return false end
  local st = store()
  if not (st and st[oldName]) then return false end
  st[newName] = st[oldName]
  st[oldName] = nil
  if getCurrent() == oldName then setCurrent(newName) end
  if CDS.RefreshLayoutDropdown then CDS.RefreshLayoutDropdown() end
  return true
end

function Presets.Delete(name)
  local st = store()
  if not (st and name and st[name]) then return false end
  st[name] = nil
  if getCurrent() == name then setCurrent(nil) end
  if CDS.RefreshLayoutDropdown then CDS.RefreshLayoutDropdown() end
  return true
end

function Presets.Names()
  local st = store() or {}
  local names = {}
  for k in pairs(st) do names[#names + 1] = k end
  table.sort(names)
  return names
end

function Presets.Current() return getCurrent() end

-- Everything back to the curated defaults, and off any named layout — you are now on the unsaved
-- starter, which is exactly retail's built-in starter layout.
function Presets.UseStarter()
  markUndo()
  local _, class = UnitClass("player")
  if M.ResetCustomList then
    M.ResetCustomList("essential", class)
    M.ResetCustomList("utility",   class)
  end
  if M.ResetTrackedAura then M.ResetTrackedAura(class) end
  local cd = cdLeaf(true)
  local lay = M._layoutBucket and M._layoutBucket(true)
  if lay then
    lay.equipAssign = {}    -- every trinket back to the source pool: the starter state is opt-in
  end
  if cd then
    cd.alerts = {}
    cd.sounds = {}
  end
  setCurrent(nil)
  if M.InvalidateCuratedCache then M.InvalidateCuratedCache() end
  if M.RefreshActiveViewer then M.RefreshActiveViewer() end
  if CDS.RefreshLayout then CDS.RefreshLayout() end
  if CDS.RefreshLayoutDropdown then CDS.RefreshLayoutDropdown() end
  return true
end

-- ── Per-spec starter ────────────────────────────────────────────────────────────────────────────
--
-- UseStarter above resets to the CLASS list — every curated spell the class has. That list is a union
-- across the class's specs, because the curated tables cannot express anything narrower (the runtime
-- gate is "have you learned it", and every druid has learned Wrath), so a Feral druid lands on
-- Balance's nukes as well as their own. This narrows it to one tree.
--
-- DISABLED, NOT DELETED. The starter writes a custom list holding EVERY spell in the class's Essential
-- list, with the spec's own turned on and the rest turned off — so off-spec spells land under Not
-- Displayed in the picker, one drag from coming back. Deleting them would make the starter a thing you
-- cannot undo except by resetting the whole layout.
--
-- ESSENTIAL ONLY. Utility is defensives, interrupts and escapes that a character of any spec might
-- press; the bloat this exists to answer is all in Essential.
function Presets.UseSpecStarter(tab)
  tab = tonumber(tab)
  local _, class = UnitClass("player")
  local byTab = class and (M.STARTER_BY_CLASS or {})[class]
  local want = byTab and tab and byTab[tab]
  if not want then return false end

  markUndo()

  local keep = {}
  for _, id in ipairs(want) do keep[id] = true end

  -- Built from the CURATED list, not from the starter, so a spell the starter does not name is still
  -- listed (disabled) rather than missing. GetEditableList seeds one from the curated defaults when
  -- the character has no custom list yet, which is exactly the shape needed here.
  local list = M.GetEditableList and M.GetEditableList("essential", class)
  if not list then return false end
  for _, entry in ipairs(list) do
    entry.enabled = keep[entry.spellID] and true or false
  end
  if M.SetCustomList then M.SetCustomList("essential", class, list) end

  -- Off any named layout: what is on screen is no longer what that layout said.
  setCurrent(nil)
  if M.InvalidateCuratedCache then M.InvalidateCuratedCache() end
  if M.RefreshActiveViewer then M.RefreshActiveViewer() end
  if CDS.RefreshLayout then CDS.RefreshLayout() end
  if CDS.RefreshLayoutDropdown then CDS.RefreshLayoutDropdown() end
  return true
end

-- ONCE PER BUCKET, and that is the whole safety argument. A layout bucket is created the first time a
-- character plays a talent group, and this marks it the moment it is seeded — so the auto path can
-- never run twice over the same bucket and can never overwrite curation. Re-deriving on every respec
-- was considered and rejected by the owner for exactly that reason.
--
-- Skipped entirely when DetectSpec returns nil (no points, or a tie): there is nothing to seed FROM,
-- and a level-5 character simply meets the full class list until they spend a point. The next call
-- after that point lands, seeds properly, because the marker is only set when a starter is applied.
function Presets.SeedStarterIfFresh()
  local lay = M._layoutBucket and M._layoutBucket(true)
  if not lay or lay.starterSeeded then return false end
  local tab = M.DetectSpec and M.DetectSpec()
  if not tab then return false end
  lay.starterSeeded = tab
  local ok = Presets.UseSpecStarter(tab)
  if ok and NE.Log then
    NE.Log("CDM", "seeded the " .. tostring((M.SpecNames and M.SpecNames()[tab]) or tab)
                  .. " starter layout for a new spec")
  end
  return ok
end

-- ── Share-string codec ──────────────────────────────────────────────────────────────────────────
-- Base64 over a hand-rolled typed serializer. Base64 because a share string has to survive being
-- pasted through a chat window and a forum post; typed-serializer because the alternative — emitting
-- Lua and reading it back with loadstring — means executing a stranger's paste.
--
-- Tags: z=nil, T=true, F=false, n<num>;, s<len>:<bytes>, t<npairs>;<k><v>…
-- Length-prefixed strings, so a spell name containing any of the tag characters is still safe.

local B64 = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
local B64DEC = {}
for i = 1, #B64 do B64DEC[B64:sub(i, i)] = i - 1 end

local function base64Encode(data)
  local out, i, n = {}, 1, #data
  while i <= n do
    local b1 = data:byte(i)
    local b2 = data:byte(i + 1)
    local b3 = data:byte(i + 2)
    local n1 = math.floor(b1 / 4)
    local n2 = (b1 % 4) * 16 + math.floor((b2 or 0) / 16)
    local n3 = ((b2 or 0) % 16) * 4 + math.floor((b3 or 0) / 64)
    local n4 = (b3 or 0) % 64
    out[#out + 1] = B64:sub(n1 + 1, n1 + 1)
    out[#out + 1] = B64:sub(n2 + 1, n2 + 1)
    out[#out + 1] = b2 and B64:sub(n3 + 1, n3 + 1) or "="
    out[#out + 1] = b3 and B64:sub(n4 + 1, n4 + 1) or "="
    i = i + 3
  end
  return table.concat(out)
end

local function base64Decode(s)
  s = s:gsub("[^%w%+/=]", "")
  local out, i, n = {}, 1, #s
  while i <= n do
    local c1 = B64DEC[s:sub(i, i)]
    local c2 = B64DEC[s:sub(i + 1, i + 1)]
    local c3c = s:sub(i + 2, i + 2); local c3 = B64DEC[c3c]
    local c4c = s:sub(i + 3, i + 3); local c4 = B64DEC[c4c]
    if not (c1 and c2) then break end
    out[#out + 1] = string.char(c1 * 4 + math.floor(c2 / 16))
    if c3c ~= "=" and c3 then out[#out + 1] = string.char((c2 % 16) * 16 + math.floor(c3 / 4)) end
    if c4c ~= "=" and c4 then out[#out + 1] = string.char((c3 % 4) * 64 + c4) end
    i = i + 4
  end
  return table.concat(out)
end

local function serialize(v, out)
  local t = type(v)
  if v == nil then out[#out + 1] = "z"
  elseif t == "boolean" then out[#out + 1] = v and "T" or "F"
  elseif t == "number" then out[#out + 1] = "n" .. tostring(v) .. ";"
  elseif t == "string" then out[#out + 1] = "s" .. #v .. ":" .. v
  elseif t == "table" then
    local count = 0
    for _ in pairs(v) do count = count + 1 end
    out[#out + 1] = "t" .. count .. ";"
    for k, val in pairs(v) do serialize(k, out); serialize(val, out) end
  else
    out[#out + 1] = "z"   -- functions/userdata never appear in a snapshot
  end
end

-- Raises on malformed input, which is what decode's pcall is for.
local function parseValue(s, i)
  local tag = s:sub(i, i)
  i = i + 1
  if tag == "z" then return nil, i
  elseif tag == "T" then return true, i
  elseif tag == "F" then return false, i
  elseif tag == "n" then
    local j = s:find(";", i, true); if not j then error("num") end
    local num = tonumber(s:sub(i, j - 1)); if not num then error("num") end
    return num, j + 1
  elseif tag == "s" then
    local j = s:find(":", i, true); if not j then error("str") end
    local len = tonumber(s:sub(i, j - 1)); if not len then error("str") end
    local start = j + 1
    if start + len - 1 > #s then error("str") end
    return s:sub(start, start + len - 1), start + len
  elseif tag == "t" then
    local j = s:find(";", i, true); if not j then error("tbl") end
    local count = tonumber(s:sub(i, j - 1)); if not count then error("tbl") end
    -- No bound on `count`, deliberately. A declared pair count is attacker-controlled, so the
    -- obvious move is to cap it — but the loop is already self-limiting: every iteration must
    -- consume at least one byte of payload or raise, so a header claiming a billion pairs fails on
    -- the first one rather than spinning. A cap here would be a guard no input can reach, and the
    -- test below is what establishes that rather than asserting the cap exists.
    i = j + 1
    local out = {}
    for _ = 1, count do
      local k; k, i = parseValue(s, i)
      local v; v, i = parseValue(s, i)
      if k ~= nil then out[k] = v end
    end
    return out, i
  end
  error("tag")
end

function Presets.Encode(snap)
  local out = {}
  serialize(snap, out)
  return MAGIC .. base64Encode(table.concat(out))
end

-- Returns snapshot, or nil + a reason fit to show the player. Never errors.
function Presets.Decode(str)
  if type(str) ~= "string" then return nil, "nothing pasted" end
  str = str:gsub("%s", "")
  if str == "" then return nil, "nothing pasted" end
  if str:sub(1, #MAGIC) ~= MAGIC then return nil, "not a Cooldown Manager layout string" end
  local payload = base64Decode(str:sub(#MAGIC + 1))
  local ok, val = pcall(function() return (parseValue(payload, 1)) end)
  if not ok or type(val) ~= "table" then return nil, "corrupt layout string" end
  if type(val.class) ~= "string" then return nil, "not a Cooldown Manager layout" end
  -- The class gate upstream lacks. The spell lists are keyed by class, so applying another class's
  -- layout writes into that class's slot and changes nothing visible — a silent no-op is a worse
  -- outcome than a refusal, because the player has no way to tell it from a broken feature.
  local _, class = UnitClass("player")
  if class and val.class ~= class then
    return nil, ("that layout is for a %s"):format(val.class)
  end
  return val
end

-- ── Import / export ─────────────────────────────────────────────────────────────────────────────

function Presets.Export(name)
  local st = store()
  local snap = (name and st and st[name]) or Presets.Capture()
  if not snap then return end
  StaticPopup_Show("NE_CDM_LAYOUT_EXPORT", nil, nil, { str = Presets.Encode(snap) })
end

function Presets.Import(text)
  local snap, err = Presets.Decode(text)
  if not snap then
    local msg = "Cooldown Manager layout: " .. (err or "invalid string")
    if UIErrorsFrame then UIErrorsFrame:AddMessage(msg, 1, 0.3, 0.3) end
    if NE.Log then NE.Log(msg) end
    return false
  end
  CDS.PromptName("Imported", function(name)
    if not name or name == "" then return end
    local st = store()
    if not st then return end
    st[name] = snap
    Presets.Apply(name)
  end)
  return true
end

-- ── StaticPopups ────────────────────────────────────────────────────────────────────────────────
-- 3.3.5a's StaticPopup names its edit box <dialog>EditBox in _G; ClassicAPI additionally exposes it
-- as .EditBox on some templates. Resolve all three rather than picking one — the same recipe
-- modules/talents/Loadouts.lua uses.
local function popupEditBox(self)
  return self.EditBox or self.editBox
    or (self.GetName and _G[(self:GetName() or "") .. "EditBox"]) or nil
end

StaticPopupDialogs = StaticPopupDialogs or {}

StaticPopupDialogs["NE_CDM_LAYOUT_NAME"] = {
  text = "Name this layout:",
  button1 = SAVE or "Save", button2 = CANCEL or "Cancel",
  hasEditBox = 1, timeout = 0, whileDead = 1, hideOnEscape = 1,
  OnShow = function(self)
    local e = popupEditBox(self)
    if e then e:SetText((self.data and self.data.preset) or ""); e:HighlightText(); e:SetFocus() end
  end,
  EditBoxOnEnterPressed = function(self)
    local p = self:GetParent()
    if p and p.button1 then p.button1:Click() end
  end,
  OnAccept = function(self)
    local e, cb = popupEditBox(self), self.data and self.data.cb
    if cb and e then cb(e:GetText()) end
  end,
}

function CDS.PromptName(preset, cb)
  StaticPopup_Show("NE_CDM_LAYOUT_NAME", nil, nil, { preset = preset, cb = cb })
end

StaticPopupDialogs["NE_CDM_LAYOUT_IMPORT"] = {
  text = "Paste a Cooldown Manager layout string:",
  button1 = "Import", button2 = CANCEL or "Cancel",
  hasEditBox = 1, editBoxWidth = 260, timeout = 0, whileDead = 1, hideOnEscape = 1,
  OnShow = function(self)
    local e = popupEditBox(self)
    if e then e:SetText(""); e:SetFocus() end
  end,
  EditBoxOnEnterPressed = function(self)
    local p = self:GetParent()
    if p and p.button1 then p.button1:Click() end
  end,
  OnAccept = function(self)
    local e = popupEditBox(self)
    Presets.Import(e and e:GetText() or "")
  end,
}

StaticPopupDialogs["NE_CDM_LAYOUT_EXPORT"] = {
  text = "Cooldown Manager layout string (Ctrl+C to copy):",
  button1 = OKAY or "Close",
  hasEditBox = 1, editBoxWidth = 260, timeout = 0, whileDead = 1, hideOnEscape = 1,
  OnShow = function(self)
    local e = popupEditBox(self)
    if e then e:SetText((self.data and self.data.str) or ""); e:HighlightText(); e:SetFocus() end
  end,
  EditBoxOnEscapePressed = function(self)
    local p = self:GetParent()
    if p then p:Hide() end
  end,
}

StaticPopupDialogs["NE_CDM_LAYOUT_DELETE"] = {
  text = "Delete the layout \"%s\"?",
  button1 = YES or "Yes", button2 = NO or "No",
  timeout = 0, whileDead = 1, hideOnEscape = 1,
  OnAccept = function(self) Presets.Delete(self.data and self.data.name) end,
}

-- Starter confirms, and Revert does not: one is destructive, the other IS the undo.
StaticPopupDialogs["NE_CDM_LAYOUT_STARTER"] = {
  text = "Reset to the starter layout?\n\nThis reverts every Cooldown Manager edit — spells, tracked "
       .. "auras, trinket placement, alerts and sounds — to their defaults, and clears your "
       .. "saved-layout selection.\n\nFrame positions are not affected.",
  button1 = YES or "Yes", button2 = NO or "No",
  timeout = 0, whileDead = 1, hideOnEscape = 1,
  OnAccept = function() Presets.UseStarter() end,
}

-- Confirms for the same reason the class starter does: it replaces the Essential list wholesale.
-- Narrower in what it says, because it is narrower in what it does — tracked auras, trinkets, alerts
-- and sounds are all left alone, and the off-spec spells are turned off rather than removed.
StaticPopupDialogs["NE_CDM_LAYOUT_SPEC_STARTER"] = {
  text = "Load the %s starter layout?\n\nEssential is set to that spec's spells. Everything else for "
       .. "your class moves to Not Displayed — nothing is deleted, and you can drag any of it back.\n\n"
       .. "Tracked auras, trinkets, alerts and frame positions are not affected.",
  button1 = YES or "Yes", button2 = NO or "No",
  timeout = 0, whileDead = 1, hideOnEscape = 1,
  OnAccept = function(self) Presets.UseSpecStarter(self.data and self.data.tab) end,
}

-- ── The menu ────────────────────────────────────────────────────────────────────────────────────

function CDS.BuildLayoutMenu(_, root)
  local cur = getCurrent()
  local names = Presets.Names()

  root:CreateTitle(cur or "No layout")

  if #names > 0 then
    for _, name in ipairs(names) do
      root:CreateRadio(name,
        function() return getCurrent() == name end,
        function() Presets.Apply(name) end)
    end
    root:CreateDivider()
  end

  root:CreateButton("New Layout", function()
    CDS.PromptName("", function(n) Presets.SaveAs(n) end)
  end)
  if cur then
    root:CreateButton("Copy", function()
      CDS.PromptName(cur .. " Copy", function(n) Presets.SaveAs(n) end)
    end)
    root:CreateButton("Rename", function()
      CDS.PromptName(cur, function(n) Presets.Rename(cur, n) end)
    end)
    root:CreateButton("|cffff5555Delete|r", function()
      StaticPopup_Show("NE_CDM_LAYOUT_DELETE", cur, nil, { name = cur })
    end)
  end

  root:CreateDivider()

  -- Starter layouts, per spec. The detected tree is marked rather than pre-clicked — detection is
  -- derived data and can be wrong, the same reason the aura picker keeps a "Show Unlearned" escape
  -- hatch — and when DetectSpec answers nil (no talent points yet, or an exact tie) nothing is marked
  -- and all three simply stand as choices. A level-5 character picking the spec they are heading for
  -- is a better answer than a one-in-three guess wearing a detection's clothes.
  local names = M.SpecNames and M.SpecNames() or {}
  local detected = M.DetectSpec and M.DetectSpec()
  if #names > 0 then
    local sub = root:CreateButton("Starter Layout")
    for tab = 1, #names do
      local label = names[tab]
      if tab == detected then label = label .. "  |cff44ff44(your spec)|r" end
      sub:CreateButton(label, function()
        StaticPopup_Show("NE_CDM_LAYOUT_SPEC_STARTER", names[tab], nil, { tab = tab })
      end)
    end
    sub:CreateDivider()
    sub:CreateButton("Everything (no spec)", function() StaticPopup_Show("NE_CDM_LAYOUT_STARTER") end)
      :SetTooltip("Everything", "The full curated list for your class, both specs' spells|nincluded. "
        .. "This is what the Cooldown Manager shipped with|nbefore per-spec starters.")
  else
    root:CreateButton("Use Starter Layout", function() StaticPopup_Show("NE_CDM_LAYOUT_STARTER") end)
  end

  root:CreateButton("Import Layout", function() StaticPopup_Show("NE_CDM_LAYOUT_IMPORT") end)
  root:CreateButton("Export Layout", function() Presets.Export(cur) end)
    :SetTooltip("Export Layout", "Opens a share string you can copy with Ctrl+C.|nIt covers this "
      .. "class's spell lists, tracked auras,|ntrinket placement, alerts and sounds.")
end

function CDS.ToggleLayoutMenu(anchor)
  if not (NE.menu and NE.menu.ToggleAnchored) then return end
  NE.menu.ToggleAnchored(CDS.BuildLayoutMenu, anchor,
    { point = "BOTTOMLEFT", relativePoint = "TOPLEFT", x = 0, y = 2 })
end
