#!/usr/bin/env python3
"""Build the derived set catalog from canonical appearance identities."""

from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
from typing import Any


class SetCatalogError(ValueError):
    pass


def _require(condition: bool, message: str) -> None:
    if not condition:
        raise SetCatalogError(message)


def _stable_json(value: Any) -> str:
    return json.dumps(value, ensure_ascii=False, sort_keys=True, separators=(",", ":"))


def _appearance_index(appearance_catalog: dict[str, Any]) -> dict[int, dict[str, Any]]:
    result: dict[int, dict[str, Any]] = {}
    for group in appearance_catalog.get("groups", []):
        if group.get("lifecycle") != "active":
            continue
        for source_item_id in group.get("sourceItemIds", []):
            source_item_id = int(source_item_id)
            _require(source_item_id not in result, f"appearance source is mapped twice: {source_item_id}")
            result[source_item_id] = group
    return result


def _normalize_variant(raw: dict[str, Any], appearances: dict[int, dict[str, Any]], label: str) -> dict[str, Any]:
    lifecycle = str(raw.get("lifecycle", "active"))
    _require(lifecycle in {"active", "disabled"}, f"invalid variant lifecycle: {label}")
    item_ids = [int(value) for value in raw.get("itemIds", [])]
    optional = {int(value) for value in raw.get("optionalItemIds", [])}
    disabled = {int(value) for value in raw.get("disabledItemIds", [])}
    _require(item_ids and len(item_ids) == len(set(item_ids)), f"variant itemIds must be non-empty and unique: {label}")
    _require(optional <= set(item_ids), f"optional item is not a variant member: {label}")
    _require(disabled <= set(item_ids), f"disabled item is not a variant member: {label}")

    grouped: dict[tuple[str, str], dict[str, Any]] = {}
    for item_id in item_ids:
        appearance = appearances.get(item_id)
        _require(appearance is not None, f"set source has no canonical appearance: {label}:{item_id}")
        member_lifecycle = "disabled" if item_id in disabled else "active"
        slot_key = str(appearance["slotKey"])
        member = grouped.setdefault((slot_key, member_lifecycle), {
            "memberKey": slot_key.lower() + (".disabled" if member_lifecycle == "disabled" else ""),
            "slotKey": slot_key,
            "lifecycle": member_lifecycle,
            "required": member_lifecycle == "active",
            "appearanceIds": [],
            "sourceItemIds": [],
        })
        if item_id in optional:
            member["required"] = False
        member["sourceItemIds"].append(item_id)
        appearance_id = int(appearance["appearanceId"])
        if appearance_id not in member["appearanceIds"]:
            member["appearanceIds"].append(appearance_id)

    members = sorted(grouped.values(), key=lambda row: (row["slotKey"], row["lifecycle"], row["memberKey"]))
    for member in members:
        member["appearanceIds"].sort()
        member["sourceItemIds"].sort()
    required_count = sum(1 for member in members if member["lifecycle"] == "active" and member["required"])
    _require(lifecycle == "disabled" or required_count > 0, f"active variant has no required members: {label}")
    return {
        "variantKey": str(raw["variantKey"]),
        "colorKey": str(raw.get("colorKey", "default")),
        "difficultyKey": str(raw.get("difficultyKey", "default")),
        "lifecycle": lifecycle,
        "requiredCount": required_count,
        "members": members,
    }


def build_model(source: dict[str, Any], appearance_catalog: dict[str, Any]) -> dict[str, Any]:
    _require(source.get("schemaVersion") == 1, "unsupported set source schema")
    appearances = _appearance_index(appearance_catalog)
    raw_sets = source.get("sets")
    _require(isinstance(raw_sets, list) and raw_sets, "set source must contain sets")
    seen_ids: set[int] = set()
    seen_keys: set[str] = set()
    seen_ordinals: set[int] = set()
    sets: list[dict[str, Any]] = []
    for raw in raw_sets:
        collection_id = int(raw["collectionId"])
        collection_key = str(raw["collectionKey"])
        ordinal = int(raw["ordinal"])
        _require(collection_id not in seen_ids and collection_key not in seen_keys and ordinal not in seen_ordinals,
                 f"duplicate set identity: {collection_key}")
        seen_ids.add(collection_id)
        seen_keys.add(collection_key)
        seen_ordinals.add(ordinal)
        raw_variants = raw.get("variants")
        _require(isinstance(raw_variants, list) and raw_variants, f"set has no variants: {collection_key}")
        variants = [_normalize_variant(value, appearances, f"{collection_key}.{value.get('variantKey', '')}")
                    for value in raw_variants]
        variant_keys = [value["variantKey"] for value in variants]
        _require(len(variant_keys) == len(set(variant_keys)), f"duplicate set variant: {collection_key}")
        sets.append({
            "collectionId": collection_id,
            "collectionKey": collection_key,
            "ordinal": ordinal,
            "itemSetId": int(raw["itemSetId"]),
            "classToken": str(raw["classToken"]),
            "name": dict(raw["name"]),
            "icon": str(raw["icon"]),
            "variants": variants,
        })
    sets.sort(key=lambda row: row["ordinal"])
    basis = [{
        "collectionId": row["collectionId"], "collectionKey": row["collectionKey"],
        "itemSetId": row["itemSetId"], "classToken": row["classToken"], "variants": row["variants"],
    } for row in sets]
    return {
        "schemaVersion": 1,
        "sourceBuild": "3.3.5.12340",
        "appearanceMappingHash": appearance_catalog["mappingHash"],
        "mappingHash": hashlib.sha256(_stable_json(basis).encode("utf-8")).hexdigest(),
        "sets": sets,
    }


def _lua(value: Any, indent: int = 0) -> str:
    pad = "    " * indent
    child = "    " * (indent + 1)
    if value is None:
        return "nil"
    if value is True:
        return "true"
    if value is False:
        return "false"
    if isinstance(value, (int, float)):
        return str(value)
    if isinstance(value, str):
        return json.dumps(value, ensure_ascii=False)
    if isinstance(value, list):
        if not value:
            return "{}"
        return "{\n" + ",\n".join(child + _lua(item, indent + 1) for item in value) + "\n" + pad + "}"
    if isinstance(value, dict):
        if not value:
            return "{}"
        return "{\n" + ",\n".join(child + f"{key} = " + _lua(item, indent + 1) for key, item in value.items()) + "\n" + pad + "}"
    raise TypeError(type(value))


def render_lua(model: dict[str, Any]) -> str:
    records = []
    for definition in model["sets"]:
        primary = next(value for value in definition["variants"] if value["lifecycle"] == "active")
        item_ids = [item for member in primary["members"] if member["lifecycle"] == "active"
                    for item in member["sourceItemIds"]]
        records.append({
            "id": definition["collectionId"], "itemSetId": definition["itemSetId"],
            "classToken": definition["classToken"], "name": definition["name"]["zhCN"] or definition["name"]["enUS"],
            "icon": definition["icon"], "itemIds": item_ids, "variants": definition["variants"],
            "favorite": False,
        })
    return "-- Generated by tools/catalog/set_catalog.py. Do not edit.\nSoloCollections.Data.Sets = " + _lua(records) + "\n"


def _cpp_string(value: str) -> str:
    return json.dumps(value, ensure_ascii=True)


def render_cpp(model: dict[str, Any]) -> str:
    lines = ["// Generated by tools/catalog/set_catalog.py. Do not edit.", "",
             "static std::vector<SetCollectionDefinition> LoadGeneratedSetCollections()", "{", "    return {"]
    for definition in model["sets"]:
        lines.append("        { CollectionId{ " + str(definition["collectionId"]) + "u }, " +
                     _cpp_string(definition["collectionKey"]) + ", " + str(definition["itemSetId"]) + "u, " +
                     _cpp_string(definition["classToken"]) + ", {")
        for variant in definition["variants"]:
            lines.append("            { " + _cpp_string(variant["variantKey"]) + ", " +
                         ("true" if variant["lifecycle"] == "active" else "false") + ", {")
            for member in variant["members"]:
                appearances = ", ".join(f"CollectionId{{ {value}u }}" for value in member["appearanceIds"])
                sources = ", ".join(f"{value}u" for value in member["sourceItemIds"])
                lines.append("                { " + _cpp_string(member["memberKey"]) + ", " +
                             _cpp_string(member["slotKey"]) + ", " + ("true" if member["required"] else "false") +
                             ", " + ("true" if member["lifecycle"] == "active" else "false") +
                             ", { " + appearances + " }, { " + sources + " } },")
            lines.append("            } },")
        lines.append("        } },")
    lines += ["    };", "}", ""]
    return "\n".join(lines)


def outputs(repo: Path, module: Path, model: dict[str, Any]) -> dict[Path, bytes]:
    json_bytes = (json.dumps(model, ensure_ascii=False, indent=2, sort_keys=True) + "\n").encode("utf-8")
    return {
        repo / "catalog/generated/set-catalog.json": json_bytes,
        repo / "addon/SoloCollections/Data/Sets.lua": render_lua(model).encode("utf-8"),
        module / "data/generated/solo_collections_sets.json": json_bytes,
        module / "src/generated/SoloCollectionsSetCatalog.inc": render_cpp(model).encode("utf-8"),
    }


def main() -> int:
    repo = Path(__file__).resolve().parents[2]
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--module-root", type=Path, default=repo.parent / "mod-solo-collections")
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args()
    module = args.module_root.resolve()
    _require(module.name == "mod-solo-collections" and (module / "src").is_dir(), f"invalid module root: {module}")
    source = json.loads((repo / "catalog/source/sets.json").read_text(encoding="utf-8"))
    appearances = json.loads((repo / "catalog/generated/appearance-sources.json").read_text(encoding="utf-8"))
    model = build_model(source, appearances)
    for path, content in outputs(repo, module, model).items():
        if args.check:
            _require(path.is_file() and path.read_bytes() == content, f"generated output drift: {path}")
        else:
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_bytes(content)
    print(f"set catalog: {len(model['sets'])} sets, hash={model['mappingHash']}, module={module}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
