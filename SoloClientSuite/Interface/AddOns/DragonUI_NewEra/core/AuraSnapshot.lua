-- DragonUI_NewEra/core/AuraSnapshot.lua — one aura scan per unit per frame (NE.aura).
--
-- DOWNPORT of NewEra's Core/Aura.lua. Purpose is unchanged: consumers that need "is aura X on unit
-- Y right now" would each run their own 1..40 UnitBuff loop, and during aura bursts UNIT_AURA can
-- fire many times per frame — so the same list gets walked over and over. This walks it ONCE per
-- (unit, filter) per frame and hands out a shared read-only view.
--
-- PUBLIC:
--   NE.aura.GetSnapshot(unit, filter) -> { byName = {[name]=row}, list = {row,...}, n = <count> }
--     filter: "HELPFUL" (default) or "HARMFUL"
--     row:    { name, icon, count, duration, expiration, dispelType, spellID, index }
--
-- The returned tables are POOLED and rewritten on the next frame's scan — read within the frame,
-- never retain. (NewEra documents the same contract.)
--
-- !! 3.3.5a ARG-POSITION HAZARD (CONTRACTS §0: "some Blizzard returns are at shifted arg positions")
-- UnitAura on 3.3.5a returns `rank` as the SECOND value, which was removed in MoP:
--     3.3.5a : name, RANK, icon, count, dispelType, duration, expirationTime, caster, ..., spellID
--     modern : name,       icon, count, dispelType, duration, expirationTime, caster, ..., spellID
-- Every index after the first is shifted by one versus the NewEra source this is ported from. The
-- source's own comment (CooldownViewer.lua ScanTargetTrackedAuras) documents the MODERN layout —
-- do not copy those indices over.

local NE = DragonUI_NewEra
NE.aura = NE.aura or {}

local UnitBuff, UnitDebuff, GetTime = UnitBuff, UnitDebuff, GetTime

-- Per (unit .. filter) cached snapshot: { stamp = <GetTime at scan>, byName = {}, list = {}, n = }
-- GetTime() is constant for the whole frame in WoW, so it is a correct and cheap frame key.
local cache = {}

local MAX_AURAS = 40

local function scan(snapshot, unit, filter)
  local fn = (filter == "HARMFUL") and UnitDebuff or UnitBuff

  local byName, list = snapshot.byName, snapshot.list
  for k in pairs(byName) do byName[k] = nil end

  local n = 0
  for i = 1, MAX_AURAS do
    -- 3.3.5a layout — see the hazard note in the file header.
    local name, _rank, icon, count, dispelType, duration, expiration, _caster,
          _isStealable, _shouldConsolidate, spellID = fn(unit, i)
    if not name then break end

    n = n + 1
    local row = list[n]
    if not row then row = {}; list[n] = row end

    row.name       = name
    row.icon       = icon
    row.count      = count or 0
    row.dispelType = dispelType
    row.duration   = duration or 0
    row.expiration = expiration or 0
    row.spellID    = spellID
    row.index      = i

    -- First occurrence wins: with two ranks of the same buff present, the lower index is the one
    -- the UI conventionally shows.
    if byName[name] == nil then byName[name] = row end
  end

  snapshot.n = n
  return snapshot
end

function NE.aura.GetSnapshot(unit, filter)
  if not unit then return nil end
  filter = filter or "HELPFUL"

  -- A unit that isn't present yields an empty (but valid) snapshot, so callers never nil-check.
  local key = unit .. filter
  local snapshot = cache[key]
  if not snapshot then
    snapshot = { byName = {}, list = {}, n = 0, stamp = -1 }
    cache[key] = snapshot
  end

  local now = GetTime()
  if snapshot.stamp == now then return snapshot end
  snapshot.stamp = now

  if not UnitExists(unit) then
    for k in pairs(snapshot.byName) do snapshot.byName[k] = nil end
    snapshot.n = 0
    return snapshot
  end

  return scan(snapshot, unit, filter)
end

-- Convenience: the row for one aura name, or nil. Buff-preferred, then debuff — the order the
-- CooldownViewer's findPlayerAuraDataByName relies on.
function NE.aura.FindByName(unit, name)
  if not (unit and name) then return nil end
  local snap = NE.aura.GetSnapshot(unit, "HELPFUL")
  local row = snap and snap.byName[name]
  if row then return row, false end
  snap = NE.aura.GetSnapshot(unit, "HARMFUL")
  row = snap and snap.byName[name]
  if row then return row, true end
  return nil
end
