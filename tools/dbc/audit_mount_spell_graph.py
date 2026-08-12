#!/usr/bin/env python3
"""Generate a private DBC effect/aura/trigger graph for catalog mount actions."""

from __future__ import annotations

import argparse
import hashlib
import json
import re
import struct
from pathlib import Path


def read_spell_dbc(path: Path) -> tuple[dict[int, tuple[int, ...]], str]:
    data = path.read_bytes()
    if len(data) < 20 or data[:4] != b"WDBC":
        raise ValueError(f"not a WDBC file: {path}")
    rows, fields, record_size, string_size = struct.unpack_from("<4I", data, 4)
    if fields != 234 or record_size != fields * 4 or 20 + rows * record_size + string_size != len(data):
        raise ValueError(f"unexpected 3.3.5a Spell.dbc schema: {path}")
    records = {
        row[0]: row
        for row in (
            struct.unpack_from(f"<{fields}I", data, 20 + index * record_size)
            for index in range(rows)
        )
    }
    return records, hashlib.sha256(data).hexdigest()


def catalog_actions(path: Path) -> dict[int, dict[str, int | str]]:
    result: dict[int, dict[str, int | str]] = {}
    for line in path.read_text(encoding="utf-8").splitlines():
        match = re.search(
            r'\{CollectionId\{(\d+)u\}, "([^"]+)", .*?, .*?, .*?, \{.*?\}, .*?, '
            r'CatalogLifecycle::Active, true, true, true, .*?, (\d+)u, MountCapability::(\w+),',
            line,
        )
        if not match:
            continue
        collection_id, key, spell_id, capability = match.groups()
        if int(spell_id):
            result[int(spell_id)] = {
                "collectionId": int(collection_id),
                "key": key,
                "capability": capability,
            }
    return result


def signed(value: int) -> int:
    return struct.unpack("<i", struct.pack("<I", value))[0]


def node(row: tuple[int, ...]) -> dict[str, object]:
    effects = []
    for index in range(3):
        effect = row[72 + index]
        aura = row[95 + index]
        trigger = row[113 + index]
        if effect or aura or trigger:
            effects.append({
                "index": index,
                "effect": effect,
                "aura": aura,
                "basePoints": signed(row[80 + index]) + 1,
                "miscValue": signed(row[110 + index]),
                "triggerSpell": trigger,
            })
    return {"spellId": row[0], "attributes4": row[8], "effects": effects}


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--spell-dbc", type=Path, required=True)
    parser.add_argument("--catalog-inc", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()

    spells, source_hash = read_spell_dbc(args.spell_dbc)
    actions = catalog_actions(args.catalog_inc)
    nodes: dict[int, dict[str, object]] = {}
    edges: list[dict[str, int]] = []
    pending = list(actions)
    while pending:
        spell_id = pending.pop()
        if spell_id in nodes or spell_id not in spells:
            continue
        current = node(spells[spell_id])
        nodes[spell_id] = current
        for effect in current["effects"]:
            trigger = int(effect["triggerSpell"])
            if trigger:
                edges.append({"from": spell_id, "effectIndex": int(effect["index"]), "to": trigger})
                pending.append(trigger)

    payload = {
        "schemaVersion": 1,
        "source": {"path": str(args.spell_dbc), "sha256": source_hash},
        "catalogActionCount": len(actions),
        "catalogActions": actions,
        "nodes": [nodes[key] for key in sorted(nodes)],
        "triggerEdges": sorted(edges, key=lambda value: (value["from"], value["effectIndex"], value["to"])),
        "auraTypes": {
            "mounted": 78,
            "groundSpeed": [32, 130, 172],
            "flightSpeed": [206, 207, 208, 209, 210, 211],
        },
    }
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(payload, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(f"mount action graph: {args.output}")
    print(f"catalog actions: {len(actions)}; graph nodes: {len(nodes)}; trigger edges: {len(edges)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
