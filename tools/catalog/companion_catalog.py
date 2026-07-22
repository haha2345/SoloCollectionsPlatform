#!/usr/bin/env python3
"""Extract, review and generate the WotLK companion catalog."""

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
from collections import defaultdict
from pathlib import Path
from typing import Any, Iterable


SKILL_LINE_COMPANIONS = 778
SPELL_EFFECT_SUMMON = 28
SOURCE_BUILD = "3.3.5.12340"
COLLECTION_ID_MIN = 100000
COLLECTION_ID_MAX = 199999


class CompanionCatalogError(ValueError):
    pass


def require(condition: bool, message: str) -> None:
    if not condition:
        raise CompanionCatalogError(message)


def read_json(path: Path) -> Any:
    try:
        return json.loads(path.read_text(encoding="utf-8-sig"))
    except (OSError, json.JSONDecodeError) as exc:
        raise CompanionCatalogError(f"cannot read JSON {path}: {exc}") from exc


def json_bytes(value: Any) -> bytes:
    return (json.dumps(value, ensure_ascii=False, sort_keys=True, separators=(",", ":")) + "\n").encode("utf-8")


def pretty_json(value: Any) -> str:
    return json.dumps(value, ensure_ascii=False, sort_keys=True, indent=2) + "\n"


def canonical_hash(value: Any) -> str:
    return hashlib.sha256(json_bytes(value)).hexdigest()


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


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
    return struct.unpack("<i", struct.pack("<I", int(value)))[0]


def verify_evidence_root(root: Path) -> tuple[dict[str, Any], dict[str, dict[str, Any]]]:
    root = root.resolve()
    if os.name == "nt":
        require(root.drive.upper() == "F:", "evidence root must stay on F:")
    manifest = read_json(root / "evidence-manifest.json")
    require(manifest.get("schemaVersion") == 1, "unsupported evidence manifest schema")
    entries = manifest.get("files")
    require(isinstance(entries, list) and entries, "evidence manifest has no files")
    files: dict[str, dict[str, Any]] = {}
    for entry in entries:
        relative = str(entry.get("relativePath", ""))
        require(relative and relative not in files, f"invalid or duplicate evidence path: {relative!r}")
        path = Path(relative)
        require(not path.is_absolute() and ".." not in path.parts, f"unsafe evidence path: {relative}")
        member = root / path
        require(member.is_file(), f"evidence file is missing: {relative}")
        require(member.stat().st_size == int(entry.get("size", -1)), f"evidence size drift: {relative}")
        require(sha256(member) == entry.get("sha256"), f"evidence hash drift: {relative}")
        files[relative] = entry
    canonical = "".join(
        f"{relative}\0{int(files[relative]['size'])}\0{files[relative]['sha256']}\n"
        for relative in sorted(files)
    ).encode("utf-8")
    require(hashlib.sha256(canonical).hexdigest() == manifest.get("packHash"), "evidence pack hash is stale")
    return manifest, files


def evidence_member(root: Path, files: dict[str, dict[str, Any]], relative: str) -> Path:
    require(relative in files, f"required evidence member is missing: {relative}")
    return root / Path(relative)


def verify_review_pack(repo_root: Path, evidence_root: Path) -> str:
    root = evidence_root.resolve()
    manifest, files = verify_evidence_root(root)
    tracked_bindings = {
        "repository/catalog/review/companions/evidence.json":
            repo_root / "catalog/review/companions/evidence.json",
        "repository/catalog/review/companions/review-policy.json":
            repo_root / "catalog/review/companions/review-policy.json",
        "repository/catalog/generated/companion-candidates.csv":
            repo_root / "catalog/generated/companion-candidates.csv",
        "repository/catalog/generated/companion-exclusions.csv":
            repo_root / "catalog/generated/companion-exclusions.csv",
    }
    for relative, tracked in tracked_bindings.items():
        require(tracked.is_file(), f"tracked companion review file is missing: {tracked}")
        packed = evidence_member(root, files, relative)
        require(sha256(tracked) == sha256(packed), f"companion review pack drift: {relative}")

    evidence = read_json(repo_root / "catalog/review/companions/evidence.json")
    dbc_bindings = {
        "Spell.dbc": "dbc/Spell.dbc",
        "SkillLineAbility.dbc": "dbc/SkillLineAbility.dbc",
        "SpellIcon.dbc": "dbc/SpellIcon.dbc",
        "CreatureDisplayInfo.dbc": "dbc/CreatureDisplayInfo.dbc",
    }
    for source_name, relative in dbc_bindings.items():
        packed = evidence_member(root, files, relative)
        require(evidence.get("sources", {}).get(source_name) == sha256(packed),
                f"companion DBC evidence drift: {source_name}")
    return str(manifest["packHash"])


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


def sql_ids(values: Iterable[int]) -> str:
    normalized = sorted(set(int(value) for value in values))
    require(normalized, "cannot query an empty ID set")
    return ",".join(map(str, normalized))


def localized_spell_name(row: tuple[int, ...], strings: bytes) -> str:
    for index in range(136, 152):
        value = dbc_string(strings, int(row[index]))
        if value:
            return value
    return f"Companion Spell {int(row[0])}"


def extract(evidence_root: Path, output: Path, mysql: Path, worldserver_config: Path) -> dict[str, Any]:
    root = evidence_root.resolve()
    manifest, files = verify_evidence_root(root)
    spell_path = evidence_member(root, files, "dbc/Spell.dbc")
    skill_path = evidence_member(root, files, "dbc/SkillLineAbility.dbc")
    icon_path = evidence_member(root, files, "dbc/SpellIcon.dbc")
    display_path = evidence_member(root, files, "dbc/CreatureDisplayInfo.dbc")
    spell_header, spell_rows, spell_strings = read_dbc(spell_path)
    skill_header, skill_rows, _ = read_dbc(skill_path)
    icon_header, icon_rows, icon_strings = read_dbc(icon_path)
    display_header, display_rows, _ = read_dbc(display_path)
    require(spell_header["fields"] == 234, "Spell.dbc schema is not 3.3.5a")
    require(skill_header["fields"] == 14, "SkillLineAbility.dbc schema is not 3.3.5a")
    require(icon_header["fields"] == 2, "SpellIcon.dbc schema is not 3.3.5a")

    skill_spell_ids = sorted({int(row[2]) for row in skill_rows if int(row[1]) == SKILL_LINE_COMPANIONS})
    spells = {int(row[0]): row for row in spell_rows}
    icons = {int(row[0]): dbc_string(icon_strings, int(row[1])) for row in icon_rows}
    display_ids = {int(row[0]) for row in display_rows}
    by_creature: dict[int, list[dict[str, Any]]] = defaultdict(list)
    rejected_spells: list[dict[str, Any]] = []
    for spell_id in skill_spell_ids:
        row = spells.get(spell_id)
        require(row is not None, f"SkillLine 778 references missing spell {spell_id}")
        summons = sorted({signed(row[110 + index]) for index in range(3)
                          if int(row[71 + index]) == SPELL_EFFECT_SUMMON and signed(row[110 + index]) > 0})
        if not summons:
            rejected_spells.append({
                "spellId": spell_id, "name_zhCN": localized_spell_name(row, spell_strings),
                "decision": "excluded", "reasonCode": "NO_POSITIVE_CREATURE_SUMMON",
            })
            continue
        require(len(summons) == 1, f"companion spell {spell_id} summons multiple creature entries")
        icon_id = int(row[133])
        by_creature[summons[0]].append({
            "spellId": spell_id,
            "name_zhCN": localized_spell_name(row, spell_strings),
            "spellIconId": icon_id,
            "iconTexture": icons.get(icon_id, ""),
        })

    creature_ids = sorted(by_creature)
    query = (
        "SELECT ct.entry,COALESCE(ct.name,''),COALESCE(ct.subname,''),"
        "GROUP_CONCAT(DISTINCT ctm.CreatureDisplayID ORDER BY ctm.CreatureDisplayID SEPARATOR ',') "
        "FROM creature_template ct LEFT JOIN creature_template_model ctm ON ctm.CreatureID=ct.entry "
        f"WHERE ct.entry IN ({sql_ids(creature_ids)}) GROUP BY ct.entry,ct.name,ct.subname"
    )
    creatures: dict[int, dict[str, Any]] = {}
    for row in mysql_rows(mysql, worldserver_config, query):
        displays = [int(value) for value in row[3].split(",") if value and value != "NULL"]
        creatures[int(row[0])] = {
            "entry": int(row[0]), "name_zhCN": row[1], "subname_zhCN": row[2], "displayIds": displays,
            "displayResourcesPresent": bool(displays) and all(value in display_ids for value in displays),
        }

    summon_spell_ids = sorted({row["spellId"] for rows in by_creature.values() for row in rows})
    ids = sql_ids(summon_spell_ids)
    item_query = (
        "SELECT entry,COALESCE(name,''),spellid_1,spellid_2,spellid_3,spellid_4,spellid_5 FROM item_template WHERE "
        + " OR ".join(f"spellid_{index} IN ({ids})" for index in range(1, 6))
    )
    items_by_spell: dict[int, list[dict[str, Any]]] = defaultdict(list)
    for row in mysql_rows(mysql, worldserver_config, item_query):
        for value in row[2:7]:
            if value not in {"", "0", "NULL"} and int(value) in summon_spell_ids:
                items_by_spell[int(value)].append({"itemId": int(row[0]), "name_zhCN": row[1]})
    quest_query = (
        "SELECT ID,COALESCE(LogTitle,''),RewardDisplaySpell,RewardSpell FROM quest_template "
        f"WHERE RewardDisplaySpell IN ({ids}) OR RewardSpell IN ({ids})"
    )
    quests_by_spell: dict[int, list[dict[str, Any]]] = defaultdict(list)
    for row in mysql_rows(mysql, worldserver_config, quest_query):
        for value in row[2:4]:
            if value not in {"", "0", "NULL"} and int(value) in summon_spell_ids:
                quests_by_spell[int(value)].append({"questId": int(row[0]), "title_zhCN": row[1]})

    candidates: list[dict[str, Any]] = []
    for creature_entry in creature_ids:
        spell_entries = sorted(by_creature[creature_entry], key=lambda row: row["spellId"])
        for spell in spell_entries:
            spell["itemSources"] = sorted(items_by_spell[spell["spellId"]], key=lambda row: row["itemId"])
            spell["questSources"] = sorted(quests_by_spell[spell["spellId"]], key=lambda row: row["questId"])
        creature = creatures.get(creature_entry)
        reason = ""
        if creature is None:
            reason = "MISSING_CREATURE_TEMPLATE"
        elif not creature["displayResourcesPresent"]:
            reason = "MISSING_DISPLAY_RESOURCE"
        elif not all(row["iconTexture"] for row in spell_entries):
            reason = "MISSING_SPELL_ICON"
        candidates.append({
            "creatureEntry": creature_entry,
            "identityKey": f"creature:{creature_entry}",
            "resourceStatus": "READY" if not reason else "BLOCKED",
            "resourceReasonCode": reason,
            "creature": creature,
            "spells": spell_entries,
        })
    basis = {"rejectedSkillLineSpells": rejected_spells, "candidates": candidates}
    evidence = {
        "schemaVersion": 1,
        "sourceBuild": SOURCE_BUILD,
        "reviewMethod": "SKILLLINE_778_EXACT_CREATURE_ENTRY",
        "sourceEvidenceId": manifest.get("evidenceId"),
        "sources": {
            "Spell.dbc": sha256(spell_path), "SkillLineAbility.dbc": sha256(skill_path),
            "SpellIcon.dbc": sha256(icon_path), "CreatureDisplayInfo.dbc": sha256(display_path),
            "worldDatabase": "runtime World DB (credentials omitted)",
        },
        "counts": {
            "skillLineSpells": len(skill_spell_ids), "positiveSummonSpells": len(summon_spell_ids),
            "rejectedSkillLineSpells": len(rejected_spells), "candidates": len(candidates),
            "resourceReadyCandidates": sum(row["resourceStatus"] == "READY" for row in candidates),
        },
        **basis,
    }
    evidence["candidateHash"] = canonical_hash(basis)
    output.mkdir(parents=True, exist_ok=True)
    (output / "evidence.json").write_text(pretty_json(evidence), encoding="utf-8", newline="\n")
    write_candidate_csv(output / "companion-candidates.csv", evidence)
    write_exclusion_csv(output / "companion-exclusions.csv", rejected_spells)
    return evidence


def csv_text(fieldnames: list[str], rows: list[dict[str, Any]]) -> str:
    output = io.StringIO(newline="")
    writer = csv.DictWriter(output, fieldnames=fieldnames, lineterminator="\n")
    writer.writeheader()
    writer.writerows(rows)
    return output.getvalue()


def write_candidate_csv(path: Path, evidence: dict[str, Any]) -> None:
    rows = []
    for candidate in evidence["candidates"]:
        creature = candidate.get("creature") or {}
        rows.append({
            "creatureEntry": candidate["creatureEntry"],
            "name_zhCN": creature.get("name_zhCN", ""),
            "spellIds": ";".join(str(row["spellId"]) for row in candidate["spells"]),
            "spellNames_zhCN": ";".join(row["name_zhCN"] for row in candidate["spells"]),
            "displayIds": ";".join(str(value) for value in creature.get("displayIds", [])),
            "itemSourceCount": sum(len(row["itemSources"]) for row in candidate["spells"]),
            "questSourceCount": sum(len(row["questSources"]) for row in candidate["spells"]),
            "resourceStatus": candidate["resourceStatus"],
            "resourceReasonCode": candidate["resourceReasonCode"],
        })
    path.write_text(csv_text(list(rows[0]), rows), encoding="utf-8", newline="\n")


def write_exclusion_csv(path: Path, rows: list[dict[str, Any]]) -> None:
    fieldnames = ["spellId", "name_zhCN", "decision", "reasonCode"]
    path.write_text(csv_text(fieldnames, rows), encoding="utf-8", newline="\n")


def load_policy(repo_root: Path, evidence: dict[str, Any]) -> dict[str, Any]:
    policy = read_json(repo_root / "catalog/review/companions/review-policy.json")
    require(policy.get("schemaVersion") == 1, "unsupported companion review policy schema")
    require(policy.get("candidateHash") == evidence.get("candidateHash"), "companion candidate hash changed; explicit review required")
    decisions = policy.get("decisions")
    require(isinstance(decisions, list), "companion review policy decisions are missing")
    indexed = {int(row["creatureEntry"]): row for row in decisions}
    require(len(indexed) == len(decisions), "duplicate companion review creatureEntry")
    expected = {int(row["creatureEntry"]) for row in evidence["candidates"]}
    require(set(indexed) == expected, "accepted + excluded + deferred must cover every companion candidate")
    allowed = {"accepted", "excluded", "deferred"}
    for entry in decisions:
        require(entry.get("decision") in allowed, f"invalid companion decision: {entry}")
        require(entry.get("reasonCode"), f"companion decision lacks a reason: {entry}")
        if entry["decision"] == "accepted":
            require(int(entry.get("canonicalSpellId", 0)) > 0, f"accepted companion lacks canonical spell: {entry}")
            require(entry.get("collectionKey"), f"accepted companion lacks collection key: {entry}")
            require(entry.get("name_zhCN") and entry.get("name_enUS"), f"accepted companion lacks localized names: {entry}")
    return policy


def render(repo_root: Path, evidence: dict[str, Any]) -> dict[Path, str]:
    policy = load_policy(repo_root, evidence)
    decisions = {int(row["creatureEntry"]): row for row in policy["decisions"]}
    candidates = {int(row["creatureEntry"]): row for row in evidence["candidates"]}
    ids_path = repo_root / "catalog/ids.json"
    ids = read_json(ids_path)
    reservations = ids["reservations"]["collections"]
    reservation_by_key = {row["key"]: row for row in reservations}
    used_ids = {int(row["id"]) for row in reservations}
    next_ordinal = max(int(row["ordinal"]) for row in reservations) + 1

    old_csv_path = repo_root / "catalog/source/collections/companions.csv"
    with old_csv_path.open(encoding="utf-8-sig", newline="") as handle:
        old_rows = list(csv.DictReader(handle))
    old_by_creature = {int(row["actionId"]): row for row in old_rows}
    old_actions = read_json(repo_root / "catalog/source/companion_actions.json")
    old_action_by_creature = {
        int(row.get("previewCreatureEntry", row.get("creatureId", 0))): row for row in old_actions["entries"]
    }
    presentation_path = repo_root / "catalog/source/creature_presentations.json"
    presentations = read_json(presentation_path)
    mount_presentations = [row for row in presentations["entries"] if row["typeKey"] != "companion"]

    accepted_rows: list[dict[str, Any]] = []
    action_entries: list[dict[str, Any]] = []
    presentation_entries: list[dict[str, Any]] = []
    for creature_entry in sorted(candidates):
        decision = decisions[creature_entry]
        if decision["decision"] != "accepted":
            continue
        candidate = candidates[creature_entry]
        require(candidate["resourceStatus"] == "READY", f"accepted companion is not resource ready: {creature_entry}")
        spell_ids = [int(row["spellId"]) for row in candidate["spells"]]
        canonical_spell = int(decision["canonicalSpellId"])
        require(canonical_spell in spell_ids, f"canonical spell is not an unlock variant: {creature_entry}")
        collection_key = str(decision["collectionKey"])
        old = old_by_creature.get(creature_entry)
        if old:
            require(old["collectionKey"] == collection_key, f"existing companion key drift: {creature_entry}")
            collection_id = int(old["collectionId"])
            ordinal = int(old["ordinal"])
            name_en = old["name_enUS"]
            name_zh = old["name_zhCN"]
            require(int(old["actionId"]) == canonical_spell, f"existing companion canonical spell drift: {creature_entry}")
        else:
            reservation = reservation_by_key.get(collection_key)
            if reservation is None:
                collection_id = next(value for value in range(COLLECTION_ID_MIN, COLLECTION_ID_MAX + 1) if value not in used_ids)
                used_ids.add(collection_id)
                reservation = {"id": collection_id, "key": collection_key, "lifecycle": "active", "ordinal": next_ordinal}
                next_ordinal += 1
                reservations.append(reservation)
                reservation_by_key[collection_key] = reservation
            collection_id = int(reservation["id"])
            ordinal = int(reservation["ordinal"])
            name_en = str(decision["name_enUS"])
            name_zh = str(decision["name_zhCN"])
        require(COLLECTION_ID_MIN <= collection_id <= COLLECTION_ID_MAX, f"companion ID outside allocated domain: {collection_id}")
        require(not any(row["key"].startswith("toy.") and int(row["id"]) == collection_id for row in reservations), "companion reused toy ID")
        spell_row = next(row for row in candidate["spells"] if int(row["spellId"]) == canonical_spell)
        accepted_rows.append({
            "typeKey": "companion", "collectionId": collection_id, "collectionKey": collection_key,
            "ordinal": ordinal, "lifecycle": "active", "name_enUS": name_en, "name_zhCN": name_zh,
            "policyKey": "unrestricted", "sourceBuild": SOURCE_BUILD, "sourceKind": "spell",
            "sourceId": canonical_spell, "actionKind": "COMPANION_SPELL", "actionId": canonical_spell,
            "assetReady": "true", "assetProfile": "wotlk_native", "aliases": "",
        })
        action_entries.append({
            "collectionId": collection_id, "collectionKey": collection_key, "ordinal": ordinal,
            "canonicalSpellId": canonical_spell, "unlockSpellIds": spell_ids,
            "previewCreatureEntry": creature_entry, "catalogLifecycle": "ACTIVE", "uiLifecycle": "public",
        })
        presentation_entries.append({
            "collectionId": collection_id, "collectionKey": collection_key, "iconSpellId": canonical_spell,
            "iconTexture": spell_row["iconTexture"], "lifecycle": "active", "presentationStatus": "READY",
            "previewCreatureEntry": creature_entry, "reasonCode": "", "sourceBuild": SOURCE_BUILD,
            "spellIconId": int(spell_row["spellIconId"]), "typeKey": "companion",
        })

    require(len(accepted_rows) == sum(row["decision"] == "accepted" for row in policy["decisions"]), "accepted count drift")
    require(len({row["collectionId"] for row in accepted_rows}) == len(accepted_rows), "duplicate companion collection ID")
    require(len({row["collectionKey"] for row in accepted_rows}) == len(accepted_rows), "duplicate companion collection key")
    unlocks = [spell for row in action_entries for spell in row["unlockSpellIds"]]
    require(len(set(unlocks)) == len(unlocks), "unlock spell maps to multiple companion identities")

    csv_fields = list(accepted_rows[0])
    exclusions = list(evidence["rejectedSkillLineSpells"])
    for creature_entry in sorted(decisions):
        decision = decisions[creature_entry]
        if decision["decision"] != "accepted":
            exclusions.append({
                "spellId": ";".join(str(row["spellId"]) for row in candidates[creature_entry]["spells"]),
                "name_zhCN": (candidates[creature_entry].get("creature") or {}).get("name_zhCN", ""),
                "decision": decision["decision"], "reasonCode": decision["reasonCode"],
            })
    evidence_copy = pretty_json(evidence)
    presentation_value = {
        key: value for key, value in presentations.items()
        if key not in {"entries", "presentationHash"}
    }
    presentation_value["entries"] = sorted(
        presentation_entries + mount_presentations,
        key=lambda row: (row["typeKey"], int(row["collectionId"])),
    )
    presentation_value["schemaVersion"] = presentations.get("schemaVersion", 1)
    presentation_value["presentationHash"] = hashlib.sha256(
        json.dumps(presentation_value["entries"], ensure_ascii=False, sort_keys=True, separators=(",", ":")).encode("utf-8")
    ).hexdigest()
    return {
        ids_path: pretty_json(ids),
        old_csv_path: csv_text(csv_fields, accepted_rows),
        repo_root / "catalog/source/companion_actions.json": pretty_json({"schemaVersion": 2, "entries": action_entries}),
        presentation_path: pretty_json(presentation_value),
        repo_root / "catalog/review/companions/evidence.json": evidence_copy,
        repo_root / "catalog/generated/companion-candidates.csv": csv_text(
            ["creatureEntry", "name_zhCN", "spellIds", "spellNames_zhCN", "displayIds", "itemSourceCount", "questSourceCount", "resourceStatus", "resourceReasonCode"],
            [{
                "creatureEntry": row["creatureEntry"],
                "name_zhCN": (row.get("creature") or {}).get("name_zhCN", ""),
                "spellIds": ";".join(str(spell["spellId"]) for spell in row["spells"]),
                "spellNames_zhCN": ";".join(spell["name_zhCN"] for spell in row["spells"]),
                "displayIds": ";".join(str(value) for value in (row.get("creature") or {}).get("displayIds", [])),
                "itemSourceCount": sum(len(spell["itemSources"]) for spell in row["spells"]),
                "questSourceCount": sum(len(spell["questSources"]) for spell in row["spells"]),
                "resourceStatus": row["resourceStatus"], "resourceReasonCode": row["resourceReasonCode"],
            } for row in evidence["candidates"]]),
        repo_root / "catalog/generated/companion-exclusions.csv": csv_text(
            ["spellId", "name_zhCN", "decision", "reasonCode"], exclusions),
    }


def generate(repo_root: Path, evidence_path: Path, check: bool) -> dict[str, Any]:
    evidence = read_json(evidence_path)
    require(evidence.get("schemaVersion") == 1, "unsupported companion evidence schema")
    basis = {"rejectedSkillLineSpells": evidence.get("rejectedSkillLineSpells"), "candidates": evidence.get("candidates")}
    require(evidence.get("candidateHash") == canonical_hash(basis), "companion evidence hash drift")
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
        raise CompanionCatalogError("generated companion outputs are stale: " + ", ".join(str(path) for path in drift))
    decisions = read_json(repo_root / "catalog/review/companions/review-policy.json")["decisions"]
    counts = {value: sum(row["decision"] == value for row in decisions) for value in ("accepted", "excluded", "deferred")}
    print(f"companion review: candidates={len(decisions)} accepted={counts['accepted']} excluded={counts['excluded']} deferred={counts['deferred']}")
    return counts


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
        if args.command == "extract":
            require(args.evidence_root and args.out and args.mysql and args.worldserver_config,
                    "extract requires --evidence-root, --out, --mysql and --worldserver-config")
            evidence = extract(args.evidence_root, args.out.resolve(), args.mysql, args.worldserver_config)
            print(f"companion candidates: {evidence['counts']}")
            print(f"candidate hash: {evidence['candidateHash']}")
        else:
            evidence_path = args.evidence or args.repo_root / "catalog/review/companions/evidence.json"
            if args.evidence_root:
                pack_hash = verify_review_pack(args.repo_root.resolve(), args.evidence_root.resolve())
                print(f"companion evidence pack hash: {pack_hash}")
            generate(args.repo_root.resolve(), evidence_path.resolve(), args.command == "check")
        return 0
    except (CompanionCatalogError, OSError) as exc:
        print(f"companion catalog error: {exc}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
