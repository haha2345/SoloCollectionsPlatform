#!/usr/bin/env python3
"""Render AddOn and C++ set projections from normalized-itemsets.json."""

from __future__ import annotations

import argparse
import copy
import json
import os
from pathlib import Path
from typing import Any


class SetCatalogError(ValueError):
    pass


def require(condition: bool, message: str) -> None:
    if not condition:
        raise SetCatalogError(message)


def read_json(path: Path) -> Any:
    return json.loads(path.read_text(encoding="utf-8-sig"))


def validate(model: dict[str, Any]) -> None:
    require(model.get("schemaVersion") == 2, "unsupported normalized ItemSet schema")
    seen_ids: set[int] = set()
    seen_keys: set[str] = set()
    seen_ordinals: set[int] = set()
    for definition in model.get("sets", []):
        collection_id = int(definition["collectionId"])
        key = str(definition["collectionKey"])
        ordinal = int(definition["ordinal"])
        require(collection_id not in seen_ids and key not in seen_keys and ordinal not in seen_ordinals,
                f"duplicate set identity: {key}")
        seen_ids.add(collection_id); seen_keys.add(key); seen_ordinals.add(ordinal)
        policy = definition["classPolicy"]
        mode = policy["mode"]
        classes = policy["allowedClassKeys"]
        require(mode in {"ANY", "ALLOW_LIST", "UNRESOLVED"}, f"invalid class policy: {key}")
        require(len(classes) == len(set(classes)), f"duplicate class policy key: {key}")
        require((mode == "ALLOW_LIST") == bool(classes), f"invalid class policy payload: {key}")
        variants = definition.get("variants", [])
        require(variants, f"set has no variants: {key}")
        active_defaults = 0
        variant_ordinals: set[int] = set()
        for variant in variants:
            variant_ordinal = int(variant["variantOrdinal"])
            require(variant_ordinal > 0 and variant_ordinal not in variant_ordinals,
                    f"duplicate or invalid variant ordinal: {key}")
            variant_ordinals.add(variant_ordinal)
            lifecycle = variant["lifecycle"]
            require(lifecycle in {"ACTIVE", "DISABLED", "DEFERRED"}, f"invalid variant lifecycle: {key}")
            if lifecycle == "ACTIVE" and variant["isDefault"]:
                active_defaults += 1
            members = variant.get("members", [])
            require(lifecycle != "ACTIVE" or any(member["required"] for member in members),
                    f"active variant has no required member: {key}")
            for member in members:
                require(member["appearanceIds"] and member["sourceItemIds"], f"empty set member: {key}")
                require(len(member["appearanceIds"]) == len(set(member["appearanceIds"])),
                        f"duplicate appearance alternative: {key}")
        require(active_defaults == 1, f"set needs exactly one active default variant: {key}")


def validate_presentations(model: dict[str, Any], presentations: dict[str, Any]) -> dict[int, dict[str, Any]]:
    require(presentations.get("schemaVersion") == 1, "unsupported set presentation schema")
    require(presentations.get("mappingHash") == model.get("mappingHash"),
            "set presentation mapping hash differs from normalized ItemSets")
    presentation_hash = presentations.get("presentationHash")
    require(isinstance(presentation_hash, str) and len(presentation_hash) == 64,
            "set presentation hash is missing or invalid")
    expected_ids = {int(row["collectionId"]) for row in model.get("sets", [])}
    by_collection_id: dict[int, dict[str, Any]] = {}
    for row in presentations.get("presentations", []):
        collection_id = int(row.get("collectionId", 0))
        require(collection_id in expected_ids and collection_id not in by_collection_id,
                f"invalid or duplicate set presentation collection ID: {collection_id}")
        ranks = row.get("sortRank")
        require(isinstance(ranks, dict), f"set presentation has no sort rank: {collection_id}")
        for key in ("expansion", "acquisition", "tier", "season", "difficulty", "medianItemLevel", "maxItemLevel"):
            require(isinstance(ranks.get(key), (int, float)),
                    f"set presentation rank is invalid: {collection_id}.{key}")
        require(bool(row.get("reasonCode")) and bool(row.get("status")),
                f"set presentation review state is incomplete: {collection_id}")
        by_collection_id[collection_id] = row
    require(set(by_collection_id) == expected_ids, "set presentation coverage differs from active ItemSets")
    return by_collection_id


def with_presentations(model: dict[str, Any], presentations: dict[str, Any]) -> dict[str, Any]:
    by_collection_id = validate_presentations(model, presentations)
    combined = copy.deepcopy(model)
    combined["schemaVersion"] = 3
    combined["identitySchemaVersion"] = model["schemaVersion"]
    combined["presentationHash"] = presentations["presentationHash"]
    combined["presentationEvidence"] = {
        "itemSetEvidenceHash": presentations["itemSetEvidenceHash"],
        "reviewPolicyHash": presentations["reviewPolicyHash"],
    }
    for definition in combined["sets"]:
        definition["presentation"] = by_collection_id[int(definition["collectionId"])]
    return combined


def lua(value: Any, indent: int = 0) -> str:
    pad = "    " * indent
    child = "    " * (indent + 1)
    if value is None: return "nil"
    if value is True: return "true"
    if value is False: return "false"
    if isinstance(value, (int, float)): return str(value)
    if isinstance(value, str): return json.dumps(value, ensure_ascii=False)
    if isinstance(value, list):
        return "{}" if not value else "{\n" + ",\n".join(child + lua(item, indent + 1) for item in value) + "\n" + pad + "}"
    if isinstance(value, dict):
        return "{}" if not value else "{\n" + ",\n".join(child + f"{key} = " + lua(item, indent + 1)
            for key, item in value.items()) + "\n" + pad + "}"
    raise TypeError(type(value))


def render_lua(model: dict[str, Any]) -> str:
    rows = []
    for definition in model["sets"]:
        default = next(value for value in definition["variants"] if value["lifecycle"] == "ACTIVE" and value["isDefault"])
        item_ids = [member["sourceItemIds"][0] for member in default["members"] if member["required"]]
        rows.append({
            "id": definition["collectionId"], "itemSetId": definition["itemSetId"],
            "classPolicy": definition["classPolicy"], "name": definition["name"]["zhCN"] or definition["name"]["enUS"],
            "iconItemId": definition["iconItemId"], "itemIds": item_ids, "variants": definition["variants"],
            "presentation": definition["presentation"],
            "selectedVariantOrdinal": default["variantOrdinal"], "favorite": False,
        })
    return "-- Generated by tools/catalog/set_catalog.py. Do not edit.\nSoloCollections.Data.Sets = " + lua(rows) + "\n"


def cpp_string(value: str) -> str:
    return json.dumps(value, ensure_ascii=True)


def render_cpp(model: dict[str, Any]) -> str:
    mode = {"ANY": "SetClassPolicyMode::Any", "ALLOW_LIST": "SetClassPolicyMode::AllowList",
            "UNRESOLVED": "SetClassPolicyMode::Unresolved"}
    lifecycle = {"ACTIVE": "SetVariantLifecycle::Active", "DISABLED": "SetVariantLifecycle::Disabled",
                 "DEFERRED": "SetVariantLifecycle::Deferred"}
    lines = ["// Generated by tools/catalog/set_catalog.py. Do not edit.", "",
             f"static constexpr char GeneratedSetMappingHash[] = {cpp_string(model['mappingHash'])};", "",
             "static std::vector<SetCollectionDefinition> LoadGeneratedSetCollections()", "{", "    return {"]
    for definition in model["sets"]:
        classes = ", ".join(cpp_string(value) for value in definition["classPolicy"]["allowedClassKeys"])
        lines.append("        { CollectionId{ " + str(definition["collectionId"]) + "u }, " +
                     cpp_string(definition["collectionKey"]) + ", " + str(definition["itemSetId"]) + "u, " +
                     mode[definition["classPolicy"]["mode"]] + ", { " + classes + " }, {")
        for variant in definition["variants"]:
            lines.append("            { " + cpp_string(variant["variantKey"]) + ", " +
                         str(variant["variantOrdinal"]) + "u, " + ("true" if variant["isDefault"] else "false") +
                         ", " + lifecycle[variant["lifecycle"]] + ", {")
            for member in variant["members"]:
                appearances = ", ".join(f"CollectionId{{ {value}u }}" for value in member["appearanceIds"])
                sources = ", ".join(f"{value}u" for value in member["sourceItemIds"])
                lines.append("                { " + cpp_string(member["memberKey"]) + ", " +
                             cpp_string(member["slotKey"]) + ", " + ("true" if member["required"] else "false") +
                             ", { " + appearances + " }, { " + sources + " } },")
            lines.append("            } },")
        lines.append("        } },")
    lines += ["    };", "}", ""]
    return "\n".join(lines)


def outputs(repo: Path, module: Path, model: dict[str, Any], presentations: dict[str, Any],
            include_module: bool) -> dict[Path, bytes]:
    addon_model = with_presentations(model, presentations)
    addon_content = (json.dumps(addon_model, ensure_ascii=False, indent=2, sort_keys=True) + "\n").encode("utf-8")
    result = {
        repo / "catalog/generated/set-catalog.json": addon_content,
        repo / "addon/SoloCollections_WardrobeData/Data/Sets.lua": render_lua(addon_model).encode("utf-8"),
    }
    if include_module:
        identity_content = (json.dumps(model, ensure_ascii=False, indent=2, sort_keys=True) + "\n").encode("utf-8")
        result[module / "data/generated/solo_collections_sets.json"] = identity_content
        result[module / "src/generated/SoloCollectionsSetCatalog.inc"] = render_cpp(model).encode("utf-8")
    return result


def main() -> int:
    repo = Path(__file__).resolve().parents[2]
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--module-root", type=Path,
        default=Path(os.environ.get("SOLOCOLLECTIONS_MODULE_ROOT", repo.parent / "mod-solo-collections")))
    parser.add_argument("--evidence-root", type=Path)
    parser.add_argument("--include-module", action="store_true",
        help="Also regenerate the identity-only module/C++ projections. Presentation-only work leaves them unchanged.")
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args()
    module = args.module_root.resolve()
    require((module / ".git").exists() and (module / "src/SoloCollectionsTypes.h").is_file(),
            f"invalid module root: {module}")
    if args.evidence_root:
        import itemset_import
        itemset_import.verify_tracked(repo, args.evidence_root.resolve())
    model = read_json(repo / "catalog/generated/normalized-itemsets.json")
    presentations = read_json(repo / "catalog/generated/set-presentations.json")
    validate(model)
    for path, content in outputs(repo, module, model, presentations, args.include_module).items():
        if args.check:
            current = path.read_bytes().replace(b"\r\n", b"\n") if path.is_file() else None
            require(current == content, f"generated output drift: {path}")
        else:
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_bytes(content)
    print(f"set catalog: {len(model['sets'])} sets, mapping={model['mappingHash']}, "
          f"presentation={presentations['presentationHash']}, module={'included' if args.include_module else 'unchanged'}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
