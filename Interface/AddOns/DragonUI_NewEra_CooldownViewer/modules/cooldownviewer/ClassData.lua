-- DragonUI_NewEra/modules/cooldownviewer/ClassData.lua — curated per-class cooldown data.
--
-- DOWNPORT of NewEra/CooldownViewer/ClassData.lua. The BODY of this file is copied byte-for-byte
-- from the 1.15 source (mechanically, not retyped — a transcription slip here is a silently wrong
-- spell). Only the namespace preamble is rewritten for the DragonUI_NewEra addon table.
--
-- FLAVOUR NOTE: these are the VANILLA 1.15 curated lists. Rank-1 spell IDs are stable across
-- expansions, so they resolve correctly on 3.3.5a — but they are not COMPLETE for WotLK: Death
-- Knight is absent entirely, and every other class has 3.3.5a abilities missing (Bladestorm,
-- Penance, Deep Freeze, Killing Spree, ...). CdmSeedWotLK.lua (Phase 2) appends those additively,
-- exactly as CdmSeedTBC.lua does for TBC upstream. Until it lands, expect a sparse but correct set.
--
-- Tables provided: M.ESSENTIAL_BY_CLASS / UTILITY_BY_CLASS / BUFFICON_BY_CLASS / BUFFBAR_BY_CLASS
-- / SPELL_DATA_BY_CATEGORY (the category->table map) / RACIAL_BY_RACE.

local NE = DragonUI_NewEra
NE.cooldownviewer = NE.cooldownviewer or {}
local M = NE.cooldownviewer
-- Vanilla 1.15.x per-class Essential cooldown data.
--
-- Retail's Essential bucket = OFFENSIVE moves: offensive buffs, damage burst
-- cooldowns, offensive procs/passives, on-CD damage abilities. Anything that
-- contributes to the player's burst window or sustained damage output.
-- Confirmed by user observation 2026-05-28: large icons = offensive, small
-- icons = defensive/CC/utility.
M.ESSENTIAL_BY_CLASS = {
  WARRIOR = {
    1719,   -- Recklessness (offensive burst)
    12292,   -- Death Wish (Fury 31pt burst)
    23881,   -- Bloodthirst (Fury 31pt)
    12294,   -- Mortal Strike (Arms 31pt)
    2687,   -- Bloodrage (rage gen, 1min)
  },
  PALADIN = {
    24275,   -- Hammer of Wrath (Ret execute)
    20473,   -- Holy Shock (Holy 31pt)
    20271,   -- Judgement (main Ret damage on CD)
    879,   -- Exorcism (holy damage, 15s)
    26573,   -- Consecration (AoE, 8s)
  },
  HUNTER = {
    19574,   -- Bestial Wrath (BM 31pt burst)
    3045,   -- Rapid Fire (offensive haste)
    19434,   -- Aimed Shot (channeled damage CD)
    14288,   -- Multi-Shot (AoE CD)
    3044,   -- Arcane Shot (instant, 6s)
  },
  ROGUE = {
    13750,   -- Adrenaline Rush (Combat 31pt)
    13877,   -- Blade Flurry (Combat cleave)
    14177,   -- Cold Blood (Assa next-crit)
    14183,   -- Premeditation (Sub opener)
    11305,   -- Sprint (positioning)
  },
  PRIEST = {
    8092,   -- Mind Blast (8s)
    10060,   -- Power Infusion (Disc 31pt, 3min)
    14751,   -- Inner Focus (Disc 15pt, 3min)
    2944,   -- Devouring Plague (Undead, 3min)
  },
  MAGE = {
    11129,   -- Combustion (Fire 31pt)
    -- 12472 was here labelled "Cold Snap" and is Icy Veins; 11958 sits in Utility below labelled
    -- "Ice Block" and is Cold Snap. Two wrong labels that between them left mages with no Ice Block
    -- at all. Both abilities are curated by name in tools/cdm-spellgen/gen_wotlk.py, which resolves
    -- them from Spell.dbc, so they are dropped here rather than relabelled — one home per ability.
    12043,   -- Presence of Mind (Arcane 30pt)
    12042,   -- Arcane Power (Arcane 31pt)
    2136,   -- Fire Blast (instant, 8s)
  },
  WARLOCK = {
    6789,   -- Death Coil (fear + drain)
    17962,   -- Conflagrate (Destro 31pt)
    6353,   -- Soul Fire (big nuke, 1min)
    17877,   -- Shadowburn (execute, 15s)
    603,   -- Curse of Doom (60s DoT)
  },
  DRUID = {
    770,    -- Faerie Fire (Balance)
    16857,   -- Faerie Fire (Feral) armor debuff
    17116,   -- Nature's Swiftness (Resto 30pt)
    16914,   -- Hurricane (Balance 30pt AoE)
    5217,   -- Tiger's Fury (Cat damage buff)
  },
  SHAMAN = {
    2825,   -- Bloodlust (Enhance 31pt haste)
    16166,   -- Elemental Mastery (Ele 31pt)
    17364,   -- Stormstrike (Enhance 31pt)
    8042,   -- Earth Shock (interrupt/damage)
    421,   -- Chain Lightning (6s)
  },
}

-- Vanilla 1.15.x per-class Utility cooldown data.
--
-- Retail's Utility bucket = DEFENSIVE buffs, CC, interrupts, escapes, dispels,
-- and minor utility. Anything that doesn't directly contribute to damage but
-- mitigates damage, controls enemies, or repositions. Smaller 30×30 icons.
M.UTILITY_BY_CLASS = {
  WARRIOR = {
    871,   -- Shield Wall (defensive)
    12975,   -- Last Stand (defensive)
    23920,   -- Spell Reflection
    6552,   -- Pummel (interrupt)
    72,   -- Shield Bash (interrupt)
    5246,   -- Intimidating Shout (fear CC)
    18499,   -- Berserker Rage (CC immune)
    100,   -- Charge (mobility, 15s)
  },
  PALADIN = {
    633,   -- Lay on Hands (panic)
    642,   -- Divine Shield (immunity)
    498,   -- Divine Protection
    1022,   -- Blessing of Protection
    10308,   -- Hammer of Justice (stun)
    1044,   -- Blessing of Freedom
    4987,   -- Cleanse (dispel)
    19752,   -- Divine Intervention
  },
  HUNTER = {
    5384,   -- Feign Death
    19263,   -- Deterrence (Survival defensive)
    1499,   -- Freezing Trap (CC)
    19503,   -- Scatter Shot (CC)
    5116,   -- Concussive Shot (slow)
    19801,   -- Tranquilizing Shot (dispel)
    781,   -- Disengage (threat drop)
    1513,   -- Scare Beast (fear beast)
  },
  ROGUE = {
    5277,   -- Evasion (defensive)
    2094,   -- Blind (CC)
    408,   -- Kidney Shot (stun)
    1776,   -- Gouge (CC)
    1766,   -- Kick (interrupt)
    6770,   -- Sap (CC)
    14185,   -- Preparation (Sub 31pt reset)
    1856,   -- Vanish (escape)
  },
  PRIEST = {
    17,   -- Power Word: Shield (Weakened Soul 15s)
    15487,   -- Silence (Shadow 31pt)
    586,   -- Fade (30s)
    8122,   -- Psychic Scream (fear)
    6346,   -- Fear Ward (Dwarf priest racial)
    19236,   -- Desperate Prayer (Human/Dwarf priest racial)
    15286,   -- Vampiric Embrace (sustain)
    724,   -- Lightwell (Holy 31pt)
  },
  MAGE = {
    -- 11958 was here labelled "Ice Block" and is Cold Snap — see the note in Essential above. Both,
    -- plus the Ice Block that was missing entirely, are curated in gen_wotlk.py.
    11426,   -- Ice Barrier (shield)
    1953,   -- Blink (escape)
    122,   -- Frost Nova (root)
    2139,   -- Counterspell (interrupt)
    12051,   -- Evocation (mana)
    118,   -- Polymorph (CC)
    120,   -- Cone of Cold (slow)
  },
  WARLOCK = {
    5782,   -- Fear (CC)
    5484,   -- Howl of Terror (AoE fear)
    710,   -- Banish (CC)
    19647,   -- Spell Lock (interrupt, Felhunter)
    693,   -- Soulstone (battle rez)
    6229,   -- Shadow Ward (absorb)
    1714,   -- Curse of Tongues (cast slow)
    18788,   -- Demonic Sacrifice
  },
  DRUID = {
    22812,   -- Barkskin (defensive)
    5211,   -- Bash (Bear stun)
    339,   -- Entangling Roots (root)
    29166,   -- Innervate (mana)
    740,   -- Tranquility (AoE heal)
    20484,   -- Rebirth (combat rez)
    1850,   -- Dash (movement)
    22842,   -- Frenzied Regeneration (Bear defensive)
  },
  SHAMAN = {
    16188,   -- Nature's Swiftness (Resto 30pt)
    20608,   -- Reincarnation (ankh)
    8177,   -- Grounding Totem
    8143,   -- Tremor Totem (fear/sleep)
    370,   -- Purge (dispel)
    2484,   -- Earthbind Totem (slow)
    16190,   -- Mana Tide Totem (Resto mana)
    5730,   -- Stoneclaw Totem (taunt)
  },
}

-- Vanilla 1.15.x per-class BuffIcon data.
--
-- Self-buffs / debuffs the player wants visible. Tracked via UNIT_AURA on the
-- player unit; the item shows icon + remaining time (REVERSE Cooldown swipe)
-- + stack count. Spellbook IDs match the buff aura's spell ID (which is
-- usually the same as the cast ID for most vanilla spells).
M.BUFFICON_BY_CLASS = {
  WARRIOR = {
    25289,  -- Battle Shout rank 8 (placeholder — vanilla has rank 7 = 11551)
    1719,   -- Recklessness (also tracked as a buff while active)
    12292,  -- Death Wish (active buff)
    18499,  -- Berserker Rage (active buff)
    871,    -- Shield Wall (active buff)
    20230,  -- Retaliation
  },
  PALADIN = {
    25291,  -- Blessing of Might rank 8 (placeholder)
    25290,  -- Blessing of Wisdom rank 6
    25895,  -- Greater Blessing of Wisdom rank 1 (raid 40min)
    642,    -- Divine Shield (active buff)
    498,    -- Divine Protection (active buff)
    20925,  -- Holy Shield
  },
  HUNTER = {
    13165,  -- Aspect of the Hawk rank 7
    5118,   -- Aspect of the Cheetah
    20043,  -- Aspect of the Wild rank 3
    19574,  -- Bestial Wrath (active buff)
    19506,  -- Trueshot Aura (Survival 31pt? — actually Marksmanship)
    3045,   -- Rapid Fire (active buff while casting)
  },
  ROGUE = {
    6774,   -- Slice and Dice rank 2
    5277,   -- Evasion (active buff)
    13877,  -- Blade Flurry (active buff)
    13750,  -- Adrenaline Rush (active buff)
    14177,  -- Cold Blood (next ability crit)
    1856,   -- Vanish (active buff during invis)
  },
  PRIEST = {
    -- BuffIcon = TrackedBuff in retail: player self-auras worth visualizing.
    -- Removed: 13128 Renew (cast on others — won't appear on player), 25217 PW:Shield
    -- (tracked via Weakened Soul in Utility — duplicate), 25431 Prayer of Healing (cast on others).
    -- All entries here MUST be auras that appear on the PLAYER (UnitBuff/UnitDebuff).
    15473,  -- Shadowform (Shadow toggle — visible as long as in Shadowform)
    14751,  -- Inner Focus (15s buff after activation, Disc 15pt)
    10060,  -- Power Infusion (15s damage/haste buff, Disc 31pt)
  },
  MAGE = {
    23028,  -- Arcane Intellect (Greater) rank 5
    25304,  -- Frostbolt rank 11 — not a buff! Need to revisit
    11129,  -- Combustion (active buff)
    11958,  -- Ice Block (active buff)
    6117,   -- Mage Armor / Frost Armor rank 1
    7302,   -- Frost Armor rank 1
  },
  WARLOCK = {
    25311,  -- Soul Link aura ID (placeholder)
    687,    -- Demon Skin
    696,    -- Demon Armor rank 5 placeholder
    755,    -- Health Funnel
    18708,  -- Fel Domination
    1454,   -- Life Tap
  },
  DRUID = {
    21849,  -- Gift of the Wild rank 1
    9846,   -- Mark of the Wild rank 7
    9492,   -- Cat Form
    9634,   -- Dire Bear Form
    22812,  -- Barkskin (active buff)
    1066,   -- Aquatic Form
  },
  SHAMAN = {
    25361,  -- Strength of Earth Totem rank 4 buff
    25420,  -- Grace of Air Totem rank 3 buff
    324,    -- Lightning Shield rank 1
    2825,   -- Bloodlust active buff
    8178,   -- Grounding Totem effect
    20608,  -- Reincarnation passive
  },
}

-- Vanilla 1.15.x per-class BuffBar data.
--
-- Long-duration tracked auras displayed as horizontal status bars (icon +
-- name + remaining time). Typical entries are 10+ minute consumables /
-- buffs / resurrection prompts that the user wants persistent visibility on.
-- Vanilla examples: Soulstone, Slow Fall, Bandage, Mage food, etc.
M.BUFFBAR_BY_CLASS = {
  WARRIOR = {
    23397,  -- Berserker Stance buff (passive — placeholder)
    7384,   -- Overpower buffed
    12328,  -- Sweeping Strikes
  },
  PALADIN = {
    25292,  -- Holy Light rank 11 (placeholder)
    20473,  -- Holy Shock (Holy talent)
    25895,  -- Greater Blessing of Wisdom (40min)
    25890,  -- Greater Blessing of Sanctuary
  },
  HUNTER = {
    20043,  -- Aspect of the Wild (long buff)
    13165,  -- Aspect of the Hawk
    13161,  -- Aspect of the Beast
  },
  ROGUE = {
    6774,   -- Slice and Dice (combo finisher duration tracking)
  },
  PRIEST = {
    -- BuffBar = TrackedBar in retail: long-duration auras visualized as bars.
    -- Removed: 21849 Gift of the Wild (druid spell, not priest's buff).
    -- All entries here MUST be auras that appear on the PLAYER.
    21562,  -- Prayer of Fortitude (1hr raid stam buff)
    27681,  -- Prayer of Spirit (1hr raid spirit buff)
    27683,  -- Prayer of Shadow Protection (1hr raid shadow res buff)
    1243,   -- Power Word: Fortitude rank 1 (30min self-cast stam buff)
  },
  MAGE = {
    23028,  -- Arcane Brilliance (1hr)
    1463,   -- Mana Shield
    11129,  -- Combustion
    7301,   -- Frost Armor — long
  },
  WARLOCK = {
    20707,  -- Soulstone resurrection (30min)
    693,    -- Soulstone cooldown
    25311,  -- Soul Link aura
  },
  DRUID = {
    21849,  -- Gift of the Wild (1hr raid buff)
    9885,   -- Regrowth rank 8
    17329,  -- Thorns rank 6
    8936,   -- Regrowth rank 1 — HoT
  },
  SHAMAN = {
    16177,  -- Ancestral Healing
    10623,  -- Strength of Earth Totem buff
    20577,  -- Cannibalize
    16191,  -- Mana Tide Totem effect
  },
}

M.SPELL_DATA_BY_CATEGORY = {
  essential = M.ESSENTIAL_BY_CLASS,
  utility   = M.UTILITY_BY_CLASS,
  buffIcon  = M.BUFFICON_BY_CLASS,
  buffBar   = M.BUFFBAR_BY_CLASS,
}

-- Vanilla 1.15.x racial cooldowns. Merged into the player's category list at
-- runtime in GetActiveSpellList based on race. Vanilla racials are class-
-- agnostic so they live in their own table keyed by race ("Dwarf", "Orc", ...
-- as returned by UnitRace).
--
-- Classifications mirror the per-class rules:
--   essential = offensive (Blood Fury, Berserking)
--   utility   = defensive / CC / escapes (Stoneform, War Stomp, Will of the Forsaken)
--   buffIcon  = self-aura toggles (Shadowmeld stealth state, Berserking active buff)
-- NOTE: keys are the canonical race FILE name returned by UnitRace() second
-- return value, NOT the localized display name:
--   Night Elf  → "NightElf"   (no space)
--   Undead     → "Scourge"    (in-game faction name returned by UnitRace)
M.RACIAL_BY_RACE = {
  Human    = {
    -- Perception (long CD, situational stealth-detect) — omit as not worth a slot.
    essential = {},
    utility   = {},
    buffIcon  = {},
    buffBar   = {},
  },
  Dwarf    = {
    essential = {},
    utility   = { 20594 },   -- Stoneform (3min CD, immune bleed/poison/disease, +armor)
    buffIcon  = { 20594 },   -- Stoneform active buff
    buffBar   = {},
  },
  NightElf = {
    essential = {},
    utility   = { 20580 },   -- Shadowmeld (10s CD, conditional stealth)
    buffIcon  = {},
    buffBar   = {},
  },
  Gnome    = {
    essential = {},
    utility   = { 20589 },   -- Escape Artist (1.5min CD, root/snare break)
    buffIcon  = {},
    buffBar   = {},
  },
  Draenei    = {
    essential = {},
    utility   = { 28880 },   -- Gift of the Naaru (1.5min CD, heal)
    buffIcon  = {},
    buffBar   = {},
  },
  Orc      = {
    essential = { 20572 },   -- Blood Fury (2min CD, +AP/SP burst)
    utility   = {},
    buffIcon  = { 20572 },   -- Blood Fury active buff (15s)
    buffBar   = {},
  },
  Tauren   = {
    essential = {},
    utility   = { 20549 },   -- War Stomp (2min CD, 2s AoE stun)
    buffIcon  = {},
    buffBar   = {},
  },
  Troll    = {
    essential = { 26297 },   -- Berserking (3min CD, haste based on missing HP)
    utility   = {},
    buffIcon  = { 26297 },   -- Berserking active buff (10s)
    buffBar   = {},
  },
  Scourge  = {
    -- UnitRace returns "Scourge" for Undead — the in-game faction name.
    essential = {},
    utility   = { 7744, 20577 },  -- Will of the Forsaken (5min CD), Cannibalize (2min CD)
    buffIcon  = {},
    buffBar   = {},
  },
  BloodElf  = {
    -- UnitRace returns "BloodElf" for Blood Elves — the canonical race file name.
    essential = {},
    utility   = { 28730 },  -- Arcane Torrent (2min CD, silence + mana restore)
    buffIcon  = {},
    buffBar   = {},
  },
}
