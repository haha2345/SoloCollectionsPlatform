-- DragonUI_NewEra/modules/cooldownviewer/SettingsAdapter.lua — the category model the /cdm panel
-- talks to. Downport of NewEra/CooldownViewerSettings/DataAdapter.lua.
--
-- The panel never touches the spell lists directly; everything goes through here. That indirection
-- is upstream's design and it earns its keep twice over: our storage model differs from theirs (we
-- keep a per-category editable list with `enabled` flags, they keep one list per bucket), and if a
-- Classic Plus client ever ships C_CooldownViewer this is the single file that would swap.
--
-- CATEGORIES. Six, in two display modes:
--   spells: Essential / Utility  — the editable lists
--           Not Displayed       — the ARSENAL, i.e. every class ability with a real cooldown that
--                                 is not currently in a viewer. This is what makes the panel a
--                                 picker rather than an undo list.
--   auras : Tracked Buffs / Tracked Bars / Not Displayed — the unified tracked-aura pool, keyed by
--                                 each entry's assignment ("icon" / "bar" / "hidden").
--
-- ONE Equip source pool, not upstream's two. `equipActive` holds the discovered on-use trinkets
-- that the player has not placed in a viewer yet. The passive pool is cut for a data reason, not a
-- scheduling one — see Equip.lua's header.
--
-- "Not Displayed" is a CATALOG, not a bucket. For spells it is computed — arsenal minus what is
-- placed — rather than stored, so a newly-generated ability appears in it automatically. For auras
-- it IS a stored assignment, because an aura the player force-hides has to stay hidden against a
-- live scan.
--
-- The LABEL is retail's ("Not Displayed", Phase 9 §H.3); the STORED assignment value is still
-- "hidden" and the category ids are still hiddenSpell / hiddenAura. Renaming those would invalidate
-- every existing saved layout for a cosmetic gain, so the rename stops at the display string.

local NE = DragonUI_NewEra
local M  = NE.cooldownviewer

NE.cooldownviewersettings = NE.cooldownviewersettings or {}
local CDS = NE.cooldownviewersettings

local Adapter = {}
CDS.adapter = Adapter

-- Prefer a client GlobalString where 3.3.5a ships one, else an English literal — the house pattern.
local function GS(key, fallback)
  local v = _G[key]
  return (v ~= nil and v ~= "") and v or fallback
end

-- kind: "icon" (grid of tiles) | "bar" (stacked rows).
-- list: the editable-list key for spell categories. aura: the assignment value for aura categories.
-- source: a discovery POOL rather than a stored list — it holds whatever is unassigned right now,
-- and is skipped at render when empty so a player with no on-use trinket never sees the section.
local CATS = {
  essential   = { mode = "spells", kind = "icon", label = GS("COOLDOWN_VIEWER_SETTINGS_CATEGORY_ESSENTIAL", "Essential"), list = "essential" },
  utility     = { mode = "spells", kind = "icon", label = GS("COOLDOWN_VIEWER_SETTINGS_CATEGORY_UTILITY",   "Utility"),   list = "utility"   },
  equipActive = { mode = "spells", kind = "icon", label = GS("COOLDOWN_VIEWER_SETTINGS_CATEGORY_EQUIP_ACTIVE", "Trinkets"), source = true },
  hiddenSpell = { mode = "spells", kind = "icon", label = GS("COOLDOWN_VIEWER_SETTINGS_CATEGORY_NOT_IN_BAR", "Not Displayed")                },
  trackedBuff = { mode = "auras",  kind = "icon", label = GS("COOLDOWN_VIEWER_SETTINGS_CATEGORY_TRACKED_BUFF", "Tracked Buffs"), aura = "icon"   },
  trackedBar  = { mode = "auras",  kind = "bar",  label = GS("COOLDOWN_VIEWER_SETTINGS_CATEGORY_TRACKED_BARS", "Tracked Bars"),  aura = "bar"    },
  hiddenAura  = { mode = "auras",  kind = "icon", label = GS("COOLDOWN_VIEWER_SETTINGS_CATEGORY_NOT_IN_BAR", "Not Displayed"), aura = "hidden" },
}

-- The source pool sits between the display categories and Not Displayed, which is upstream's order
-- and retail's: "here is what you own but haven't placed", above "here is everything else".
Adapter.MODE_ORDER = {
  spells = { "essential", "utility", "equipActive", "hiddenSpell" },
  auras  = { "trackedBuff", "trackedBar", "hiddenAura" },
}

-- Settings category id → the assignment value M.SetEquipAssignment stores. The values are VIEWER
-- category names, so M.GetEquipItemsForCategory can compare them directly against a live viewer's
-- `category` field with no second mapping at runtime. Source cats map to nil, "back to the pool".
local ASSIGN_FOR_CAT = {
  essential = "essential", utility = "utility", hiddenSpell = "hidden",
  equipActive = nil,
}

function Adapter.IsSourcePool(catID)
  return (CATS[catID] and CATS[catID].source) and true or false
end

function Adapter.Meta(catID)  return CATS[catID] end
function Adapter.Label(catID) return CATS[catID] and CATS[catID].label or catID end
function Adapter.Kind(catID)  return CATS[catID] and CATS[catID].kind or "icon" end

-- What an empty section should say (Phase 7c). "(empty)" is fine for a list the player emptied
-- themselves; it reads as a fault in a section that has never been fillable, which is exactly how
-- the aura tab looked before this phase. Deliberately static: the text has to be true whatever the
-- auto-track destination happens to be, so it names the action rather than describing the state.
--
-- hiddenSpell names the setting rather than describing the state, because the state it is most
-- likely reporting is a LOW-LEVEL character with nothing left to list — and "(empty)" there reads as
-- a fault. Naming Show Unlearned turns the dead end into a signposted one.
local EMPTY_TEXT = {
  trackedBuff = "Nothing here yet — drag a buff in to pin it.",
  trackedBar  = "Nothing here yet — drag a buff in to pin it.",
  hiddenAura  = "Everything recorded is displayed.",
  hiddenSpell = "Everything you have learned is displayed. Turn on Show Unlearned (cog) to see the rest.",
}

function Adapter.EmptyText(catID) return EMPTY_TEXT[catID] or "(empty)" end
function Adapter.Mode(catID)  return CATS[catID] and CATS[catID].mode or "spells" end

-- ── Spell categories ────────────────────────────────────────────────────────────────────────────

-- Every spellID currently placed in a spell viewer, as a set.
--
-- ASKED, NOT RE-DERIVED (§H.3.22). This used to reimplement the placement rules — read the custom
-- list, fall back to the curated default — which is the same question GetActiveSpellList already
-- answers, and the copy drifted from the original. GetActiveSpellList also merges the player's
-- RACIALS in (appendRacials), and the copy never knew racials existed, so every racial was placed
-- and unplaced at the same time: shown in Utility by the viewer, and listed again under Not
-- Displayed by this catalog. Draenei saw Gift of the Naaru twice, Orcs Blood Fury, and so on for
-- every race with a racial at all.
--
-- Not Displayed is defined as "the catalog minus what is on screen", so it has to be computed from
-- what is on screen. Any future merge into a display list is then inherited rather than re-missed.
--
-- includeUnlearned is TRUE deliberately: this asks about PLACEMENT, not castability. Letting the
-- learn-gate run here would call an unlearned-but-placed spell unplaced and hand it to the catalog,
-- putting it in two places again for a second reason.
--
-- Returns ids AND names. The names are the §H.3.23 half: the catalog must not offer a SECOND id for
-- an ability already on screen under a first one, and an id comparison cannot see that.
local function placedSet(class)
  local ids, names = {}, {}
  for _, key in ipairs({ "essential", "utility" }) do
    for _, id in ipairs(M.GetActiveSpellList(key, true, class) or {}) do
      ids[id] = true
      local name = GetSpellInfo(id)
      if name then names[name] = true end
    end
  end
  return ids, names
end

-- The Not Displayed catalog: every class ability with a real cooldown that is not currently placed,
-- plus the player's racials. Race-impossible spells are dropped outright — that is not a "not yet"
-- but a "never", and no setting should surface it.
--
-- The LEARN gate applies here too now (§H.3.21). It did not, on the reasoning that an empty picker
-- reads as broken on a fresh character — but the cost was worse: an untalented druid's Mangle sat in
-- the catalog indistinguishable from an ability deliberately left undisplayed, one drag from a row
-- that could never light up. Tinting it red said "not yet learned" where the section's own name
-- already said "you chose not to show this", and the two readings cancel.
--
-- The empty-picker worry is answered where it belongs: the section's empty text names Show Unlearned,
-- so the full arsenal is one click away and the player is told where.
local function hiddenSpells(class)
  local showAll = M.GetShowUnlearned and M.GetShowUnlearned()
  local placed, placedNames = placedSet(class)
  local _, race = UnitRace("player")
  local rb = race and M.RACIAL_BY_RACE and M.RACIAL_BY_RACE[race]

  -- Which id OWNS an ability, when the pools disagree about it (§H.3.23). The arsenal is generated and
  -- the curated tables are authored, and for five abilities they picked different Spell.dbc rows for
  -- the same thing — the DK's Icy Touch is curated as 45477 and generated as 52372. The catalog walks
  -- the arsenal first, so without this the row the player drags would be the generated twin.
  --
  -- Nothing functional rides on the choice: highestKnownRankID resolves any id for an ability to the
  -- player's known rank by name, so both tiles behave identically. It rides on CONSISTENCY — the
  -- curated id is the one the seed, the starter layouts and the presets all name, and a layout is
  -- easier to reason about when one ability means one number everywhere.
  local ownerByName = {}
  local function claim(id)
    local name = id and GetSpellInfo(id)
    if name and ownerByName[name] == nil then ownerByName[name] = id end
  end
  for _, key in ipairs({ "essential", "utility" }) do
    local src = M.SPELL_DATA_BY_CATEGORY[key] and M.SPELL_DATA_BY_CATEGORY[key][class]
    if src then for _, id in ipairs(src) do claim(id) end end
    if rb and rb[key] then for _, id in ipairs(rb[key]) do claim(id) end end
  end

  local seen, seenNames, out = {}, {}, {}
  local function consider(id)
    if not id or seen[id] then return end
    seen[id] = true
    if M.SpellAllowedForRace and not M.SpellAllowedForRace(id) then return end
    -- IsSpellLearned, NOT IsTrackable: the latter waves through anything outside the curated tables,
    -- which is most of this catalog — the arsenal is a separate generated pool. Gating on it would
    -- have hidden Mangle (Cat), which the seed curates, and kept Mangle (Bear), which it does not.
    if not showAll and M.IsSpellLearned and not M.IsSpellLearned(id) then return end
    -- One tile per ABILITY. An id the client cannot name skips this and is judged by id alone —
    -- there is nothing to compare it against, and dropping it would be a guess.
    local name = GetSpellInfo(id)
    if name then
      local owner = ownerByName[name]
      if (owner and owner ~= id) or placedNames[name] or seenNames[name] then return end
      seenNames[name] = true
    end
    if not placed[id] then out[#out + 1] = id end
  end

  local arsenal = M.ARSENAL_BY_CLASS and M.ARSENAL_BY_CLASS[class]
  if arsenal then for _, id in ipairs(arsenal) do consider(id) end end

  -- Curated ids act as a floor: an ability the curation added but the generator missed still has to
  -- be re-addable after the player removes it.
  for _, key in ipairs({ "essential", "utility" }) do
    local src = M.SPELL_DATA_BY_CATEGORY[key] and M.SPELL_DATA_BY_CATEGORY[key][class]
    if src then for _, id in ipairs(src) do consider(id) end end
  end

  if rb then
    for _, key in ipairs({ "essential", "utility" }) do
      if rb[key] then for _, id in ipairs(rb[key]) do consider(id) end end
    end
  end
  return out
end

-- ── Equip rows ──────────────────────────────────────────────────────────────────────────────────
-- An equip row is an ENTRY TABLE, not a bare spellID, and GetItems returns a mixed list. That is
-- upstream's shape and it is the reason the whole thing stays cheap: a tile that gets a table calls
-- SetEquipEntry, a tile that gets a number calls SetSpell, and every other consumer keys off
-- `item.token or item.spellID`. The alternative — promoting every spell to an entry table — would
-- have touched the menu, the drag path, the filter and the tests for no gain.
--
-- The token, not the spellID, is the move key. It is stable across an unequip/re-equip, and it
-- survives the case a use-spell cannot be resolved yet.
local function equipEntry(e)
  return { itemID = e.itemID, spellID = e.spellID, token = e.token,
           label = e.label, source = e.source, kind = e.kind,
           hidden = (M.GetEquipAssignment(e.token) == "hidden") }
end

-- Is this spell already a STORED entry in an editable list — i.e. the player added the on-use item
-- through the picker as a spell? If so the discovery layer skips it, or a trinket whose use-spell is
-- also a curated entry would render twice: once as the stored spell, once as the discovered item.
local function editableHasSpell(spellID, class)
  if not spellID then return false end
  for _, key in ipairs({ "essential", "utility" }) do
    local list = M.GetCustomList(key, class)
    if list then
      for _, e in ipairs(list) do
        if e.spellID == spellID and e.enabled then return true end
      end
    end
  end
  return false
end

-- Discovered equip items whose assignment is exactly `assignVal` (nil = the unassigned source pool).
local function equipItemsAssigned(assignVal, class)
  local out = {}
  if not M.GetEquipActiveItems then return out end
  for _, e in ipairs(M.GetEquipActiveItems()) do
    if M.GetEquipAssignment(e.token) == assignVal and not editableHasSpell(e.spellID, class) then
      out[#out + 1] = equipEntry(e)
    end
  end
  return out
end

-- ── Aura rows (Phase 7b) ────────────────────────────────────────────────────────────────────────
--
-- An aura category is now the union of two things: what the player has ASSIGNED by hand, and what
-- the viewers are deciding for themselves. The second half is the point — before it, the only writer
-- of the assignment pool was this picker, so the pool could never be anything but empty.
--
-- Where an unassigned candidate lands depends on what is actually happening to it:
--
--   auto-track ON   it is being tracked, so it appears in whichever category the destination sends
--                   it to (M.AutoTrackDest: both / icon / bar) and is marked `auto`
--   auto-track OFF  nothing is showing it, so it appears under HIDDEN — which is the truth, and it
--                   also gives the section a purpose beyond force-excludes
--
-- Either way, dragging one out is what makes it explicit: the drag already calls SetAuraAssignment,
-- and "stop deciding this one for me" is exactly what that write means. No new write path.
local AUTO_DEST_CATS = {
  both = { icon = true, bar = true },
  icon = { icon = true },
  bar  = { bar = true },
}

local function auraRow(e, assignment)
  local name = e.name or (e.spellID and M.ResolveAuraName and M.ResolveAuraName(e.spellID))
  local icon = e.icon or (e.spellID and select(3, GetSpellInfo(e.spellID)))
  return {
    aura       = true,          -- the tile setter dispatches on this
    spellID    = e.spellID,
    label      = name,
    icon       = icon,
    dur        = e.dur,
    assignment = assignment,    -- nil for an auto row: it has no stored assignment yet
    auto       = (assignment == nil) or nil,
    talent     = e.talent,
    untalented = e.untalented,
    seen       = e.seen,
  }
end

local function auraItems(assignVal, class)
  local out = {}

  for _, e in ipairs(M.GetTrackedAuraList(class) or {}) do
    if (e.assignment or "icon") == assignVal then
      out[#out + 1] = auraRow(e, e.assignment or "icon")
    end
  end

  local autoOn = (not M.IsAutoTrackBuffs) or M.IsAutoTrackBuffs()
  local wanted
  if autoOn then
    wanted = AUTO_DEST_CATS[(M.AutoTrackDest and M.AutoTrackDest()) or "both"] or AUTO_DEST_CATS.both
    wanted = wanted[assignVal]
  else
    wanted = (assignVal == "hidden")
  end

  if wanted and M.GetAuraCandidates then
    -- Show Unlearned is reused rather than given an aura-specific twin: it already means "show me
    -- what I cannot use yet" for spells, and a second setting saying the same thing about auras is
    -- how a settings page stops making sense.
    local showAll = M.GetShowUnlearned and M.GetShowUnlearned()
    for _, e in ipairs(M.GetAuraCandidates(class, showAll and true or false)) do
      out[#out + 1] = auraRow(e, nil)
    end
  end

  return out
end

-- ── Items for a category ────────────────────────────────────────────────────────────────────────

function Adapter.GetItems(catID, class)
  if not class then local _; _, class = UnitClass("player") end
  local meta = CATS[catID]
  if not (meta and class) then return {} end

  local out = {}

  -- The source pool IS the unassigned discovery set — nothing stored, nothing curated.
  if meta.source then
    return equipItemsAssigned(nil, class)
  end

  if meta.aura then
    return auraItems(meta.aura, class)
  end

  if meta.list then
    -- The learn gate applies here: Essential/Utility should show what you can cast, unless the
    -- player has asked to see everything.
    local showAll = M.GetShowUnlearned and M.GetShowUnlearned()
    for _, id in ipairs(M.GetActiveSpellList(meta.list, showAll and true or false, class)) do
      out[#out + 1] = id
    end
    -- Trinkets placed in this viewer, listed after the spells — the same order the live viewer
    -- builds them in, so the panel reads as a preview of the bar rather than a separate list.
    for _, e in ipairs(equipItemsAssigned(ASSIGN_FOR_CAT[catID], class)) do out[#out + 1] = e end
    return out
  end

  -- Not Displayed: the catalog minus whatever the display categories are showing right now. See
  -- hiddenSpells and placedSet — the subtraction is against the real lists, not a re-derivation.
  for _, id in ipairs(hiddenSpells(class)) do out[#out + 1] = id end
  for _, e in ipairs(equipItemsAssigned("hidden", class)) do out[#out + 1] = e end
  return out
end

-- ── Moves ───────────────────────────────────────────────────────────────────────────────────────
-- Mirrors retail's legalOriginalSourceCategoryToTargetCategory. Same category is always legal
-- (that is a reorder, not a move).
-- Nothing lists equipActive as a target: a trinket leaves the pool by being placed, and comes back
-- only by being unequipped. That asymmetry is retail's, and it is why the pool has no inbound edges.
local LEGAL = {
  essential   = { utility = true, hiddenSpell = true },
  utility     = { essential = true, hiddenSpell = true },
  equipActive = { essential = true, utility = true },      -- retail EquipSlotEssential → {Essential, Utility}
  hiddenSpell = { essential = true, utility = true },
  trackedBuff = { trackedBar = true, hiddenAura = true },
  trackedBar  = { trackedBuff = true, hiddenAura = true },
  hiddenAura  = { trackedBuff = true, trackedBar = true },
}

function Adapter.CanTarget(fromCat, toCat)
  if not (fromCat and toCat) then return false end
  if fromCat == toCat then return true end
  local t = LEGAL[fromCat]
  return (t and t[toCat]) and true or false
end

function Adapter.GetValidTargets(fromCat)
  local meta = CATS[fromCat]
  if not meta then return {} end
  local out = {}
  for _, id in ipairs(Adapter.MODE_ORDER[meta.mode]) do
    if id ~= fromCat and Adapter.CanTarget(fromCat, id) then out[#out + 1] = id end
  end
  return out
end

-- Move a spell or aura between categories.
function Adapter.Assign(spellID, fromCat, toCat, class)
  if not (spellID and Adapter.CanTarget(fromCat, toCat)) then return false end
  if not class then local _; _, class = UnitClass("player") end

  local fromMeta, toMeta = CATS[fromCat], CATS[toCat]
  if not (fromMeta and toMeta) then return false end

  -- A source-pool row is an equip item and MUST route through AssignEquip. Falling through here
  -- would write its use-spell into the editable list as if the player had picked a spell, which
  -- looks right until you unequip the trinket and the entry stays behind, pointing at nothing.
  if fromMeta.source or toMeta.source then return false end

  -- Auras are one pool keyed by assignment, so a move is a single write.
  if toMeta.aura then
    M.SetAuraAssignment(class, spellID, toMeta.aura)
    return true
  end

  -- Spells: clear the old placement, then set the new one. Not Displayed is the ABSENCE of a placement,
  -- which is why it has no list of its own.
  if fromMeta.list then M.SetSpellEnabled(fromMeta.list, spellID, false) end
  if toMeta.list   then M.SetSpellEnabled(toMeta.list,   spellID, true)  end
  return true
end

-- Reassign an EQUIP item by TOKEN. Separate from Assign because an equip row's identity is its
-- token: the spellID may be shared with a curated entry, and for a source-pool row there is no
-- stored list to write into at all — the whole state is the one assignment value.
function Adapter.AssignEquip(token, fromCat, toCat)
  if not (token and toCat and CATS[toCat]) then return false end
  if fromCat and not Adapter.CanTarget(fromCat, toCat) then return false end
  M.SetEquipAssignment(token, ASSIGN_FOR_CAT[toCat])
  if M.RefreshActiveViewer then M.RefreshActiveViewer() end
  return true
end

-- Remove a user-added entry outright. Only meaningful for auras: a spell's "removal" is just
-- returning it to the Not Displayed catalog, which Assign already does, and an equip row is discovered
-- rather than stored — it leaves by being unequipped.
function Adapter.IsRemovable(spellID, catID, class)
  local meta = CATS[catID]
  if not (meta and meta.aura and spellID) then return false end
  if meta.source then return false end
  if not class then local _; _, class = UnitClass("player") end
  for _, e in ipairs(M.GetTrackedAuraList(class) or {}) do
    if e.spellID == spellID then return true end
  end
  return false
end

function Adapter.Remove(spellID, catID, class)
  if not Adapter.IsRemovable(spellID, catID, class) then return false end
  if not class then local _; _, class = UnitClass("player") end
  M.RemoveTrackedAura(class, spellID)
  return true
end

-- The ordered backing list for a category: the editable spell list, or the tracked-aura pool.
-- Not Displayed (spells) has neither — it is computed — so it returns nil and reorders there are no-ops.
local function orderedList(catID, class)
  local meta = CATS[catID]
  if not meta then return nil end
  if meta.list then return M.GetEditableList(meta.list, class) end
  if meta.aura then return M.GetTrackedAuraList(class) end
  return nil
end

local function indexOf(list, spellID)
  for i, e in ipairs(list) do
    if e.spellID == spellID then return i end
  end
  return nil
end

-- Move spellID to sit immediately before (offset 0) or after (offset 1) targetID, inside one
-- category. This is drag-only: retail reorders by drag and has no menu equivalent, so neither do we.
function Adapter.ReorderTo(catID, spellID, targetID, offset, class)
  if not (spellID and targetID and spellID ~= targetID) then return false end
  if not class then local _; _, class = UnitClass("player") end
  local list = orderedList(catID, class)
  if not list then return false end

  local from = indexOf(list, spellID)
  if not from then return false end
  local entry = table.remove(list, from)

  -- Recompute the target index AFTER the removal. Pulling the entry out shifts everything below it
  -- up by one, so an index captured beforehand lands a slot too far whenever the item moved DOWN
  -- the list — the classic off-by-one in every drag reorder.
  local to = indexOf(list, targetID)
  if not to then table.insert(list, from, entry); return false end
  table.insert(list, to + ((offset == 1) and 1 or 0), entry)

  local meta = CATS[catID]
  if meta.list then M.RefreshActiveViewer(meta.list) else M.RefreshActiveViewer() end
  return true
end

-- Cross-category move that lands at a POSITION rather than at the end of the destination.
function Adapter.AssignAt(spellID, fromCat, toCat, dropID, offset, class)
  if not Adapter.Assign(spellID, fromCat, toCat, class) then return false end
  if dropID and dropID ~= spellID then
    Adapter.ReorderTo(toCat, spellID, dropID, offset, class)
  end
  return true
end

-- Reorder within a category. Spell order is the editable list's order; aura order is the pool's.
function Adapter.MoveWithin(catID, spellID, delta, class)
  local meta = CATS[catID]
  if not (meta and meta.list and spellID and delta ~= 0) then return false end
  if not class then local _; _, class = UnitClass("player") end

  local list = M.GetEditableList(meta.list, class)
  if not list then return false end
  for i, e in ipairs(list) do
    if e.spellID == spellID then
      local j = i + delta
      if j < 1 or j > #list then return false end
      list[i], list[j] = list[j], list[i]
      M.RefreshActiveViewer(meta.list)
      return true
    end
  end
  return false
end
