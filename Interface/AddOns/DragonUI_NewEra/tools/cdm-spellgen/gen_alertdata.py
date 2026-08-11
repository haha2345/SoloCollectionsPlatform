"""Generates modules/cooldownviewer/AlertData.lua — the curated Execute / Reactive tables the
visual-alert engine gates its "Usable" event on.

DIFFERENT QUERY from resolve.py, deliberately. That script picks ONE id per ability (the rank-1
castable) because the cooldown viewer tracks one entry per ability. The alert engine instead has to
recognise the ability at WHICHEVER rank the player actually casts, so this resolves EVERY rank.

It also cannot reuse resolve.py's ">1.5s cooldown" castability filter: Execute, Victory Rush and
Riposte have no cooldown at all.

The discriminator is instead SkillLineAbility class attribution, the same join resolve.py uses. Rank
text CANNOT be used for this: 3.3.5a's Spell.dbc gives Overpower rank 1 (7384) an EMPTY rank string
while its ranks 2-4 are labelled, and all four NPC copies of Riposte are likewise unranked — so any
"keep the ranked rows" rule both drops real rank 1s and keeps creature spells. Attribution drops the
impostors cleanly, because NPC spells appear in no player skill line.

Only the ABILITY NAMES and their mechanics are hand-authored; every id is resolved from the client.
"""
import os, json, struct, collections, re, sys
from mpyq import MPQArchive

# name -> target HP fraction below which the ability becomes castable.
# WotLK 3.3.5a has exactly three true execute-range abilities.
EXECUTE = {
    "WARRIOR": {"Execute": 0.20},
    "PALADIN": {"Hammer of Wrath": 0.20},
    # Kill Shot is the WotLK addition — no vanilla/TBC equivalent, so it is absent from the
    # upstream Era AlertData entirely.
    "HUNTER":  {"Kill Shot": 0.20},
}
# Warlock Drain Soul is deliberately absent: in WotLK it deals bonus damage below 25% but is
# castable at any health, so it has no "becomes usable" transition to alert on.

# Abilities usable only after a combat trigger enables a brief window.
REACTIVE = {
    "WARRIOR": ["Overpower",      # enabled by a target dodge
                "Revenge",        # enabled by a block, dodge or parry
                "Victory Rush"],  # enabled by killing an XP/honor-granting target
    "ROGUE":   ["Riposte"],       # enabled by a parry
    "HUNTER":  ["Counterattack"], # enabled by a parry
}
# Hunter Mongoose Bite is deliberately absent. It is reactive (dodge-gated) in vanilla and TBC —
# which is why upstream's Era table lists it — but patch 3.1.0 removed the dodge requirement, so on
# 3.3.5a it is castable on cooldown like any other shot. Listing it would flash the icon every time
# it came up, which is precisely the "every ready spell flashes" behaviour the engine exists to
# avoid. Excluded on the mechanic, not on the id.

RANKED = re.compile(r"(\d+)\s*$")
DATA = r"D:/Project Reforged 3.3.5a/Data/enUS"
CLASS_BY_ID = {1: "WARRIOR", 2: "PALADIN", 3: "HUNTER", 4: "ROGUE", 5: "PRIEST", 6: "DEATHKNIGHT",
               7: "SHAMAN", 8: "MAGE", 9: "WARLOCK", 11: "DRUID"}


def grab(name):
    """Later locale archives win, matching resolve.py."""
    best = None
    for archive in ["locale-enUS.MPQ", "patch-enUS.MPQ", "patch-enUS-2.MPQ", "patch-enUS-3.MPQ"]:
        path = os.path.join(DATA, archive)
        if os.path.exists(path):
            try:
                blob = MPQArchive(path).read_file("DBFilesClient\\" + name)
                if blob:
                    best = blob
            except Exception:
                pass
    return best


def class_candidates():
    """class -> name -> {spell ids}, from the SkillLineAbility join."""
    blob = grab("SkillLineAbility.dbc")
    if not blob:
        sys.exit("SkillLineAbility.dbc not readable")
    _, rc, fc, rs, _ = struct.unpack("<4sIIII", blob[:20])
    recs = [struct.unpack_from(f"<{fc}I", blob, 20 + i * rs) for i in range(rc)]

    votes = collections.defaultdict(collections.Counter)
    for r in recs:
        for cid, cname in CLASS_BY_ID.items():
            if r[4] & (1 << (cid - 1)):
                votes[r[1]][cname] += 1
    skill2class = {k: v.most_common(1)[0][0] for k, v in votes.items() if v}
    return recs, skill2class


def main():
    try:
        spells = json.load(open("spells.json", encoding="utf-8"))
    except FileNotFoundError:
        sys.exit("spells.json missing — run dbc.py first")
    # spells.json is keyed by stringified id: [name, rank]
    byid = {int(k): v for k, v in spells.items()}

    recs, skill2class = class_candidates()
    cand = collections.defaultdict(lambda: collections.defaultdict(set))
    for r in recs:
        cls = skill2class.get(r[1])
        row = byid.get(r[2])
        if cls and row and row[0]:
            cand[cls][row[0]].add(r[2])

    def resolve(cls, name):
        ids = cand.get(cls, {}).get(name)
        if not ids:
            sys.exit(f"FATAL: '{name}' resolved to no {cls} spell ids")
        got = []
        for sid in ids:
            m = RANKED.search(byid[sid][1] or "")
            got.append((int(m.group(1)) if m else 0, sid))
        # If the ability has real ranks, drop any unranked sibling — that is the triggered
        # sub-spell, which shares the name and is attributed to the same class (Warrior Execute
        # 20647, the damage component, sits in skill line 256). Safe ONLY after attribution: run
        # against the raw DBC this same rule discards genuinely-unranked rank 1s such as Overpower
        # 7384, whose higher ranks exist as spells but appear in no skill line on 3.3.5a.
        if any(r > 0 for r, _ in got):
            got = [(r, i) for r, i in got if r > 0]
        return sorted(set(got))

    def ranklabel(r):
        # Rank 0 means the DBC carries no rank string. That is NOT always "single rank": Overpower
        # 7384 is genuinely rank 1 but unlabelled, so say what the data says and nothing more.
        return f"Rank {r}" if r else "unranked"

    out = []
    out.append("""-- DragonUI_NewEra/modules/cooldownviewer/AlertData.lua — GENERATED, DO NOT HAND-EDIT.
--
-- Curated data for the visual-alert engine's "Usable" event (Alerts.lua). A Usable alert flashes a
-- spell ONLY if it appears in one of these tables — retail does not flash every ready spell, and
-- neither do we. Every id below is resolved from this client's own Spell.dbc; only the ability
-- NAMES and their mechanics are hand-authored. Regenerate with tools/cdm-spellgen/gen_alertdata.py.
--
-- Keyed by EVERY rank, because the engine has to recognise the ability at whichever rank the player
-- actually casts — our curated lists key rank 1, but the item's _rankCDIDs carries the learned ones
-- and a custom list may hold any of them.
--
-- COVERAGE NOTE: an entry here only ever fires if the spell is present in a viewer. Of the abilities
-- below, Hammer of Wrath, Kill Shot, Overpower and Revenge are in the curated Essential/Utility
-- lists; Execute, Victory Rush, Riposte and Counterattack are NOT, because those lists are built
-- from abilities with a real cooldown and these four have none. They stay listed so they work the
-- moment a custom list adds them.

local NE = DragonUI_NewEra
NE.cooldownviewer = NE.cooldownviewer or {}
local M = NE.cooldownviewer
M.alertdata = M.alertdata or {}
local A = M.alertdata

-- EXECUTE = { [spellID] = hpFraction } — castable only below a target health fraction.
A.EXECUTE = {""")

    for cls in sorted(EXECUTE):
        for name, frac in sorted(EXECUTE[cls].items()):
            got = resolve(cls, name)
            out.append(f"  -- {cls.title()} — {name} (target below {int(frac*100)}% health)")
            for r, sid in got:
                out.append(f"  [{sid}] = {frac:.2f},   -- {ranklabel(r)}")
    out.append("}")
    out.append("")
    out.append("-- REACTIVE = { [spellID] = true } — usable only after a combat trigger opens a window.")
    out.append("A.REACTIVE = {")

    TRIGGER = {
        "Overpower": "target dodge",
        "Revenge": "block, dodge or parry",
        "Victory Rush": "killing an XP/honor-granting target",
        "Riposte": "parry",
        "Counterattack": "parry",
    }
    for cls in sorted(REACTIVE):
        for name in REACTIVE[cls]:
            got = resolve(cls, name)
            out.append(f"  -- {cls.title()} — {name} (enabled by a {TRIGGER[name]})")
            for r, sid in got:
                out.append(f"  [{sid}] = true,   -- {ranklabel(r)}")
    out.append("}")

    out.append('''
-- Execute HP fraction for a spell: the id itself, then any known rank (the item caches learned
-- ranks in _rankCDIDs). nil for non-execute spells, which makes the engine skip the branch.
function A.ExecuteThreshold(spellID, rankIDs)
  if spellID and A.EXECUTE[spellID] then return A.EXECUTE[spellID] end
  if rankIDs then
    for _, id in ipairs(rankIDs) do
      if A.EXECUTE[id] then return A.EXECUTE[id] end
    end
  end
  return nil
end

-- True if the spell, at any rank, is a curated reactive ability.
function A.IsReactive(spellID, rankIDs)
  if spellID and A.REACTIVE[spellID] then return true end
  if rankIDs then
    for _, id in ipairs(rankIDs) do
      if A.REACTIVE[id] then return true end
    end
  end
  return false
end''')

    path = "../../modules/cooldownviewer/AlertData.lua"
    with open(path, "w", encoding="utf-8") as f:
        f.write("\n".join(out) + "\n")

    n_ex = sum(len(resolve(c, n)) for c in EXECUTE for n in EXECUTE[c])
    n_re = sum(len(resolve(c, n)) for c in REACTIVE for n in REACTIVE[c])
    print(f"wrote {path}")
    print(f"  EXECUTE  {n_ex} ids across {sum(len(v) for v in EXECUTE.values())} abilities")
    print(f"  REACTIVE {n_re} ids across {sum(len(v) for v in REACTIVE.values())} abilities")


if __name__ == "__main__":
    main()
