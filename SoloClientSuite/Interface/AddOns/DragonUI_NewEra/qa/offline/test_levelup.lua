-- qa/offline/test_levelup.lua — offline harness for the Level Up Display's data layer.
--
--   lua5.1 qa/offline/test_levelup.lua        (from the addon root)
--
-- Scope is deliberately Assets + Data + Harvest + Unlocks, NOT the two view files. The views are a
-- port of choreography that has shipped twice; the data layer is new logic with no precedent, and
-- it is the part that decides whether this addon works on a server nobody tested it against. It is
-- also the only part that can be exercised without a rendering client.
--
-- The trainer stub below is the interesting fixture: it models a class trainer whose list is
-- FILTERED and PARTLY COLLAPSED at the moment the harvest arrives, because that is the real state
-- Blizzard's ClassTrainerFrame leaves it in, and a harvest that forgets to widen the filters silently
-- records only the handful of services the player can already afford.

local ADDON = (arg and arg[0] or ""):match("^(.*)qa/offline/[^/]+$") or "./"

-- ── Minimal client stubs ────────────────────────────────────────────────────────────────────────

local events = {}
local function fireEvent(name, ...)
  for _, f in ipairs(events) do
    if f._reg[name] and f._script then f._script(f, name, ...) end
  end
end

function CreateFrame(_, _, _, _)
  local f = { _reg = {}, _script = nil }
  function f:RegisterEvent(e)      self._reg[e] = true end
  function f:UnregisterAllEvents() self._reg = {} end
  function f:SetScript(_, fn)      self._script = fn end
  function f:GetName()             return nil end
  events[#events + 1] = f
  return f
end

_G.UnitClass    = function() return "Warrior", "WARRIOR" end
_G.UnitLevel    = function() return 40 end
_G.GetRealmName = function() return "TestRealm" end
_G.BOOKTYPE_SPELL = "spell"

-- Talents: 51 total points at 40, 50 at 39 -> a gain of 1 observed at level 40.
_G.GetUnspentTalentPoints = function() return 51 end
_G.GetNumTalentTabs       = function() return 3 end
_G.GetTalentTabInfo       = function() return "Arms", nil, 0 end

-- Spellbook: empty, so the backstop records nothing and cannot mask a trainer bug.
_G.GetNumSpellTabs       = function() return 0 end
_G.GetSpellTabInfo       = function() return nil end
_G.GetSpellBookItemName  = function() return nil end

-- Battlegrounds. Note AV at 20, NOT the Blizzlike 51 — this stands in for a server that re-brackets
-- its battlegrounds, and the assertion below is that we follow the server rather than a constant.
local BGS = {
  { "Warsong Gulch", 1, nil, 10 },
  { "Arathi Basin",  1, nil, 20 },
  { "Alterac Valley", 1, nil, 20 },
}
_G.GetBattlegroundInfo = function(i)
  local b = BGS[i]
  if not b then return nil end
  return b[1], b[2], b[3], b[4]
end

-- Dungeons, via the client's own id lists.
_G.LFDDungeonList = { 101, 102 }
_G.LFRRaidList    = { 201 }
_G.TYPEID_HEROIC_DIFFICULTY = 2
local DUNGEONS = {
  [101] = { "Deadmines", 1, 15 },
  [102] = { "Scholomance", 1, 40 },
  [201] = { "Molten Core", 4, 60 },
}
_G.GetLFGDungeonInfo = function(id)
  local d = DUNGEONS[id]
  if not d then return nil end
  return d[1], d[2], d[3]
end
_G.LFGDungeonList_Setup = function() end

-- ── Trainer stub ────────────────────────────────────────────────────────────────────────────────
--
-- serviceType mirrors the client's: "available" is what the player can train now, "unavailable" is
-- gated behind a higher level (the forward-looking data), "used" is already learned, "header" is a
-- collapsible group. The last entry has NO level requirement, standing in for a profession recipe,
-- and must be dropped.
local SERVICES = {
  { name = "Blacksmithing",  rank = nil,       stype = "header",      level = nil, expanded = false },
  { name = "Heroic Strike",  rank = "Rank 1",  stype = "used",        level = 1,   icon = "i/hs1" },
  { name = "Heroic Strike",  rank = "Rank 6",  stype = "available",   level = 40,  icon = "i/hs6" },
  { name = "Mortal Strike",  rank = "Rank 1",  stype = "unavailable", level = 40,  icon = "i/ms1" },
  { name = "Molten Cleave",  rank = "Rank 3",  stype = "unavailable", level = 42,  icon = "i/mc3" },
  { name = "Rough Grinding Stone", rank = nil, stype = "available",   level = nil, icon = "i/rgs" },
}

local filters = { available = 1, unavailable = nil, used = nil }   -- Blizzard's default state
local headerExpanded = false
local filtersDuringRead

local function visible()
  local out = {}
  for _, s in ipairs(SERVICES) do
    if s.stype == "header" then
      out[#out + 1] = s
    elseif headerExpanded or s.name ~= "Rough Grinding Stone" then
      -- Everything except the header's own child is top-level in this fixture; the recipe sits
      -- under the collapsed Blacksmithing header.
      if filters[s.stype] then out[#out + 1] = s end
    end
  end
  return out
end

_G.GetNumTrainerServices = function() return #visible() end
_G.GetTrainerServiceInfo = function(i)
  local s = visible()[i]
  if not s then return nil end
  return s.name, s.rank, s.stype, (s.stype == "header") and headerExpanded or nil
end
_G.GetTrainerServiceLevelReq = function(i)
  local s = visible()[i]
  -- Record what the filters looked like while the harvest was actually reading, so the test can
  -- prove they were widened rather than just restored.
  filtersDuringRead = filtersDuringRead or
    { available = filters.available, unavailable = filters.unavailable, used = filters.used }
  return s and s.level or nil
end
_G.GetTrainerServiceIcon = function(i)
  local s = visible()[i]
  return s and s.icon or nil
end
_G.GetTrainerServiceTypeFilter = function(t) return filters[t] end
_G.SetTrainerServiceTypeFilter = function(t, on) filters[t] = (on == 1) and 1 or nil end
_G.ExpandTrainerSkillLine   = function() headerExpanded = true end
_G.CollapseTrainerSkillLine = function() headerExpanded = false end

-- ── Addon namespace ─────────────────────────────────────────────────────────────────────────────

DragonUI_NewEra = {
  db = {},
  L  = setmetatable({}, { __index = function(_, k) return k end }),
  EV_LEARNED_SPELL = "LEARNED_SPELL_IN_TAB",
}
local NE = DragonUI_NewEra

local FILES = {
  "modules/levelup/Assets.lua",
  "modules/levelup/Data.lua",
  "modules/levelup/Harvest.lua",
  "modules/levelup/Unlocks.lua",
}

print("=== LOAD ===")
for _, rel in ipairs(FILES) do
  local ok, err = pcall(dofile, ADDON .. rel)
  if ok then print("  ok   " .. rel)
  else print("  FAIL " .. rel .. "\n       " .. tostring(err)); os.exit(1) end
end

local M, H = NE.levelup, NE.levelup.harvest
local fails = 0
local function assertf(cond, msg)
  if cond then print("  ok   " .. msg)
  else fails = fails + 1; print("  FAIL " .. msg) end
end

-- ── Harvest ─────────────────────────────────────────────────────────────────────────────────────

print("\n=== HARVEST ===")
fireEvent("PLAYER_ENTERING_WORLD")
fireEvent("TRAINER_SHOW")

local store = H.ClassStore()
local function entry(name, rank) return store[name .. "|" .. (rank or "")] end

assertf(entry("Mortal Strike", "Rank 1"), "an UNAVAILABLE service was harvested (forward-looking data)")
assertf(entry("Heroic Strike", "Rank 1"), "a USED service was harvested (already-learned history)")
assertf(entry("Molten Cleave", "Rank 3"), "a server-invented ability was harvested with no spell id")
assertf(entry("Molten Cleave", "Rank 3") and entry("Molten Cleave", "Rank 3").l == 42,
        "the SERVER's level requirement was recorded, not a baked one")
assertf(entry("Molten Cleave", "Rank 3") and entry("Molten Cleave", "Rank 3").i == "i/mc3",
        "the icon came from the trainer service")
assertf(entry("Rough Grinding Stone") == nil,
        "a service with no level requirement was dropped (profession recipes stay out)")

assertf(filtersDuringRead and filtersDuringRead.unavailable and filtersDuringRead.used,
        "filters were WIDENED during the read")
assertf(filters.available == 1 and filters.unavailable == nil and filters.used == nil,
        "filters were RESTORED to the player's original state")
assertf(headerExpanded == false, "a collapsed header was left collapsed")

local r = H.RealmStore()
assertf(r.bgs["Alterac Valley"] == 20, "battleground bracket follows the server (20, not Blizzlike 51)")
assertf(r.dungeons and r.dungeons["Deadmines|15"], "dungeons harvested from the client's own list")
assertf(r.dungeons and r.dungeons["Molten Core|60"] and r.dungeons["Molten Core|60"].k == "Raid",
        "raids are distinguished from dungeons")

-- Realm scoping: the whole reason one install can serve many servers.
assertf(NE.db.levelup.realms["TestRealm"] ~= nil, "store is namespaced by realm")

-- ── Unlocks ─────────────────────────────────────────────────────────────────────────────────────

print("\n=== UNLOCKS ===")
local function textsAt(level)
  local t = {}
  for _, e in ipairs(M.Unlocks(level)) do t[#t + 1] = e.text end
  return t
end
local function has(list, s)
  for _, v in ipairs(list) do if v == s then return true end end
  return false
end

local at40 = textsAt(40)
assertf(has(at40, "Mortal Strike"), "rank 1 renders as the plain ability name")
assertf(has(at40, "Heroic Strike (Rank 6)"), "rank 6 renders with the server's own rank string")
-- AV is bracketed at 20 in the fixture, not the Blizzlike 51, so 20 is where it must surface.
local at20 = textsAt(20)
assertf(has(at20, "Arathi Basin") and has(at20, "Alterac Valley"),
        "battlegrounds appear at the server's bracket, not the Blizzlike one")
assertf(not has(at40, "Alterac Valley"), "and nowhere else")
assertf(has(at40, "Scholomance"), "dungeons appear at their bracket")

-- Talent points: totals observed at 39 and 40 differ by 1, so the OBSERVED step is used.
H.RealmStore().talentTotals[39] = 50
H.generation = H.generation + 1
assertf(H.TalentPointsGainedAt(40) == 1, "talent gain derived from observed totals")

local at42 = textsAt(42)
assertf(has(at42, "Molten Cleave (Rank 3)"),
        "a custom-server ability reaches the display end to end")

-- Fallback suppression: level 40 carries Journeyman Riding and Dual Talent Specialization in
-- Data.lua. Neither was harvested here, so both should still show.
assertf(has(at40, "Journeyman Riding"), "fallback feature shows when nothing observed covers it")

-- ...but once the harvest HAS seen it, the fallback must not double it up.
store["Journeyman Riding|"] = { n = "Journeyman Riding", r = nil, i = "i/ride", l = 30 }
H.generation = H.generation + 1
local at30, at40b = textsAt(30), textsAt(40)
assertf(has(at30, "Journeyman Riding"), "observed riding appears at the SERVER's level (30)")
local dupes = 0
for _, v in ipairs(at40b) do if v == "Journeyman Riding" then dupes = dupes + 1 end end
assertf(dupes == 0, "the Blizzlike fallback withdrew once the server's own answer was known")

-- ── Coverage report ─────────────────────────────────────────────────────────────────────────────

print("\n=== COVERAGE ===")
local c = M.Coverage()
assertf(c.entries > 0 and c.levels > 0, "coverage reports harvested abilities")
assertf(c.bgs == 3, "coverage counts battlegrounds")

print("")
if fails == 0 then
  print("#### LEVELUP OFFLINE: PASS ####")
  os.exit(0)
else
  print("#### LEVELUP OFFLINE: FAIL (" .. fails .. ") ####")
  os.exit(1)
end
