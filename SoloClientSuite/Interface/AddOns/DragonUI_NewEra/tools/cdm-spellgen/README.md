# CDM spell generator

Generates `modules/cooldownviewer/CdmSeedWotLK.lua` from the **client's own data**, so no spell ID
is ever typed from memory. This is the 3.3.5a equivalent of the `.scratch/spellgen` pipeline that
NewEra's `CdmSeedTBC.lua` was built with, and it exists for the same reason: a wrong ID here is
silent — the icon simply never lights up, or lights up for the wrong thing.

## Requirements

```bash
python -m pip install mpyq
```

## Pipeline

Run from this directory, in order:

| script | does | writes |
|---|---|---|
| `dbc.py` | extracts + parses `DBFilesClient\Spell.dbc` | `spells.json` |
| `resolve.py` | joins it with `SkillLineAbility.dbc` + `SkillLine.dbc` to attribute spells to classes, then resolves each ability name to its rank-1 ID — twice, once requiring a cooldown and once not | `resolved.json`, `resolved_any.json`, `listing.txt` |
| `gen_wotlk.py` | applies the authored curation and emits the Lua seed | `../../modules/cooldownviewer/CdmSeedWotLK.lua` |
| `verify.py` | re-checks every emitted ID against the DBC independently | — (exit 1 on any problem) |
| `explore_nocd.py` | not a pipeline step. Prints each class's no-cooldown, non-passive, non-talent abilities — the menu the rotation curation is authored from — or one name's candidate IDs | `listing_nocd.txt` |
| `gen_alertdata.py` | resolves the Execute / Reactive ability names to **every** rank | `../../modules/cooldownviewer/AlertData.lua` |
| `gen_auracatalog.py` | the per-class pool of trackable **self-buffs** — standalone, reads the DBCs itself | `../../modules/cooldownviewer/CdmAuraCatalog.lua` |

`listing.txt` is the useful artefact for curation: every class's abilities that carry a real
cooldown, sorted longest-first.

## Where the data comes from

DBCs live in the **locale** archives, not the base ones: `Data/enUS/{locale,patch-enUS,
patch-enUS-2,patch-enUS-3}.MPQ`, later winning. `Data/*.MPQ` carry no `Spell.dbc` override.

Column positions in 3.3.5a `Spell.dbc` (234 fields, 936-byte records), all located empirically by
the scripts rather than assumed:

- `136` SpellName, `153` Rank (16 locale slots + a flags word apart)
- `29` RecoveryTime, `30` CategoryRecoveryTime — cooldown is `max` of the two

## Why "castable" needs defining

A name maps to several IDs: the ability plus its triggered sub-spells. The discriminator is a real
cooldown (`> 1.5s`), which is also exactly what the Cooldown Manager reads. So `resolve.py` picks
the lowest-rank, lowest-ID entry that has one — giving Penance `47540` rather than its `47666` /
`47750` heal and damage triggers, and Death Grip `49576` rather than `49560` / `49575`.

## …and why that definition hid an entire half of the data

`> 1.5s` is a fine test for "is this the ability or one of its triggers" and a terrible one for "is
this an ability". Every rotational spell in the game — Wrath, Frostbolt, Shred, Steady Shot, Shadow
Bolt — has **no cooldown at all**, so it resolved to nothing and `gen_wotlk.py` rejected it as an
unresolvable name. The seed could never have contained one. Reported from the game as "lots of classes
are missing default abilities that dont have cooldowns, such as druids with wrath".

So `resolve.py` runs a second pass with no cooldown test, and replaces it with the two rules that were
actually doing the work — both chosen by reading `explore_nocd.py` dumps rather than by argument:

- **Prefer an explicit `Rank 1`; fall back to unranked only when there is no ranked row.** Rejuvenation
  forces this: its fifteen ranks are joined by an *unranked* sixteenth (`64801`), and sorting by rank
  number puts that one first because an unparseable rank string scores 0. Savage Roar and Swipe (Cat)
  are the other side — genuinely single-rank, empty rank text.
- **Drop passives.** Without the cooldown filter nothing else keeps talent passives out of a list of
  things to press.

## The class attribution was wrong, and the cooldown filter was hiding that too

`skill2class` used to be a bare `most_common(1)` over every skill line. Three lines break it:

| line | what it is | why it won |
|---|---|---|
| 202 | **Engineering** | 321 rows, 287 with no class mask; the 34 that do split 10 PALADIN / 9 SHAMAN / 9 DRUID — class-restricted engineering items. `most_common` broke the tie for PALADIN and handed a profession's whole inventory to paladins. |
| 777 | **Mounts** | category 7 like the real class lines; 4 of its 315 rows carry a class mask (the paladin class mounts), so it is unanimously PALADIN. |
| 183, 129 | GENERIC (DND), First Aid | same shape as 202. |

Invisible while every answer had to carry a cooldown; it surfaced the moment the rotation resolver
stopped filtering, as PALADIN reporting **661** abilities against 60–100 for every other class. The fix
is category 7 only, Mounts excluded by name, and a 90% dominance rule — verified to change **not one
ID** in the existing Essential/Utility curation. Using each row's own class mask instead of the vote was
tried and is worse: it loses every talent-granted ability (Penance, Starfall, Dispersion, all of
DEATHKNIGHT), whose skill-line rows carry a class mask of 0.

## What curation still means

`gen_wotlk.py` holds the only hand-authored part: which ability belongs in **Essential** (offensive
burst, damage and throughput cooldowns) vs **Utility** (defensives, interrupts, CC, escapes, raid
cooldowns). Names are authored; IDs are resolved. An unresolvable name is a hard error rather than
a silent omission.

`ROTATION` is the third table and the same deal — names authored, IDs resolved, an unresolvable name is
a hard error. It emits into its own `ROTATION_ADD` in the Lua rather than into `ESSENTIAL_ADD`, which is
what lets `verify.py` keep asserting "carries a real cooldown" of the two tables where that is true
instead of dropping the check for all three. In that table the assertion is inverted: an entry that
*does* carry a cooldown is an error, and it is how Crusader Strike (4s) and Flame Shock (6s) got moved
up into Essential where they belong.

Two collision guards, because the seed **appends** to `ClassData.lua` and `appendAll` dedupes by **ID**,
which is not the same as deduping by ability:

- a name curated into two of the three tables here;
- a name already in `ClassData.lua` — compared **by name**, with every vanilla ID mapped back through
  `Spell.dbc`, because ranks are exactly what an eyeball comparison cannot catch. `ClassData` lists
  Multi-Shot as `14288` and the resolver answers `2643`: both real, both survive an ID dedupe, and the
  viewer shows one spell twice. Same ID is merely redundant and only printed; a *different* ID is a
  hard error. It caught nine of those in the rotation curation.

  Its own first version had a bug worth keeping in mind if you touch it: it matched the two table
  headers on entry and nothing on exit, so it read straight on into `BUFFICON_BY_CLASS` and
  `BUFFBAR_BY_CLASS` and reported half the rotation as colliding with the **buff** viewers. That false
  alarm is how the bad IDs in those two tables were found (see below) — but it was still a false alarm.

`verify.py` then independently re-reads the DBC and asserts, for every emitted ID: it exists, its
name matches the trailing comment, it carries a real cooldown (or, in `ROTATION_ADD`, does not), it is
rank 1, and no ID is duplicated. That gate is what caught three Metamorphosis-form/passive entries (rank
`Demon` and `Passive`) that had no business in a pressable-cooldown list.

## Why `gen_alertdata.py` resolves differently

It answers a different question, so it cannot reuse `resolve.py`'s answer. The cooldown viewer wants
*one* id per ability; the alert engine has to recognise the ability at **whichever rank the player
casts**, so it keeps them all. It also can't use the `>1.5s cooldown` castability filter — Execute,
Victory Rush and Riposte have no cooldown at all.

Two traps, both found by reading output rather than by reasoning about it:

- **Rank text cannot tell a real ability from an impostor.** Overpower rank 1 (`7384`) has an
  **empty** rank string while its ranks 2-4 are labelled, so a "keep the ranked rows" filter throws
  away the real ability. All four NPC copies of Riposte are likewise unranked, so the same filter
  keeps them.
- **`SkillLineAbility` attribution fixes both**, because NPC spells appear in no player skill line.
  Applied *first*, the "drop unranked siblings" rule is then safe and removes triggered sub-spells
  such as Execute's damage component (`20647`).

Incidentally confirmed by the same query: Overpower's higher ranks appear in no skill line on
3.3.5a — it is single-rank on this client.

## `gen_auracatalog.py` — the buff picker's catalog

Standalone rather than a step in the pipeline above: it needs Spell.dbc columns `spells.json` does not
carry (effects, targets, durations, attribute flags), plus SkillLine, Talent and TalentTab. It locates
every column with `locate()` — the one column agreeing with 3-6 independently-known anchors, where
ambiguity is a hard error — and verifies its own output before writing.

An entry is a spell that puts a timed aura on the **caster** (`EffectImplicitTargetA == 1`) lasting
1-120s, reached directly or through one `EffectTriggerSpell` hop. The hop is where the value is: it is
the difference between a list of cooldowns you press and a list of things that happen to you
(Clearcasting, Missile Barrage, Lock and Load, Sudden Death, Bloodsurge).

Three filters exist only because output was read rather than reasoned about:

- **`AttributesEx & 0x44`** (channelled). A channel's duration lives in the same column as an aura's,
  so without this Blizzard, Evocation, Mind Control and Tranquility all arrive as "self buffs".
- **Per-row class mask first, skill-line vote only at >=90% dominance.** `resolve.py`'s majority vote
  drags in skill line 183 `GENERIC (DND)` — Grovel, Honorless Target — whose rows have a class mask of
  0 and vote evenly for all ten classes.
- **Racial skill lines excluded outright.** Blood Fury's row carries a WARRIOR class bit and would
  otherwise be offered to every warrior regardless of race.

Talent gating is the "per spec" part, and it is per **talent** rather than per spec on purpose: the
runtime asks `GetTalentInfo`, so it follows respecs and dual spec. Where an aura is reachable both as a
talent proc and as a class-skill-line row, **the talent reading wins** — the client indexes talent procs
in class skill lines, so presence there is not evidence of being baseline. All 35 both-ways conflicts
were printed and checked by hand; every one is a real talent.

## Known gap

`Data/patch-4.MPQ` and `Data/patch-S.mpq` are encrypted and cannot be read. If this server
overrides spell data there, these IDs reflect the stock client instead. Nothing observed suggests
it does, but it is the one hole in the sourcing and is repeated in the generated file's header.
