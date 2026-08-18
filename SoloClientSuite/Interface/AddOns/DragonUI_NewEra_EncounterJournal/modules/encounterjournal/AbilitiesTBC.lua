-- DOWNPORT: copied from NewEra (see ReferenceAddons); namespace localized to DragonUI_NewEra,
-- art paths re-pointed at DragonUI_NewEra\Textures\EncounterJournal. Content unchanged.
local NE = DragonUI_NewEra
-- Addon/EncounterJournal/AbilitiesTBC.lua — hand-seeded boss ability sections for the TBC
-- (Burning Crusade) RAIDS, the one part of the Outland Encounter Journal retail never authored
-- sections for. Same overlay mechanism as AbilitiesEra.lua: merged into NE.ej.DATA at load by
-- encounter id, WITHOUT touching the auto-generated Generated/tbc/EJData.lua. TBC-ONLY — loaded
-- by NewEra_TBC.toc AFTER EJData.lua (which appends the TBC instances); Era never loads it.
--
-- Why hand-seeded (and why NOT the DB2 like the dungeons): the 16 Outland DUNGEONS are
-- un-revamped, so retail's modern EJ still describes them and tools/gen_ej.py EXTRACTS their
-- JournalEncounterSection straight into EJData.lua. But retail authored NO EJ sections for the 8
-- TBC raids (Karazhan..Sunwell), so — per CLAUDE.md's prime directive that we never fabricate —
-- these are sourced from the live TBC data the same way AbilitiesEra sourced vanilla:
--   * which spells each boss casts  -> cmangos TBCDB creature_spell_list + ScriptDev2 boss scripts
--     (the #define SPELL_* ids), cross-checked on the TBC Wowhead for the gaps.
--   * flags (badges) DERIVED, not guessed: Tank(1), Heal(4), Deadly(16 lethal/must-avoid),
--     Important(32 summons/phase/major mechanic), Interrupt(64), Magic(128), Curse(256),
--     Poison(512), Disease(1024), Enrage(2048), Bleed(8192) — bit order per EncounterPage
--     FLAG_ATLAS; sums combine (e.g. 192 = Magic+Interrupt).
--   * `spell` = the real TBC spellID (icon resolved via GetSpellTexture at runtime, no baked
--     FDID). 0 where a mechanic is not a castable spell (adds/phases/events) or no id could be
--     verified — never a guessed id.
--
-- Schema per entry: ABIL[encounterID] = { {title=, body=, flags=, spell=}, ... } — a flat
-- top-level ability list, identical to AbilitiesEra.lua. Section ids are synthesised as
-- encID*1000 + index (raid encIDs are 1552-1596, so no collision with the dungeons' DB2 section
-- ids in the 5000-6600 range).

NE.ej = NE.ej or {}

local ABIL = {

  -- Karazhan (instance 745)
  [1552] = { -- Servant's Quarters
    { title = "Stable Rares", flags = 32, spell = 0,
      body = "Clearing the Servant's Quarters can spawn one of several roaming rare beasts from the stables — Hyakiss the Lurker, Rokad the Ravager, or Shadikith the Glider among them. These optional mini-bosses wander the halls and drop extra loot for groups that hunt them down." },
    { title = "Roaming Menagerie", flags = 0, spell = 0,
      body = "Each rare patrols a set route through the quarters rather than guarding a fixed room, so pull carefully to avoid waking a second pack. They are entirely optional and do not block progress deeper into the tower." },
  },

  [1553] = { -- Attumen the Huntsman
    { title = "Shadow Cleave", flags = 1, spell = 29832,
      body = "Attumen swings in a wide arc, striking his primary target and everyone beside them for heavy Shadow damage. Keep non-tanks clear of his front." },
    { title = "Intangible Presence", flags = 128, spell = 29833,
      body = "Attumen afflicts a player with a curse of shadow that sharply reduces their chance to hit. The magic effect can be removed by dispel." },
    { title = "Uppercut", flags = 1, spell = 29850,
      body = "A brutal blow to his current target that deals massive physical damage and hurls them into the air. Only the tank should ever be in melee range." },
    { title = "Berserker Charge", flags = 16, spell = 29847,
      body = "Once mounted on Midnight, Attumen charges a random player, dealing severe damage and knocking them back. Stay spread so the charge cannot chain through the raid." },
    { title = "Mounted Assault", flags = 32, spell = 29799,
      body = "When either Midnight or Attumen is brought low, the huntsman mounts his steed and the two merge into a single, far deadlier foe that gains new charging attacks for the remainder of the fight." },
  },

  [1554] = { -- Moroes
    { title = "Garrote", flags = 8192, spell = 37066,
      body = "After vanishing, Moroes garrotes a random player, applying a vicious Bleed that inflicts escalating physical damage over time and cannot be dispelled. Heal through it until it expires." },
    { title = "Vanish", flags = 32, spell = 29448,
      body = "Moroes disappears from sight, becoming untargetable before reappearing to garrote a victim. His threat resets briefly, so the tank must re-establish aggro the moment he returns." },
    { title = "Gouge", flags = 1, spell = 29425,
      body = "Moroes gouges his current target, incapacitating them and wiping their threat for several seconds. A second tank or a taunt keeps him controlled through the gouge window." },
    { title = "Blind", flags = 0, spell = 34694,
      body = "Moroes blinds a player, causing them to flee in disorientation for the duration. The effect breaks on damage." },
    { title = "Enrage", flags = 2048, spell = 37023,
      body = "At low health Moroes enrages, dramatically increasing his attack speed and damage. Blind or crowd-control effects and defensive cooldowns help the raid survive the burn phase." },
    { title = "Dinner Guests", flags = 32, spell = 0,
      body = "Moroes is accompanied by four undead nobles drawn from a pool of guests, each with the abilities of its class. They must be crowd-controlled or killed so the raid can focus Moroes without being overwhelmed." },
  },

  [1555] = { -- Maiden of Virtue
    { title = "Repentance", flags = 32, spell = 29511,
      body = "The Maiden stuns the entire raid in a wave of holy judgment, incapacitating everyone for several seconds. Any damage taken breaks the effect, so healers should pre-heal before it lands." },
    { title = "Holy Fire", flags = 128, spell = 29522,
      body = "A pillar of holy flame engulfs a random player, dealing heavy Holy damage and leaving a burning magic debuff that can be dispelled." },
    { title = "Holy Wrath", flags = 16, spell = 32445,
      body = "The Maiden looses a bolt of holy energy that arcs from target to target, dealing more damage with each jump. Spread out so the wrath cannot chain lethally through the group." },
    { title = "Holy Ground", flags = 0, spell = 29512,
      body = "Sanctified ground surrounds the Maiden, continually searing and interrupting any player who stands in melee range. Ranged and healers should fight from well outside the aura." },
  },

  [1556] = { -- Opera Hall
    { title = "The Wizard of Oz", flags = 32, spell = 0,
      body = "Dorothee and her companions take the stage: Tito, Strawman, Tinhead and Roar must be handled together before the Crone appears to summon a deadly tornado. A test of multi-target management and crowd control." },
    { title = "The Big Bad Wolf", flags = 32, spell = 0,
      body = "The Big Bad Wolf hunts the raid, periodically transforming a random player into 'Little Red Riding Hood' who is forced to flee at great speed. The cursed player must kite the Wolf until the effect fades." },
    { title = "Romulo and Julianne", flags = 32, spell = 0,
      body = "The star-crossed lovers fight as a pair and resurrect one another unless both are slain within moments of each other. The raid must burst them down together to end the show." },
  },

  [1557] = { -- The Curator
    { title = "Summon Astral Flare", flags = 32, spell = 30236,
      body = "The Curator conjures Astral Flares that fixate and burn random players with Arcane damage. They must be destroyed quickly, but each summon drains the Curator's mana toward his vulnerable Evocation." },
    { title = "Hateful Bolt", flags = 1, spell = 30383,
      body = "A bolt of arcane energy strikes the second-highest player on the Curator's threat list for heavy damage. A well-healed off-tank should hold that position to shield the raid." },
    { title = "Evocation", flags = 32, spell = 30254,
      body = "When his mana is exhausted, the Curator channels Evocation to recharge, during which he takes greatly increased damage and cannot summon flares. This is the raid's window to burn him down." },
    { title = "Enrage", flags = 2048, spell = 30403,
      body = "Below fifteen percent health the Curator enters a permanent enrage, ceasing his flare summons but striking with vastly increased damage and speed until he or the raid falls." },
  },

  [1559] = { -- Shade of Aran
    { title = "Flame Wreath", flags = 16, spell = 30004,
      body = "Aran ignites rings of fire beneath several players. Anyone who moves from their spot detonates the wreath, dealing lethal Fire damage to the whole raid — hold completely still until it fades." },
    { title = "Blizzard", flags = 16, spell = 29969,
      body = "A rotating storm of ice sweeps around the chamber, inflicting heavy Frost damage to anyone caught in its path. Watch its direction and move around the room to stay ahead of it." },
    { title = "Arcane Explosion", flags = 16, spell = 29973,
      body = "Aran magnetically pulls the entire raid to him, then unleashes a massive Arcane Explosion. Spread out and use any means of escape to avoid taking the full, potentially fatal blast." },
    { title = "Conjure Water Elementals", flags = 32, spell = 29962,
      body = "At around forty percent health Aran becomes invulnerable and summons Water Elementals that bombard the raid. They must be killed or outlasted before he rejoins the fight." },
    { title = "Counterspell", flags = 0, spell = 29961,
      body = "Aran counters a spellcaster, locking their school of magic for several seconds. Casters should stagger their casts so the whole raid is never silenced at once." },
    { title = "Pyroblast", flags = 80, spell = 29978,
      body = "When his mana runs low Aran stops to drink, then begins a devastating Pyroblast. Interrupt the cast immediately or a player will be struck for enormous, likely lethal Fire damage." },
  },

  [1560] = { -- Terestian Illhoof
    { title = "Sacrifice", flags = 32, spell = 30115,
      body = "Terestian binds a random player in Demonic Chains, draining their life to heal himself while they are held helpless. The chains must be destroyed quickly to free the victim and stop the healing." },
    { title = "Fiendish Portal", flags = 32, spell = 30171,
      body = "Terestian opens portals that continuously spew Fiendish Imps into the fight. The imps pelt the raid with Firebolts and must be controlled by area damage or they will overwhelm the healers." },
    { title = "Kil'rek", flags = 32, spell = 30065,
      body = "His familiar imp Kil'rek shields Terestian and respawns over time. Slaying it inflicts Broken Pact, greatly increasing the damage Terestian takes — a key window to push his health down." },
    { title = "Shadow Bolt", flags = 0, spell = 30055,
      body = "Terestian hurls bolts of shadow at random members of the raid for moderate Shadow damage throughout the encounter." },
    { title = "Berserk", flags = 2048, spell = 32965,
      body = "If the fight runs too long Terestian goes berserk, gaining a huge boost to attack speed and damage that will quickly wipe an unprepared raid." },
  },

  [1561] = { -- Netherspite
    { title = "Portal Beams", flags = 32, spell = 30422,
      body = "Three colored beams — red, green and blue — connect Netherspite to portals around the room. Players must stand in each beam to absorb its buff and deny it to the dragon, rotating out before their Exhaustion debuff makes the beam harmful." },
    { title = "Void Zone", flags = 16, spell = 37063,
      body = "During his Banish phase Netherspite litters the room with Void Zones that deal severe damage to anyone standing in them. Move clear of the growing pools immediately." },
    { title = "Netherbreath", flags = 1, spell = 38523,
      body = "Netherspite breathes a cone of nether energy at his target, dealing heavy damage and interrupting spellcasts caught in front of him. The tank should point him away from the raid." },
    { title = "Nether Burn", flags = 128, spell = 30522,
      body = "A stacking aura of nether flame sears players near the beams, dealing increasing magic damage the longer it builds. Rotate beam duty so the stacks never grow lethal." },
    { title = "Nether Infusion", flags = 2048, spell = 38688,
      body = "As the fight drags on Netherspite gains stacking Nether Infusion, a hard enrage that steadily increases his damage until the raid can no longer survive. He must die before it overwhelms the healers." },
  },

  [1562] = { -- Chess Event
    { title = "The Game of Kings", flags = 32, spell = 0,
      body = "Medivh's enchanted chessboard pits the raid against the Burning Crusade's pieces. Each player takes control of a chess figure — king, knights, conjurers and pawns — and directs its attacks and moves across the squares." },
    { title = "Defeat the King", flags = 0, spell = 0,
      body = "Victory requires slaying the opposing King while protecting your own. Positioning pieces to focus fire and using the healing squares wisely wins the match with no traditional boss to tank." },
  },

  [1563] = { -- Prince Malchezaar
    { title = "Enfeeble", flags = 16, spell = 30843,
      body = "Malchezaar reduces several players to a single point of health and blocks all healing on them for the duration. The afflicted must avoid every source of damage until the effect lifts." },
    { title = "Shadow Nova", flags = 16, spell = 30852,
      body = "The Prince erupts with a burst of shadow energy, dealing massive damage to everyone nearby and knocking them back. It frequently follows Enfeeble, so weakened players must be at maximum range." },
    { title = "Summon Infernal", flags = 32, spell = 30835,
      body = "Malchezaar rains flaming Infernals from the sky that crash down and burn everything around them. The raid must constantly reposition to stay out of their spreading Hellfire." },
    { title = "Axes of Malchezaar", flags = 1, spell = 30891,
      body = "In his second phase Malchezaar arms himself with a pair of enchanted axes, dual-wielding for greatly increased physical damage and shredding his tank. Cooldowns and strong healing are essential." },
    { title = "Shadow Word: Pain", flags = 128, spell = 30898,
      body = "The Prince afflicts players with Shadow Word: Pain, a magic damage-over-time curse that can be dispelled to ease the strain on the healers." },
  },

  -- Gruul's Lair (instance 746) + Magtheridon's Lair (instance 747)
  [1564] = { -- High King Maulgar
    { title = "Arcing Smash", flags = 1, spell = 39144,
      body = "Maulgar delivers a vicious frontal cleave to his primary target and nearby players, punishing melee that stack too tightly on his tank." },
    { title = "Mighty Blow", flags = 1, spell = 33230,
      body = "A crushing strike against Maulgar's current target that inflicts heavy physical damage, demanding steady tank cooldowns and healing." },
    { title = "Whirlwind", flags = 16, spell = 33238,
      body = "Maulgar spins wildly, striking everyone around him for severe damage. Melee should back away for the duration to avoid being cut down." },
    { title = "Greater Fireball", flags = 16, spell = 33051,
      body = "Krosh Firehand hurls a massive fireball at a random target for heavy fire damage. He is shielded against interrupts, so his mage tank must strip his Spell Shield." },
    { title = "Spell Shield", flags = 32, spell = 33054,
      body = "Krosh Firehand wraps himself in a barrier that absorbs and reflects incoming spells. A mage should Spellsteal the shield to safely tank and interrupt him." },
    { title = "Death Coil", flags = 32, spell = 33130,
      body = "Olm the Summoner fires a bolt of shadow that damages and briefly horrifies its victim, sending them fleeing while he raises Wild Felhunters." },
    { title = "Summon Wild Felhunter", flags = 32, spell = 33131,
      body = "Olm the Summoner calls forth Wild Felhunters that hound the raid and devour magical buffs, so they must be picked up and killed quickly." },
    { title = "Greater Polymorph", flags = 0, spell = 33173,
      body = "Kiggler the Crazed transforms a random player into a sheep, removing them from the fight until the effect fades or they take damage." },
    { title = "Prayer of Healing", flags = 68, spell = 33152,
      body = "Blindeye the Seer channels a group heal that restores health to the council. His casts must be interrupted so the lieutenants can be brought down." },
  },

  [1565] = { -- Gruul the Dragonkiller
    { title = "Growth", flags = 2048, spell = 36300,
      body = "Gruul steadily grows in size throughout the fight, and each stack increases his damage and attack speed, imposing a soft enrage the longer he lives." },
    { title = "Ground Slam", flags = 32, spell = 33525,
      body = "Gruul smashes the ground, knocking players into the air and scattering them at random points around the room in preparation for Shatter." },
    { title = "Shatter", flags = 16, spell = 33654,
      body = "Moments after Ground Slam, Gruul petrifies the raid and detonates the stone, dealing damage that scales sharply with how close players stand to one another. Spread out immediately." },
    { title = "Cave In", flags = 16, spell = 36240,
      body = "Gruul causes rocks to crash down on random locations, inflicting heavy area damage. Players must watch the ground and move clear of falling debris." },
    { title = "Hurtful Strike", flags = 1, spell = 33812,
      body = "Gruul strikes the second-highest threat target in melee range for tremendous damage, requiring an off-tank to stay close so it never lands on a cloth wearer." },
    { title = "Reverberation", flags = 0, spell = 36297,
      body = "Gruul unleashes a shockwave that silences and interrupts nearby players for several seconds, briefly cutting off casters and healers in melee range." },
  },

  [1566] = { -- Magtheridon
    { title = "Blast Nova", flags = 48, spell = 30616,
      body = "Magtheridon channels a devastating explosion that will wipe the raid if completed. Players must use the Manticron Cubes around the room to banish him and cancel the cast." },
    { title = "Shadow Grasp (Manticron Cube)", flags = 32, spell = 30410,
      body = "Clicking a Manticron Cube channels Shadow Grasp on Magtheridon; five channels applied together stun him and interrupt Blast Nova, but each user is left with Mind Exhaustion afterward." },
    { title = "Cleave", flags = 1, spell = 30619,
      body = "Magtheridon savagely cleaves his tank and any players in front of him, so the raid must stay behind or to his sides." },
    { title = "Quake", flags = 0, spell = 30657,
      body = "Magtheridon shakes the cavern, periodically knocking players into the air and interrupting their actions during the second phase." },
    { title = "Blaze", flags = 16, spell = 30541,
      body = "Magtheridon ignites patches of fire beneath random players that burn anyone standing in them. Move out of the flames to avoid rapid damage." },
    { title = "Debris", flags = 16, spell = 30631,
      body = "In the final phase the ceiling collapses, raining debris that deals heavy damage where it lands and knocks players down. Watch for the falling markers and move away." },
    { title = "Shadow Bolt Volley", flags = 32, spell = 30510,
      body = "The Hellfire Channelers restraining Magtheridon barrage the raid with shadow bolts. They must be killed to free him, but doing so releases him into combat." },
    { title = "Soul Transfer", flags = 4, spell = 30531,
      body = "When a Hellfire Channeler dies it channels its remaining life into the others, healing the surviving Channelers unless they are brought down close together." },
  },

  -- Serpentshrine Cavern (instance 748)
  [1567] = { -- Hydross the Unstable
    { title = "Elemental Transition", flags = 32, spell = 36459,
      body = "Whenever Hydross is pulled across the water's edge he switches between his frost and corrupted nature aspects, resetting his marks and spawning a wave of Pure or Tainted Spawn of Hydross that must be picked up and killed." },
    { title = "Mark of Hydross", flags = 129, spell = 38218,
      body = "In his frost aspect Hydross applies a stacking mark to his current target that steadily increases the frost damage they take, forcing a tank swap or an aspect transition before the stacks become lethal." },
    { title = "Mark of Corruption", flags = 129, spell = 38230,
      body = "In his corrupted nature aspect Hydross applies a stacking mark that increases the nature damage the tank takes, the mirror of Mark of Hydross and the reason the fight is tanked with two tanks." },
    { title = "Water Tomb", flags = 128, spell = 38235,
      body = "While in his frost aspect Hydross entombs random players in ice, dealing frost damage over time to them and nearby allies." },
    { title = "Vile Sludge", flags = 16, spell = 38246,
      body = "In his corrupted aspect Hydross afflicts a random player with a heavy nature damage-over-time effect that spreads to anyone nearby, so afflicted players must move away from the raid." },
  },

  [1568] = { -- The Lurker Below
    { title = "Spout", flags = 16, spell = 37431,
      body = "The Lurker Below rears up and sweeps a rotating jet of water around the room, knocking back and heavily damaging anyone caught in its path. Players must dive underwater to avoid it." },
    { title = "Submerge", flags = 32, spell = 28819,
      body = "Periodically the Lurker submerges beneath the water and summons Coilfang Guardians and Coilfang Ambushers to attack the raid until he resurfaces." },
    { title = "Geyser", flags = 0, spell = 37478,
      body = "The Lurker erupts a geyser of water beneath a random player, flinging them into the air and dealing frost damage on landing." },
    { title = "Whirl", flags = 0, spell = 37660,
      body = "The Lurker spins violently, striking and knocking back all players within melee range." },
    { title = "Water Bolt", flags = 0, spell = 37138,
      body = "If no target is within melee range the Lurker hurls water bolts at distant players for frost damage." },
  },

  [1569] = { -- Leotheras the Blind
    { title = "Metamorphosis", flags = 32, spell = 37673,
      body = "Leotheras alternates between his elf and demon forms. In demon form he stops meleeing and instead bombards the raid with Chaos Blast, requiring a dedicated warlock tank." },
    { title = "Whirlwind", flags = 16, spell = 37640,
      body = "In his elf form Leotheras periodically whirlwinds, dealing lethal melee damage to everyone nearby and switching to random targets, so players must spread and range him during the spin." },
    { title = "Chaos Blast", flags = 16, spell = 37674,
      body = "In demon form Leotheras repeatedly casts Chaos Blast at his target, applying a stacking fire damage-over-time that quickly becomes deadly to anyone but a resistant warlock tank." },
    { title = "Insidious Whisper", flags = 32, spell = 37676,
      body = "Leotheras marks several players with Insidious Whisper, summoning an Inner Demon beside each. The targeted player must kill their own demon before the debuff expires or be feared for the remainder of the fight." },
    { title = "Berserk", flags = 2048, spell = 27680,
      body = "If Leotheras is not defeated in time he goes Berserk, gaining a massive attack and damage increase that quickly wipes the raid." },
  },

  [1570] = { -- Fathom-Lord Karathress
    { title = "Cataclysmic Bolt", flags = 16, spell = 38441,
      body = "Karathress hurls a Cataclysmic Bolt at a random player, dealing damage equal to roughly half their current health and requiring immediate healing." },
    { title = "Blessing of the Tides", flags = 32, spell = 38449,
      body = "As each of his three Fathom-Guard advisors dies, Karathress absorbs their power and grows far more dangerous, so the advisors' kill order and their abilities dictate the whole encounter." },
    { title = "Sear Nova", flags = 16, spell = 38445,
      body = "Karathress unleashes Sear Nova, a burst of fire damage striking players around his current target." },
    { title = "Sharkkis: Summon Beasts", flags = 32, spell = 38433,
      body = "The advisor Sharkkis summons a Fathom Lurker or Fathom Sporebat pet and enters Bestial Wrath, and Karathress inherits this beast-summoning power if Sharkkis is not killed first." },
    { title = "Caribdis: Healing Wave", flags = 68, spell = 38330,
      body = "The advisor Caribdis casts a large Healing Wave on her allies that must be interrupted, and also drops damaging cyclones and a knocking-back Tidal Surge." },
    { title = "Tidalvess: Totems & Frost Shock", flags = 0, spell = 38234,
      body = "The advisor Tidalvess drops Spitfire, Poison Cleansing and Earthbind totems and chills players with Frost Shock; his totems should be destroyed quickly." },
  },

  [1571] = { -- Morogrim Tidewalker
    { title = "Watery Grave", flags = 48, spell = 38028,
      body = "Morogrim teleports random players into water pools around the room and spawns Water Globules that home in on them and explode for heavy frost damage." },
    { title = "Murloc Onslaught", flags = 32, spell = 37766,
      body = "At intervals, and again when he reaches low health, Morogrim summons a large wave of Tidewalker murlocs that swarm the raid and must be controlled with area damage." },
    { title = "Earthquake", flags = 32, spell = 37764,
      body = "Below roughly 25 percent health Morogrim repeatedly casts Earthquake, dealing raid-wide nature damage and briefly stunning players while a final murloc wave pours in." },
    { title = "Tidal Wave", flags = 1, spell = 37730,
      body = "Morogrim smashes the ground in front of him with a Tidal Wave, dealing heavy frontal damage and knocking back everyone in the cone, so only the tank should stand before him." },
    { title = "Water Globules", flags = 32, spell = 37854,
      body = "Players trapped by Watery Grave are chased by Water Globules that explode on contact; ranged players should destroy the globules before they reach their targets." },
  },

  [1572] = { -- Lady Vashj
    { title = "Tainted Elementals & Shield Generators", flags = 32, spell = 38139,
      body = "During phase two Vashj becomes immune behind four Shield Generators. Tainted Elementals drop Tainted Cores that players must relay hand-to-hand to destroy each generator and expose her again." },
    { title = "Shock Blast", flags = 16, spell = 38509,
      body = "Vashj blasts a random nearby player with Shock Blast, dealing lethal nature damage and stunning them, which must be healed through or avoided by staying at range." },
    { title = "Entangle", flags = 32, spell = 38316,
      body = "In phase two Vashj entangles the entire raid in roots, holding players in place while the adds and spore mechanics threaten them." },
    { title = "Static Charge", flags = 128, spell = 38280,
      body = "Vashj afflicts random players with Static Charge, a magic debuff that deals periodic nature damage to the target and everyone near them, forcing afflicted players to spread out." },
    { title = "Toxic Spores", flags = 544, spell = 38574,
      body = "The Coilfang Striders that appear in phase two drop Toxic Spores across the floor; standing in them inflicts stacking poison damage, so players must keep moving to clear ground." },
    { title = "Poison Bolt Volley", flags = 512, spell = 0,
      body = "Vashj rains a volley of poison bolts across the raid, inflicting nature damage-over-time on multiple players that healers must top off." },
  },

  -- Tempest Keep: The Eye (instance 749)
  [1573] = { -- Al'ar
    { title = "Flame Quills", flags = 16, spell = 34229,
      body = "Al'ar flies to the center platform and unleashes a ring of flame quills in every direction, blanketing the room in Fire damage. Players must position between the outgoing waves to survive." },
    { title = "Flame Buffet", flags = 128, spell = 34121,
      body = "Any player within melee range is struck by Flame Buffet, applying a stacking Fire damage-over-time debuff that intensifies the longer they remain close." },
    { title = "Dive Bomb", flags = 16, spell = 35181,
      body = "In the second phase Al'ar soars into the air and dive bombs a random location, dealing massive Fire damage to anyone nearby and scorching the ground on impact." },
    { title = "Melt Armor", flags = 1, spell = 35410,
      body = "Al'ar melts the armor of its current target, sharply reducing its armor and increasing the physical damage it takes for the duration." },
    { title = "Ember Blast", flags = 48, spell = 34341,
      body = "When its health is depleted at the end of the first phase, Al'ar erupts in an Ember Blast that deals heavy Fire damage to the entire raid before it is reborn to continue the encounter." },
    { title = "Ember of Al'ar", flags = 32, spell = 41824,
      body = "Al'ar spawns small phoenix Embers that assail the raid; if one reaches Al'ar's remains it is consumed to heal and revive the phoenix god." },
  },

  [1574] = { -- Void Reaver
    { title = "Arcane Orb", flags = 16, spell = 34172,
      body = "Void Reaver launches a slow-moving Arcane Orb at a distant player that detonates on contact for lethal Arcane damage. Ranged players must spread and sidestep the incoming orbs." },
    { title = "Pounding", flags = 16, spell = 34162,
      body = "Void Reaver pounds the ground, dealing heavy Arcane damage to all players within a wide radius. Anyone caught in range should be topped off before it lands." },
    { title = "Knock Away", flags = 1, spell = 25778,
      body = "Void Reaver strikes his current target, hurling them backward and reducing their threat, forcing the tank to re-establish position and aggro." },
    { title = "Enrage", flags = 2048, spell = 26662,
      body = "After roughly ten minutes Void Reaver goes berserk, drastically increasing his damage and quickly overwhelming the raid." },
  },

  [1575] = { -- High Astromancer Solarian
    { title = "Wrath of the Astromancer", flags = 16, spell = 42783,
      body = "Solarian marks a random player with an Arcane bomb that, after a short delay, detonates for massive Arcane damage and knocks back everyone nearby. The target must run clear of the raid before it explodes." },
    { title = "Blinding Light", flags = 0, spell = 33009,
      body = "Solarian periodically bathes the room in Blinding Light, dealing Arcane damage to the entire raid and keeping healers under steady pressure." },
    { title = "Arcane Missiles", flags = 0, spell = 39414,
      body = "Solarian channels a barrage of Arcane Missiles at a random player, inflicting rapid Arcane damage over the duration of the channel." },
    { title = "Split", flags = 32, spell = 0,
      body = "Solarian splits into three identical copies and vanishes, summoning waves of Solarium Agents and Priests around the room before the real Solarian reappears to attack." },
    { title = "Voidwalker Form", flags = 32, spell = 0,
      body = "At low health Solarian transforms into a towering voidwalker, abandoning her spells for a devastating melee assault that must be tanked and burned down." },
  },

  [1576] = { -- Kael'thas Sunstrider
    { title = "Kael'thas's Advisors", flags = 32, spell = 0,
      body = "Before engaging directly, Kael'thas sends his four advisors against the raid one after another, each with its own abilities, followed by his reanimated legendary weapons." },
    { title = "Summon Legendary Weapons", flags = 32, spell = 36976,
      body = "Kael'thas animates his seven enchanted weapons and hurls them into the fight, each attacking the raid until it is destroyed." },
    { title = "Pyroblast", flags = 80, spell = 36819,
      body = "Kael'thas channels a long Pyroblast that deals lethal Fire damage to its target. The cast must be interrupted or broken by line of sight before it completes." },
    { title = "Flame Strike", flags = 16, spell = 36735,
      body = "Kael'thas conjures a Flame Strike on a targeted area that erupts after a short delay, dealing heavy Fire damage and leaving a burning patch. Move out of the marked ground." },
    { title = "Mind Control", flags = 32, spell = 36797,
      body = "Kael'thas seizes control of several players, turning them against their allies until the effect is broken or expires." },
    { title = "Gravity Lapse", flags = 48, spell = 35941,
      body = "In the final phase Kael'thas removes gravity, sending the raid floating helplessly into the air while Nether Beams and Nether Vapor hunt down drifting players." },
  },

  -- The Battle for Mount Hyjal (instance 750)
  [1577] = { -- Rage Winterchill
    { title = "Icebolt", flags = 128, spell = 31249,
      body = "Rage Winterchill hurls a bolt of ice at a random player, encasing them in frost and dealing heavy frost damage over time while they are frozen in place." },
    { title = "Death and Decay", flags = 16, spell = 31258,
      body = "He blankets an area beneath the raid with unholy energy, inflicting rapid ticking damage to anyone standing within it. Move out of the affected ground immediately." },
    { title = "Frost Nova", flags = 128, spell = 31250,
      body = "A burst of frost roots all nearby players in ice and deals frost damage, briefly locking melee in place near him." },
    { title = "Frost Armor", flags = 1, spell = 31256,
      body = "Winterchill shrouds himself in frost armor, chilling and slowing the attack speed of any who strike him in melee." },
  },

  [1578] = { -- Anetheron
    { title = "Inferno", flags = 48, spell = 31299,
      body = "Anetheron summons an Infernal that crashes down from the sky, stunning and burning players near its impact before it rises to fight as an add. Kill it quickly and avoid the landing point." },
    { title = "Carrion Swarm", flags = 4, spell = 31306,
      body = "A swarm of bats erupts in a frontal cone, dealing shadow damage and reducing the healing received by everyone it strikes." },
    { title = "Sleep", flags = 128, spell = 31298,
      body = "He lulls a random player into a magical slumber, incapacitating them until they take damage or the effect is dispelled." },
    { title = "Vampiric Aura", flags = 0, spell = 31317,
      body = "Anetheron radiates a vampiric aura that heals him and his infernals for a portion of the damage they deal to the raid." },
  },

  [1579] = { -- Kaz'rogal
    { title = "Mark of Kaz'rogal", flags = 272, spell = 31447,
      body = "Kaz'rogal curses random players, rapidly draining their mana. When a marked player's mana is fully depleted, the mark detonates for massive damage and spreads to nearby allies. Remove the curse where possible." },
    { title = "Cripple", flags = 129, spell = 31477,
      body = "A debilitating hex slows a target's melee attack speed and movement while reducing its damage, punishing tanks and melee." },
    { title = "Malevolent Cleave", flags = 1, spell = 31436,
      body = "He delivers a savage cleave to the tank and anyone standing in front of him, dealing heavy physical damage." },
    { title = "War Stomp", flags = 0, spell = 31480,
      body = "Kaz'rogal stomps the ground, stunning nearby players for several seconds." },
  },

  [1580] = { -- Azgalor
    { title = "Doom", flags = 48, spell = 31347,
      body = "Azgalor afflicts a random player with Doom; after a short delay the curse slays them and a Lesser Doomguard erupts from the corpse to join the fight." },
    { title = "Rain of Fire", flags = 16, spell = 31340,
      body = "He calls down fire over a targeted area, inflicting heavy fire damage to anyone caught within it. Move clear of the flames." },
    { title = "Howl of Azgalor", flags = 4, spell = 31344,
      body = "A booming howl silences all nearby players for several seconds, cutting off casters and healers." },
    { title = "Cleave", flags = 1, spell = 31345,
      body = "Azgalor cleaves the tank and players in front of him for heavy physical damage." },
  },

  [1581] = { -- Archimonde
    { title = "Air Burst", flags = 16, spell = 32014,
      body = "Archimonde hurls players high into the air, and the resulting fall can be fatal. Use the Tears of the Goddess (Ancient Gem) to conjure a wisp that safely lowers you to the ground." },
    { title = "Finger of Death", flags = 16, spell = 31984,
      body = "He instantly annihilates any player who strays too far from the raid. Stay within range of the group at all times." },
    { title = "Doomfire", flags = 48, spell = 31945,
      body = "Archimonde spawns wandering Doomfire that drifts across the platform, leaving a trail of flame that deals severe damage. Watch its movement and keep away." },
    { title = "Fear", flags = 128, spell = 31970,
      body = "A wave of terror causes nearby players to flee in panic, scattering them toward the deadly edges of the platform. Dispel or counter the fear promptly." },
    { title = "Grip of the Legion", flags = 128, spell = 31972,
      body = "He curses a random player with fel energy that inflicts nature damage over time until removed." },
    { title = "Soul Charge", flags = 32, spell = 32054,
      body = "Each time a player dies, Archimonde absorbs their soul and later unleashes a Soul Charge, dealing damage to nearby players based on the fallen's class. Minimize deaths to limit these bursts." },
  },

  -- Sunwell Plateau (instance 752)
  [1591] = { -- Kalecgos
    { title = "Spectral Blast", flags = 32, spell = 44869,
      body = "Kalecgos blasts an area of the floor, banishing players caught in it into the Spectral Realm where they must help slay Sathrovarr the Corruptor before they are returned to the physical world." },
    { title = "Arcane Buffet", flags = 128, spell = 45018,
      body = "Kalecgos wracks the raid with arcane energy, applying a stacking debuff that steadily increases the arcane damage each player takes for the rest of the fight." },
    { title = "Frost Breath", flags = 16, spell = 44799,
      body = "The dragon exhales a wide cone of frost before him, inflicting heavy frost damage to everyone standing in the frontal breath." },
    { title = "Tail Lash", flags = 1, spell = 45122,
      body = "Kalecgos sweeps his tail behind him, damaging and dazing any players caught to his rear." },
    { title = "Corrupting Strike", flags = 1, spell = 45029,
      body = "In the Spectral Realm, Sathrovarr the Corruptor strikes his current target, adding a burst of shadow damage on top of his melee blows." },
    { title = "Shadow Bolt Volley", flags = 0, spell = 45031,
      body = "Sathrovarr looses a volley of shadow bolts that strikes every player fighting him within the Spectral Realm." },
    { title = "Curse of Boundless Agony", flags = 256, spell = 45032,
      body = "Sathrovarr afflicts a player with a curse whose damage escalates rapidly over time. It must be removed or it will eventually become fatal, jumping to a nearby player if the victim dies." },
  },

  [1592] = { -- Brutallus
    { title = "Meteor Slash", flags = 17, spell = 45150,
      body = "Brutallus cleaves a wide frontal arc, splitting the enormous fire damage among all players in front of him and leaving a stacking vulnerability that increases the fire damage they take. The raid stacks into two groups to share it." },
    { title = "Burn", flags = 16, spell = 45141,
      body = "Brutallus ignites a random player with a burning debuff that deals mounting fire damage and spreads to anyone standing too close, forcing afflicted players to spread out." },
    { title = "Stomp", flags = 1, spell = 45185,
      body = "Brutallus stomps the ground, striking his tank for heavy physical damage and briefly interrupting spellcasting." },
    { title = "Berserk", flags = 2048, spell = 26662,
      body = "After roughly six minutes Brutallus goes berserk, gaining a massive damage and haste increase that quickly wipes any raid that has not yet defeated him." },
  },

  [1593] = { -- Felmyst
    { title = "Gas Nova", flags = 16, spell = 45855,
      body = "Felmyst releases a nova of noxious gas around herself, dealing heavy damage to all players in melee range." },
    { title = "Encapsulate", flags = 16, spell = 45665,
      body = "Felmyst seals a random player inside a sphere of corrosive gas that deals escalating damage and pulls them into the air, harming allies who remain nearby." },
    { title = "Corrosion", flags = 1, spell = 45866,
      body = "Felmyst spits corrosive fluid at her tank, sharply reducing the target's armor for the duration of the debuff." },
    { title = "Noxious Fumes", flags = 128, spell = 47002,
      body = "A lingering fume aura periodically wracks the entire raid with poison damage throughout the encounter." },
    { title = "Fog of Corruption", flags = 32, spell = 45717,
      body = "Once airborne, Felmyst lays down a creeping fog of corruption; any player it touches is mind-controlled and turned against the raid until freed." },
    { title = "Demonic Vapor", flags = 16, spell = 45399,
      body = "During her flight phase Felmyst chases a player, trailing a stream of demonic vapor across the ground that deals lethal damage to anyone standing in it." },
  },

  [1594] = { -- The Eredar Twins
    { title = "Conflagration", flags = 128, spell = 45342,
      body = "Grand Warlock Alythess sets a random player ablaze, dealing periodic fire damage and disorienting them. The magic effect can be dispelled to end it early." },
    { title = "Blaze", flags = 16, spell = 45235,
      body = "Alythess scorches the ground beneath players, leaving patches of blaze that inflict rapid fire damage to anyone who stands in them." },
    { title = "Pyrogenics", flags = 0, spell = 45230,
      body = "Alythess radiates an aura that increases the fire damage taken by all nearby players, amplifying her other fire abilities." },
    { title = "Shadow Nova", flags = 16, spell = 45329,
      body = "Lady Sacrolash unleashes a burst of shadow energy that deals massive shadow damage and knocks back every player in the raid." },
    { title = "Shadowfury", flags = 16, spell = 45270,
      body = "Sacrolash calls down a shadowfury at a targeted location, stunning and heavily damaging players caught within it." },
    { title = "Dark Flame", flags = 48, spell = 45345,
      body = "A player struck by both Alythess's flame and Sacrolash's shadow attacks is branded with Dark Flame, a lethal combined debuff. The twins share a health pool and enrage, so they must be brought down together." },
  },

  [1595] = { -- M'uru
    { title = "Negative Energy", flags = 16, spell = 46009,
      body = "M'uru fires beams of negative energy that arc to the nearest players, dealing heavy shadow damage. Positioning is used to control who absorbs the beams." },
    { title = "Dark Fiends", flags = 32, spell = 45996,
      body = "M'uru opens zones of darkness that spawn Dark Fiends; if not killed quickly they detonate, damaging and silencing nearby players." },
    { title = "Summon Void Sentinels", flags = 32, spell = 45988,
      body = "M'uru calls Void Sentinels into the fight, powerful adds that must be tanked and killed while the raid manages the rest of the encounter." },
    { title = "Summon Sunblade Berserkers", flags = 32, spell = 46037,
      body = "Portals disgorge waves of Sunblade Berserkers and Fury Mages that pour into the room and must be controlled and cut down." },
    { title = "Black Hole", flags = 48, spell = 46282,
      body = "In his second form as Entropius, the boss spawns singularities that pull players toward them and inflict lethal shadow damage, forcing constant repositioning." },
  },

  [1596] = { -- Kil'jaeden
    { title = "Soul Flay", flags = 1, spell = 45442,
      body = "Kil'jaeden channels a beam of shadow at his tank, dealing sustained shadow damage and slowing the target." },
    { title = "Legion Lightning", flags = 0, spell = 45664,
      body = "Kil'jaeden strikes a player with fel lightning that arcs onward to additional nearby players, encouraging the raid to stay spread." },
    { title = "Fire Bloom", flags = 16, spell = 45641,
      body = "Kil'jaeden brands the raid with Fire Bloom, burning any afflicted player who moves, forcing them to stand still until it fades." },
    { title = "Darkness of a Thousand Souls", flags = 16, spell = 46605,
      body = "Kil'jaeden channels a growing storm of shadow, culminating in a raid-wide burst of heavy shadow damage that the healers must prepare for." },
    { title = "Sinister Reflection", flags = 32, spell = 45892,
      body = "Kil'jaeden conjures shadowy reflections of random players that mimic their class abilities and must be dealt with alongside the boss." },
    { title = "Armageddon", flags = 48, spell = 45921,
      body = "In the final phase Kil'jaeden rains flaming meteors across the platform. Players channel Anveena's power through the Blaze of the Heavens shield to survive the onslaught and weaken him." },
  },
  
  -- Zul'Aman (instance 780)
  [186] = { -- Akil'zon
    { title = "Electrical Storm", flags = 48, spell = 43648,
      body = "Akil'zon summons a violent electrical storm that lifts a random player into the air. Allies must stack beneath the suspended player to avoid the deadly lightning striking the rest of the raid." },
    { title = "Static Disruption", flags = 128, spell = 44008,
      body = "A burst of electricity strikes a random player, dealing Nature damage and increasing the Nature damage taken by nearby allies. Spread out to prevent multiple players from being afflicted." },
    { title = "Call Lightning", flags = 128, spell = 43661,
      body = "Akil'zon repeatedly calls down bolts of lightning on his current target, inflicting heavy Nature damage throughout the encounter." },
    { title = "Summon Soaring Eagles", flags = 32, spell = 44769,
      body = "Soaring Eagles join the fight and harass random players, repeatedly swooping through the raid until defeated." },
  },

  [187] = { -- Nalorakk
    { title = "Bear Form", flags = 32, spell = 42377,
      body = "Nalorakk alternates between troll and bear forms throughout the encounter, gaining different abilities in each phase while retaining his previous threat." },
    { title = "Brutal Swipe", flags = 1, spell = 42384,
      body = "A crushing cleave strikes Nalorakk's current target and anyone standing beside them. Only the active tank should remain in front of the boss." },
    { title = "Mangle", flags = 8193, spell = 44955,
      body = "In bear form Nalorakk mangles his current target, inflicting heavy physical damage and leaving a powerful Bleed effect." },
    { title = "Surge", flags = 16, spell = 42402,
      body = "Nalorakk charges a distant player, dealing heavy damage before immediately returning to his tank." },
    { title = "Lacerating Slash", flags = 8193, spell = 42395,
      body = "A vicious slash leaves a stacking Bleed on Nalorakk's tank, increasing healing requirements as the fight progresses." },
  },

  [188] = { -- Jan'alai
    { title = "Flame Breath", flags = 16, spell = 43140,
      body = "Jan'alai breathes a cone of fire in front of him, dealing heavy Fire damage. The tank should always keep him facing away from the raid." },
    { title = "Fire Bombs", flags = 48, spell = 42628,
      body = "Jan'alai fills the arena with Fire Bombs before igniting them simultaneously. Players must quickly locate a safe gap or risk being killed in the explosions." },
    { title = "Hatch Eggs", flags = 32, spell = 43144,
      body = "Dragonhawk eggs hatch throughout the encounter, releasing Amani Dragonhawk Hatchlings that quickly overwhelm the raid if left alive." },
    { title = "Summon Amani Hatchers", flags = 32, spell = 43962,
      body = "Amani Hatchers run toward the egg platforms and rapidly hatch large groups of Dragonhawks unless stopped." },
    { title = "Frenzy", flags = 2048, spell = 44779,
      body = "After enough eggs have been destroyed or at low health, Jan'alai enters a frenzy, dramatically increasing his attack speed until defeated." },
  },

  [189] = { -- Halazzi
    { title = "Saber Lash", flags = 1, spell = 43267,
      body = "Halazzi lashes out in a wide arc, splitting heavy physical damage between everyone standing in front of him. Multiple tanks should share the attack." },
    { title = "Split Form", flags = 32, spell = 43142,
      body = "At health thresholds Halazzi separates into his troll body and Spirit Lynx, forcing the raid to manage both enemies before they merge once more." },
    { title = "Lightning Totem", flags = 32, spell = 43302,
      body = "Halazzi summons a Lightning Totem that repeatedly shocks nearby players. Destroy the totem quickly to reduce incoming raid damage." },
    { title = "Frenzy", flags = 2048, spell = 43139,
      body = "Halazzi periodically enters a frenzy, greatly increasing his melee damage until soothed or the effect expires." },
  },

  [190] = { -- Hex Lord Malacrass
    { title = "Spirit Bolts", flags = 16, spell = 43383,
      body = "Malacrass bombards the entire raid with shadowy Spirit Bolts, dealing unavoidable Shadow damage over several seconds." },
    { title = "Drain Power", flags = 32, spell = 44131,
      body = "Hex Lord Malacrass steals power from every player, increasing his own damage while reducing the raid's effectiveness for the remainder of the fight." },
    { title = "Siphon Soul", flags = 32, spell = 43501,
      body = "Malacrass steals the soul of a random player, gaining access to several abilities from that player's class for a short time." },
    { title = "Spirit Companions", flags = 32, spell = 0,
      body = "Malacrass is accompanied by four random Amani champions selected from a larger pool. Each encounter requires a different strategy depending on which companions are present." },
  },

  [191] = { -- Zul'jin
    { title = "Whirlwind", flags = 16, spell = 17207,
      body = "During his troll aspect Zul'jin spins through nearby players, dealing heavy physical damage. Melee should move away until the attack ends." },
    { title = "Grievous Throw", flags = 8192, spell = 43093,
      body = "In bear form Zul'jin hurls a grievous weapon that leaves a Bleed effect which persists until the victim is healed to full health." },
    { title = "Energy Storm", flags = 16, spell = 43983,
      body = "While empowered by the eagle spirit, Zul'jin fills the platform with electrical energy that continually damages players throughout the phase." },
    { title = "Claw Rage", flags = 16, spell = 43150,
      body = "In lynx form Zul'jin fixates on a random player, rapidly striking them with a flurry of claw attacks before returning to the tank." },
    { title = "Flame Whirl", flags = 16, spell = 43213,
      body = "In dragonhawk form Zul'jin unleashes fiery cyclones and pillars of flame that force the raid to keep moving until the phase ends." },
    { title = "Animal Aspects", flags = 32, spell = 0,
      body = "As his health falls, Zul'jin invokes the spirits of the bear, eagle, lynx and dragonhawk, completely changing his abilities with each new phase." },
  },
  [192] = { -- Amani Chests
    { title = "Save the Hostages", flags = 32, spell = 25236,
      body = "Zul'Aman provides a unique challenge in which players are put on an optional mission to defeat the four Loa bosses in Zul'Aman: Akil'zon (Eagle), Nalorakk (Bear), Jan'alai (Dragonhawk), and Halazzi (Lynx), within 45 minutes of starting the event. You only get one chance at this event; if you fail it, there are no other attempts until the raid lockout resets. The reward for doing so is that when you free a hostage from each boss, it grants you a chest with loot each time you do so" },
  },
  
}

NE.ej.ABIL_TBC = ABIL

-- Merge the seeded raid abilities into NE.ej.DATA. Fills only bosses that have no sections yet, so
-- the DB2-extracted dungeon sections (already on their encounters via EJData.lua) always win. Runs
-- AFTER EJData.lua has appended the TBC instances, so every raid encounter is present to match.
local function applyAbilities()
  local data = NE.ej.DATA
  if not data then return end
  for _, inst in ipairs(data.instances or {}) do
    for _, enc in ipairs(inst.encounters or {}) do
      local list = ABIL[enc.id]
      if list and (not enc.sections or #enc.sections == 0) then
        local secs = {}
        local n = #list
        for i, a in ipairs(list) do
          secs[i] = {
            id = enc.id * 1000 + i, title = a.title, parent = 0, child = 0,
            sib = (i < n) and (enc.id * 1000 + i + 1) or 0, order = i,
            spell = a.spell or 0, icon = a.icon or 0, flags = a.flags or 0,
            cdisp = 0, body = a.body,
          }
        end
        enc.sections = secs
        enc.rootSection = secs[1] and secs[1].id or 0
      end
    end
  end
end
applyAbilities()
