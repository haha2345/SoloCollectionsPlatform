#!/usr/bin/env python3
"""Build and verify the reviewed appearance UI-lifecycle projection."""

from __future__ import annotations

import argparse
import csv
import hashlib
import io
import json
import os
import re
import subprocess
import sys
from collections import Counter
from pathlib import Path
from typing import Any


LIFECYCLES = {"public", "hidden_internal", "deprecated", "test", "unobtainable", "deferred"}
RISK_PATTERNS = {
    "TEST_NAME": re.compile(r"(?i)(?:^|[^a-z])(test|qa|debug)(?:[^a-z]|$)"),
    "INTERNAL_NAME": re.compile(r"(?i)(?:^|[^a-z])(monster|internal|placeholder)(?:[^a-z]|$)"),
    "DEPRECATED_NAME": re.compile(r"(?i)(?:^|[^a-z])(deprecated|obsolete|unused|old)(?:[^a-z]|$)"),
}


class VisibilityError(ValueError):
    pass


def require(condition: bool, message: str) -> None:
    if not condition:
        raise VisibilityError(message)


def read_json(path: Path) -> Any:
    try:
        return json.loads(path.read_text(encoding="utf-8-sig"))
    except (OSError, json.JSONDecodeError) as exc:
        raise VisibilityError(f"cannot read JSON {path}: {exc}") from exc


def pretty(value: Any) -> str:
    return json.dumps(value, ensure_ascii=False, sort_keys=True, indent=2) + "\n"


def canonical_hash(value: Any) -> str:
    data = json.dumps(value, ensure_ascii=False, sort_keys=True, separators=(",", ":")) + "\n"
    return hashlib.sha256(data.encode("utf-8")).hexdigest()


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for block in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def parse_database_info(config: Path) -> tuple[str, str, str, str, str]:
    text = config.read_text(encoding="utf-8-sig", errors="replace")
    match = re.search(r'^\s*WorldDatabaseInfo\s*=\s*"([^"]+)"', text, re.MULTILINE)
    require(match is not None, f"WorldDatabaseInfo missing from {config}")
    parts = match.group(1).split(";")
    require(len(parts) >= 5, "WorldDatabaseInfo has an unexpected format")
    return parts[0], parts[1], parts[2], parts[3], parts[4]


def mysql_lines(mysql: Path, config: Path, query: str) -> list[str]:
    host, port, user, password, database = parse_database_info(config)
    environment = os.environ.copy()
    environment["MYSQL_PWD"] = password
    result = subprocess.run(
        [str(mysql), f"--host={host}", f"--port={port}", f"--user={user}", f"--database={database}",
         "--default-character-set=utf8mb4", "--batch", "--raw", "--skip-column-names", "--execute", query],
        check=False, capture_output=True, text=True, encoding="utf-8", errors="replace", env=environment,
    )
    require(result.returncode == 0, f"World DB query failed (credentials redacted): {result.stderr.strip()}")
    return [line for line in result.stdout.splitlines() if line]


def database_snapshot(mysql: Path, config: Path) -> tuple[dict[int, dict[str, Any]], set[int]]:
    rows: dict[int, dict[str, Any]] = {}
    query = (
        "SELECT entry,REPLACE(REPLACE(name,CHAR(9),' '),CHAR(10),' '),displayid,class,subclass,"
        "InventoryType,Quality,bonding,flags,FlagsExtra FROM item_template "
        "WHERE class IN (2,4) AND displayid>0 ORDER BY entry"
    )
    for line in mysql_lines(mysql, config, query):
        fields = line.split("\t")
        require(len(fields) == 10, f"unexpected item_template visibility row: {line!r}")
        entry = int(fields[0])
        rows[entry] = {
            "entry": entry, "name": fields[1], "displayId": int(fields[2]), "itemClass": int(fields[3]),
            "itemSubclass": int(fields[4]), "inventoryType": int(fields[5]), "quality": int(fields[6]),
            "bonding": int(fields[7]), "flags": int(fields[8]), "flagsExtra": int(fields[9]),
        }
    acquisition_query = " UNION ".join((
        "SELECT item FROM npc_vendor",
        "SELECT Item FROM creature_loot_template",
        "SELECT Item FROM gameobject_loot_template",
        "SELECT Item FROM item_loot_template",
        "SELECT Item FROM reference_loot_template",
        "SELECT RewardItem1 FROM quest_template", "SELECT RewardItem2 FROM quest_template",
        "SELECT RewardItem3 FROM quest_template", "SELECT RewardItem4 FROM quest_template",
        "SELECT RewardChoiceItemID1 FROM quest_template", "SELECT RewardChoiceItemID2 FROM quest_template",
        "SELECT RewardChoiceItemID3 FROM quest_template", "SELECT RewardChoiceItemID4 FROM quest_template",
        "SELECT RewardChoiceItemID5 FROM quest_template", "SELECT RewardChoiceItemID6 FROM quest_template",
    ))
    acquired = {int(line) for line in mysql_lines(mysql, config, acquisition_query) if int(line) > 0}
    return rows, acquired


def decide(group: dict[str, Any], sources: list[dict[str, Any]], acquired: set[int], override: dict[str, Any] | None) -> tuple[str, str, list[str]]:
    signals: list[str] = []
    if group.get("lifecycle") != "active":
        signals.append("CATALOG_TOMBSTONE")
    if not sources:
        signals.append("NO_WORLD_SOURCE")
    if sources and not any(int(row["displayId"]) == int(group["displayId"]) for row in sources):
        signals.append("DISPLAY_MISMATCH")
    if sources and not any(int(row["entry"]) in acquired for row in sources):
        signals.append("NO_KNOWN_ACQUISITION")
    names = [str(row.get("name", "")) for row in sources] or [str(group.get("name", ""))]
    for signal, pattern in RISK_PATTERNS.items():
        if any(pattern.search(name) for name in names):
            signals.append(signal)
    if any(int(row.get("quality", 0)) < 0 or int(row.get("quality", 0)) > 7 for row in sources):
        signals.append("INVALID_QUALITY")
    if override is not None:
        lifecycle = str(override.get("uiLifecycle", ""))
        require(lifecycle in LIFECYCLES, f"invalid override lifecycle for {group['appearanceId']}")
        return lifecycle, str(override.get("reasonCode", "MANUAL_OVERRIDE")), sorted(set(signals + ["MANUAL_OVERRIDE"]))
    if "CATALOG_TOMBSTONE" in signals:
        return "deprecated", "CATALOG_TOMBSTONE", sorted(set(signals))
    if "NO_WORLD_SOURCE" in signals or "DISPLAY_MISMATCH" in signals or "INVALID_QUALITY" in signals:
        return "deferred", "INCOMPLETE_EVIDENCE", sorted(set(signals))
    if "TEST_NAME" in signals:
        return "test", "REVIEWED_TEST_SIGNAL", sorted(set(signals))
    if "INTERNAL_NAME" in signals:
        return "hidden_internal", "REVIEWED_INTERNAL_SIGNAL", sorted(set(signals))
    if "DEPRECATED_NAME" in signals:
        return "deprecated", "REVIEWED_DEPRECATED_SIGNAL", sorted(set(signals))
    if "NO_KNOWN_ACQUISITION" in signals:
        return "unobtainable", "NO_KNOWN_ACQUISITION", sorted(set(signals))
    return "public", "TRACEABLE_WORLD_SOURCE", sorted(set(signals))


def build(repo: Path, mysql: Path, config: Path) -> tuple[dict[str, Any], list[dict[str, Any]]]:
    catalog_path = repo / "catalog/generated/appearance-sources.json"
    catalog = read_json(catalog_path)
    policy = read_json(repo / "catalog/review/appearances/visibility-policy.json")
    overrides_data = read_json(repo / "catalog/source/overrides/appearance_visibility.json")
    require(policy.get("schemaVersion") == 1 and policy.get("allowedUiLifecycles") == sorted(LIFECYCLES),
            "appearance visibility policy is invalid")
    overrides: dict[int, dict[str, Any]] = {}
    for entry in overrides_data.get("entries", []):
        appearance_id = int(entry.get("appearanceId", 0))
        require(appearance_id > 0 and appearance_id not in overrides, f"duplicate visibility override: {appearance_id}")
        overrides[appearance_id] = entry
    world_rows, acquired = database_snapshot(mysql, config)
    decisions: list[dict[str, Any]] = []
    known_ids: set[int] = set()
    for group in catalog.get("groups", []):
        appearance_id = int(group["appearanceId"])
        known_ids.add(appearance_id)
        sources = [world_rows[item_id] for item_id in group.get("sourceItemIds", []) if item_id in world_rows]
        lifecycle, reason, signals = decide(group, sources, acquired, overrides.get(appearance_id))
        decisions.append({
            "appearanceId": appearance_id, "collectionKey": group["collectionKey"],
            "catalogLifecycle": "ACTIVE" if group.get("lifecycle") == "active" else "TOMBSTONE",
            "uiLifecycle": lifecycle, "reasonCode": reason, "riskSignals": signals,
            "displayId": int(group["displayId"]), "slotKey": group["slotKey"],
            "primarySourceItemId": int(group.get("primarySourceItemId", 0)),
            "sourceItemIds": [int(value) for value in group.get("sourceItemIds", [])],
            "worldSourceCount": len(sources),
            "knownAcquisition": any(int(row["entry"]) in acquired for row in sources),
            "itemFacts": [{key: row[key] for key in ("entry", "name", "displayId", "itemClass", "itemSubclass", "inventoryType", "quality", "bonding", "flags", "flagsExtra")} for row in sources],
        })
    require(set(overrides).issubset(known_ids), "appearance visibility override references an unknown canonical ID")
    decisions.sort(key=lambda row: int(row["appearanceId"]))
    counters = Counter(row["uiLifecycle"] for row in decisions)
    evidence = {
        "schemaVersion": 1, "evidenceId": "round2-20260722-appearance-visibility",
        "sourceBuild": catalog.get("sourceBuild"), "appearanceMappingHash": catalog.get("mappingHash"),
        "sourceCatalogSha256": sha256(catalog_path), "worldSnapshotContract": "item-template-plus-known-acquisition-v1",
        "reviewUnitCount": len(decisions), "counters": {key: counters.get(key, 0) for key in sorted(LIFECYCLES)},
        "decisions": decisions,
    }
    evidence["decisionHash"] = canonical_hash(decisions)
    return evidence, decisions


def report_csv(decisions: list[dict[str, Any]]) -> str:
    stream = io.StringIO(newline="")
    fields = ["appearanceId", "collectionKey", "catalogLifecycle", "uiLifecycle", "reasonCode", "displayId", "slotKey", "primarySourceItemId", "worldSourceCount", "knownAcquisition", "riskSignals"]
    writer = csv.DictWriter(stream, fieldnames=fields, lineterminator="\n")
    writer.writeheader()
    for row in decisions:
        writer.writerow({key: ("|".join(row[key]) if key == "riskSignals" else row[key]) for key in fields})
    return stream.getvalue()


def write_or_check(path: Path, content: str, check: bool) -> None:
    if check:
        require(path.is_file() and path.read_text(encoding="utf-8") == content, f"generated output drift: {path}")
        return
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(content, encoding="utf-8", newline="\n")


def main(argv: list[str] | None = None) -> int:
    repo = Path(__file__).resolve().parents[2]
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("command", choices=("extract", "check"))
    parser.add_argument("--mysql", type=Path, required=True, help="Path to the MySQL client executable")
    parser.add_argument("--config", type=Path, required=True, help="Path to a local AzerothCore worldserver.conf")
    args = parser.parse_args(argv)
    try:
        evidence, decisions = build(repo, args.mysql, args.config)
        check = args.command == "check"
        write_or_check(repo / "catalog/review/appearances/visibility-evidence.json", pretty(evidence), check)
        write_or_check(repo / "catalog/generated/appearance-visibility-report.csv", report_csv(decisions), check)
        print("appearance visibility: " + " ".join(f"{key}={value}" for key, value in evidence["counters"].items()) +
              f" review={evidence['reviewUnitCount']} hash={evidence['decisionHash']}")
        return 0
    except (OSError, VisibilityError) as exc:
        print(f"appearance visibility error: {exc}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
