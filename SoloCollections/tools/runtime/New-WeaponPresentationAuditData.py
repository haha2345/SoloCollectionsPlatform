#!/usr/bin/env python3
"""Render a temporary production-wardrobe runtime-audit input on F:."""

from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path
from typing import Any


DIRECT_DISPLAY_CAPABILITY = "DIRECT_DISPLAY_V1"
UNAVAILABLE_CAPABILITY = "UNAVAILABLE"
PUBLIC_STATUSES = {"READY", "UNAVAILABLE"}


def require(value: bool, message: str) -> None:
    if not value:
        raise ValueError(message)


def ensure_f(path: Path, label: str) -> Path:
    value = path.resolve()
    if os.name == "nt":
        require(value.drive.upper() == "F:", f"{label} must be on F:, got {value}")
    return value


def sha256_file(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def lua_quote(value: str) -> str:
    return '"' + value.replace("\\", "\\\\").replace('"', '\\"').replace("\r", "\\r").replace("\n", "\\n") + '"'


def as_positive_int(value: Any, label: str) -> int:
    try:
        result = int(value)
    except (TypeError, ValueError) as exc:
        raise ValueError(f"{label} is not an integer: {value!r}") from exc
    require(result > 0, f"{label} must be positive: {result}")
    return result


def load_contract(source_path: Path, report_path: Path, catalog_path: Path) -> tuple[dict[str, Any], list[dict[str, Any]]]:
    source = json.loads(source_path.read_text(encoding="utf-8"))
    report = json.loads(report_path.read_text(encoding="utf-8"))
    catalog = json.loads(catalog_path.read_text(encoding="utf-8"))
    require(source.get("schemaVersion") == 2, "presentation source schema drift")
    require(report.get("schemaVersion") == 3, "presentation report schema drift")
    asset_pack_version = str(source.get("assetPackVersion", ""))
    require(asset_pack_version, "source assetPackVersion is missing")
    require(report.get("assetPackVersion") == asset_pack_version, "report assetPackVersion drift")
    public_count = as_positive_int(source.get("publicAppearanceCount"), "source publicAppearanceCount")
    require(int(report.get("publicAppearanceCount", -1)) == public_count, "report public count drift")
    require(int(catalog.get("appearancePresentationPublicCount", -1)) == public_count, "catalog public count drift")
    require(catalog.get("assetPackVersion") == asset_pack_version, "catalog assetPackVersion drift")
    appearance_hash = str(catalog.get("appearancePresentationHash", ""))
    require(len(appearance_hash) == 64 and all(char in "0123456789abcdef" for char in appearance_hash),
            "catalog appearancePresentationHash is invalid")

    source_bundle = source.get("assetBundle")
    report_bundle = report.get("assetBundle")
    catalog_bundle = (catalog.get("appearancePresentationEvidence") or {}).get("assetBundle")
    require(isinstance(source_bundle, dict) and isinstance(report_bundle, dict) and isinstance(catalog_bundle, dict),
            "asset bundle evidence is missing")
    for key in ("bundleId", "assetPackVersion", "bundleManifestHash", "registryHash", "candidateCsvSha256"):
        value = source_bundle.get(key)
        require(isinstance(value, str) and value, f"source asset bundle {key} is missing")
        require(report_bundle.get(key) == value and catalog_bundle.get(key) == value,
                f"asset bundle {key} drift")
    require(source_bundle["assetPackVersion"] == asset_pack_version, "asset bundle version drift")

    generated_collections = catalog.get("collections")
    require(isinstance(generated_collections, list), "catalog collections are missing")
    collection_by_appearance: dict[int, dict[str, Any]] = {}
    for collection in generated_collections:
        if not isinstance(collection, dict) or collection.get("typeKey") != "appearance":
            continue
        appearance_id = as_positive_int(collection.get("collectionId"), "catalog appearance collectionId")
        require(appearance_id not in collection_by_appearance,
                f"duplicate catalog appearance collectionId: {appearance_id}")
        collection_by_appearance[appearance_id] = collection

    entries = source.get("entries")
    require(isinstance(entries, list), "presentation entries are missing")
    records: list[dict[str, Any]] = []
    seen: set[int] = set()
    terminal_counts = {"READY": 0, "UNAVAILABLE": 0}
    for entry in entries:
        require(isinstance(entry, dict), "presentation entry is not an object")
        status = str(entry.get("presentationStatus", ""))
        if status not in PUBLIC_STATUSES:
            require(status == "RETAINED_BASELINE" and entry.get("presentationAudience") == "NONPUBLIC_BASELINE",
                    f"unsupported non-public presentation state: {status}")
            continue
        appearance_id = as_positive_int(entry.get("appearanceId"), "appearanceId")
        source_item_id = as_positive_int(entry.get("sourceItemId"), f"sourceItemId for {appearance_id}")
        require(appearance_id not in seen, f"duplicate public appearanceId: {appearance_id}")
        seen.add(appearance_id)
        require(entry.get("assetPackVersion") == asset_pack_version,
                f"appearance {appearance_id} assetPackVersion drift")
        collection = collection_by_appearance.get(appearance_id)
        require(collection is not None and collection.get("lifecycle") == "active"
                and collection.get("uiLifecycle") == "public",
                f"appearance {appearance_id} is not an active public generated collection")
        display_item_id = as_positive_int(
            collection.get("actionId", collection.get("sourceId")),
            f"generated display item for {appearance_id}",
        )
        aliases = collection.get("aliases") or []
        require(f"item:{source_item_id}" in aliases,
                f"presentation source item is not an alias of {appearance_id}")
        if status == "READY":
            require(entry.get("renderMode") == "STANDALONE", f"READY {appearance_id} is not standalone")
            require(entry.get("presentationCapability") == DIRECT_DISPLAY_CAPABILITY,
                    f"READY {appearance_id} lacks direct-display capability")
            display_id = as_positive_int(entry.get("syntheticDisplayId"), f"syntheticDisplayId for {appearance_id}")
            require(display_id <= 0x00FFFFFF, f"syntheticDisplayId is unsafe for {appearance_id}")
            model_path = str(entry.get("modelPath", ""))
            require(model_path.lower().endswith(".m2") and ".." not in model_path,
                    f"READY {appearance_id} has an unsafe model path")
            reason = ""
        else:
            require(entry.get("renderMode") == "UNAVAILABLE", f"UNAVAILABLE {appearance_id} render mode drift")
            require(entry.get("presentationCapability") == UNAVAILABLE_CAPABILITY,
                    f"UNAVAILABLE {appearance_id} capability drift")
            require(not entry.get("syntheticDisplayId") and not entry.get("modelPath"),
                    f"UNAVAILABLE {appearance_id} leaks direct model fields")
            display_id = 0
            model_path = ""
            reason = str(entry.get("presentationReasonCode", ""))
            require(reason, f"UNAVAILABLE {appearance_id} has no reason")
        terminal_counts[status] += 1
        records.append({
            "appearanceId": appearance_id,
            "sourceItemId": source_item_id,
            "displayItemId": display_item_id,
            "presentationStatus": status,
            "syntheticDisplayId": display_id,
            "modelPath": model_path.replace("/", "\\"),
            "presentationReasonCode": reason,
        })

    require(len(records) == public_count, f"public presentation count drift: {len(records)} != {public_count}")
    source_counts = source.get("terminalCounts") or {}
    for status, count in terminal_counts.items():
        require(count == int(source_counts.get(status, -1)), f"{status} terminal count drift")
    records.sort(key=lambda row: row["appearanceId"])
    metadata = {
        "bundleId": str(source_bundle["bundleId"]),
        "assetPackVersion": asset_pack_version,
        "appearancePresentationHash": appearance_hash,
        "publicCount": public_count,
        "readyCount": terminal_counts["READY"],
        "unavailableCount": terminal_counts["UNAVAILABLE"],
        "presentationSourceSha256": sha256_file(source_path),
        "presentationReportSha256": sha256_file(report_path),
        "catalogManifestSha256": sha256_file(catalog_path),
    }
    return metadata, records


def select_visual_samples(metadata: dict[str, Any], records: list[dict[str, Any]], sample_plan_path: Path) -> tuple[dict[str, Any], list[dict[str, Any]]]:
    plan = json.loads(sample_plan_path.read_text(encoding="utf-8"))
    require(plan.get("schemaVersion") == 1 and plan.get("kind") == "SoloCollectionsWeaponPresentationVisualSamplePlan",
            "visual sample plan schema drift")
    require(plan.get("assetPackVersion") == metadata["assetPackVersion"] and plan.get("bundleId") == metadata["bundleId"],
            "visual sample plan asset identity drift")
    require(plan.get("presentationSourceSha256") == metadata["presentationSourceSha256"],
            "visual sample plan source hash drift")
    plan_records = plan.get("records")
    require(isinstance(plan_records, list) and plan_records, "visual sample plan records are missing")
    by_appearance = {int(record["appearanceId"]): record for record in records}
    selected: list[dict[str, Any]] = []
    seen: set[int] = set()
    for plan_record in plan_records:
        require(isinstance(plan_record, dict), "visual sample plan record is not an object")
        appearance_id = as_positive_int(plan_record.get("appearanceId"), "visual sample appearanceId")
        require(appearance_id not in seen and appearance_id in by_appearance,
                f"visual sample appearance is invalid or duplicated: {appearance_id}")
        source = by_appearance[appearance_id]
        require(str(plan_record.get("presentationStatus")) == source["presentationStatus"] and
                int(plan_record.get("sourceItemId", 0)) == source["sourceItemId"],
                f"visual sample identity drift for {appearance_id}")
        kinds = plan_record.get("sampleKinds")
        require(isinstance(kinds, list) and kinds and all(isinstance(kind, str) and kind for kind in kinds),
                f"visual sample kinds are invalid for {appearance_id}")
        selected_record = dict(source)
        selected_record["sampleKinds"] = "|".join(sorted(kinds))
        selected.append(selected_record)
        seen.add(appearance_id)
    require(len(selected) == int(plan.get("sampleCount", -1)), "visual sample count drift")
    ready_count = sum(record["presentationStatus"] == "READY" for record in selected)
    unavailable_count = sum(record["presentationStatus"] == "UNAVAILABLE" for record in selected)
    require(ready_count == int(plan.get("readySampleCount", -1)) and
            unavailable_count == int(plan.get("unavailableSampleCount", -1)), "visual sample terminal counts drift")
    result_metadata = dict(metadata)
    result_metadata.update({
        "sampleOnly": True,
        "visualCapture": True,
        "sampleCount": len(selected),
        "samplePlanSha256": sha256_file(sample_plan_path),
        "publicCount": len(selected),
        "readyCount": ready_count,
        "unavailableCount": unavailable_count,
    })
    return result_metadata, selected


def render(metadata: dict[str, Any], records: list[dict[str, Any]], cache_state: str, auto_logout: bool,
           auto_logout_delay: float) -> str:
    rows = []
    for record in records:
        sample_suffix = ""
        if "sampleKinds" in record:
            sample_suffix = ", sampleKinds = " + lua_quote(str(record["sampleKinds"]))
        rows.append(
            "        { appearanceId = %d, sourceItemId = %d, displayItemId = %d, presentationStatus = %s, syntheticDisplayId = %d, modelPath = %s, presentationReasonCode = %s%s },"
            % (
                record["appearanceId"],
                record["sourceItemId"],
                record["displayItemId"],
                lua_quote(record["presentationStatus"]),
                record["syntheticDisplayId"],
                lua_quote(record["modelPath"]),
                lua_quote(record["presentationReasonCode"]),
                sample_suffix,
            )
        )
    metadata_exclusions = {
        "publicCount", "readyCount", "unavailableCount", "sampleOnly", "visualCapture", "sampleCount",
        "performanceMode", "performanceRounds",
    }
    extra_metadata = [f"    {key} = {lua_quote(str(value))}," for key, value in metadata.items()
                      if key not in metadata_exclusions]
    return "\n".join([
        "-- Generated from the production presentation contract; do not hand edit.",
        "SoloCollectionsWeaponPresentationAuditData = {",
        *extra_metadata,
        f"    publicCount = {metadata['publicCount']},",
        f"    readyCount = {metadata['readyCount']},",
        f"    unavailableCount = {metadata['unavailableCount']},",
        f"    sampleOnly = {'true' if metadata.get('sampleOnly') else 'false'},",
        f"    visualCapture = {'true' if metadata.get('visualCapture') else 'false'},",
        f"    sampleCount = {int(metadata.get('sampleCount', 0))},",
        f"    performanceMode = {'true' if metadata.get('performanceMode') else 'false'},",
        f"    performanceRounds = {int(metadata.get('performanceRounds', 0))},",
        f"    cacheState = {lua_quote(cache_state)},",
        f"    autoLogout = {'true' if auto_logout else 'false'},",
        f"    autoLogoutDelay = {auto_logout_delay:.3f},",
        "    records = {",
        *rows,
        "    },",
        "}",
        "",
    ])


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source", type=Path, required=True)
    parser.add_argument("--report", type=Path, required=True)
    parser.add_argument("--catalog-manifest", type=Path, required=True)
    parser.add_argument("--sample-plan", type=Path, help="optional F:-resident visual sample plan")
    parser.add_argument("--performance-rounds", type=int, default=0,
                        help="repeat the full production card-pool audit for 1-3 measured performance rounds")
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--cache-state", choices=("cold", "hot", "reload"), required=True)
    parser.add_argument("--auto-logout", action="store_true")
    parser.add_argument("--auto-logout-delay", type=float, default=8.0)
    parser.add_argument("--check", action="store_true", help="require output to match the deterministic rendering")
    args = parser.parse_args()
    require(1.0 <= args.auto_logout_delay <= 60.0, "auto logout delay must be between 1 and 60 seconds")
    require(0 <= args.performance_rounds <= 3, "performance rounds must be between 0 and 3")
    require(not (args.sample_plan and args.performance_rounds),
            "visual sampling and performance rounds are mutually exclusive")
    source = ensure_f(args.source, "source")
    report = ensure_f(args.report, "report")
    catalog_manifest = ensure_f(args.catalog_manifest, "catalog manifest")
    sample_plan = ensure_f(args.sample_plan, "visual sample plan") if args.sample_plan else None
    output = ensure_f(args.output, "output")
    metadata, records = load_contract(source, report, catalog_manifest)
    if sample_plan:
        metadata, records = select_visual_samples(metadata, records, sample_plan)
    if args.performance_rounds:
        metadata.update({
            "performanceMode": True,
            "performanceRounds": args.performance_rounds,
        })
    content = render(metadata, records, args.cache_state, args.auto_logout, args.auto_logout_delay)
    if args.check:
        require(output.is_file(), f"audit data output is missing: {output}")
        require(output.read_text(encoding="utf-8") == content, f"audit data output is stale: {output}")
    else:
        output.parent.mkdir(parents=True, exist_ok=True)
        temporary = output.with_name(output.name + ".tmp")
        temporary.write_text(content, encoding="utf-8", newline="\n")
        os.replace(temporary, output)
    print(json.dumps({**metadata, "records": len(records), "cacheState": args.cache_state,
                      "autoLogout": bool(args.auto_logout), "output": str(output), "checked": bool(args.check)},
                     ensure_ascii=False))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
