-- DragonUI_NewEra/modules/cooldownviewer/CdmAuraCatalog.lua — GENERATED, DO NOT HAND-EDIT.
--
-- The per-class pool of trackable SELF-BUFFS: what the Tracked Buffs / Tracked Bars picker offers
-- you, as opposed to what you happen to have had. Retail reads a Blizzard-curated per-spec aura set
-- from C_CooldownViewer; 3.3.5a has no such table, so this is derived from the client's own
-- Spell.dbc + SkillLineAbility.dbc + Talent.dbc + TalentTab.dbc by
-- tools/cdm-spellgen/gen_auracatalog.py. No id is typed by hand.
--
-- An entry is a spell that puts a timed aura on the CASTER, lasting 0 < d <= 120s (the same window
-- M.BUFF_TRACK_MAX_DURATION gives the runtime auto-tracker), reached either directly or through one
-- EffectTriggerSpell hop — the hop is where the procs are.
--
--   id      the rank-1 aura spellID. Matching at runtime is by NAME, not id, so a down-ranked or
--           higher-ranked cast of the same buff still resolves (see M.GetBuffOverrides).
--   dur     seconds, for the picker's tooltip; the live viewer always reads the real aura.
--   tree    1-3, the talent tree the granting talent sits in, or nil for a baseline ability.
--   talent  the granting TALENT's name. Present = this row is spec-gated: the runtime asks
--           GetTalentInfo whether the player actually has it. Absent = always offered.
--
-- Racials are deliberately absent — they are race-gated, not class-gated, so they do not fit a
-- per-class catalog (retail's curated list has none either). The seen-aura registry picks them up
-- the first time you press them.
--
-- KNOWN GAP: Data/patch-4.MPQ and patch-S.mpq are encrypted and unreadable, so if this server
-- overrides spell data there, these ids reflect the stock client.

local NE = DragonUI_NewEra
NE.cooldownviewer = NE.cooldownviewer or {}
local M = NE.cooldownviewer

M.AURA_CATALOG_BY_CLASS = {

  DEATHKNIGHT = {
    { id = 57330, name = "Horn of Winter", dur = 120 },   -- class
    { id = 50447, name = "Bloody Vengeance", dur = 30, tree = 1, talent = "Bloody Vengeance" },   -- trigger
    { id = 49796, name = "Deathchill", dur = 30, tree = 2, talent = "Deathchill" },   -- class
    { id = 51124, name = "Killing Machine", dur = 30, tree = 2, talent = "Killing Machine" },   -- trigger
    { id = 61777, name = "Summon Gargoyle", dur = 30, tree = 3, talent = "Summon Gargoyle" },   -- trigger
    { id = 45529, name = "Blood Tap", dur = 20 },   -- class
    { id = 63583, name = "Desolation", dur = 20, tree = 3, talent = "Desolation" },   -- trigger
    { id = 50882, name = "Icy Talons", dur = 20, tree = 2, talent = "Icy Talons" },   -- trigger
    { id = 50421, name = "Scent of Blood", dur = 20, tree = 1, talent = "Scent of Blood" },   -- trigger
    { id = 51271, name = "Unbreakable Armor", dur = 20, tree = 2, talent = "Unbreakable Armor" },   -- class
    { id = 59052, name = "Freezing Fog", dur = 15, tree = 2, talent = "Rime" },   -- trigger
    { id = 49028, name = "Dancing Rune Weapon", dur = 12, tree = 1, talent = "Dancing Rune Weapon" },   -- class
    { id = 48792, name = "Icebound Fortitude", dur = 12 },   -- class
    { id = 51789, name = "Blade Barrier", dur = 10, tree = 1, talent = "Blade Barrier" },   -- trigger
    { id = 49039, name = "Lichborne", dur = 10, tree = 2, talent = "Lichborne" },   -- class
    { id = 55233, name = "Vampiric Blood", dur = 10, tree = 1, talent = "Vampiric Blood" },   -- class
    { id = 48707, name = "Anti-Magic Shell", dur = 5 },   -- class
  },
  DRUID = {
    { id = 16689, name = "Nature's Grasp", dur = 45 },   -- class
    { id = 61336, name = "Survival Instincts", dur = 20, tree = 2, talent = "Survival Instincts" },   -- class
    { id = 50334, name = "Berserk", dur = 15, tree = 2, talent = "Berserk" },   -- class
    { id = 16870, name = "Clearcasting", dur = 15, tree = 3, talent = "Omen of Clarity" },   -- trigger
    { id = 1850, name = "Dash", dur = 15 },   -- class
    { id = 22812, name = "Barkskin", dur = 12 },   -- class
    { id = 5229, name = "Enrage", dur = 10 },   -- class
    { id = 22842, name = "Frenzied Regeneration", dur = 10 },   -- class
    { id = 48391, name = "Owlkin Frenzy", dur = 10, tree = 1, talent = "Owlkin Frenzy" },   -- trigger
    { id = 62606, name = "Savage Defense", dur = 10 },   -- trigger
    { id = 48505, name = "Starfall", dur = 10, tree = 1, talent = "Starfall" },   -- class
    { id = 52610, name = "Savage Roar", dur = 9 },   -- class
    { id = 45281, name = "Natural Perfection", dur = 8, tree = 3, talent = "Natural Perfection" },   -- trigger
    { id = 69369, name = "Predator's Swiftness", dur = 8, tree = 2, talent = "Predatory Strikes" },   -- trigger
    { id = 5217, name = "Tiger's Fury", dur = 6 },   -- class
    { id = 16886, name = "Nature's Grace", dur = 3, tree = 1, talent = "Nature's Grace" },   -- trigger
  },
  HUNTER = {
    { id = 62757, name = "Call Stabled Pet", dur = 120 },   -- class
    { id = 34026, name = "Kill Command", dur = 30 },   -- class
    { id = 34477, name = "Misdirection", dur = 30 },   -- class
    { id = 35098, name = "Rapid Killing", dur = 20, tree = 2, talent = "Rapid Killing" },   -- trigger
    { id = 3045, name = "Rapid Fire", dur = 15 },   -- class
    { id = 53230, name = "Rapid Recuperation Effect", dur = 15, tree = 2, talent = "Rapid Recuperation" },   -- trigger
    { id = 53220, name = "Improved Steady Shot", dur = 12, tree = 2, talent = "Improved Steady Shot" },   -- trigger
    { id = 56453, name = "Lock and Load", dur = 12, tree = 3, talent = "Lock and Load" },   -- trigger
    { id = 6150, name = "Quick Shots", dur = 12 },   -- trigger
    { id = 53257, name = "Cobra Strikes", dur = 10, tree = 1, talent = "Cobra Strikes" },   -- trigger
    { id = 34471, name = "The Beast Within", dur = 10 },   -- class
    { id = 34833, name = "Master Tactician", dur = 8, tree = 3, talent = "Master Tactician" },   -- trigger
    { id = 34501, name = "Expose Weakness", dur = 7, tree = 3, talent = "Expose Weakness" },   -- trigger
    { id = 60798, name = "Monkey Speed", dur = 6 },   -- trigger
    { id = 19263, name = "Deterrence", dur = 5 },   -- class
    { id = 15571, name = "Dazed", dur = 4 },   -- trigger
    { id = 982, name = "Revive Pet", dur = 3 },   -- class
  },
  MAGE = {
    { id = 11426, name = "Ice Barrier", dur = 60, tree = 3, talent = "Ice Barrier" },   -- class
    { id = 1463, name = "Mana Shield", dur = 60 },   -- class
    { id = 543, name = "Fire Ward", dur = 30 },   -- class
    { id = 6143, name = "Frost Ward", dur = 30 },   -- class
    { id = 55342, name = "Mirror Image", dur = 30 },   -- class
    { id = 54748, name = "Burning Determination", dur = 20, tree = 2, talent = "Burning Determination" },   -- trigger
    { id = 12472, name = "Icy Veins", dur = 20, tree = 3, talent = "Icy Veins" },   -- class
    { id = 12042, name = "Arcane Power", dur = 15, tree = 1, talent = "Arcane Power" },   -- class
    { id = 12536, name = "Clearcasting", dur = 15, tree = 1, talent = "Arcane Concentration" },   -- trigger
    { id = 44544, name = "Fingers of Frost", dur = 15, tree = 3, talent = "Fingers of Frost" },   -- trigger
    { id = 57761, name = "Fireball!", dur = 15, tree = 3, talent = "Brain Freeze" },   -- trigger
    { id = 44401, name = "Missile Barrage", dur = 15, tree = 1, talent = "Missile Barrage" },   -- trigger
    { id = 54741, name = "Firestarter", dur = 10, tree = 2, talent = "Firestarter" },   -- trigger
    { id = 45438, name = "Ice Block", dur = 10 },   -- class
    { id = 64343, name = "Impact", dur = 10, tree = 2, talent = "Impact" },   -- trigger
    { id = 44413, name = "Incanter's Absorption", dur = 10, tree = 1, talent = "Incanter's Absorption" },   -- trigger
    { id = 31643, name = "Blazing Speed", dur = 8 },   -- class
    { id = 36032, name = "Arcane Blast", dur = 6 },   -- trigger
    { id = 46989, name = "Improved Blink", dur = 4, tree = 1, talent = "Improved Blink" },   -- trigger
    { id = 66, name = "Invisibility", dur = 3 },   -- class
    { id = 1953, name = "Blink", dur = 1 },   -- class
  },
  PALADIN = {
    { id = 53655, name = "Judgements of the Pure", dur = 60, tree = 1, talent = "Judgements of the Pure" },   -- trigger
    { id = 20050, name = "Vengeance", dur = 30, tree = 3, talent = "Vengeance" },   -- trigger
    { id = 31884, name = "Avenging Wrath", dur = 20 },   -- class
    { id = 31842, name = "Divine Illumination", dur = 15, tree = 1, talent = "Divine Illumination" },   -- class
    { id = 54428, name = "Divine Plea", dur = 15 },   -- class
    { id = 53672, name = "Infusion of Light", dur = 15, tree = 1, talent = "Infusion of Light" },   -- trigger
    { id = 31834, name = "Light's Grace", dur = 15, tree = 1, talent = "Light's Grace" },   -- trigger
    { id = 53489, name = "The Art of War", dur = 15, tree = 3, talent = "The Art of War" },   -- trigger
    { id = 498, name = "Divine Protection", dur = 12 },   -- class
    { id = 642, name = "Divine Shield", dur = 12 },   -- class
    { id = 20925, name = "Holy Shield", dur = 10, tree = 2, talent = "Holy Shield" },   -- class
    { id = 20128, name = "Redoubt", dur = 10, tree = 2, talent = "Redoubt" },   -- trigger
    { id = 20178, name = "Reckoning", dur = 8, tree = 2, talent = "Reckoning" },   -- trigger
    { id = 31821, name = "Aura Mastery", dur = 6, tree = 1, talent = "Aura Mastery" },   -- class
  },
  PRIEST = {
    { id = 63731, name = "Serendipity", dur = 20, tree = 2, talent = "Serendipity" },   -- trigger
    { id = 15258, name = "Shadow Weaving", dur = 15, tree = 3, talent = "Shadow Weaving" },   -- trigger
    { id = 15271, name = "Spirit Tap", dur = 15, tree = 3, talent = "Spirit Tap" },   -- trigger
    { id = 586, name = "Fade", dur = 10 },   -- class
    { id = 33151, name = "Surge of Light", dur = 10, tree = 2, talent = "Surge of Light" },   -- trigger
    { id = 45237, name = "Focused Will", dur = 8, tree = 1, talent = "Focused Will" },   -- trigger
    { id = 34754, name = "Holy Concentration", dur = 8, tree = 2, talent = "Holy Concentration" },   -- trigger
    { id = 49694, name = "Improved Spirit Tap", dur = 8, tree = 3, talent = "Improved Spirit Tap" },   -- trigger
    { id = 27813, name = "Blessed Recovery", dur = 6 },   -- class
    { id = 33143, name = "Blessed Resilience", dur = 6, tree = 2, talent = "Blessed Resilience" },   -- trigger
    { id = 59887, name = "Borrowed Time", dur = 6, tree = 1, talent = "Borrowed Time" },   -- trigger
    { id = 47585, name = "Dispersion", dur = 6, tree = 3, talent = "Dispersion" },   -- class
    { id = 14743, name = "Focused Casting", dur = 6, tree = 1, talent = "Martyrdom" },   -- trigger
  },
  ROGUE = {
    { id = 57934, name = "Tricks of the Trade", dur = 30 },   -- class
    { id = 14183, name = "Premeditation", dur = 20, tree = 3, talent = "Premeditation" },   -- class
    { id = 14143, name = "Remorseless", dur = 20, tree = 1, talent = "Remorseless Attacks" },   -- trigger
    { id = 13750, name = "Adrenaline Rush", dur = 15, tree = 2, talent = "Adrenaline Rush" },   -- class
    { id = 13877, name = "Blade Flurry", dur = 15, tree = 2, talent = "Blade Flurry" },   -- class
    { id = 5277, name = "Evasion", dur = 15 },   -- class
    { id = 2983, name = "Sprint", dur = 15 },   -- class
    { id = 11327, name = "Vanish", dur = 10 },   -- trigger
    { id = 14278, name = "Ghostly Strike", dur = 7, tree = 3, talent = "Ghostly Strike" },   -- class
    { id = 48659, name = "Feint", dur = 6 },   -- class
    { id = 51713, name = "Shadow Dance", dur = 6, tree = 3, talent = "Shadow Dance" },   -- class
    { id = 5171, name = "Slice and Dice", dur = 6 },   -- class
    { id = 31224, name = "Cloak of Shadows", dur = 5 },   -- class
    { id = 36554, name = "Shadowstep", dur = 3, tree = 3, talent = "Shadowstep" },   -- class
    { id = 51690, name = "Killing Spree", dur = 2, tree = 2, talent = "Killing Spree" },   -- class
    { id = 32645, name = "Envenom", dur = 1 },   -- class
    { id = 51699, name = "Honor Among Thieves", dur = 1 },   -- class
  },
  SHAMAN = {
    { id = 16166, name = "Elemental Mastery", dur = 30, tree = 1, talent = "Elemental Mastery" },   -- class
    { id = 53817, name = "Maelstrom Weapon", dur = 30, tree = 2, talent = "Maelstrom Weapon" },   -- trigger
    { id = 16246, name = "Clearcasting", dur = 15, tree = 1, talent = "Elemental Focus" },   -- trigger
    { id = 16257, name = "Flurry", dur = 15, tree = 2, talent = "Flurry" },   -- trigger
    { id = 43339, name = "Focused", dur = 15 },   -- class
    { id = 30823, name = "Shamanistic Rage", dur = 15, tree = 2, talent = "Shamanistic Rage" },   -- class
    { id = 53390, name = "Tidal Waves", dur = 15, tree = 3, talent = "Tidal Waves" },   -- trigger
    { id = 30165, name = "Elemental Devastation", dur = 10, tree = 1, talent = "Elemental Devastation" },   -- trigger
    { id = 55198, name = "Tidal Force", dur = 2, tree = 3, talent = "Tidal Force" },   -- class
  },
  WARLOCK = {
    { id = 47241, name = "Metamorphosis", dur = 30, tree = 2, talent = "Metamorphosis" },   -- trigger
    { id = 6229, name = "Shadow Ward", dur = 30 },   -- class
    { id = 54274, name = "Backdraft", dur = 15, tree = 3, talent = "Backdraft" },   -- trigger
    { id = 18708, name = "Fel Domination", dur = 15, tree = 2, talent = "Fel Domination" },   -- class
    { id = 50589, name = "Immolation Aura", dur = 15 },   -- trigger
    { id = 47383, name = "Molten Core", dur = 15, tree = 2, talent = "Molten Core" },   -- trigger
    { id = 63165, name = "Decimation", dur = 10, tree = 2, talent = "Decimation" },   -- trigger
    { id = 64368, name = "Eradication", dur = 10, tree = 1, talent = "Eradication" },   -- trigger
    { id = 47426, name = "Kindling Soul", dur = 10 },   -- trigger
    { id = 18093, name = "Pyroclasm", dur = 10, tree = 3, talent = "Pyroclasm" },   -- trigger
    { id = 53756, name = "Sudden Fear", dur = 10 },   -- class
    { id = 33151, name = "Surge of Light", dur = 10 },   -- trigger
    { id = 34936, name = "Backlash", dur = 8, tree = 3, talent = "Backlash" },   -- trigger
    { id = 48020, name = "Demonic Circle: Teleport", dur = 1 },   -- class
  },
  WARRIOR = {
    { id = 12292, name = "Death Wish", dur = 30, tree = 2, talent = "Death Wish" },   -- class
    { id = 12328, name = "Sweeping Strikes", dur = 30, tree = 1, talent = "Sweeping Strikes" },   -- class
    { id = 12976, name = "Last Stand", dur = 20 },   -- class
    { id = 32216, name = "Victorious", dur = 20 },   -- trigger
    { id = 12966, name = "Flurry", dur = 15, tree = 2, talent = "Flurry" },   -- trigger
    { id = 12880, name = "Enrage", dur = 12, tree = 2, talent = "Enrage" },   -- trigger
    { id = 1719, name = "Recklessness", dur = 12 },   -- class
    { id = 20230, name = "Retaliation", dur = 12 },   -- class
    { id = 871, name = "Shield Wall", dur = 12 },   -- class
    { id = 18499, name = "Berserker Rage", dur = 10 },   -- class
    { id = 29131, name = "Bloodrage", dur = 10 },   -- trigger
    { id = 55694, name = "Enraged Regeneration", dur = 10 },   -- class
    { id = 65156, name = "Juggernaut", dur = 10, tree = 1, talent = "Juggernaut" },   -- trigger
    { id = 29841, name = "Second Wind", dur = 10 },   -- class
    { id = 2565, name = "Shield Block", dur = 10 },   -- class
    { id = 52437, name = "Sudden Death", dur = 10, tree = 1, talent = "Sudden Death" },   -- trigger
    { id = 60503, name = "Taste for Blood", dur = 9, tree = 1, talent = "Taste for Blood" },   -- trigger
    { id = 23885, name = "Bloodthirst", dur = 8 },   -- class
    { id = 46924, name = "Bladestorm", dur = 6, tree = 1, talent = "Bladestorm" },   -- class
    { id = 16488, name = "Blood Craze", dur = 6, tree = 2, talent = "Blood Craze" },   -- trigger
    { id = 46916, name = "Slam!", dur = 5, tree = 2, talent = "Bloodsurge" },   -- trigger
    { id = 23920, name = "Spell Reflection", dur = 5 },   -- class
    { id = 50227, name = "Sword and Board", dur = 5, tree = 3, talent = "Sword and Board" },   -- trigger
  },
}

