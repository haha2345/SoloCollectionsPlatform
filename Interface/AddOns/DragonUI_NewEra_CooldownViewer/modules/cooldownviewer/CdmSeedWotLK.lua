-- DragonUI_NewEra/modules/cooldownviewer/CdmSeedWotLK.lua — WotLK (3.3.5a) data seed.
--
-- The 3.3.5a counterpart of NewEra's CdmSeedTBC.lua, and structured the same way: ADDITIVE appends
-- onto the vanilla curated lists in ClassData.lua, which carry the 1.12 staples whose rank-1 ids
-- still resolve on this client. The two COOLDOWN tables list only genuinely new-to-WotLK abilities —
-- plus the whole of DEATHKNIGHT, which has no vanilla base at all.
--
-- ROTATION_ADD is not bound by that, and is mostly vanilla spells. It exists because the generator
-- could not previously emit a spell with no cooldown AT ALL — the resolver's castability test is
-- `cooldown > 1.5s`, so Wrath, Frostbolt, Shred and every other filler resolved to nothing and were
-- rejected as unresolvable names. Nothing had ever curated them, in either file.
--
-- FACTS, NOT GUESSES. Every spell ID below was resolved from THIS CLIENT'S OWN DATA, not typed
-- from memory:
--   * Spell.dbc            (DBFilesClient\\Spell.dbc, from Data/enUS/patch-enUS-3.MPQ — the
--                           highest-priority readable archive) for name, rank and cooldown
--   * SkillLineAbility.dbc for class attribution, via each skill line's ClassMask
-- The generator authors the curation BY NAME and resolves each name to the rank-1 CASTABLE id —
-- defined as the lowest-rank, lowest-id entry that actually carries a cooldown > 1.5s. That last
-- filter is what separates a real ability from its triggered sub-spells (e.g. Penance resolves to
-- 47540, not its 47666/47750 heal/damage triggers; Death Grip to 49576, not 49560/49575).
--
-- CAVEAT: two archives in this install (patch-4.MPQ, patch-S.mpq) are encrypted and unreadable, so
-- if the server overrides a spell's data there, these ids reflect the stock client rather than the
-- server's edit. Nothing observed suggests it does, but that is the one gap in the sourcing.
--
-- Bucketing follows retail's split: Essential = offensive burst / damage / throughput cooldowns,
-- Utility = defensives, interrupts, CC, escapes and raid cooldowns.
--
-- The BuffIcon / BuffBar viewers are deliberately NOT seeded: they auto-track any player buff
-- <= 120s (see CooldownViewer.lua), which already covers WotLK procs and trinkets, and upstream
-- removed its long-maintenance-buff seed as clutter.

local NE = DragonUI_NewEra
local M = NE.cooldownviewer
if not M then return end

local ESSENTIAL_ADD = {
  DEATHKNIGHT = {
    42650,   -- Army of the Dead
    49206,   -- Summon Gargoyle
    49028,   -- Dancing Rune Weapon
    47568,   -- Empower Rune Weapon
    49184,   -- Howling Blast
    43265,   -- Death and Decay
    45529,   -- Blood Tap
    46584,   -- Raise Dead
    57330,   -- Horn of Winter
  },
  DRUID = {
    48505,   -- Starfall
    50334,   -- Berserk
    50516,   -- Typhoon
    48438,   -- Wild Growth
    18562,   -- Swiftmend
  },
  HUNTER = {
    53301,   -- Explosive Shot
    53209,   -- Chimera Shot
    53351,   -- Kill Shot
    3674,    -- Black Arrow
    34490,   -- Silencing Shot
  },
  MAGE = {
    44572,   -- Deep Freeze
    55342,   -- Mirror Image
    12472,   -- Icy Veins
    44425,   -- Arcane Barrage
    11113,   -- Blast Wave
    31687,   -- Summon Water Elemental
  },
  PALADIN = {
    53385,   -- Divine Storm
    53595,   -- Hammer of the Righteous
    53600,   -- Shield of Righteousness
    31935,   -- Avenger's Shield
    2812,    -- Holy Wrath
    20216,   -- Divine Favor
    31842,   -- Divine Illumination
    35395,   -- Crusader Strike
  },
  PRIEST = {
    47540,   -- Penance
    14914,   -- Holy Fire
    34861,   -- Circle of Healing
    33076,   -- Prayer of Mending
    64843,   -- Divine Hymn
    64901,   -- Hymn of Hope
  },
  ROGUE = {
    51690,   -- Killing Spree
    51713,   -- Shadow Dance
    14278,   -- Ghostly Strike
    57934,   -- Tricks of the Trade
  },
  SHAMAN = {
    51533,   -- Feral Spirit
    51490,   -- Thunderstorm
    51505,   -- Lava Burst
    60103,   -- Lava Lash
    61295,   -- Riptide
    32182,   -- Heroism
    8050,    -- Flame Shock
  },
  WARLOCK = {
    47241,   -- Metamorphosis
    48181,   -- Haunt
    50796,   -- Chaos Bolt
    47897,   -- Shadowflame
    47193,   -- Demonic Empowerment
  },
  WARRIOR = {
    46924,   -- Bladestorm
    64382,   -- Shattering Throw
    12328,   -- Sweeping Strikes
    57755,   -- Heroic Throw
    23922,   -- Shield Slam
    7384,    -- Overpower
    6572,    -- Revenge
  },
}

local UTILITY_ADD = {
  DEATHKNIGHT = {
    48792,   -- Icebound Fortitude
    48707,   -- Anti-Magic Shell
    51052,   -- Anti-Magic Zone
    49576,   -- Death Grip
    47528,   -- Mind Freeze
    47476,   -- Strangulate
    48743,   -- Death Pact
    48982,   -- Rune Tap
    55233,   -- Vampiric Blood
    49222,   -- Bone Shield
    51271,   -- Unbreakable Armor
    49039,   -- Lichborne
    49203,   -- Hungering Cold
    56222,   -- Dark Command
    61999,   -- Raise Ally
  },
  DRUID = {
    61336,   -- Survival Instincts
    22812,   -- Barkskin
    22842,   -- Frenzied Regeneration
    16689,   -- Nature's Grasp
    16979,   -- Feral Charge - Bear
    49376,   -- Feral Charge - Cat
    22570,   -- Maim
    5211,    -- Bash
    20484,   -- Rebirth
    29166,   -- Innervate
    1850,    -- Dash
  },
  HUNTER = {
    53271,   -- Master's Call
    19386,   -- Wyvern Sting
    60192,   -- Freezing Arrow
    13813,   -- Explosive Trap
    13809,   -- Frost Trap
    1543,    -- Flare
    19577,   -- Intimidation
  },
  MAGE = {
    6143,    -- Frost Ward
    543,     -- Fire Ward
    11958,   -- Cold Snap
    31661,   -- Dragon's Breath
    45438,   -- Ice Block
  },
  PALADIN = {
    64205,   -- Divine Sacrifice
    6940,    -- Hand of Sacrifice
    1038,    -- Hand of Salvation
    31821,   -- Aura Mastery
    54428,   -- Divine Plea
    20066,   -- Repentance
    20925,   -- Holy Shield
    31789,   -- Righteous Defense
  },
  PRIEST = {
    47585,   -- Dispersion
    33206,   -- Pain Suppression
    47788,   -- Guardian Spirit
    64044,   -- Psychic Horror
  },
  ROGUE = {
    51722,   -- Dismantle
    1966,    -- Feint
    1725,    -- Distract
    36554,   -- Shadowstep
    31224,   -- Cloak of Shadows
  },
  SHAMAN = {
    51514,   -- Hex
    57994,   -- Wind Shear
    8177,    -- Grounding Totem
    2484,    -- Earthbind Totem
    5730,    -- Stoneclaw Totem
    16188,   -- Nature's Swiftness
  },
  WARLOCK = {
    48020,   -- Demonic Circle: Teleport
    29858,   -- Soulshatter
    18708,   -- Fel Domination
    6229,    -- Shadow Ward
  },
  WARRIOR = {
    46968,   -- Shockwave
    55694,   -- Enraged Regeneration
    60970,   -- Heroic Fury
    676,     -- Disarm
    12809,   -- Concussion Blow
    1161,    -- Challenging Shout
    20230,   -- Retaliation
  },
}

-- ROTATION — the spells a spec presses constantly, none of which has a cooldown.
--
-- Its own table rather than more rows in ESSENTIAL_ADD, for two reasons. It documents the difference:
-- everything above is something you WAIT for, and everything here is something that is simply always
-- there. And it is what lets verify.py keep asserting "every id carries a real cooldown" of the two
-- lists where that is true, instead of dropping the check for all three.
--
-- Appended into ESSENTIAL_BY_CLASS all the same, which is where retail would show them.
--
-- PER CLASS, not per spec: the runtime gate is "has the player learned it", and every druid has
-- learned Wrath. So this is the union across a class's specs and a Feral druid will find Balance's
-- nukes in the picker — prune per spec in /cdm, which is stored per talent group.
local ROTATION_ADD = {
  DEATHKNIGHT = {
    45477,   -- Icy Touch
    45462,   -- Plague Strike
    45902,   -- Blood Strike
    55050,   -- Heart Strike
    49998,   -- Death Strike
    49020,   -- Obliterate
    55090,   -- Scourge Strike
    49143,   -- Frost Strike
    66217,   -- Rune Strike
    47541,   -- Death Coil
    48721,   -- Blood Boil
    50842,   -- Pestilence
  },
  DRUID = {
    5176,    -- Wrath
    2912,    -- Starfire
    8921,    -- Moonfire
    5570,    -- Insect Swarm
    5221,    -- Shred
    33876,   -- Mangle (Cat)
    1822,    -- Rake
    1079,    -- Rip
    22568,   -- Ferocious Bite
    52610,   -- Savage Roar
    6807,    -- Maul
    33745,   -- Lacerate
    779,     -- Swipe (Bear)
    5185,    -- Healing Touch
    50464,   -- Nourish
    774,     -- Rejuvenation
    8936,    -- Regrowth
    33763,   -- Lifebloom
  },
  HUNTER = {
    56641,   -- Steady Shot
    1978,    -- Serpent Sting
    1510,    -- Volley
    1130,    -- Hunter's Mark
  },
  MAGE = {
    133,     -- Fireball
    116,     -- Frostbolt
    30451,   -- Arcane Blast
    5143,    -- Arcane Missiles
    2948,    -- Scorch
    44457,   -- Living Bomb
    30455,   -- Ice Lance
    44614,   -- Frostfire Bolt
    11366,   -- Pyroblast
    1449,    -- Arcane Explosion
    10,      -- Blizzard
    2120,    -- Flamestrike
  },
  PALADIN = {
    635,     -- Holy Light
    19750,   -- Flash of Light
    20186,   -- Judgement of Wisdom
    31801,   -- Seal of Vengeance
    20154,   -- Seal of Righteousness
    20375,   -- Seal of Command
  },
  PRIEST = {
    585,     -- Smite
    589,     -- Shadow Word: Pain
    15407,   -- Mind Flay
    34914,   -- Vampiric Touch
    48045,   -- Mind Sear
    2061,    -- Flash Heal
    2060,    -- Greater Heal
    139,     -- Renew
    596,     -- Prayer of Healing
  },
  ROGUE = {
    1752,    -- Sinister Strike
    53,      -- Backstab
    1329,    -- Mutilate
    16511,   -- Hemorrhage
    2098,    -- Eviscerate
    32645,   -- Envenom
    1943,    -- Rupture
    5171,    -- Slice and Dice
    8647,    -- Expose Armor
    51723,   -- Fan of Knives
  },
  SHAMAN = {
    403,     -- Lightning Bolt
    331,     -- Healing Wave
    8004,    -- Lesser Healing Wave
    1064,    -- Chain Heal
    974,     -- Earth Shield
    3599,    -- Searing Totem
    8190,    -- Magma Totem
  },
  WARLOCK = {
    686,     -- Shadow Bolt
    29722,   -- Incinerate
    348,     -- Immolate
    172,     -- Corruption
    980,     -- Curse of Agony
    30108,   -- Unstable Affliction
    27243,   -- Seed of Corruption
    1120,    -- Drain Soul
    689,     -- Drain Life
    1454,    -- Life Tap
    5740,    -- Rain of Fire
  },
  WARRIOR = {
    78,      -- Heroic Strike
    845,     -- Cleave
    1464,    -- Slam
    5308,    -- Execute
    772,     -- Rend
    7386,    -- Sunder Armor
    20243,   -- Devastate
    34428,   -- Victory Rush
    1715,    -- Hamstring
  },
}

local STARTER_BY_CLASS = {
  DEATHKNIGHT = {
    [1] = {
      45477,   -- Icy Touch
      45462,   -- Plague Strike
      55050,   -- Heart Strike
      49998,   -- Death Strike
      66217,   -- Rune Strike
      47541,   -- Death Coil
      48721,   -- Blood Boil
      50842,   -- Pestilence
      49028,   -- Dancing Rune Weapon
      57330,   -- Horn of Winter
    },
    [2] = {
      45477,   -- Icy Touch
      45462,   -- Plague Strike
      49020,   -- Obliterate
      49143,   -- Frost Strike
      49184,   -- Howling Blast
      45902,   -- Blood Strike
      50842,   -- Pestilence
      47568,   -- Empower Rune Weapon
      57330,   -- Horn of Winter
    },
    [3] = {
      45477,   -- Icy Touch
      45462,   -- Plague Strike
      55090,   -- Scourge Strike
      45902,   -- Blood Strike
      47541,   -- Death Coil
      43265,   -- Death and Decay
      50842,   -- Pestilence
      49206,   -- Summon Gargoyle
      46584,   -- Raise Dead
      57330,   -- Horn of Winter
    },
  },
  DRUID = {
    [1] = {
      5176,    -- Wrath
      2912,    -- Starfire
      8921,    -- Moonfire
      5570,    -- Insect Swarm
      48505,   -- Starfall
      50516,   -- Typhoon
      16914,   -- Hurricane
      770,     -- Faerie Fire (Balance)
    },
    [2] = {
      5221,    -- Shred
      33876,   -- Mangle (Cat)
      1822,    -- Rake
      1079,    -- Rip
      22568,   -- Ferocious Bite
      52610,   -- Savage Roar
      5217,    -- Tiger's Fury
      6807,    -- Maul
      33745,   -- Lacerate
      779,     -- Swipe (Bear)
      50334,   -- Berserk
      16857,   -- Faerie Fire (Feral)
    },
    [3] = {
      5185,    -- Healing Touch
      50464,   -- Nourish
      774,     -- Rejuvenation
      8936,    -- Regrowth
      33763,   -- Lifebloom
      48438,   -- Wild Growth
      18562,   -- Swiftmend
      17116,   -- Nature's Swiftness
    },
  },
  HUNTER = {
    [1] = {
      56641,   -- Steady Shot
      3044,    -- Arcane Shot
      1978,    -- Serpent Sting
      14288,   -- Multi-Shot
      53351,   -- Kill Shot
      19574,   -- Bestial Wrath
      3045,    -- Rapid Fire
      1130,    -- Hunter's Mark
    },
    [2] = {
      56641,   -- Steady Shot
      3044,    -- Arcane Shot
      1978,    -- Serpent Sting
      53209,   -- Chimera Shot
      19434,   -- Aimed Shot
      14288,   -- Multi-Shot
      53351,   -- Kill Shot
      34490,   -- Silencing Shot
      3045,    -- Rapid Fire
      1130,    -- Hunter's Mark
    },
    [3] = {
      56641,   -- Steady Shot
      53301,   -- Explosive Shot
      1978,    -- Serpent Sting
      3674,    -- Black Arrow
      3044,    -- Arcane Shot
      14288,   -- Multi-Shot
      53351,   -- Kill Shot
      3045,    -- Rapid Fire
      1130,    -- Hunter's Mark
    },
  },
  MAGE = {
    [1] = {
      30451,   -- Arcane Blast
      5143,    -- Arcane Missiles
      44425,   -- Arcane Barrage
      1449,    -- Arcane Explosion
      12043,   -- Presence of Mind
      12042,   -- Arcane Power
      55342,   -- Mirror Image
      2136,    -- Fire Blast
    },
    [2] = {
      133,     -- Fireball
      2948,    -- Scorch
      11366,   -- Pyroblast
      44457,   -- Living Bomb
      2120,    -- Flamestrike
      11113,   -- Blast Wave
      11129,   -- Combustion
      2136,    -- Fire Blast
      55342,   -- Mirror Image
      44614,   -- Frostfire Bolt
    },
    [3] = {
      116,     -- Frostbolt
      30455,   -- Ice Lance
      44572,   -- Deep Freeze
      10,      -- Blizzard
      44614,   -- Frostfire Bolt
      12472,   -- Icy Veins
      31687,   -- Summon Water Elemental
      2136,    -- Fire Blast
    },
  },
  PALADIN = {
    [1] = {
      635,     -- Holy Light
      19750,   -- Flash of Light
      20473,   -- Holy Shock
      20216,   -- Divine Favor
      31842,   -- Divine Illumination
      20271,   -- Judgement of Light
      20186,   -- Judgement of Wisdom
      26573,   -- Consecration
      879,     -- Exorcism
    },
    [2] = {
      31935,   -- Avenger's Shield
      53595,   -- Hammer of the Righteous
      53600,   -- Shield of Righteousness
      26573,   -- Consecration
      2812,    -- Holy Wrath
      20271,   -- Judgement of Light
      20186,   -- Judgement of Wisdom
      879,     -- Exorcism
      24275,   -- Hammer of Wrath
    },
    [3] = {
      35395,   -- Crusader Strike
      53385,   -- Divine Storm
      20186,   -- Judgement of Wisdom
      20271,   -- Judgement of Light
      26573,   -- Consecration
      879,     -- Exorcism
      24275,   -- Hammer of Wrath
      20375,   -- Seal of Command
      31801,   -- Seal of Vengeance
      20154,   -- Seal of Righteousness
    },
  },
  PRIEST = {
    [1] = {
      47540,   -- Penance
      2061,    -- Flash Heal
      2060,    -- Greater Heal
      139,     -- Renew
      596,     -- Prayer of Healing
      33076,   -- Prayer of Mending
      10060,   -- Power Infusion
      14751,   -- Inner Focus
      585,     -- Smite
      14914,   -- Holy Fire
    },
    [2] = {
      2061,    -- Flash Heal
      2060,    -- Greater Heal
      139,     -- Renew
      596,     -- Prayer of Healing
      33076,   -- Prayer of Mending
      34861,   -- Circle of Healing
      64843,   -- Divine Hymn
      64901,   -- Hymn of Hope
      14914,   -- Holy Fire
      585,     -- Smite
    },
    [3] = {
      8092,    -- Mind Blast
      15407,   -- Mind Flay
      589,     -- Shadow Word: Pain
      34914,   -- Vampiric Touch
      2944,    -- Devouring Plague
      48045,   -- Mind Sear
    },
  },
  ROGUE = {
    [1] = {
      1329,    -- Mutilate
      32645,   -- Envenom
      1943,    -- Rupture
      5171,    -- Slice and Dice
      2098,    -- Eviscerate
      14177,   -- Cold Blood
      8647,    -- Expose Armor
      51723,   -- Fan of Knives
      57934,   -- Tricks of the Trade
    },
    [2] = {
      1752,    -- Sinister Strike
      2098,    -- Eviscerate
      5171,    -- Slice and Dice
      1943,    -- Rupture
      13750,   -- Adrenaline Rush
      13877,   -- Blade Flurry
      51690,   -- Killing Spree
      51723,   -- Fan of Knives
      11305,   -- Sprint
      57934,   -- Tricks of the Trade
    },
    [3] = {
      53,      -- Backstab
      16511,   -- Hemorrhage
      2098,    -- Eviscerate
      5171,    -- Slice and Dice
      1943,    -- Rupture
      51713,   -- Shadow Dance
      14183,   -- Premeditation
      14278,   -- Ghostly Strike
      51723,   -- Fan of Knives
      57934,   -- Tricks of the Trade
    },
  },
  SHAMAN = {
    [1] = {
      403,     -- Lightning Bolt
      421,     -- Chain Lightning
      51505,   -- Lava Burst
      8050,    -- Flame Shock
      8042,    -- Earth Shock
      16166,   -- Elemental Mastery
      51490,   -- Thunderstorm
      8190,    -- Magma Totem
      3599,    -- Searing Totem
      32182,   -- Heroism
      2825,    -- Bloodlust
    },
    [2] = {
      17364,   -- Stormstrike
      60103,   -- Lava Lash
      403,     -- Lightning Bolt
      8050,    -- Flame Shock
      8042,    -- Earth Shock
      51533,   -- Feral Spirit
      8190,    -- Magma Totem
      3599,    -- Searing Totem
      32182,   -- Heroism
      2825,    -- Bloodlust
    },
    [3] = {
      331,     -- Healing Wave
      8004,    -- Lesser Healing Wave
      1064,    -- Chain Heal
      61295,   -- Riptide
      974,     -- Earth Shield
      403,     -- Lightning Bolt
      8050,    -- Flame Shock
      32182,   -- Heroism
      2825,    -- Bloodlust
    },
  },
  WARLOCK = {
    [1] = {
      172,     -- Corruption
      980,     -- Curse of Agony
      30108,   -- Unstable Affliction
      48181,   -- Haunt
      686,     -- Shadow Bolt
      1120,    -- Drain Soul
      689,     -- Drain Life
      1454,    -- Life Tap
      27243,   -- Seed of Corruption
      603,     -- Curse of Doom
    },
    [2] = {
      686,     -- Shadow Bolt
      348,     -- Immolate
      172,     -- Corruption
      980,     -- Curse of Agony
      47241,   -- Metamorphosis
      47193,   -- Demonic Empowerment
      6353,    -- Soul Fire
      1454,    -- Life Tap
      47897,   -- Shadowflame
    },
    [3] = {
      29722,   -- Incinerate
      348,     -- Immolate
      17962,   -- Conflagrate
      50796,   -- Chaos Bolt
      686,     -- Shadow Bolt
      17877,   -- Shadowburn
      603,     -- Curse of Doom
      5740,    -- Rain of Fire
      1454,    -- Life Tap
      47897,   -- Shadowflame
    },
  },
  WARRIOR = {
    [1] = {
      12294,   -- Mortal Strike
      7384,    -- Overpower
      1464,    -- Slam
      5308,    -- Execute
      772,     -- Rend
      46924,   -- Bladestorm
      12328,   -- Sweeping Strikes
      78,      -- Heroic Strike
      64382,   -- Shattering Throw
      2687,    -- Bloodrage
    },
    [2] = {
      23881,   -- Bloodthirst
      78,      -- Heroic Strike
      845,     -- Cleave
      5308,    -- Execute
      1464,    -- Slam
      12292,   -- Death Wish
      1719,    -- Recklessness
      34428,   -- Victory Rush
      2687,    -- Bloodrage
    },
    [3] = {
      23922,   -- Shield Slam
      6572,    -- Revenge
      20243,   -- Devastate
      78,      -- Heroic Strike
      845,     -- Cleave
      7386,    -- Sunder Armor
      57755,   -- Heroic Throw
      34428,   -- Victory Rush
      2687,    -- Bloodrage
    },
  },
}

-- Append (deduped) into the existing per-class arrays. A class with no vanilla entry — i.e.
-- DEATHKNIGHT — gets a fresh list rather than being skipped.
local function appendAll(target, byClass)
  if not target then return end
  for class, adds in pairs(byClass) do
    local list = target[class]
    if not list then list = {}; target[class] = list end
    local seen = {}
    for _, id in ipairs(list) do seen[id] = true end
    for _, id in ipairs(adds) do
      if not seen[id] then seen[id] = true; list[#list + 1] = id end
    end
  end
end

appendAll(M.ESSENTIAL_BY_CLASS, ESSENTIAL_ADD)
appendAll(M.UTILITY_BY_CLASS,   UTILITY_ADD)
appendAll(M.ESSENTIAL_BY_CLASS, ROTATION_ADD)

-- The same ids again, flattened into a set, because ONE consumer needs to ask the question the other
-- direction: given a spell, does it have a real cooldown at all?
--
-- ItemMixin:ConsumeReadyTransition — the edge the `available` alert and the ready sound hang off — is
-- defined as "was on a REAL cooldown, now is not", and a real cooldown explicitly excludes the GCD
-- and cast lockouts. For everything in the two COOLDOWN tables that is exactly right: a GCD flash on
-- Starfall would be noise, because the event worth hearing about is the 90 seconds ending.
--
-- For a ROTATION spell it makes the edge unreachable. Wrath has no cooldown, so IsOnRealCooldown is
-- false forever, `_wasOnRealCD` is never armed, and the transition never fires — the "available alert
-- does nothing on the new filler spells" report. `usable` was unaffected because it polls
-- IsUsableSpell rather than waiting on an edge, which is why one worked and the other did not.
--
-- Flat rather than per-class: an id is unique to one class already, and the lookup happens on a tile
-- that has long since stopped caring which class list it came from.
--
-- Membership is a statement about the SPELL, and every entry here was verified cooldown-less against
-- Spell.dbc by the same generator that authored the lists. It is not a runtime guess: "have we seen
-- a real cooldown on this yet" would misfire for every long cooldown the player has not pressed this
-- session, flashing a 2-minute ability at the end of an unrelated global.
M.GCD_ONLY_SPELLS = M.GCD_ONLY_SPELLS or {}
for _, ids in pairs(ROTATION_ADD) do
  for _, id in ipairs(ids) do M.GCD_ONLY_SPELLS[id] = true end
end

-- STARTER LAYOUTS, per class and talent tab. Not appended anywhere: this is a lookup the runtime
-- reads when a starter is applied (M.ApplySpecStarter), listing which of the class's Essential spells
-- stay ON. Everything else in the list goes to Not Displayed rather than being deleted, so it is one
-- drag away in the picker.
--
-- Tab INDEX is the key because that is what GetTalentTabInfo answers. Order is from TalentTab.dbc:
-- 1/2/3 = Arms/Fury/Protection, Holy/Protection/Retribution, Beast Mastery/Marksmanship/Survival,
-- Assassination/Combat/Subtlety, Discipline/Holy/Shadow, Blood/Frost/Unholy,
-- Elemental/Enhancement/Restoration, Arcane/Fire/Frost, Affliction/Demonology/Destruction,
-- Balance/Feral Combat/Restoration.
M.STARTER_BY_CLASS = STARTER_BY_CLASS

-- SPELL_DATA_BY_CATEGORY holds references to the same tables, so the appends above are already
-- visible through it. The learn-gate memoises the curated set on first use, though, so drop that
-- cache now that the tables have grown.
if M.InvalidateCuratedCache then M.InvalidateCuratedCache() end
