"""Independently re-verify every ID in the generated seed straight from Spell.dbc:
the id must exist, its name must match the trailing comment, and it must carry a real cooldown."""
import json, re, sys
spells = {int(k): tuple(v) for k, v in json.load(open("spells.json", encoding="utf-8")).items()}
import os, struct
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
blob = grab("Spell.dbc")
_, rc, fc, rs, _ = struct.unpack("<4sIIII", blob[:20])
recs = {}
for i in range(rc):
    r = struct.unpack_from(f"<{fc}I", blob, 20 + i*rs)
    recs[r[0]] = r

path = r"D:/Project Reforged 3.3.5a/Interface/AddOns/DragonUI_NewEra/modules/cooldownviewer/CdmSeedWotLK.lua"
bad = 0; n = 0; ids = []
# Which table we are inside. The rotation list is the ONE place a zero cooldown is correct — that is
# what it is for — so the check is relaxed there and nowhere else. Tracking the section rather than
# dropping the assertion outright is the whole reason the seed emits three tables instead of two.
section = None
starter_ids = []
for line in open(path, encoding="utf-8"):
    if line.startswith("local ") and line.rstrip().endswith("= {"):
        section = line.split()[1]
    m = re.match(r"\s+(\d+),\s+--\s+(.+?)\s*$", line)
    if not m: continue
    n += 1
    sid, want = int(m.group(1)), m.group(2)
    # The starter table RE-LISTS ids from the three tables above — that is what it is, a per-spec
    # subset of the class list — so duplicates are the point and a cooldown says nothing. Its own
    # invariant is checked after the loop: every starter id must exist in one of those tables, or it
    # would enable a row the picker has never heard of.
    if section == "STARTER_BY_CLASS":
        starter_ids.append((sid, want))
        got = spells.get(sid)
        if not got:
            print(f"  MISSING {sid} ({want})"); bad += 1
        elif got[0] != want:
            print(f"  NAME MISMATCH {sid}: file says {want!r}, dbc says {got[0]!r}"); bad += 1
        continue
    ids.append(sid)
    got = spells.get(sid)
    if not got:
        print(f"  MISSING {sid} ({want})"); bad += 1; continue
    if got[0] != want:
        print(f"  NAME MISMATCH {sid}: file says {want!r}, dbc says {got[0]!r}"); bad += 1; continue
    cd = max(recs[sid][29], recs[sid][30])
    if cd <= 1500 and section != "ROTATION_ADD":
        print(f"  NO COOLDOWN {sid} ({want}) cd={cd}ms"); bad += 1
    if cd > 1500 and section == "ROTATION_ADD":
        print(f"  HAS A COOLDOWN {sid} ({want}) cd={cd}ms -- belongs in the cooldown lists"); bad += 1
    if got[1] not in ("", "Rank 1"):
        print(f"  NOT RANK 1 {sid} ({want}) rank={got[1]!r}"); bad += 1

dupes = {i for i in ids if ids.count(i) > 1}
if dupes:
    print(f"  DUPLICATE IDS: {sorted(dupes)}"); bad += 1

# The starter's own invariant. It only ever ENABLES rows, so an id that is in no list enables nothing
# and the starter silently does less than it says. ClassData's vanilla entries count too — a starter
# may legitimately name Mind Blast, which lives there and not in this file.
seed_ids = set(ids)
for line in open(r"D:/Project Reforged 3.3.5a/Interface/AddOns/DragonUI_NewEra/modules/cooldownviewer/ClassData.lua",
                encoding="utf-8"):
    m = re.match(r"\s+(\d+),\s*--", line)
    if m: seed_ids.add(int(m.group(1)))
for sid, want in starter_ids:
    if sid not in seed_ids:
        print(f"  STARTER ORPHAN {sid} ({want}) is in no curated list, so it would enable nothing")
        bad += 1
print(f"\nchecked {n} ids -> {'ALL VERIFIED' if bad == 0 else str(bad) + ' PROBLEM(S)'}")
sys.exit(1 if bad else 0)
