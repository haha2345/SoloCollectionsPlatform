from __future__ import annotations

import argparse
import csv
import hashlib
import json
import subprocess
from collections import defaultdict
from pathlib import Path
from typing import Any


COLLECTION_COLUMNS = [
    "typeKey", "collectionId", "collectionKey", "ordinal", "lifecycle",
    "name_enUS", "name_zhCN", "policyKey", "sourceBuild", "sourceKind",
    "sourceId", "actionKind", "actionId", "assetReady", "assetProfile", "aliases",
]
VISIBLE_INVENTORY_TYPES = {1, 3, 4, 5, 6, 7, 8, 9, 10, 13, 14, 15, 16, 17, 19, 20, 21, 22, 23, 25, 26}
SLOT_LABELS = {
    1: "HEAD", 3: "SHOULDER", 4: "SHIRT", 5: "CHEST", 6: "WAIST",
    7: "LEGS", 8: "FEET", 9: "WRIST", 10: "HANDS", 13: "MAINHAND",
    14: "OFFHAND", 15: "MAINHAND", 16: "BACK", 17: "MAINHAND",
    19: "TABARD", 20: "CHEST", 21: "MAINHAND", 22: "OFFHAND",
    23: "OFFHAND", 25: "MAINHAND", 26: "MAINHAND",
}
ARMOR_TYPES = {1: "CLOTH", 2: "LEATHER", 3: "MAIL", 4: "PLATE"}
WEAPON_TYPES = {
    0: "ONE_HAND_AXE", 1: "TWO_HAND_AXE", 2: "BOW", 3: "GUN",
    4: "ONE_HAND_MACE", 5: "TWO_HAND_MACE", 6: "POLEARM",
    7: "ONE_HAND_SWORD", 8: "TWO_HAND_SWORD", 10: "STAFF",
    13: "FIST_WEAPON", 15: "DAGGER", 16: "THROWN", 18: "CROSSBOW",
    19: "WAND", 20: "FISHING_POLE",
}
# Item-specific signature corrections belong here. The default signature is
# (displayId, normalized slot family, item class, item subclass); keeping the
# exception mechanism explicit prevents one-off compatibility fixes from being
# hidden in UI or runtime code.
SIGNATURE_OVERRIDES: dict[int, tuple[int, int, int, int]] = {}


def stable_json(value: Any) -> str:
    return json.dumps(value, ensure_ascii=False, sort_keys=True, separators=(",", ":"))


def mapping_hash(groups: list[dict[str, Any]]) -> str:
    basis = [{key: row[key] for key in (
        "appearanceId", "displayId", "slotFamily", "itemClass", "itemSubclass", "sourceItemIds", "lifecycle"
    )} for row in groups]
    return hashlib.sha256(stable_json(basis).encode("utf-8")).hexdigest()


def mysql_rows(args: argparse.Namespace) -> list[dict[str, Any]]:
    query = (
        "SELECT entry,REPLACE(REPLACE(name,CHAR(9),' '),CHAR(10),' '),displayid,class,subclass,"
        "InventoryType,AllowableClass,AllowableRace FROM item_template WHERE class IN (2,4) "
        "AND displayid>0 AND InventoryType IN (" + ",".join(map(str, sorted(VISIBLE_INVENTORY_TYPES))) + ") ORDER BY entry"
    )
    command = [
        str(args.mysql), "--protocol=tcp", f"--host={args.host}", f"--port={args.port}",
        f"--user={args.user}", f"--password={args.password}", f"--database={args.database}",
        "--batch", "--raw", "--skip-column-names", f"--execute={query}",
    ]
    completed = subprocess.run(command, check=True, capture_output=True, text=True, encoding="utf-8")
    rows: list[dict[str, Any]] = []
    for line_number, line in enumerate(completed.stdout.splitlines(), start=1):
        fields = line.split("\t")
        if len(fields) != 8:
            raise ValueError(f"unexpected item_template row {line_number}: {line!r}")
        entry, name, display, item_class, subclass, inventory, class_mask, race_mask = fields
        rows.append({
            "entry": int(entry), "name": name, "displayId": int(display), "itemClass": int(item_class),
            "itemSubclass": int(subclass), "inventoryType": int(inventory),
            "allowableClass": int(class_mask), "allowableRace": int(race_mask),
        })
    return rows


def slot_family(inventory_type: int) -> int:
    return 5 if inventory_type in {5, 20} else inventory_type


def collection_key(display_id: int, slot: int, item_class: int, subclass: int) -> str:
    return f"appearance.d{display_id}.s{slot}.c{item_class}.sc{subclass}"


def appearance_signature(row: dict[str, Any]) -> tuple[int, int, int, int]:
    return SIGNATURE_OVERRIDES.get(row["entry"], (
        row["displayId"], slot_family(row["inventoryType"]), row["itemClass"], row["itemSubclass"],
    ))


def build_groups(rows: list[dict[str, Any]], ids: dict[str, Any], previous: dict[str, Any]) -> list[dict[str, Any]]:
    grouped: dict[tuple[int, int, int, int], list[dict[str, Any]]] = defaultdict(list)
    for row in rows:
        grouped[appearance_signature(row)].append(row)

    reservations = ids["reservations"].setdefault("collections", [])
    reserved_by_key = {row["key"]: row for row in reservations}
    next_id = max(200_000, max((int(row["id"]) + 1 for row in reservations), default=200_000))
    next_ordinal = max((int(row["ordinal"]) + 1 for row in reservations), default=0)
    previous_by_key = {row["collectionKey"]: row for row in previous.get("groups", [])}
    groups: list[dict[str, Any]] = []

    for signature in sorted(grouped):
        display_id, slot, item_class, subclass = signature
        key = collection_key(*signature)
        reservation = reserved_by_key.get(key)
        if reservation is None:
            reservation = {"id": next_id, "key": key, "lifecycle": "active", "ordinal": next_ordinal}
            reservations.append(reservation)
            reserved_by_key[key] = reservation
            next_id += 1
            next_ordinal += 1
        sources = sorted(grouped[signature], key=lambda row: row["entry"])
        primary = sources[0]
        groups.append({
            "appearanceId": int(reservation["id"]), "collectionKey": key,
            "ordinal": int(reservation["ordinal"]), "lifecycle": "active",
            "displayId": display_id, "slotFamily": slot, "slotKey": SLOT_LABELS[slot],
            "itemClass": item_class, "itemSubclass": subclass,
            "compatibilityFamily": f"{item_class}:{subclass}",
            "primarySourceItemId": primary["entry"], "name": primary["name"],
            "allowableClass": primary["allowableClass"], "allowableRace": primary["allowableRace"],
            "sourceItemIds": [row["entry"] for row in sources],
        })

    active_keys = {row["collectionKey"] for row in groups}
    for key, old in previous_by_key.items():
        if key in active_keys:
            continue
        reservation = reserved_by_key[key]
        reservation["lifecycle"] = "tombstone"
        tombstone = dict(old)
        tombstone["lifecycle"] = "tombstone"
        tombstone["sourceItemIds"] = []
        tombstone["primarySourceItemId"] = 0
        groups.append(tombstone)

    reservations.sort(key=lambda row: int(row["ordinal"]))
    groups.sort(key=lambda row: int(row["ordinal"]))
    return groups


def aliases_for(group: dict[str, Any]) -> str:
    aliases = [f"item:{item_id}" for item_id in group["sourceItemIds"]]
    aliases += [f"slot:{group['slotKey']}", f"compat:{group['compatibilityFamily']}"]
    if group["itemClass"] == 4:
        aliases.append(f"armor:{'ALL' if group['slotKey'] == 'BACK' else ARMOR_TYPES.get(group['itemSubclass'], 'ALL')}")
    else:
        aliases.append(f"weapon:{WEAPON_TYPES.get(group['itemSubclass'], 'OTHER')}")
    return "|".join(aliases)


def csv_bytes(groups: list[dict[str, Any]]) -> bytes:
    from io import StringIO

    output = StringIO(newline="")
    writer = csv.DictWriter(output, fieldnames=COLLECTION_COLUMNS, lineterminator="\n")
    writer.writeheader()
    for group in groups:
        active = group["lifecycle"] == "active"
        writer.writerow({
            "typeKey": "appearance", "collectionId": group["appearanceId"],
            "collectionKey": group["collectionKey"], "ordinal": group["ordinal"],
            "lifecycle": group["lifecycle"], "name_enUS": group.get("name", group["collectionKey"]),
            "name_zhCN": group.get("name", group["collectionKey"]), "policyKey": "unrestricted",
            "sourceBuild": "3.3.5.12340", "sourceKind": "item", "sourceId": group["primarySourceItemId"],
            "actionKind": "APPLY", "actionId": group["primarySourceItemId"],
            "assetReady": "true" if active else "false", "assetProfile": "wotlk_native",
            "aliases": aliases_for(group) if active else "",
        })
    return output.getvalue().encode("utf-8")


def cpp_bytes(groups: list[dict[str, Any]]) -> bytes:
    active_groups = [group for group in groups if group["lifecycle"] == "active"]
    source_ids = [item_id for group in active_groups for item_id in group["sourceItemIds"]]
    lines = [
        "// Generated by tools/catalog/appearance_catalog.py. Do not edit.", "",
        "struct GeneratedAppearanceGroup", "{",
        "    std::uint32_t Id;", "    std::uint32_t DisplayId;", "    std::uint32_t SlotFamily;",
        "    std::uint32_t ItemClass;", "    std::uint32_t ItemSubclass;",
        "    std::uint32_t PrimarySourceItemId;", "    std::uint32_t SourceOffset;",
        "    std::uint32_t SourceCount;", "};", "",
        "static constexpr std::uint32_t GeneratedAppearanceSources[] = {",
    ]
    for offset in range(0, len(source_ids), 16):
        lines.append("    " + ", ".join(f"{item_id}u" for item_id in source_ids[offset:offset + 16]) + ",")
    lines += ["};", "", "static constexpr GeneratedAppearanceGroup GeneratedAppearanceGroups[] = {"]
    source_offset = 0
    for group in active_groups:
        source_count = len(group["sourceItemIds"])
        lines.append(
            "    { " + str(group["appearanceId"]) + "u, " +
            f"{group['displayId']}u, {group['slotFamily']}u, {group['itemClass']}u, {group['itemSubclass']}u, " +
            f"{group['primarySourceItemId']}u, {source_offset}u, {source_count}u }},"
        )
        source_offset += source_count
    lines += ["};", ""]
    return "\n".join(lines).encode("utf-8")


def write_or_check(path: Path, content: bytes, check: bool) -> None:
    if check:
        if not path.is_file() or path.read_bytes() != content:
            raise SystemExit(f"generated output drift: {path}")
        return
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(content)


def main() -> int:
    repo = Path(__file__).resolve().parents[2]
    parser = argparse.ArgumentParser(description="Generate stable canonical WotLK appearance groups.")
    parser.add_argument("--mysql", type=Path, required=True)
    parser.add_argument("--host", default="127.0.0.1")
    parser.add_argument("--port", type=int, default=3306)
    parser.add_argument("--user", default="acore")
    parser.add_argument("--password", required=True)
    parser.add_argument("--database", default="acore_world")
    parser.add_argument("--module-root", type=Path, default=repo.parent / "mod-solo-collections")
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args()

    module_root = args.module_root.resolve()
    if module_root.name != "mod-solo-collections" or not (module_root / "src").is_dir():
        raise SystemExit(f"invalid module root: {module_root}")
    ids_path = repo / "catalog" / "ids.json"
    output_json_path = repo / "catalog" / "generated" / "appearance-sources.json"
    ids = json.loads(ids_path.read_text(encoding="utf-8"))
    previous = json.loads(output_json_path.read_text(encoding="utf-8")) if output_json_path.is_file() else {}
    rows = mysql_rows(args)
    groups = build_groups(rows, ids, previous)
    catalog = {"schemaVersion": 1, "sourceBuild": "3.3.5.12340", "groups": groups}
    catalog["mappingHash"] = mapping_hash(groups)

    writes = {
        ids_path: (json.dumps(ids, ensure_ascii=False, indent=2, sort_keys=True) + "\n").encode("utf-8"),
        repo / "catalog" / "source" / "collections" / "appearances.csv": csv_bytes(groups),
        output_json_path: (json.dumps(catalog, ensure_ascii=False, indent=2, sort_keys=True) + "\n").encode("utf-8"),
        module_root / "data" / "generated" / "solo_collections_appearance_sources.json":
            (json.dumps(catalog, ensure_ascii=False, indent=2, sort_keys=True) + "\n").encode("utf-8"),
        module_root / "src" / "generated" / "SoloCollectionsAppearanceCatalog.inc": cpp_bytes(groups),
    }
    for path, content in writes.items():
        write_or_check(path, content, args.check)
    print(f"appearance groups={sum(row['lifecycle'] == 'active' for row in groups)} "
          f"sources={len(rows)} mappingHash={catalog['mappingHash']}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
