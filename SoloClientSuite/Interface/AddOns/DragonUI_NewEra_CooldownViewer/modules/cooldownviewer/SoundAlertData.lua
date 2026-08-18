-- DragonUI_NewEra/modules/cooldownviewer/SoundAlertData.lua — the Cooldown Manager's per-spell
-- "ability is ready" sound cues.
--
-- Downport of NewEra/CooldownViewer/SoundAlertData.lua, itself a port of retail's
-- Blizzard_CooldownViewer/CooldownViewerSoundAlertData.lua. Retail keys the catalogue by
-- Enum.CooldownViewerSound / Enum.CooldownViewerSoundCategory and plays the assigned kit through
-- C_Sound.PlaySoundWithOptions when a cooldown finishes.
--
-- WHY THE KIT IDS ARE DECORATION HERE. These are TWW SoundKit IDs (316401, 353392, …). 3.3.5a's
-- sound system knows nothing about them:
--
--   * `PlaySound` on this client takes a sound NAME string ("igMainMenuOpen"), not a numeric kit.
--   * `PlaySoundKitID` does take a number, but a 3.3.5a kit id — a four-digit index into this
--     client's own SoundEntries.dbc. A retail six-digit id resolves to nothing.
--
-- So upstream's `PlaySound(kit)` forward-compat fallback is DEAD on 3.3.5a — it cannot ever make a
-- sound. The only thing that works is playing the audio by file path, which is why upstream also
-- extracted each kit's OGG. We ship those extracted files (Sounds/cdm/<fileDataID>.ogg, each
-- verified to carry an "OggS" header) and play them with PlaySoundFile, which 3.3.5a supports for
-- .ogg — DBM has shipped .ogg cues on this client for years.
--
-- The kit id is therefore kept purely as the stable ASSIGNMENT KEY (what gets written to saved
-- settings) and as provenance back to retail. It is never handed to a sound API.
--
-- DROPPED vs upstream: the entire `Short` category (26 entries). Those kits are new in retail
-- 12.1.0 and their audio blobs were never on the CDN, so upstream has no extracted file for them
-- and relies on the PlaySound(kit) fallback — which, per above, is silent here. Listing 26 sounds
-- that can only ever play nothing would be a worse menu, so they are omitted. Everything upstream
-- could actually extract is present: 67 sounds across 6 categories, matching the 67 files shipped.

local NE = DragonUI_NewEra
NE.cooldownviewer = NE.cooldownviewer or {}
local M = NE.cooldownviewer

local SOUND_PATH = "Interface\\AddOns\\DragonUI_NewEra\\Sounds\\cdm\\"

-- Category display order — retail CooldownViewerUtil.lua:5-11, minus `Short` (see header).
M.SOUND_CATEGORY_ORDER = { "Animals", "Devices", "Impacts", "Instruments", "War2", "War3" }

-- entry = { kit = <retail soundKitID, the assignment key>, name = <English label>, file = <fdid> }
--
-- `file` is the FileDataID upstream's extraction pipeline resolved for the kit, and is the basename
-- of the shipped OGG. Both numbers come from upstream's verified tables — never hand-edit either.
M.SOUND_DATA = {
  Animals = {
    { kit = 316401, name = "Cat",         file = 7466002 },
    { kit = 316406, name = "Chicken",     file = 7466004 },
    { kit = 316407, name = "Cow",         file = 7466006 },
    { kit = 316409, name = "Gnoll",       file = 7466010 },
    { kit = 316715, name = "Goat",        file = 7466951 },
    { kit = 316411, name = "Lion",        file = 7466012 },
    { kit = 316412, name = "Panther",     file = 7466014 },
    { kit = 316413, name = "Rattlesnake", file = 7466016 },
    { kit = 316414, name = "Sheep",       file = 7466018 },
    { kit = 316415, name = "Wolf",        file = 7466020 },
  },
  Devices = {
    { kit = 316442, name = "Boat Horn",         file = 7466062 },
    { kit = 316436, name = "Air Horn",          file = 7466054 },
    { kit = 316713, name = "Bike Horn",         file = 7466947 },
    { kit = 316446, name = "Cash Register",     file = 7466070 },
    { kit = 316717, name = "Jackpot Bell",      file = 7466955 },
    { kit = 316718, name = "Jackpot Coins",     file = 7466957 },
    { kit = 316719, name = "Jackpot Fail",      file = 7466959 },
    { kit = 316433, name = "Rotary Phone Dial", file = 7466048 },
    { kit = 316492, name = "Rotary Phone Ring", file = 7466124 },
    { kit = 316425, name = "Stove Pipe",        file = 7466036 },
    { kit = 316430, name = "Trashcan Lid",      file = 7466046 },
  },
  Impacts = {
    { kit = 316528, name = "Anvil Strike",  file = 7466899 },
    { kit = 316419, name = "Bubble Smash",  file = 7466026 },
    { kit = 316531, name = "Low Thud",      file = 7466901 },
    { kit = 316532, name = "Metal Clanks",  file = 7466903 },
    { kit = 316486, name = "Metal Rattle",  file = 7466116 },
    { kit = 316484, name = "Metal Scrape",  file = 7466112 },
    { kit = 316536, name = "Metal Warble",  file = 7466913 },
    { kit = 316434, name = "Pop Click",     file = 7466050 },
    { kit = 316453, name = "Strange Clang", file = 7466082 },
    { kit = 316535, name = "Sword Scrape",  file = 7466911 },
  },
  Instruments = {
    { kit = 316493, name = "Bell Ring",             file = 7466126 },
    { kit = 316712, name = "Bell Trill",            file = 7466945 },
    { kit = 316722, name = "Brass",                 file = 7466965 },
    { kit = 316447, name = "Chime Ascending",       file = 7466072 },
    { kit = 316477, name = "Guitar Chug",           file = 7466098 },
    { kit = 316482, name = "Guitar Pinch",          file = 7466108 },
    { kit = 316509, name = "Pitch Pipe Distressed", file = 7466148 },
    { kit = 316501, name = "Pitch Pipe Note",       file = 7466138 },
    { kit = 316540, name = "Synth Big",             file = 7466915 },
    { kit = 316476, name = "Synth Buzz",            file = 7466096 },
    { kit = 316460, name = "Synth High",            file = 7466092 },
    { kit = 316723, name = "Warhorn",               file = 7466967 },
  },
  War2 = {
    { kit = 316731, name = "Abstract Whoosh", file = 7467017 },
    { kit = 316733, name = "Choir",           file = 7467021 },
    { kit = 316735, name = "Construction",    file = 7467023 },
    { kit = 316736, name = "Magic Chimes",    file = 7467025 },
    { kit = 316745, name = "Pig Squeal",      file = 7464792 },
    { kit = 316738, name = "Saws",            file = 7467029 },
    { kit = 316746, name = "Seal",            file = 7464794 },
    { kit = 316748, name = "Slow",            file = 7464798 },
    { kit = 316749, name = "Smith",           file = 7464800 },
    { kit = 316739, name = "Synth Stinger",   file = 7467031 },
    { kit = 316740, name = "Trumpet Rally",   file = 7467033 },
    { kit = 316737, name = "Zippy Magic",     file = 7467027 },
  },
  War3 = {
    { kit = 316773, name = "Bell",          file = 7467088 },
    { kit = 316774, name = "Crunchy Bell",  file = 7467090 },
    { kit = 316768, name = "Drum Splash",   file = 7467080 },
    { kit = 316775, name = "Error",         file = 7467092 },
    { kit = 316769, name = "Fanfare",       file = 7467082 },
    { kit = 316776, name = "Gate Open",     file = 7467094 },
    { kit = 316770, name = "Gold",          file = 7467072 },
    { kit = 316778, name = "Magic Shimmer", file = 7467098 },
    { kit = 316771, name = "Ringout",       file = 7467084 },
    { kit = 316765, name = "Rooster",       file = 7467074 },
    { kit = 316779, name = "Shimmer Bell",  file = 7467100 },
    { kit = 316766, name = "Wolf Howl",     file = 7467076 },
  },
}

-- kit -> entry, built once on first use.
local byKit
local function ensureLookup()
  if byKit then return end
  byKit = {}
  for _, cat in ipairs(M.SOUND_CATEGORY_ORDER) do
    for _, e in ipairs(M.SOUND_DATA[cat] or {}) do
      byKit[e.kit] = e
    end
  end
end

function M.GetSoundKitName(kit)
  ensureLookup()
  local e = kit and byKit[kit]
  return e and e.name or nil
end

-- Play a cooldown-ready cue. Returns true only if the client said it would actually play, so a
-- caller (the settings preview) can tell the difference between "played" and "silently did nothing".
--
-- pcall-guarded: a missing file must never raise, least of all mid-combat.
function M.PlayReadySound(kit)
  if not kit then return false end
  ensureLookup()
  local e = byKit[kit]
  if not (e and e.file and PlaySoundFile) then return false end
  local ok, willPlay = pcall(PlaySoundFile, SOUND_PATH .. e.file .. ".ogg", "SFX")
  return (ok and willPlay) and true or false
end

-- ── Per-spell assignment ────────────────────────────────────────────────────────────────────────
-- Stored beside every other Cooldown Manager setting, in DragonUI's profile (CooldownViewer.lua
-- `store`), as spellID -> soundKitID. Default is no sound: this is strictly opt-in.
function M.GetReadySoundKit(spellID)
  if not spellID then return nil end
  local cd = M._store and M._store(false)
  return cd and cd.sounds and cd.sounds[spellID] or nil
end

function M.SetReadySoundKit(spellID, kit)
  if not spellID then return end
  local cd = M._store and M._store(true)
  if not cd then return end
  cd.sounds = cd.sounds or {}
  cd.sounds[spellID] = kit   -- nil clears the assignment
end

-- Has the player assigned any ready sound at all? The alert ticker's early-out reads this, so the
-- default no-sound setup costs nothing per tick.
function M.HasAnyReadySound()
  local cd = M._store and M._store(false)
  local t = cd and cd.sounds
  if not t then return false end
  for _, kit in pairs(t) do
    if kit then return true end
  end
  return false
end

-- Walk the catalogue in display order. Mirrors retail CooldownViewerUtil.BuildSoundMenus; the
-- right-click assignment menu (ItemMenu.lua) is the consumer.
function M.BuildSoundMenu(addCategory, addEntry)
  for _, cat in ipairs(M.SOUND_CATEGORY_ORDER) do
    if addCategory then addCategory(cat) end
    for _, e in ipairs(M.SOUND_DATA[cat] or {}) do
      if addEntry then addEntry(cat, e) end
    end
  end
end
