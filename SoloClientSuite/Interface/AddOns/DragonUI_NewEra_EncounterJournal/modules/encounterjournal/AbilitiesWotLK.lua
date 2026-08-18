local NE = DragonUI_NewEra
-- Addon/EncounterJournal/AbilitiesWotLK.lua — hand-seeded boss ability sections for Wrath of the
-- Lich King (tier=3), the same overlay mechanism as AbilitiesEra.lua/AbilitiesTBC.lua: merged
-- into NE.ej.DATA at load by encounter id, WITHOUT touching DataWotLK.lua. Loaded by
-- DragonUI_NewEra.toc AFTER DataWotLK.lua (which builds NE.ej.DATA.instances for tier=3).
--
-- Sourcing: ~82 of the 119 WotLK encounters below are seeded from a user-supplied CSV export of
-- Wowhead WotLK tooltip text (wotlk_complete_boss_abilities_tooltips_v23.csv, Gemini-parsed, not
-- guaranteed 100% accurate) — body text is PARAPHRASED into this file's own prose rather than
-- copied verbatim, and `spell` is the real spellID pulled from that CSV's Wowhead links. The
-- remaining ~37 encounters (mostly dungeon trash-tier/event bosses and Vault of Archavon/Onyxia
-- that the CSV didn't cover) are hand-written from general WotLK encounter-design knowledge; per
-- this project's "never fabricate" rule (see AbilitiesTBC.lua), those entries use spell=0 rather
-- than a guessed spellID — only CSV-sourced ids (independently checkable against the Wowhead
-- link) are populated. Flags follow the same bit scheme as AbilitiesEra/AbilitiesTBC: Tank(1),
-- Heal(4), Deadly(16), Important(32), Interrupt(64), Magic(128), Curse(256), Poison(512),
-- Disease(1024), Enrage(2048), Bleed(8192); sums combine.
--
-- Schema: ABIL[encounterID] = { {title=, body=, flags=, spell=}, ... }, identical to
-- AbilitiesTBC.lua. Section ids are synthesised as encID*1000 + index by the shared merge logic
-- below (WotLK encIDs are 9000101-9002501, so no collision with any other tier's id space).

NE.ej = NE.ej or {}

local ABIL = {

  ------------------------------------------------------------------------------------------------
  -- Utgarde Keep (instance 90001)
  ------------------------------------------------------------------------------------------------
  [9000101] = { -- Prince Keleseth
    { title = "Shadow Bolt", flags = 128, spell = 43667,
      body = "Keleseth hurls a bolt of dark energy at a random target for Shadow damage. A steady, low-priority nuisance while the adds are the real threat." },
    { title = "Frost Tomb", flags = 16, spell = 48400,
      body = "Encases a player in a block of solid ice, stunning them and slowly draining their health until the raid breaks the tomb open. Free the trapped player quickly." },
    { title = "Decrepit Skeletons", flags = 32, spell = 0,
      body = "Skeletal minions rise around the room and must be cleaved or AoE'd down before they overwhelm the group; Keleseth grows more dangerous the longer they're ignored." },
  },

  [9000102] = { -- Skarvald the Constructor & Dalronn the Controller
    { title = "Charge (Skarvald)", flags = 1, spell = 43651,
      body = "Skarvald charges the current target for heavy Physical damage and a brief stun. The tank should expect periodic repositioning as he resets between charges." },
    { title = "Whirlwind (Skarvald)", flags = 16, spell = 0,
      body = "Skarvald spins with his weapon drawn, striking everyone in melee range. Non-tanks should give him room during the spin." },
    { title = "Chains of Servitude (Dalronn)", flags = 128, spell = 0,
      body = "Dalronn roots a player in place with binding magic while he peppers the group with Shadow Bolts. Dispel or break the chains to keep the raid mobile." },
    { title = "Fight Together", flags = 32, spell = 0,
      body = "Skarvald and Dalronn heal each other and share threat while both are alive; keeping their health totals even (or killing them close together) avoids a prolonged one-on-one finish." },
  },

  [9000103] = { -- Ingvar the Plunderer
    { title = "Cleave", flags = 1, spell = 42723,
      body = "Strikes the tank and nearby allies for extra melee damage in a frontal arc. Non-tanks should stay out of Ingvar's front cone." },
    { title = "Smash", flags = 16, spell = 42669,
      body = "Slams the ground in front of him, dealing heavy Physical damage to everyone caught in the blast and knocking them back." },
    { title = "Dark Smash", flags = 16, spell = 42730,
      body = "After Ingvar rises undead in phase two, this unholy-infused smash deals lethal Shadow and Physical damage to anyone standing directly in front of him — never tank this phase facing the raid." },
    { title = "Dreadful Roar", flags = 64, spell = 42729,
      body = "A terrifying roar that silences everyone nearby and interrupts spellcasting; casters should watch for this and be ready to resume the moment it fades." },
  },

  ------------------------------------------------------------------------------------------------
  -- The Nexus (instance 90002)
  ------------------------------------------------------------------------------------------------
  [9000201] = { -- Ormorok the Tree-Shaper
    { title = "Spell Reflection", flags = 128, spell = 47981,
      body = "Ormorok surrounds himself in a barrier that reflects the next harmful spell back at its caster. Casters should hold their damage spells while it's up and let melee carry the burst." },
    { title = "Crystal Spikes", flags = 16, spell = 47958,
      body = "Jagged crystal spikes erupt beneath random players, dealing heavy Physical damage and launching them into the air. Watch the ground-targeted warning and step off the spot." },
  },

  [9000202] = { -- Anomalus
    { title = "Chaotic Rift", flags = 32, spell = 47743,
      body = "Anomalus periodically becomes invulnerable and opens rifts that spawn waves of Mana Wraiths. The rifts must be destroyed to bring him back within reach and stop the adds." },
    { title = "Spark Arcane Bolt", flags = 128, spell = 47751,
      body = "Fires bolts of raw arcane energy at random targets. A steady damage source while the group's attention is split toward the rifts." },
  },

  [9000203] = { -- Grand Magus Telestra
    { title = "Fire Bomb", flags = 16, spell = 47772,
      body = "Hurls a fiery orb at a targeted location, burning anyone caught nearby. Move out of the marked area before it lands." },
    { title = "Ice Nova", flags = 16, spell = 47773,
      body = "Releases a burst of freezing frost that roots nearby targets in place, leaving them exposed to whatever attack follows." },
    { title = "Gravity Well", flags = 32, spell = 47740,
      body = "Creates a gravitational anomaly that pulls everyone toward its center, useful for Telestra's split-image phases to bunch the raid together at the wrong moment." },
  },

  [9000204] = { -- Commander Kolurg
    { title = "Rescue the Commander", flags = 32, spell = 0,
      body = "Kolurg is a captive ally, chained and guarded by Ethereal captors. Freeing him turns the fight into an escort: keep him alive while his guards focus the raid with arcane bolts and binds." },
    { title = "Arcane Bind", flags = 128, spell = 0,
      body = "The Ethereal Beacons anchoring the cell periodically root nearby players with binding arcane energy; break free and keep moving to protect Kolurg." },
  },

  [9000205] = { -- Keristrasza
    { title = "Intense Cold", flags = 16, spell = 48094,
      body = "A stacking frost aura that punishes standing still — everyone must keep moving (or use the room's crystal updrafts) or the cold builds until it becomes lethal." },
    { title = "Crystal Chains", flags = 16, spell = 50997,
      body = "Encases a player in crystal chains, immobilizing them and draining their health over time. Free the chained player as quickly as possible." },
  },

  ------------------------------------------------------------------------------------------------
  -- Azjol-Nerub (instance 90003)
  ------------------------------------------------------------------------------------------------
  [9000301] = { -- Krik'thir the Gatewatcher
    { title = "Summon Watchers", flags = 32, spell = 0,
      body = "Krik'thir calls in waves of Anub'ar Watchers and Anub'ar Champions from the surrounding webbing. Focus the casters among the adds first to cut down incoming damage." },
    { title = "Mind Flay", flags = 128, spell = 0,
      body = "Channels a bolt of shadow energy at a random player, dealing steady Shadow damage while the caster stands still — an easy interrupt if it's threatening a healer." },
  },

  [9000302] = { -- Hadronox
    { title = "Acid Cloud", flags = 16, spell = 53400,
      body = "Spits a toxic cloud of acid onto the ground that damages anyone standing inside. Step out of the puddle as soon as it lands." },
    { title = "Leech Poison", flags = 512, spell = 53030,
      body = "Infects the current target with a draining venom that saps their life to heal Hadronox — dispel or heal through it so the boss doesn't out-heal the raid's damage." },
    { title = "Web Spray", flags = 32, spell = 53177,
      body = "Hadronox retreats up the webbed walls and sprays the room, and can seal off the room's spiders behind webbing if he isn't kept engaged near the entrance." },
  },

  [9000303] = { -- Anub'arak (Azjol-Nerub)
    { title = "Pound", flags = 16, spell = 27607,
      body = "Slams a massive claw into the ground, dealing heavy Physical damage to everyone in a frontal cone and knocking them down. Stay out of Anub'arak's front arc." },
    { title = "Impale", flags = 16, spell = 53472,
      body = "Drives sharp subterranean spikes up through the ground beneath a player, dealing lethal Physical damage and launching them into the air." },
    { title = "Submerge", flags = 32, spell = 53421,
      body = "Anub'arak periodically burrows underground and calls up Nerubian Burrowers to swarm the raid before resurfacing to resume the melee fight." },
  },

  ------------------------------------------------------------------------------------------------
  -- Ahn'kahet: The Old Kingdom (instance 90004)
  ------------------------------------------------------------------------------------------------
  [9000401] = { -- Elder Nadox
    { title = "Summon Nerubian Egg", flags = 32, spell = 0,
      body = "Nadox continually hatches Nerubian Swarmers and Nerubian Broodkeepers from eggs scattered around his chamber; thinning the eggs keeps the add count manageable." },
    { title = "Spider Bite", flags = 1024, spell = 0,
      body = "A diseased bite on the tank that lingers as a stacking Disease debuff — healers should watch for it building up over a long tanking phase." },
  },

  [9000402] = { -- Prince Taldaram
    { title = "Conjure Flame Sphere", flags = 16, spell = 55931,
      body = "Summons a slow, tracking orb of fire that explodes with heavy Fire damage on contact. Anyone it's chasing should keep it away from the raid." },
    { title = "Devour", flags = 512, spell = 55959,
      body = "Taldaram leaps onto a random player, draining their life force to heal himself. He becomes immune to physical damage while feeding, so ranged and casters carry the burst during it." },
  },

  [9000403] = { -- Amanitar
    { title = "Summon Mushrooms", flags = 32, spell = 0,
      body = "Amanitar litters the room with mushroom clusters that release a lingering cloud when destroyed; pop them away from the raid rather than letting them mature." },
    { title = "Spore Cloud", flags = 512, spell = 0,
      body = "The disturbed mushroom patches unleash a poisonous cloud that damages and disorients anyone caught standing in it." },
  },

  [9000404] = { -- Jedoga Shadowseeker
    { title = "Thundershock", flags = 16, spell = 56894,
      body = "Discharges a wide electrical storm that hits every nearby enemy for heavy Nature damage — a strong reason to spread away from melee range when possible." },
    { title = "Cyclone Strike", flags = 1, spell = 56892,
      body = "Whirls her weapon rapidly, striking nearby enemies for solid weapon damage and knocking them back." },
    { title = "Sacrifice", flags = 32, spell = 56150,
      body = "Jedoga can sacrifice one of her Twilight Volunteers to heal herself and grow stronger; killing the volunteers first denies her the resource." },
  },

  [9000405] = { -- Herald Volazj
    { title = "Mind Shatter", flags = 128, spell = 57496,
      body = "Shatters the target's sanity, dealing heavy Shadow damage and slowing their attack speed. A dangerous burst that healers should be ready to top off." },
    { title = "Insanity", flags = 32, spell = 57512,
      body = "At low health Volazj splits the raid's minds, spawning a personal phantasmal copy of each player that must be fought and defeated individually before rejoining the group fight." },
  },

  ------------------------------------------------------------------------------------------------
  -- Drak'Tharon Keep (instance 90005)
  ------------------------------------------------------------------------------------------------
  [9000501] = { -- Trollgore
    { title = "Consume", flags = 4, spell = 49380,
      body = "Trollgore devours a nearby corpse to heal himself substantially — the raid should avoid leaving fresh trash corpses near the pull, or race him down before he can feed." },
    { title = "Stampede", flags = 16, spell = 0,
      body = "Charges through the room, trampling and damaging everyone in his path. Stay clear of the direct line between Trollgore and his target." },
  },

  [9000502] = { -- Novos the Summoner
    { title = "Summon Skeletons", flags = 32, spell = 0,
      body = "Novos periodically raises waves of skeletal minions from the surrounding crypts; keep them off the healers while whittling Novos down between waves." },
    { title = "Frost Bolt Volley", flags = 128, spell = 49037,
      body = "Blankets the raid in bolts of frost, dealing damage and briefly slowing anyone hit — a good spell to interrupt if it threatens to chain-slow the group." },
  },

  [9000503] = { -- King Dred
    { title = "Bellowing Roar", flags = 16, spell = 59422,
      body = "Lets out a deafening roar that fears every nearby player for several seconds. Trinkets or fear breaks help keep the raid in position." },
    { title = "Grievous Bite", flags = 8192, spell = 48873,
      body = "Tears deep, bleeding wounds into the tank, stacking a heavy physical bleed over time. Healers should track the stacks and be ready for the burn as they climb." },
  },

  [9000504] = { -- The Prophet Tharon'ja
    { title = "Decay Flesh", flags = 1024, spell = 49527,
      body = "Rots the flesh of nearby targets, dealing Shadow damage over time and reducing their armor. Stacks make the tank noticeably squishier the longer the phase runs." },
    { title = "Shadow Volley", flags = 128, spell = 49529,
      body = "Hurls dark bolts at everyone nearby for Shadow damage — steady raid-wide pressure during his living phases." },
    { title = "Forces of the Amani", flags = 32, spell = 0,
      body = "Tharon'ja alternates between his living and undead forms and can raise the fallen trolls of the room as skeletal allies; keep the group topped up through the transitions." },
  },

  ------------------------------------------------------------------------------------------------
  -- The Violet Hold (instance 90006)
  ------------------------------------------------------------------------------------------------
  [9000601] = { -- Erekem
    { title = "Frost Shock", flags = 128, spell = 0,
      body = "Erekem blasts a random target with frost, dealing damage and slowing their movement. His two Ymirjar Guardians should be controlled or killed alongside him." },
    { title = "Whirlwind", flags = 16, spell = 0,
      body = "Spins with his blades drawn, striking everyone nearby — non-tanks should give him space during the spin." },
  },

  [9000602] = { -- Zuramat the Obliterator
    { title = "Shadow Channeling", flags = 128, spell = 0,
      body = "Zuramat periodically becomes immune while channeling a shadow bolt at the raid; interrupting or outlasting the channel is the priority during it." },
    { title = "Summon Void Sentinel", flags = 32, spell = 54369,
      body = "Calls in a Void Sentinel that shields Zuramat with an absorb barrier; kill the sentinel quickly to strip the shield and keep damage flowing." },
  },

  [9000603] = { -- Xevozz
    { title = "Summon Ethereal Spheres", flags = 16, spell = 54102,
      body = "Summons volatile spheres that drift toward random players and detonate for area damage on contact — keep moving so they don't reach the raid." },
    { title = "Arcane Overload", flags = 128, spell = 0,
      body = "Xevozz debuffs a player so that any spell they cast next explodes for damage; casters should hold their next cast until the mark fades." },
  },

  [9000604] = { -- Ichoron
    { title = "Water Globule", flags = 32, spell = 54267,
      body = "Splits off globules of water that must be killed away from the raid, since destroying them showers nearby players — spread these kills out around the room." },
    { title = "Expulse Water", flags = 16, spell = 0,
      body = "At intervals Ichoron unleashes a violent burst of water that knocks back and damages anyone nearby; players should stack against a wall to avoid being scattered." },
  },

  [9000605] = { -- Moragg
    { title = "Optical Blast", flags = 16, spell = 0,
      body = "Fires a beam from his central eye at the current target, dealing heavy damage — the tank should expect periodic large hits." },
    { title = "Consuming Beam", flags = 4, spell = 0,
      body = "Locks a beam onto a player that drains their life to heal Moragg; breaking line of sight or moving out of range stops the beam." },
  },

  [9000606] = { -- Lavanthor
    { title = "Fire Nova", flags = 16, spell = 0,
      body = "Erupts in a burst of fire around himself, damaging everyone in melee range. Ranged attackers are safer than staying in close." },
    { title = "Enrage", flags = 2048, spell = 0,
      body = "The longer the fight runs the angrier Lavanthor gets, gradually hitting harder and faster — favor a quick kill over a drawn-out one." },
  },

  [9000607] = { -- Cyanigosa
    { title = "Uncontrollable Blizzard", flags = 16, spell = 58694,
      body = "Fills the room with a freezing blizzard, dealing Frost damage over time and slowing everyone caught inside." },
    { title = "Mana Destruction", flags = 128, spell = 59374,
      body = "Detonates the mana pools of casters near her, dealing damage scaled to how much mana was lost — mana users should be cautious about running dry near her." },
    { title = "Tail Sweep", flags = 16, spell = 58690,
      body = "Sweeps her tail through anyone standing behind her, dealing heavy Physical damage and knocking them back — melee should stay to her sides." },
  },

  ------------------------------------------------------------------------------------------------
  -- Gundrak (instance 90007)
  ------------------------------------------------------------------------------------------------
  [9000701] = { -- Slad'ran
    { title = "Summon Serpents", flags = 32, spell = 0,
      body = "Slad'ran calls venomous snakes up out of the ground around the room; clear them quickly so they don't stack poison on the raid." },
    { title = "Venom Bolt Volley", flags = 512, spell = 0,
      body = "Sprays the raid with bolts of venom, poisoning everyone hit and dealing damage over time." },
  },

  [9000702] = { -- Drakkari Colossus
    { title = "Mojo Frenzy", flags = 2048, spell = 0,
      body = "Drinking from the room's mojo pools speeds the Colossus up and increases his damage; interrupting his path to a pool denies the buff." },
    { title = "Ground Smash", flags = 16, spell = 0,
      body = "Slams the ground with tremendous force, dealing heavy Physical damage to everyone nearby and knocking them down." },
  },

  [9000703] = { -- Moorabi
    { title = "Quake", flags = 64, spell = 55355,
      body = "Stomps the ground, sending out a localized earthquake that damages and interrupts anyone nearby — a good moment to hold casts." },
    { title = "Mammoth Transformation", flags = 32, spell = 55098,
      body = "Moorabi transforms into a massive mammoth, gaining a large health and damage boost along with new trampling attacks; treat this as a new, deadlier phase of the fight." },
  },

  [9000704] = { -- Eck the Ferocious
    { title = "Tail Sweep", flags = 16, spell = 0,
      body = "Sweeps his tail behind him, dealing heavy Physical damage and knocking back anyone caught there — stay out of his rear arc." },
    { title = "Acid Spit", flags = 512, spell = 55814,
      body = "Spits acid at a random target, poisoning them and dealing damage over time." },
  },

  [9000705] = { -- Gal'darah
    { title = "Whirlwind", flags = 16, spell = 55250,
      body = "Spins through the room with his blades out, striking everyone nearby for Physical damage." },
    { title = "Impale", flags = 16, spell = 55276,
      body = "Launches sharp tusks from the ground in a line, dealing heavy Physical damage and tossing anyone hit into the air." },
    { title = "Rhino Transformation", flags = 32, spell = 0,
      body = "In the fight's final phase Gal'darah transforms into a massive rhino, charging through the room and gaining powerful new trampling attacks." },
  },

  ------------------------------------------------------------------------------------------------
  -- Halls of Stone (instance 90008)
  ------------------------------------------------------------------------------------------------
  [9000801] = { -- Maiden of Grief
    { title = "Storm of Grief", flags = 16, spell = 50752,
      body = "Surrounds herself in a sorrowful storm that damages and slows anyone standing nearby — step back rather than trading melee blows through it." },
    { title = "Shock of Sorrow", flags = 16, spell = 50760,
      body = "Stuns every nearby player briefly and deals a burst of Holy damage; healers should pre-heal before it lands if possible." },
  },

  [9000802] = { -- Krystallus
    { title = "Ground Slam", flags = 16, spell = 50840,
      body = "Sends seismic shockwaves through the floor that damage and daze everyone nearby." },
    { title = "Shatter", flags = 16, spell = 50810,
      body = "Shatters stone fragments across the room, dealing heavy Physical damage to anyone caught close by." },
  },

  [9000803] = { -- Tribunal of Ages
    { title = "Beam of Light", flags = 128, spell = 51136,
      body = "The Tribunal's statues channel a beam of light at a marked player that must be redirected onto the correct rune to solve the encounter's puzzle rather than left to hit the raid." },
    { title = "Summon Guardians", flags = 32, spell = 0,
      body = "The statues periodically call in stone guardians to defend themselves while the group works the runes; clear them quickly so the beam mechanic isn't interrupted." },
  },

  [9000804] = { -- Sjonnir the Ironshaper
    { title = "Static Charge", flags = 128, spell = 50834,
      body = "Charges a random player with electricity that jumps to anyone standing too close to them — spread out when marked." },
    { title = "Shockwave", flags = 16, spell = 0,
      body = "Slams the ground, sending a shockwave through the room that knocks down and damages everyone nearby." },
    { title = "Activate Iron Sentinels", flags = 32, spell = 0,
      body = "Sjonnir can reactivate the room's dormant Iron Sentinel constructs to fight alongside him if the raid doesn't disable them beforehand." },
  },

  ------------------------------------------------------------------------------------------------
  -- Halls of Lightning (instance 90009)
  ------------------------------------------------------------------------------------------------
  [9000901] = { -- General Bjarngrim
    { title = "Cleave", flags = 1, spell = 0,
      body = "Strikes his current target and nearby allies with each of his four weapons — non-tanks should stay well clear of his melee range." },
    { title = "Enrage", flags = 2048, spell = 0,
      body = "Bjarngrim periodically enrages, hitting significantly harder for a short window; healers should be ready to burn cooldowns on the tank during it." },
  },

  [9000902] = { -- Volkhan
    { title = "Heat Wave", flags = 16, spell = 52387,
      body = "Radiates intense heat across the forge, dealing Fire damage to everyone nearby." },
    { title = "Shatter Molten Golems", flags = 16, spell = 52399,
      body = "Smashes his forged Molten Golems apart, showering the area in molten shrapnel — stand away from the golems when Volkhan turns his attention to them." },
  },

  [9000903] = { -- Ionar
    { title = "Static Overload", flags = 128, spell = 52658,
      body = "Charges a player with electrical energy that pulses outward, damaging anyone standing too close to them." },
    { title = "Spark of Ionar", flags = 32, spell = 52770,
      body = "Ionar periodically splits off a Spark that drifts around the room; stepping into the spark's path safely discharges some of the room's built-up static." },
  },

  [9000904] = { -- Loken
    { title = "Pulsing Shockwave", flags = 16, spell = 52942,
      body = "Loken pulses raw lightning through the room, dealing more damage the closer a player is standing to him — spread to maximum range when it begins." },
    { title = "Nova", flags = 16, spell = 52960,
      body = "At the fight's climax Loken locks the room in an inescapable Nova of accelerating damage; the encounter must end before it finishes ramping up." },
  },

  ------------------------------------------------------------------------------------------------
  -- The Culling of Stratholme (instance 90010)
  ------------------------------------------------------------------------------------------------
  [9001001] = { -- Meathook
    { title = "Meat Wagon Barrage", flags = 16, spell = 0,
      body = "Wagons on the road periodically bombard the area — clearing or avoiding them keeps the pull to Meathook clean before the fight even starts." },
    { title = "Choking Cloud", flags = 1024, spell = 0,
      body = "Meathook exhales a diseased cloud that lingers on the raid, dealing damage over time to anyone slow to move out." },
  },

  [9001002] = { -- Salramm the Fleshcrafter
    { title = "Shadow Bolt Volley", flags = 128, spell = 0,
      body = "Blankets the raid in bolts of Shadow energy — a steady damage source that ramps up if his summoned ghouls are left unchecked." },
    { title = "Summon Rot Hound", flags = 32, spell = 0,
      body = "Calls in Rot Hounds to flank the raid; kill them quickly before their bites start stacking up on the healers." },
  },

  [9001003] = { -- Chrono-Lord Epoch
    { title = "Time Lapse", flags = 32, spell = 0,
      body = "Epoch periodically rewinds a player's recent damage taken, effectively healing them for the same amount and briefly slowing them — a strange defensive mechanic to be aware of rather than fight through." },
    { title = "Wound", flags = 8192, spell = 0,
      body = "Opens a bleeding wound on the tank that deals physical damage over time and stacks the longer melee continues uninterrupted." },
  },

  [9001004] = { -- Infinite Corruptor
    { title = "Corrupted Blood", flags = 1024, spell = 0,
      body = "Infects a random player with a lingering disease that spreads to anyone standing nearby — spread out if you're carrying it." },
    { title = "Time Stop", flags = 16, spell = 0,
      body = "Briefly freezes a player in place, locking them out of acting while the fight continues around them." },
  },

  [9001005] = { -- Mal'Ganis
    { title = "Carrion Swarm", flags = 16, spell = 52720,
      body = "Unleashes a swarm of bats that deals Shadow damage to everyone nearby and knocks them back." },
    { title = "Sleep", flags = 32, spell = 52722,
      body = "Puts a random player into a deep, incapacitating slumber; damage wakes them, but a healer or off-target should watch for anyone who falls asleep at a bad moment." },
    { title = "Vampiric Touch", flags = 512, spell = 52723,
      body = "Imbues Mal'Ganis's attacks with life-draining energy, healing him for a portion of the damage he deals — a fight to end quickly rather than let drag on." },
  },

  ------------------------------------------------------------------------------------------------
  -- Utgarde Pinnacle (instance 90011)
  ------------------------------------------------------------------------------------------------
  [9001101] = { -- Svala Sorrowgrave
    { title = "Sinister Strike", flags = 1, spell = 48267,
      body = "A vicious rogue-style strike against her current target for immediate Physical damage." },
    { title = "Ritual of the Sword", flags = 32, spell = 48276,
      body = "Suspends a targeted player above a sacrificial altar beneath a descending blade — everyone else must deal enough damage to Svala before the blade falls, or the raid must otherwise interrupt the ritual to save them." },
  },

  [9001102] = { -- Gortok Palehoof
    { title = "Fero-Stomp", flags = 16, spell = 0,
      body = "Stomps the ground, dealing heavy Physical damage and knocking down everyone nearby." },
    { title = "Furious Charge", flags = 16, spell = 0,
      body = "Charges a random ranged player, dealing damage and trampling anyone caught in the charge's path." },
    { title = "Enraged", flags = 2048, spell = 0,
      body = "Every time one of Gortok's proto-drake pets dies, he enrages further — killing the pets slowly rather than burning them down fast keeps his damage output manageable." },
  },

  [9001103] = { -- Skadi the Ruthless
    { title = "Whirlwind", flags = 16, spell = 50228,
      body = "Spins in a flurry of steel, striking every nearby player for Physical damage each second the spin lasts." },
    { title = "Freezing Slash", flags = 16, spell = 50264,
      body = "Strikes an enemy with an icy blade, dealing Frost damage and freezing them in place for several seconds." },
    { title = "Harpoon", flags = 32, spell = 0,
      body = "During the drake-riding phase Skadi's harpoons must be intercepted or the raid's mount takes heavy damage — assign players to break the harpoon chains." },
  },

  [9001104] = { -- King Ymiron
    { title = "Bane", flags = 256, spell = 51750,
      body = "Curses a target with dark energy that deals periodic Shadow damage; dispelling it keeps the damage from stacking." },
    { title = "Screaming Dead", flags = 32, spell = 51735,
      body = "Summons vengeful spirits that fear and damage the party — deal with the adds quickly so they don't scatter the raid." },
  },

  ------------------------------------------------------------------------------------------------
  -- The Oculus (instance 90012)
  ------------------------------------------------------------------------------------------------
  [9001201] = { -- Drakos the Interrogator
    { title = "Whirlwind", flags = 16, spell = 0,
      body = "Spins with his weapon drawn, striking everyone in melee range — non-tanks should keep their distance during the spin." },
    { title = "Arcane Vacuum", flags = 128, spell = 0,
      body = "Pulls the raid toward Drakos before releasing a burst of Arcane damage; expect to be repositioned and ready to move back out afterward." },
  },

  [9001202] = { -- Varos Cloudstrider
    { title = "Static Field", flags = 16, spell = 0,
      body = "An aura around Varos that damages anyone who lingers too close — keep moving rather than standing still in melee." },
    { title = "Thundering Storm", flags = 16, spell = 0,
      body = "Charges up and releases a burst of storm energy that damages and knocks back the entire raid." },
  },

  [9001203] = { -- Urom (Mage-Lord Urom)
    { title = "Time Bomb", flags = 16, spell = 51103,
      body = "Afflicts a player with temporal instability that detonates for Arcane damage after several seconds; move away from the raid before it goes off." },
    { title = "Frostbomb", flags = 16, spell = 51110,
      body = "Hurls a volatile bomb of frost that slows movement and deals heavy Frost damage on detonation." },
    { title = "Empowered Arcane Explosion", flags = 16, spell = 51121,
      body = "After a visible channel, Urom unleashes a room-wide wave of arcane energy — using the room's ice blocks for cover mitigates the hit." },
  },

  [9001204] = { -- Ley-Guardian Eregos
    { title = "Arcane Barrage", flags = 128, spell = 51162,
      body = "Fires a flurry of arcane missiles at a random target for solid ranged damage." },
    { title = "Planar Shift", flags = 32, spell = 51163,
      body = "Eregos briefly shifts out of phase, becoming immune to attacks while summoning whelps to harass the raid — clear the whelps quickly before he returns." },
  },

  ------------------------------------------------------------------------------------------------
  -- Vault of Archavon (instance 90013)
  ------------------------------------------------------------------------------------------------
  [9001301] = { -- Archavon the Stone Watcher
    { title = "Crush", flags = 1, spell = 0,
      body = "A heavy melee strike against his current target that also lightly damages nearby allies — the tank should expect a steady stream of large hits." },
    { title = "Rock Shards", flags = 16, spell = 58689,
      body = "Shards of stone erupt beneath random players, dealing Physical damage to anyone caught in the blast." },
    { title = "Stomp", flags = 16, spell = 60880,
      body = "Stomps the ground, knocking back and damaging everyone in the room — a simple positioning check more than a true mechanic." },
  },

  [9001302] = { -- Emalon the Storm Watcher
    { title = "Lightning Nova", flags = 16, spell = 59835,
      body = "Releases a burst of Nature damage across the entire room, hitting everyone regardless of position." },
    { title = "Overcharge", flags = 32, spell = 0,
      body = "Empowers his three Tempest Minions, sharply increasing the damage of their lightning attacks — killing a minion quickly removes a third of the incoming damage." },
  },

  [9001303] = { -- Koralon the Flame Watcher
    { title = "Flame Breath", flags = 16, spell = 0,
      body = "Breathes a cone of fire in front of him, dealing heavy Fire damage to anyone caught in front of Koralon." },
    { title = "Meteor Fists", flags = 16, spell = 66725,
      body = "Slams the ground with his fists, sending fire spreading outward from the impact — melee should be ready to step out and back in." },
    { title = "Burning Aura", flags = 16, spell = 0,
      body = "The ground beneath and around Koralon continuously burns, punishing players who stay in melee range instead of managing their positioning." },
  },

  [9001304] = { -- Toravon the Ice Watcher
    { title = "Frozen Orb", flags = 16, spell = 72092,
      body = "Launches a slow-moving orb of ice that damages and chills anyone it passes through — sidestep its path rather than tanking the hit." },
    { title = "Encase in Ice", flags = 16, spell = 0,
      body = "Traps a player in a block of ice, immobilizing them until it's broken or expires." },
    { title = "Fury of the Ice Watcher", flags = 2048, spell = 0,
      body = "Toravon periodically empowers himself with the room's frost pillars, hitting harder for a duration — a burn window the raid should be prepared to heal through." },
  },

  ------------------------------------------------------------------------------------------------
  -- Naxxramas (instance 90014)
  ------------------------------------------------------------------------------------------------
  [9001401] = { -- Patchwerk
    { title = "Hateful Strike", flags = 1, spell = 28308,
      body = "Slams the melee-range player with the highest current health for extreme Physical damage, then resets its target list — tanks trade this hit back and forth." },
    { title = "Frenzy", flags = 2048, spell = 28131,
      body = "Doubles Patchwerk's physical damage and speeds up his attacks for half a minute; healers should be ready for the tank swap and burn window." },
    { title = "Berserk", flags = 2048, spell = 26662,
      body = "If the enrage timer expires, Patchwerk's damage and speed spike catastrophically — this is effectively an unsurvivable wipe condition, not a mechanic to heal through." },
  },

  [9001402] = { -- Grobbulus
    { title = "Poison Cloud", flags = 512, spell = 28240,
      body = "Leaves a thick, spreading cloud of toxic gas behind him that damages anyone standing inside — keep moving the fight away from old clouds." },
    { title = "Mutating Injection", flags = 512, spell = 28169,
      body = "Injects a player with a toxin that explodes after several seconds (or on dispel), leaving a fresh poison cloud on the ground — run the injected player away from the raid before it pops." },
    { title = "Slime Spray", flags = 16, spell = 28157,
      body = "Sprays a cone of toxic slime in front of him and spawns a Fallout Slime; ranged players should avoid standing directly ahead of Grobbulus." },
  },

  [9001403] = { -- Gluth
    { title = "Mortal Wound", flags = 8192, spell = 29337,
      body = "Stacks a physical wound on the tank that reduces healing received further with each application — tank swaps or heavy cooldowns manage the stacking." },
    { title = "Decimate", flags = 16, spell = 28374,
      body = "Crushes every nearby player and zombie down to a sliver of their maximum health — a burst healers should top the raid off before, not after." },
    { title = "Enrage", flags = 2048, spell = 28371,
      body = "Increases Gluth's physical damage and attack speed for a couple of minutes — expect a harder tanking phase during it." },
  },

  [9001404] = { -- Thaddius
    { title = "Polarity Shift", flags = 16, spell = 28089,
      body = "Charges every raid member with a Positive or Negative polarity; standing near someone of the opposite charge deals severe damage to both, so the raid must regroup by matching charge each time it flips." },
    { title = "Chain Lightning", flags = 128, spell = 28090,
      body = "Strikes a target with lightning that arcs on to several nearby players for Nature damage." },
  },

  [9001405] = { -- Anub'Rekhan
    { title = "Impale", flags = 16, spell = 28783,
      body = "Spikes erupt from the earth in a line, dealing heavy Physical damage and launching anyone hit into the air with a stun." },
    { title = "Locust Swarm", flags = 16, spell = 28785,
      body = "Releases a swarm of locusts that slows Anub'Rekhan and silences and damages everyone nearby — casters lose the ability to act while it's up." },
    { title = "Summon Crypt Guards", flags = 32, spell = 0,
      body = "Calls in a Crypt Guard that attacks players and stacks a bleed effect; keeping it off the raid's ranged and healers matters more than burning it down instantly." },
  },

  [9001406] = { -- Grand Widow Faerlina
    { title = "Poison Bolt Volley", flags = 512, spell = 28796,
      body = "Showers every nearby enemy with poison bolts, dealing instant Nature damage followed by a lingering damage-over-time tick." },
    { title = "Rain of Fire", flags = 16, spell = 28794,
      body = "Calls down fire on a targeted area, punishing anyone who stays inside the zone for its duration." },
    { title = "Frenzy", flags = 2048, spell = 28798,
      body = "Doubles her physical damage and speeds her attacks — Faerlina's adds must be mind-controlled to silence her before this triggers, or the tank needs strong cooldowns to survive it." },
    { title = "Widow's Embrace", flags = 32, spell = 28790,
      body = "Sacrificing a captive Worshipper silences Faerlina's Nature spells and prevents her Frenzy for a time — a defensive tool the encounter is built around using." },
  },

  [9001407] = { -- Maexxna
    { title = "Web Wrap", flags = 16, spell = 28622,
      body = "Wraps a random player in a sticky cocoon and hauls them to the wall, dealing Nature damage every second until the web is destroyed." },
    { title = "Web Spray", flags = 16, spell = 28841,
      body = "Sprays webbing across the whole room, stunning and damaging everyone caught in the open." },
    { title = "Necrotic Poison", flags = 512, spell = 28776,
      body = "A deadly poison that reduces all healing received by the target by a huge margin for half a minute — the tank needs external cooldowns or a swap to survive it." },
  },

  [9001408] = { -- Instructor Razuvious
    { title = "Unbalancing Strike", flags = 1, spell = 26613,
      body = "A heavy strike against his target that also cuts their defense skill, making follow-up hits land harder." },
    { title = "Disrupting Shout", flags = 64, spell = 29107,
      body = "A wide interrupt-and-silence shout that locks out spellcasting for anyone caught nearby." },
    { title = "Jagged Knife", flags = 8192, spell = 55550,
      body = "Throws a knife that deals Physical damage and opens a bleeding wound that ticks for several seconds." },
  },

  [9001409] = { -- Gothik the Harvester
    { title = "Harvest Soul", flags = 512, spell = 28679,
      body = "Drains souls from nearby players, dealing Shadow damage and growing stronger with each soul taken — don't let Gothik linger uncontested on the living side." },
    { title = "Unholy Aura", flags = 128, spell = 28350,
      body = "Pulses unholy energy that damages everyone in the room every couple of seconds, on top of the waves of undead spilling in from both sides of the gate." },
  },

  [9001410] = { -- The Four Horsemen
    { title = "Unholy Shadow", flags = 128, spell = 28863,
      body = "Strikes a target with dark magic for a large initial hit followed by a lingering Shadow damage-over-time." },
    { title = "Holy Wrath", flags = 128, spell = 28883,
      body = "Strikes a target with Holy energy that then jumps on to nearby allies, spreading damage across whoever is stacked together." },
    { title = "Void Zone", flags = 16, spell = 28865,
      body = "Drops a damaging void zone on the ground beneath a target; move it off the raid immediately." },
    { title = "Meteor", flags = 16, spell = 28884,
      body = "Calls down a meteor that splits heavy Fire damage among everyone within its blast radius — spread out to soften the hit." },
  },

  [9001411] = { -- Noth the Plaguebringer
    { title = "Curse of the Plaguebringer", flags = 256, spell = 29213,
      body = "Curses nearby players; if it isn't dispelled within ten seconds, it erupts for heavy Shadow damage to the cursed player and everyone near them." },
    { title = "Blink", flags = 32, spell = 29210,
      body = "Teleports Noth to a new target, clearing all stuns and roots on him and wiping his threat table completely — tanks need to reacquire him fast." },
    { title = "Cripple", flags = 16, spell = 29212,
      body = "Reduces the target's movement speed, attack speed, and strength significantly for the duration." },
    { title = "Summon Skeletons", flags = 32, spell = 0,
      body = "Raises Plagued Warriors and Skeletons from the balcony floor plates to assault the raid; these need to be cleared alongside Noth himself." },
  },

  [9001412] = { -- Heigan the Unclean
    { title = "Eruption", flags = 16, spell = 29371,
      body = "Erupts specific floor quadrants with toxic sludge in a rolling pattern — the well-known 'Heigan dance' where the raid must dodge each wave in sequence." },
    { title = "Spell Disruption", flags = 128, spell = 29310,
      body = "An aura that triples the cast time of every nearby enemy's spells, punishing casters who try to stand and nuke through the dance phase." },
    { title = "Decrepit Fever", flags = 1024, spell = 29998,
      body = "Afflicts nearby players with a heavy fever that deals Nature damage and drains Stamina — a reason to keep some distance during the tank-and-spank phase." },
  },

  [9001413] = { -- Loatheb
    { title = "Necrotic Aura", flags = 4, spell = 29184,
      body = "A deathly pulse that blocks all healing received by the raid for the encounter's duration — direct heals must be timed for the brief windows between casts, or absorbed with cooldowns." },
    { title = "Deathbloom", flags = 16, spell = 29865,
      body = "Deals Shadow damage over several seconds, then blooms for a large final hit when it expires — spread out before it detonates." },
    { title = "Inevitable Doom", flags = 256, spell = 29204,
      body = "A terminal curse on a random player that deals heavy Shadow damage after ten seconds; there's no way to remove it, only heal or cooldown through the hit." },
    { title = "Summon Spores", flags = 32, spell = 29234,
      body = "Plague Spores drift toward the raid and, when killed, burst into a cloud that boosts critical strike chance and drops threat for anyone standing in it — useful for DPS to pop deliberately." },
  },

  [9001414] = { -- Sapphiron
    { title = "Frost Aura", flags = 16, spell = 28531,
      body = "A constant frost pulse that damages everyone in the room every couple of seconds regardless of position." },
    { title = "Icebolt", flags = 16, spell = 28522,
      body = "Freezes a random player and everyone standing near them in a solid block of ice, dealing Frost damage — spread out to avoid chaining the freeze to others." },
    { title = "Frost Breath", flags = 16, spell = 28524,
      body = "A frontal cone of frost that deals massive damage and freezes anyone caught in front of Sapphiron; only face him away from the raid." },
    { title = "Life Drain", flags = 512, spell = 28542,
      body = "Drains life from a couple of random targets, damaging them and healing Sapphiron in return." },
  },

  [9001415] = { -- Kel'Thuzad
    { title = "Frost Blast", flags = 16, spell = 27808,
      body = "Locks a player in a block of ice for heavy Frost damage that then chains on to nearby allies — spread the raid to limit how far the bounce reaches." },
    { title = "Shadow Fissure", flags = 16, spell = 27810,
      body = "Marks a spot on the ground that erupts after a few seconds for massive Shadow damage; move off the marked tile before it goes off." },
    { title = "Detonate Mana", flags = 128, spell = 27819,
      body = "Destabilizes a caster's mana pool so it explodes after several seconds, dealing Arcane damage to everyone nearby based on how much mana they had banked." },
    { title = "Chains of Kel'Thuzad", flags = 32, spell = 28410,
      body = "Enslaves several random players, sharply boosting their damage and turning them against their own raid — crowd control or careful damage is needed to handle the charmed players without killing them." },
  },

  ------------------------------------------------------------------------------------------------
  -- Obsidian Sanctum (instance 90015)
  ------------------------------------------------------------------------------------------------
  [9001501] = { -- Sartharion
    { title = "Flame Tsunami", flags = 16, spell = 57491,
      body = "A wall of fire sweeps across the entire platform, dealing massive Fire damage to anyone it reaches — the raid must move to the safe half of the room in time." },
    { title = "Cleave", flags = 1, spell = 56909,
      body = "Strikes his current target and the nearest allies for boosted melee damage in a frontal cone." },
    { title = "Tail Lash", flags = 16, spell = 56910,
      body = "Swings his tail at anyone standing behind him, dealing Physical damage and stunning them — melee must stay to his sides." },
    { title = "Drake Allies", flags = 32, spell = 0,
      body = "Leaving one or more of Tenebron, Shadron, or Vesperon alive for the fight adds their own auras and breath attacks on top of Sartharion's, sharply raising the difficulty in exchange for better loot." },
  },

  ------------------------------------------------------------------------------------------------
  -- The Eye of Eternity (instance 90016)
  ------------------------------------------------------------------------------------------------
  [9001601] = { -- Malygos
    { title = "Arcane Storm", flags = 16, spell = 56172,
      body = "Fires a flurry of arcane missiles at random targets, dealing heavy Arcane damage to each one hit." },
    { title = "Vortex", flags = 16, spell = 56105,
      body = "Pulls the entire raid into the air and spins them, dealing Arcane damage every second for the duration — there's little to do but ride it out." },
    { title = "Power Spark", flags = 32, spell = 56152,
      body = "A glowing orb of energy drifts toward Malygos; if it reaches him his damage output increases substantially, so it should be intercepted and destroyed first." },
    { title = "Surge of Power", flags = 16, spell = 56505,
      body = "Sweeps a beam of concentrated arcane energy across the platform during the drake-combat phase — stay out of the beam's path while flying." },
  },

  ------------------------------------------------------------------------------------------------
  -- Ulduar (instance 90017)
  ------------------------------------------------------------------------------------------------
  [9001701] = { -- Flame Leviathan
    { title = "Flame Vents", flags = 16, spell = 62396,
      body = "Channels jets of fire from its side turrets, dealing heavy Fire damage per second to everyone within a wide radius." },
    { title = "Battering Ram", flags = 16, spell = 62376,
      body = "Charges forward and slams into a vehicle for greatly increased damage, knocking it back — evasive driving matters more than tanking the hit." },
    { title = "Systems Overload", flags = 32, spell = 62475,
      body = "Forces a temporary shutdown that increases damage taken by the Leviathan by half while disabling its attacks — the burn window vehicle turrets should focus." },
  },

  [9001702] = { -- Razorscale
    { title = "Devouring Flame", flags = 16, spell = 62796,
      body = "Spits a fireball that leaves a spreading sea of blue fire on the ground, dealing heavy Fire damage per second to anyone standing in it." },
    { title = "Flame Buffet", flags = 16, spell = 64016,
      body = "Stacks Fire damage taken on the current target with each application — the tank should be swapped before the stacks climb too high." },
    { title = "Harpoon Phase", flags = 32, spell = 0,
      body = "Before she can be fought on the ground, Razorscale must be harpooned out of the sky repeatedly while her adds are managed — skipping this phase isn't an option." },
  },

  [9001703] = { -- Ignis the Furnace Master
    { title = "Flame Jets", flags = 16, spell = 62680,
      body = "Erupts the ground in flame, interrupting spellcasting and dealing Fire damage over time to everyone nearby." },
    { title = "Slag Pot", flags = 16, spell = 62717,
      body = "Grabs a random player and dunks them in the molten furnace pot, dealing heavy Fire damage every second until they're freed." },
    { title = "Scorch", flags = 16, spell = 62686,
      body = "Blasts a trail of fire along the ground in front of him that deals damage over time to anyone standing in it." },
  },

  [9001704] = { -- XT-002 Deconstructor
    { title = "Tympanic Tantrum", flags = 16, spell = 62776,
      body = "Channels a room-wide sound wave that deals a percentage of everyone's maximum health as Physical damage every second and dazes them for the duration." },
    { title = "Searing Light", flags = 128, spell = 63018,
      body = "Burns a random player with holy energy, dealing heavy Holy damage and causing them to burn nearby allies — spread away from the group when marked." },
    { title = "Gravity Bomb", flags = 16, spell = 63024,
      body = "Traps a player in a gravitational field that explodes after several seconds, pulling in and damaging anyone nearby — move away from the raid before it detonates." },
  },

  [9001705] = { -- Assembly of Iron
    { title = "Fusion Punch", flags = 1, spell = 61903,
      body = "A heavy melee strike on the tank followed by a lingering Nature damage tick — cooldowns help smooth out the burst." },
    { title = "Rune of Power", flags = 32, spell = 61974,
      body = "Drops a rune zone on the ground that boosts the damage of anyone standing inside it, boss or player — the raid can use this deliberately during burn phases." },
    { title = "Static Overload", flags = 128, spell = 61909,
      body = "Charges a random player with electricity that pulses outward, damaging nearby allies — spread out when marked." },
  },

  [9001706] = { -- Kologarn
    { title = "Stone Grip", flags = 16, spell = 62166,
      body = "Squeezes a player in his massive stone fist, dealing damage every second until the arm takes enough damage to force a release — focus the grabbing arm down quickly." },
    { title = "Focused Eyebeams", flags = 16, spell = 63346,
      body = "Tracks a target with twin laser beams from his eyes, dealing heavy Fire damage per second to anyone caught in the beam's path." },
    { title = "Overhead Smash", flags = 1, spell = 62019,
      body = "A heavy overhead slam on the tank that also reduces their armor with each stack, making later hits progressively worse." },
  },

  [9001707] = { -- Algalon the Observer
    { title = "Quantum Strike", flags = 1, spell = 64412,
      body = "A precise strike on the tank that partially bypasses armor for high Physical damage." },
    { title = "Cosmic Smash", flags = 16, spell = 62311,
      body = "Calls down a cosmic sphere at a location, dealing heavy Fire damage to anyone near the impact and tapering off with distance — step away from the marked spot." },
    { title = "Big Bang", flags = 16, spell = 64584,
      body = "An arena-wide cosmic explosion that deals catastrophic Physical damage to everyone — the raid must take shelter inside a Shadow Crevice to survive it." },
  },

  [9001708] = { -- Auriaya
    { title = "Sonic Screech", flags = 16, spell = 64688,
      body = "A piercing frontal blast that splits heavy Physical damage among everyone it hits — avoid standing in front of her." },
    { title = "Terrifying Screech", flags = 16, spell = 64386,
      body = "A horrific roar that sends every nearby player fleeing in terror for several seconds." },
    { title = "Feral Defender", flags = 32, spell = 64447,
      body = "Summons a Feral Defender that channels a beam linking it to Auriaya, healing her while active — the beam must be broken or the defender killed to stop the drain." },
  },

  [9001709] = { -- Hodir
    { title = "Biting Cold", flags = 16, spell = 62038,
      body = "A stacking frost debuff that builds the longer a player stands still — keep moving to avoid the damage climbing out of control." },
    { title = "Flash Freeze", flags = 16, spell = 61968,
      body = "Encases every exposed player and NPC in blocks of ice; sheltering in one of the room's warming snowdrifts blocks the effect entirely." },
    { title = "Frozen Blows", flags = 16, spell = 62478,
      body = "Infuses Hodir's weapon with frost, trading some physical damage for a large Frost damage component on every swing." },
  },

  [9001710] = { -- Thorim
    { title = "Chain Lightning", flags = 128, spell = 64363,
      body = "Strikes a target with lightning that arcs on to several nearby allies for Nature damage." },
    { title = "Lightning Charge", flags = 16, spell = 62466,
      body = "Draws a beam of electricity from the arena's pillars, damaging anyone in the beam's path and empowering Thorim's attack power." },
    { title = "Unbalancing Strike", flags = 1, spell = 62130,
      body = "A heavy strike on the tank that also cuts their defense skill for several seconds, making follow-up attacks hit harder." },
  },

  [9001711] = { -- Freya
    { title = "Sunbeam", flags = 16, spell = 62623,
      body = "Drops a pillar of light on a random target, dealing Nature damage and silencing anyone caught within it — step out of the beam quickly." },
    { title = "Bright Waves", flags = 4, spell = 62626,
      body = "Sends a wave of nature magic across the room that heals Freya's allied Elders or damages the raid depending on the fight's setup." },
    { title = "Touch of Eonar", flags = 4, spell = 62528,
      body = "Channels a large heal on Freya from a Lifebinder's Gift totem — interrupting or killing the source quickly denies the healing." },
    { title = "Attuned Elders", flags = 32, spell = 0,
      body = "Choosing to fight Freya's three Elder Nature Guardians alongside her (Ironbranch, Brightleaf, Stonebark) adds their own auras — more Elders means a longer, harder, but more rewarding fight." },
  },

  [9001712] = { -- Mimiron
    { title = "Proximity Mines", flags = 16, spell = 63297,
      body = "Scatters mines across the floor that detonate for Fire damage when stepped on or walked near — watch your footing during his mobile phases." },
    { title = "Plasma Blast", flags = 16, spell = 62997,
      body = "Channels a beam of plasma at the tank, dealing heavy Fire damage per second for several seconds." },
    { title = "Laser Barrage", flags = 16, spell = 63274,
      body = "A rapid spinning laser sweep that deals heavy damage per second to anyone caught directly in its frontal path." },
    { title = "Shock Blast", flags = 16, spell = 63631,
      body = "After a visible cast, deals massive Nature damage to everyone within range — this phase punishes staying too close to the boss's platform." },
  },

  [9001713] = { -- General Vezax
    { title = "Aura of Despair", flags = 128, spell = 62692,
      body = "Shuts off all passive and spell-based mana regeneration in the room while boosting his own physical attack speed — mana management becomes the core of the fight." },
    { title = "Shadow Crash", flags = 16, spell = 62660,
      body = "Fires a missile of dark energy at a location, leaving behind a pool that reduces spell costs and speeds up casting — standing in it deliberately can help mana-starved casters." },
    { title = "Searing Flames", flags = 64, spell = 62661,
      body = "A channeled blast of Fire damage that also strips armor from everyone nearby unless interrupted." },
    { title = "Mark of the Faceless", flags = 512, spell = 63276,
      body = "Siphons health from a random player and heals Vezax from nearby Saronite Vapors — killing the vapors before he can drain them limits the healing." },
  },

  [9001714] = { -- Yogg-Saron
    { title = "Brain Link", flags = 128, spell = 63802,
      body = "Links two players with a psychic beam; if they drift more than 20 yards apart they both take heavy Shadow damage and lose Sanity — stay paired up close together." },
    { title = "Malady of the Mind", flags = 256, spell = 63830,
      body = "A psychic curse that deals Shadow damage and briefly stuns the target in horror before jumping to another nearby ally." },
    { title = "Psychosis", flags = 128, spell = 65301,
      body = "Blasts a target's mind with Shadow damage and drains a chunk of their Sanity — low Sanity eventually causes hallucinations and loss of control." },
    { title = "Lunatic Gaze", flags = 16, spell = 64163,
      body = "A dark visual wave from Yogg-Saron himself — looking directly at him during the cast deals Shadow damage and rapidly drains Sanity, so face away." },
  },

  ------------------------------------------------------------------------------------------------
  -- Trial of the Champion (instance 90018)
  ------------------------------------------------------------------------------------------------
  [9001801] = { -- The Grand Champions
    { title = "Champion's Charge", flags = 16, spell = 0,
      body = "The mounted champions periodically charge across the arena; watch for the telegraphed run and step out of the lane." },
    { title = "Paired Class Abilities", flags = 32, spell = 0,
      body = "Each of the three Grand Champions fights with a full class kit (warrior, hunter, and a caster or healer among them) — focusing them down one at a time while controlling their pet or interrupting their casts prevents the fight from spiraling." },
  },

  [9001802] = { -- Argent Confessor Paletress
    { title = "Smite", flags = 128, spell = 66536,
      body = "A bolt of Holy damage flung at a random player — nothing exotic, just steady ranged pressure." },
    { title = "Summon Memory", flags = 32, spell = 66708,
      body = "Paletress calls up a Memory of a past champion to fight alongside her; killing the Memory quickly prevents it from overwhelming the raid with its own attacks." },
  },

  [9001803] = { -- Eadric the Pure
    { title = "Hammer of Justice", flags = 16, spell = 66940,
      body = "Stuns his current target briefly with a righteous hammer blow." },
    { title = "Sacred Cleansing", flags = 4, spell = 0,
      body = "Eadric periodically heals himself and removes his own harmful effects with a burst of holy light — timing damage to avoid wasting burst right before this heal helps." },
  },

  [9001804] = { -- The Black Knight
    { title = "Plague Strike", flags = 1024, spell = 67724,
      body = "Infects the target with a stacking disease on top of a solid Physical hit." },
    { title = "Army of the Dead", flags = 32, spell = 67751,
      body = "Raises a swarm of ghouls from the arena floor in his final phase; the raid needs to control or cleave down the army while still damaging the Knight himself." },
    { title = "Unholy Power", flags = 2048, spell = 67749,
      body = "Empowers his own attacks with unholy fury, increasing the Physical damage of his subsequent strikes." },
  },

  ------------------------------------------------------------------------------------------------
  -- Trial of the Crusader (instance 90019)
  ------------------------------------------------------------------------------------------------
  [9001901] = { -- Northrend Beasts
    { title = "Impale (Gormok)", flags = 8192, spell = 66331,
      body = "Gormok the Impaler drives his spear into the target for heavy Physical damage and a stacking bleed that lasts half a minute." },
    { title = "Massive Crash (Icehowl)", flags = 16, spell = 66683,
      body = "Icehowl leaps into the arena's center and crashes down, knocking back and stunning everyone nearby." },
    { title = "Trample (Icehowl)", flags = 16, spell = 66734,
      body = "Icehowl charges across the floor toward a marked player — anyone directly in his path takes a devastating hit, so clear the lane." },
  },

  [9001902] = { -- Lord Jaraxxus
    { title = "Fel Fireball", flags = 16, spell = 66228,
      body = "Hurls a corrupted fireball at the tank for a heavy instant hit followed by a lingering Fire damage-over-time." },
    { title = "Incinerate Flesh", flags = 4, spell = 66237,
      body = "Marks a player with a debuff that absorbs incoming healing; if they aren't healed past the absorb amount in time, it explodes for massive raid-wide Fire damage." },
    { title = "Legion Flame", flags = 16, spell = 66197,
      body = "Blasts a player with hellfire and leaves a trail of flame patches spreading from their location — move away from the raid while marked." },
  },

  [9001903] = { -- Faction Champions
    { title = "Rival Team Tactics", flags = 32, spell = 0,
      body = "A team of enemy-faction heroes fights with full class kits and no fixed threat table, dynamically targeting low-health or crowd-controlled players — focus fire, peel, and burst cooldowns matter more than tanking here." },
  },

  [9001904] = { -- Twin Val'kyr
    { title = "Twin Spikes", flags = 1, spell = 66075,
      body = "A coordinated strike from both sisters that raises the target's damage taken from the opposite magic school for a time." },
    { title = "Shield of Darkness", flags = 4, spell = 65874,
      body = "One twin shields herself with a massive damage absorb and channels a continuous heal — she must be attacked through the shield or the fight stalls." },
    { title = "Light Vortex (Fjola)", flags = 128, spell = 66058,
      body = "Fjola Lightbane channels a whirlwind of holy energy that damages everyone not carrying the matching Light Essence." },
    { title = "Dark Vortex (Eydis)", flags = 128, spell = 66046,
      body = "Eydis Darkbane channels a whirlwind of shadow energy that damages everyone not carrying the matching Dark Essence — swapping essences between casts is the core of the fight." },
  },

  [9001905] = { -- Anub'arak (Trial of the Crusader)
    { title = "Penetrating Cold", flags = 16, spell = 66013,
      body = "Pierces several random raid members with bone-deep cold, dealing repeating Frost damage over the debuff's duration." },
    { title = "Freezing Slash", flags = 16, spell = 66012,
      body = "Encases the tank in ice with a heavy strike, stunning them briefly and cutting their armor." },
    { title = "Leeching Swarm", flags = 512, spell = 66118,
      body = "Releases scarabs that drain a percentage of every raid member's current health each second, healing Anub'arak with every tick — this is a hard enrage-style burn phase, not something to stall through." },
    { title = "Impale", flags = 16, spell = 56090,
      body = "Drives spikes up through the ground beneath a player, dealing lethal Physical damage — standing on a frozen Permafrost patch blocks the spike from erupting." },
  },

  ------------------------------------------------------------------------------------------------
  -- Onyxia's Lair (instance 90020)
  ------------------------------------------------------------------------------------------------
  [9002001] = { -- Onyxia
    { title = "Deep Breath", flags = 16, spell = 0,
      body = "Flies to one end of the lair and exhales a scorching line of fire the length of the room, dealing devastating Fire damage to anyone caught in its path." },
    { title = "Flame Breath", flags = 16, spell = 0,
      body = "A frontal cone of fire while grounded — stay out of Onyxia's front arc, especially melee." },
    { title = "Wing Buffet", flags = 16, spell = 0,
      body = "Knocks back everyone standing behind her with a sweep of her wings; melee positioning matters throughout the ground phases." },
    { title = "Bellowing Roar", flags = 16, spell = 0,
      body = "Fears everyone in the room briefly — trinkets and fear breaks help keep the raid from scattering into other mechanics." },
    { title = "Whelp Phases", flags = 32, spell = 0,
      body = "Onyxia periodically takes to the air and rains fireballs down while spawning waves of whelps from the room's eggs; the whelps must be tanked and cleared until she lands again." },
  },

  ------------------------------------------------------------------------------------------------
  -- The Forge of Souls (instance 90021)
  ------------------------------------------------------------------------------------------------
  [9002101] = { -- Bronjahm
    { title = "Magic's Bane", flags = 128, spell = 68872,
      body = "Fires a bolt of soul energy at a random target, dealing Arcane damage and draining a portion of their mana." },
    { title = "Corrupt Soul", flags = 32, spell = 68839,
      body = "Rips a soul fragment out of a player, sending a corrupted soul drifting toward Bronjahm — intercept and kill it before it reaches him and heals him." },
    { title = "Soulstorm", flags = 16, spell = 68874,
      body = "Channels a violent vortex of souls that damages anyone outside the safe bubble near Bronjahm — stay close during the channel." },
  },

  [9002102] = { -- Devourer of Souls
    { title = "Phantom Blast", flags = 16, spell = 68939,
      body = "After a short cast, deals heavy Shadow damage to a random target." },
    { title = "Mirrored Soul", flags = 32, spell = 69051,
      body = "Links a player to the boss so that damage the boss takes is mirrored onto that player for several seconds — that player should hold off attacking or use a defensive cooldown." },
    { title = "Wailing Souls", flags = 16, spell = 68982,
      body = "A sweeping cone of wailing souls that deals heavy Shadow damage to anyone caught in front of the Devourer." },
  },

  ------------------------------------------------------------------------------------------------
  -- Pit of Saron (instance 90022)
  ------------------------------------------------------------------------------------------------
  [9002201] = { -- Forgemaster Garfrost
    { title = "Permafrost", flags = 16, spell = 70381,
      body = "Radiates a stacking cold aura that slows movement and attack speed the longer a player stays near him." },
    { title = "Forge Saronite Weapon", flags = 32, spell = 70383,
      body = "Retreats briefly to forge a superior weapon, sharply boosting his attack power and melee damage once he returns — a hint to save cooldowns for after this phase." },
  },

  [9002202] = { -- Ick and Krick
    { title = "Ick's Bloated Ooze", flags = 16, spell = 0,
      body = "When Ick dies (or after enough time), he detonates in a wave of ooze that damages nearby players; controlling the timing of his death matters more than raw burst." },
    { title = "Krick's Sonic Ring Blast", flags = 16, spell = 0,
      body = "Krick, riding on Ick's back, calls down rings of expanding sound that deal Physical damage to anyone standing on their edge — step through the gaps rather than the rings themselves." },
  },

  [9002203] = { -- Tyrannus (Scourgelord Tyrannus)
    { title = "Overlord's Brand", flags = 128, spell = 69172,
      body = "Brands a player so that Tyrannus (or his drake ally Rimefang) takes backlash damage whenever that player attacks or is healed — useful as a controlled damage source, not a debuff to avoid." },
    { title = "Forceful Smash", flags = 1, spell = 69155,
      body = "A brutal blow against the current tank for heavy Physical damage." },
    { title = "Rimefang's Assault", flags = 32, spell = 0,
      body = "In the fight's first phase, the drake Rimefang breathes frost across the room and must be survived while the raid whittles down his health before Tyrannus takes the field alone." },
  },

  ------------------------------------------------------------------------------------------------
  -- Halls of Reflection (instance 90023)
  ------------------------------------------------------------------------------------------------
  [9002301] = { -- Falric
    { title = "Quivering Strike", flags = 128, spell = 72340,
      body = "Strikes the tank with dark energy, reducing healing received and dealing Shadow damage." },
    { title = "Defiling Horror", flags = 16, spell = 72435,
      body = "Frightens everyone nearby with horrifying visions, causing them to flee — trinkets and fear breaks help keep positioning intact." },
  },

  [9002302] = { -- Marwyn
    { title = "Obliterate", flags = 1, spell = 72363,
      body = "A crushing blow against the tank for heavy Physical damage." },
    { title = "Corrupted Flesh", flags = 1024, spell = 72362,
      body = "Infects a target with corrupted flesh, reducing their maximum health and the healing they receive — a growing problem the longer the fight runs." },
  },

  [9002303] = { -- The Lich King (Escape from the Lich King)
    { title = "Remorseless Winter", flags = 16, spell = 72726,
      body = "The Lich King channels an icy vortex down the corridor that instantly freezes and kills anyone it catches — this is a scripted chase, and the raid must simply keep running ahead of it to the finish." },
  },

  ------------------------------------------------------------------------------------------------
  -- Icecrown Citadel (instance 90024)
  ------------------------------------------------------------------------------------------------
  [9002401] = { -- Lord Marrowgar
    { title = "Bone Slice", flags = 1, spell = 69055,
      body = "Strikes the tank and up to two nearby players for heavy Physical damage in a frontal cone." },
    { title = "Coldflame", flags = 16, spell = 69146,
      body = "Fires a line of blue fire toward a random player that leaves a damaging trail on the ground — walk it away from the raid rather than through it." },
    { title = "Bone Spike Graveyard", flags = 16, spell = 69057,
      body = "Impales random players on bone spikes, stunning them and dealing damage over time until the spike is destroyed — free the impaled players quickly." },
    { title = "Bone Storm", flags = 16, spell = 69076,
      body = "Spins in a hurricane of bone fragments for half a minute, chasing and damaging anyone in range — keep moving and away from melee during it." },
  },

  [9002402] = { -- Lady Deathwhisper
    { title = "Mana Barrier", flags = 128, spell = 70842,
      body = "In phase one she's shielded by a mana-based barrier instead of health and immune to physical damage — casters carry this phase while melee help clear adds." },
    { title = "Death and Decay", flags = 16, spell = 71001,
      body = "Corrupts a targeted area of ground, dealing Shadow damage every second to anyone standing inside — move out immediately." },
    { title = "Shadow Bolt Volley", flags = 128, spell = 71002,
      body = "Hurls dark bolts at several targets at once for Shadow damage." },
    { title = "Dominate Mind", flags = 32, spell = 71289,
      body = "Mind-controls several random players to fight for the Cult of the Damned — crowd control or careful damage keeps them from doing too much harm before it wears off." },
  },

  [9002403] = { -- The Gunship Battle
    { title = "Below Zero", flags = 16, spell = 69705,
      body = "Freezes the deck's machinery and slows nearby players' attack and casting speed — a reason to spread out on the ship's deck." },
    { title = "Burning Pitch", flags = 16, spell = 69709,
      body = "Hurls burning pitch onto the enemy ship's deck, leaving patches that burn anyone who lingers near them." },
    { title = "Boarding Phase", flags = 32, spell = 0,
      body = "Once the ships close, enemy officers and mages teleport aboard and must be killed quickly — leaving them alive lets them wreak havoc on the deck crew." },
  },

  [9002404] = { -- Deathbringer Saurfang
    { title = "Boiling Blood", flags = 16, spell = 72241,
      body = "Deals Shadow damage over time to a random player and heals Saurfang for the full amount dealt — a reason to keep his health pressured rather than let this tick freely." },
    { title = "Mark of the Fallen Champion", flags = 256, spell = 72293,
      body = "Curses a player so that whenever Saurfang's Blood Beasts deal damage or he gains Blood Power, the marked player takes a percentage of their max health as true damage — the mark should be dispelled or managed carefully." },
    { title = "Blood Beasts", flags = 32, spell = 72173,
      body = "At high Blood Power, Saurfang summons Blood Beasts that must be tanked and killed quickly before their bleeding attacks stack out of control." },
  },

  [9002405] = { -- Festergut
    { title = "Gaseous Blight", flags = 1024, spell = 72193,
      body = "Fills the room with a noxious blight that deals Shadow damage every few seconds, stacking up as the fight progresses." },
    { title = "Gas Spore", flags = 32, spell = 69279,
      body = "Inoculates a random player with a volatile spore that explodes after several seconds, damaging nearby allies but granting the target resistance to future Blight stacks — that player should move away from the raid before it pops." },
    { title = "Vile Gas", flags = 16, spell = 71218,
      body = "Sprays a foul gas on a random player, forcing them to vomit and move away from the group for several seconds." },
    { title = "Pungent Blight", flags = 16, spell = 71219,
      body = "Consumes all of Festergut's built-up Blight stacks to unleash a massive room-wide burst of Nature damage — this typically defines the enrage timer for the fight." },
  },

  [9002406] = { -- Rotface
    { title = "Slime Spray", flags = 16, spell = 69508,
      body = "Sprays a cone of toxic slime in front of him and spawns a Fallout Slime — face him away from the raid." },
    { title = "Mutated Infection", flags = 1024, spell = 69674,
      body = "Injects a toxic ooze into a player that ticks Shadow damage and, when it expires, spawns a small ooze that must be kited into the larger oozes to merge and pop them." },
    { title = "Unstable Ooze Explosion", flags = 16, spell = 69839,
      body = "A large merged ooze explodes violently for heavy Nature damage to anyone within range and spawns more small oozes — pop these away from the raid." },
  },

  [9002407] = { -- Professor Putricide
    { title = "Slime Puddle", flags = 16, spell = 70341,
      body = "Drops a pool of slime beneath a target that slows movement and deals Nature damage over time — step out of the puddle." },
    { title = "Choking Gas Bomb", flags = 64, spell = 71255,
      body = "Hurls gas bombs around the room; stepping near one releases a cloud that silences and causes attacks to miss for anyone caught inside." },
    { title = "Malleable Goo", flags = 16, spell = 72295,
      body = "Hurls a glob of slime at a location, damaging anyone nearby and slowing their attack and casting speed heavily." },
    { title = "Phase Transformations", flags = 32, spell = 0,
      body = "Putricide periodically drinks experimental mutagens that reshape the fight's mechanics for a time (Gas, Ooze, or a blend of both) — the raid needs to adapt to whichever phase is active." },
  },

  [9002408] = { -- Blood Prince Council
    { title = "Kinetic Bomb", flags = 16, spell = 72053,
      body = "Summons a slow floating orb toward a random player; if it reaches the ground it explodes for damage scaled to how high it was when it landed — intercept and pop it early." },
    { title = "Glittering Sparks", flags = 64, spell = 71396,
      body = "The active Prince emits dazzling sparks that deal Fire damage and interrupt spellcasting for anyone standing too close." },
    { title = "Shadow Resonance", flags = 128, spell = 71822,
      body = "Empowers the currently active Prince, boosting their damage output — the raid rotates which Prince is targeted as this stacks up, to keep from over-committing to one." },
  },

  [9002409] = { -- Blood-Queen Lana'thel
    { title = "Shroud of Sorrow", flags = 128, spell = 70986,
      body = "A constant aura of despair that deals Shadow damage to the whole raid every few seconds for the entire fight — sustained raid healing is required throughout." },
    { title = "Essence of the Blood-Queen", flags = 512, spell = 70879,
      body = "Infects a player with vampiric essence, doubling their damage and letting them heal from it — but they must bite another player before the buff expires or take a severe penalty; managing the bite chain carefully avoids an uncontrolled vampire outbreak." },
    { title = "Swarming Shadows", flags = 16, spell = 71264,
      body = "The targeted player leaves trails of dark shadow fire behind them as they move — walk this trail away from the raid." },
  },

  [9002410] = { -- Valithria Dreamwalker
    { title = "Dream Portals", flags = 4, spell = 71305,
      body = "Green portals to the Nightmare occasionally open; stepping through and collecting Emerald Vigor sharply boosts a healer's output for the rest of the encounter — this is a healing-check fight built around keeping Valithria's health climbing." },
    { title = "Suppressor Aura", flags = 4, spell = 71743,
      body = "Nightmare invaders reduce all healing Valithria receives while alive — killing the adds (especially the Suppressers) as they spawn is as important as the direct healing." },
  },

  [9002411] = { -- Sindragosa
    { title = "Frost Aura", flags = 16, spell = 70084,
      body = "A constant frost pulse that damages everyone in the room regardless of position." },
    { title = "Permeating Chill", flags = 128, spell = 70109,
      body = "Every spell a player casts stacks a chilling debuff that deals Frost damage when it expires — casters should be mindful of how many stacks they're carrying." },
    { title = "Unchained Magic", flags = 128, spell = 70134,
      body = "Builds instability the more a player casts spells, eventually triggering a backlash explosion — another reason for casters to pace their output." },
    { title = "Blistering Cold", flags = 16, spell = 70123,
      body = "Channels an absolute-zero shockwave that deals massive Frost damage to anyone within range; breaking line of sight behind an Ice Tomb is the only way to survive it." },
    { title = "Icy Grip / Frost Beacon", flags = 16, spell = 70117,
      body = "Pulls the raid to the platform's center and marks random players with frost beacons that encase them in Ice Tombs shortly after — these Tombs double as the only shelter from Blistering Cold." },
  },

  [9002412] = { -- The Lich King
    { title = "Infest", flags = 1024, spell = 70541,
      body = "Infests a target with ghoulish parasites that deal Shadow damage over time, worsening if the target's health drops too low — healing above the threshold matters." },
    { title = "Necrotic Plague", flags = 1024, spell = 70337,
      body = "A terminal plague that deals Shadow damage every few seconds and jumps to the nearest player when it expires or is dispelled, growing the Lich King's power each time it spreads — passing it around deliberately is part of managing the fight." },
    { title = "Remorseless Winter", flags = 16, spell = 68981,
      body = "Channels an icy vortex around the platform's edge that instantly kills anyone who steps outside the safe inner circle." },
    { title = "Defile", flags = 16, spell = 72762,
      body = "Grows a corrupted pool beneath a player's feet that expands and deals more damage the longer it persists — move it to an unused corner of the platform immediately." },
    { title = "Soul Reaper", flags = 1, spell = 69409,
      body = "A heavy strike on the tank that leaves a shadow debuff dealing massive damage after five seconds unless mitigated with a defensive cooldown — tank swaps are typically timed around this." },
    { title = "Raging Spirits", flags = 32, spell = 69200,
      body = "Summons spectral warriors that chase random players and must be controlled or killed before their attacks add up on top of everything else happening on the platform." },
  },

  ------------------------------------------------------------------------------------------------
  -- Ruby Sanctum (instance 90025)
  ------------------------------------------------------------------------------------------------
  [9002501] = { -- Halion
    { title = "Flame Tsunami", flags = 16, spell = 74711,
      body = "A wall of dark fire sweeps across the platform in the physical realm, dealing heavy Fire damage to anyone caught in its path." },
    { title = "Meteor Strike", flags = 16, spell = 74648,
      body = "Marks a location that erupts into a massive meteor after several seconds, splitting heavy Fire damage among nearby players and spawning fire elementals." },
    { title = "Fiery Combustion", flags = 16, spell = 74562,
      body = "A stacking Fire damage-over-time on a target and everyone within 10 yards that leaves a burning pool on the ground when it ends or is dispelled." },
    { title = "Soul Consumption", flags = 512, spell = 74792,
      body = "The Twilight Realm counterpart to Fiery Combustion — a stacking Shadow damage-over-time that leaves a lingering void pool behind when it expires." },
    { title = "Twilight Cutter", flags = 16, spell = 74769,
      body = "Four rotating shadow orbs sweep razor-sharp beams of twilight energy across the Twilight Realm platform — touching one is lethal, so track their rotation and stay clear." },
  },

}

NE.ej.ABIL_WOTLK = ABIL

-- Merge the seeded WotLK abilities into NE.ej.DATA, identical logic to AbilitiesTBC.lua's
-- applyAbilities(): fills only bosses that have no sections yet, runs after DataWotLK.lua has
-- appended the tier=3 instances so every encounter above is present to match.
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
