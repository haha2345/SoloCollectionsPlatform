#!/usr/bin/env python3
"""Generate SoloCollections catalog artifacts from the canonical source tree."""

from __future__ import annotations

import argparse
import csv
import hashlib
import json
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


def _canonical_for_hash(model: dict[str, Any]) -> dict[str, Any]:
    def clean(value: Any, key: str = "") -> Any:
        if key in {"name", "icon", "metadataVersion"}:
            return None
        if isinstance(value, dict):
            return {child_key: cleaned for child_key in sorted(value) if (cleaned := clean(value[child_key], child_key)) is not None}
        if isinstance(value, list):
            return [clean(item) for item in value]
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
    mount_actions = _load_mount_actions(source_root, collections)
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
        "aliases": aliases,
        "identityOverrides": sorted(overrides, key=lambda row: (row.get("collectionKey", ""), row.get("classKey", ""), row.get("raceKey", ""))),
    }
    mapping_basis = _canonical_for_hash(model)
    model["mappingHash"] = _hash(mapping_basis)
    model["typeMappingHashes"] = {}
    for entry in model["collectionTypes"]:
        basis: Any = [row for row in mapping_basis["collections"] if row["typeKey"] == entry["typeKey"]]
        if entry["typeKey"] == "mount":
            basis = {"collections": basis, "actions": mapping_basis["mountActions"]}
        model["typeMappingHashes"][entry["typeKey"]] = _hash(basis)
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
    for entry in model["mountActions"]["collections"]:
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
            ]) + "},"
        )
    lines += ["    };", "}", ""]
    return "\n".join(lines)


def render_outputs(model: dict[str, Any], repo_root: Path, module_root: Path) -> dict[Path, str]:
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
    client_collections = deepcopy(model["collections"])
    mount_actions_by_id = {
        int(entry["collectionId"]): entry for entry in model["mountActions"]["collections"]
    }
    for entry in client_collections:
        if entry["typeKey"] != "mount":
            continue
        action = mount_actions_by_id[int(entry["collectionId"])]
        entry["displayCreatureId"] = int(action["creatureIds"][0])
        # The client can render a mount, but action spell resolution remains
        # server-only. The wire request contains only typeId + collectionId.
        entry.pop("actionId", None)
        entry.pop("sourceId", None)
    catalog_lua = "-- Generated by tools/catalog/generate_catalog.py. Do not edit.\nSoloCollections.GeneratedCatalog = " + _lua({
        "schemaVersion": model["schemaVersion"], "metadataVersion": model["metadataVersion"],
        "assetPackVersion": model["assetPackVersion"], "mappingHash": model["mappingHash"],
        "collectionTypes": model["collectionTypes"], "collections": client_collections,
        "typeMappingHashes": model["typeMappingHashes"],
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
        repo_root / "addon/SoloCollections/Data/Generated/Catalog.lua": catalog_lua,
        repo_root / "addon/SoloCollections/Data/Generated/IdentityRegistry.lua": identity_lua,
        repo_root / "addon/SoloCollections/Data/Generated/PolicyRegistry.lua": policy_lua,
        module_root / "data/generated/solo_collections_catalog_manifest.json": json_text,
        module_root / "data/generated/solo_collections_mount_actions.json": mount_actions_text,
        module_root / "data/generated/solo_collections_missing_resources.json": missing_text,
        module_root / "src/generated/SoloCollectionsIdentityData.inc": _identity_inc(model),
        module_root / "src/generated/SoloCollectionsPolicyData.inc": _policy_inc(model),
        module_root / "src/generated/SoloCollectionsProtocolCatalog.inc": _protocol_catalog_inc(model),
        module_root / "src/generated/SoloCollectionsMountCatalog.inc": _mount_catalog_inc(model),
    }


def validate_module_root(repo_root: Path, module_root: Path) -> Path:
    module_root = module_root.resolve()
    _require(module_root != repo_root.resolve(), "module root must not be the SoloCollections repository")
    _require(module_root.name == "mod-solo-collections", "module root basename must be mod-solo-collections")
    _require((module_root / ".git").exists(), "module root must be a Git checkout")
    _require((module_root / "src/SoloCollectionsTypes.h").is_file(), "module root does not contain SoloCollectionsTypes.h")
    return module_root


def generate(repo_root: Path, source_root: Path, module_root: Path, check: bool) -> int:
    module_root = validate_module_root(repo_root, module_root)
    print(f"catalog module target: {module_root}")
    model = build_model(source_root)
    outputs = render_outputs(model, repo_root, module_root)
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
    parser.add_argument("--module-root", required=True, type=Path)
    parser.add_argument("--source-root", type=Path)
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args(argv)
    repo_root = Path(__file__).resolve().parents[2]
    source_root = args.source_root.resolve() if args.source_root else repo_root / "catalog/source"
    try:
        return generate(repo_root, source_root, args.module_root, args.check)
    except CatalogError as exc:
        print(f"catalog error: {exc}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
