-- DragonUI_NewEra/modules/levelup/Unlocks.lua — what to show for a given level.
--
-- Merges the two sources into one ordered, display-ready list:
--
--   observed  (Harvest.lua)  the live server's own answer — always wins
--   fallback  (Data.lua)     Blizzlike constants for what no API reports
--
-- "Observed wins" is a suppression rule, not a priority number: a fallback entry is dropped
-- outright when the harvest already produced an entry with the same name, so a player who has
-- visited a riding trainer sees the server's Apprentice Riding at the server's level and never a
-- second copy at ours.
--
-- No validation gate survives from the original design, and that is the point. The standalone
-- addon needs one (it checks GetSpellLink on every hardcoded id, because ids it was born with may
-- not exist here); harvested entries came off this server a moment ago, so there is nothing left
-- to validate them against.

local NE = DragonUI_NewEra
if not NE or NE.disabled then return end

local M = NE.levelup
local H = M.harvest

-- Display order within a level. Talents first because a talent point is the one unlock that
-- demands an action; the rest descend from "you can now do a thing" to "you can now go somewhere".
local ORDER = {
  Talent = 1, Spell = 2, Rank = 3, Feature = 4, Mount = 5, BG = 6, Dungeon = 7, Raid = 8,
}

-- "Rank 5" / "Rang 5" / "Rango 5" — every locale trails the digits, so read the number and ignore
-- the word. Same approach as core/SpellRanks.lua:45, for the same reason.
local function rankNumber(rankText)
  if not rankText then return 0 end
  return tonumber(tostring(rankText):match("(%d+)%s*$")) or 0
end

-- ── Per-level index over the harvested class store ──────────────────────────────────────────────
--
-- The store is keyed by name|rank so re-harvesting overwrites in place; the banner wants it keyed
-- by level. Invert once and cache, rebuilding only when Harvest.generation moves.
local indexCache, indexGen, indexKey, nameCache

local function spellsByLevel()
  local _, classFile = UnitClass("player")
  local key = (GetRealmName() or "?") .. "/" .. (classFile or "?")
  if indexCache and indexGen == H.generation and indexKey == key then return indexCache end

  local out, names = {}, {}
  local store = H.ClassStore()
  if store then
    for _, e in pairs(store) do
      if e.l and e.n then
        local rank = rankNumber(e.r)
        local text = e.n
        -- Rank 1 (or unranked) reads as a new ability; later ranks say so, using the server's own
        -- rank string so it stays localized.
        local etype = "Spell"
        if rank > 1 then
          etype = "Rank"
          text = e.n .. " (" .. tostring(e.r) .. ")"
        end
        out[e.l] = out[e.l] or {}
        table.insert(out[e.l], { type = etype, text = text, icon = e.i, _rank = rank, _name = e.n })
        names[e.n] = true
      end
    end
  end
  indexCache, indexGen, indexKey, nameCache = out, H.generation, key, names
  return out
end
M.SpellsByLevel = spellsByLevel

-- Every ability name this server has taught us, at ANY level.
--
-- Suppression has to be global, not per-level, and getting that wrong is subtle: the fallback says
-- Journeyman Riding is a level-40 unlock, a server that teaches it at 30 gets harvested at 30, and a
-- per-level check finds nothing to collide with at 40 — so the player is congratulated on it twice,
-- once at the level they actually got it and once at ours. If the server has an answer, ours is
-- wrong everywhere, not just where the two happen to coincide.
local function observedNames()
  spellsByLevel()          -- populates nameCache as a side effect of the same walk
  return nameCache or {}
end

-- ── The merge ───────────────────────────────────────────────────────────────────────────────────

function M.Unlocks(level)
  if not level then return {} end
  local out, seenName = {}, {}

  local function add(e)
    out[#out + 1] = e
    if e._name or e.text then seenName[(e._name or e.text)] = true end
  end

  -- (1) Talent points. The server's observed step first, our Blizzlike rate only if it has not
  -- been observed yet.
  local points = H.TalentPointsGainedAt(level) or M.FallbackTalentPoints(level)
  if points and points > 0 then
    add({ type = "Talent",
          text = (points > 1) and (NE.L["New Talent Points"] .. " x" .. points)
                               or NE.L["New Talent Point"] })
  end

  -- (2) Class abilities and ranks, straight off this server's trainer.
  local spells = spellsByLevel()[level]
  if spells then
    -- Lowest rank first, then alphabetical, so a level granting several ranks of the same ability
    -- reads in order instead of in pairs() order (which is arbitrary and changes between sessions).
    local sorted = {}
    for _, e in ipairs(spells) do sorted[#sorted + 1] = e end
    table.sort(sorted, function(a, b)
      if a._name ~= b._name then return (a._name or "") < (b._name or "") end
      return (a._rank or 0) < (b._rank or 0)
    end)
    for _, e in ipairs(sorted) do add(e) end
  end

  -- (3) Battlegrounds — the server's bracket, already localized.
  local r = H.RealmStore()
  if r then
    for name, minLevel in pairs(r.bgs) do
      if minLevel == level then add({ type = "BG", text = name,
                                      icon = [[Interface\Icons\Ability_DualWield]] }) end
    end
    -- (4) Dungeons and raids, likewise.
    if r.dungeons then
      for _, d in pairs(r.dungeons) do
        if d.l == level then
          add({ type = (d.k == "Raid") and "Raid" or "Dungeon", text = d.n,
                icon = M.ICON_LFD })
        end
      end
    end
  end

  -- (5) Fallback features, minus anything the harvest already covered — here at this level, or at
  -- any other level (see observedNames).
  local fb = M.FALLBACK[level]
  if fb then
    local observed = observedNames()
    for _, e in ipairs(fb) do
      if not seenName[e.text] and not observed[e.text]
         and (type(e.check) ~= "function" or e.check()) then
        add(e)
      end
    end
  end

  -- Resolve each entry against its type defaults, and stabilise the order.
  local stable = {}
  for i, e in ipairs(out) do stable[e] = i end
  table.sort(out, function(a, b)
    local oa, ob = ORDER[a.type] or 99, ORDER[b.type] or 99
    if oa ~= ob then return oa < ob end
    return stable[a] < stable[b]
  end)

  local resolved = {}
  for _, e in ipairs(out) do
    local def = M.ENTRY_TYPES[e.type] or {}
    resolved[#resolved + 1] = {
      text    = e.text or "?",
      subText = e.subText or def.subText or "",
      icon    = e.icon or def.icon or M.FALLBACK_ICON,
      subIcon = e.subIcon or def.subIcon,
    }
  end
  return resolved
end

-- How much this realm/class actually knows. Register.lua reports it, because "the banner looked
-- thin" and "the harvest has not run yet" are otherwise indistinguishable to a user.
function M.Coverage()
  local levels, entries = 0, 0
  for _, list in pairs(spellsByLevel()) do
    levels = levels + 1
    entries = entries + #list
  end
  local r = H.RealmStore()
  local bgs, dungeons = 0, 0
  if r then
    for _ in pairs(r.bgs) do bgs = bgs + 1 end
    for _ in pairs(r.dungeons or {}) do dungeons = dungeons + 1 end
  end
  return { levels = levels, entries = entries, bgs = bgs, dungeons = dungeons }
end
