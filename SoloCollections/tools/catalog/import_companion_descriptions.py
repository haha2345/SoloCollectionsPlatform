#!/usr/bin/env python3
"""Import traceable zhCN BattlePetSpecies descriptions for known companions."""

from __future__ import annotations

import argparse
import csv
import hashlib
import io
import json
import urllib.request
from pathlib import Path


DEFAULT_BUILD = "7.3.5.26972"
DEFAULT_URL = "https://wago.tools/db2/BattlePetSpecies/csv?build={build}&locale=zhCN"


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--repo-root", type=Path, default=Path(__file__).resolve().parents[2])
    parser.add_argument("--build", default=DEFAULT_BUILD)
    parser.add_argument("--url")
    args = parser.parse_args()

    root = args.repo_root.resolve()
    url = args.url or DEFAULT_URL.format(build=args.build)
    request = urllib.request.Request(url, headers={"User-Agent": "SoloCollectionsCatalog/1.0"})
    with urllib.request.urlopen(request, timeout=60) as response:
        payload = response.read()
    rows = list(csv.DictReader(io.StringIO(payload.decode("utf-8-sig"))))
    by_creature: dict[int, list[dict[str, str]]] = {}
    for row in rows:
        by_creature.setdefault(int(row["CreatureID"]), []).append(row)

    actions = json.loads((root / "catalog/source/companion_actions.json").read_text(encoding="utf-8"))["entries"]
    entries = []
    missing = []
    for action in actions:
        creature = int(action["previewCreatureEntry"])
        descriptions = {
            row["Description_lang"].strip(): row
            for row in by_creature.get(creature, [])
            if row["Description_lang"].strip()
        }
        if not descriptions:
            missing.append(int(action["collectionId"]))
            continue
        if len(descriptions) != 1:
            raise ValueError(f"ambiguous BattlePetSpecies description for creature {creature}")
        description, row = next(iter(descriptions.items()))
        entries.append({
            "collectionId": int(action["collectionId"]),
            "creatureEntry": creature,
            "spellId": int(action["canonicalSpellId"]),
            "descriptionZhCN": description,
            "descriptionStatus": "OFFICIAL_ZHCN_BATTLE_PET_SPECIES",
            "sourceBuild": args.build,
            "sourceRowId": int(row["ID"]),
        })

    output = {
        "schemaVersion": 1,
        "locale": "zhCN",
        "sourceTable": "BattlePetSpecies",
        "sourceBuild": args.build,
        "sourceUrl": url,
        "sourcePayloadSha256": hashlib.sha256(payload).hexdigest(),
        "matchedCount": len(entries),
        "missingCollectionIds": missing,
        "entries": entries,
    }
    target = root / "catalog/source/companion_descriptions_zhCN.json"
    target.write_text(json.dumps(output, ensure_ascii=False, sort_keys=True, indent=2) + "\n", encoding="utf-8", newline="\n")
    print(f"wrote {target}: matched={len(entries)} missing={len(missing)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
