#!/usr/bin/env python3
"""Extract and generate immutable mount/companion presentation metadata."""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import re
import struct
import subprocess
import sys
from pathlib import Path
from typing import Any, Iterable


class PresentationError(ValueError):
    pass


def require(condition: bool, message: str) -> None:
    if not condition:
        raise PresentationError(message)


def sha256_bytes(value: bytes) -> str:
    return hashlib.sha256(value).hexdigest()


def canonical_hash(value: Any) -> str:
    encoded = json.dumps(value, ensure_ascii=False, sort_keys=True, separators=(",", ":")).encode("utf-8")
    return sha256_bytes(encoded)


def read_json(path: Path) -> Any:
    try:
        return json.loads(path.read_text(encoding="utf-8-sig"))
    except (OSError, json.JSONDecodeError) as exc:
        raise PresentationError(f"cannot read JSON {path}: {exc}") from exc


def write_json(path: Path, value: Any) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(
        json.dumps(value, ensure_ascii=False, sort_keys=True, indent=2) + "\n",
        encoding="utf-8",
        newline="\n",
    )


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


def _manifest_files(manifest: dict[str, Any]) -> dict[str, dict[str, Any]]:
    files = manifest.get("files")
    require(isinstance(files, list) and files, "evidence manifest has no files")
    result: dict[str, dict[str, Any]] = {}
    for entry in files:
        relative = str(entry.get("relativePath", ""))
        require(relative and relative not in result, f"invalid or duplicate evidence path: {relative!r}")
        require(not Path(relative).is_absolute() and ".." not in Path(relative).parts, f"unsafe evidence path: {relative}")
        result[relative] = entry
    return result


def verify_evidence_root(root: Path) -> tuple[dict[str, Any], dict[str, dict[str, Any]]]:
    root = root.resolve()
    if os.name == "nt":
        require(root.drive.upper() == "F:", "evidence root must stay on F:")
    manifest_path = root / "evidence-manifest.json"
    manifest = read_json(manifest_path)
    require(manifest.get("schemaVersion") == 1, "unsupported evidence manifest schema")
    files = _manifest_files(manifest)
    for relative, entry in files.items():
        path = root / Path(relative)
        require(path.is_file(), f"evidence file is missing: {relative}")
        payload = path.read_bytes()
        require(len(payload) == int(entry.get("size", -1)), f"evidence size drift: {relative}")
        require(sha256_bytes(payload) == entry.get("sha256"), f"evidence hash drift: {relative}")
    canonical = "".join(
        f"{relative}\0{int(files[relative]['size'])}\0{files[relative]['sha256']}\n"
        for relative in sorted(files)
    ).encode("utf-8")
    require(sha256_bytes(canonical) == manifest.get("packHash"), "evidence pack hash is stale")
    return manifest, files


def evidence_path(root: Path, files: dict[str, dict[str, Any]], relative: str) -> Path:
    require(relative in files, f"required evidence member is missing: {relative}")
    return root / Path(relative)


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
        [
            str(mysql), f"--host={host}", f"--port={port}", f"--user={user}",
            f"--database={database}", "--batch", "--raw", "--skip-column-names", "--execute", query,
        ],
        check=False,
        capture_output=True,
        text=True,
        encoding="utf-8",
        errors="replace",
        env=environment,
    )
    require(result.returncode == 0, f"World DB query failed: {result.stderr.strip()}")
    return [line.split("\t") for line in result.stdout.splitlines() if line]


def sql_ids(values: Iterable[int]) -> str:
    normalized = sorted(set(int(value) for value in values))
    require(normalized, "cannot query an empty ID set")
    return ",".join(map(str, normalized))


def extract_companions(args: argparse.Namespace) -> int:
    root = args.evidence_root.resolve()
    manifest, files = verify_evidence_root(root)
    catalog = read_json(evidence_path(root, files, "repository/catalog/generated/catalog-manifest.json"))
    actions = read_json(evidence_path(root, files, "repository/catalog/source/companion_actions.json"))
    _, display_rows, _ = read_dbc(evidence_path(root, files, "dbc/CreatureDisplayInfo.dbc"))
    display_ids = {int(row[0]) for row in display_rows}
    collections = {
        int(entry["collectionId"]): entry
        for entry in catalog["collections"]
        if entry["typeKey"] == "companion"
    }
    action_entries = actions.get("entries", [])
    require(len(collections) == len(action_entries), "companion action coverage differs from catalog")
    creature_entries = [int(entry["creatureId"]) for entry in action_entries]
    query = (
        "SELECT ct.entry,COALESCE(ct.name,''),COALESCE(ct.subname,''),"
        "GROUP_CONCAT(DISTINCT ctm.CreatureDisplayID ORDER BY ctm.CreatureDisplayID SEPARATOR ',') "
        "FROM creature_template ct LEFT JOIN creature_template_model ctm ON ctm.CreatureID=ct.entry "
        f"WHERE ct.entry IN ({sql_ids(creature_entries)}) GROUP BY ct.entry,ct.name,ct.subname"
    )
    creatures: dict[int, dict[str, Any]] = {}
    for row in mysql_rows(args.mysql, args.worldserver_config, query):
        display_values = [int(value) for value in row[3].split(",") if value and value != "NULL"]
        creatures[int(row[0])] = {
            "entry": int(row[0]),
            "name": row[1],
            "subname": row[2],
            "displayIds": display_values,
            "displayResourcesPresent": bool(display_values) and all(value in display_ids for value in display_values),
        }

    entries: list[dict[str, Any]] = []
    for action in sorted(action_entries, key=lambda entry: int(entry["ordinal"])):
        collection_id = int(action["collectionId"])
        collection = collections.get(collection_id)
        require(collection is not None, f"unknown companion collection: {collection_id}")
        creature_entry = int(action["creatureId"])
        creature = creatures.get(creature_entry)
        if creature is None:
            status, reason = "EXCLUDED", "MISSING_CREATURE_TEMPLATE"
        elif not creature["displayResourcesPresent"]:
            status, reason = "EXCLUDED", "MISSING_DISPLAY_RESOURCE"
        else:
            status, reason = "READY", ""
        entries.append({
            "collectionId": collection_id,
            "collectionKey": collection["collectionKey"],
            "ordinal": int(collection["ordinal"]),
            "iconSpellId": int(collection["actionId"]),
            "previewCreatureEntry": creature_entry,
            "status": status,
            "reasonCode": reason,
            "creature": creature,
        })
    evidence = {
        "schemaVersion": 1,
        "sourceBuild": manifest["clientBuild"].replace(", ", "."),
        "reviewMethod": "EXACT_CREATURE_ENTRY_ONLY",
        "sources": {
            "CreatureDisplayInfo.dbc": files["dbc/CreatureDisplayInfo.dbc"]["sha256"],
            "companion_actions.json": files["repository/catalog/source/companion_actions.json"]["sha256"],
            "catalog-manifest.json": files["repository/catalog/generated/catalog-manifest.json"]["sha256"],
            "worldDatabase": "runtime World DB (credentials omitted)",
        },
        "entries": entries,
    }
    evidence["evidenceHash"] = canonical_hash(entries)
    write_json(args.output, evidence)
    ready = sum(entry["status"] == "READY" for entry in entries)
    print(f"companion evidence: entries={len(entries)} ready={ready} hash={evidence['evidenceHash']}")
    require(ready == len(entries), "active companion evidence contains excluded entries")
    return 0


def _spell_icons(root: Path, files: dict[str, dict[str, Any]]) -> dict[int, tuple[int, str]]:
    spell_header, spell_rows, _ = read_dbc(evidence_path(root, files, "dbc/Spell.dbc"))
    icon_header, icon_rows, icon_strings = read_dbc(evidence_path(root, files, "dbc/SpellIcon.dbc"))
    require(spell_header["fields"] == 234, "Spell.dbc schema is not 3.3.5a")
    require(icon_header["fields"] == 2, "SpellIcon.dbc schema is not 3.3.5a")
    icons = {int(row[0]): dbc_string(icon_strings, int(row[1])) for row in icon_rows}
    result: dict[int, tuple[int, str]] = {}
    for row in spell_rows:
        spell_id, icon_id = int(row[0]), int(row[133])
        if icon_id > 0:
            result[spell_id] = (icon_id, icons.get(icon_id, ""))
    return result


def build_presentations(root: Path) -> dict[str, Any]:
    root = root.resolve()
    manifest, files = verify_evidence_root(root)
    catalog = read_json(evidence_path(root, files, "repository/catalog/generated/catalog-manifest.json"))
    mount_actions = read_json(evidence_path(root, files, "repository/catalog/source/mount_actions.json"))
    companion_actions = read_json(evidence_path(root, files, "repository/catalog/source/companion_actions.json"))
    mount_evidence = read_json(evidence_path(root, files, "repository/catalog/review/mounts/evidence.json"))
    mount_policy = read_json(evidence_path(root, files, "repository/catalog/review/mounts/review-policy.json"))
    companion_evidence = read_json(evidence_path(root, files, "repository/catalog/review/companions/evidence.json"))
    require(mount_policy.get("candidateHash") == mount_evidence.get("candidateHash"), "mount review policy hash changed")
    companion_review_method = companion_evidence.get("reviewMethod")
    require(companion_review_method in {"EXACT_CREATURE_ENTRY_ONLY", "SKILLLINE_778_EXACT_CREATURE_ENTRY"},
            "invalid companion review method")
    spell_icons = _spell_icons(root, files)

    mount_by_id = {int(entry["collectionId"]): entry for entry in mount_actions["collections"]}
    companion_by_id = {int(entry["collectionId"]): entry for entry in companion_actions["entries"]}
    mount_candidate_by_spell = {int(entry["spellId"]): entry for entry in mount_evidence["candidates"]}
    companion_evidence_by_id = {
        int(entry["collectionId"]): entry for entry in companion_evidence.get("entries", [])
    }
    companion_evidence_by_creature = {
        int(entry["creatureEntry"]): entry for entry in companion_evidence.get("candidates", [])
    }
    entries: list[dict[str, Any]] = []
    for collection in catalog["collections"]:
        type_key = collection["typeKey"]
        if type_key not in {"mount", "companion"}:
            continue
        lifecycle = collection["lifecycle"]
        if type_key == "mount":
            action = mount_by_id.get(int(collection["collectionId"]))
            require(action is not None, f"mount presentation action missing: {collection['collectionKey']}")
            icon_spell = int(action["canonicalSpellId"])
            preview_entry = int(action["creatureIds"][0])
            candidate = mount_candidate_by_spell.get(icon_spell)
            ready = bool(candidate) and any(
                int(creature["entry"]) == preview_entry and creature["displayResourcesPresent"]
                for creature in candidate.get("creatures", [])
            )
            reason = "" if ready else "MISSING_CREATURE_OR_DISPLAY_EVIDENCE"
        else:
            action = companion_by_id.get(int(collection["collectionId"]))
            require(action is not None, f"companion presentation action missing: {collection['collectionKey']}")
            if companion_actions.get("schemaVersion") == 2:
                icon_spell = int(action["canonicalSpellId"])
                preview_entry = int(action["previewCreatureEntry"])
                evidence = companion_evidence_by_creature.get(preview_entry)
                ready = bool(evidence) and evidence["resourceStatus"] == "READY"
                reason = evidence.get("resourceReasonCode", "") if evidence and not ready else (
                    "MISSING_COMPANION_CANDIDATE" if not evidence else ""
                )
            else:
                evidence = companion_evidence_by_id.get(int(collection["collectionId"]))
                require(evidence is not None, f"companion presentation evidence missing: {collection['collectionKey']}")
                icon_spell = int(evidence["iconSpellId"])
                preview_entry = int(action["creatureId"])
                ready = evidence["status"] == "READY" and int(evidence["previewCreatureEntry"]) == preview_entry
                reason = evidence.get("reasonCode", "") if not ready else ""
        icon = spell_icons.get(icon_spell)
        if not icon or not icon[1]:
            ready = False
            reason = "MISSING_SPELL_ICON"
            icon_id, icon_texture = 0, ""
        else:
            icon_id, icon_texture = icon
        status = "READY" if ready and lifecycle == "active" else ("DISABLED" if lifecycle != "active" else "EXCLUDED")
        if lifecycle == "active":
            require(status == "READY", f"active presentation is not ready: {collection['collectionKey']} ({reason})")
        entries.append({
            "typeKey": type_key,
            "collectionId": int(collection["collectionId"]),
            "collectionKey": collection["collectionKey"],
            "lifecycle": lifecycle,
            "presentationStatus": status,
            "reasonCode": reason,
            "previewCreatureEntry": preview_entry,
            "iconSpellId": icon_spell,
            "spellIconId": icon_id,
            "iconTexture": icon_texture.replace("/", "\\"),
            "sourceBuild": manifest["clientBuild"].replace(", ", "."),
        })
    source_paths = [
        "dbc/Spell.dbc",
        "dbc/SpellIcon.dbc",
        "dbc/CreatureDisplayInfo.dbc",
        "repository/catalog/review/mounts/evidence.json",
        "repository/catalog/review/mounts/review-policy.json",
        "repository/catalog/review/companions/evidence.json",
        "repository/catalog/source/mount_actions.json",
        "repository/catalog/source/companion_actions.json",
    ]
    result = {
        "schemaVersion": 1,
        "evidenceId": manifest["evidenceId"],
        "evidencePackHash": manifest["packHash"],
        "sourceBuild": manifest["clientBuild"].replace(", ", "."),
        "sourceHashes": {path: files[path]["sha256"] for path in source_paths},
        "entries": sorted(entries, key=lambda entry: (entry["typeKey"], entry["collectionId"])),
    }
    result["presentationHash"] = canonical_hash(result["entries"])
    return result


def generate(args: argparse.Namespace) -> int:
    value = build_presentations(args.evidence_root)
    rendered = json.dumps(value, ensure_ascii=False, sort_keys=True, indent=2) + "\n"
    current = args.output.read_text(encoding="utf-8") if args.output.exists() else None
    if args.check:
        if current != rendered:
            print(f"out of date: {args.output}", file=sys.stderr)
            return 1
    else:
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(rendered, encoding="utf-8", newline="\n")
    print(f"creature presentation hash: {value['presentationHash']}")
    return 0


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    subparsers = parser.add_subparsers(dest="command", required=True)
    extract_parser = subparsers.add_parser("extract-companions")
    extract_parser.add_argument("--evidence-root", required=True, type=Path)
    extract_parser.add_argument("--mysql", required=True, type=Path)
    extract_parser.add_argument("--worldserver-config", required=True, type=Path)
    extract_parser.add_argument("--output", required=True, type=Path)
    generate_parser = subparsers.add_parser("generate")
    generate_parser.add_argument("--evidence-root", required=True, type=Path)
    generate_parser.add_argument("--output", required=True, type=Path)
    generate_parser.add_argument("--check", action="store_true")
    args = parser.parse_args(argv)
    try:
        return extract_companions(args) if args.command == "extract-companions" else generate(args)
    except (OSError, PresentationError) as exc:
        print(f"presentation error: {exc}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
