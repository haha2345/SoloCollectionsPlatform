#!/usr/bin/env python3
"""Generate SoloCollections catalog artifacts from the canonical source tree."""

from __future__ import annotations

import argparse
import csv
import hashlib
import importlib.util
import json
import re
import sys
from copy import deepcopy
from pathlib import Path
from typing import Any, Iterable


class CatalogError(ValueError):
    pass


COLLECTION_COLUMNS = [
    "typeKey", "collectionId", "collectionKey", "ordinal", "lifecycle",
    "name_enUS", "name_zhCN", "policyKey", "sourceBuild", "sourceKind",
    "sourceId", "actionKind", "actionId", "assetReady", "assetProfile", "aliases",
]


def _read_json(path: Path) -> Any:
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as exc:
        raise CatalogError(f"cannot read JSON {path}: {exc}") from exc


def _require(condition: bool, message: str) -> None:
    if not condition:
        raise CatalogError(message)


def _unique(entries: Iterable[dict[str, Any]], fields: Iterable[str], label: str) -> None:
    for field in fields:
        seen: dict[Any, int] = {}
        for index, entry in enumerate(entries):
            value = entry.get(field)
            _require(value is not None and value != "", f"{label}[{index}] missing {field}")
            _require(value not in seen, f"duplicate {label} {field}={value!r}")
            seen[value] = index


def _validate_ordinals(entries: list[dict[str, Any]], field: str, label: str) -> None:
    ordinals = sorted(int(entry[field]) for entry in entries)
    _require(ordinals == list(range(len(ordinals))), f"{label} ordinals must be contiguous from zero")


def _validate_reservations(
    reservations: list[dict[str, Any]],
    entries: list[dict[str, Any]],
    id_field: str,
    key_field: str,
    label: str,
) -> None:
    _unique(reservations, ("id", "key", "ordinal"), f"{label} reservations")
    _unique(entries, (id_field, key_field, "ordinal"), label)
    _validate_ordinals(reservations, "ordinal", f"{label} reservations")
    _validate_ordinals(entries, "ordinal", label)
    actual_by_key = {entry[key_field]: entry for entry in entries}
    for reservation in reservations:
        lifecycle = reservation.get("lifecycle")
        _require(lifecycle in {"active", "tombstone"}, f"invalid {label} reservation lifecycle")
        actual = actual_by_key.get(reservation["key"])
        if lifecycle == "active":
            _require(actual is not None, f"active {label} reservation missing source entry: {reservation['key']}")
            _require(int(actual[id_field]) == int(reservation["id"]), f"reserved {label} id changed: {reservation['key']}")
            _require(int(actual["ordinal"]) == int(reservation["ordinal"]), f"reserved {label} ordinal changed: {reservation['key']}")
        else:
            _require(actual is None or actual.get("lifecycle") == "tombstone", f"tombstoned {label} key was rebound: {reservation['key']}")
    reserved = {(int(row["id"]), row["key"], int(row["ordinal"])) for row in reservations}
    for entry in entries:
        triple = (int(entry[id_field]), entry[key_field], int(entry["ordinal"]))
        _require(triple in reserved, f"unreserved {label} identity: {entry[key_field]}")


def _validate_dependency_graph(types: list[dict[str, Any]]) -> None:
    keys = {entry["typeKey"] for entry in types}
    graph: dict[str, list[str]] = {}
    for entry in types:
        dependencies = entry.get("dependencies", [])
        _require(isinstance(dependencies, list), f"dependencies must be an array: {entry['typeKey']}")
        for dependency in dependencies:
            _require(dependency in keys, f"unknown collection type dependency: {dependency}")
        graph[entry["typeKey"]] = dependencies
    visiting: set[str] = set()
    visited: set[str] = set()

    def visit(key: str) -> None:
        if key in visiting:
            raise CatalogError(f"collection type dependency cycle at {key}")
        if key in visited:
            return
        visiting.add(key)
        for dependency in graph[key]:
            visit(dependency)
        visiting.remove(key)
        visited.add(key)

    for key in sorted(graph):
        visit(key)


def _normalize_alias(value: str) -> str:
    return value.strip().lower().replace("-", "_").replace(" ", "_")


def _validate_aliases(ids: dict[str, Any], entities: dict[str, set[str]]) -> list[dict[str, str]]:
    aliases = ids.get("aliases", [])
    _require(isinstance(aliases, list), "catalog aliases must be an array")
    graph: dict[tuple[str, str], str] = {}
    normalized: list[dict[str, str]] = []
    for index, entry in enumerate(aliases):
        kind = entry.get("kind")
        alias = _normalize_alias(str(entry.get("alias", "")))
        target = _normalize_alias(str(entry.get("target", entry.get("targetKey", ""))))
        _require(kind in entities, f"alias[{index}] has invalid kind")
        _require(alias and target, f"alias[{index}] is incomplete")
        key = (kind, alias)
        _require(key not in graph, f"duplicate alias {kind}:{alias}")
        _require(alias not in entities[kind], f"alias shadows canonical key {kind}:{alias}")
        graph[key] = target
        normalized.append({"kind": kind, "alias": alias, "target": target})

    def resolve(kind: str, alias: str) -> str:
        seen: set[str] = set()
        current = alias
        while (kind, current) in graph:
            _require(current not in seen, f"alias cycle at {kind}:{current}")
            seen.add(current)
            current = graph[(kind, current)]
        _require(current in entities[kind], f"alias target does not exist: {kind}:{current}")
        return current

    for entry in normalized:
        entry["target"] = resolve(entry["kind"], entry["alias"])
    return sorted(normalized, key=lambda row: (row["kind"], row["alias"]))


def _parse_bool(value: str, label: str) -> bool:
    normalized = value.strip().lower()
    _require(normalized in {"true", "false", "1", "0", "yes", "no"}, f"invalid boolean for {label}: {value}")
    return normalized in {"true", "1", "yes"}


def _parse_collections(source_root: Path, type_keys: set[str]) -> list[dict[str, Any]]:
    collection_dir = source_root / "collections"
    entries: list[dict[str, Any]] = []
    for path in sorted(collection_dir.glob("*.csv"), key=lambda value: value.name):
        with path.open("r", encoding="utf-8-sig", newline="") as handle:
            reader = csv.DictReader(handle)
            _require(reader.fieldnames == COLLECTION_COLUMNS, f"unexpected columns in {path.name}")
            for line, row in enumerate(reader, start=2):
                _require(row["typeKey"] in type_keys, f"unknown typeKey in {path.name}:{line}")
                lifecycle = row["lifecycle"].strip()
                _require(lifecycle in {"active", "tombstone"}, f"invalid lifecycle in {path.name}:{line}")
                policy_key = row["policyKey"].strip() or "unrestricted"
                entries.append({
                    "typeKey": row["typeKey"].strip(),
                    "collectionId": int(row["collectionId"]),
                    "collectionKey": row["collectionKey"].strip(),
                    "ordinal": int(row["ordinal"]),
                    "lifecycle": lifecycle,
                    "name": {"enUS": row["name_enUS"], "zhCN": row["name_zhCN"]},
                    "policyKey": policy_key,
                    "sourceBuild": row["sourceBuild"].strip(),
                    "sourceKind": row["sourceKind"].strip(),
                    "sourceId": int(row["sourceId"] or 0),
                    "actionKind": row["actionKind"].strip(),
                    "actionId": int(row["actionId"] or 0),
                    "assetReady": _parse_bool(row["assetReady"], f"{path.name}:{line}.assetReady"),
                    "assetProfile": row["assetProfile"].strip(),
                    "aliases": sorted(filter(None, (item.strip() for item in row["aliases"].split("|")))),
                })
    if entries:
        _unique(entries, ("collectionId", "collectionKey", "ordinal"), "collections")
        _validate_ordinals(entries, "ordinal", "collections")
    return sorted(entries, key=lambda row: row["ordinal"])


def _load_mount_actions(source_root: Path, collections: list[dict[str, Any]]) -> dict[str, Any]:
    path = source_root / "mount_actions.json"
    mount_collections = [entry for entry in collections if entry["typeKey"] == "mount"]
    _require(all(int(entry["collectionId"]) != 1 for entry in mount_collections),
             "mount collectionId 1 is reserved for RANDOM_SUMMON")
    if not path.exists():
        _require(not mount_collections, "mount_actions.json is required when mount collections exist")
        return {"schemaVersion": 1, "collections": [], "mappingHash": _hash({"schemaVersion": 1, "collections": []})}
    actions = deepcopy(_read_json(path))
    _require(actions.get("schemaVersion") == 1, "unsupported mount action schema version")
    entries = actions.get("collections")
    _require(isinstance(entries, list), "mount action collections must be an array")
    _unique(entries, ("collectionId", "collectionKey", "ordinal"), "mount actions")
    _validate_ordinals(entries, "ordinal", "mount actions")
    source_by_key = {entry["collectionKey"]: entry for entry in mount_collections}
    _require(len(entries) == len(source_by_key), "mount action coverage must match mount catalog")
    seen_spells: set[int] = set()
    for entry in entries:
        source = source_by_key.get(entry["collectionKey"])
        _require(source is not None, f"mount action references unknown collection: {entry['collectionKey']}")
        _require(int(entry["collectionId"]) == source["collectionId"], f"mount action collectionId mismatch: {entry['collectionKey']}")
        _require(int(entry["ordinal"]) == source["ordinal"], f"mount action ordinal mismatch: {entry['collectionKey']}")
        unlocks = entry.get("unlockSpellIds")
        variants = entry.get("actionVariants")
        _require(isinstance(unlocks, list) and unlocks, f"mount action has no unlock spells: {entry['collectionKey']}")
        _require(isinstance(variants, list) and variants, f"mount action has no action variants: {entry['collectionKey']}")
        variant_ids = [int(variant["spellId"]) for variant in variants]
        _require(sorted(map(int, unlocks)) == sorted(variant_ids), f"mount unlock/action variants differ: {entry['collectionKey']}")
        _require(not (set(variant_ids) & seen_spells), f"mount spell is mapped to multiple collections: {entry['collectionKey']}")
        seen_spells.update(variant_ids)
        _require(int(entry["canonicalSpellId"]) in variant_ids, f"canonical mount spell is not an action variant: {entry['collectionKey']}")
    claimed_hash = actions.pop("mappingHash", "")
    _require(claimed_hash == _hash(actions), "mount action mappingHash is stale")
    actions["mappingHash"] = claimed_hash
    return actions


def _apply_mount_journal_contract(source_root: Path, actions: dict[str, Any]) -> dict[str, Any]:
    journal = _read_json(source_root / "mount_journal_metadata.json")
    _require(journal.get("schemaVersion") == 2, "unsupported mount journal metadata schema")
    rows = journal.get("entries")
    _require(isinstance(rows, list), "mount journal entries must be an array")
    by_id = {int(row["collectionId"]): row for row in rows}
    entries = actions["collections"]
    _require(len(by_id) == len(rows) == len(entries), "mount journal/action coverage differs")
    seen_action_spells: set[int] = set()
    allowed_capabilities = {"GROUND", "FLYING", "AQUATIC", "SPECIAL"}
    allowed_exclusions = {None, "TAXI", "QUEST_TEMPORARY", "CLASS_FORM", "TEST", "DUPLICATE", "INTERNAL"}
    for entry in entries:
        row = by_id.get(int(entry["collectionId"]))
        _require(row is not None and int(row["spellId"]) == int(entry["canonicalSpellId"]),
                 f"mount journal action identity drift: {entry['collectionKey']}")
        journal_visible = bool(row.get("journalVisible"))
        actionable = bool(row.get("actionable"))
        draggable = bool(row.get("draggable"))
        random_eligible = bool(row.get("randomEligible"))
        action_spell_id = int(row.get("canonicalActionSpellId") or 0)
        capability = row.get("capability")
        exclusion_reason = row.get("exclusionReason")
        _require(capability in allowed_capabilities, f"invalid mount capability: {entry['collectionKey']}")
        _require(exclusion_reason in allowed_exclusions, f"invalid mount exclusion reason: {entry['collectionKey']}")
        _require(not actionable or journal_visible, f"hidden mount is actionable: {entry['collectionKey']}")
        _require(not draggable or actionable, f"non-actionable mount is draggable: {entry['collectionKey']}")
        _require(not random_eligible or (journal_visible and actionable),
                 f"invalid random-eligible mount: {entry['collectionKey']}")
        _require((exclusion_reason is None) == journal_visible,
                 f"mount exclusion/visibility mismatch: {entry['collectionKey']}")
        _require(not draggable or action_spell_id == int(entry["canonicalSpellId"]),
                 f"mount draggable spell is not canonical: {entry['collectionKey']}")
        _require(draggable or action_spell_id == 0,
                 f"non-draggable mount exposes an action spell: {entry['collectionKey']}")
        if action_spell_id:
            _require(action_spell_id not in seen_action_spells,
                     f"mount action spell is mapped twice: {entry['collectionKey']}")
            seen_action_spells.add(action_spell_id)
        entry.update({
            "journalVisible": journal_visible,
            "actionable": actionable,
            "draggable": draggable,
            "randomEligible": random_eligible,
            "canonicalActionSpellId": action_spell_id,
            "capability": capability,
            "exclusionReason": exclusion_reason,
        })
    audit = _read_json(source_root.parent / "review/mounts/action-identity-audit.json")
    _require(audit.get("schemaVersion") == 1, "unsupported mount action identity audit schema")
    summary = audit.get("summary", {})
    visible_count = sum(bool(entry["journalVisible"]) for entry in entries)
    creature_groups = [tuple(map(int, entry["creatureIds"])) for entry in entries]
    name_groups: dict[str, list[int]] = {}
    for row in rows:
        name_groups.setdefault(str(row["journalNameZhCN"]), []).append(int(row["collectionId"]))
    duplicate_name_groups = {name: sorted(ids) for name, ids in name_groups.items() if len(ids) > 1}
    reviewed_name_groups = {
        str(decision["name"]): sorted(map(int, decision["collectionIds"]))
        for decision in audit.get("sameZhCNNameDecisions", [])
    }
    _require(summary.get("canonicalRows") == len(entries) and summary.get("visibleRows") == visible_count,
             "mount action identity audit count drift")
    _require(summary.get("uniqueVisibleCanonicalActionSpells") == len(seen_action_spells),
             "mount action identity audit spell count drift")
    _require(summary.get("duplicateCanonicalActionSpells") == 0 and len(seen_action_spells) == visible_count,
             "mount action identity audit found duplicate canonical action spells")
    _require(summary.get("duplicateCreatureTuples") == len(creature_groups) - len(set(creature_groups)) == 0,
             "mount action identity audit creature grouping drift")
    _require(reviewed_name_groups == duplicate_name_groups,
             "mount action identity audit zhCN name decisions are incomplete")
    return actions


def _load_companion_actions(source_root: Path, collections: list[dict[str, Any]]) -> dict[str, Any]:
    path = source_root / "companion_actions.json"
    sources = [entry for entry in collections if entry["typeKey"] == "companion"]
    _require(path.exists() or not sources, "companion_actions.json is required when companion collections exist")
    if not sources:
        empty = {"schemaVersion": 2, "entries": []}
        return {**empty, "mappingHash": _hash(empty)}
    data = deepcopy(_read_json(path))
    _require(data.get("schemaVersion") == 2, "unsupported companion action schema version")
    entries = data.get("entries")
    _require(isinstance(entries, list), "companion action entries must be an array")
    _unique(entries, ("collectionId", "collectionKey", "ordinal", "previewCreatureEntry"), "companion actions")
    source_by_key = {entry["collectionKey"]: entry for entry in sources}
    _require(len(entries) == len(source_by_key), "companion action coverage must match companion catalog")
    normalized: list[dict[str, Any]] = []
    seen_spells: set[int] = set()
    for entry in entries:
        source = source_by_key.get(entry["collectionKey"])
        _require(source is not None, f"companion action references unknown collection: {entry['collectionKey']}")
        _require(int(entry["collectionId"]) == source["collectionId"], f"companion collectionId mismatch: {entry['collectionKey']}")
        _require(int(entry["ordinal"]) == source["ordinal"], f"companion ordinal mismatch: {entry['collectionKey']}")
        _require(source["sourceKind"] == "spell" and source["actionKind"] == "COMPANION_SPELL",
                 f"companion source/action kind is not explicit: {entry['collectionKey']}")
        canonical_spell_id = int(entry.get("canonicalSpellId", 0))
        unlock_spell_ids = [int(value) for value in entry.get("unlockSpellIds", [])]
        preview_entry = int(entry.get("previewCreatureEntry", 0))
        _require(canonical_spell_id > 0 and int(source["actionId"]) == canonical_spell_id
                 and int(source["sourceId"]) == canonical_spell_id,
                 f"companion unlock/action spell differs: {entry['collectionKey']}")
        _require(unlock_spell_ids and canonical_spell_id in unlock_spell_ids,
                 f"companion canonical spell is not an unlock variant: {entry['collectionKey']}")
        _require(len(set(unlock_spell_ids)) == len(unlock_spell_ids) and all(value > 0 for value in unlock_spell_ids),
                 f"companion unlock variants are invalid: {entry['collectionKey']}")
        _require(not (set(unlock_spell_ids) & seen_spells),
                 f"companion unlock spell is mapped twice: {entry['collectionKey']}")
        seen_spells.update(unlock_spell_ids)
        _require(preview_entry > 0, f"companion preview creature is invalid: {entry['collectionKey']}")
        _require(entry.get("catalogLifecycle") == source["catalogLifecycle"],
                 f"companion catalog lifecycle drift: {entry['collectionKey']}")
        _require(entry.get("uiLifecycle") == "public", f"companion UI lifecycle is not public: {entry['collectionKey']}")
        normalized.append({
            "collectionId": source["collectionId"], "collectionKey": source["collectionKey"],
            "ordinal": source["ordinal"], "canonicalSpellId": canonical_spell_id,
            "unlockSpellIds": sorted(unlock_spell_ids), "previewCreatureEntry": preview_entry,
            "catalogLifecycle": entry["catalogLifecycle"], "uiLifecycle": entry["uiLifecycle"],
        })
    result = {"schemaVersion": 2, "entries": sorted(normalized, key=lambda row: row["ordinal"])}
    result["mappingHash"] = _hash(result)
    return result


def _apply_companion_journal_contract(source_root: Path, actions: dict[str, Any]) -> dict[str, Any]:
    journal = _read_json(source_root / "companion_journal_metadata.json")
    _require(journal.get("schemaVersion") == 1, "unsupported companion journal metadata schema")
    rows = journal.get("entries")
    _require(isinstance(rows, list), "companion journal entries must be an array")
    by_id = {int(row["collectionId"]): row for row in rows}
    entries = actions["entries"]
    _require(len(by_id) == len(rows) == len(entries), "companion journal/action coverage differs")
    _require(set(by_id) == {int(entry["collectionId"]) for entry in entries},
             "companion journal/action collectionId sets differ")
    for entry in entries:
        row = by_id[int(entry["collectionId"])]
        _require(int(row.get("spellId") or 0) == int(entry["canonicalSpellId"]),
                 f"companion journal spell drift: {entry['collectionKey']}")
        journal_visible = bool(row.get("journalVisible"))
        actionable = bool(row.get("actionable"))
        random_eligible = bool(row.get("randomEligible"))
        action_spell_id = int(row.get("canonicalActionSpellId") or 0)
        exclusion_reason = row.get("exclusionReason")
        _require(not actionable or journal_visible, f"hidden companion is actionable: {entry['collectionKey']}")
        _require(not random_eligible or (journal_visible and actionable),
                 f"invalid random-eligible companion: {entry['collectionKey']}")
        _require((exclusion_reason is None) == journal_visible,
                 f"companion exclusion/visibility mismatch: {entry['collectionKey']}")
        _require((action_spell_id == int(entry["canonicalSpellId"])) if actionable else action_spell_id == 0,
                 f"companion canonical action spell mismatch: {entry['collectionKey']}")
        entry.update({
            "journalVisible": journal_visible,
            "actionable": actionable,
            "randomEligible": random_eligible,
            "canonicalActionSpellId": action_spell_id,
        })
    actions["mappingHash"] = _hash({key: value for key, value in actions.items() if key != "mappingHash"})
    return actions


def _load_toy_actions(source_root: Path, collections: list[dict[str, Any]]) -> dict[str, Any]:
    path = source_root / "toy_actions.json"
    sources = [entry for entry in collections if entry["typeKey"] == "toy"]
    _require(path.exists() or not sources, "toy_actions.json is required when toy collections exist")
    if not sources:
        empty = {"schemaVersion": 2, "entries": []}
        return {**empty, "mappingHash": _hash(empty)}
    data = deepcopy(_read_json(path))
    _require(data.get("schemaVersion") == 2, "unsupported toy action schema version")
    entries = data.get("entries")
    _require(isinstance(entries, list), "toy action entries must be an array")
    _unique(entries, ("collectionId", "collectionKey", "ordinal", "itemId"), "toy actions")
    source_by_key = {entry["collectionKey"]: entry for entry in sources}
    _require(len(entries) == len(source_by_key), "toy action coverage must match toy catalog")
    action_kinds = {"SPELL_SELF", "SPELL_TARGET", "ITEM_USE", "CUSTOM_HANDLER"}
    target_policies = {"NONE", "SELF", "OPTIONAL_UNIT", "REQUIRED_UNIT"}
    cooldown_scopes = {"NONE", "CHARACTER", "ACCOUNT", "HANDLER_NATIVE"}
    replay_policies = {"REJECT_DUPLICATE", "IDEMPOTENT"}
    lifecycles = {"ACTIVE", "PREVIEW_ONLY", "DISABLED", "TOMBSTONE"}
    risk_flags = {"TELEPORT", "ECONOMY", "ITEM_CREATE", "WORLD_OBJECT", "MATERIAL", "SEASONAL", "AREA", "COMBAT"}
    for entry in entries:
        source = source_by_key.get(entry["collectionKey"])
        _require(source is not None, f"toy action references unknown collection: {entry['collectionKey']}")
        _require(int(entry["collectionId"]) == source["collectionId"], f"toy collectionId mismatch: {entry['collectionKey']}")
        _require(int(entry["ordinal"]) == source["ordinal"], f"toy ordinal mismatch: {entry['collectionKey']}")
        _require(source["sourceKind"] == "item" and int(source["sourceId"]) == int(entry["itemId"]),
                 f"toy source item mismatch: {entry['collectionKey']}")
        _require(entry.get("actionKind") in action_kinds and source["actionKind"] == entry["actionKind"],
                 f"toy action kind mismatch: {entry['collectionKey']}")
        _require(int(source["actionId"]) == int(entry["spellId"]) and int(entry["spellId"]) > 0,
                  f"toy action spell mismatch: {entry['collectionKey']}")
        _require(entry.get("unlockSource") == "ITEM_ACQUIRED", f"toy unlock source is not item acquisition: {entry['collectionKey']}")
        _require(entry.get("targetPolicy") in target_policies, f"invalid toy target policy: {entry['collectionKey']}")
        _require(entry.get("cooldownScope") in cooldown_scopes, f"invalid toy cooldown scope: {entry['collectionKey']}")
        _require(isinstance(entry.get("accountCooldownMs"), int) and entry["accountCooldownMs"] >= 0,
                 f"invalid toy account cooldown: {entry['collectionKey']}")
        _require(entry["cooldownScope"] != "ACCOUNT" or entry["accountCooldownMs"] > 0,
                 f"account-scoped toy requires a logical cooldown: {entry['collectionKey']}")
        _require(isinstance(entry.get("allowInCombat"), bool) and isinstance(entry.get("consumesMaterial"), bool),
                 f"toy combat/material semantics must be explicit: {entry['collectionKey']}")
        _require(isinstance(entry.get("riskFlags"), list) and set(entry["riskFlags"]) <= risk_flags,
                 f"invalid toy risk flags: {entry['collectionKey']}")
        _require(entry.get("replayPolicy") in replay_policies,
                  f"toy action lacks explicit replay semantics: {entry['collectionKey']}")
        _require(entry.get("catalogLifecycle") in lifecycles,
                  f"toy action lacks catalog lifecycle: {entry['collectionKey']}")
        _require(entry["catalogLifecycle"] == "ACTIVE" and source["lifecycle"] == "active",
                  f"non-active toy entered the public action catalog: {entry['collectionKey']}")
        if entry["actionKind"] == "CUSTOM_HANDLER":
            _require(bool(entry.get("customHandler")), f"custom toy handler missing: {entry['collectionKey']}")
        else:
            _require(not entry.get("customHandler"), f"non-custom toy declares handler: {entry['collectionKey']}")
        if entry["actionKind"] == "SPELL_TARGET":
            _require(entry["targetPolicy"] in {"OPTIONAL_UNIT", "REQUIRED_UNIT"},
                     f"targeted toy lacks unit target policy: {entry['collectionKey']}")
        elif entry["actionKind"] == "SPELL_SELF":
            _require(entry["targetPolicy"] in {"NONE", "SELF"},
                     f"self toy declares a unit target policy: {entry['collectionKey']}")
    normalized = sorted(entries, key=lambda row: int(row["ordinal"]))
    result = {"schemaVersion": 2, "entries": normalized}
    result["mappingHash"] = _hash(result)
    return result


def _load_creature_presentations(source_root: Path, collections: list[dict[str, Any]]) -> dict[str, Any]:
    path = source_root / "creature_presentations.json"
    data = deepcopy(_read_json(path))
    _require(data.get("schemaVersion") == 1, "unsupported creature presentation schema version")
    entries = data.get("entries")
    _require(isinstance(entries, list), "creature presentation entries must be an array")
    _require(data.get("presentationHash") == _hash(entries), "creature presentation hash is stale")
    expected = {
        (entry["typeKey"], int(entry["collectionId"])): entry
        for entry in collections
        if entry["typeKey"] in {"mount", "companion"}
    }
    actual: dict[tuple[str, int], dict[str, Any]] = {}
    for entry in entries:
        identity = (entry.get("typeKey"), int(entry.get("collectionId", 0)))
        _require(identity not in actual, f"duplicate creature presentation: {identity}")
        source = expected.get(identity)
        _require(source is not None, f"creature presentation references unknown collection: {identity}")
        _require(entry.get("collectionKey") == source["collectionKey"],
                 f"creature presentation key mismatch: {source['collectionKey']}")
        _require(entry.get("lifecycle") == source["lifecycle"],
                 f"creature presentation lifecycle mismatch: {source['collectionKey']}")
        _require(entry.get("presentationStatus") in {"READY", "DISABLED", "EXCLUDED"},
                 f"invalid creature presentation status: {source['collectionKey']}")
        _require(int(entry.get("previewCreatureEntry", 0)) > 0,
                 f"invalid preview creature Entry: {source['collectionKey']}")
        if source["lifecycle"] == "active":
            _require(entry["presentationStatus"] == "READY",
                     f"active creature presentation is not ready: {source['collectionKey']}")
            _require(int(entry.get("iconSpellId", 0)) > 0,
                     f"active creature presentation has no icon spell: {source['collectionKey']}")
            _require(re.match(r"^Interface[\\/]Icons[\\/]", str(entry.get("iconTexture", "")), re.IGNORECASE) is not None,
                     f"active creature presentation has no native icon: {source['collectionKey']}")
        actual[identity] = entry
    _require(set(actual) == set(expected), "creature presentation coverage must match mount/companion catalog")
    return data


def _load_appearance_presentations(source_root: Path, collections: list[dict[str, Any]]) -> dict[str, Any]:
    path = source_root.parent / "generated" / "appearance-presentation-report.json"
    data = deepcopy(_read_json(path))
    _require(data.get("schemaVersion") == 3, "unsupported appearance presentation schema version")
    entries = data.get("entries")
    _require(isinstance(entries, list) and entries, "appearance presentation report has no entries")
    _require(isinstance(data.get("assetPackVersion"), str) and data["assetPackVersion"],
             "appearance presentation asset pack version is missing")
    _require(isinstance(data.get("publicAppearanceCount"), int) and data["publicAppearanceCount"] > 0,
             "appearance presentation public denominator is invalid")
    terminal_counts = data.get("terminalCounts")
    _require(isinstance(terminal_counts, dict) and all(isinstance(terminal_counts.get(key), int)
             for key in ("READY", "UNAVAILABLE")), "appearance presentation terminal counts are invalid")
    expected = {
        int(entry["collectionId"]): entry
        for entry in collections if entry["typeKey"] == "appearance"
    }
    actual: dict[int, dict[str, Any]] = {}
    ready = 0
    unavailable = 0
    retained = 0
    for entry in entries:
        appearance_id = int(entry.get("appearanceId", 0))
        source = expected.get(appearance_id)
        _require(source is not None, f"appearance presentation references unknown canonical ID: {appearance_id}")
        _require(entry.get("collectionKey") == source["collectionKey"],
                 f"appearance presentation key drift: {appearance_id}")
        _require(entry.get("sourceAlias") in source.get("aliases", []),
                  f"appearance presentation source alias drift: {appearance_id}")
        _require(entry.get("assetPackVersion") == data["assetPackVersion"],
                 f"appearance presentation asset pack drift: {appearance_id}")
        status = entry.get("presentationStatus")
        if status in {"READY", "RETAINED_BASELINE"}:
            _require(entry.get("renderMode") == "STANDALONE"
                     and entry.get("presentationCapability") == "DIRECT_DISPLAY_V1",
                     f"appearance presentation capability drift: {appearance_id}")
            _require(re.match(r"^m2:[a-f0-9]{64}$", str(entry.get("modelSignature", ""))) is not None,
                     f"appearance presentation has invalid model signature: {appearance_id}")
            _require(0 < int(entry.get("syntheticDisplayId", 0)) <= 0x00FFFFFF,
                     f"appearance presentation has unsafe synthetic display: {appearance_id}")
            auto_camera = entry.get("autoCamera")
            _require(isinstance(auto_camera, dict) and all(key in auto_camera for key in (
                "yaw", "pitch", "roll", "distanceScale", "target",
            )), f"appearance presentation has incomplete automatic camera: {appearance_id}")
            if status == "READY":
                ready += 1
            else:
                _require(entry.get("presentationAudience") == "NONPUBLIC_BASELINE",
                         f"appearance presentation retained baseline audience drift: {appearance_id}")
                retained += 1
        elif status == "UNAVAILABLE":
            _require(entry.get("renderMode") == "UNAVAILABLE"
                     and entry.get("presentationCapability") == "UNAVAILABLE"
                     and entry.get("presentationReasonCode"),
                     f"appearance presentation unavailable verdict drift: {appearance_id}")
            unavailable += 1
        else:
            raise CatalogError(f"appearance presentation has unsupported status: {appearance_id}")
        _require(appearance_id not in actual, f"duplicate appearance presentation: {appearance_id}")
        actual[appearance_id] = entry
    _require(ready == int(terminal_counts["READY"]) and unavailable == int(terminal_counts["UNAVAILABLE"]),
             "appearance presentation terminal counts drift")
    _require(ready + unavailable == int(data["publicAppearanceCount"]),
             "appearance presentation public denominator drift")
    _require(retained == int(data.get("retainedNonPublicBaselineCount", 0)),
             "appearance presentation retained baseline count drift")
    return data


def _parse_legacy_sc1_table(lua_text: str, table_name: str) -> list[dict[str, Any]]:
    table = re.search(rf"(?ms)^local\s+{re.escape(table_name)}\s*=\s*\{{(.*?)^\}}", lua_text)
    _require(table is not None, f"legacy SC1 table is missing: {table_name}")
    entries: list[dict[str, Any]] = []
    for match in re.finditer(r"(?m)^\s*\[(\d+)\]\s*=\s*\{([^\n]+)\},?\s*$", table.group(1)):
        fields: dict[str, Any] = {"legacyId": int(match.group(1))}
        for field in re.finditer(r"(\w+)\s*=\s*(\d+|true|false)", match.group(2)):
            value = field.group(2)
            fields[field.group(1)] = value == "true" if value in {"true", "false"} else int(value)
        entries.append(fields)
    _require(entries, f"legacy SC1 table is empty: {table_name}")
    _require([entry["legacyId"] for entry in entries] == list(range(1, len(entries) + 1)),
             f"legacy SC1 IDs must be contiguous: {table_name}")
    return entries


def _load_legacy_sc1_shadow(repo_root: Path, model: dict[str, Any]) -> dict[str, Any]:
    path = repo_root / "server" / "ale" / "solo_collections.lua"
    try:
        lua_text = path.read_text(encoding="utf-8").replace("\r\n", "\n").replace("\r", "\n")
        raw = lua_text.encode("utf-8")
    except (OSError, UnicodeDecodeError) as exc:
        raise CatalogError(f"cannot read legacy SC1 bridge {path}: {exc}") from exc

    type_ids = {entry["typeKey"]: int(entry["typeId"]) for entry in model["collectionTypes"]}
    table_specs = (
        ("mount", "MOUNTS", "creatureId"),
        ("companion", "PETS", "creatureId"),
        ("toy", "TOYS", "itemId"),
    )
    parsed: dict[str, list[dict[str, Any]]] = {}
    entries: list[dict[str, Any]] = []

    mount_actions = model["mountActions"]["collections"]
    companion_actions = model["companionActions"]["entries"]
    toy_actions = model["toyActions"]["entries"]

    for type_key, table_name, source_field in table_specs:
        _require(type_key in type_ids, f"legacy SC1 type is not registered: {type_key}")
        rows = _parse_legacy_sc1_table(lua_text, table_name)
        parsed[type_key] = rows
        for row in rows:
            required = {source_field, "spellId", "collected"}
            _require(required <= row.keys(), f"legacy SC1 entry is incomplete: {table_name}[{row['legacyId']}]")
            candidates: list[dict[str, Any]]
            if type_key == "mount":
                candidates = [entry for entry in mount_actions
                              if int(row["spellId"]) in map(int, entry["unlockSpellIds"])
                              and int(row[source_field]) in map(int, entry["creatureIds"])]
            elif type_key == "companion":
                candidates = [entry for entry in companion_actions
                              if int(row["spellId"]) in map(int, entry["unlockSpellIds"])
                              and int(entry["previewCreatureEntry"]) == int(row[source_field])]
            else:
                candidates = [entry for entry in toy_actions
                              if int(entry["spellId"]) == int(row["spellId"])
                              and int(entry[source_field]) == int(row[source_field])]
            _require(len(candidates) <= 1,
                     f"legacy SC1 entry maps to multiple canonical entries: {table_name}[{row['legacyId']}]")
            entries.append({
                "typeKey": type_key,
                "typeId": type_ids[type_key],
                "legacyId": int(row["legacyId"]),
                "canonicalId": int(candidates[0]["collectionId"]) if candidates else 0,
                "legacyOwned": bool(row["collected"]),
                "legacyCatalogKnown": True,
                "legacyAssetReady": int(row[source_field]) > 0 and int(row["spellId"]) > 0,
                "sourceId": int(row[source_field]),
                "actionId": int(row["spellId"]),
            })

    categories = []
    for type_key, _, _ in table_specs:
        category_entries = [entry for entry in entries if entry["typeKey"] == type_key]
        legacy_basis = [{key: entry[key] for key in (
            "legacyId", "legacyOwned", "legacyCatalogKnown", "legacyAssetReady", "sourceId", "actionId")}
            for entry in category_entries]
        categories.append({
            "typeKey": type_key,
            "typeId": type_ids[type_key],
            "legacyMappingHash": _hash(legacy_basis),
            "canonicalMappingHash": model["typeMappingHashes"][type_key],
            "legacyEntryCount": len(category_entries),
            "mappedEntryCount": sum(1 for entry in category_entries if entry["canonicalId"] > 0),
        })

    result = {
        "schemaVersion": 1,
        "sourceHash": hashlib.sha256(raw).hexdigest(),
        "canonicalMappingHash": model["mappingHash"],
        "categories": categories,
        "entries": entries,
    }
    result["mappingHash"] = _hash({"categories": categories, "entries": entries})
    return result


def _load_policies(source_root: Path, class_keys: set[str], race_keys: set[str]) -> list[dict[str, Any]]:
    policies = [_read_json(path) for path in sorted((source_root / "policies").glob("*.json"), key=lambda value: value.name)]
    _require(policies, "at least one policy is required")
    _unique(policies, ("policyKey",), "policies")
    required_arrays = (
        "requiredCapabilities", "anyCapabilities", "forbiddenCapabilities",
        "allowedRaceKeys", "deniedRaceKeys", "allowedClassKeys", "deniedClassKeys",
    )
    for policy in policies:
        for field in required_arrays:
            _require(isinstance(policy.get(field), list), f"policy {policy['policyKey']} field {field} must be an array")
            policy[field] = sorted(set(policy[field]))
        _require(set(policy["allowedClassKeys"] + policy["deniedClassKeys"]) <= class_keys, f"policy {policy['policyKey']} references unknown class")
        _require(set(policy["allowedRaceKeys"] + policy["deniedRaceKeys"]) <= race_keys, f"policy {policy['policyKey']} references unknown race")
        _require(policy.get("factionPolicy") in {"ANY", "ALLIANCE", "HORDE"}, f"policy {policy['policyKey']} has invalid factionPolicy")
        _require(isinstance(policy.get("minimumLevel"), int) and policy["minimumLevel"] >= 0, f"policy {policy['policyKey']} has invalid minimumLevel")
        _require(isinstance(policy.get("requiredSkills"), dict), f"policy {policy['policyKey']} requiredSkills must be an object")
        _require(all(isinstance(rank, int) and rank >= 0 for rank in policy["requiredSkills"].values()), f"policy {policy['policyKey']} has invalid skill rank")
        _require(isinstance(policy.get("legacyFallback"), bool), f"policy {policy['policyKey']} legacyFallback must be boolean")
        policy.setdefault("customPolicyKey", "")
        policy["requiredSkills"] = dict(sorted(policy["requiredSkills"].items()))
    _require(any(policy["policyKey"] == "unrestricted" for policy in policies), "unrestricted policy is required")
    return sorted(policies, key=lambda row: row["policyKey"])


def _derive_class(entry: dict[str, Any]) -> dict[str, Any]:
    result = deepcopy(entry)
    profile = result.get("defaultFilterProfile", {})
    armor = profile.get("armorType")
    _require(armor and isinstance(profile.get("mainhand"), list) and isinstance(profile.get("offhand"), list), f"class {result.get('classKey')} has invalid defaultFilterProfile")
    derived = [f"armor.{armor.lower()}"]
    derived += [f"weapon.{value.lower()}" for value in profile["mainhand"] + profile["offhand"]]
    result["capabilities"] = sorted(set(result.get("capabilities", []) + derived))
    result["aliases"] = sorted(set(result.get("aliases", [])))
    return result


def _canonical_for_hash(model: dict[str, Any], mapping_asset_pack_version: str | None = None) -> dict[str, Any]:
    """Return the server-authoritative identity basis.

    The root asset-pack field historically participated in the mapping hash.
    Keep that one legacy identity value stable while omitting per-presentation
    asset versions, resource hashes, poses and render verdicts.  This lets the
    AddOn/DLL/MPQ contract evolve without changing owned collection identity.
    """

    def clean(value: Any, key: str = "", parent_path: tuple[str, ...] = ()) -> Any:
        if key in {"assetPackVersion", "clientAssetVersion"}:
            # The original mapping contract carried a catalog-wide asset
            # version and each race's client asset version.  Preserve those
            # two legacy identity fields at their mapping-contract value;
            # per-appearance asset versions are a presentation projection and
            # deliberately have no server mapping effect.
            if not parent_path or parent_path == ("races",):
                return mapping_asset_pack_version
            return None
        if key in {
            "name", "icon", "metadataVersion", "iconSpellId", "spellIconId", "iconTexture",
            "presentationStatus", "presentationReasonCode", "presentationHash",
            "presentationEvidenceHash", "presentationEvidenceId", "presentationEvidencePackHash",
            "appearancePresentationHash", "appearancePresentationEvidence", "deprecatedAliases",
            "appearancePresentationPublicCount",
            "presentationHash",
            "nativeDisplayId", "syntheticDisplayId", "modelPath", "modelScale", "weaponType", "weaponCategory",
            "cameraTuningKey", "m2Camera", "modelSignature", "autoCamera", "presentationStatus", "renderMode",
            "presentationCapability", "assetHashes", "retiredSyntheticDisplayId", "registryTombstoneReason",
            "presentationAudience", "baselineSourceSha256", "runtimeProjection", "assetBundle",
            "generatedModelCameraOverride", "modelCameraOverrides",
            "uiLifecycle",
        }:
            return None
        if isinstance(value, dict):
            child_parent = parent_path + ((key,) if key else ())
            return {
                child_key: cleaned
                for child_key in sorted(value)
                if (cleaned := clean(value[child_key], child_key, child_parent)) is not None
            }
        if isinstance(value, list):
            return [clean(item, parent_path=parent_path + ((key,) if key else ())) for item in value]
        return value
    return clean(model)


def _hash(value: Any) -> str:
    encoded = json.dumps(value, ensure_ascii=False, sort_keys=True, separators=(",", ":")).encode("utf-8")
    return hashlib.sha256(encoded).hexdigest()


def build_model(source_root: Path) -> dict[str, Any]:
    source_root = source_root.resolve()
    versions = _read_json(source_root / "versions.json")
    ids = _read_json(source_root.parent / "ids.json")
    type_data = _read_json(source_root / "collection_types.json")
    class_data = _read_json(source_root / "classes.json")
    race_data = _read_json(source_root / "races.json")
    types = deepcopy(type_data.get("entries", []))
    classes = [_derive_class(entry) for entry in class_data.get("entries", [])]
    races = deepcopy(race_data.get("entries", []))
    _require(versions.get("schemaVersion") == 1 and ids.get("schemaVersion") == 1, "unsupported catalog schema version")
    for entry in types:
        entry["typeId"] = int(entry["typeId"])
        entry.setdefault("lifecycle", "active")
    for entry in classes:
        entry["ordinal"] = next((int(row["ordinal"]) for row in ids["reservations"]["classes"] if row["key"] == entry["classKey"]), -1)
    for entry in races:
        entry["ordinal"] = next((int(row["ordinal"]) for row in ids["reservations"]["races"] if row["key"] == entry["raceKey"]), -1)
        entry.setdefault("appearanceOverrideProfile", entry["compatibilityProfile"])
        entry.setdefault("clientAssetVersion", versions["assetPackVersion"])
        entry.setdefault("modelProfile", entry["clientAssetProfile"])
    _validate_reservations(ids["reservations"]["collectionTypes"], types, "typeId", "typeKey", "collection types")
    _validate_reservations(ids["reservations"]["classes"], classes, "logicalClassId", "classKey", "classes")
    _validate_reservations(ids["reservations"]["races"], races, "logicalRaceId", "raceKey", "races")
    _unique(classes, ("runtimeClassId", "sourceId", "legacyMaskBit"), "classes")
    _unique(races, ("runtimeRaceId", "sourceId"), "races")
    _validate_dependency_graph(types)
    class_keys = {entry["classKey"] for entry in classes}
    race_keys = {entry["raceKey"] for entry in races}
    type_keys = {entry["typeKey"] for entry in types}
    aliases = _validate_aliases(ids, {"class": class_keys, "race": race_keys, "collectionType": type_keys})
    policies = _load_policies(source_root, class_keys, race_keys)
    policy_keys = {entry["policyKey"] for entry in policies}
    collections = _parse_collections(source_root, type_keys)
    _validate_reservations(ids["reservations"].get("collections", []), collections, "collectionId", "collectionKey", "collections")
    for entry in collections:
        _require(entry["policyKey"] in policy_keys, f"collection {entry['collectionKey']} references unknown policy")
        lifecycle = entry["lifecycle"]
        entry["catalogLifecycle"] = {"active": "ACTIVE", "tombstone": "TOMBSTONE"}[lifecycle]
        entry["uiLifecycle"] = "public" if lifecycle == "active" else "deprecated"
    visibility = _read_json(source_root.parent / "review" / "appearances" / "visibility-evidence.json")
    _require(visibility.get("schemaVersion") == 1 and visibility.get("reviewUnitCount") ==
             sum(1 for entry in collections if entry["typeKey"] == "appearance"),
             "appearance visibility review is missing or incomplete")
    visibility_by_id = {int(entry["appearanceId"]): entry for entry in visibility.get("decisions", [])}
    _require(len(visibility_by_id) == visibility.get("reviewUnitCount"), "duplicate appearance visibility decision")
    allowed_ui_lifecycles = {"public", "hidden_internal", "deprecated", "test", "unobtainable", "deferred"}
    for entry in collections:
        if entry["typeKey"] != "appearance":
            continue
        decision = visibility_by_id.get(int(entry["collectionId"]))
        _require(decision is not None and decision.get("collectionKey") == entry["collectionKey"],
                 f"appearance visibility identity drift: {entry['collectionKey']}")
        _require(decision.get("uiLifecycle") in allowed_ui_lifecycles,
                 f"invalid appearance UI lifecycle: {entry['collectionKey']}")
        _require(decision.get("catalogLifecycle") == entry["catalogLifecycle"],
                 f"appearance visibility changed catalog authorization: {entry['collectionKey']}")
        entry["uiLifecycle"] = decision["uiLifecycle"]
    overrides_data = _read_json(source_root / "overrides" / "identity_overrides.json")
    overrides = deepcopy(overrides_data.get("entries", []))
    seen_override: set[tuple[Any, ...]] = set()
    for override in overrides:
        _require(override.get("outcome") in {"ALLOW", "DENY"}, "identity override outcome must be ALLOW or DENY")
        _require(override.get("collectionKey") in {entry["collectionKey"] for entry in collections}, "identity override references unknown collection")
        if override.get("classKey"):
            _require(override["classKey"] in class_keys, "identity override references unknown class")
        if override.get("raceKey"):
            _require(override["raceKey"] in race_keys, "identity override references unknown race")
        identity = (override.get("collectionKey"), override.get("classKey", ""), override.get("raceKey", ""))
        _require(identity not in seen_override, f"duplicate identity override: {identity}")
        seen_override.add(identity)
    mount_actions = _apply_mount_journal_contract(source_root, _load_mount_actions(source_root, collections))
    companion_actions = _apply_companion_journal_contract(
        source_root, _load_companion_actions(source_root, collections),
    )
    toy_actions = _load_toy_actions(source_root, collections)
    creature_presentations = _load_creature_presentations(source_root, collections)
    appearance_presentations = _load_appearance_presentations(source_root, collections)
    _require(appearance_presentations["assetPackVersion"] == versions["assetPackVersion"],
             "appearance presentation asset pack version drift")
    presentation_by_identity = {
        (entry["typeKey"], int(entry["collectionId"])): entry
        for entry in creature_presentations["entries"]
    }
    for entry in collections:
        presentation = presentation_by_identity.get((entry["typeKey"], int(entry["collectionId"])))
        if presentation is None:
            continue
        entry["previewCreatureEntry"] = int(presentation["previewCreatureEntry"])
        entry["iconSpellId"] = int(presentation["iconSpellId"])
        entry["spellIconId"] = int(presentation["spellIconId"])
        entry["iconTexture"] = presentation["iconTexture"]
        entry["presentationStatus"] = presentation["presentationStatus"]
        entry["presentationReasonCode"] = presentation.get("reasonCode", "")
    appearance_by_id = {
        int(entry["appearanceId"]): entry for entry in appearance_presentations["entries"]
    }
    weapon_slots = {"MAINHAND", "OFFHAND"}
    for entry in collections:
        if entry["typeKey"] != "appearance":
            continue
        slot = next((alias.split(":", 1)[1] for alias in entry.get("aliases", [])
                     if alias.startswith("slot:")), "")
        presentation = appearance_by_id.get(int(entry["collectionId"]))
        if presentation is not None:
            for key in ("nativeDisplayId", "syntheticDisplayId", "modelPath", "modelScale", "weaponType",
                         "weaponCategory", "cameraTuningKey", "m2Camera", "modelSignature",
                         "autoCamera", "presentationStatus", "presentationReasonCode",
                         "generatedModelCameraOverride",
                         "presentationCapability", "assetPackVersion", "retiredSyntheticDisplayId",
                         "registryTombstoneReason", "presentationAudience"):
                if key in presentation:
                    entry[key] = deepcopy(presentation[key])
            entry["renderMode"] = presentation["renderMode"]
        elif slot in weapon_slots:
            entry["renderMode"] = "UNAVAILABLE"
        else:
            entry["renderMode"] = "BODY"
    model = {
        "schemaVersion": 1,
        "metadataVersion": versions["metadataVersion"],
        "assetPackVersion": versions["assetPackVersion"],
        "policyVersion": versions["policyVersion"],
        "collectionTypes": sorted(types, key=lambda row: row["ordinal"]),
        "classes": sorted(classes, key=lambda row: row["ordinal"]),
        "races": sorted(races, key=lambda row: row["ordinal"]),
        "policies": policies,
        "collections": collections,
        "mountActions": mount_actions,
        "companionActions": companion_actions,
        "toyActions": toy_actions,
        "aliases": aliases,
        "identityOverrides": sorted(overrides, key=lambda row: (row.get("collectionKey", ""), row.get("classKey", ""), row.get("raceKey", ""))),
        "presentationEvidenceHash": creature_presentations["presentationHash"],
        "presentationEvidenceId": creature_presentations["evidenceId"],
        "presentationEvidencePackHash": creature_presentations["evidencePackHash"],
        "appearancePresentationHash": _hash(appearance_presentations["entries"]),
        "appearancePresentationEvidence": {
            "baselineSourceSha256": appearance_presentations["baselineSourceSha256"],
            "runtimeProjection": appearance_presentations["runtimeProjection"],
            "assetBundle": appearance_presentations["assetBundle"],
            "modelCameraOverrides": appearance_presentations["modelCameraOverrides"],
        },
        "appearancePresentationPublicCount": appearance_presentations["publicAppearanceCount"],
        "deprecatedAliases": {"displayCreatureId": "previewCreatureEntry"},
    }
    presentation_basis = [
        {
            key: entry.get(key)
            for key in (
                "typeKey", "collectionId", "collectionKey", "name", "lifecycle", "assetReady",
                "assetProfile", "previewCreatureEntry", "iconSpellId", "spellIconId", "iconTexture",
                "presentationStatus", "presentationReasonCode",
                "uiLifecycle",
                "renderMode", "nativeDisplayId", "syntheticDisplayId", "modelPath", "modelScale", "weaponType",
                "weaponCategory", "cameraTuningKey", "m2Camera", "modelSignature", "autoCamera",
                "generatedModelCameraOverride",
                "presentationCapability", "assetPackVersion", "retiredSyntheticDisplayId",
                "registryTombstoneReason", "presentationAudience",
            )
        }
        for entry in collections
    ]
    model["presentationHash"] = _hash(presentation_basis)
    normalized_sets = _read_json(source_root.parent / "generated" / "normalized-itemsets.json")
    _require(normalized_sets.get("schemaVersion") == 2 and len(normalized_sets.get("mappingHash", "")) == 64,
             "normalized ItemSet mapping is missing or invalid")
    model["setCatalogMappingHash"] = normalized_sets["mappingHash"]
    mapping_basis = _canonical_for_hash(model, str(versions.get("mappingAssetPackVersion", versions["assetPackVersion"])))
    model["mappingHash"] = _hash(mapping_basis)
    model["typeMappingHashes"] = {}
    for entry in model["collectionTypes"]:
        basis: Any = [row for row in mapping_basis["collections"] if row["typeKey"] == entry["typeKey"]]
        if entry["typeKey"] == "mount":
            basis = {"collections": basis, "actions": mapping_basis["mountActions"]}
        elif entry["typeKey"] == "mount-favorite":
            # Internal type 16 projects preference membership over the exact
            # same stable IDs as the mount catalog; it has no navigation rows.
            basis = {
                "collections": [row for row in mapping_basis["collections"] if row["typeKey"] == "mount"],
                "actions": mapping_basis["mountActions"],
            }
        elif entry["typeKey"] == "companion":
            basis = {"collections": basis, "actions": mapping_basis["companionActions"]}
        elif entry["typeKey"] == "companion-favorite":
            # Internal type 17 projects preference membership over the exact
            # same stable IDs as the companion catalog; it has no navigation rows.
            basis = {
                "collections": [
                    row for row in mapping_basis["collections"] if row["typeKey"] == "companion"
                ],
                "actions": mapping_basis["companionActions"],
            }
        elif entry["typeKey"] == "toy":
            basis = {"collections": basis, "actions": mapping_basis["toyActions"]}
        model["typeMappingHashes"][entry["typeKey"]] = (
            model["setCatalogMappingHash"] if entry["typeKey"] == "set" else _hash(basis)
        )
    return model


def _lua_string(value: str) -> str:
    return json.dumps(value, ensure_ascii=False).replace("/", "\\/")


def _lua(value: Any, indent: int = 0) -> str:
    pad = "    " * indent
    if value is None:
        return "nil"
    if value is True:
        return "true"
    if value is False:
        return "false"
    if isinstance(value, (int, float)):
        return str(value)
    if isinstance(value, str):
        return _lua_string(value)
    if isinstance(value, list):
        if not value:
            return "{}"
        return "{\n" + ",\n".join(f"{'    ' * (indent + 1)}{_lua(item, indent + 1)}" for item in value) + f"\n{pad}}}"
    if isinstance(value, dict):
        if not value:
            return "{}"
        rows = []
        for key in sorted(value):
            rendered_key = key if key.replace("_", "a").isalnum() and not key[0].isdigit() else f"[{_lua_string(key)}]"
            rows.append(f"{'    ' * (indent + 1)}{rendered_key} = {_lua(value[key], indent + 1)}")
        return "{\n" + ",\n".join(rows) + f"\n{pad}}}"
    raise TypeError(type(value))


def _cpp_string(value: str) -> str:
    return '"' + value.replace("\\", "\\\\").replace('"', '\\"') + '"'


def _cpp_strings(values: Iterable[str]) -> str:
    return "{" + ", ".join(_cpp_string(value) for value in values) + "}"


def _cpp_uints(values: Iterable[int]) -> str:
    return "{" + ", ".join(str(int(value)) + "u" for value in values) + "}"


def _identity_inc(model: dict[str, Any]) -> str:
    lines = ["// Generated by tools/catalog/generate_catalog.py. Do not edit.", ""]
    lines += ["static std::vector<ClassIdentityDefinition> LoadGeneratedClassIdentities()", "{", "    return {"]
    for entry in model["classes"]:
        profile = entry["defaultFilterProfile"]
        lines.append(
            "        {" + ", ".join([
                f"LogicalClassId{{{entry['logicalClassId']}}}", _cpp_string(entry["classKey"]), str(entry["runtimeClassId"]),
                _cpp_strings(entry["aliases"]), _cpp_strings(entry["capabilities"]),
                _cpp_string(entry["compatibilityProfile"]), _cpp_string(entry["clientAssetProfile"]),
                str(entry["legacyMaskBit"]), _cpp_string(profile["armorType"]),
                _cpp_strings(profile["mainhand"]), _cpp_strings(profile["offhand"]),
            ]) + "},"
        )
    lines += ["    };", "}", "", "static std::vector<RaceIdentityDefinition> LoadGeneratedRaceIdentities()", "{", "    return {"]
    for entry in model["races"]:
        lines.append(
            "        {" + ", ".join([
                f"LogicalRaceId{{{entry['logicalRaceId']}}}", _cpp_string(entry["raceKey"]), str(entry["runtimeRaceId"]),
                _cpp_strings(entry.get("aliases", [])), _cpp_strings(entry.get("capabilities", [])),
                _cpp_string(entry["factionKey"]), _cpp_string(entry["compatibilityProfile"]),
                _cpp_string(entry["clientAssetProfile"]), _cpp_string(entry["cameraProfile"]),
                _cpp_string(entry["appearanceOverrideProfile"]), _cpp_string(entry["clientAssetVersion"]),
                _cpp_string(entry["modelProfile"]),
            ]) + "},"
        )
    lines += ["    };", "}", ""]
    return "\n".join(lines)


def _policy_inc(model: dict[str, Any]) -> str:
    lines = ["// Generated by tools/catalog/generate_catalog.py. Do not edit.", "", "static std::vector<EligibilityPolicyDefinition> LoadGeneratedEligibilityPolicies()", "{", "    return {"]
    for entry in model["policies"]:
        skills = "{" + ", ".join("{" + _cpp_string(key) + ", " + str(value) + "}" for key, value in entry["requiredSkills"].items()) + "}"
        lines.append(
            "        {" + ", ".join([
                _cpp_string(entry["policyKey"]), _cpp_strings(entry["requiredCapabilities"]),
                _cpp_strings(entry["anyCapabilities"]), _cpp_strings(entry["forbiddenCapabilities"]),
                _cpp_strings(entry["allowedRaceKeys"]), _cpp_strings(entry["deniedRaceKeys"]),
                _cpp_strings(entry["allowedClassKeys"]), _cpp_strings(entry["deniedClassKeys"]),
                _cpp_string(entry["factionPolicy"]), str(entry["minimumLevel"]), skills,
                _cpp_string(entry["customPolicyKey"]), "true" if entry["legacyFallback"] else "false",
            ]) + "},"
        )
    lines += ["    };", "}", ""]
    return "\n".join(lines)


def _protocol_catalog_inc(model: dict[str, Any]) -> str:
    lines = [
        "// Generated by tools/catalog/generate_catalog.py. Do not edit.",
        f"static constexpr std::uint32_t GeneratedCatalogSchemaVersion = {model['schemaVersion']}u;",
        f"static constexpr std::string_view GeneratedCatalogVersion = {_cpp_string(model['metadataVersion'])};",
        f"static constexpr std::string_view GeneratedIdentityVersion = {_cpp_string(model['metadataVersion'])};",
        f"static constexpr std::string_view GeneratedSc2MetadataVersion = {_cpp_string(model['metadataVersion'])};",
        f"static constexpr std::string_view GeneratedSc2AssetPackVersion = {_cpp_string(model['assetPackVersion'])};",
        "",
        "static std::vector<Sc2CategoryDefinition> LoadGeneratedSc2Categories()",
        "{",
        "    return {",
    ]
    for entry in model["collectionTypes"]:
        lines.append(
            "        { CollectionTypeId(std::uint16_t { " + str(entry["typeId"]) +
            " }), " + _cpp_string(model["typeMappingHashes"][entry["typeKey"]]) + ", false },"
        )
    lines += ["    };", "}", ""]
    return "\n".join(lines)


def _mount_catalog_inc(model: dict[str, Any]) -> str:
    lines = [
        "// Generated by tools/catalog/generate_catalog.py. Do not edit.",
        "",
        "static std::vector<MountCollectionDefinition> LoadGeneratedMountCollections()",
        "{",
        "    return {",
    ]
    collections = {int(entry["collectionId"]): entry for entry in model["collections"]}
    lifecycle_names = {
        "ACTIVE": "CatalogLifecycle::Active",
        "PREVIEW_ONLY": "CatalogLifecycle::PreviewOnly",
        "DISABLED": "CatalogLifecycle::Disabled",
        "TOMBSTONE": "CatalogLifecycle::Tombstone",
    }
    capability_names = {
        "GROUND": "MountCapability::Ground", "FLYING": "MountCapability::Flying",
        "AQUATIC": "MountCapability::Aquatic", "SPECIAL": "MountCapability::Special",
    }
    exclusion_names = {
        None: "MountExclusionReason::None", "TAXI": "MountExclusionReason::Taxi",
        "QUEST_TEMPORARY": "MountExclusionReason::QuestTemporary",
        "CLASS_FORM": "MountExclusionReason::ClassForm", "TEST": "MountExclusionReason::Test",
        "DUPLICATE": "MountExclusionReason::Duplicate", "INTERNAL": "MountExclusionReason::Internal",
    }
    for entry in model["mountActions"]["collections"]:
        collection = collections[int(entry["collectionId"])]
        variants = []
        for variant in entry["actionVariants"]:
            variants.append(
                "{" + ", ".join([
                    str(int(variant["spellId"])) + "u",
                    _cpp_uints(variant["raceMasks"]),
                    _cpp_uints(variant["classMasks"]),
                    str(int(variant["minimumRidingSkill"])) + "u",
                    "true" if variant["isFlying"] else "false",
                ]) + "}"
            )
        lines.append(
            "        {" + ", ".join([
                f"CollectionId{{{entry['collectionId']}u}}", _cpp_string(entry["collectionKey"]),
                str(int(entry["canonicalSpellId"])) + "u", _cpp_uints(entry["creatureIds"]),
                _cpp_uints(entry["unlockSpellIds"]), "{" + ", ".join(variants) + "}",
                str(int(collection["previewCreatureEntry"])) + "u",
                lifecycle_names[collection["catalogLifecycle"]],
                "true" if entry["journalVisible"] else "false",
                "true" if entry["actionable"] else "false",
                "true" if entry["draggable"] else "false",
                "true" if entry["randomEligible"] else "false",
                str(int(entry["canonicalActionSpellId"])) + "u",
                capability_names[entry["capability"]],
                exclusion_names[entry["exclusionReason"]],
            ]) + "},"
        )
    lines += ["    };", "}", ""]
    return "\n".join(lines)


def _companion_catalog_inc(model: dict[str, Any]) -> str:
    lines = [
        "// Generated by tools/catalog/generate_catalog.py. Do not edit.", "",
        "static std::vector<CompanionCollectionDefinition> LoadGeneratedCompanionCollections()", "{", "    return {",
    ]
    collections = {int(entry["collectionId"]): entry for entry in model["collections"]}
    lifecycle_names = {
        "ACTIVE": "CatalogLifecycle::Active",
        "PREVIEW_ONLY": "CatalogLifecycle::PreviewOnly",
        "DISABLED": "CatalogLifecycle::Disabled",
        "TOMBSTONE": "CatalogLifecycle::Tombstone",
    }
    for entry in model["companionActions"]["entries"]:
        collection = collections[int(entry["collectionId"])]
        lines.append(
            "        {" + ", ".join([
                f"CollectionId{{{entry['collectionId']}u}}", _cpp_string(entry["collectionKey"]),
                str(int(entry["canonicalSpellId"])) + "u", _cpp_uints(entry["unlockSpellIds"]),
                str(int(collection["previewCreatureEntry"])) + "u",
                lifecycle_names[collection["catalogLifecycle"]],
                "true" if entry["journalVisible"] else "false",
                "true" if entry["actionable"] else "false",
                "true" if entry["randomEligible"] else "false",
                str(int(entry["canonicalActionSpellId"])) + "u",
            ]) + "},"
        )
    lines += ["    };", "}", ""]
    return "\n".join(lines)


def _toy_catalog_inc(model: dict[str, Any]) -> str:
    action_names = {
        "SPELL_SELF": "ToyActionKind::SpellSelf", "SPELL_TARGET": "ToyActionKind::SpellTarget",
        "ITEM_USE": "ToyActionKind::ItemUse", "CUSTOM_HANDLER": "ToyActionKind::CustomHandler",
    }
    target_names = {
        "NONE": "ToyTargetPolicy::None", "SELF": "ToyTargetPolicy::Self",
        "OPTIONAL_UNIT": "ToyTargetPolicy::OptionalUnit", "REQUIRED_UNIT": "ToyTargetPolicy::RequiredUnit",
    }
    cooldown_names = {
        "NONE": "ToyCooldownScope::None", "CHARACTER": "ToyCooldownScope::Character",
        "ACCOUNT": "ToyCooldownScope::Account", "HANDLER_NATIVE": "ToyCooldownScope::HandlerNative",
    }
    replay_names = {
        "REJECT_DUPLICATE": "ToyReplayPolicy::RejectDuplicate", "IDEMPOTENT": "ToyReplayPolicy::Idempotent",
    }
    lifecycle_names = {
        "ACTIVE": "ToyCatalogLifecycle::Active", "PREVIEW_ONLY": "ToyCatalogLifecycle::PreviewOnly",
        "DISABLED": "ToyCatalogLifecycle::Disabled", "TOMBSTONE": "ToyCatalogLifecycle::Tombstone",
    }
    lines = [
        "// Generated by tools/catalog/generate_catalog.py. Do not edit.", "",
        "static std::vector<ToyCollectionDefinition> LoadGeneratedToyCollections()", "{", "    return {",
    ]
    for entry in model["toyActions"]["entries"]:
        lines.append(
            "        {" + ", ".join([
                f"CollectionId{{{entry['collectionId']}u}}", _cpp_string(entry["collectionKey"]),
                str(int(entry["itemId"])) + "u", action_names[entry["actionKind"]],
                str(int(entry["spellId"])) + "u", target_names[entry["targetPolicy"]],
                cooldown_names[entry["cooldownScope"]], str(int(entry["accountCooldownMs"])) + "u",
                "true" if entry["allowInCombat"] else "false",
                "true" if entry["consumesMaterial"] else "false",
                _cpp_string(entry["customHandler"]), replay_names[entry["replayPolicy"]],
                _cpp_strings(entry["riskFlags"]), lifecycle_names[entry["catalogLifecycle"]],
            ]) + "},"
        )
    lines += ["    };", "}", ""]
    return "\n".join(lines)


def _legacy_shadow_catalog_inc(shadow: dict[str, Any]) -> str:
    lines = [
        "// Generated by tools/catalog/generate_catalog.py from server/ale/solo_collections.lua. Do not edit.",
        f"static constexpr std::string_view GeneratedLegacySc1SourceHash = {_cpp_string(shadow['sourceHash'])};",
        f"static constexpr std::string_view GeneratedLegacySc1MappingHash = {_cpp_string(shadow['mappingHash'])};",
        f"static constexpr std::string_view GeneratedCanonicalMappingHash = {_cpp_string(shadow['canonicalMappingHash'])};",
        "",
        "static std::vector<LegacyShadowCategoryDefinition> LoadGeneratedLegacyShadowCategories()",
        "{",
        "    return {",
    ]
    for entry in shadow["categories"]:
        lines.append(
            "        {" + ", ".join([
                f"CollectionTypeId{{{entry['typeId']}u}}", _cpp_string(entry["typeKey"]),
                _cpp_string(entry["legacyMappingHash"]), _cpp_string(entry["canonicalMappingHash"]),
                str(int(entry["legacyEntryCount"])) + "u", str(int(entry["mappedEntryCount"])) + "u",
            ]) + "},"
        )
    lines += ["    };", "}", "", "static std::vector<LegacyShadowEntryDefinition> LoadGeneratedLegacyShadowEntries()", "{", "    return {"]
    for entry in shadow["entries"]:
        lines.append(
            "        {" + ", ".join([
                f"CollectionTypeId{{{entry['typeId']}u}}", str(int(entry["legacyId"])) + "u",
                f"CollectionId{{{entry['canonicalId']}u}}",
                "true" if entry["legacyOwned"] else "false",
                "true" if entry["legacyCatalogKnown"] else "false",
                "true" if entry["legacyAssetReady"] else "false",
            ]) + "},"
        )
    lines += ["    };", "}", ""]
    return "\n".join(lines)


def render_outputs(model: dict[str, Any], repo_root: Path, module_root: Path) -> dict[Path, str]:
    legacy_shadow = _load_legacy_sc1_shadow(repo_root, model)
    manifest = deepcopy(model)
    missing = {
        "schemaVersion": 1,
        "mappingHash": model["mappingHash"],
        "entries": [
            {key: entry[key] for key in ("typeKey", "collectionId", "collectionKey", "assetProfile")}
            for entry in model["collections"] if not entry["assetReady"]
        ],
    }
    json_text = json.dumps(manifest, ensure_ascii=False, sort_keys=True, indent=2) + "\n"
    missing_text = json.dumps(missing, ensure_ascii=False, sort_keys=True, indent=2) + "\n"
    mount_actions_text = json.dumps(model["mountActions"], ensure_ascii=False, sort_keys=True, indent=2) + "\n"
    companion_actions_text = json.dumps(model["companionActions"], ensure_ascii=False, sort_keys=True, indent=2) + "\n"
    toy_actions_text = json.dumps(model["toyActions"], ensure_ascii=False, sort_keys=True, indent=2) + "\n"
    legacy_shadow_text = json.dumps(legacy_shadow, ensure_ascii=False, sort_keys=True, indent=2) + "\n"
    client_collections = deepcopy(model["collections"])
    mount_actions_by_id = {
        int(entry["collectionId"]): entry for entry in model["mountActions"]["collections"]
    }
    mount_journal = _read_json(repo_root / "catalog/source/mount_journal_metadata.json")
    mount_journal_by_id = {
        int(entry["collectionId"]): entry for entry in mount_journal["entries"]
    }
    _require(
        set(mount_journal_by_id) == set(mount_actions_by_id),
        "mount journal metadata must cover every canonical mount action",
    )
    companion_actions_by_id = {
        int(entry["collectionId"]): entry for entry in model["companionActions"]["entries"]
    }
    companion_journal = _read_json(repo_root / "catalog/source/companion_journal_metadata.json")
    companion_journal_by_id = {
        int(entry["collectionId"]): entry for entry in companion_journal["entries"]
    }
    _require(
        set(companion_journal_by_id) == set(companion_actions_by_id),
        "companion journal metadata must cover every canonical companion action",
    )
    toy_actions_by_id = {
        int(entry["collectionId"]): entry for entry in model["toyActions"]["entries"]
    }
    mount_evidence = _read_json(repo_root / "catalog/review/mounts/evidence.json")
    alliance_mask = 1101
    horde_mask = 690
    faction_by_spell: dict[int, str] = {}
    for candidate in mount_evidence.get("candidates", []):
        masks = {
            int(source.get("allowableRace", 0))
            for source in candidate.get("itemSources", [])
            if int(source.get("allowableRace", 0)) > 0
        }
        masks.update(
            int(source.get("raceMask", 0))
            for source in candidate.get("skillLineAbilities", [])
            if int(source.get("raceMask", 0)) > 0
        )
        faction = None
        if masks and all(mask & ~alliance_mask == 0 for mask in masks):
            faction = "ALLIANCE"
        elif masks and all(mask & ~horde_mask == 0 for mask in masks):
            faction = "HORDE"
        if faction:
            faction_by_spell[int(candidate["spellId"])] = faction
    for entry in client_collections:
        if entry["typeKey"] == "mount":
            entry["displayCreatureId"] = int(entry["previewCreatureEntry"])
            action = mount_actions_by_id[int(entry["collectionId"])]
            entry["spellId"] = int(action["canonicalSpellId"])
            entry["faction"] = faction_by_spell.get(entry["spellId"])
            journal = mount_journal_by_id[int(entry["collectionId"])]
            _require(entry["spellId"] == int(journal["spellId"]),
                     f"mount journal spell drift: {entry['collectionId']}")
            entry["sourceText"] = journal["source"]
            entry["mountType"] = journal.get("mountType")
            entry["flags"] = int(journal.get("flags") or 0)
            entry["sourceType"] = journal.get("sourceType")
            entry["descriptionKey"] = int(journal.get("descriptionKey") or entry["spellId"])
            entry["descriptionStatus"] = journal.get("descriptionStatus") or "MISSING"
            if journal.get("journalNameZhCN"):
                entry["name"]["zhCN"] = journal["journalNameZhCN"]
            entry["journalVisible"] = bool(journal.get("journalVisible", journal["uiCollectible"]))
            entry["actionable"] = bool(journal["actionable"])
            entry["draggable"] = bool(journal["draggable"])
            entry["randomEligible"] = bool(journal["randomEligible"])
            entry["canonicalActionSpellId"] = int(journal.get("canonicalActionSpellId") or 0)
            entry["capability"] = journal["capability"]
            entry["exclusionReason"] = journal.get("exclusionReason")
            entry["acquisitionClass"] = journal.get("acquisitionClass") or "STANDARD"
            entry["visibilityReason"] = journal.get("visibilityReason", journal.get("exclusionReason"))
            entry["uiCollectible"] = entry["journalVisible"]
            entry["uiExclusionReason"] = entry["visibilityReason"]
        elif entry["typeKey"] == "companion":
            entry["displayCreatureId"] = int(entry["previewCreatureEntry"])
            action = companion_actions_by_id[int(entry["collectionId"])]
            journal = companion_journal_by_id[int(entry["collectionId"])]
            _require(int(action["canonicalSpellId"]) == int(journal["spellId"]),
                     f"companion journal spell drift: {entry['collectionId']}")
            entry["spellId"] = int(action["canonicalSpellId"])
            entry["sourceText"] = journal["source"]
            entry["sourceType"] = int(journal["sourceType"])
            entry["descriptionZhCN"] = journal.get("descriptionZhCN") or ""
            entry["descriptionStatus"] = journal.get("descriptionStatus") or "MISSING"
            entry["journalVisible"] = bool(journal["journalVisible"])
            entry["actionable"] = bool(journal["actionable"])
            entry["randomEligible"] = bool(journal["randomEligible"])
            entry["canonicalActionSpellId"] = int(journal.get("canonicalActionSpellId") or 0)
            entry["acquisitionClass"] = journal.get("acquisitionClass") or "STANDARD"
            entry["visibilityReason"] = journal.get("visibilityReason")
            entry["exclusionReason"] = journal.get("exclusionReason")
            entry["uiCollectible"] = entry["journalVisible"]
            entry["uiExclusionReason"] = entry["visibilityReason"]
            if journal.get("journalNameZhCN"):
                entry["name"]["zhCN"] = journal["journalNameZhCN"]
        elif entry["typeKey"] == "toy":
            action = toy_actions_by_id[int(entry["collectionId"])]
            entry["displayItemId"] = int(action["itemId"])
            entry["targetPolicy"] = action["targetPolicy"]
            entry["requiresTarget"] = action["targetPolicy"] == "REQUIRED_UNIT"
        elif entry["typeKey"] == "appearance":
            entry["displayItemId"] = int(entry["sourceId"])
        if entry["typeKey"] in {"mount", "companion", "toy", "appearance", "set"}:
            # The client renders metadata only. Spell/item resolution and all
            # authorization remain server-side; the wire request carries a
            # stable typeId + collectionId and an optional target selector.
            entry.pop("actionId", None)
            entry.pop("sourceId", None)
    startup_collections = [
        entry for entry in client_collections if entry["typeKey"] not in {"appearance", "set"}
    ]
    wardrobe_collections = [
        entry for entry in client_collections if entry["typeKey"] in {"appearance", "set"}
    ]
    catalog_lua = "-- Generated by tools/catalog/generate_catalog.py. Do not edit.\nSoloCollections.GeneratedCatalog = " + _lua({
        "schemaVersion": model["schemaVersion"], "metadataVersion": model["metadataVersion"],
        "assetPackVersion": model["assetPackVersion"], "mappingHash": model["mappingHash"],
        "collectionTypes": model["collectionTypes"], "collections": startup_collections,
        "typeMappingHashes": model["typeMappingHashes"], "presentationHash": model["presentationHash"],
        "presentationEvidenceHash": model["presentationEvidenceHash"],
        "presentationEvidenceId": model["presentationEvidenceId"],
        "presentationEvidencePackHash": model["presentationEvidencePackHash"],
        "appearancePresentationHash": model["appearancePresentationHash"],
        "appearancePresentationEvidence": model["appearancePresentationEvidence"],
        "appearancePresentationPublicCount": model["appearancePresentationPublicCount"],
        "deprecatedAliases": model["deprecatedAliases"],
    }) + "\n"
    wardrobe_catalog_lua = "-- Generated by tools/catalog/generate_catalog.py. Do not edit.\nSoloCollections.GeneratedWardrobeCatalog = " + _lua({
        "schemaVersion": model["schemaVersion"],
        "metadataVersion": model["metadataVersion"],
        "mappingHash": model["mappingHash"],
        "collections": wardrobe_collections,
    }) + "\n"
    identity_lua = "-- Generated by tools/catalog/generate_catalog.py. Do not edit.\nSoloCollections.GeneratedIdentityData = " + _lua({
        "schemaVersion": model["schemaVersion"], "mappingHash": model["mappingHash"],
        "classes": model["classes"], "races": model["races"], "aliases": model["aliases"],
    }) + "\n"
    policy_lua = "-- Generated by tools/catalog/generate_catalog.py. Do not edit.\nSoloCollections.GeneratedPolicyData = " + _lua({
        "policyVersion": model["policyVersion"], "mappingHash": model["mappingHash"],
        "policies": model["policies"], "identityOverrides": model["identityOverrides"],
    }) + "\n"
    return {
        repo_root / "catalog/generated/catalog-manifest.json": json_text,
        repo_root / "catalog/generated/missing-resources.json": missing_text,
        repo_root / "catalog/generated/legacy-sc1-shadow.json": legacy_shadow_text,
        repo_root / "addon/SoloCollections/Data/Generated/Catalog.lua": catalog_lua,
        repo_root / "addon/SoloCollections_WardrobeData/Data/Generated/WardrobeCatalog.lua": wardrobe_catalog_lua,
        repo_root / "addon/SoloCollections/Data/Generated/IdentityRegistry.lua": identity_lua,
        repo_root / "addon/SoloCollections/Data/Generated/PolicyRegistry.lua": policy_lua,
        module_root / "data/generated/solo_collections_catalog_manifest.json": json_text,
        module_root / "data/generated/solo_collections_mount_actions.json": mount_actions_text,
        module_root / "data/generated/solo_collections_companion_actions.json": companion_actions_text,
        module_root / "data/generated/solo_collections_toy_actions.json": toy_actions_text,
        module_root / "data/generated/solo_collections_missing_resources.json": missing_text,
        module_root / "data/generated/solo_collections_legacy_sc1_shadow.json": legacy_shadow_text,
        module_root / "src/generated/SoloCollectionsIdentityData.inc": _identity_inc(model),
        module_root / "src/generated/SoloCollectionsPolicyData.inc": _policy_inc(model),
        module_root / "src/generated/SoloCollectionsProtocolCatalog.inc": _protocol_catalog_inc(model),
        module_root / "src/generated/SoloCollectionsMountCatalog.inc": _mount_catalog_inc(model),
        module_root / "src/generated/SoloCollectionsCompanionCatalog.inc": _companion_catalog_inc(model),
        module_root / "src/generated/SoloCollectionsToyCatalog.inc": _toy_catalog_inc(model),
        module_root / "src/generated/SoloCollectionsLegacyShadowCatalog.inc": _legacy_shadow_catalog_inc(legacy_shadow),
    }


def validate_module_root(repo_root: Path, module_root: Path) -> Path:
    module_root = module_root.resolve()
    _require(module_root != repo_root.resolve(), "module root must not be the SoloCollections repository")
    _require((module_root / ".git").exists(), "module root must be a Git checkout")
    _require((module_root / "src/SoloCollectionsTypes.h").is_file(), "module root does not contain SoloCollectionsTypes.h")
    return module_root


def project_mount_journal(repo_root: Path, check: bool) -> int:
    """Regenerate the UI-only mount journal projection from reviewed metadata.

    This deliberately leaves protocol/action projections and their mapping hashes
    untouched, so a visibility/source-text correction does not require unrelated
    external model evidence or a server catalog rewrite.
    """
    # Rebuild the canonical model so UI-only fields never leak back into the
    # manifest's mapping basis. The selected two outputs are rendered by the
    # same production renderer; module/action artifacts are intentionally not
    # written in this mode.
    model = build_model(repo_root / "catalog/source")
    render = render_outputs(model, repo_root, repo_root.parent / "mod-solo-collections")
    selected_paths = {
        repo_root / "catalog/generated/catalog-manifest.json",
        repo_root / "addon/SoloCollections/Data/Generated/Catalog.lua",
    }
    drift = []
    for path in selected_paths:
        content = render[path]
        current = path.read_text(encoding="utf-8") if path.exists() else None
        if current == content:
            continue
        if check:
            drift.append(path)
        else:
            path.write_text(content, encoding="utf-8", newline="\n")
            print(f"generated: {path}")
    if drift:
        for path in drift:
            print(f"out of date: {path}", file=sys.stderr)
        return 1
    print(f"mount journal projection mapping hash unchanged: {model['mappingHash']}")
    return 0

    # Kept below as an explicit description of the equivalent projection
    # mechanics; execution returns above after using the shared renderer.
    manifest_path = repo_root / "catalog/generated/catalog-manifest.json"
    catalog_path = repo_root / "addon/SoloCollections/Data/Generated/Catalog.lua"
    manifest = _read_json(manifest_path)
    journal = _read_json(repo_root / "catalog/source/mount_journal_metadata.json")
    by_id = {int(entry["collectionId"]): entry for entry in journal["entries"]}
    mount_actions = _read_json(repo_root / "catalog/source/mount_actions.json")
    mount_actions_by_id = {
        int(entry["collectionId"]): entry for entry in mount_actions["collections"]
    }
    mounts = [entry for entry in manifest["collections"] if entry.get("typeKey") == "mount"]
    _require({int(entry["collectionId"]) for entry in mounts} == set(by_id),
             "mount journal metadata must cover every generated mount")
    for entry in mounts:
        row = by_id[int(entry["collectionId"])]
        action = mount_actions_by_id[int(entry["collectionId"])]
        _require(int(action["canonicalSpellId"]) == int(row["spellId"]),
                 f"mount journal spell drift: {entry['collectionId']}")
        entry["sourceText"] = row["source"]
        entry["mountType"] = row.get("mountType")
        entry["flags"] = int(row.get("flags") or 0)
        entry["sourceType"] = row.get("sourceType")
        entry["descriptionKey"] = int(row.get("descriptionKey") or action["canonicalSpellId"])
        entry["descriptionStatus"] = row.get("descriptionStatus") or "MISSING"
        entry["journalVisible"] = bool(row.get("journalVisible", row.get("uiCollectible", True)))
        entry["acquisitionClass"] = row.get("acquisitionClass") or "STANDARD"
        entry["visibilityReason"] = row.get("visibilityReason", row.get("exclusionReason"))
        entry["uiCollectible"] = entry["journalVisible"]
        entry["uiExclusionReason"] = entry["visibilityReason"]
        if row.get("journalNameZhCN"):
            entry["name"]["zhCN"] = row["journalNameZhCN"]

    startup_collections = deepcopy([
        entry for entry in manifest["collections"] if entry["typeKey"] not in {"appearance", "set"}
    ])
    companion_actions = _read_json(repo_root / "catalog/source/companion_actions.json")
    companion_actions_by_id = {int(entry["collectionId"]): entry for entry in companion_actions["entries"]}
    toy_actions = _read_json(repo_root / "catalog/source/toy_actions.json")
    toy_actions_by_id = {int(entry["collectionId"]): entry for entry in toy_actions["entries"]}
    mount_evidence = _read_json(repo_root / "catalog/review/mounts/evidence.json")
    alliance_mask, horde_mask = 1101, 690
    faction_by_spell = {}
    for candidate in mount_evidence.get("candidates", []):
        masks = {int(source.get("allowableRace", 0)) for source in candidate.get("itemSources", [])
                 if int(source.get("allowableRace", 0)) > 0}
        masks.update(int(source.get("raceMask", 0)) for source in candidate.get("skillLineAbilities", [])
                     if int(source.get("raceMask", 0)) > 0)
        if masks and all(mask & ~alliance_mask == 0 for mask in masks):
            faction_by_spell[int(candidate["spellId"])] = "ALLIANCE"
        elif masks and all(mask & ~horde_mask == 0 for mask in masks):
            faction_by_spell[int(candidate["spellId"])] = "HORDE"
    for entry in startup_collections:
        if entry["typeKey"] == "mount":
            row = by_id[int(entry["collectionId"])]
            action = mount_actions_by_id[int(entry["collectionId"])]
            entry["displayCreatureId"] = int(entry["previewCreatureEntry"])
            entry["spellId"] = int(action["canonicalSpellId"])
            entry["faction"] = faction_by_spell.get(entry["spellId"])
            entry["sourceText"] = row["source"]
            entry["mountType"] = row.get("mountType")
            entry["flags"] = int(row.get("flags") or 0)
            entry["sourceType"] = row.get("sourceType")
            entry["descriptionKey"] = int(row.get("descriptionKey") or entry["spellId"])
            entry["descriptionStatus"] = row.get("descriptionStatus") or "MISSING"
            entry["journalVisible"] = bool(row.get("journalVisible", row.get("uiCollectible", True)))
            entry["acquisitionClass"] = row.get("acquisitionClass") or "STANDARD"
            entry["visibilityReason"] = row.get("visibilityReason", row.get("exclusionReason"))
            entry["uiCollectible"] = entry["journalVisible"]
            entry["uiExclusionReason"] = entry["visibilityReason"]
            if row.get("journalNameZhCN"):
                entry["name"]["zhCN"] = row["journalNameZhCN"]
        elif entry["typeKey"] == "companion":
            entry["displayCreatureId"] = int(entry["previewCreatureEntry"])
        elif entry["typeKey"] == "toy":
            action = toy_actions_by_id[int(entry["collectionId"])]
            entry["displayItemId"] = int(action["itemId"])
            entry["targetPolicy"] = action["targetPolicy"]
            entry["requiresTarget"] = action["targetPolicy"] == "REQUIRED_UNIT"
        if entry["typeKey"] in {"mount", "companion", "toy"}:
            entry.pop("actionId", None)
            entry.pop("sourceId", None)
    catalog_payload = {
        "schemaVersion": manifest["schemaVersion"], "metadataVersion": manifest["metadataVersion"],
        "assetPackVersion": manifest["assetPackVersion"], "mappingHash": manifest["mappingHash"],
        "collectionTypes": manifest["collectionTypes"], "collections": startup_collections,
        "typeMappingHashes": manifest["typeMappingHashes"], "presentationHash": manifest["presentationHash"],
        "presentationEvidenceHash": manifest["presentationEvidenceHash"],
        "presentationEvidenceId": manifest["presentationEvidenceId"],
        "presentationEvidencePackHash": manifest["presentationEvidencePackHash"],
        "appearancePresentationHash": manifest["appearancePresentationHash"],
        "appearancePresentationEvidence": manifest["appearancePresentationEvidence"],
        "appearancePresentationPublicCount": manifest["appearancePresentationPublicCount"],
        "deprecatedAliases": manifest["deprecatedAliases"],
    }
    outputs = {
        manifest_path: json.dumps(manifest, ensure_ascii=False, sort_keys=True, indent=2) + "\n",
        catalog_path: "-- Generated by tools/catalog/generate_catalog.py. Do not edit.\nSoloCollections.GeneratedCatalog = " + _lua(catalog_payload) + "\n",
    }
    drift = []
    for path, content in outputs.items():
        current = path.read_text(encoding="utf-8") if path.exists() else None
        if current == content:
            continue
        if check:
            drift.append(path)
        else:
            path.write_text(content, encoding="utf-8", newline="\n")
            print(f"generated: {path}")
    if drift:
        for path in drift:
            print(f"out of date: {path}", file=sys.stderr)
        return 1
    print(f"mount journal projection mapping hash unchanged: {manifest['mappingHash']}")
    return 0


def project_mount_action_contract(repo_root: Path, module_root: Path, check: bool) -> int:
    """Render the cross-repository mount action contract from tracked canonical inputs."""
    module_root = validate_module_root(repo_root, module_root)
    model = build_model(repo_root / "catalog/source")
    outputs = render_outputs(model, repo_root, module_root)
    drift = []
    for path, content in outputs.items():
        current = path.read_text(encoding="utf-8") if path.exists() else None
        if current == content:
            continue
        if check:
            drift.append(path)
        else:
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text(content, encoding="utf-8", newline="\n")
            print(f"generated: {path}")
    if drift:
        for path in drift:
            print(f"out of date: {path}", file=sys.stderr)
        return 1
    print(f"mount action contract mapping hash: {model['mappingHash']}")
    print(f"mount action type hash: {model['typeMappingHashes']['mount']}")
    return 0


def discover_module_root(repo_root: Path) -> Path:
    candidates = (
        repo_root.parent / "mod-solo-collections",
        repo_root.parent.parent / "mod-solo-collections",
    )
    for candidate in candidates:
        if (candidate / "src/SoloCollectionsTypes.h").is_file() and (candidate / ".git").exists():
            return candidate
    raise CatalogError("cannot discover sibling mod-solo-collections checkout; pass --module-root")


def project_companion_journal(repo_root: Path, module_root: Path, check: bool) -> int:
    """Render the tracked AddOn/module companion journal contract without external assets."""
    module_root = validate_module_root(repo_root, module_root)
    model = build_model(repo_root / "catalog/source")
    outputs = render_outputs(model, repo_root, module_root)
    drift = []
    for path, content in outputs.items():
        current = path.read_text(encoding="utf-8") if path.exists() else None
        if current == content:
            continue
        if check:
            drift.append(path)
        else:
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text(content, encoding="utf-8", newline="\n")
            print(f"generated: {path}")
    if drift:
        for path in drift:
            print(f"out of date: {path}", file=sys.stderr)
        return 1
    print(f"companion journal contract mapping hash: {model['mappingHash']}")
    print(f"companion journal type hash: {model['typeMappingHashes']['companion']}")
    return 0


def _validate_creature_presentation_evidence(source_root: Path, evidence_root: Path) -> None:
    module_path = Path(__file__).with_name("creature_presentations.py")
    spec = importlib.util.spec_from_file_location("solo_creature_presentations", module_path)
    _require(spec is not None and spec.loader is not None, "cannot load creature presentation generator")
    presentation_generator = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(presentation_generator)
    try:
        expected = presentation_generator.build_presentations(evidence_root)
    except (OSError, presentation_generator.PresentationError) as exc:
        raise CatalogError(f"creature presentation evidence rejected: {exc}") from exc
    actual = _read_json(source_root / "creature_presentations.json")
    expected_mounts = [entry for entry in expected.get("entries", []) if entry.get("typeKey") == "mount"]
    actual_mounts = [entry for entry in actual.get("entries", []) if entry.get("typeKey") == "mount"]
    _require(actual.get("schemaVersion") == expected.get("schemaVersion") and actual_mounts == expected_mounts,
             "mount creature presentations do not match the supplied evidence root")


def _validate_companion_catalog(repo_root: Path, evidence_root: Path) -> None:
    module_path = Path(__file__).with_name("companion_catalog.py")
    spec = importlib.util.spec_from_file_location("solo_companion_catalog", module_path)
    _require(spec is not None and spec.loader is not None, "cannot load companion catalog generator")
    companion_generator = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(companion_generator)
    try:
        companion_generator.verify_review_pack(repo_root, evidence_root)
        companion_generator.generate(
            repo_root,
            repo_root / "catalog/review/companions/evidence.json",
            True,
        )
    except (OSError, companion_generator.CompanionCatalogError) as exc:
        raise CatalogError(f"companion catalog rejected: {exc}") from exc


def _validate_toy_catalog(repo_root: Path, evidence_root: Path) -> None:
    module_path = Path(__file__).with_name("toy_catalog.py")
    spec = importlib.util.spec_from_file_location("solo_toy_catalog", module_path)
    _require(spec is not None and spec.loader is not None, "cannot load toy catalog generator")
    toy_generator = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(toy_generator)
    try:
        toy_generator.verify_review_pack(repo_root, evidence_root)
        toy_generator.generate(
            repo_root,
            repo_root / "catalog/review/toys/evidence.json",
            True,
        )
    except (OSError, toy_generator.ToyCatalogError) as exc:
        raise CatalogError(f"toy catalog rejected: {exc}") from exc


def _validate_itemset_catalog(repo_root: Path, evidence_root: Path) -> None:
    module_path = Path(__file__).with_name("itemset_import.py")
    spec = importlib.util.spec_from_file_location("solo_itemset_import", module_path)
    _require(spec is not None and spec.loader is not None, "cannot load ItemSet importer")
    itemset_importer = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(itemset_importer)
    try:
        itemset_importer.verify_tracked(repo_root, evidence_root)
    except (OSError, itemset_importer.ItemSetImportError) as exc:
        raise CatalogError(f"ItemSet catalog rejected: {exc}") from exc


def _validate_appearance_presentation_evidence(repo_root: Path, source_root: Path, evidence_root: Path) -> None:
    module_path = Path(__file__).with_name("appearance_presentations.py")
    spec = importlib.util.spec_from_file_location("solo_appearance_presentations", module_path)
    _require(spec is not None and spec.loader is not None, "cannot load appearance presentation generator")
    presentation_generator = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(presentation_generator)
    try:
        expected = presentation_generator.build_report(
            source_root / "appearance_presentations.json",
            repo_root / "catalog/generated/appearance-sources.json",
            evidence_root,
        )
    except (OSError, presentation_generator.PresentationError) as exc:
        raise CatalogError(f"appearance presentation evidence rejected: {exc}") from exc
    actual = _read_json(repo_root / "catalog/generated/appearance-presentation-report.json")
    _require(actual == expected, "appearance presentation report does not match supplied evidence")


def _validate_character_camera_profiles(repo_root: Path) -> None:
    module_path = Path(__file__).with_name("character_camera_profiles.py")
    spec = importlib.util.spec_from_file_location("solo_character_camera_profiles", module_path)
    _require(spec is not None and spec.loader is not None, "cannot load character camera profile generator")
    camera_generator = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(camera_generator)
    try:
        camera_generator.check(repo_root)
    except (OSError, camera_generator.CameraProfileError) as exc:
        raise CatalogError(f"character camera profiles rejected: {exc}") from exc


def generate(
    repo_root: Path,
    source_root: Path,
    module_root: Path,
    evidence_root: Path,
    check: bool,
    include_module: bool = True,
) -> int:
    module_root = validate_module_root(repo_root, module_root)
    print(f"catalog module target: {module_root}")
    _validate_creature_presentation_evidence(source_root, evidence_root)
    _validate_companion_catalog(repo_root, evidence_root)
    _validate_toy_catalog(repo_root, evidence_root)
    _validate_itemset_catalog(repo_root, evidence_root)
    _validate_appearance_presentation_evidence(repo_root, source_root, evidence_root)
    _validate_character_camera_profiles(repo_root)
    model = build_model(source_root)
    outputs = render_outputs(model, repo_root, module_root)
    if not include_module:
        resolved_module_root = module_root.resolve()
        outputs = {
            path: content
            for path, content in outputs.items()
            if path.resolve() != resolved_module_root and resolved_module_root not in path.resolve().parents
        }
    drift: list[Path] = []
    for path, content in outputs.items():
        current = path.read_text(encoding="utf-8") if path.exists() else None
        if current == content:
            continue
        if check:
            drift.append(path)
            continue
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(content, encoding="utf-8", newline="\n")
        print(f"generated: {path}")
    if drift:
        for path in drift:
            print(f"out of date: {path}", file=sys.stderr)
        return 1
    print(f"catalog mapping hash: {model['mappingHash']}")
    return 0


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--module-root", type=Path)
    parser.add_argument("--evidence-root", type=Path)
    parser.add_argument("--source-root", type=Path)
    parser.add_argument(
        "--addon-only",
        action="store_true",
        help="regenerate or check AddOn/catalog projections without writing module projections",
    )
    parser.add_argument("--check", action="store_true")
    parser.add_argument(
        "--mount-journal-only",
        action="store_true",
        help="regenerate only reviewed client mount-journal fields; protocol mappings remain unchanged",
    )
    parser.add_argument(
        "--mount-action-contract-only",
        action="store_true",
        help="regenerate the tracked cross-repository mount action contract without external presentation evidence",
    )
    parser.add_argument(
        "--companion-journal-only",
        action="store_true",
        help="regenerate the tracked AddOn/module companion journal contract without external presentation evidence",
    )
    args = parser.parse_args(argv)
    repo_root = Path(__file__).resolve().parents[2]
    if args.mount_journal_only:
        try:
            return project_mount_journal(repo_root, args.check)
        except CatalogError as exc:
            print(f"catalog error: {exc}", file=sys.stderr)
            return 2
    if args.mount_action_contract_only:
        if args.module_root is None:
            parser.error("--module-root is required with --mount-action-contract-only")
        try:
            return project_mount_action_contract(repo_root, args.module_root, args.check)
        except CatalogError as exc:
            print(f"catalog error: {exc}", file=sys.stderr)
            return 2
    if args.companion_journal_only:
        try:
            module_root = args.module_root or discover_module_root(repo_root)
            return project_companion_journal(repo_root, module_root, args.check)
        except CatalogError as exc:
            print(f"catalog error: {exc}", file=sys.stderr)
            return 2
    if args.module_root is None or args.evidence_root is None:
        parser.error("--module-root and --evidence-root are required unless a tracked-only projection mode is used")
    source_root = args.source_root.resolve() if args.source_root else repo_root / "catalog/source"
    try:
        return generate(
            repo_root,
            source_root,
            args.module_root,
            args.evidence_root.resolve(),
            args.check,
            include_module=not args.addon_only,
        )
    except CatalogError as exc:
        print(f"catalog error: {exc}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
