"""Generates modules/cooldownviewer/CdmAuraCatalog.lua — the per-class pool of trackable SELF-BUFFS.

This is to the buff viewers what gen_arsenal.py is to Essential/Utility: it turns the Tracked
Buffs / Tracked Bars picker from a list of things you have already had into a catalog of things you
can have — retail's shape, where Blizzard ships a curated per-spec aura set through
C_CooldownViewer. There is no such table on 3.3.5a, so it is derived from the client's own DBCs.

WHAT COUNTS AS A TRACKABLE SELF-BUFF

  * some effect is APPLY_AURA (6) with implicit target A = UNIT_CASTER (1) — a buff on YOU, so
    heals, DoTs and raid buffs cast on others are out
  * a real timed duration, 0 < d <= 120s — the same window the runtime auto-tracker uses
    (M.BUFF_TRACK_MAX_DURATION), which is also why food buffs, flasks and permanent toggles are out
  * not passive (Attributes & 0x40)
  * NOT CHANNELLED (AttributesEx & 0x44). Without this, Blizzard, Evocation, Mind Control and
    Tranquility all read as 8-60s "buffs" — a channel's duration lives in the same column as an
    aura's, and there is nothing else in the record to tell them apart.

Reached two ways: the class ability itself, and ONE HOP through EffectTriggerSpell — which is where
the procs live (Clearcasting, Missile Barrage, Lock and Load, Killing Machine, Borrowed Time). The
hop is what makes the catalog worth having; without it you get cooldowns you press and nothing that
happens TO you.

CLASS ATTRIBUTION, AND WHY THE VOTE ALONE IS NOT ENOUGH

resolve.py maps skill line -> class by majority vote. That is fine there because its >1.5s cooldown
filter hides the collateral, but here it drags in skill line 183 "GENERIC (DND)" — Grovel, Honorless
Target — which has rows for all ten classes and a per-row class mask of 0. So:

  * a row with a nonzero class mask is authoritative (it names its classes outright)
  * a row with mask 0 falls back to the skill line's class, but only if that line is >=90% one
    class. Marksmanship (85 rows, all HUNTER) qualifies; GENERIC, First Aid, Cloth and the racial
    lines do not

Dropping the racial lines costs Berserking and Blood Fury. They are race-gated rather than
class-gated so they do not fit a per-class catalog, retail's curated list has no racials either, and
the runtime seen-aura registry picks them up the first time you press them.

TALENTS ARE THE "PER SPEC" PART

Talent.dbc gives every talent's spell ranks; TalentTab.dbc gives that talent's class (ClassMask,
col 20) and tree order (OrderIndex, col 22). An aura reachable only through a talent is emitted with
that talent's NAME, and the runtime gate asks GetTalentInfo whether the player actually has it. That
beats a static per-spec list on its own terms: it follows respecs and dual spec.

An aura reachable BOTH from a baseline ability and from a talent is emitted ungated. Showing a row
the player cannot use is a much smaller fault than hiding one they can.

COLUMN POSITIONS, ALL LOCATED RATHER THAN ASSUMED

Every column below is proved by `locate()` against anchors whose values are known independently, and
an ambiguous or failed match is a hard error. Two of them were WRONG on the first attempt in exactly
the way assuming would never have caught: Bloodrage has no duration of its own (its aura is on the
triggered spell 29131) and its first effect is ENERGIZE, not APPLY_AURA — so anchoring on it
"disproved" two correct columns.

KNOWN GAP: Data/patch-4.MPQ and patch-S.mpq are encrypted and unreadable, so if this server
overrides spell data there, these ids reflect the stock client.
"""
import os, re, struct, collections, sys

DATA = r"D:/Project Reforged 3.3.5a/Data/enUS"
ORDER = ["locale-enUS.MPQ", "patch-enUS.MPQ", "patch-enUS-2.MPQ", "patch-enUS-3.MPQ"]
OUT = "../../modules/cooldownviewer/CdmAuraCatalog.lua"

WINDOW_MS = 120000          # must match M.BUFF_TRACK_MAX_DURATION
# A floor as well as a ceiling. Heroic Fury's aura lasts 100ms: real, self-targeted, in the window,
# and completely unreadable as a bar or a swipe. Anything under a second is a mechanic, not a buff.
MIN_MS = 1000
APPLY_AURA, TARGET_SELF = 6, 1
ATTR_PASSIVE = 0x40
ATTREX_CHANNELED = 0x4 | 0x40

CLASS_BY_ID = {1: "WARRIOR", 2: "PALADIN", 3: "HUNTER", 4: "ROGUE", 5: "PRIEST",
               6: "DEATHKNIGHT", 7: "SHAMAN", 8: "MAGE", 9: "WARLOCK", 11: "DRUID"}


def load(name):
    from mpyq import MPQArchive
    blob = None
    for a in ORDER:
        p = os.path.join(DATA, a)
        if not os.path.exists(p):
            continue
        try:
            d = MPQArchive(p).read_file("DBFilesClient\\" + name)
            if d:
                blob = d          # later archive wins
        except Exception:
            pass
    if not blob:
        sys.exit(f"{name} not found under {DATA}")
    magic, rc, fc, rs, sbs = struct.unpack("<4sIIII", blob[:20])
    if magic != b"WDBC":
        sys.exit(f"{name}: bad magic {magic!r}")
    recs = [struct.unpack_from(f"<{fc}I", blob, 20 + i * rs) for i in range(rc)]
    sb = blob[20 + rc * rs: 20 + rc * rs + sbs]

    def s(o):
        if o <= 0 or o >= len(sb):
            return ""
        e = sb.find(b"\0", o)
        return sb[o:e].decode("utf-8", "ignore")
    return recs, s, fc


spell, sstr, SFC = load("Spell.dbc")
dur, _, _ = load("SpellDuration.dbc")
sla, _, _ = load("SkillLineAbility.dbc")
skl, kstr, KFC = load("SkillLine.dbc")
tal, _, _ = load("Talent.dbc")
tab, tstr, _ = load("TalentTab.dbc")

by_id = {r[0]: r for r in spell}
DURBASE = {r[0]: r[1] for r in dur}


def locate(label, anchors, xform=lambda v: v):
    """The one column that agrees with every anchor. Ambiguity is an error, not a first match."""
    hits = [c for c in range(1, SFC)
            if all(by_id.get(sid) and xform(by_id[sid][c]) == want for sid, want in anchors.items())]
    if len(hits) != 1:
        sys.exit(f"{label}: expected exactly one matching column, got {hits}")
    print(f"  {label:26s} = {hits[0]:3d}  (proved by {len(anchors)} anchors)")
    return hits[0]


print("locating columns:")
NAME = locate("Spell.SpellName", {133: "Fireball", 8092: "Mind Blast", 1459: "Arcane Intellect"},
              xform=sstr)
RANK = NAME + 17          # next locale block: 16 locales + a flags word
DURIDX = locate("Spell.DurationIndex", {12042: 15000, 12472: 20000, 2825: 40000, 139: 15000,
                                        588: 1800000, 172: 12000}, xform=lambda v: DURBASE.get(v))
EFF = locate("Spell.Effect[0]", {133: 2, 139: 6, 12042: 6, 172: 6, 588: 6, 1459: 6})
if locate("Spell.Effect[1]", {133: 6, 172: 3, 12042: 6, 12472: 6, 139: 0}) != EFF + 1:
    sys.exit("Effect[] is not contiguous")
TGTA = locate("Spell.ImplicitTargetA[0]", {12042: 1, 588: 1, 139: 21, 133: 6, 172: 6})
TRIG = locate("Spell.EffectTriggerSpell[1]", {2687: 29131}) - 1
ATTR, ATTREX = 4, 5
# Attributes/AttributesEx are asserted rather than searched: a flag word has no unique anchor value.
# These two facts are what the channel filter rests on, so they are checked outright.
for sid, want_chan in ((10, True), (12051, True), (605, True), (12042, False), (16870, False)):
    if bool(by_id[sid][ATTREX] & ATTREX_CHANNELED) != want_chan:
        sys.exit(f"AttributesEx col {ATTREX} fails the channel check on {sid}")
print(f"  {'Spell.Attributes':26s} = {ATTR:3d}\n  {'Spell.AttributesEx':26s} = {ATTREX:3d}"
      f"  (channel filter checked on 5 spells)")


def spellname(sid):
    r = by_id.get(sid)
    return sstr(r[NAME]) if r else ""


def ranknum(sid):
    r = by_id.get(sid)
    m = re.search(r"(\d+)\s*$", sstr(r[RANK]) if r else "")
    return int(m.group(1)) if m else 0


def duration_ms(sid):
    r = by_id.get(sid)
    return DURBASE.get(r[DURIDX], 0) if r else 0


def is_self_aura(sid):
    r = by_id.get(sid)
    if not r:
        return False
    if r[ATTR] & ATTR_PASSIVE:
        return False
    if r[ATTREX] & ATTREX_CHANNELED:
        return False
    return any(r[EFF + i] == APPLY_AURA and r[TGTA + i] == TARGET_SELF for i in range(3))


# ── racial skill lines ──────────────────────────────────────────────────────────────────────────
# Blood Fury proves these cannot be left to the class-mask rule: the orc racial's SkillLineAbility
# row carries a WARRIOR bit, so it reads as a baseline warrior ability and would be offered to every
# warrior in the game. Race-gating is not something a per-class catalog can express.
SKL_NAME = None
for c in range(1, KFC):
    if any(r[0] == 26 and kstr(r[c]) == "Arms" for r in skl):
        SKL_NAME = c
        break
if SKL_NAME is None:
    sys.exit("could not locate the SkillLine name column")
racial_lines = {r[0] for r in skl if kstr(r[SKL_NAME]).endswith("Racial")}
racial_ids = {r[2] for r in sla if r[1] in racial_lines}
print(f"  {'SkillLine.Name':26s} = {SKL_NAME:3d}  ({len(racial_lines)} racial lines excluded)")

# ── class attribution ───────────────────────────────────────────────────────────────────────────
line_votes = collections.defaultdict(collections.Counter)
for r in sla:
    for cid, cname in CLASS_BY_ID.items():
        if r[4] & (1 << (cid - 1)):
            line_votes[r[1]][cname] += 1

DOMINANCE = 0.90
line_class = {}
for line, v in line_votes.items():
    total = sum(v.values())
    cname, n = v.most_common(1)[0]
    if total and n / total >= DOMINANCE:
        line_class[line] = cname

class_spells = collections.defaultdict(set)
generic_dropped, racial_dropped = 0, 0
for r in sla:
    if r[1] in racial_lines:
        racial_dropped += 1
        continue
    mask = r[4]
    if mask:
        for cid, cname in CLASS_BY_ID.items():
            if mask & (1 << (cid - 1)):
                class_spells[cname].add(r[2])
    else:
        c = line_class.get(r[1])
        if c:
            class_spells[c].add(r[2])
        else:
            generic_dropped += 1

# ── talent attribution ──────────────────────────────────────────────────────────────────────────
tabinfo = {}
for r in tab:
    mask, order = r[20], r[22]
    for cid, cname in CLASS_BY_ID.items():
        if mask & (1 << (cid - 1)):
            tabinfo[r[0]] = (cname, order + 1, tstr(r[1]))

talent_of = {}      # spellID -> (class, tree, treeName, talentName)
for r in tal:
    info = tabinfo.get(r[1])
    if not info:
        continue
    ranks = [r[c] for c in range(4, 13) if r[c]]
    if not ranks:
        continue
    tname = spellname(ranks[0])
    for sid in ranks:
        talent_of[sid] = (info[0], info[1], info[2], tname)

# ── build ───────────────────────────────────────────────────────────────────────────────────────
# class -> auraName -> dict(id, dur, tree, talent, via)
rows = collections.defaultdict(dict)


conflicts = collections.defaultdict(set)   # (cls, auraName) -> {"gated", "ungated"}


def offer(cls, sid, src, via):
    """src is the talent tuple of the SOURCE ability, or None for a baseline one."""
    nm = spellname(sid)
    if not nm:
        return
    d = duration_ms(sid)
    if not (MIN_MS <= d <= WINDOW_MS) or not is_self_aura(sid):
        return
    cand = dict(id=sid, dur=d, tree=src[1] if src else 0,
                talent=src[3] if src else None, via=via, rank=ranknum(sid))
    conflicts[(cls, nm)].add("gated" if src else "ungated")
    prev = rows[cls].get(nm)
    if prev is None or sortkey(cand) < sortkey(prev):
        rows[cls][nm] = cand


def sortkey(c):
    # A talent attribution WINS over a baseline-looking one. Both routes reach plenty of auras,
    # because the client indexes a talent's triggered proc aura in a class skill line as well —
    # Improved Steady Shot and Lock and Load sit in the Marksmanship/Survival lines despite being
    # purely talent-granted, so "it is in a skill line" is not evidence of being baseline, while
    # "Talent.dbc reaches it" IS evidence of being talent-gated. Preferring ungated left HUNTER
    # with 1 gated row out of 18. The rows this gets wrong are recoverable: the picker's existing
    # Show Unlearned toggle reveals spec-gated rows the player has not talented.
    return (0 if c["talent"] else 1, c["rank"], c["id"])


for cls, ids in class_spells.items():
    for sid in ids:
        src = talent_of.get(sid)
        if src and src[0] != cls:
            src = None
        offer(cls, sid, src, "class")
        r = by_id.get(sid)
        if r:
            for i in range(3):
                if r[TRIG + i]:
                    offer(cls, r[TRIG + i], src, "trigger")

for sid, src in talent_of.items():
    cls = src[0]
    offer(cls, sid, src, "talent")
    r = by_id.get(sid)
    if r:
        for i in range(3):
            if r[TRIG + i]:
                offer(cls, r[TRIG + i], src, "trigger")

# ── verify, independently of how it was built ───────────────────────────────────────────────────
problems = []
seen_ids = collections.defaultdict(list)
for cls, byname in rows.items():
    for nm, c in byname.items():
        sid = c["id"]
        seen_ids[(cls, sid)].append(nm)
        if spellname(sid) != nm:
            problems.append(f"{cls} {sid}: name {spellname(sid)!r} != key {nm!r}")
        if not is_self_aura(sid):
            problems.append(f"{cls} {sid} {nm}: not a non-channelled self aura")
        d = duration_ms(sid)
        if not (MIN_MS <= d <= WINDOW_MS):
            problems.append(f"{cls} {sid} {nm}: duration {d} outside the window")
        if sid in racial_ids:
            problems.append(f"{cls} {sid} {nm}: a racial reached the catalog")
        if c["talent"] and not c["tree"]:
            problems.append(f"{cls} {sid} {nm}: talent {c['talent']!r} with no tree")
for key, names in seen_ids.items():
    if len(names) > 1:
        problems.append(f"{key}: one id under several names {names}")
if problems:
    for p in problems:
        print("  PROBLEM", p)
    sys.exit(f"{len(problems)} problem(s); nothing written")

# ── emit ────────────────────────────────────────────────────────────────────────────────────────
HEADER = '''-- DragonUI_NewEra/modules/cooldownviewer/CdmAuraCatalog.lua — GENERATED, DO NOT HAND-EDIT.
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
'''


def lua_str(s):
    return '"' + s.replace("\\", "\\\\").replace('"', '\\"') + '"'


out = [HEADER]
total, gated = 0, 0
for cls in sorted(rows):
    entries = sorted(rows[cls].items(), key=lambda kv: (-kv[1]["dur"], kv[0].lower()))
    out.append(f"  {cls} = {{")
    for nm, c in entries:
        secs = c["dur"] / 1000.0
        secs_lua = f"{secs:g}"
        bits = [f"id = {c['id']}", f"name = {lua_str(nm)}", f"dur = {secs_lua}"]
        if c["talent"]:
            bits.append(f"tree = {c['tree']}")
            bits.append(f"talent = {lua_str(c['talent'])}")
            gated += 1
        out.append("    { " + ", ".join(bits) + f" }},   -- {c['via']}")
        total += 1
    out.append("  },")
out.append("}")
out.append("")

path = os.path.abspath(OUT)
with open(path, "w", encoding="utf-8", newline="\n") as f:
    f.write("\n".join(out) + "\n")

print(f"\nwrote {path}")
print(f"  dropped {generic_dropped} SkillLineAbility rows with no usable class attribution,"
      f" {racial_dropped} racial rows")
both = sorted(k for k, v in conflicts.items() if len(v) > 1 and k[1] in rows[k[0]])
print(f"  {len(both)} aura(s) reachable BOTH ways (talent attribution won):")
for cls, nm in both:
    c = rows[cls][nm]
    print(f"     {cls:12s} {nm:28s} talent={c['talent']!r} tree={c['tree']}")
for cls in sorted(rows):
    g = sum(1 for c in rows[cls].values() if c["talent"])
    print(f"  {cls:12s} {len(rows[cls]):3d}  ({g} spec-gated)")
print(f"  {'TOTAL':12s} {total:3d}  ({gated} spec-gated)")
