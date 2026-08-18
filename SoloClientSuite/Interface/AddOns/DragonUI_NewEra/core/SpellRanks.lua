-- DragonUI_NewEra/core/SpellRanks.lua — per-ability rank tables built from the live spellbook.
--
-- DOWNPORT: NewEra ships `NE.spellbook.SPELLID.<CLASS>[name] = {every rank id}` as a GENERATED
-- table dumped from the client db2 (Generated/ClassSpells.lua et al). We don't have that pipeline
-- here, so this builds the equivalent by scanning the spellbook at login. The difference in
-- coverage is harmless for our consumers: the generated table included ranks the player has NOT
-- learned, and an unlearned rank's GetSpellCooldown reads 0 anyway.
--
-- WHY THIS IS LOAD-BEARING, not a nicety:
--
-- The CooldownViewer's rank resolution (ItemMixins.lua highestKnownRankID) is built on
-- `select(7, GetSpellInfo(name))` — on Era/TBC's modern engine the 7th return is the spellID of
-- the highest known rank. **On 3.3.5a it is castTime.** The WotLK signature is
--     name, rank, icon, cost, isFunnel, powerType, castTime, minRange, maxRange
-- (confirmed by !!!ClassicAPI/Util/C_Spell.lua:39, which destructures exactly that). Ported
-- verbatim, `highestKnownRankID` would return e.g. 1500 for a 1.5s cast and treat it as a spell
-- ID — silently, since it's a plausible-looking number. So on this client the spellbook scan is
-- the ONLY correct source for "highest rank the player knows".
--
-- Rank matters here because the curated cooldown lists key each ability by its RANK 1 id, while
-- the client tracks a cooldown against the EXACT rank cast — the "vanilla rank gotcha" documented
-- at ItemMixins.lua:108-119.
--
-- PUBLIC:
--   NE.spellbook.SPELLID[CLASS][name:lower()] -> { id, id, ... } ascending by rank
--   NE.spellbook.KnownRankIDs(name)           -> that list for the player's class, or nil
--   NE.spellbook.HighestKnownRankID(spellID, name) -> highest learned rank id, else spellID

local NE = DragonUI_NewEra
NE.spellbook = NE.spellbook or {}
local SB = NE.spellbook

SB.SPELLID = SB.SPELLID or {}

-- Lowercased set of every ability name currently in the player's spellbook, for the class in
-- SB.SPELLID. Built from GetSpellBookItemName ALONE — deliberately no spell-ID resolution — so it
-- still works when GetSpellLink parsing (compat/SpellBook.lua) fails for an entry. This is the
-- authoritative "do I actually know this?" test; see SB.IsSpellNameKnown.
SB.KNOWN_NAMES = SB.KNOWN_NAMES or {}

local BOOKTYPE = BOOKTYPE_SPELL or "spell"

-- "Rank 5" / "Rango 5" / "Rang 5" — every locale puts the digits last, so pull the trailing number
-- and ignore the word. Non-ranked spells (talents, racials, most utility) return nil and sort as 0.
local function rankNumber(rankText)
  if not rankText then return 0 end
  return tonumber(rankText:match("(%d+)%s*$")) or 0
end

-- Rebuild the whole table for the player's class from the live spellbook.
function SB.BuildRankTable()
  local _, class = UnitClass("player")
  if not class then return end
  if not (GetNumSpellTabs and GetSpellTabInfo and GetSpellBookItemName) then return end

  local byName = {}
  local ranks  = {}   -- name -> { [id] = rankNumber } for the sort below
  local known  = {}

  for tab = 1, (GetNumSpellTabs() or 0) do
    local _, _, offset, numSlots = GetSpellTabInfo(tab)
    if offset and numSlots then
      for slot = offset + 1, offset + numSlots do
        local name, rankText = GetSpellBookItemName(slot, BOOKTYPE)
        if name then
          -- Record the NAME before any id resolution, so a spell whose link can't be parsed is
          -- still correctly reported as known.
          known[name:lower()] = true
          -- compat/SpellBook.lua maps this onto GetSpellLink parsing on 3.3.5a; it returns
          -- ("SPELL", spellID) and spellID may be nil if the link can't be parsed.
          local _, spellID = GetSpellBookItemInfo(slot, BOOKTYPE)
          if spellID then
            local key = name:lower()
            local list = byName[key]
            if not list then list = {}; byName[key] = list; ranks[key] = {} end
            -- Guard against the same id appearing twice (a spell present in two tabs).
            if ranks[key][spellID] == nil then
              list[#list + 1] = spellID
              ranks[key][spellID] = rankNumber(rankText)
            end
          end
        end
      end
    end
  end

  -- Sort ascending by rank so the LAST element is the highest rank the player knows.
  --
  -- NOTE vs the NewEra source: its comment warns "the TBC seed merge APPENDS ids so last element
  -- isn't the top rank". That caveat applies to their generated+merged table. Ours is derived
  -- purely from the live spellbook and explicitly sorted here, so last == highest IS valid.
  for key, list in pairs(byName) do
    local r = ranks[key]
    table.sort(list, function(a, b)
      local ra, rb = r[a] or 0, r[b] or 0
      if ra == rb then return a < b end
      return ra < rb
    end)
  end

  SB.SPELLID[class] = byName
  SB.KNOWN_NAMES = known
  SB.built = true
  return byName
end

-- Build on demand if nothing has yet. PLAYER_LOGIN and SPELLS_CHANGED both rebuild on a deferred
-- timer (see the watcher below), but a consumer can run BEFORE that timer fires — the cooldown
-- viewers rebuild on PLAYER_ENTERING_WORLD, for instance. Without this, their first pass would read
-- an empty table and conclude the player knows nothing.
local function ensureBuilt()
  if not SB.built then
    local ok = pcall(SB.BuildRankTable)
    if not ok then return false end
  end
  return SB.built and true or false
end
SB.EnsureBuilt = ensureBuilt

-- The rank id list for an ability name, for the player's class.
function SB.KnownRankIDs(name)
  if not name then return nil end
  ensureBuilt()
  local _, class = UnitClass("player")
  local byName = class and SB.SPELLID[class]
  return byName and byName[name:lower()] or nil
end

-- Is this ability in the player's spellbook RIGHT NOW, at any rank?
--
-- This is the authoritative learn test, and it is deliberately name-keyed rather than id-keyed.
-- IsSpellKnown(id) checks one EXACT rank, so a curated rank-1 id reports false the moment the
-- player trains rank 2 — which is what made talent-granted and higher-rank abilities vanish from
-- the cooldown viewers. Matching on name is immune to that, and equally immune to level
-- requirements (relevant on level-squished servers, where a character can know an ability well
-- below its stock level).
function SB.IsSpellNameKnown(name)
  if not name then return false end
  ensureBuilt()
  return SB.KNOWN_NAMES[name:lower()] and true or false
end

-- Highest rank of `name` the player has learned. Falls back to the passed spellID for single-rank
-- abilities, racials, item use-spells, and anything not in the spellbook (e.g. an unlearned
-- curated entry being previewed).
function SB.HighestKnownRankID(spellID, name)
  if not name then return spellID end
  local list = SB.KnownRankIDs(name)
  if list and #list > 0 then return list[#list] end
  return spellID
end

-- Rebuild on the events that can change what's in the book. SPELLS_CHANGED fires on login and on
-- talent/spell changes; LEARNED_SPELL_IN_TAB on training a new rank.
local watcher = CreateFrame("Frame")
watcher:RegisterEvent("PLAYER_LOGIN")
watcher:RegisterEvent("SPELLS_CHANGED")
watcher:RegisterEvent("LEARNED_SPELL_IN_TAB")
-- Dual spec swaps the whole book. SPELLS_CHANGED does fire for it, but its ORDER against
-- ACTIVE_TALENT_GROUP_CHANGED is not guaranteed, and consumers that refresh on the talent event were
-- reading this table before it had caught up — a Holy talent stayed listed after switching to
-- Discipline until something unrelated refreshed. Registering both makes the rebuild certain; the
-- coalescing below means the extra event costs nothing when they arrive together.
watcher:RegisterEvent("ACTIVE_TALENT_GROUP_CHANGED")
watcher:SetScript("OnEvent", function()
  -- Coalesce: SPELLS_CHANGED can burst during login and talent swaps, and a full book walk is
  -- ~200 GetSpellLink string matches. One rebuild per frame is plenty.
  if watcher._queued then return end
  watcher._queued = true
  C_Timer.After(0, function()
    watcher._queued = false
    local ok, err = pcall(SB.BuildRankTable)
    if not ok then
      if NE.Log then NE.Log("SPELLRANKS", "rebuild failed: " .. tostring(err)) end
      return
    end
    -- Consumers gate on this table (the cooldown viewers' learn-check, for one), so anything that
    -- changed the spellbook — training, a talent respec, a spec switch — has to re-run them now
    -- that the table reflects reality. Without this a newly-learned ability only appeared after
    -- some later unrelated rebuild.
    for _, fn in ipairs(SB._onRebuilt) do pcall(fn) end
  end)
end)

-- Subscribe to "the spellbook changed and the table is up to date".
SB._onRebuilt = SB._onRebuilt or {}
function SB.OnRebuilt(fn)
  if type(fn) == "function" then SB._onRebuilt[#SB._onRebuilt + 1] = fn end
end
