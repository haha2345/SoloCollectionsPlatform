-- DragonUI_NewEra/modules/levelup/Harvest.lua — learn this server's level unlocks FROM this server.
--
-- WHY THIS FILE EXISTS
--
-- Every level-up display before this one shipped a hand-typed `spellList[CLASS][level] = {ids}`
-- table: the standalone 3.3.5 addon carries ~900 lines of it, NewEra derives an equivalent from its
-- spellbook seed. Both are correct only for the server they were written against. This addon runs on
-- many servers, and private servers change trainer levels, add custom abilities, and remove others.
-- A baked table is wrong on arrival there, and silently — it shows spells that do not exist and
-- misses the ones that do.
--
-- The 3.3.5a client can just ask. A trainer window is the server telling you, for this character's
-- class on this realm, exactly which abilities exist and at which level each unlocks:
--
--   GetTrainerServiceInfo(i)     -> name, rank subtext ("Rank 4"), serviceType
--   GetTrainerServiceLevelReq(i) -> the level the SERVER requires
--   GetTrainerServiceIcon(i)     -> the icon path
--
-- That is precisely the banner's display payload — {text, subText, icon} plus the level key — so
-- nothing here ever needs a spell ID. Which is the whole trick: a server that invents
-- "Molten Cleave (Rank 3)" at level 42 is picked up with the right name, rank, icon and level
-- without this addon knowing such a spell could exist.
--
-- The decisive detail is the `unavailable` filter. It reveals services the player CANNOT yet buy,
-- so one visit at level 20 harvests the level 21-80 requirements in a single sweep. Most of the
-- table lands on the first trainer visit; `used` backfills everything already learned.
--
-- Battlegrounds work the same way: GetBattlegroundInfo returns minlevel per bracket, so a server
-- that opens Alterac Valley at 20 needs no configuration.
--
-- What this CANNOT learn is covered by Data.lua's curated fallback, and Unlocks.lua is what decides
-- between them (observed wins).

local NE = DragonUI_NewEra
if not NE or NE.disabled then return end

local M = NE.levelup
local H = {}
M.harvest = H

-- ── Tunables ────────────────────────────────────────────────────────────────────────────────────
local MAX_ENTRIES_PER_LEVEL = 40    -- a runaway guard, not a display cap; Unlocks.lua does display
local MAX_HEADER_EXPANDS    = 24    -- profession trainers have headers; class trainers rarely do
local MAX_BG_INDEX          = 20    -- NUM_BATTLEGROUNDS is 6 on 3.3.5a; loop defensively past it

-- ── Store ───────────────────────────────────────────────────────────────────────────────────────
--
-- Keyed by realm so ONE installed copy of the addon serves many servers without cross-contaminating
-- their data. Per class within that, because a Rogue's trainer cannot tell you anything about a
-- Mage's abilities.
--
--   db.levelup.realms[realm].classes[CLASS][nameKey] = { n=name, r=rank, i=icon, l=level }
--   db.levelup.realms[realm].bgs[name]               = minLevel
--   db.levelup.realms[realm].talentTotals[level]     = total talent points at that level
--
-- Entries are keyed by name|rank rather than appended to a per-level list, so re-harvesting the
-- same trainer overwrites in place instead of accumulating duplicates. Unlocks.lua inverts this
-- into a per-level index at read time.

-- Bumped when previously-harvested data is known to be wrong and must be re-learned. v2: builds
-- before the IsTradeskillTrainer gate below harvested PROFESSION trainers into the class store, so
-- any realm harvested by one of them has profession ranks (Journeyman Blacksmithing, Apprentice
-- Riding, …) sitting in its class buckets, ready to be announced on level-up. There is no way to
-- tell those entries apart after the fact — nothing recorded which trainer they came from — so the
-- classes table is dropped and re-learned on the next class-trainer visit. Nothing is lost
-- meanwhile: Unlocks.lua falls back to Data.lua's curated list whenever there's no observed data.
-- bgs and talentTotals are untouched; no trainer ever wrote them.
local STORE_VERSION = 2

local function realmStore()
  if not NE.db then return nil end
  NE.db.levelup = NE.db.levelup or {}
  NE.db.levelup.realms = NE.db.levelup.realms or {}
  local realm = GetRealmName() or "?"
  local r = NE.db.levelup.realms[realm]
  if not r then
    r = { classes = {}, bgs = {}, talentTotals = {}, v = STORE_VERSION }
    NE.db.levelup.realms[realm] = r
  end
  if (r.v or 1) < STORE_VERSION then
    r.classes = {}
    r.v = STORE_VERSION
  end
  r.classes      = r.classes      or {}
  r.bgs          = r.bgs          or {}
  r.talentTotals = r.talentTotals or {}
  return r
end
H.RealmStore = realmStore

local function classStore()
  local r = realmStore()
  if not r then return nil end
  local _, classFile = UnitClass("player")
  classFile = classFile or "?"
  r.classes[classFile] = r.classes[classFile] or {}
  return r.classes[classFile]
end
H.ClassStore = classStore

-- Bumped whenever a harvest actually writes something, so Unlocks.lua's per-level cache knows to
-- rebuild instead of serving a stale index for the rest of the session.
H.generation = 0
local function touch() H.generation = H.generation + 1 end

-- ── Trainer harvest ─────────────────────────────────────────────────────────────────────────────

-- Expand every collapsed group header so the walk below can see the services underneath.
-- GetNumTrainerServices reflects the list AS DISPLAYED, so a collapsed header hides its contents
-- from us as surely as it does from the player. ExpandTrainerSkillLine raises a Lua error when the
-- index is not a header, hence the serviceType check and the pcall around it.
--
-- Expanding renumbers the list, so each expansion restarts the scan. Bounded by MAX_HEADER_EXPANDS:
-- a malformed list must not spin here.
local function expandHeaders()
  local expanded = {}
  for _ = 1, MAX_HEADER_EXPANDS do
    local found = false
    for i = 1, (GetNumTrainerServices() or 0) do
      local name, _, serviceType, isExpanded = GetTrainerServiceInfo(i)
      if serviceType == "header" and not isExpanded then
        if pcall(ExpandTrainerSkillLine, i) then
          expanded[#expanded + 1] = name
          found = true
          break        -- indices just shifted; rescan from the top
        end
      end
    end
    if not found then break end
  end
  return expanded
end

local function collapseHeaders(names)
  if not (names and #names > 0 and CollapseTrainerSkillLine) then return end
  local wanted = {}
  for _, n in ipairs(names) do wanted[n] = true end
  for _ = 1, MAX_HEADER_EXPANDS do
    local found = false
    for i = 1, (GetNumTrainerServices() or 0) do
      local name, _, serviceType, isExpanded = GetTrainerServiceInfo(i)
      if serviceType == "header" and isExpanded and wanted[name] then
        if pcall(CollapseTrainerSkillLine, i) then found = true; break end
      end
    end
    if not found then break end
  end
end

-- One pass over the currently-displayed service list, writing into the class store.
local function readServices(store)
  local perLevel, wrote = {}, 0
  for i = 1, (GetNumTrainerServices() or 0) do
    local name, rank, serviceType = GetTrainerServiceInfo(i)
    if name and serviceType ~= "header" then
      local level = GetTrainerServiceLevelReq(i)
      -- No level requirement means the gate is something else — profession recipes gate on SKILL,
      -- not character level, and a crafting trainer would otherwise flood every bucket. Those are
      -- exactly the entries this drops.
      if level and level >= 1 then
        perLevel[level] = (perLevel[level] or 0) + 1
        if perLevel[level] <= MAX_ENTRIES_PER_LEVEL then
          local icon = GetTrainerServiceIcon and GetTrainerServiceIcon(i) or nil
          local key = name .. "|" .. (rank or "")
          local prev = store[key]
          if not (prev and prev.l == level and prev.i == icon) then
            store[key] = { n = name, r = rank, i = icon, l = level }
            wrote = wrote + 1
          end
        end
      end
    end
  end
  return wrote
end

-- The full harvest: widen the filters, read everything, put the filters back.
--
-- Save/restore is not optional politeness — SetTrainerServiceTypeFilter drives the checkboxes on
-- Blizzard's own ClassTrainerFrame, and leaving them widened would silently change what the player
-- sees for the rest of the session. GetTrainerServiceTypeFilter gives us the getter to restore
-- from. The whole thing runs inside one event handler, so the widened state never reaches a frame.
function H.HarvestTrainer()
  if not (GetNumTrainerServices and GetTrainerServiceInfo and GetTrainerServiceLevelReq) then return 0 end
  if (GetNumTrainerServices() or 0) == 0 then return 0 end

  -- PROFESSION TRAINERS ARE NOT A SOURCE OF CLASS UNLOCKS. 3.3.5a runs both through the same
  -- ClassTrainerFrame and the same GetTrainerService* API, so without this check a visit to the
  -- blacksmith harvests into the CLASS store and the banner starts announcing professions on
  -- level-up. New class abilities are the whole point of that banner; recipes are not.
  --
  -- The readServices "no level requirement" filter below is not enough on its own: individual
  -- recipes gate on skill and are dropped by it, but the profession RANKS a trainer also sells
  -- (Journeyman/Expert/Artisan/Master, and riding) gate on CHARACTER LEVEL and sail straight
  -- through. IsTradeskillTrainer is the client's own class-vs-tradeskill answer — it exists on
  -- 3.3.5a and returns 1 at a profession trainer.
  if IsTradeskillTrainer and IsTradeskillTrainer() then return 0 end
  local store = classStore()
  if not store then return 0 end

  local saved
  if GetTrainerServiceTypeFilter and SetTrainerServiceTypeFilter then
    saved = {
      available   = GetTrainerServiceTypeFilter("available"),
      unavailable = GetTrainerServiceTypeFilter("unavailable"),
      used        = GetTrainerServiceTypeFilter("used"),
    }
    SetTrainerServiceTypeFilter("available", 1)
    SetTrainerServiceTypeFilter("unavailable", 1)   -- the forward-looking levels live behind this
    SetTrainerServiceTypeFilter("used", 1)          -- and the already-learned history behind this
  end

  local expanded = expandHeaders()
  local ok, wrote = pcall(readServices, store)
  collapseHeaders(expanded)

  if saved then
    SetTrainerServiceTypeFilter("available",   saved.available   and 1 or 0)
    SetTrainerServiceTypeFilter("unavailable", saved.unavailable and 1 or 0)
    SetTrainerServiceTypeFilter("used",        saved.used        and 1 or 0)
  end

  -- Blizzard's frame cached its row data before we touched anything; make it re-read so its list
  -- and checkboxes agree with the filters we just restored.
  if ClassTrainerFrame and ClassTrainerFrame:IsShown() and ClassTrainerFrame_Update then
    pcall(ClassTrainerFrame_Update)
  end

  if not ok then return 0 end
  if wrote > 0 then touch() end
  return wrote
end

-- ── Battlegrounds ───────────────────────────────────────────────────────────────────────────────
--
-- minlevel is the SERVER's bracket, so this replaces a hardcoded WSG-10/AB-20/AV-51 table outright
-- and comes back localized for free.
function H.HarvestBattlegrounds()
  if not GetBattlegroundInfo then return 0 end
  local r = realmStore()
  if not r then return 0 end
  local wrote = 0
  for i = 1, MAX_BG_INDEX do
    local ok, name, _, _, minLevel = pcall(GetBattlegroundInfo, i)
    if not ok or not name then break end
    if minLevel and minLevel >= 1 and r.bgs[name] ~= minLevel then
      r.bgs[name] = minLevel
      wrote = wrote + 1
    end
  end
  if wrote > 0 then touch() end
  return wrote
end

-- ── Dungeons and raids ──────────────────────────────────────────────────────────────────────────
--
-- The standalone 3.3.5 addon ships this as a 148-line hand-typed list of English dungeon names,
-- duplicated again in Russian, and defines its lookup INSIDE `if GetLocale() == "enUS"` — so on a
-- German or Chinese client the whole feature silently disappears. None of that is necessary here:
-- GetLFGDungeonInfo answers with the localized name and the level bracket, and LFDDungeonList /
-- LFRRaidList are the client's own id arrays (modules/lfg/Dungeons.lua:278 and Raids.lua:240 read
-- exactly these). A server that re-brackets its dungeons is followed automatically.
function H.HarvestDungeons()
  if not GetLFGDungeonInfo then return 0 end
  local r = realmStore()
  if not r then return 0 end
  r.dungeons = r.dungeons or {}

  -- Populates LFDDungeonList/LFRRaidList the first time; a no-op afterwards.
  if LFGDungeonList_Setup then pcall(LFGDungeonList_Setup) end

  local wrote = 0
  local function take(list, kind)
    if type(list) ~= "table" then return end
    for _, id in ipairs(list) do
      local ok, name, typeID, minLevel = pcall(GetLFGDungeonInfo, id)
      if ok and name and minLevel and minLevel >= 1 then
        -- Heroics share a name with their normal version and would overwrite it; the level is what
        -- distinguishes them, so key on both.
        local heroic = (TYPEID_HEROIC_DIFFICULTY and typeID == TYPEID_HEROIC_DIFFICULTY) or nil
        local key = name .. "|" .. minLevel
        local prev = r.dungeons[key]
        if not (prev and prev.l == minLevel) then
          r.dungeons[key] = { n = name, l = minLevel, k = kind, h = heroic }
          wrote = wrote + 1
        end
      end
    end
  end
  take(LFDDungeonList, "Dungeon")
  take(LFRRaidList,    "Raid")

  if wrote > 0 then touch() end
  return wrote
end

-- ── Talent points ───────────────────────────────────────────────────────────────────────────────
--
-- TOTAL points, not unspent: unspent alone drops to zero the moment the player spends them, and a
-- level-to-level diff would then read as "no talent point this level". Total = unspent + the sum of
-- what each tab reports spent, which is stable no matter how the player allocates.
local function totalTalentPoints()
  if not GetUnspentTalentPoints then return nil end
  local okU, unspent = pcall(GetUnspentTalentPoints)
  if not okU or not unspent then return nil end
  local spent = 0
  if GetNumTalentTabs and GetTalentTabInfo then
    for tab = 1, (GetNumTalentTabs() or 0) do
      local ok, _, _, pointsSpent = pcall(GetTalentTabInfo, tab)
      if ok and pointsSpent then spent = spent + pointsSpent end
    end
  end
  return unspent + spent
end
H.TotalTalentPoints = totalTalentPoints

function H.RecordTalentPoints()
  local r = realmStore()
  if not r then return end
  local level = UnitLevel("player")
  local total = totalTalentPoints()
  if not (level and total) then return end
  if r.talentTotals[level] ~= total then
    r.talentTotals[level] = total
    touch()
  end
end

-- Points gained AT this level, or nil when we have not observed both sides of the step yet.
-- Unlocks.lua falls back to the curated rule in that case rather than inventing a number.
function H.TalentPointsGainedAt(level)
  local r = realmStore()
  if not (r and level) then return nil end
  local here, before = r.talentTotals[level], r.talentTotals[level - 1]
  if not (here and before) then return nil end
  local d = here - before
  if d > 0 then return d end
  return nil
end

-- ── Spellbook backstop ──────────────────────────────────────────────────────────────────────────
--
-- Catches what no trainer can tell us: abilities the SERVER grants automatically on level-up. They
-- never appear in a trainer list at any filter, so without this they are invisible to the harvest.
--
-- Walks the book the same way core/SpellRanks.lua does (GetNumSpellTabs / GetSpellTabInfo /
-- GetSpellBookItemName) and records by name, never by id — see that file's header for why id
-- resolution is the fragile part on this client.
local BOOKTYPE = BOOKTYPE_SPELL or "spell"
local lastBook

local function snapshotBook()
  if not (GetNumSpellTabs and GetSpellTabInfo and GetSpellBookItemName) then return nil end
  local seen = {}
  for tab = 1, (GetNumSpellTabs() or 0) do
    local _, _, offset, numSlots = GetSpellTabInfo(tab)
    if offset and numSlots then
      for slot = offset + 1, offset + numSlots do
        local name, rank = GetSpellBookItemName(slot, BOOKTYPE)
        if name then
          seen[name .. "|" .. (rank or "")] = slot
        end
      end
    end
  end
  return seen
end

-- Diff against the previous snapshot and attribute anything new to the CURRENT level. Only records
-- when a previous snapshot exists — the first snapshot of a session is the baseline, not a set of
-- freshly-learned spells.
function H.ScanSpellbook()
  local now = snapshotBook()
  if not now then return 0 end
  local prev = lastBook
  lastBook = now
  if not prev then return 0 end

  local store = classStore()
  if not store then return 0 end
  local level = UnitLevel("player")
  if not level then return 0 end

  local wrote = 0
  for key, slot in pairs(now) do
    if prev[key] == nil then
      -- A trainer-taught spell reaches the book too, and the trainer already recorded it with its
      -- true requirement. Overwriting that with "the level I happened to train it" would be strictly
      -- worse data, so an existing entry always wins.
      if store[key] == nil then
        local name, rank = key:match("^(.-)|(.*)$")
        local icon
        if GetSpellBookItemTexture then
          local ok, t = pcall(GetSpellBookItemTexture, slot, BOOKTYPE)
          if ok then icon = t end
        elseif GetSpellTexture then
          local ok, t = pcall(GetSpellTexture, slot, BOOKTYPE)
          if ok then icon = t end
        end
        store[key] = { n = name, r = (rank ~= "" and rank or nil), i = icon, l = level, auto = true }
        wrote = wrote + 1
      end
    end
  end
  if wrote > 0 then touch() end
  return wrote
end

-- Re-baseline without recording. Used at login, where every spell in the book would otherwise look
-- newly learned at the player's current level.
function H.ResetSpellbookBaseline()
  lastBook = snapshotBook()
end

-- ── Wiring ──────────────────────────────────────────────────────────────────────────────────────
--
-- TRAINER_SHOW rather than a timer: it is the only moment the trainer API answers at all
-- (GetNumTrainerServices returns 0 otherwise), and handling it synchronously is what keeps the
-- widened filters from ever being rendered.
local driver = CreateFrame("Frame")
driver:RegisterEvent("PLAYER_ENTERING_WORLD")
driver:RegisterEvent("TRAINER_SHOW")
driver:RegisterEvent("PLAYER_LEVEL_UP")
driver:RegisterEvent("CHARACTER_POINTS_CHANGED")
driver:RegisterEvent("LFG_UPDATE_RANDOM_INFO")
driver:RegisterEvent(NE.EV_LEARNED_SPELL or "LEARNED_SPELL_IN_TAB")

driver:SetScript("OnEvent", function(_, event)
  if not NE.db then return end          -- pre-SavedVariables; nothing to write into yet
  if event == "PLAYER_ENTERING_WORLD" then
    H.ResetSpellbookBaseline()
    H.HarvestBattlegrounds()
    H.HarvestDungeons()
    H.RecordTalentPoints()
  elseif event == "TRAINER_SHOW" then
    H.HarvestTrainer()
  elseif event == "LFG_UPDATE_RANDOM_INFO" then
    -- The dungeon lists are not reliably populated at login; this is when the server has answered.
    H.HarvestDungeons()
  elseif event == "PLAYER_LEVEL_UP" then
    -- All level-sensitive and cheap; the banner reads them a moment later.
    H.HarvestBattlegrounds()
    H.HarvestDungeons()
    H.RecordTalentPoints()
  elseif event == "CHARACTER_POINTS_CHANGED" then
    H.RecordTalentPoints()
  else
    H.ScanSpellbook()
  end
end)
