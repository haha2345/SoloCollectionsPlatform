"""Scratch: list every NO-COOLDOWN ability in each class's player skill lines.

listing.txt is the menu for curating COOLDOWNS. There has never been a menu for the other half —
the rotational spells a class presses constantly, which carry no cooldown at all and are therefore
invisible to resolve.py's `> 1.5s` castability filter. This prints that complement, plus every
candidate id behind each name, so the resolution rule for them can be chosen from evidence.

Not part of the pipeline; run by hand while authoring.
"""
import os, struct, re, collections, sys
from mpyq import MPQArchive

DATA = r"D:/Project Reforged 3.3.5a/Data/enUS"


def grab(n):
    best = None
    for a in ["locale-enUS.MPQ", "patch-enUS.MPQ", "patch-enUS-2.MPQ", "patch-enUS-3.MPQ"]:
        p = os.path.join(DATA, a)
        if os.path.exists(p):
            try:
                d = MPQArchive(p).read_file("DBFilesClient\\" + n)
                if d:
                    best = d
            except Exception:
                pass
    return best


sblob = grab("Spell.dbc")
magic, rc, fc, rs, sbs = struct.unpack("<4sIIII", sblob[:20])
srecs = [struct.unpack_from(f"<{fc}I", sblob, 20 + i * rs) for i in range(rc)]
sb = sblob[20 + rc * rs: 20 + rc * rs + sbs]


def s(o):
    if o <= 0 or o >= len(sb):
        return ""
    e = sb.find(b"\0", o)
    return sb[o:e].decode("utf-8", "ignore")


NAME, RANK, REC, CAT = 136, 153, 29, 30
ATTR, ATTR_PASSIVE = 4, 0x40          # same columns gen_auracatalog.py proves and uses
spell = {r[0]: (s(r[NAME]), s(r[RANK]), max(r[REC], r[CAT])) for r in srecs}
passive = {r[0] for r in srecs if r[ATTR] & ATTR_PASSIVE}

# Talent ranks, so the menu is abilities rather than 90 rows of talent passives. Talent.dbc holds up
# to 9 rank spell ids per talent starting at column 4 (the layout gen_auracatalog.py reads).
tblob = grab("Talent.dbc")
_, trc, tfc, trs, _ = struct.unpack("<4sIIII", tblob[:20])
talent_spells = set()
for i in range(trc):
    tr = struct.unpack_from(f"<{tfc}I", tblob, 20 + i * trs)
    for c in range(4, 13):
        if tr[c]:
            talent_spells.add(tr[c])

ablob = grab("SkillLineAbility.dbc")
_, arc, afc, ars, _ = struct.unpack("<4sIIII", ablob[:20])
arecs = [struct.unpack_from(f"<{afc}I", ablob, 20 + i * ars) for i in range(arc)]

CLASS_BY_ID = {1: "WARRIOR", 2: "PALADIN", 3: "HUNTER", 4: "ROGUE", 5: "PRIEST",
               6: "DEATHKNIGHT", 7: "SHAMAN", 8: "MAGE", 9: "WARLOCK", 11: "DRUID"}
votes = collections.defaultdict(collections.Counter)
for r in arecs:
    for cid, cname in CLASS_BY_ID.items():
        if r[4] & (1 << (cid - 1)):
            votes[r[1]][cname] += 1
skill2class = {k: v.most_common(1)[0][0] for k, v in votes.items() if v}


def ranknum(rk):
    m = re.search(r"(\d+)\s*$", rk or "")
    return int(m.group(1)) if m else 0


cand = collections.defaultdict(lambda: collections.defaultdict(set))
for r in arecs:
    cls = skill2class.get(r[1])
    if not cls:
        continue
    nm = spell.get(r[2])
    if nm and nm[0]:
        cand[cls][nm[0]].add(r[2])

if len(sys.argv) > 2:
    cls, name = sys.argv[1], sys.argv[2]
    print(f"=== {cls} :: {name} ===")
    for i in sorted(cand[cls].get(name, ())):
        nm, rk, cd = spell[i]
        print(f"  {i:6d}  rank={rk!r:12s} cd={cd:6d}ms")
    sys.exit(0)

with open("listing_nocd.txt", "w", encoding="utf-8") as f:
    for cls in sorted(cand):
        rows = []
        for nm, ids in cand[cls].items():
            # No candidate anywhere carries a real cooldown -> the whole NAME is a no-cooldown ability.
            if any(spell[i][2] > 1500 for i in ids):
                continue
            # Passives and talent ranks are the bulk of what is left, and none of them is pressable.
            if all(i in passive or i in talent_spells for i in ids):
                continue
            ranked = sorted((ranknum(spell[i][1]), i) for i in ids)
            nranks = len({r for r, _ in ranked})
            rows.append((nm, len(ids), nranks, ranked[0][1]))
        rows.sort()
        f.write(f"\n===== {cls} ===== ({len(rows)})\n")
        for nm, nids, nranks, first in rows:
            f.write(f"  {nids:3d} ids {nranks:2d} ranks  {first:6d}  {nm}\n")
print("wrote listing_nocd.txt")
