"""Extract + parse 3.3.5a Spell.dbc -> {id: (name, rank)}.

Locale archives hold the DBCs. Load order is locale-enUS then patch-enUS, -2, -3; later wins.
"""
import os, struct, glob
from mpyq import MPQArchive

DATA = r"D:/Project Reforged 3.3.5a/Data"
TARGET = "DBFilesClient\\Spell.dbc"

# lowest -> highest priority
LOCALE_ORDER = ["locale-enUS.MPQ", "patch-enUS.MPQ", "patch-enUS-2.MPQ", "patch-enUS-3.MPQ"]


def extract():
    best = None
    for name in LOCALE_ORDER:
        p = os.path.join(DATA, "enUS", name)
        if not os.path.exists(p):
            continue
        try:
            data = MPQArchive(p).read_file(TARGET)
        except Exception as e:
            print(f"  {name}: {e}")
            continue
        if data:
            best = (data, name)
            print(f"  {name}: {len(data):,} bytes")
    # A custom server could override Spell.dbc in the non-locale patches; report if so.
    for p in sorted(glob.glob(os.path.join(DATA, "*.MPQ")) + glob.glob(os.path.join(DATA, "*.mpq"))):
        try:
            d = MPQArchive(p).read_file(TARGET)
            if d:
                best = (d, os.path.basename(p))
                print(f"  OVERRIDE {os.path.basename(p)}: {len(d):,} bytes")
        except Exception:
            pass
    return best


def parse(blob):
    magic, rec_count, field_count, rec_size, sb_size = struct.unpack("<4sIIII", blob[:20])
    assert magic == b"WDBC", magic
    print(f"  records={rec_count:,} fields={field_count} recsize={rec_size} strblock={sb_size:,}")
    body_off = 20
    sb_off = body_off + rec_count * rec_size
    sb = blob[sb_off:sb_off + sb_size]

    def s(off):
        if off <= 0 or off >= len(sb):
            return ""
        end = sb.find(b"\0", off)
        return sb[off:end].decode("utf-8", "ignore")

    records = []
    for i in range(rec_count):
        o = body_off + i * rec_size
        records.append(struct.unpack_from(f"<{field_count}I", blob, o))

    # Auto-detect the SpellName column: the one where known ids give known names.
    ANCHORS = {133: "Fireball", 8092: "Mind Blast", 1449: "Arcane Explosion", 2050: "Lesser Heal"}
    by_id = {r[0]: r for r in records}
    name_col = None
    for c in range(1, field_count):
        ok = 0
        for sid, want in ANCHORS.items():
            r = by_id.get(sid)
            if r and s(r[c]) == want:
                ok += 1
        if ok == len(ANCHORS):
            name_col = c
            break
    if name_col is None:
        raise SystemExit("could not locate SpellName column")
    print(f"  SpellName column = {name_col}")

    # Rank sits in the next locale block: 16 locales + 1 flags word after the name block.
    rank_col = name_col + 17
    sample = s(by_id[8092][rank_col]) if 8092 in by_id else ""
    print(f"  Rank column = {rank_col} (spell 8092 rank = {sample!r})")

    out = {}
    for r in records:
        out[r[0]] = (s(r[name_col]), s(r[rank_col]))
    return out


if __name__ == "__main__":
    got = extract()
    if not got:
        raise SystemExit("Spell.dbc not found")
    blob, src = got
    print(f"\nusing {src}")
    spells = parse(blob)
    print(f"  parsed {len(spells):,} spells")
    import json
    with open("spells.json", "w", encoding="utf-8") as f:
        json.dump({str(k): v for k, v in spells.items()}, f)
    print("  wrote spells.json")
    for sid in (133, 8092, 47540, 53385, 49576):
        print(f"   {sid}: {spells.get(sid)}")
