#!/usr/bin/env python3
"""Create a deterministic real-client visual sampling plan for public weapon presentations."""

from __future__ import annotations

import argparse
import csv
import hashlib
import json
import os
from collections import defaultdict
from pathlib import Path
from typing import Any


PUBLIC_STATUSES = {"READY", "UNAVAILABLE"}
SPECIAL_FAMILIES = {
    "SHIELD": "SPECIAL_SHIELD_FRONT",
    "OFFHAND_ITEM": "SPECIAL_BOOK_OR_OFFHAND",
    "FIST_WEAPON": "SPECIAL_FIST_WEAPON",
    "BOW": "SPECIAL_BOW",
    "CROSSBOW": "SPECIAL_CROSSBOW",
    "GUN": "SPECIAL_GUN",
    "WAND": "SPECIAL_WAND",
    "THROWN": "SPECIAL_THROWN",
    "FISHING_POLE": "SPECIAL_FISHING_POLE",
}


def require(value: bool, message: str) -> None:
    if not value:
        raise ValueError(message)


def ensure_f(path: Path, label: str) -> Path:
    resolved = path.resolve()
    if os.name == "nt":
        require(resolved.drive.upper() == "F:", f"{label} must be on F:, got {resolved}")
    require(resolved.exists(), f"{label} is missing: {resolved}")
    return resolved


def sha256_file(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def decimal(value: str, label: str, appearance_id: int) -> float | None:
    if str(value).strip() == "":
        return None
    try:
        result = float(value)
    except (TypeError, ValueError) as exc:
        raise ValueError(f"{label} is invalid for appearance {appearance_id}: {value!r}") from exc
    require(result >= 0.0, f"{label} is negative for appearance {appearance_id}")
    return result


def load_groups(path: Path) -> dict[int, dict[str, Any]]:
    payload = json.loads(path.read_text(encoding="utf-8"))
    require(payload.get("schemaVersion") == 1, "appearance source schema drift")
    groups = payload.get("groups")
    require(isinstance(groups, list), "appearance groups are missing")
    result: dict[int, dict[str, Any]] = {}
    for row in groups:
        require(isinstance(row, dict), "appearance group is not an object")
        appearance_id = int(row.get("appearanceId", 0))
        require(appearance_id > 0 and appearance_id not in result,
                f"duplicate or invalid appearance source {appearance_id}")
        result[appearance_id] = row
    return result


def load_candidates(path: Path) -> dict[int, dict[str, str]]:
    result: dict[int, dict[str, str]] = {}
    with path.open("r", encoding="utf-8", newline="") as handle:
        for row in csv.DictReader(handle):
            appearance_id = int(row.get("appearanceId", "0"))
            require(appearance_id > 0 and appearance_id not in result,
                    f"duplicate or invalid weapon candidate {appearance_id}")
            result[appearance_id] = row
    return result


def add_selection(selected: dict[int, dict[str, Any]], record: dict[str, Any], kind: str) -> None:
    appearance_id = int(record["appearanceId"])
    target = selected.setdefault(appearance_id, record)
    target.setdefault("sampleKinds", set()).add(kind)


def choose_preferred(records: list[dict[str, Any]]) -> dict[str, Any]:
    ready = [record for record in records if record["presentationStatus"] == "READY"]
    return sorted(ready or records, key=lambda record: int(record["appearanceId"]))[0]


def make_records(source: dict[str, Any], groups: dict[int, dict[str, Any]],
                 candidates: dict[int, dict[str, str]]) -> list[dict[str, Any]]:
    entries = source.get("entries")
    require(source.get("schemaVersion") == 2 and isinstance(entries, list), "presentation source schema drift")
    result: list[dict[str, Any]] = []
    seen: set[int] = set()
    for entry in entries:
        require(isinstance(entry, dict), "presentation entry is not an object")
        status = str(entry.get("presentationStatus", ""))
        if status not in PUBLIC_STATUSES:
            continue
        appearance_id = int(entry.get("appearanceId", 0))
        require(appearance_id > 0 and appearance_id not in seen, f"duplicate appearance {appearance_id}")
        seen.add(appearance_id)
        group = groups.get(appearance_id)
        candidate = candidates.get(appearance_id)
        require(group is not None and candidate is not None,
                f"visual sampling source/candidate join is missing for {appearance_id}")
        weapon_type = str(entry.get("weaponType") or entry.get("weaponCategory") or "")
        slot = str(group.get("slotKey", ""))
        require(weapon_type and slot in {"MAINHAND", "OFFHAND"},
                f"weapon identity is incomplete for {appearance_id}")
        result.append({
            "appearanceId": appearance_id,
            "sourceItemId": int(entry.get("sourceItemId", 0)),
            "presentationStatus": status,
            "weaponType": weapon_type,
            "slot": slot,
            "modelPath": str(entry.get("modelPath", "")),
            "modelSignature": str(entry.get("modelSignature", "")),
            "syntheticDisplayId": int(entry.get("syntheticDisplayId") or 0),
            "textureKey": str(candidate.get("textureKey", "")),
            "radius": decimal(candidate.get("radius", ""), "radius", appearance_id),
            "extentRatio": decimal(candidate.get("extentRatio", ""), "extentRatio", appearance_id),
            "outlierReasons": sorted(filter(None, str(candidate.get("outlierReasons", "")).split(";"))),
        })
    expected = int(source.get("publicAppearanceCount", 0))
    require(len(result) == expected, f"public count drift: {len(result)} != {expected}")
    return sorted(result, key=lambda record: int(record["appearanceId"]))


def select(records: list[dict[str, Any]]) -> tuple[list[dict[str, Any]], dict[str, Any]]:
    by_family: dict[str, list[dict[str, Any]]] = defaultdict(list)
    for record in records:
        by_family[record["weaponType"]].append(record)
    selected: dict[int, dict[str, Any]] = {}
    shared_pairs = 0
    outlier_samples = 0
    for family in sorted(by_family):
        family_records = sorted(by_family[family], key=lambda record: int(record["appearanceId"]))
        for kind, record in (("FAMILY_FIRST", family_records[0]),
                             ("FAMILY_MIDDLE", family_records[(len(family_records) - 1) // 2]),
                             ("FAMILY_LAST", family_records[-1])):
            add_selection(selected, record, kind)

        ready = [record for record in family_records if record["presentationStatus"] == "READY"]
        require(ready, f"family has no renderable record: {family}")
        require(all(record["radius"] is not None for record in ready),
                f"renderable family has no bounds radius: {family}")
        add_selection(selected, min(ready, key=lambda record: (record["radius"], record["appearanceId"])), "MIN_BOUNDS")
        add_selection(selected, max(ready, key=lambda record: (record["radius"], record["appearanceId"])), "MAX_BOUNDS")

        for slot in ("MAINHAND", "OFFHAND"):
            slot_records = [record for record in family_records if record["slot"] == slot]
            if slot_records:
                add_selection(selected, choose_preferred(slot_records), "SLOT_" + slot)

        by_model: dict[str, list[dict[str, Any]]] = defaultdict(list)
        for record in ready:
            if record["modelSignature"] and record["textureKey"]:
                by_model[record["modelSignature"]].append(record)
        eligible = []
        for signature, entries in by_model.items():
            by_texture: dict[str, list[dict[str, Any]]] = defaultdict(list)
            for entry in entries:
                by_texture[entry["textureKey"]].append(entry)
            if len(by_texture) > 1:
                eligible.append((signature, by_texture))
        if eligible:
            _, by_texture = sorted(eligible, key=lambda pair: pair[0])[0]
            texture_keys = sorted(by_texture)
            for texture_key in texture_keys[:2]:
                add_selection(selected, sorted(by_texture[texture_key], key=lambda record: record["appearanceId"])[0],
                              "SHARED_MODEL_DIFFERENT_TEXTURE")
            shared_pairs += 1

        for reason in sorted({reason for record in ready for reason in record["outlierReasons"]}):
            candidates = [record for record in ready if reason in record["outlierReasons"]]
            if candidates:
                add_selection(selected, max(candidates, key=lambda record: (record["radius"], record["appearanceId"])),
                              "OUTLIER_" + reason)
                outlier_samples += 1

    for family, kind in SPECIAL_FAMILIES.items():
        candidates = by_family.get(family)
        require(candidates, f"required special family is missing: {family}")
        add_selection(selected, choose_preferred(candidates), kind)

    ordered: list[dict[str, Any]] = []
    for appearance_id in sorted(selected):
        record = dict(selected[appearance_id])
        record["sampleKinds"] = sorted(record.get("sampleKinds", set()))
        ordered.append(record)
    coverage = {
        "familyCount": len(by_family),
        "families": sorted(by_family),
        "sharedModelDifferentTextureFamilies": shared_pairs,
        "outlierSamples": outlier_samples,
        "specialFamilies": sorted(SPECIAL_FAMILIES),
    }
    for family in by_family:
        require(any("FAMILY_FIRST" in record["sampleKinds"] for record in ordered
                    if record["weaponType"] == family),
                f"family-first selection is incomplete for {family}")
    return ordered, coverage


def select_baseline_regression(source: dict[str, Any], records: list[dict[str, Any]],
                               baseline: dict[str, Any]) -> tuple[list[dict[str, Any]], dict[str, Any]]:
    """Select every still-public legacy sample and prove all baseline poses stayed exact.

    One of the 21 fixed samples is intentionally non-public in the current
    catalogue.  It cannot be placed in a production wardrobe visual page, but
    remains part of the static zero-drift comparison below.
    """
    require(baseline.get("schemaVersion") == 1 and isinstance(baseline.get("entries"), list),
            "baseline presentation source schema drift")
    current_entries = source.get("entries")
    require(isinstance(current_entries, list), "presentation source entries are missing")
    current_by_appearance = {int(entry["appearanceId"]): entry for entry in current_entries}
    public_by_appearance = {int(record["appearanceId"]): record for record in records}
    selected: list[dict[str, Any]] = []
    seen: set[int] = set()
    retained_nonpublic: list[int] = []
    for baseline_entry in baseline["entries"]:
        require(isinstance(baseline_entry, dict), "baseline presentation entry is not an object")
        appearance_id = int(baseline_entry.get("appearanceId", 0))
        require(appearance_id > 0 and appearance_id not in seen,
                f"baseline appearance is invalid or duplicated: {appearance_id}")
        seen.add(appearance_id)
        current = current_by_appearance.get(appearance_id)
        require(current is not None, f"legacy baseline appearance is missing: {appearance_id}")
        for field in ("syntheticDisplayId", "modelPath", "m2Camera"):
            require(current.get(field) == baseline_entry.get(field),
                    f"legacy baseline {field} drifted for {appearance_id}")
        status = str(current.get("presentationStatus", ""))
        if status in PUBLIC_STATUSES:
            record = public_by_appearance.get(appearance_id)
            require(record is not None, f"public legacy baseline is absent from sample source: {appearance_id}")
            selected_record = dict(record)
            selected_record["sampleKinds"] = ["LEGACY_BASELINE_VISUAL"]
            selected.append(selected_record)
        else:
            require(status == "RETAINED_BASELINE" and
                    current.get("presentationAudience") == "NONPUBLIC_BASELINE",
                    f"legacy baseline has unsupported audience/status: {appearance_id}")
            retained_nonpublic.append(appearance_id)
    require(selected, "legacy baseline has no public visual samples")
    selected.sort(key=lambda record: int(record["appearanceId"]))
    return selected, {
        "baselineRegression": True,
        "baselineAppearanceCount": len(seen),
        "publicVisualSampleCount": len(selected),
        "retainedNonPublicAppearanceIds": sorted(retained_nonpublic),
        "zeroDriftFields": ["syntheticDisplayId", "modelPath", "m2Camera"],
    }


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source", type=Path, required=True)
    parser.add_argument("--appearance-sources", type=Path, required=True)
    parser.add_argument("--candidate-csv", type=Path, required=True)
    parser.add_argument("--baseline-source", type=Path,
                        help="optional schema-1 21-sample source for a zero-drift visual regression plan")
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args()

    source_path = ensure_f(args.source, "source")
    groups_path = ensure_f(args.appearance_sources, "appearance sources")
    candidate_path = ensure_f(args.candidate_csv, "candidate CSV")
    baseline_path = ensure_f(args.baseline_source, "baseline source") if args.baseline_source else None
    output = args.output.resolve()
    if os.name == "nt":
        require(output.drive.upper() == "F:", f"output must be on F:, got {output}")

    source = json.loads(source_path.read_text(encoding="utf-8"))
    groups = load_groups(groups_path)
    candidates = load_candidates(candidate_path)
    all_records = make_records(source, groups, candidates)
    if baseline_path:
        baseline = json.loads(baseline_path.read_text(encoding="utf-8"))
        records, coverage = select_baseline_regression(source, all_records, baseline)
    else:
        records, coverage = select(all_records)
    bundle = source.get("assetBundle") or {}
    payload = {
        "schemaVersion": 1,
        "kind": "SoloCollectionsWeaponPresentationVisualSamplePlan",
        "assetPackVersion": source.get("assetPackVersion"),
        "bundleId": bundle.get("bundleId"),
        "presentationSourceSha256": sha256_file(source_path),
        "appearanceSourcesSha256": sha256_file(groups_path),
        "candidateCsvSha256": sha256_file(candidate_path),
        "baselineSourceSha256": sha256_file(baseline_path) if baseline_path else None,
        "publicAppearanceCount": source.get("publicAppearanceCount"),
        "sampleCount": len(records),
        "readySampleCount": sum(record["presentationStatus"] == "READY" for record in records),
        "unavailableSampleCount": sum(record["presentationStatus"] == "UNAVAILABLE" for record in records),
        "coverage": coverage,
        "records": records,
    }
    content = json.dumps(payload, ensure_ascii=False, indent=2, sort_keys=True) + "\n"
    if args.check:
        require(output.is_file(), f"visual sample plan is missing: {output}")
        require(output.read_text(encoding="utf-8") == content, f"visual sample plan is stale: {output}")
    else:
        output.parent.mkdir(parents=True, exist_ok=True)
        temporary = output.with_name(output.name + ".tmp")
        temporary.write_text(content, encoding="utf-8", newline="\n")
        os.replace(temporary, output)
    print(json.dumps({"sampleCount": payload["sampleCount"], **coverage, "output": str(output),
                      "checked": bool(args.check)}, ensure_ascii=False))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
