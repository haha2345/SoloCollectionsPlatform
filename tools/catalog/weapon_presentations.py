#!/usr/bin/env python3
"""Project the runtime-safe weapon registry into the production presentation source.

The Stage 6/7 shadow evidence deliberately remained outside the normal catalog
until a real 3.3.5 client audit completed.  This tool is the narrow, audited
boundary that turns that immutable, runtime-safe projection into the source
consumed by ``appearance_presentations.py``.  It never scans a live client and
it never allocates IDs: both are already frozen by the registry/stage inputs.
"""

from __future__ import annotations

import argparse
import csv
import hashlib
import importlib.util
import json
import sys
from copy import deepcopy
from pathlib import Path
from typing import Any


CATALOG_ROOT = Path(__file__).resolve().parent
REPO_ROOT = CATALOG_ROOT.parents[1]
if str(CATALOG_ROOT) not in sys.path:
    sys.path.insert(0, str(CATALOG_ROOT))

from model_camera_overrides import (  # noqa: E402
    ModelCameraOverrideError,
    load_model_camera_overrides,
)


EXPECTED_PUBLIC = 3690
DIRECT_DISPLAY_CAPABILITY = "DIRECT_DISPLAY_V1"
UNAVAILABLE_CAPABILITY = "UNAVAILABLE"
DEFAULT_MODEL_CAMERA_OVERRIDES = (
    REPO_ROOT / "catalog" / "source" / "overrides" / "weapon_model_camera_overrides.json"
)


class WeaponPresentationError(RuntimeError):
    pass


def require(value: bool, message: str) -> None:
    if not value:
        raise WeaponPresentationError(message)


def canonical(value: Any) -> bytes:
    return (json.dumps(value, ensure_ascii=False, sort_keys=True, separators=(",", ":")) + "\n").encode("utf-8")


def pretty(value: Any) -> str:
    return json.dumps(value, ensure_ascii=False, sort_keys=True, indent=2) + "\n"


def sha_path(path: Path) -> str:
    digest = hashlib.sha256()
    try:
        with path.open("rb") as handle:
            for chunk in iter(lambda: handle.read(1024 * 1024), b""):
                digest.update(chunk)
    except OSError as exc:
        raise WeaponPresentationError(f"cannot hash {path}: {exc}") from exc
    return digest.hexdigest()


def read_json(path: Path) -> Any:
    try:
        return json.loads(path.read_text(encoding="utf-8-sig"))
    except (OSError, UnicodeDecodeError, json.JSONDecodeError) as exc:
        raise WeaponPresentationError(f"cannot read JSON {path}: {exc}") from exc


def verify_hash_object(value: dict[str, Any], field: str) -> dict[str, Any]:
    copy = deepcopy(value)
    expected = copy.pop(field, None)
    require(
        isinstance(expected, str) and expected == hashlib.sha256(canonical(copy)).hexdigest(),
        f"{field} drift",
    )
    return value


def normalize_path(value: str) -> str:
    return value.replace("/", "\\").strip("\\").lower()


def load_shadow_module() -> Any:
    path = Path(__file__).with_name("weapon_shadow.py")
    spec = importlib.util.spec_from_file_location("solo_weapon_shadow", path)
    require(spec is not None and spec.loader is not None, "cannot load weapon shadow helper")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def read_candidates(path: Path) -> tuple[bytes, dict[int, dict[str, str]]]:
    try:
        raw = path.read_bytes()
        with path.open("r", encoding="utf-8-sig", newline="") as handle:
            rows = list(csv.DictReader(handle))
    except OSError as exc:
        raise WeaponPresentationError(f"cannot read candidate CSV {path}: {exc}") from exc
    required = {
        "appearanceId", "collectionKey", "scope", "terminalStatus", "assetStatus",
        "presentationStatus", "reasonCodes", "primarySourceItemId", "nativeDisplayId",
        "route", "modelPath", "modelSignature", "syntheticDisplayId", "allocationStatus",
        "cameraPreset",
    }
    require(rows and required.issubset(rows[0]), "candidate CSV schema is incomplete")
    result: dict[int, dict[str, str]] = {}
    for row in rows:
        try:
            appearance_id = int(row["appearanceId"])
        except (KeyError, TypeError, ValueError) as exc:
            raise WeaponPresentationError("candidate CSV has invalid appearance ID") from exc
        require(appearance_id not in result, f"candidate CSV duplicates appearance {appearance_id}")
        result[appearance_id] = dict(row)
    return raw, result


def load_appearance_sources(path: Path) -> tuple[dict[int, dict[str, Any]], dict[int, dict[str, Any]]]:
    data = read_json(path)
    groups = data.get("groups")
    require(isinstance(groups, list), "appearance sources has no groups")
    by_item: dict[int, dict[str, Any]] = {}
    by_appearance: dict[int, dict[str, Any]] = {}
    for group in groups:
        if group.get("lifecycle") != "active":
            continue
        appearance_id = int(group.get("appearanceId", 0))
        require(appearance_id > 0 and appearance_id not in by_appearance,
                f"appearance sources duplicate canonical ID {appearance_id}")
        by_appearance[appearance_id] = group
        for raw_item_id in group.get("sourceItemIds", []):
            item_id = int(raw_item_id)
            require(item_id > 0 and item_id not in by_item,
                    f"appearance sources duplicate item ID {item_id}")
            by_item[item_id] = group
    return by_item, by_appearance


def load_baseline(path: Path) -> tuple[str, dict[int, dict[str, Any]], dict[int, dict[str, Any]]]:
    source = read_json(path)
    require(source.get("schemaVersion") == 1, "baseline presentation schema drift")
    entries = source.get("entries")
    require(isinstance(entries, list) and len(entries) == 21, "baseline must retain exactly 21 records")
    by_appearance: dict[int, dict[str, Any]] = {}
    by_item: dict[int, dict[str, Any]] = {}
    for entry in entries:
        appearance_id = int(entry.get("appearanceId", 0))
        item_id = int(entry.get("sourceItemId", 0))
        display_id = int(entry.get("syntheticDisplayId", 0))
        require(appearance_id > 0 and item_id > 0 and display_id > 0,
                "baseline has invalid identity")
        require(appearance_id not in by_appearance and item_id not in by_item,
                "baseline duplicates appearance or source item")
        require(entry.get("presentationStatus") == "verified", "baseline verification status drift")
        require(isinstance(entry.get("m2Camera"), dict), "baseline camera is missing")
        by_appearance[appearance_id] = deepcopy(entry)
        by_item[item_id] = deepcopy(entry)
    return sha_path(path), by_appearance, by_item


def asset_hashes(stage: dict[str, Any], model_path: str, texture_name: str) -> dict[str, str]:
    files = {
        normalize_path(str(row.get("relativePath", ""))): row
        for row in stage.get("files", [])
    }
    model_key = normalize_path(model_path)
    require(model_key.endswith(".m2"), f"invalid stage model path {model_path}")
    skin_key = model_key[:-3] + "00.skin"
    texture_key = normalize_path("Item\\ObjectComponents\\SoloCollections\\" + texture_name + ".blp")
    result: dict[str, str] = {}
    for label, key in (("m2", model_key), ("skin", skin_key), ("texture", texture_key)):
        row = files.get(key)
        require(row is not None and isinstance(row.get("sha256"), str),
                f"stage lacks declared {label} resource {key}")
        result[label] = str(row["sha256"]).lower()
    return result


def weapon_identity(
    plan_row: dict[str, Any], model_path: str, fallback_family: str, shadow: Any
) -> tuple[str, str]:
    route = str(plan_row.get("route", ""))
    if route == "SHIELD":
        return "SHIELD", "SHIELD"
    if route == "HELD_IN_OFFHAND":
        return "OFFHAND_ITEM", "OFFHAND_ITEM"
    source_items = plan_row.get("sourceItems") or []
    primary_id = int(plan_row.get("primarySourceItemId", 0))
    primary = next((row for row in source_items if int(row.get("entry", 0)) == primary_id), None)
    require(primary is not None, f"shadow plan has no primary source item {primary_id}")
    category = shadow.FAMILY_BY_SUBCLASS.get(int(primary.get("itemSubclass", -1)))
    # A handful of 3.3.5 world rows use the obsolete/misc weapon subclasses
    # while their ItemDisplayInfo/M2 is nevertheless a normal one-hand item.
    # The Stage 6 family classifier already chose a stable camera family for
    # those rows; use that frozen result rather than guessing from a localized
    # item name or dropping an otherwise valid public record.
    if category is None:
        category = fallback_family
    require(category and category != "WAR_GLAIVE_MAINHAND" and category != "WAR_GLAIVE_OFFHAND",
            f"unsupported weapon subclass for {primary_id}")
    if "glave" in str(model_path).lower():
        return "WAR_GLAIVE", "ONE_HAND_SWORD"
    return category, category


def normalized_pose(pose: dict[str, Any]) -> dict[str, Any]:
    target = pose.get("target") or {}
    required = ("yaw", "pitch", "roll", "distanceScale")
    require(all(isinstance(pose.get(key), (int, float)) for key in required), "generated camera pose is incomplete")
    require(all(isinstance(target.get(key), (int, float)) for key in ("x", "y", "z")),
            "generated camera target is incomplete")
    return {
        "yaw": float(pose["yaw"]),
        "pitch": float(pose["pitch"]),
        "roll": float(pose["roll"]),
        "distanceScale": float(pose["distanceScale"]),
        "target": {"x": float(target["x"]), "y": float(target["y"]), "z": float(target["z"])},
    }


def reason_code(candidate: dict[str, str]) -> str:
    values = sorted({value for value in str(candidate.get("reasonCodes", "")).split(";")
                     if value and value != "READY"})
    require(values, f"unavailable candidate has no reason code: {candidate.get('appearanceId')}")
    return ";".join(values)


def render_source(
    baseline_path: Path,
    appearance_sources_path: Path,
    runtime_review_root: Path,
    stage_root: Path,
    shadow_evidence_root: Path,
    asset_pack_version: str,
    model_camera_overrides_path: Path | None = None,
) -> dict[str, Any]:
    """Build the deterministic schema-v2 production presentation source."""

    require(asset_pack_version and asset_pack_version.strip(), "asset pack version is required")
    model_camera_overrides = load_model_camera_overrides(
        model_camera_overrides_path or DEFAULT_MODEL_CAMERA_OVERRIDES
    )
    baseline_sha, baseline_by_appearance, baseline_by_item = load_baseline(baseline_path)
    source_by_item, source_by_appearance = load_appearance_sources(appearance_sources_path)

    runtime_summary = verify_hash_object(read_json(runtime_review_root / "shadow-summary.json"), "summaryHash")
    runtime_registry = verify_hash_object(read_json(runtime_review_root / "shadow-registry.json"), "registryHash")
    runtime_projection = verify_hash_object(read_json(runtime_review_root / "runtime-projection.json"), "runtimeProjectionHash")
    candidate_bytes, candidates = read_candidates(runtime_review_root / "shadow-candidates.csv")
    require(runtime_summary.get("registryHash") == runtime_registry.get("registryHash"),
            "runtime review registry hash drift")
    require(runtime_summary.get("candidateCsvSha256") == hashlib.sha256(candidate_bytes).hexdigest(),
            "runtime review candidate CSV hash drift")
    require(runtime_projection.get("result", {}).get("summaryHash") == runtime_summary.get("summaryHash"),
            "runtime projection summary lock drift")
    require(runtime_projection.get("result", {}).get("registryHash") == runtime_registry.get("registryHash"),
            "runtime projection registry lock drift")
    require(runtime_projection.get("result", {}).get("candidateCsvSha256") == runtime_summary.get("candidateCsvSha256"),
            "runtime projection candidate lock drift")

    stage = verify_hash_object(read_json(stage_root / "weapon-bundle-manifest.json"), "bundleManifestHash")
    require(stage.get("kind") == "SoloCollectionsWeaponBundleStage", "unsupported weapon asset stage")
    require(stage.get("assetPackVersion") == asset_pack_version,
            "stage asset pack version differs from presentation source")
    stage_inputs = stage.get("inputs") or {}
    require(stage_inputs.get("registryHash") == runtime_registry.get("registryHash"),
            "stage registry hash drift")
    require(stage_inputs.get("candidateCsvSha256") == runtime_summary.get("candidateCsvSha256"),
            "stage candidate CSV hash drift")
    require(stage_inputs.get("modelCameraOverridesSha256") == model_camera_overrides["sha256"],
            "stage model camera override source hash drift")

    shadow = load_shadow_module()
    asset_plan = verify_hash_object(read_json(shadow_evidence_root / "asset-plan.json"), "assetPlanHash")
    asset_index = verify_hash_object(read_json(shadow_evidence_root / "asset-index.json"), "assetIndexHash")
    require(asset_plan.get("assetPlanHash") == runtime_summary.get("assetPlanHash"), "shadow plan hash drift")
    require(asset_index.get("assetPlanHash") == asset_plan.get("assetPlanHash"), "shadow index plan hash drift")
    require(asset_index.get("assetIndexHash") == runtime_summary.get("assetIndexHash"), "shadow index hash drift")
    plans = {int(row["appearanceId"]): row for row in asset_plan.get("candidates", [])}
    assets = {str(row["assetId"]): row for row in asset_index.get("assets", [])}
    require(len(plans) == len(asset_plan.get("candidates", [])), "shadow plan duplicates appearance")
    require(len(assets) == len(asset_index.get("assets", [])), "shadow index duplicates asset")

    registry_entries = runtime_registry.get("entries") or []
    registry_tombstones = runtime_registry.get("tombstones") or []
    registry_by_appearance = {int(row["appearanceId"]): row for row in registry_entries}
    tombstone_by_appearance = {int(row["appearanceId"]): row for row in registry_tombstones}
    require(len(registry_by_appearance) == len(registry_entries), "runtime registry duplicates appearance")
    require(not (set(registry_by_appearance) & set(tombstone_by_appearance)),
            "runtime registry active/tombstone overlap")
    for signature, override in model_camera_overrides["overrides"].items():
        matching = sorted(
            int(row["appearanceId"])
            for row in registry_entries
            if row.get("modelSignature") == signature
        )
        require(matching == override["expectedAppearanceIds"],
                f"model camera override appearance scope drift: {signature}")
    stage_records = {
        int(row["appearanceId"]): row
        for row in (stage.get("registryProjection") or {}).get("records", [])
    }
    require(len(stage_records) == int(stage.get("selection", {}).get("appearanceCount", -1)),
            "stage registry projection is incomplete")

    public_candidates = {
        appearance_id: row for appearance_id, row in candidates.items()
        if row.get("scope") == "PUBLIC"
    }
    require(len(public_candidates) == EXPECTED_PUBLIC, "public presentation denominator drift")
    terminal_counts = runtime_projection.get("result", {}).get("terminalCounts") or {}
    require(
        int(terminal_counts.get("publicReady", -1)) + int(terminal_counts.get("publicUnavailable", -1))
        == EXPECTED_PUBLIC,
        "runtime projection terminal denominator drift",
    )

    presets = shadow.preset_map({"entries": list(baseline_by_appearance.values())})
    entries: list[dict[str, Any]] = []
    seen_item_ids: set[int] = set()
    seen_appearance_ids: set[int] = set()
    display_projection: dict[int, tuple[str, dict[str, str]]] = {}

    def generated_model_camera_override(appearance_id: int, model_signature: str, hashes: dict[str, str]) -> dict[str, Any] | None:
        override = model_camera_overrides["overrides"].get(model_signature)
        if override is None:
            return None
        require(appearance_id in override["expectedAppearanceIds"],
                f"model camera override appearance drift: {appearance_id}")
        require(hashes.get("m2") == override["expectedOutputM2Sha256"],
                f"model camera override resource hash drift: {appearance_id}")
        return {
            "scope": "model",
            "key": model_signature,
            "modelSignature": model_signature,
            "reasonCode": override["reasonCode"],
            "cameraStrategy": override["cameraStrategy"],
            "workbenchExportSha256": override["workbenchExportSha256"],
            "pose": deepcopy(override["presentationPose"]),
        }

    for appearance_id, candidate in sorted(public_candidates.items()):
        baseline = baseline_by_appearance.get(appearance_id)
        candidate_item_id = int(candidate.get("primarySourceItemId", 0))
        item_id = int(baseline["sourceItemId"]) if baseline is not None else candidate_item_id
        require(item_id > 0 and item_id not in seen_item_ids, f"duplicate public source item {item_id}")
        require(appearance_id not in seen_appearance_ids, f"duplicate public appearance {appearance_id}")
        candidate_source = source_by_item.get(candidate_item_id)
        require(candidate_source is not None and int(candidate_source.get("appearanceId", 0)) == appearance_id,
                f"candidate canonical source drift: {appearance_id}")
        require(candidate_source.get("collectionKey") == candidate.get("collectionKey"),
                f"candidate collection key drift: {appearance_id}")
        source = source_by_item.get(item_id)
        require(source is not None and int(source.get("appearanceId", 0)) == appearance_id,
                f"presentation source item drift: {appearance_id}")
        plan_row = plans.get(appearance_id)
        require(plan_row is not None, f"shadow plan lacks public appearance {appearance_id}")
        weapon_type, weapon_category = weapon_identity(
            plan_row,
            str(candidate.get("modelPath", "")),
            str(candidate.get("cameraPreset", "")),
            shadow,
        )
        base = {
            "sourceItemId": item_id,
            "appearanceId": appearance_id,
            "nativeDisplayId": int(candidate.get("nativeDisplayId", 0)),
            "weaponType": weapon_type,
            "weaponCategory": weapon_category,
            "assetPackVersion": asset_pack_version,
        }
        require(base["nativeDisplayId"] > 0, f"candidate native display is invalid: {appearance_id}")

        if candidate.get("terminalStatus") == "READY":
            registry = registry_by_appearance.get(appearance_id)
            stage_record = stage_records.get(appearance_id)
            require(registry is not None and stage_record is not None,
                    f"READY appearance lacks active registry/stage record: {appearance_id}")
            require(registry.get("allocationStatus") in {"ACTIVE", "RESERVED"},
                    f"READY appearance has invalid registry allocation: {appearance_id}")
            display_id = int(registry.get("syntheticDisplayId", 0))
            require(display_id > 0 and display_id == int(stage_record.get("syntheticDisplayId", 0)),
                    f"READY appearance display projection drift: {appearance_id}")
            model_path = str(stage_record.get("modelPath", ""))
            texture_name = str(stage_record.get("textureName", ""))
            hashes = asset_hashes(stage, model_path, texture_name)
            previous_projection = display_projection.get(display_id)
            projection = (normalize_path(model_path), hashes)
            if previous_projection is not None:
                require(previous_projection == projection,
                        f"shared synthetic display has conflicting assets: {display_id}")
            else:
                display_projection[display_id] = projection

            if baseline is not None:
                require(display_id == int(baseline["syntheticDisplayId"]),
                        f"reserved baseline display ID drift: {appearance_id}")
                require(normalize_path(model_path) == normalize_path(str(baseline["modelPath"])),
                        f"reserved baseline model path drift: {appearance_id}")
                pose = normalized_pose(baseline["m2Camera"])
                model_scale = float(baseline["modelScale"])
                camera_key = str(baseline["cameraTuningKey"])
                weapon_type = str(baseline["weaponType"])
                weapon_category = str(baseline["weaponCategory"])
            else:
                model_asset_id = str(plan_row.get("refs", {}).get("model", ""))
                model_asset = assets.get(model_asset_id)
                require(model_asset is not None, f"shadow index lacks model asset for {appearance_id}")
                camera, _fallback = shadow.auto_camera(plan_row, model_asset, presets)
                pose = normalized_pose(camera["presetPose"])
                camera_key = str(camera["presetKey"])
                require(camera_key == candidate.get("cameraPreset"),
                        f"generated camera family drift: {appearance_id}")
                model_scale = 0.88

            model_signature = str(registry.get("modelSignature", ""))
            record = {
                **base,
                "syntheticDisplayId": display_id,
                "modelPath": model_path,
                "modelScale": model_scale,
                "cameraTuningKey": camera_key,
                "m2Camera": pose,
                "autoCamera": pose,
                "modelSignature": model_signature,
                "assetHashes": hashes,
                "presentationStatus": "READY",
                "renderMode": "STANDALONE",
                "presentationCapability": DIRECT_DISPLAY_CAPABILITY,
            }
            override = generated_model_camera_override(appearance_id, model_signature, hashes)
            if override is not None:
                record["generatedModelCameraOverride"] = override
            entries.append(record)
        else:
            require(candidate.get("terminalStatus") == "UNAVAILABLE",
                    f"public candidate is not terminal: {appearance_id}")
            tombstone = tombstone_by_appearance.get(appearance_id)
            record = {
                **base,
                "presentationStatus": "UNAVAILABLE",
                "renderMode": "UNAVAILABLE",
                "presentationCapability": UNAVAILABLE_CAPABILITY,
                "presentationReasonCode": reason_code(candidate),
            }
            if candidate.get("modelSignature"):
                record["modelSignature"] = str(candidate["modelSignature"])
            if tombstone is not None:
                record["retiredSyntheticDisplayId"] = int(tombstone["syntheticDisplayId"])
                record["registryTombstoneReason"] = str(tombstone.get("tombstoneReason", ""))
            entries.append(record)
        seen_item_ids.add(item_id)
        seen_appearance_ids.add(appearance_id)

    # One historical baseline (Frostmourne) is intentionally non-public under
    # the canonical visibility policy.  Keep it in the registry-backed source
    # as a non-public regression sentinel: it retains its original display,
    # M2 and pose without widening the public 3,690-item denominator.
    retained_nonpublic = 0
    for appearance_id, baseline in sorted(baseline_by_appearance.items()):
        if appearance_id in seen_appearance_ids:
            continue
        candidate = candidates.get(appearance_id)
        registry = registry_by_appearance.get(appearance_id)
        stage_record = stage_records.get(appearance_id)
        item_id = int(baseline["sourceItemId"])
        require(candidate is not None and candidate.get("scope") != "PUBLIC"
                and candidate.get("terminalStatus") == "NONPUBLIC",
                f"reserved non-public baseline drift: {appearance_id}")
        require(registry is not None and registry.get("allocationStatus") == "RESERVED"
                and stage_record is not None,
                f"reserved non-public baseline lacks stage record: {appearance_id}")
        source = source_by_item.get(item_id)
        require(source is not None and int(source.get("appearanceId", 0)) == appearance_id,
                f"non-public baseline canonical source drift: {appearance_id}")
        display_id = int(registry["syntheticDisplayId"])
        model_path = str(stage_record.get("modelPath", ""))
        texture_name = str(stage_record.get("textureName", ""))
        hashes = asset_hashes(stage, model_path, texture_name)
        require(display_id == int(baseline["syntheticDisplayId"])
                and normalize_path(model_path) == normalize_path(str(baseline["modelPath"])),
                f"reserved non-public baseline resource drift: {appearance_id}")
        projection = (normalize_path(model_path), hashes)
        existing = display_projection.get(display_id)
        if existing is not None:
            require(existing == projection, f"shared non-public display conflict: {display_id}")
        else:
            display_projection[display_id] = projection
        model_signature = str(registry["modelSignature"])
        record = {
            "sourceItemId": item_id,
            "appearanceId": appearance_id,
            "nativeDisplayId": int(candidate["nativeDisplayId"]),
            "syntheticDisplayId": display_id,
            "modelPath": model_path,
            "modelScale": float(baseline["modelScale"]),
            "weaponType": str(baseline["weaponType"]),
            "weaponCategory": str(baseline["weaponCategory"]),
            "cameraTuningKey": str(baseline["cameraTuningKey"]),
            "m2Camera": normalized_pose(baseline["m2Camera"]),
            "autoCamera": normalized_pose(baseline["m2Camera"]),
            "modelSignature": model_signature,
            "assetHashes": hashes,
            "assetPackVersion": asset_pack_version,
            "presentationStatus": "RETAINED_BASELINE",
            "renderMode": "STANDALONE",
            "presentationCapability": DIRECT_DISPLAY_CAPABILITY,
            "presentationAudience": "NONPUBLIC_BASELINE",
        }
        override = generated_model_camera_override(appearance_id, model_signature, hashes)
        if override is not None:
            record["generatedModelCameraOverride"] = override
        entries.append(record)
        seen_item_ids.add(item_id)
        seen_appearance_ids.add(appearance_id)
        retained_nonpublic += 1

    require(len(entries) == EXPECTED_PUBLIC + retained_nonpublic, "production presentation count drift")
    require(set(baseline_by_appearance).issubset(seen_appearance_ids),
            "reserved baseline appearance absent from production projection")
    ready_count = sum(row["presentationStatus"] == "READY" for row in entries)
    unavailable_count = sum(row["presentationStatus"] == "UNAVAILABLE" for row in entries)
    require(ready_count == int(terminal_counts.get("publicReady", -1)), "READY count drift")
    require(unavailable_count == int(terminal_counts.get("publicUnavailable", -1)), "UNAVAILABLE count drift")
    return {
        "schemaVersion": 2,
        "assetPackVersion": asset_pack_version,
        "baselineSourceSha256": baseline_sha,
        "publicAppearanceCount": EXPECTED_PUBLIC,
        "retainedNonPublicBaselineCount": retained_nonpublic,
        "terminalCounts": {"READY": ready_count, "UNAVAILABLE": unavailable_count},
        "runtimeProjection": {
            "runtimeProjectionHash": runtime_projection["runtimeProjectionHash"],
            "runtimeQuarantineHash": runtime_projection["runtimeQuarantineHash"],
            "summaryHash": runtime_summary["summaryHash"],
            "registryHash": runtime_registry["registryHash"],
            "candidateCsvSha256": runtime_summary["candidateCsvSha256"],
        },
        "assetBundle": {
            "bundleId": stage["bundleId"],
            "assetPackVersion": stage["assetPackVersion"],
            "bundleManifestHash": stage["bundleManifestHash"],
            "registryHash": stage_inputs["registryHash"],
            "candidateCsvSha256": stage_inputs["candidateCsvSha256"],
        },
        "modelCameraOverrides": {
            "sourceSha256": model_camera_overrides["sha256"],
            "count": len(model_camera_overrides["overrides"]),
        },
        "entries": sorted(entries, key=lambda row: int(row["appearanceId"])),
    }


def write_output(path: Path, text: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.with_name(path.name + ".tmp")
    temporary.write_text(text, encoding="utf-8", newline="\n")
    temporary.replace(path)


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest="command", required=True)
    for name in ("generate", "check"):
        current = commands.add_parser(name)
        current.add_argument("--baseline-source", type=Path, required=True)
        current.add_argument("--appearance-sources", type=Path, required=True)
        current.add_argument("--runtime-review-root", type=Path, required=True)
        current.add_argument("--stage-root", type=Path, required=True)
        current.add_argument("--shadow-evidence-root", type=Path, required=True)
        current.add_argument("--asset-pack-version", required=True)
        current.add_argument("--model-camera-overrides", type=Path, default=DEFAULT_MODEL_CAMERA_OVERRIDES)
        current.add_argument("--output", type=Path, required=True)
    args = parser.parse_args(argv)
    try:
        rendered = pretty(render_source(
            args.baseline_source,
            args.appearance_sources,
            args.runtime_review_root,
            args.stage_root,
            args.shadow_evidence_root,
            args.asset_pack_version,
            args.model_camera_overrides,
        ))
        if args.command == "check":
            require(args.output.is_file() and args.output.read_text(encoding="utf-8") == rendered,
                    f"stale production weapon presentation source: {args.output}")
        else:
            write_output(args.output, rendered)
        print(json.dumps({"output": str(args.output), "sha256": hashlib.sha256(rendered.encode("utf-8")).hexdigest()},
                         ensure_ascii=False, sort_keys=True))
    except (WeaponPresentationError, ModelCameraOverrideError) as exc:
        parser.error(str(exc))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
