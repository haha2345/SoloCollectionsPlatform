"""Generate modules/cooldownviewer/CdmSeedWotLK.lua.

Curation (which ability belongs in Essential vs Utility) is authored here BY NAME.
Every spell ID is then resolved from the client's own Spell.dbc + SkillLineAbility.dbc
(resolved.json, built by resolve.py) -- never typed by hand. A name that fails to
resolve is a hard error, so the file can't silently ship a wrong id.

Essential = offensive burst / damage / throughput cooldowns.
Utility    = defensives, interrupts, CC, escapes, dispels, raid cooldowns.
"""
import json, re, sys

resolved = json.load(open("resolved.json", encoding="utf-8"))
resolved_any = json.load(open("resolved_any.json", encoding="utf-8"))

ESSENTIAL = {
 "WARRIOR": ["Bladestorm", "Shattering Throw", "Sweeping Strikes", "Heroic Throw",
             "Shield Slam", "Overpower", "Revenge"],
 "PALADIN": ["Divine Storm", "Hammer of the Righteous", "Shield of Righteousness",
             "Avenger's Shield", "Holy Wrath", "Divine Favor", "Divine Illumination",
             "Crusader Strike"],
 "HUNTER":  ["Explosive Shot", "Chimera Shot", "Kill Shot", "Black Arrow", "Silencing Shot"],
 "ROGUE":   ["Killing Spree", "Shadow Dance", "Ghostly Strike", "Tricks of the Trade"],
 "PRIEST":  ["Penance", "Holy Fire", "Circle of Healing", "Prayer of Mending",
             "Divine Hymn", "Hymn of Hope"],
 "MAGE":    ["Deep Freeze", "Mirror Image", "Icy Veins", "Arcane Barrage", "Blast Wave",
             "Summon Water Elemental"],
 "WARLOCK": ["Metamorphosis", "Haunt", "Chaos Bolt", "Shadowflame", "Demonic Empowerment"],
 "DRUID":   ["Starfall", "Berserk", "Typhoon", "Wild Growth", "Swiftmend"],
 "SHAMAN":  ["Feral Spirit", "Thunderstorm", "Lava Burst", "Lava Lash", "Riptide", "Heroism",
             "Flame Shock"],
 "DEATHKNIGHT": ["Army of the Dead", "Summon Gargoyle", "Dancing Rune Weapon",
                 "Empower Rune Weapon", "Howling Blast", "Death and Decay", "Blood Tap",
                 "Raise Dead", "Horn of Winter"],
}

UTILITY = {
 "WARRIOR": ["Shockwave", "Enraged Regeneration", "Heroic Fury", "Disarm", "Concussion Blow",
             "Challenging Shout", "Retaliation"],
 "PALADIN": ["Divine Sacrifice", "Hand of Sacrifice", "Hand of Salvation", "Aura Mastery",
             "Divine Plea", "Repentance", "Holy Shield", "Righteous Defense"],
 "HUNTER":  ["Master's Call", "Wyvern Sting", "Freezing Arrow", "Explosive Trap", "Frost Trap",
             "Flare", "Intimidation"],
 "ROGUE":   ["Dismantle", "Feint", "Distract", "Shadowstep", "Cloak of Shadows"],
 "PRIEST":  ["Dispersion", "Pain Suppression", "Guardian Spirit", "Psychic Horror"],
 # Ice Block was in NO list: ClassData carried Cold Snap's id under Ice Block's name, and Icy Veins'
 # under Cold Snap's. Both labels were wrong and the ability itself was simply absent.
 "MAGE":    ["Frost Ward", "Fire Ward", "Cold Snap", "Dragon's Breath", "Ice Block"],
 "WARLOCK": ["Demonic Circle: Teleport", "Soulshatter", "Fel Domination", "Shadow Ward"],
 "DRUID":   ["Survival Instincts", "Barkskin", "Frenzied Regeneration", "Nature's Grasp",
             "Feral Charge - Bear", "Feral Charge - Cat", "Maim", "Bash", "Rebirth",
             "Innervate", "Dash"],
 "SHAMAN":  ["Hex", "Wind Shear", "Grounding Totem", "Earthbind Totem", "Stoneclaw Totem",
             "Nature's Swiftness"],
 "DEATHKNIGHT": ["Icebound Fortitude", "Anti-Magic Shell", "Anti-Magic Zone", "Death Grip",
                 "Mind Freeze", "Strangulate", "Death Pact", "Rune Tap", "Vampiric Blood",
                 "Bone Shield", "Unbreakable Armor", "Lichborne", "Hungering Cold",
                 "Dark Command", "Raise Ally"],
}

# ── Rotation ────────────────────────────────────────────────────────────────────────────────────
#
# The spells a spec presses constantly. None of them has a cooldown, which is precisely why none of
# them was here: resolve.py's castability filter is `cooldown > 1.5s`, so every one of these resolved
# to nothing and was rejected as an unresolvable name. Reported as "lots of classes are missing
# default abilities that dont have cooldowns, such as druids with wrath".
#
# Curated from `listing_nocd.txt` — the client's own list of each class's no-cooldown, non-passive,
# non-talent skill-line abilities (explore_nocd.py) — not from memory. What is IN: the builders,
# spenders, fillers and maintained DoTs/HoTs a spec actually rotates through, plus the ones that read
# as rotation because you watch their timer (Serpent Sting, Slice and Dice, Savage Roar). What is OUT:
# buffs you set and forget (Mark of the Wild, Arcane Intellect, aspects, presences, armors, seals),
# shapeshift forms, pet management, tracking, conjures, rez and out-of-combat healing.
#
# PER CLASS, NOT PER SPEC, because that is the only thing the curated tables can express — the runtime
# gate is "has the player learned it" plus the talent gate, and every druid has learned Wrath. So this
# is the UNION across a class's specs, and the per-spec layouts (F2) are where a player prunes it to
# their own. That is also why the count per class runs to a dozen: a Feral druid seeing Balance's
# nukes in the picker is the cost of a Balance druid finding them there at all.
ROTATION = {
 # Absent on purpose, every one of them found by the two guards below rather than by inspection:
 # Revenge, Explosive Shot, Lava Burst and Riptide carry cooldowns and are curated above; Holy Shock,
 # Judgement of Light, Arcane Shot, Multi-Shot, Aimed Shot, Devouring Plague, Power Word: Shield,
 # Chain Lightning, Earth Shock and Stormstrike are already in ClassData.lua's vanilla base. Crusader
 # Strike (4s) and Flame Shock (6s) turned out to carry cooldowns too and moved UP into Essential —
 # verify.py refuses a rotation entry that has one, which is the check working in the other direction.
 "WARRIOR": ["Heroic Strike", "Cleave", "Slam", "Execute", "Rend", "Sunder Armor", "Devastate",
             "Victory Rush", "Hamstring"],
 "PALADIN": ["Holy Light", "Flash of Light", "Judgement of Wisdom", "Seal of Vengeance",
             "Seal of Righteousness", "Seal of Command"],
 "HUNTER":  ["Steady Shot", "Serpent Sting", "Volley", "Hunter's Mark"],
 "ROGUE":   ["Sinister Strike", "Backstab", "Mutilate", "Hemorrhage", "Eviscerate", "Envenom",
             "Rupture", "Slice and Dice", "Expose Armor", "Fan of Knives"],
 "PRIEST":  ["Smite", "Shadow Word: Pain", "Mind Flay", "Vampiric Touch", "Mind Sear",
             "Flash Heal", "Greater Heal", "Renew", "Prayer of Healing"],
 "MAGE":    ["Fireball", "Frostbolt", "Arcane Blast", "Arcane Missiles", "Scorch", "Living Bomb",
             "Ice Lance", "Frostfire Bolt", "Pyroblast", "Arcane Explosion", "Blizzard",
             "Flamestrike"],
 "WARLOCK": ["Shadow Bolt", "Incinerate", "Immolate", "Corruption", "Curse of Agony",
             "Unstable Affliction", "Seed of Corruption", "Drain Soul", "Drain Life", "Life Tap",
             "Rain of Fire"],
 "DRUID":   ["Wrath", "Starfire", "Moonfire", "Insect Swarm", "Shred", "Mangle (Cat)", "Rake", "Rip",
             "Ferocious Bite", "Savage Roar", "Maul", "Lacerate", "Swipe (Bear)", "Healing Touch",
             "Nourish", "Rejuvenation", "Regrowth", "Lifebloom"],
 "SHAMAN":  ["Lightning Bolt", "Healing Wave", "Lesser Healing Wave", "Chain Heal",
             "Earth Shield", "Searing Totem", "Magma Totem"],
 "DEATHKNIGHT": ["Icy Touch", "Plague Strike", "Blood Strike", "Heart Strike", "Death Strike",
                 "Obliterate", "Scourge Strike", "Frost Strike", "Rune Strike", "Death Coil",
                 "Blood Boil", "Pestilence"],
}

# ── Starter layouts, per spec ───────────────────────────────────────────────────────────────────
#
# The rotation pass above is a UNION across each class's specs — that is all the curated tables can
# express, since the runtime gate is "have you learned it" and every druid has learned Wrath. It leaves
# a Feral druid looking at Balance's nukes. A starter layout is the answer: the same class list, with
# everything off-spec moved to Not Displayed rather than deleted, so it is all still one drag away.
#
# ESSENTIAL ONLY. Utility is defensives, interrupts and escapes — 8-15 entries a character of any spec
# might press — and pruning it per spec would be churn for no gain. Essential is where the bloat landed
# (27 entries for a druid), and Essential is what this trims.
#
# Keyed by TALENT TAB INDEX, which is what GetTalentTabInfo answers and what the runtime detects. Tab
# order comes from TalentTab.dbc (orderIndex within each class's ClassMask), not from memory:
#
#   WARRIOR  1 Arms          2 Fury          3 Protection
#   PALADIN  1 Holy          2 Protection    3 Retribution
#   HUNTER   1 Beast Mastery 2 Marksmanship  3 Survival
#   ROGUE    1 Assassination 2 Combat        3 Subtlety
#   PRIEST   1 Discipline    2 Holy          3 Shadow
#   DK       1 Blood         2 Frost         3 Unholy
#   SHAMAN   1 Elemental     2 Enhancement   3 Restoration
#   MAGE     1 Arcane        2 Fire          3 Frost
#   WARLOCK  1 Affliction    2 Demonology    3 Destruction
#   DRUID    1 Balance       2 Feral Combat  3 Restoration
#
# Every name is checked against that class's own merged Essential list below; one that is not in it is
# a hard error, because a starter that enables a spell the picker never offers enables nothing.
STARTER = {
 "WARRIOR": {
  1: ["Mortal Strike", "Overpower", "Slam", "Execute", "Rend", "Bladestorm", "Sweeping Strikes",
      "Heroic Strike", "Shattering Throw", "Bloodrage"],
  2: ["Bloodthirst", "Heroic Strike", "Cleave", "Execute", "Slam", "Death Wish", "Recklessness",
      "Victory Rush", "Bloodrage"],
  3: ["Shield Slam", "Revenge", "Devastate", "Heroic Strike", "Cleave", "Sunder Armor",
      "Heroic Throw", "Victory Rush", "Bloodrage"],
 },
 "PALADIN": {
  1: ["Holy Light", "Flash of Light", "Holy Shock", "Divine Favor", "Divine Illumination",
      "Judgement of Light", "Judgement of Wisdom", "Consecration", "Exorcism"],
  2: ["Avenger's Shield", "Hammer of the Righteous", "Shield of Righteousness", "Consecration",
      "Holy Wrath", "Judgement of Light", "Judgement of Wisdom", "Exorcism", "Hammer of Wrath"],
  3: ["Crusader Strike", "Divine Storm", "Judgement of Wisdom", "Judgement of Light", "Consecration",
      "Exorcism", "Hammer of Wrath", "Seal of Command", "Seal of Vengeance", "Seal of Righteousness"],
 },
 "HUNTER": {
  1: ["Steady Shot", "Arcane Shot", "Serpent Sting", "Multi-Shot", "Kill Shot", "Bestial Wrath",
      "Rapid Fire", "Hunter's Mark"],
  2: ["Steady Shot", "Arcane Shot", "Serpent Sting", "Chimera Shot", "Aimed Shot", "Multi-Shot",
      "Kill Shot", "Silencing Shot", "Rapid Fire", "Hunter's Mark"],
  3: ["Steady Shot", "Explosive Shot", "Serpent Sting", "Black Arrow", "Arcane Shot", "Multi-Shot",
      "Kill Shot", "Rapid Fire", "Hunter's Mark"],
 },
 "ROGUE": {
  1: ["Mutilate", "Envenom", "Rupture", "Slice and Dice", "Eviscerate", "Cold Blood", "Expose Armor",
      "Fan of Knives", "Tricks of the Trade"],
  2: ["Sinister Strike", "Eviscerate", "Slice and Dice", "Rupture", "Adrenaline Rush", "Blade Flurry",
      "Killing Spree", "Fan of Knives", "Sprint", "Tricks of the Trade"],
  3: ["Backstab", "Hemorrhage", "Eviscerate", "Slice and Dice", "Rupture", "Shadow Dance",
      "Premeditation", "Ghostly Strike", "Fan of Knives", "Tricks of the Trade"],
 },
 "PRIEST": {
  1: ["Penance", "Flash Heal", "Greater Heal", "Renew", "Prayer of Healing", "Prayer of Mending",
      "Power Infusion", "Inner Focus", "Smite", "Holy Fire"],
  2: ["Flash Heal", "Greater Heal", "Renew", "Prayer of Healing", "Prayer of Mending",
      "Circle of Healing", "Divine Hymn", "Hymn of Hope", "Holy Fire", "Smite"],
  3: ["Mind Blast", "Mind Flay", "Shadow Word: Pain", "Vampiric Touch", "Devouring Plague",
      "Mind Sear"],
 },
 "DEATHKNIGHT": {
  1: ["Icy Touch", "Plague Strike", "Heart Strike", "Death Strike", "Rune Strike", "Death Coil",
      "Blood Boil", "Pestilence", "Dancing Rune Weapon", "Horn of Winter"],
  2: ["Icy Touch", "Plague Strike", "Obliterate", "Frost Strike", "Howling Blast", "Blood Strike",
      "Pestilence", "Empower Rune Weapon", "Horn of Winter"],
  3: ["Icy Touch", "Plague Strike", "Scourge Strike", "Blood Strike", "Death Coil", "Death and Decay",
      "Pestilence", "Summon Gargoyle", "Raise Dead", "Horn of Winter"],
 },
 "SHAMAN": {
  1: ["Lightning Bolt", "Chain Lightning", "Lava Burst", "Flame Shock", "Earth Shock",
      "Elemental Mastery", "Thunderstorm", "Magma Totem", "Searing Totem", "Heroism", "Bloodlust"],
  2: ["Stormstrike", "Lava Lash", "Lightning Bolt", "Flame Shock", "Earth Shock", "Feral Spirit",
      "Magma Totem", "Searing Totem", "Heroism", "Bloodlust"],
  3: ["Healing Wave", "Lesser Healing Wave", "Chain Heal", "Riptide", "Earth Shield",
      "Lightning Bolt", "Flame Shock", "Heroism", "Bloodlust"],
 },
 "MAGE": {
  1: ["Arcane Blast", "Arcane Missiles", "Arcane Barrage", "Arcane Explosion", "Presence of Mind",
      "Arcane Power", "Mirror Image", "Fire Blast"],
  2: ["Fireball", "Scorch", "Pyroblast", "Living Bomb", "Flamestrike", "Blast Wave", "Combustion",
      "Fire Blast", "Mirror Image", "Frostfire Bolt"],
  3: ["Frostbolt", "Ice Lance", "Deep Freeze", "Blizzard", "Frostfire Bolt", "Icy Veins",
      "Summon Water Elemental", "Fire Blast"],
 },
 "WARLOCK": {
  1: ["Corruption", "Curse of Agony", "Unstable Affliction", "Haunt", "Shadow Bolt", "Drain Soul",
      "Drain Life", "Life Tap", "Seed of Corruption", "Curse of Doom"],
  2: ["Shadow Bolt", "Immolate", "Corruption", "Curse of Agony", "Metamorphosis",
      "Demonic Empowerment", "Soul Fire", "Life Tap", "Shadowflame"],
  3: ["Incinerate", "Immolate", "Conflagrate", "Chaos Bolt", "Shadow Bolt", "Shadowburn",
      "Curse of Doom", "Rain of Fire", "Life Tap", "Shadowflame"],
 },
 "DRUID": {
  1: ["Wrath", "Starfire", "Moonfire", "Insect Swarm", "Starfall", "Typhoon", "Hurricane"],
  2: ["Shred", "Mangle (Cat)", "Rake", "Rip", "Ferocious Bite", "Savage Roar", "Tiger's Fury",
      "Maul", "Lacerate", "Swipe (Bear)", "Berserk", "Faerie Fire (Feral)"],
  3: ["Healing Touch", "Nourish", "Rejuvenation", "Regrowth", "Lifebloom", "Wild Growth",
      "Swiftmend", "Nature's Swiftness"],
 },
}

# ── What ClassData.lua already carries ──────────────────────────────────────────────────────────
#
# This seed APPENDS to the vanilla curation in ClassData.lua, and appendAll dedupes by ID — which is
# not the same as deduping by ability. ClassData lists Multi-Shot as 14288 and the resolver answers
# 2643; both are Multi-Shot, both would survive the dedupe, and the viewer would show the same spell
# twice. Ranks are exactly the thing this pipeline exists to stop anyone reasoning about by eye.
#
# So the comparison is BY NAME, with every id mapped back through Spell.dbc. Nothing here is parsed
# for meaning beyond "id, -- Name" lines inside the two tables, which is the same shape verify.py
# reads.
CLASSDATA = r"D:/Project Reforged 3.3.5a/Interface/AddOns/DragonUI_NewEra/modules/cooldownviewer/ClassData.lua"
spells = {int(k): v for k, v in json.load(open("spells.json", encoding="utf-8")).items()}
vanilla, vanilla_ess = {}, {}
cur_table = cur_class = None
for line in open(CLASSDATA, encoding="utf-8"):
    m = re.match(r"M\.([A-Z_]+)\s*=\s*\{", line)
    if m:
        # ONLY the two tables this seed appends to. The first version of this matched on entry and
        # never on exit, so it ran straight through into BUFFICON_BY_CLASS and BUFFBAR_BY_CLASS and
        # reported half the rotation as colliding with the BUFF viewers — a different list entirely.
        cur_table = m.group(1) if m.group(1) in ("ESSENTIAL_BY_CLASS", "UTILITY_BY_CLASS") else None
        cur_class = None
        continue
    if line.startswith("}"):
        cur_table = cur_class = None; continue
    m = re.match(r"\s{2}([A-Z]+)\s*=\s*\{", line)
    if m and cur_table:
        cur_class = m.group(1); continue
    m = re.match(r"\s+(\d+),\s*--", line)
    if m and cur_class:
        nm = spells.get(int(m.group(1)), ("", ""))[0]
        if nm:
            vanilla.setdefault(cur_class, {})[nm] = int(m.group(1))
            # Kept separately as well: the starter check below must ask "is this in ESSENTIAL", not
            # "is this anywhere". A starter name that lives only in Utility would pass a combined
            # check and then enable nothing, because the starter writes the essential custom list.
            if cur_table == "ESSENTIAL_BY_CLASS":
                vanilla_ess.setdefault(cur_class, {})[nm] = int(m.group(1))

errors = []
def lookup(cls, name, table=None):
    sid = (table if table is not None else resolved).get(cls, {}).get(name)
    if not sid:
        errors.append(f"{cls}: {name!r} did not resolve")
        return None
    return sid

def emit(table, title, source=None):
    lines = []
    for cls in sorted(table):
        entries = []
        for nm in table[cls]:
            sid = lookup(cls, nm, source)
            if sid:
                entries.append((sid, nm))
        if not entries:
            continue
        lines.append(f"  {cls} = {{")
        for sid, nm in entries:
            lines.append(f"    {sid},{' ' * max(1, 8 - len(str(sid)))}-- {nm}")
        lines.append("  },")
    return "\n".join(lines)

ess = emit(ESSENTIAL, "essential")
uti = emit(UTILITY, "utility")
rot = emit(ROTATION, "rotation", resolved_any)

# ── Starter emit ────────────────────────────────────────────────────────────────────────────────
#
# The MERGED Essential list per class, name -> the id that list actually holds: ClassData's vanilla
# entries plus everything this file is about to emit into ESSENTIAL_ADD and ROTATION_ADD. The starter
# has to name ids that are IN the curated list, not ids that merely resolve — ClassData keeps some
# abilities at a higher rank (Multi-Shot at 14288), and a starter carrying 2643 would enable a row the
# picker has never heard of and silently do nothing.
merged = {}
for cls, names in vanilla_ess.items():      # ESSENTIAL only — see the note where it is built
    merged.setdefault(cls, {}).update(names)
for table, src in ((ESSENTIAL, resolved), (ROTATION, resolved_any)):
    for cls, names in table.items():
        for nm in names:
            sid = src.get(cls, {}).get(nm)
            if sid:
                merged.setdefault(cls, {})[nm] = sid

starter_lines = []
for cls in sorted(STARTER):
    starter_lines.append(f"  {cls} = {{")
    for tab in sorted(STARTER[cls]):
        entries = []
        for nm in STARTER[cls][tab]:
            sid = merged.get(cls, {}).get(nm)
            if not sid:
                errors.append(f"{cls} tab {tab}: {nm!r} is not in that class's Essential list, so a "
                              f"starter naming it would enable nothing")
            else:
                entries.append((sid, nm))
        starter_lines.append(f"    [{tab}] = {{")
        for sid, nm in entries:
            starter_lines.append(f"      {sid},{' ' * max(1, 8 - len(str(sid)))}-- {nm}")
        starter_lines.append("    },")
    starter_lines.append("  },")
sta = chr(10).join(starter_lines)

# A name curated twice is a curation mistake, not a runtime problem — but it ships as two tiles for
# one spell, so it is a hard error. Checked against both the other tables here AND against what
# ClassData.lua already carries, by name, because that is the only comparison ranks cannot defeat.
for cls, names in ROTATION.items():
    for nm in names:
        if nm in ESSENTIAL.get(cls, []) + UTILITY.get(cls, []):
            errors.append(f"{cls}: {nm!r} is in both the rotation and the cooldown curation")
# Same id as ClassData is harmless — appendAll drops it — and only worth printing. A DIFFERENT id for
# the same ability is the bug: two ranks of one spell, two tiles, one of them permanently dark.
redundant = []
for table, label, src in ((ESSENTIAL, "essential", resolved), (UTILITY, "utility", resolved),
                          (ROTATION, "rotation", resolved_any)):
    for cls, names in table.items():
        for nm in names:
            was = vanilla.get(cls, {}).get(nm)
            if not was:
                continue
            now = src.get(cls, {}).get(nm)
            if now and now != was:
                errors.append(f"{cls}: {nm!r} ({label}) resolves to {now} but ClassData.lua already "
                              f"lists it as {was} — two ranks of one spell is two tiles")
            else:
                redundant.append(f"{cls}: {nm!r} ({label}) duplicates ClassData.lua's {was}")

if redundant:
    print("already in ClassData.lua at the same id (deduped on append, harmless):")
    for r in redundant:
        print("  " + r)

if errors:
    print("REFUSING TO GENERATE:")
    for e in errors:
        print("  " + e)
    sys.exit(1)

header = '''-- DragonUI_NewEra/modules/cooldownviewer/CdmSeedWotLK.lua — WotLK (3.3.5a) data seed.
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
--   * Spell.dbc            (DBFilesClient\\\\Spell.dbc, from Data/enUS/patch-enUS-3.MPQ — the
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
%s
}

local UTILITY_ADD = {
%s
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
%s
}

local STARTER_BY_CLASS = {
%s
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
''' % (ess, uti, rot, sta)

out = r"D:/Project Reforged 3.3.5a/Interface/AddOns/DragonUI_NewEra/modules/cooldownviewer/CdmSeedWotLK.lua"
with open(out, "w", encoding="utf-8", newline="\n") as f:
    f.write(header)

n_e = sum(len(v) for v in ESSENTIAL.values())
n_u = sum(len(v) for v in UTILITY.values())
print(f"resolved {n_e} essential + {n_u} utility = {n_e + n_u} abilities across {len(ESSENTIAL)} classes")
print("wrote", out)
