import os, struct, json, re, collections
from mpyq import MPQArchive
DATA = r"D:/Project Reforged 3.3.5a/Data/enUS"
def grab(n):
    best = None
    for a in ["locale-enUS.MPQ","patch-enUS.MPQ","patch-enUS-2.MPQ","patch-enUS-3.MPQ"]:
        p = os.path.join(DATA, a)
        if os.path.exists(p):
            try:
                d = MPQArchive(p).read_file("DBFilesClient\\" + n)
                if d: best = d
            except Exception: pass
    return best

sblob = grab("Spell.dbc")
magic, rc, fc, rs, sbs = struct.unpack("<4sIIII", sblob[:20])
srecs = [struct.unpack_from(f"<{fc}I", sblob, 20 + i*rs) for i in range(rc)]
sb = sblob[20+rc*rs : 20+rc*rs+sbs]
def s(o):
    if o <= 0 or o >= len(sb): return ""
    e = sb.find(b"\0", o); return sb[o:e].decode("utf-8","ignore")
NAME, RANK, REC, CAT = 136, 153, 29, 30
spell = {r[0]: (s(r[NAME]), s(r[RANK]), max(r[REC], r[CAT])) for r in srecs}

# Passive flag, for the rotation resolver below. Asserted rather than searched, exactly as
# gen_auracatalog.py does it: a flag word has no unique anchor value, so the check is that known
# passives and known abilities land on the right side of it.
ATTR, ATTR_PASSIVE = 4, 0x40
_by_id = {r[0]: r for r in srecs}
for sid, want in ((16864, True), (17007, True), (5176, False), (133, False)):
    if bool(_by_id[sid][ATTR] & ATTR_PASSIVE) != want:
        raise SystemExit(f"Attributes col {ATTR} fails the passive check on {sid}")
passive = {r[0] for r in srecs if r[ATTR] & ATTR_PASSIVE}

ablob = grab("SkillLineAbility.dbc")
_, arc, afc, ars, _ = struct.unpack("<4sIIII", ablob[:20])
arecs = [struct.unpack_from(f"<{afc}I", ablob, 20 + i*ars) for i in range(arc)]

# SkillLine, for the category + name of each line the vote below runs over.
lblob = grab("SkillLine.dbc")
_, lrc, lfc, lrs, lsbs = struct.unpack("<4sIIII", lblob[:20])
lrecs = [struct.unpack_from(f"<{lfc}I", lblob, 20 + i*lrs) for i in range(lrc)]
lsb = lblob[20+lrc*lrs : 20+lrc*lrs+lsbs]
def ls(o):
    if o <= 0 or o >= len(lsb): return ""
    e = lsb.find(b"\0", o); return lsb[o:e].decode("utf-8","ignore")
# Name column located the same way dbc.py locates SpellName: the one where known lines give known
# names. Category is field 1, and CATEGORY 7 IS "class skills" — Arms, Holy, Blood, Discipline…
LNAME = next(c for c in range(1, lfc)
             if sum(1 for k, v in {26:"Arms", 95:"Defense", 184:"Retribution", 594:"Holy",
                                   770:"Blood"}.items()
                    if ls(dict((r[0], r) for r in lrecs).get(k, (0,)*lfc)[c]) == v) >= 4)
line_cat  = {r[0]: r[1] for r in lrecs}
line_name = {r[0]: ls(r[LNAME]) for r in lrecs}

CLASS_BY_ID = {1:"WARRIOR",2:"PALADIN",3:"HUNTER",4:"ROGUE",5:"PRIEST",6:"DEATHKNIGHT",
               7:"SHAMAN",8:"MAGE",9:"WARLOCK",11:"DRUID"}
votes = collections.defaultdict(collections.Counter)
for r in arecs:
    for cid, cname in CLASS_BY_ID.items():
        if r[4] & (1 << (cid-1)): votes[r[1]][cname] += 1

# WHICH LINES GET A VOTE AT ALL. The plain `most_common(1)` this used to be is wrong, and was
# invisible for as long as the `>1.5s cooldown` filter downstream was throwing the damage away — it
# surfaced the moment the rotation resolver below stopped filtering, as PALADIN reporting 661
# "abilities" against 60-100 for every other class.
#
#   * CATEGORY 7 ONLY. Skill line 202 is ENGINEERING: 321 rows, of which 287 carry no class mask at
#     all, and the 34 that do split 10 PALADIN / 9 SHAMAN / 9 DRUID — class-restricted engineering
#     items. `most_common` broke that near-tie for PALADIN and handed a profession's entire inventory
#     to paladins. First Aid (129) and GENERIC (DND) (183) fail the same way.
#   * MOUNTS EXCLUDED BY NAME. Line 777 is category 7 like the real class lines, and 4 of its 315
#     rows carry a class mask (the paladin class mounts) — so it is unanimously PALADIN and passes
#     every ratio test. It is named rather than thresholded because that is what it is: one line, one
#     reason, no tuned constant that some later patch drifts past.
#   * 90% DOMINANCE. What is left after those two is real class lines, where the winner takes all but
#     a stray row or two.
#
# Verified before adopting: this changes NOT ONE id in the existing Essential/Utility curation. It
# only stops junk lines from offering names. In particular it does NOT use each row's own class mask
# instead of the vote — that was tried, and it loses every talent-granted ability (Penance, Starfall,
# Dispersion, the whole of DEATHKNIGHT), whose skill-line rows carry a class mask of 0.
skill2class = {}
for k, v in votes.items():
    if line_cat.get(k) != 7 or line_name.get(k) == "Mounts":
        continue
    total = sum(v.values())
    cls, n = v.most_common(1)[0]
    if total and n / total >= 0.90:
        skill2class[k] = cls

def ranknum(rk):
    m = re.search(r"(\d+)\s*$", rk or "")
    return int(m.group(1)) if m else 0

# class -> name -> candidate ids
cand = collections.defaultdict(lambda: collections.defaultdict(set))
for r in arecs:
    cls = skill2class.get(r[1])
    if not cls: continue
    nm = spell.get(r[2])
    if nm and nm[0]: cand[cls][nm[0]].add(r[2])

# Resolve each name to the RANK-1 CASTABLE id: must have a real cooldown (>1.5s), lowest rank,
# then lowest id. Spells with no cooldown are triggers/passives and are never what we want.
resolved = {}
listing  = {}
for cls, byname in cand.items():
    resolved[cls] = {}
    rows = []
    for nm, ids in byname.items():
        withcd = [(ranknum(spell[i][1]), i, spell[i][2]) for i in ids if spell[i][2] > 1500]
        if not withcd: continue
        withcd.sort()
        _, best, cdms = withcd[0]
        resolved[cls][nm] = best
        rows.append((cdms, nm, best))
    rows.sort(key=lambda t: -t[0])
    listing[cls] = rows

# ── The rotation resolver ───────────────────────────────────────────────────────────────────────
#
# The filter above is the reason whole classes had no filler in the viewers: a rotational spell —
# Wrath, Shred, Steady Shot, Frostbolt — has NO cooldown, so it resolves to nothing and gen_wotlk.py
# treats that as a hard error. It could never have emitted one.
#
# So this second pass drops the cooldown test and replaces it with the one thing that test was
# standing in for: telling the real ability from its triggered sub-spells. Two rules, both chosen by
# reading candidate dumps rather than by reasoning about them (explore_nocd.py prints them):
#
#   * PREFER AN EXPLICIT "Rank 1", and only fall back to an unranked id when the ability has no
#     ranked row at all. Rejuvenation is the case that forces this: its fifteen ranks are joined by an
#     UNRANKED sixteenth (64801, the glyph's version), and sorting by rank number alone puts that one
#     first, because an unparseable rank string scores 0. Savage Roar and Swipe (Cat) are the other
#     side of it — genuinely single-rank abilities whose rank text is empty.
#   * DROP PASSIVES. A passive is never a button, and without the cooldown filter there is nothing
#     else keeping talent passives out of a list of things to press.
#
# Ranks above 1 are never eligible, so the emitted id stays the rank-1 id the rest of the seed uses
# and the runtime's own rank upgrade (NE.spellbook.HighestKnownRankID) still does the walking.
resolved_any = {}
for cls, byname in cand.items():
    resolved_any[cls] = {}
    for nm, ids in byname.items():
        usable = [i for i in ids if i not in passive]
        r1 = sorted(i for i in usable if spell[i][1] == "Rank 1")
        unranked = sorted(i for i in usable if spell[i][1] == "")
        if r1:
            resolved_any[cls][nm] = r1[0]
        elif unranked:
            resolved_any[cls][nm] = unranked[0]

json.dump(resolved, open("resolved.json","w",encoding="utf-8"))
json.dump(resolved_any, open("resolved_any.json","w",encoding="utf-8"))
print("resolved (name -> rank1 castable id, cooldown > 1.5s):")
for cls in sorted(listing): print(f"  {cls:12s} {len(listing[cls]):3d} abilities")
print("rotation resolver (name -> rank1 id, no cooldown required, passives dropped):")
for cls in sorted(resolved_any): print(f"  {cls:12s} {len(resolved_any[cls]):3d} names")
with open("listing.txt","w",encoding="utf-8") as f:
    for cls in sorted(listing):
        f.write(f"\n===== {cls} =====\n")
        for cdms, nm, sid in listing[cls]:
            f.write(f"  {cdms/1000:8.1f}s  {sid:6d}  {nm}\n")
print("wrote listing.txt")
