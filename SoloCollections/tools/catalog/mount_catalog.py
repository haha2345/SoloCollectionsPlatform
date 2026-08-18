#!/usr/bin/env python3
"""Extract, review, and generate the authoritative WotLK mount catalog.

The extractor reads the currently deployed 3.3.5a DBC files and World DB.  It
writes sanitized evidence only; database credentials never enter the checkout.
Generation is deliberately separate and requires a review policy pinned to the
exact candidate hash, so changed source data cannot silently enter production.
"""

from __future__ import annotations

import argparse
import csv
import hashlib
import json
import os
import re
import struct
import subprocess
import sys
import unicodedata
from collections import defaultdict
from pathlib import Path
from typing import Any, Iterable


MOUNT_AURA = 78
MOUNT_SKILL_LINE = 777
MOUNT_SPEED_AURAS = {32, 130, 172}
FLIGHT_SPEED_AURAS = {206, 207, 208, 209, 210, 211}
REVIEW_METHOD = "EXACT_CREATURE_ENTRY_ONLY"
COLLECTION_ID_BASE = 100000
COLLECTION_COLUMNS = [
    "typeKey", "collectionId", "collectionKey", "ordinal", "lifecycle",
    "name_enUS", "name_zhCN", "policyKey", "sourceBuild", "sourceKind",
    "sourceId", "actionKind", "actionId", "assetReady", "assetProfile", "aliases",
]


class MountCatalogError(ValueError):
    pass


def require(condition: bool, message: str) -> None:
    if not condition:
        raise MountCatalogError(message)


def sha256_bytes(value: bytes) -> str:
    return hashlib.sha256(value).hexdigest()


def canonical_hash(value: Any) -> str:
    encoded = json.dumps(value, ensure_ascii=False, sort_keys=True, separators=(",", ":")).encode("utf-8")
    return sha256_bytes(encoded)


def read_json(path: Path) -> Any:
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as exc:
        raise MountCatalogError(f"cannot read JSON {path}: {exc}") from exc


def write_json(path: Path, value: Any) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(value, ensure_ascii=False, sort_keys=True, indent=2) + "\n", encoding="utf-8", newline="\n")


def read_dbc(path: Path) -> tuple[dict[str, int], list[tuple[int, ...]], bytes]:
    data = path.read_bytes()
    require(len(data) >= 20 and data[:4] == b"WDBC", f"not a WDBC file: {path}")
    rows, fields, record_size, string_size = struct.unpack_from("<4I", data, 4)
    require(record_size == fields * 4, f"unexpected DBC record size: {path}")
    records_end = 20 + rows * record_size
    require(records_end + string_size == len(data), f"truncated or extended DBC: {path}")
    records = [struct.unpack_from(f"<{fields}I", data, 20 + index * record_size) for index in range(rows)]
    return ({"rows": rows, "fields": fields, "recordSize": record_size, "stringSize": string_size}, records, data[records_end:])


def dbc_string(block: bytes, offset: int) -> str:
    if offset <= 0 or offset >= len(block):
        return ""
    end = block.find(b"\0", offset)
    require(end >= 0, f"unterminated DBC string at {offset}")
    return block[offset:end].decode("utf-8", errors="replace")


def signed(value: int) -> int:
    return struct.unpack("<i", struct.pack("<I", value))[0]


def parse_world_database_info(config: Path) -> tuple[str, str, str, str, str]:
    text = config.read_text(encoding="utf-8-sig", errors="replace")
    match = re.search(r'^\s*WorldDatabaseInfo\s*=\s*"([^"]+)"', text, re.MULTILINE)
    require(match is not None, f"WorldDatabaseInfo missing from {config}")
    parts = match.group(1).split(";")
    require(len(parts) >= 5, "WorldDatabaseInfo has an unexpected format")
    return parts[0], parts[1], parts[2], parts[3], parts[4]


def mysql_rows(mysql: Path, config: Path, query: str) -> list[list[str]]:
    host, port, user, password, database = parse_world_database_info(config)
    env = os.environ.copy()
    env["MYSQL_PWD"] = password
    result = subprocess.run(
        [str(mysql), f"--host={host}", f"--port={port}", f"--user={user}",
         f"--database={database}", "--batch", "--raw", "--skip-column-names", "--execute", query],
        check=False, capture_output=True, text=True, encoding="utf-8", errors="replace", env=env,
    )
    require(result.returncode == 0, f"World DB query failed: {result.stderr.strip()}")
    return [line.split("\t") for line in result.stdout.splitlines() if line]


def sql_ids(values: Iterable[int]) -> str:
    result = sorted(set(int(value) for value in values))
    require(result, "cannot query an empty ID set")
    return ",".join(str(value) for value in result)


def extract(args: argparse.Namespace) -> dict[str, Any]:
    spell_header, spell_rows, spell_strings = read_dbc(args.dbc_root / "Spell.dbc")
    skill_header, skill_rows, _ = read_dbc(args.dbc_root / "SkillLineAbility.dbc")
    display_header, display_rows, _ = read_dbc(args.dbc_root / "CreatureDisplayInfo.dbc")
    require(spell_header["fields"] == 234, "Spell.dbc schema is not 3.3.5a")
    require(skill_header["fields"] == 14, "SkillLineAbility.dbc schema is not 3.3.5a")
    display_ids = {row[0] for row in display_rows}

    skill_by_spell: dict[int, list[dict[str, int]]] = defaultdict(list)
    for row in skill_rows:
        skill_by_spell[row[2]].append({
            "recordId": row[0], "skillLine": row[1], "raceMask": row[3], "classMask": row[4],
            "minSkillRank": row[7], "supersededBySpell": row[8], "acquireMethod": row[9],
        })

    raw_candidates: list[dict[str, Any]] = []
    creature_ids: set[int] = set()
    for row in spell_rows:
        mount_effects = [index for index in range(3) if row[95 + index] == MOUNT_AURA]
        if not mount_effects:
            continue
        mounted_creatures = sorted({signed(row[110 + index]) for index in mount_effects if signed(row[110 + index]) > 0})
        creature_ids.update(mounted_creatures)
        speed_effects = []
        for index in range(3):
            aura = row[95 + index]
            if aura in MOUNT_SPEED_AURAS | FLIGHT_SPEED_AURAS:
                speed_effects.append({"aura": aura, "amount": signed(row[80 + index]) + 1})
        raw_candidates.append({
            "spellId": row[0], "name_enUS": dbc_string(spell_strings, row[136]),
            "spellIconId": row[133], "baseLevel": row[38], "spellLevel": row[39],
            "mountedCreatureIds": mounted_creatures, "speedEffects": speed_effects,
            "isFlying": any(effect["aura"] in FLIGHT_SPEED_AURAS for effect in speed_effects),
            "skillLineAbilities": sorted(skill_by_spell.get(row[0], []), key=lambda value: value["recordId"]),
        })

    creature_query = (
        "SELECT ct.entry,COALESCE(ct.name,''),COALESCE(ct.subname,''),"
        "GROUP_CONCAT(DISTINCT ctm.CreatureDisplayID ORDER BY ctm.CreatureDisplayID SEPARATOR ',') "
        "FROM creature_template ct LEFT JOIN creature_template_model ctm ON ctm.CreatureID=ct.entry "
        f"WHERE ct.entry IN ({sql_ids(creature_ids)}) GROUP BY ct.entry,ct.name,ct.subname"
    )
    creatures: dict[int, dict[str, Any]] = {}
    for row in mysql_rows(args.mysql, args.worldserver_config, creature_query):
        displays = [int(value) for value in row[3].split(",") if value and value != "NULL"]
        creatures[int(row[0])] = {
            "entry": int(row[0]), "name": row[1], "subname": row[2], "displayIds": displays,
            "displayResourcesPresent": bool(displays) and all(value in display_ids for value in displays),
        }

    spell_ids = {row["spellId"] for row in raw_candidates}
    ids = sql_ids(spell_ids)
    item_query = (
        "SELECT entry,name,RequiredSkill,RequiredSkillRank,AllowableClass,AllowableRace,"
        "spellid_1,spellid_2,spellid_3,spellid_4,spellid_5 FROM item_template WHERE " +
        " OR ".join(f"spellid_{index} IN ({ids})" for index in range(1, 6))
    )
    items_by_spell: dict[int, list[dict[str, Any]]] = defaultdict(list)
    for row in mysql_rows(args.mysql, args.worldserver_config, item_query):
        source = {
            "itemId": int(row[0]), "name": row[1], "requiredSkill": int(row[2]),
            "requiredSkillRank": int(row[3]), "allowableClass": int(row[4]), "allowableRace": int(row[5]),
        }
        for value in row[6:11]:
            if value not in {"", "0", "NULL"} and int(value) in spell_ids:
                items_by_spell[int(value)].append(source)

    quest_query = (
        "SELECT ID,LogTitle,RewardDisplaySpell,RewardSpell FROM quest_template "
        f"WHERE RewardDisplaySpell IN ({ids}) OR RewardSpell IN ({ids})"
    )
    quests_by_spell: dict[int, list[dict[str, Any]]] = defaultdict(list)
    for row in mysql_rows(args.mysql, args.worldserver_config, quest_query):
        for value in row[2:4]:
            if value not in {"", "0", "NULL"} and int(value) in spell_ids:
                quests_by_spell[int(value)].append({"questId": int(row[0]), "title": row[1]})

    trainer_query = (
        "SELECT ts.SpellId,ts.TrainerId,ts.MoneyCost,ts.ReqSkillLine,ts.ReqSkillRank "
        "FROM trainer_spell ts "
        f"WHERE ts.SpellId IN ({ids})"
    )
    trainers_by_spell: dict[int, list[dict[str, int]]] = defaultdict(list)
    for row in mysql_rows(args.mysql, args.worldserver_config, trainer_query):
        trainers_by_spell[int(row[0])].append({
            "trainerId": int(row[1]), "moneyCost": int(row[2]),
            "requiredSkill": int(row[3]), "requiredSkillRank": int(row[4]),
        })

    candidates: list[dict[str, Any]] = []
    for candidate in sorted(raw_candidates, key=lambda value: value["spellId"]):
        candidate["creatures"] = [creatures[value] for value in candidate["mountedCreatureIds"] if value in creatures]
        candidate["itemSources"] = sorted(items_by_spell[candidate["spellId"]], key=lambda value: value["itemId"])
        candidate["questSources"] = sorted(quests_by_spell[candidate["spellId"]], key=lambda value: value["questId"])
        candidate["trainerSources"] = sorted(trainers_by_spell[candidate["spellId"]], key=lambda value: value["trainerId"])
        candidates.append(candidate)

    basis = [{key: value for key, value in candidate.items() if key != "decision"} for candidate in candidates]
    evidence = {
        "schemaVersion": 1, "sourceBuild": "3.3.5.12340", "reviewMethod": REVIEW_METHOD,
        "sources": {
            "Spell.dbc": {**spell_header, "sha256": sha256_bytes((args.dbc_root / "Spell.dbc").read_bytes())},
            "SkillLineAbility.dbc": {**skill_header, "sha256": sha256_bytes((args.dbc_root / "SkillLineAbility.dbc").read_bytes())},
            "CreatureDisplayInfo.dbc": {**display_header, "sha256": sha256_bytes((args.dbc_root / "CreatureDisplayInfo.dbc").read_bytes())},
            "worldDatabase": "runtime World DB (credentials omitted)",
        },
        "candidateHash": canonical_hash(basis), "candidates": candidates,
    }
    write_json(args.evidence, evidence)
    print(f"mount evidence: {args.evidence}")
    print(f"mount candidates: {len(candidates)}")
    print(f"mount candidate hash: {evidence['candidateHash']}")
    return evidence


def slugify(value: str) -> str:
    normalized = unicodedata.normalize("NFKD", value).encode("ascii", "ignore").decode("ascii").lower()
    result = re.sub(r"[^a-z0-9]+", "_", normalized).strip("_")
    return result or "unnamed"


def structural_exclusion(candidate: dict[str, Any]) -> tuple[str, str] | None:
    if not any(row["skillLine"] == MOUNT_SKILL_LINE for row in candidate["skillLineAbilities"]):
        return "NOT_PLAYER_MOUNT_SKILL_LINE", "Spell is not listed in the client player-mount skill line."
    if not candidate["mountedCreatureIds"] or len(candidate["creatures"]) != len(candidate["mountedCreatureIds"]):
        return "MISSING_CREATURE_TEMPLATE", "Mounted creature template is missing."
    if not all(row["displayResourcesPresent"] for row in candidate["creatures"]):
        return "MISSING_DISPLAY_RESOURCE", "Creature display resource is missing from the current client data."
    return None


def review(evidence: dict[str, Any], policy: dict[str, Any]) -> tuple[list[dict[str, Any]], list[dict[str, Any]]]:
    require(evidence.get("reviewMethod") == REVIEW_METHOD, "unsupported evidence review method")
    require(policy.get("candidateHash") == evidence.get("candidateHash"), "candidate evidence changed; explicit re-review required")
    require(policy.get("groupingPolicy") == REVIEW_METHOD, "review policy may only group exact creature entries")
    manual = {int(row["spellId"]): row for row in policy.get("manualExclusions", [])}
    require(len(manual) == len(policy.get("manualExclusions", [])), "duplicate manual exclusion spellId")
    known_ids = {row["spellId"] for row in evidence["candidates"]}
    require(set(manual) <= known_ids, "manual exclusion references an unknown candidate")
    accepted: list[dict[str, Any]] = []
    excluded: list[dict[str, Any]] = []
    for candidate in evidence["candidates"]:
        decision = structural_exclusion(candidate)
        if decision is None and candidate["spellId"] in manual:
            entry = manual[candidate["spellId"]]
            decision = (entry["reasonCode"], entry["reason"])
        if decision is None:
            accepted.append(candidate)
        else:
            excluded.append({
                "spellId": candidate["spellId"], "name_enUS": candidate["name_enUS"],
                "reasonCode": decision[0], "reason": decision[1],
            })
    require(len(accepted) + len(excluded) == len(evidence["candidates"]), "review did not cover every candidate")
    return accepted, excluded


def load_existing_reservations(ids_path: Path) -> dict[str, dict[str, Any]]:
    data = read_json(ids_path)
    return {row["key"]: row for row in data["reservations"].get("collections", [])}


def build_groups(accepted: list[dict[str, Any]], existing: dict[str, dict[str, Any]]) -> list[dict[str, Any]]:
    grouped: dict[tuple[int, ...], list[dict[str, Any]]] = defaultdict(list)
    for candidate in accepted:
        key = tuple(candidate["mountedCreatureIds"])
        require(key, f"accepted spell {candidate['spellId']} has no mounted creature")
        grouped[key].append(candidate)

    preliminary: list[tuple[str, tuple[int, ...], list[dict[str, Any]]]] = []
    used_keys: set[str] = set()
    for creature_key, variants in sorted(grouped.items()):
        variants.sort(key=lambda value: value["spellId"])
        preferred = sorted(
            variants,
            key=lambda value: (
                not bool(value["itemSources"]),
                not bool(value["questSources"] or value["trainerSources"]),
                -value["spellId"],
            ),
        )[0]
        base = f"mount.{slugify(preferred['name_enUS'])}"
        collection_key = base if base not in used_keys else f"{base}.creature_{'_'.join(map(str, creature_key))}"
        while collection_key in used_keys:
            collection_key += "_variant"
        used_keys.add(collection_key)
        preliminary.append((collection_key, creature_key, variants))

    existing_ids = {int(row["id"]) for row in existing.values()}
    next_id = max([COLLECTION_ID_BASE - 1, *existing_ids]) + 1
    ordered = sorted(preliminary, key=lambda value: (existing.get(value[0], {}).get("ordinal", 1 << 30), value[0]))
    groups: list[dict[str, Any]] = []
    for ordinal, (collection_key, creature_key, variants) in enumerate(ordered):
        reservation = existing.get(collection_key)
        collection_id = int(reservation["id"]) if reservation else next_id
        if reservation is None:
            next_id += 1
        canonical = sorted(
            variants,
            key=lambda value: (not bool(value["itemSources"]), not bool(value["questSources"] or value["trainerSources"]), -value["spellId"]),
        )[0]
        localized_name = next((source["name"] for source in canonical["itemSources"] if source.get("name")), canonical["name_enUS"])
        groups.append({
            "collectionId": collection_id, "collectionKey": collection_key, "ordinal": ordinal,
            "name_enUS": canonical["name_enUS"], "name_zhCN": localized_name,
            "creatureIds": list(creature_key), "canonicalSpellId": canonical["spellId"],
            "unlockSpellIds": [row["spellId"] for row in variants],
            "actionVariants": [{
                "spellId": row["spellId"], "raceMasks": sorted({ability["raceMask"] for ability in row["skillLineAbilities"] if ability["skillLine"] == MOUNT_SKILL_LINE}),
                "classMasks": sorted({ability["classMask"] for ability in row["skillLineAbilities"] if ability["skillLine"] == MOUNT_SKILL_LINE}),
                "minimumRidingSkill": max(
                    [source["requiredSkillRank"] for source in row["itemSources"] if source["requiredSkill"] == 762] +
                    [source["requiredSkillRank"] for source in row["trainerSources"] if source["requiredSkill"] == 762] + [0]
                ),
                "isFlying": row["isFlying"], "speedEffects": row["speedEffects"],
                "sourceItemIds": [source["itemId"] for source in row["itemSources"]],
                "sourceQuestIds": [source["questId"] for source in row["questSources"]],
                "sourceTrainerIds": [source["trainerId"] for source in row["trainerSources"]],
            } for row in variants],
        })
    require(len({row["collectionId"] for row in groups}) == len(groups), "duplicate generated collectionId")
    return groups


def write_csv(path: Path, columns: list[str], rows: list[dict[str, Any]]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", encoding="utf-8", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=columns, lineterminator="\n")
        writer.writeheader()
        writer.writerows(rows)


def generate(args: argparse.Namespace) -> dict[str, Any]:
    evidence = read_json(args.evidence)
    policy = read_json(args.policy)
    accepted, excluded = review(evidence, policy)
    existing = load_existing_reservations(args.ids)
    groups = build_groups(accepted, existing)

    candidate_rows = []
    excluded_by_id = {row["spellId"]: row for row in excluded}
    collection_by_spell = {spell_id: group for group in groups for spell_id in group["unlockSpellIds"]}
    for candidate in evidence["candidates"]:
        group = collection_by_spell.get(candidate["spellId"])
        rejection = excluded_by_id.get(candidate["spellId"])
        candidate_rows.append({
            "spellId": candidate["spellId"], "name_enUS": candidate["name_enUS"],
            "creatureIds": "|".join(map(str, candidate["mountedCreatureIds"])),
            "skillLine777": "true" if any(row["skillLine"] == MOUNT_SKILL_LINE for row in candidate["skillLineAbilities"]) else "false",
            "hasItemSource": "true" if candidate["itemSources"] else "false",
            "hasQuestSource": "true" if candidate["questSources"] else "false",
            "hasTrainerSource": "true" if candidate["trainerSources"] else "false",
            "decision": "ACCEPT" if group else "EXCLUDE",
            "collectionId": group["collectionId"] if group else "",
            "reasonCode": rejection["reasonCode"] if rejection else "",
        })
    write_csv(args.candidates_report, list(candidate_rows[0]), candidate_rows)
    write_csv(args.exclusions_report, ["spellId", "name_enUS", "reasonCode", "reason"], excluded)

    collection_rows = []
    for group in groups:
        collection_rows.append({
            "typeKey": "mount", "collectionId": group["collectionId"], "collectionKey": group["collectionKey"],
            "ordinal": group["ordinal"], "lifecycle": "active", "name_enUS": group["name_enUS"],
            "name_zhCN": group["name_zhCN"], "policyKey": "unrestricted", "sourceBuild": evidence["sourceBuild"],
            "sourceKind": "spell", "sourceId": group["canonicalSpellId"], "actionKind": "mount_spell",
            "actionId": group["canonicalSpellId"], "assetReady": "true", "assetProfile": "wotlk_native", "aliases": "",
        })
    write_csv(args.collections, COLLECTION_COLUMNS, collection_rows)

    actions = {
        "schemaVersion": 1, "sourceBuild": evidence["sourceBuild"], "candidateHash": evidence["candidateHash"],
        "reviewMethod": REVIEW_METHOD, "collections": groups,
    }
    actions["mappingHash"] = canonical_hash(actions)
    write_json(args.actions, actions)

    ids_data = read_json(args.ids)
    old_reservations = ids_data["reservations"].get("collections", [])
    generated_keys = {row["collectionKey"] for row in groups}
    mount_reservations = [row for row in old_reservations if row["key"].startswith("mount.")]
    other_reservations = [row for row in old_reservations if not row["key"].startswith("mount.")]
    tombstones = [row for row in mount_reservations if row["key"] not in generated_keys]
    require(not tombstones, "existing collection reservations disappeared; tombstone them explicitly before regeneration")
    regenerated_mounts = [
        {"id": row["collectionId"], "key": row["collectionKey"], "ordinal": row["ordinal"], "lifecycle": "active"}
        for row in groups
    ]
    require(not ({row["ordinal"] for row in regenerated_mounts} & {row["ordinal"] for row in other_reservations}),
            "new mount ordinals collide with another collection provider; reserve new IDs in the unified catalog")
    ids_data["reservations"]["collections"] = sorted(
        regenerated_mounts + other_reservations, key=lambda row: int(row["ordinal"]))
    write_json(args.ids, ids_data)

    report = [
        "# WotLK 坐骑目录审核报告", "",
        f"- 数据版本：`{evidence['sourceBuild']}`", f"- 候选 Hash：`{evidence['candidateHash']}`",
        f"- 正式动作法术：{len(accepted)}", f"- 正式逻辑坐骑：{len(groups)}", f"- 排除法术：{len(excluded)}",
        f"- 分组规则：`{REVIEW_METHOD}`（只合并 mounted creature entry 完全相同的动作，不按名称或速度合并）", "",
        "## 审核边界", "",
        "正式 allowlist 必须同时满足玩家坐骑 SkillLine 777、CreatureTemplate 存在、当前客户端 Display 资源存在，并通过固定人工排除表。",
        "候选 Hash 发生变化时生成器会失败，必须重新审核并更新 review-policy；数据库凭据不会写入证据文件。", "",
        "## 排除统计", "",
    ]
    counts: dict[str, int] = defaultdict(int)
    for row in excluded:
        counts[row["reasonCode"]] += 1
    report += [f"- `{key}`：{counts[key]}" for key in sorted(counts)]
    report += ["", "## 输出", "", "- `catalog/generated/mount-candidates.csv`：全部候选与逐项决策。", "- `catalog/generated/mount-exclusions.csv`：排除原因。", "- `catalog/source/collections/mounts.csv`：正式逻辑坐骑目录。", "- `catalog/source/mount_actions.json`：服务端动作/解锁映射。", ""]
    args.review_report.parent.mkdir(parents=True, exist_ok=True)
    args.review_report.write_text("\n".join(report), encoding="utf-8", newline="\n")
    print(f"accepted mount spells: {len(accepted)}")
    print(f"logical mounts: {len(groups)}")
    print(f"excluded mount spells: {len(excluded)}")
    print(f"mount action mapping hash: {actions['mappingHash']}")
    return actions


def default_paths(parser: argparse.ArgumentParser) -> None:
    repo = Path(__file__).resolve().parents[2]
    parser.add_argument("--evidence", type=Path, default=repo / "catalog/review/mounts/evidence.json")
    parser.add_argument("--policy", type=Path, default=repo / "catalog/review/mounts/review-policy.json")
    parser.add_argument("--ids", type=Path, default=repo / "catalog/ids.json")
    parser.add_argument("--collections", type=Path, default=repo / "catalog/source/collections/mounts.csv")
    parser.add_argument("--actions", type=Path, default=repo / "catalog/source/mount_actions.json")
    parser.add_argument("--candidates-report", type=Path, default=repo / "catalog/generated/mount-candidates.csv")
    parser.add_argument("--exclusions-report", type=Path, default=repo / "catalog/generated/mount-exclusions.csv")
    parser.add_argument("--review-report", type=Path, default=repo / "docs/reports/2026-07-20-wotlk-mount-catalog-review.md")


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    sub = parser.add_subparsers(dest="command", required=True)
    extract_parser = sub.add_parser("extract", help="extract sanitized evidence from deployed DBC and World DB")
    default_paths(extract_parser)
    extract_parser.add_argument("--dbc-root", required=True, type=Path)
    extract_parser.add_argument("--mysql", required=True, type=Path)
    extract_parser.add_argument("--worldserver-config", required=True, type=Path)
    generate_parser = sub.add_parser("generate", help="generate the reviewed production catalog")
    default_paths(generate_parser)
    args = parser.parse_args(argv)
    try:
        if args.command == "extract":
            extract(args)
        else:
            generate(args)
        return 0
    except MountCatalogError as exc:
        print(f"mount catalog error: {exc}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
