#!/usr/bin/env python3
"""Extract, review, and generate the WotLK toy action catalog."""

from __future__ import annotations

import argparse
import csv
import hashlib
import io
import json
import os
import re
import struct
import subprocess
import sys
from copy import deepcopy
from pathlib import Path
from typing import Any


SOURCE_BUILD = "3.3.5.12340"
COLLECTION_ID_MIN = 100000
COLLECTION_ID_MAX = 199999
ACTION_KINDS = {"SPELL_SELF", "SPELL_TARGET", "ITEM_USE", "CUSTOM_HANDLER"}
TARGET_POLICIES = {"NONE", "SELF", "OPTIONAL_UNIT", "REQUIRED_UNIT"}
COOLDOWN_SCOPES = {"NONE", "CHARACTER", "ACCOUNT", "HANDLER_NATIVE"}
REPLAY_POLICIES = {"REJECT_DUPLICATE", "IDEMPOTENT"}
LIFECYCLES = {"ACTIVE", "PREVIEW_ONLY", "DISABLED", "TOMBSTONE"}
RISK_FLAGS = {"TELEPORT", "ECONOMY", "ITEM_CREATE", "WORLD_OBJECT", "MATERIAL", "SEASONAL", "AREA", "COMBAT"}


class ToyCatalogError(ValueError):
    pass


def require(condition: bool, message: str) -> None:
    if not condition:
        raise ToyCatalogError(message)


def read_json(path: Path) -> Any:
    try:
        return json.loads(path.read_text(encoding="utf-8-sig"))
    except (OSError, json.JSONDecodeError) as exc:
        raise ToyCatalogError(f"cannot read JSON {path}: {exc}") from exc


def pretty_json(value: Any) -> str:
    return json.dumps(value, ensure_ascii=False, sort_keys=True, indent=2) + "\n"


def canonical_hash(value: Any) -> str:
    payload = json.dumps(value, ensure_ascii=False, sort_keys=True, separators=(",", ":")) + "\n"
    return hashlib.sha256(payload.encode("utf-8")).hexdigest()


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def verify_evidence_root(root: Path) -> dict[str, Path]:
    root = root.resolve()
    if os.name == "nt":
        require(root.drive.upper() == "F:", "toy evidence root must stay on F:")
    manifest = read_json(root / "evidence-manifest.json")
    require(manifest.get("schemaVersion") == 1, "unsupported evidence manifest schema")
    members: dict[str, Path] = {}
    for entry in manifest.get("files", []):
        relative = str(entry.get("relativePath", "")).replace("\\", "/")
        require(relative and relative not in members, f"invalid or duplicate evidence path: {relative!r}")
        member = root / Path(relative)
        require(member.is_file(), f"missing evidence member: {relative}")
        require(member.stat().st_size == int(entry.get("size", -1)), f"evidence size drift: {relative}")
        require(sha256(member) == entry.get("sha256"), f"evidence hash drift: {relative}")
        members[relative] = member
    for required in ("dbc/Spell.dbc", "dbc/Item.dbc", "dbc/ItemDisplayInfo.dbc"):
        require(required in members, f"required toy evidence member is missing: {required}")
    canonical = "".join(
        f"{relative}\0{members[relative].stat().st_size}\0{sha256(members[relative])}\n"
        for relative in sorted(members)
    ).encode("utf-8")
    require(hashlib.sha256(canonical).hexdigest() == manifest.get("packHash"), "evidence pack hash is stale")
    return members


def read_dbc(path: Path) -> tuple[dict[str, int], list[tuple[int, ...]], bytes]:
    data = path.read_bytes()
    require(len(data) >= 20 and data[:4] == b"WDBC", f"not a WDBC file: {path}")
    rows, fields, record_size, string_size = struct.unpack_from("<4I", data, 4)
    require(record_size == fields * 4, f"unexpected DBC record size: {path}")
    records_end = 20 + rows * record_size
    require(records_end + string_size == len(data), f"truncated or extended DBC: {path}")
    records = [struct.unpack_from(f"<{fields}I", data, 20 + index * record_size) for index in range(rows)]
    return {"rows": rows, "fields": fields, "recordSize": record_size, "stringSize": string_size}, records, data[records_end:]


def dbc_string(block: bytes, offset: int) -> str:
    if offset <= 0 or offset >= len(block):
        return ""
    end = block.find(b"\0", offset)
    require(end >= 0, f"unterminated DBC string at {offset}")
    return block[offset:end].decode("utf-8", errors="replace")


def parse_world_database_info(config: Path) -> tuple[str, str, str, str, str]:
    text = config.read_text(encoding="utf-8-sig", errors="replace")
    match = re.search(r'^\s*WorldDatabaseInfo\s*=\s*"([^"]+)"', text, re.MULTILINE)
    require(match is not None, f"WorldDatabaseInfo missing from {config}")
    parts = match.group(1).split(";")
    require(len(parts) >= 5, "WorldDatabaseInfo has an unexpected format")
    return parts[0], parts[1], parts[2], parts[3], parts[4]


def mysql_rows(mysql: Path, config: Path, query: str) -> list[list[str]]:
    host, port, user, password, database = parse_world_database_info(config)
    environment = os.environ.copy()
    environment["MYSQL_PWD"] = password
    result = subprocess.run(
        [str(mysql), f"--host={host}", f"--port={port}", f"--user={user}", f"--database={database}",
         "--default-character-set=utf8mb4", "--batch", "--raw", "--skip-column-names", "--execute", query],
        check=False, capture_output=True, text=True, encoding="utf-8", errors="replace", env=environment,
    )
    require(result.returncode == 0, f"World DB query failed: {result.stderr.strip()}")
    return [line.split("\t") for line in result.stdout.splitlines() if line]


def parse_prototypes(path: Path) -> list[dict[str, Any]]:
    text = path.read_text(encoding="utf-8-sig")
    pattern = re.compile(
        r'\{\s*id\s*=\s*(\d+),\s*itemId\s*=\s*(\d+),\s*spellId\s*=\s*(\d+),\s*'
        r'name\s*=\s*"([^"]+)",.*?source\s*=\s*"([^"]+)"', re.DOTALL,
    )
    rows = [
        {"legacyId": int(match.group(1)), "itemId": int(match.group(2)), "spellId": int(match.group(3)),
         "name_zhCN": match.group(4), "legacySource_zhCN": match.group(5)}
        for match in pattern.finditer(text)
    ]
    require(len(rows) == 36, f"expected exactly 36 legacy toy prototypes, found {len(rows)}")
    require([row["legacyId"] for row in rows] == list(range(1, 37)), "legacy toy prototype IDs are not contiguous")
    require(len({row["itemId"] for row in rows}) == 36, "legacy toy item IDs are not unique")
    return rows


def extract(repo_root: Path, evidence_root: Path, output: Path, mysql: Path, config: Path) -> dict[str, Any]:
    members = verify_evidence_root(evidence_root)
    spell_header, spell_rows, spell_strings = read_dbc(members["dbc/Spell.dbc"])
    item_header, item_rows, _ = read_dbc(members["dbc/Item.dbc"])
    display_header, display_rows, _ = read_dbc(members["dbc/ItemDisplayInfo.dbc"])
    require(spell_header["fields"] == 234, "Spell.dbc schema is not 3.3.5a")
    prototypes = parse_prototypes(repo_root / "addon/SoloCollections/Data/Toys.lua")
    spells = {int(row[0]): row for row in spell_rows}
    client_items = {int(row[0]) for row in item_rows}
    display_ids = {int(row[0]) for row in display_rows}
    item_ids = ",".join(str(row["itemId"]) for row in prototypes)
    db_items: dict[int, dict[str, Any]] = {}
    query = (
        "SELECT entry,COALESCE(name,''),displayid,class,subclass,InventoryType,stackable,maxcount,"
        "RequiredSkill,RequiredSkillRank,requiredspell,spellid_1,spelltrigger_1,spellcharges_1,"
        "spellcooldown_1,spellcategory_1,spellcategorycooldown_1 FROM item_template "
        f"WHERE entry IN ({item_ids})"
    )
    for values in mysql_rows(mysql, config, query):
        numbers = [int(value) for value in values[2:]]
        db_items[int(values[0])] = {
            "itemId": int(values[0]), "name_zhCN": values[1], "displayId": numbers[0],
            "class": numbers[1], "subclass": numbers[2], "inventoryType": numbers[3],
            "stackable": numbers[4], "maxCount": numbers[5], "requiredSkill": numbers[6],
            "requiredSkillRank": numbers[7], "requiredSpell": numbers[8], "itemSpellId": numbers[9],
            "spellTrigger": numbers[10], "spellCharges": numbers[11], "spellCooldownMs": numbers[12],
            "spellCategory": numbers[13], "spellCategoryCooldownMs": numbers[14],
        }
    spell_ids = ",".join(str(row["spellId"]) for row in prototypes)
    script_names: dict[int, list[str]] = {}
    for values in mysql_rows(mysql, config, f"SELECT spell_id,ScriptName FROM spell_script_names WHERE spell_id IN ({spell_ids}) ORDER BY spell_id,ScriptName"):
        script_names.setdefault(int(values[0]), []).append(values[1])
    candidates = []
    for prototype in prototypes:
        spell = spells.get(prototype["spellId"])
        item = db_items.get(prototype["itemId"])
        require(spell is not None, f"legacy toy references missing Spell.dbc row: {prototype['spellId']}")
        require(item is not None, f"legacy toy references missing item_template row: {prototype['itemId']}")
        localized_names = [dbc_string(spell_strings, int(spell[index])) for index in range(136, 152)]
        candidates.append({
            **prototype,
            "clientItemPresent": prototype["itemId"] in client_items,
            "clientDisplayPresent": item["displayId"] in display_ids,
            "item": item,
            "spell": {
                "spellId": prototype["spellId"],
                "name": next((value for value in localized_names if value), f"Spell {prototype['spellId']}"),
                "effects": [int(spell[71 + index]) for index in range(3)],
                "implicitTargetsA": [int(spell[95 + index]) for index in range(3)],
                "implicitTargetsB": [int(spell[98 + index]) for index in range(3)],
                "miscValues": [struct.unpack("<i", struct.pack("<I", int(spell[110 + index])))[0] for index in range(3)],
                "scriptNames": script_names.get(prototype["spellId"], []),
            },
        })
    basis = {"candidates": candidates}
    evidence = {
        "schemaVersion": 1,
        "sourceBuild": SOURCE_BUILD,
        "reviewMethod": "LEGACY_36_ITEM_SPELL_EXACT_REVIEW",
        "sources": {
            "Spell.dbc": sha256(members["dbc/Spell.dbc"]),
            "Item.dbc": sha256(members["dbc/Item.dbc"]),
            "ItemDisplayInfo.dbc": sha256(members["dbc/ItemDisplayInfo.dbc"]),
            "worldDatabase": "runtime World DB (credentials omitted)",
            "legacyPrototype": sha256(repo_root / "addon/SoloCollections/Data/Toys.lua"),
        },
        "counts": {"legacyPrototypes": len(candidates), "clientItemsPresent": sum(row["clientItemPresent"] for row in candidates),
                   "clientDisplaysPresent": sum(row["clientDisplayPresent"] for row in candidates)},
        **basis,
    }
    evidence["candidateHash"] = canonical_hash(basis)
    output.mkdir(parents=True, exist_ok=True)
    (output / "evidence.json").write_text(pretty_json(evidence), encoding="utf-8", newline="\n")
    write_candidate_csv(output / "toy-candidates.csv", candidates)
    print(f"toy candidates: {len(candidates)}")
    print(f"candidate hash: {evidence['candidateHash']}")
    return evidence


def csv_text(fieldnames: list[str], rows: list[dict[str, Any]]) -> str:
    output = io.StringIO(newline="")
    writer = csv.DictWriter(output, fieldnames=fieldnames, lineterminator="\n")
    writer.writeheader()
    writer.writerows(rows)
    return output.getvalue()


def write_candidate_csv(path: Path, candidates: list[dict[str, Any]]) -> None:
    rows = [{
        "legacyId": row["legacyId"], "itemId": row["itemId"], "spellId": row["spellId"],
        "name_zhCN": row["name_zhCN"], "worldName_zhCN": row["item"]["name_zhCN"],
        "effects": ";".join(map(str, row["spell"]["effects"])),
        "scriptNames": ";".join(row["spell"]["scriptNames"]),
        "requiredSkill": row["item"]["requiredSkill"], "spellCharges": row["item"]["spellCharges"],
        "clientItemPresent": str(row["clientItemPresent"]).lower(),
        "clientDisplayPresent": str(row["clientDisplayPresent"]).lower(),
    } for row in candidates]
    path.write_text(csv_text(list(rows[0]), rows), encoding="utf-8", newline="\n")


def load_policy(repo_root: Path, evidence: dict[str, Any]) -> dict[str, Any]:
    policy = read_json(repo_root / "catalog/review/toys/review-policy.json")
    require(policy.get("schemaVersion") == 1, "unsupported toy review policy schema")
    require(policy.get("candidateHash") == evidence.get("candidateHash"), "toy candidate hash changed; explicit review required")
    decisions = policy.get("decisions")
    require(isinstance(decisions, list), "toy review decisions are missing")
    indexed = {int(row["itemId"]): row for row in decisions}
    require(len(indexed) == len(decisions), "duplicate toy review itemId")
    expected = {int(row["itemId"]) for row in evidence["candidates"]}
    require(set(indexed) == expected, "accepted + excluded + deferred must cover all 36 toy candidates")
    for decision in decisions:
        require(decision.get("decision") in {"accepted", "excluded", "deferred"}, f"invalid toy decision: {decision}")
        require(bool(decision.get("reasonCode")), f"toy decision lacks a reason: {decision}")
        flags = decision.get("riskFlags", [])
        require(isinstance(flags, list) and set(flags) <= RISK_FLAGS, f"invalid toy risk flags: {decision}")
        if decision["decision"] != "accepted":
            continue
        require(decision.get("unlockSource") == "ITEM_ACQUIRED", f"accepted toy lacks acquisition source: {decision}")
        require(decision.get("actionKind") in ACTION_KINDS, f"invalid toy action kind: {decision}")
        require(decision.get("targetPolicy") in TARGET_POLICIES, f"invalid toy target policy: {decision}")
        require(decision.get("cooldownScope") in COOLDOWN_SCOPES, f"invalid toy cooldown scope: {decision}")
        require(decision.get("replayPolicy") in REPLAY_POLICIES, f"invalid toy replay policy: {decision}")
        require(decision.get("catalogLifecycle") == "ACTIVE", f"first-batch toy is not active: {decision}")
        require(isinstance(decision.get("accountCooldownMs"), int) and decision["accountCooldownMs"] >= 0,
                f"invalid toy account cooldown: {decision}")
        require(decision["cooldownScope"] != "ACCOUNT" or decision["accountCooldownMs"] > 0,
                f"account-scoped toy lacks logical cooldown: {decision}")
        require(isinstance(decision.get("allowInCombat"), bool) and isinstance(decision.get("consumesMaterial"), bool),
                f"toy combat/material semantics are not explicit: {decision}")
        require(not decision["consumesMaterial"], f"material-consuming toy cannot enter first batch: {decision}")
        if decision["actionKind"] == "CUSTOM_HANDLER":
            require(bool(decision.get("customHandler")), f"custom toy handler missing: {decision}")
        else:
            require(not decision.get("customHandler"), f"non-custom toy declares a handler: {decision}")
    return policy


def render(repo_root: Path, evidence: dict[str, Any]) -> dict[Path, str]:
    policy = load_policy(repo_root, evidence)
    candidates = {int(row["itemId"]): row for row in evidence["candidates"]}
    decisions = {int(row["itemId"]): row for row in policy["decisions"]}
    ids_path = repo_root / "catalog/ids.json"
    ids = read_json(ids_path)
    reservations = ids["reservations"]["collections"]
    by_key = {row["key"]: row for row in reservations}
    used_ids = {int(row["id"]) for row in reservations}
    next_ordinal = max(int(row["ordinal"]) for row in reservations) + 1
    old_csv = repo_root / "catalog/source/collections/toys.csv"
    with old_csv.open(encoding="utf-8-sig", newline="") as handle:
        old_rows = list(csv.DictReader(handle))
    old_by_item = {int(row["sourceId"]): row for row in old_rows}
    collection_rows = []
    action_rows = []
    for item_id in sorted(decisions, key=lambda value: int(candidates[value]["legacyId"])):
        decision = decisions[item_id]
        if decision["decision"] != "accepted":
            continue
        candidate = candidates[item_id]
        require(candidate["clientItemPresent"] and candidate["clientDisplayPresent"], f"accepted toy lacks client resources: {item_id}")
        require(int(decision["spellId"]) == int(candidate["spellId"]), f"toy reviewed spell drift: {item_id}")
        key = str(decision["collectionKey"])
        old = old_by_item.get(item_id)
        if old:
            require(key == old["collectionKey"], f"existing toy key drift: {item_id}")
            collection_id = int(old["collectionId"])
            ordinal = int(old["ordinal"])
            name_en = old["name_enUS"]
            name_zh = old["name_zhCN"]
        else:
            reservation = by_key.get(key)
            if reservation is None:
                collection_id = next(value for value in range(COLLECTION_ID_MIN, COLLECTION_ID_MAX + 1) if value not in used_ids)
                used_ids.add(collection_id)
                reservation = {"id": collection_id, "key": key, "lifecycle": "active", "ordinal": next_ordinal}
                next_ordinal += 1
                reservations.append(reservation)
                by_key[key] = reservation
            collection_id = int(reservation["id"])
            ordinal = int(reservation["ordinal"])
            name_en = str(decision["name_enUS"])
            name_zh = str(decision["name_zhCN"])
        collection_rows.append({
            "typeKey": "toy", "collectionId": collection_id, "collectionKey": key, "ordinal": ordinal,
            "lifecycle": "active", "name_enUS": name_en, "name_zhCN": name_zh, "policyKey": "unrestricted",
            "sourceBuild": SOURCE_BUILD, "sourceKind": "item", "sourceId": item_id,
            "actionKind": decision["actionKind"], "actionId": int(decision["spellId"]),
            "assetReady": "true", "assetProfile": "wotlk_native", "aliases": "",
        })
        action_rows.append({
            "collectionId": collection_id, "collectionKey": key, "ordinal": ordinal, "itemId": item_id,
            "unlockSource": decision["unlockSource"], "actionKind": decision["actionKind"],
            "spellId": int(decision["spellId"]), "targetPolicy": decision["targetPolicy"],
            "cooldownScope": decision["cooldownScope"], "accountCooldownMs": int(decision["accountCooldownMs"]),
            "allowInCombat": decision["allowInCombat"], "consumesMaterial": decision["consumesMaterial"],
            "customHandler": decision.get("customHandler", ""), "replayPolicy": decision["replayPolicy"],
            "riskFlags": decision.get("riskFlags", []), "catalogLifecycle": decision["catalogLifecycle"],
        })
    require({row["collectionId"] for row in collection_rows if row["sourceId"] in {35275, 21713, 33223, 45984}} ==
            {100305, 100306, 100307, 100308}, "existing toy IDs changed")
    require(len({row["collectionId"] for row in collection_rows}) == len(collection_rows), "duplicate toy collection ID")
    require(len({row["collectionKey"] for row in collection_rows}) == len(collection_rows), "duplicate toy collection key")
    exclusions = [{
        "legacyId": candidates[item_id]["legacyId"], "itemId": item_id, "spellId": candidates[item_id]["spellId"],
        "name_zhCN": candidates[item_id]["name_zhCN"], "decision": decisions[item_id]["decision"],
        "reasonCode": decisions[item_id]["reasonCode"], "riskFlags": ";".join(decisions[item_id].get("riskFlags", [])),
    } for item_id in decisions if decisions[item_id]["decision"] != "accepted"]
    candidate_rows = [{
        "legacyId": row["legacyId"], "itemId": row["itemId"], "spellId": row["spellId"],
        "name_zhCN": row["name_zhCN"], "worldName_zhCN": row["item"]["name_zhCN"],
        "effects": ";".join(map(str, row["spell"]["effects"])), "scriptNames": ";".join(row["spell"]["scriptNames"]),
        "requiredSkill": row["item"]["requiredSkill"], "spellCharges": row["item"]["spellCharges"],
        "clientItemPresent": str(row["clientItemPresent"]).lower(), "clientDisplayPresent": str(row["clientDisplayPresent"]).lower(),
    } for row in evidence["candidates"]]
    return {
        ids_path: pretty_json(ids),
        old_csv: csv_text(list(collection_rows[0]), collection_rows),
        repo_root / "catalog/source/toy_actions.json": pretty_json({"schemaVersion": 2, "entries": action_rows}),
        repo_root / "catalog/review/toys/evidence.json": pretty_json(evidence),
        repo_root / "catalog/generated/toy-candidates.csv": csv_text(list(candidate_rows[0]), candidate_rows),
        repo_root / "catalog/generated/toy-exclusions.csv": csv_text(list(exclusions[0]), exclusions),
    }


def generate(repo_root: Path, evidence_path: Path, check: bool) -> dict[str, int]:
    evidence = read_json(evidence_path)
    require(evidence.get("schemaVersion") == 1, "unsupported toy evidence schema")
    require(evidence.get("candidateHash") == canonical_hash({"candidates": evidence.get("candidates")}), "toy evidence hash drift")
    outputs = render(repo_root, evidence)
    drift = []
    for path, content in outputs.items():
        current = path.read_text(encoding="utf-8-sig") if path.exists() else None
        if current == content:
            continue
        if check:
            drift.append(path)
            continue
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(content, encoding="utf-8", newline="\n")
        print(f"generated: {path}")
    if drift:
        raise ToyCatalogError("generated toy outputs are stale: " + ", ".join(str(path) for path in drift))
    decisions = read_json(repo_root / "catalog/review/toys/review-policy.json")["decisions"]
    counts = {value: sum(row["decision"] == value for row in decisions) for value in ("accepted", "excluded", "deferred")}
    print(f"toy review: candidates={len(decisions)} accepted={counts['accepted']} excluded={counts['excluded']} deferred={counts['deferred']}")
    return counts


def verify_review_pack(repo_root: Path, evidence_root: Path) -> str:
    members = verify_evidence_root(evidence_root)
    tracked_bindings = {
        "repository/catalog/review/toys/evidence.json": repo_root / "catalog/review/toys/evidence.json",
        "repository/catalog/review/toys/review-policy.json": repo_root / "catalog/review/toys/review-policy.json",
        "repository/catalog/generated/toy-candidates.csv": repo_root / "catalog/generated/toy-candidates.csv",
        "repository/catalog/generated/toy-exclusions.csv": repo_root / "catalog/generated/toy-exclusions.csv",
    }
    for relative, tracked in tracked_bindings.items():
        require(tracked.is_file(), f"tracked toy review file is missing: {tracked}")
        require(relative in members, f"required toy evidence member is missing: {relative}")
        require(sha256(tracked) == sha256(members[relative]), f"toy review pack drift: {relative}")

    evidence = read_json(repo_root / "catalog/review/toys/evidence.json")
    for name in ("Spell.dbc", "Item.dbc", "ItemDisplayInfo.dbc"):
        require(evidence.get("sources", {}).get(name) == sha256(members[f"dbc/{name}"]), f"toy source evidence drift: {name}")
    manifest = read_json(evidence_root / "evidence-manifest.json")
    return str(manifest["packHash"])


def verify_source_evidence(repo_root: Path, evidence_root: Path) -> None:
    verify_review_pack(repo_root, evidence_root)


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("command", choices=("extract", "generate", "check"))
    parser.add_argument("--repo-root", type=Path, default=Path(__file__).resolve().parents[2])
    parser.add_argument("--evidence-root", type=Path)
    parser.add_argument("--evidence", type=Path)
    parser.add_argument("--out", type=Path)
    parser.add_argument("--mysql", type=Path)
    parser.add_argument("--worldserver-config", type=Path)
    args = parser.parse_args(argv)
    try:
        repo_root = args.repo_root.resolve()
        if args.command == "extract":
            require(args.evidence_root and args.out and args.mysql and args.worldserver_config,
                    "extract requires --evidence-root, --out, --mysql and --worldserver-config")
            extract(repo_root, args.evidence_root.resolve(), args.out.resolve(), args.mysql.resolve(), args.worldserver_config.resolve())
        else:
            evidence_path = (args.evidence or repo_root / "catalog/review/toys/evidence.json").resolve()
            if args.evidence_root:
                pack_hash = verify_review_pack(repo_root, args.evidence_root.resolve())
                print(f"toy evidence pack hash: {pack_hash}")
            generate(repo_root, evidence_path, args.command == "check")
        return 0
    except (ToyCatalogError, OSError) as exc:
        print(f"toy catalog error: {exc}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
