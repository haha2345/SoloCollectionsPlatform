#!/usr/bin/env python3
"""Build a self-contained, append-only WotLK weapon asset bundle.

This is the production-bound half of the stage-six weapon shadow.  It only
accepts the frozen shadow evidence plus the generated registry; it never
walks a live client directory.  The output is an atomic staging directory
that can subsequently be packed into an asset MPQ and a locale DBC MPQ.
"""

from __future__ import annotations

import argparse
import csv
import hashlib
import json
import os
import shutil
import struct
import sys
import uuid
from collections import Counter, defaultdict
from pathlib import Path
from typing import Any


REPO_ROOT = Path(__file__).resolve().parents[2]
CATALOG_ROOT = Path(__file__).resolve().parent
if str(CATALOG_ROOT) not in sys.path:
    sys.path.insert(0, str(CATALOG_ROOT))
SOLOCAM_SCRIPT_ROOT = REPO_ROOT / "client-extension" / "SoloCam" / "scripts"
if str(SOLOCAM_SCRIPT_ROOT) not in sys.path:
    sys.path.insert(0, str(SOLOCAM_SCRIPT_ROOT))

from build_creature_weapon_assets import (  # noqa: E402
    add_string,
    convert_object_skin,
    find_record,
    parse_wdbc,
    write_wdbc,
)
from patch_item_m2_textures import (  # noqa: E402
    append_static_item_camera,
    replace_existing_item_camera_from_vertex_bounds,
)
from model_camera_overrides import (  # noqa: E402
    CAMERA_STRATEGY,
    ModelCameraOverrideError,
    load_model_camera_overrides,
)


SCHEMA_VERSION = 1
CONVERTER_VERSION = "weapon-shadow-creature-converter-v1"
DISPLAY_REQUEST_BASE = 0x6F000000
MAX_DISPLAY_ID = 0x00FFFFFF
# CreatureModelData.dbc model-name strings are consumed by the 3.3.5 client
# as Windows-style MPQ paths.  File-list / StormLib APIs can normalize either
# separator, but the DBC loader cannot be assumed to do so; keep this canonical
# form distinct from the manifest's forward-slash relative paths.
MODEL_TARGET_ROOT = "Item\\ObjectComponents\\SoloCollections"
DEFAULT_MODEL_CAMERA_OVERRIDES = (
    REPO_ROOT / "catalog" / "source" / "overrides" / "weapon_model_camera_overrides.json"
)


class WeaponBundleError(RuntimeError):
    """Raised when a frozen input or generated bundle violates the contract."""


def require(value: bool, message: str) -> None:
    if not value:
        raise WeaponBundleError(message)


def canonical(value: Any) -> bytes:
    return (
        json.dumps(value, ensure_ascii=False, sort_keys=True, separators=(",", ":"))
        + "\n"
    ).encode("utf-8")


def pretty(value: Any) -> str:
    return json.dumps(value, ensure_ascii=False, sort_keys=True, indent=2) + "\n"


def sha_bytes(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def sha_path(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def ensure_f(path: Path, label: str) -> Path:
    value = path.resolve()
    if os.name == "nt":
        require(value.drive.upper() == "F:", f"{label} must be on F:, got {value}")
    return value


def read_json(path: Path) -> Any:
    try:
        return json.loads(path.read_text(encoding="utf-8-sig"))
    except (OSError, UnicodeDecodeError, json.JSONDecodeError) as exc:
        raise WeaponBundleError(f"cannot read JSON {path}: {exc}") from exc


def verify_hash_object(value: dict[str, Any], field: str) -> dict[str, Any]:
    copy = dict(value)
    expected = copy.pop(field, None)
    require(
        isinstance(expected, str) and expected == hashlib.sha256(canonical(copy)).hexdigest(),
        f"{field} drift",
    )
    return value


def normalize_internal(value: str) -> str:
    text = value.strip().replace("/", "\\").strip("\\")
    pieces = text.split("\\")
    require(
        bool(text)
        and ":" not in text
        and not text.startswith("\\")
        and all(piece not in ("", ".", "..") for piece in pieces),
        f"unsafe MPQ-internal path: {value!r}",
    )
    return "\\".join(pieces)


def creature_model_target(model_id: int) -> str:
    """Return the canonical DBC/MPQ base path for a transformed M2 model."""

    require(model_id > 0, f"unsafe synthetic model ID: {model_id}")
    return normalize_internal(MODEL_TARGET_ROOT + f"\\SCW_M{model_id}")


def stage_path(stage: Path, internal: str) -> Path:
    return stage.joinpath(*normalize_internal(internal).split("\\"))


def write_atomic(path: Path, data: bytes) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.with_name(path.name + ".tmp-" + uuid.uuid4().hex)
    temporary.write_bytes(data)
    os.replace(temporary, path)


def load_csv(path: Path) -> dict[int, dict[str, str]]:
    require(path.is_file(), f"candidate CSV is missing: {path}")
    rows: dict[int, dict[str, str]] = {}
    with path.open("r", encoding="utf-8-sig", newline="") as handle:
        for row in csv.DictReader(handle):
            try:
                appearance_id = int(row["appearanceId"])
            except (KeyError, TypeError, ValueError) as exc:
                raise WeaponBundleError("candidate CSV has invalid appearanceId") from exc
            require(appearance_id not in rows, f"candidate CSV duplicates {appearance_id}")
            rows[appearance_id] = dict(row)
    require(rows, "candidate CSV is empty")
    return rows


def validate_fixed_member(root: Path, fixed_files: dict[str, dict[str, Any]], relative: str) -> Path:
    relative = relative.replace("\\", "/")
    row = fixed_files.get(relative)
    require(row is not None, f"fixed evidence member is absent: {relative}")
    path = root / Path(relative)
    require(path.is_file(), f"fixed evidence member is missing: {relative}")
    require(
        path.stat().st_size == int(row["size"]) and sha_path(path) == str(row["sha256"]).lower(),
        f"fixed evidence member drift: {relative}",
    )
    return path


def asset_path(evidence_root: Path, asset: dict[str, Any]) -> Path:
    relative = str(asset.get("evidenceRelativePath", "")).replace("/", "\\")
    path = evidence_root.joinpath(*normalize_internal(relative).split("\\"))
    require(path.is_file(), f"shadow asset is missing: {relative}")
    require(
        path.stat().st_size == int(asset["bytes"]) and sha_path(path) == str(asset["sha256"]).lower(),
        f"shadow asset drift: {asset.get('assetId')}",
    )
    return path


def m2_geometry_key(model: dict[str, Any], skin: dict[str, Any]) -> str:
    return hashlib.sha256(
        canonical({"m2": str(model["sha256"]), "skin": str(skin["sha256"])})
    ).hexdigest()


def m2_texture_key(texture: dict[str, Any], hardcoded: list[dict[str, Any]]) -> str:
    return hashlib.sha256(
        canonical({"blp": sorted(str(value["sha256"]) for value in [texture, *hardcoded])})
    ).hexdigest()


def load_inputs(
    registry_path: Path,
    candidate_csv_path: Path,
    shadow_evidence_root: Path,
    fixed_input_root: Path,
    model_camera_overrides_path: Path,
) -> dict[str, Any]:
    registry_path = ensure_f(registry_path, "registry path")
    candidate_csv_path = ensure_f(candidate_csv_path, "candidate CSV path")
    shadow_evidence_root = ensure_f(shadow_evidence_root, "shadow evidence root")
    fixed_input_root = ensure_f(fixed_input_root, "fixed evidence root")
    model_camera_overrides_path = ensure_f(
        model_camera_overrides_path, "model camera override source"
    )

    registry = verify_hash_object(read_json(registry_path), "registryHash")
    require(registry.get("schemaVersion") == 1, "unsupported registry schema")
    entries = registry.get("entries")
    require(isinstance(entries, list) and entries, "registry has no entries")
    by_appearance: dict[int, dict[str, Any]] = {}
    for row in entries:
        appearance_id = int(row["appearanceId"])
        require(appearance_id not in by_appearance, f"registry duplicates appearance {appearance_id}")
        require(row.get("allocationStatus") in {"RESERVED", "ACTIVE"}, "registry has unsupported allocation")
        model_id = int(row["modelId"])
        display_id = int(row["syntheticDisplayId"])
        require(model_id > 0, f"invalid synthetic model ID: {model_id}")
        require(0 < display_id <= MAX_DISPLAY_ID, f"invalid synthetic display ID: {display_id}")
        require(DISPLAY_REQUEST_BASE + display_id <= 0xFFFFFFFF, "display request overflows uint32")
        by_appearance[appearance_id] = row

    summary_path = registry_path.with_name("shadow-summary.json")
    summary = verify_hash_object(read_json(summary_path), "summaryHash")
    require(summary.get("registryHash") == registry.get("registryHash"), "summary registry hash drift")
    candidate_bytes = candidate_csv_path.read_bytes()
    require(
        sha_bytes(candidate_bytes) == summary.get("candidateCsvSha256"),
        "candidate CSV hash differs from shadow summary",
    )
    candidates = load_csv(candidate_csv_path)
    require(set(by_appearance).issubset(candidates), "registry entry absent from candidate CSV")

    plan = verify_hash_object(read_json(shadow_evidence_root / "asset-plan.json"), "assetPlanHash")
    index = verify_hash_object(read_json(shadow_evidence_root / "asset-index.json"), "assetIndexHash")
    require(
        plan.get("inputHash") == registry.get("inputHash") == index.get("inputHash"),
        "registry/shadow evidence input hash drift",
    )
    require(index.get("assetPlanHash") == plan.get("assetPlanHash"), "asset index plan hash drift")
    require(summary.get("assetPlanHash") == plan.get("assetPlanHash"), "summary plan hash drift")
    require(summary.get("assetIndexHash") == index.get("assetIndexHash"), "summary index hash drift")
    plan_by_appearance = {int(row["appearanceId"]): row for row in plan.get("candidates", [])}
    require(len(plan_by_appearance) == len(plan.get("candidates", [])), "shadow plan duplicate appearance")
    assets = {str(row["assetId"]): row for row in index.get("assets", [])}
    require(len(assets) == len(index.get("assets", [])), "shadow index duplicate asset")

    fixed_manifest = read_json(fixed_input_root / "evidence-manifest.json")
    require(fixed_manifest.get("schemaVersion") == 1, "unsupported fixed evidence schema")
    fixed_files = {str(row["relativePath"]): row for row in fixed_manifest.get("files", [])}
    require(len(fixed_files) == len(fixed_manifest.get("files", [])), "fixed evidence duplicate relative path")
    model_dbc = validate_fixed_member(fixed_input_root, fixed_files, "dbc/CreatureModelData.dbc")
    display_dbc = validate_fixed_member(fixed_input_root, fixed_files, "dbc/CreatureDisplayInfo.dbc")
    reserve_config_path = validate_fixed_member(
        fixed_input_root, fixed_files, "weapon-resources/weapon-creature-build.json"
    )
    reserve_config = read_json(reserve_config_path)
    require(isinstance(reserve_config, list) and len(reserve_config) == 21, "reserved baseline count drift")
    reserve_by_ids = {
        (int(row["model_id"]), int(row["display_id"])): row for row in reserve_config
    }
    require(len(reserve_by_ids) == len(reserve_config), "reserved baseline duplicate ID pair")
    model_camera_overrides = load_model_camera_overrides(model_camera_overrides_path)
    for signature, override in model_camera_overrides["overrides"].items():
        matching = sorted(
            int(row["appearanceId"])
            for row in by_appearance.values()
            if row.get("modelSignature") == signature
        )
        require(matching == override["expectedAppearanceIds"],
                f"model camera override appearance scope drift: {signature}")

    return {
        "registry": registry,
        "entries": by_appearance,
        "summary": summary,
        "candidates": candidates,
        "plan": plan_by_appearance,
        "assetPlanHash": plan["assetPlanHash"],
        "assetIndexHash": index["assetIndexHash"],
        "assets": assets,
        "shadowRoot": shadow_evidence_root,
        "fixedRoot": fixed_input_root,
        "fixedFiles": fixed_files,
        "modelDbc": model_dbc,
        "displayDbc": display_dbc,
        "reserveByIds": reserve_by_ids,
        "registryPath": registry_path,
        "candidateCsvPath": candidate_csv_path,
        "modelCameraOverrides": model_camera_overrides["overrides"],
        "modelCameraOverridesPath": model_camera_overrides["path"],
        "modelCameraOverridesSha256": model_camera_overrides["sha256"],
    }


def active_entry_valid(entry: dict[str, Any], candidate: dict[str, str]) -> None:
    require(entry.get("allocationStatus") == "ACTIVE", "expected active entry")
    require(candidate.get("scope") == "PUBLIC", "active entry is not public")
    require(candidate.get("terminalStatus") == "READY", "active entry is not terminal READY")
    require(candidate.get("assetStatus") == "READY", "active entry raw assets are unavailable")
    require(candidate.get("allocationStatus") == "ACTIVE", "candidate allocation drift")
    require(int(candidate["modelId"]) == int(entry["modelId"]), "candidate model ID drift")
    require(
        int(candidate["syntheticDisplayId"]) == int(entry["syntheticDisplayId"]),
        "candidate display ID drift",
    )
    for field in ("geometryKey", "textureKey", "displayKey", "modelSignature"):
        require(candidate.get(field) == str(entry[field]), f"candidate {field} drift")


def choose_batch(inputs: dict[str, Any], batch: int) -> list[dict[str, Any]]:
    require(batch in (1, 2, 3), f"unsupported batch: {batch}")
    entries = inputs["entries"]
    candidates = inputs["candidates"]
    reserved = sorted(
        (row for row in entries.values() if row["allocationStatus"] == "RESERVED"),
        key=lambda row: int(row["appearanceId"]),
    )
    active = sorted(
        (row for row in entries.values() if row["allocationStatus"] == "ACTIVE"),
        key=lambda row: int(row["appearanceId"]),
    )
    require(len(reserved) == 21, "reserved baseline count drift")
    for row in active:
        active_entry_valid(row, candidates[int(row["appearanceId"])])
    if batch == 3:
        return [*reserved, *active]

    selected: dict[int, dict[str, Any]] = {int(row["appearanceId"]): row for row in reserved}
    groups: dict[str, list[dict[str, Any]]] = defaultdict(list)
    for row in active:
        groups[str(candidates[int(row["appearanceId"])]["cameraPreset"])].append(row)
    # Two actual new entries per family, deterministic by appearance ID.  The
    # route completion below additionally forces shield, held-offhand and the
    # ranged families into the first acceptance bundle.
    for family in sorted(groups):
        members = groups[family]
        require(len(members) >= 2, f"family has fewer than two active candidates: {family}")
        for row in members[:2]:
            selected[int(row["appearanceId"])] = row
    for route in ("SHIELD", "HELD_IN_OFFHAND", "RANGED"):
        route_members = [
            row for row in active
            if candidates[int(row["appearanceId"])].get("route") == route
        ]
        require(route_members, f"route absent from active registry: {route}")
        for row in route_members[:2]:
            selected[int(row["appearanceId"])] = row
    batch_one = sorted(selected.values(), key=lambda row: int(row["appearanceId"]))
    if batch == 1:
        return batch_one

    # Batch 2 retains batch 1 and expands to a deterministic 250-entry
    # stratified cut.  First cover geometry and texture sharing paths; then
    # use a stable round-robin over family/route strata.
    target = 250
    require(len(batch_one) <= target, "batch one exceeds batch two capacity")
    by_geometry: dict[int, list[dict[str, Any]]] = defaultdict(list)
    by_texture: dict[str, list[dict[str, Any]]] = defaultdict(list)
    for row in active:
        by_geometry[int(row["modelId"])].append(row)
        by_texture[str(row["textureKey"])].append(row)
    priorities: list[dict[str, Any]] = []
    for group in sorted(by_geometry.values(), key=lambda rows: (int(rows[0]["modelId"]), int(rows[0]["appearanceId"]))):
        if len({int(row["syntheticDisplayId"]) for row in group}) > 1:
            priorities.extend(sorted(group, key=lambda row: int(row["appearanceId"])))
    for group in sorted(by_texture.values(), key=lambda rows: (str(rows[0]["textureKey"]), int(rows[0]["appearanceId"]))):
        if len({int(row["modelId"]) for row in group}) > 1:
            priorities.extend(sorted(group, key=lambda row: int(row["appearanceId"])))
    for row in priorities:
        if len(selected) >= target:
            break
        selected.setdefault(int(row["appearanceId"]), row)
    strata: dict[tuple[str, str], list[dict[str, Any]]] = defaultdict(list)
    for row in active:
        candidate = candidates[int(row["appearanceId"])]
        strata[(candidate["route"], candidate["cameraPreset"])].append(row)
    ordered_strata = [
        sorted(rows, key=lambda row: int(row["appearanceId"]))
        for _key, rows in sorted(strata.items())
    ]
    position = 0
    while len(selected) < target:
        added = False
        for rows in ordered_strata:
            while position < len(rows) and int(rows[position]["appearanceId"]) in selected:
                position += 1
            if position < len(rows):
                selected[int(rows[position]["appearanceId"])] = rows[position]
                added = True
                if len(selected) >= target:
                    break
        if not added:
            break
        position += 1
    if len(selected) < target:
        for row in active:
            if len(selected) >= target:
                break
            selected.setdefault(int(row["appearanceId"]), row)
    require(len(selected) == target, "unable to populate batch two")
    return sorted(selected.values(), key=lambda row: int(row["appearanceId"]))


def inspect_bridge_contract() -> dict[str, Any]:
    header = (REPO_ROOT / "client-extension" / "SoloCam" / "src" / "DisplayInfoBridge.hpp").read_text(
        encoding="utf-8"
    )
    require("kDisplayInfoRequestBase = 0x6F000000" in header, "SoloCam request base drift")
    require("kMaximumDisplayInfoId = 0x00FFFFFF" in header, "SoloCam display max drift")
    return {
        "requestBase": DISPLAY_REQUEST_BASE,
        "maximumDisplayId": MAX_DISPLAY_ID,
        "maximumRequest": DISPLAY_REQUEST_BASE + MAX_DISPLAY_ID,
        "stockClientBehavior": "NO_SYNTHETIC_DBC_OR_SOLOCAM_REQUEST_MEANS_STANDARD_ITEM_PREVIEW_FALLBACK",
    }


def _add_file(
    files: dict[str, dict[str, Any]],
    internal: str,
    data: bytes,
    kind: str,
    source: dict[str, Any],
    reference: str,
) -> None:
    internal = normalize_internal(internal)
    digest = sha_bytes(data)
    key = internal.lower()
    previous = files.get(key)
    if previous is not None:
        require(previous["sha256"] == digest, f"output collision with different bytes: {internal}")
        previous["references"].append(reference)
        return
    files[key] = {
        "relativePath": internal.replace("\\", "/"),
        "kind": kind,
        "size": len(data),
        "sha256": digest,
        "source": source,
        "references": [reference],
        "data": data,
    }


def _shadow_asset(inputs: dict[str, Any], asset_id: str, expected_kind: str) -> tuple[dict[str, Any], bytes]:
    asset = inputs["assets"].get(asset_id)
    require(asset is not None, f"shadow asset is absent: {asset_id}")
    require(asset.get("parseError") is None, f"shadow asset parse failure: {asset_id}")
    require(asset.get("parse", {}).get("kind") == expected_kind, f"shadow asset kind mismatch: {asset_id}")
    source = asset_path(inputs["shadowRoot"], asset)
    return asset, source.read_bytes()


def _fixed_asset(inputs: dict[str, Any], relative: str) -> bytes:
    source = validate_fixed_member(inputs["fixedRoot"], inputs["fixedFiles"], relative)
    return source.read_bytes()


def _model_camera_override_provenance(override: dict[str, Any]) -> dict[str, Any]:
    """Keep the asset-stage projection auditable without embedding a file path."""
    return {
        "scope": override["scope"],
        "modelSignature": override["modelSignature"],
        "expectedAppearanceIds": list(override["expectedAppearanceIds"]),
        "expectedInputM2Sha256": override["expectedInputM2Sha256"],
        "expectedOutputM2Sha256": override["expectedOutputM2Sha256"],
        "cameraStrategy": override["cameraStrategy"],
        "reasonCode": override["reasonCode"],
        "workbenchExportSha256": override["workbenchExportSha256"],
    }


def _prepare_active_model(raw: bytes, asset: dict[str, Any]) -> tuple[bytes, str]:
    parsed = asset.get("parse", {})
    layout = parsed.get("cameraLayout")
    require(layout in {"CAMERALESS", "HAS_CAMERA"}, f"invalid M2 camera layout: {layout}")
    converted = raw
    if int(parsed.get("objectSkinDescriptorCount", 0)) > 0:
        converted = convert_object_skin(converted)
    mode = "PRESERVED_EXISTING_CAMERA" if layout == "HAS_CAMERA" else "APPENDED_STATIC_CAMERA"
    if layout == "CAMERALESS":
        converted = append_static_item_camera(converted)
    return converted, mode


def _append_dbc_rows(
    stage: Path,
    model_dbc: Path,
    display_dbc: Path,
    models: list[dict[str, Any]],
    displays: list[dict[str, Any]],
) -> dict[str, Any]:
    model_records, model_strings, model_fields, model_record_size = parse_wdbc(
        model_dbc.read_bytes(), {(26, 104), (28, 112)}
    )
    display_records, display_strings, display_fields, display_record_size = parse_wdbc(
        display_dbc.read_bytes(), {(16, 64)}
    )
    existing_models = {struct.unpack_from("<I", row, 0)[0] for row in model_records}
    existing_displays = {struct.unpack_from("<I", row, 0)[0] for row in display_records}
    require(len(existing_models) == len(model_records), "baseline CreatureModelData duplicate IDs")
    require(len(existing_displays) == len(display_records), "baseline CreatureDisplayInfo duplicate IDs")
    requested_models = {int(row["modelId"]) for row in models}
    requested_displays = {int(row["displayId"]) for row in displays}
    require(len(requested_models) == len(models), "duplicate requested CreatureModelData ID")
    require(len(requested_displays) == len(displays), "duplicate requested CreatureDisplayInfo ID")
    require(not (requested_models & existing_models), "CreatureModelData would overwrite baseline ID")
    require(not (requested_displays & existing_displays), "CreatureDisplayInfo would overwrite baseline ID")
    model_template = find_record(model_records, 1)
    display_template = find_record(display_records, 141)
    for row in sorted(models, key=lambda value: int(value["modelId"])):
        record = bytearray(model_template)
        struct.pack_into("<I", record, 0, int(row["modelId"]))
        struct.pack_into("<I", record, 8, add_string(model_strings, row["target"] + ".mdx"))
        struct.pack_into("<f", record, 16, 1.0)
        model_records.append(bytes(record))
    for row in sorted(displays, key=lambda value: int(value["displayId"])):
        display_id = int(row["displayId"])
        require(0 < display_id <= MAX_DISPLAY_ID, f"unsafe synthetic display ID: {display_id}")
        record = bytearray(display_template)
        struct.pack_into("<I", record, 0, display_id)
        struct.pack_into("<I", record, 4, int(row["modelId"]))
        struct.pack_into("<I", record, 8, 0)
        struct.pack_into("<I", record, 12, 0)
        struct.pack_into("<f", record, 16, 1.0)
        struct.pack_into("<B", record, 20, 255)
        struct.pack_into("<I", record, 24, add_string(display_strings, row["textureName"]))
        struct.pack_into("<I", record, 28, 0)
        struct.pack_into("<I", record, 32, 0)
        struct.pack_into("<I", record, 36, 0)
        display_records.append(bytes(record))
    model_output = stage / "DBFilesClient" / "CreatureModelData.dbc"
    display_output = stage / "DBFilesClient" / "CreatureDisplayInfo.dbc"
    write_wdbc(model_output, model_records, model_strings, model_fields, model_record_size)
    write_wdbc(display_output, display_records, display_strings, display_fields, display_record_size)
    return {
        "baseline": {
            "CreatureModelData": sha_path(model_dbc),
            "CreatureDisplayInfo": sha_path(display_dbc),
        },
        "appended": {"models": len(models), "displays": len(displays)},
        "records": {
            "CreatureModelData": len(model_records),
            "CreatureDisplayInfo": len(display_records),
        },
    }


def build_registry_assets(args: Any) -> dict[str, Any]:
    """Build stage files for one deterministic rollout batch.

    This function is intentionally imported by ``build_creature_weapon_assets``
    so the legacy 21-item CLI and the registry-backed workflow share the same
    WDBC writer and M2 conversion primitives.
    """

    stage = ensure_f(Path(args.stage), "weapon bundle stage")
    require(not stage.exists(), f"stage output must be absent for atomic build: {stage}")
    inputs = load_inputs(
        Path(args.registry),
        Path(args.candidates),
        Path(args.shadow_evidence_root),
        Path(args.fixed_input_root),
        Path(getattr(args, "model_camera_overrides", None) or DEFAULT_MODEL_CAMERA_OVERRIDES),
    )
    batch = int(args.batch)
    bundle_id = str(args.bundle_id)
    asset_pack_version = str(args.asset_pack_version)
    require(bundle_id and all(char.isalnum() or char in "-_." for char in bundle_id), "unsafe bundle ID")
    require(asset_pack_version and all(char.isalnum() or char in "-_." for char in asset_pack_version), "unsafe asset pack version")
    selected = choose_batch(inputs, batch)
    selected_ids = {int(row["appearanceId"]) for row in selected}
    require(len(selected_ids) == len(selected), "batch selection duplicates appearance")
    for signature, override in inputs["modelCameraOverrides"].items():
        selected_matching = sorted(
            int(row["appearanceId"])
            for row in selected
            if row.get("modelSignature") == signature
        )
        if selected_matching:
            require(selected_matching == override["expectedAppearanceIds"],
                    f"selected model camera override scope drift: {signature}")
    temporary = stage.with_name(stage.name + ".tmp-" + uuid.uuid4().hex)
    require(not temporary.exists(), f"temporary stage exists: {temporary}")
    temporary.mkdir(parents=True)
    files: dict[str, dict[str, Any]] = {}
    model_rows: dict[int, dict[str, Any]] = {}
    display_rows: dict[int, dict[str, Any]] = {}
    appearance_rows: list[dict[str, Any]] = []
    try:
        active_by_model: dict[int, list[dict[str, Any]]] = defaultdict(list)
        active_by_display: dict[int, list[dict[str, Any]]] = defaultdict(list)
        reserve_entries: list[dict[str, Any]] = []
        for entry in selected:
            appearance_id = int(entry["appearanceId"])
            candidate = inputs["candidates"][appearance_id]
            if entry["allocationStatus"] == "ACTIVE":
                active_entry_valid(entry, candidate)
                active_by_model[int(entry["modelId"])].append(entry)
                active_by_display[int(entry["syntheticDisplayId"])].append(entry)
            else:
                require(candidate.get("allocationStatus") == "RESERVED", "reserved candidate allocation drift")
                reserve_entries.append(entry)
            appearance_rows.append(
                {
                    "appearanceId": appearance_id,
                    "allocationStatus": entry["allocationStatus"],
                    "sourceItemId": int(entry["sourceItemId"]),
                    "modelId": int(entry["modelId"]),
                    "syntheticDisplayId": int(entry["syntheticDisplayId"]),
                    "modelSignature": str(entry.get("modelSignature", "")),
                    "route": candidate.get("route", ""),
                    "cameraPreset": candidate.get("cameraPreset", ""),
                    "terminalStatus": candidate.get("terminalStatus", ""),
                }
            )

        # Preserve the verified 21-item baseline byte-for-byte except a named,
        # hash-locked model correction.  The exception is deliberately model
        # scoped and generated from mesh vertices; it is not a per-appearance
        # SavedVariables tuning record.
        for entry in sorted(reserve_entries, key=lambda row: int(row["appearanceId"])):
            pair = (int(entry["modelId"]), int(entry["syntheticDisplayId"]))
            config = inputs["reserveByIds"].get(pair)
            require(config is not None, f"reserved baseline asset mapping missing: {pair}")
            target = normalize_internal(str(config["target"]))
            texture_name = str(config["texture_name"])
            m2_relative = "weapon-resources/stage/" + target.replace("\\", "/") + ".m2"
            skin_relative = "weapon-resources/stage/" + target.replace("\\", "/") + "00.skin"
            texture_relative = (
                "weapon-resources/stage/" + MODEL_TARGET_ROOT + "/" + texture_name + ".blp"
            )
            m2 = _fixed_asset(inputs, m2_relative)
            skin = _fixed_asset(inputs, skin_relative)
            texture = _fixed_asset(inputs, texture_relative)
            override = inputs["modelCameraOverrides"].get(str(entry.get("modelSignature", "")))
            camera_handling = "PRESERVED_VERIFIED_BASELINE"
            model_source: dict[str, Any] = {
                "fixedRelativePath": m2_relative,
                "sha256": sha_bytes(m2),
            }
            model_override_provenance = None
            if override is not None:
                require(override["cameraStrategy"] == CAMERA_STRATEGY,
                        f"unsupported model camera strategy: {entry['appearanceId']}")
                require(int(entry["appearanceId"]) in override["expectedAppearanceIds"],
                        f"reserved model camera override appearance drift: {entry['appearanceId']}")
                require(sha_bytes(m2) == override["expectedInputM2Sha256"],
                        f"reserved model camera override input hash drift: {entry['appearanceId']}")
                m2, _mesh_camera = replace_existing_item_camera_from_vertex_bounds(m2)
                require(sha_bytes(m2) == override["expectedOutputM2Sha256"],
                        f"reserved model camera override output hash drift: {entry['appearanceId']}")
                camera_handling = "CURATED_VERTEX_MESH_BOUNDS_CAMERA"
                model_override_provenance = _model_camera_override_provenance(override)
                model_source["modelCameraOverride"] = model_override_provenance
            _add_file(
                files, target + ".m2", m2, "M2",
                model_source,
                f"reserved:{entry['appearanceId']}:model",
            )
            _add_file(
                files, target + "00.skin", skin, "SKIN",
                {"fixedRelativePath": skin_relative, "sha256": sha_bytes(skin)},
                f"reserved:{entry['appearanceId']}:skin",
            )
            _add_file(
                files, MODEL_TARGET_ROOT + "/" + texture_name + ".blp", texture, "BLP",
                {"fixedRelativePath": texture_relative, "sha256": sha_bytes(texture)},
                f"reserved:{entry['appearanceId']}:display-texture",
            )
            model_rows[int(entry["modelId"])] = {
                "modelId": int(entry["modelId"]),
                "target": target,
                "sourceKind": "RESERVED_BASELINE",
                "cameraHandling": camera_handling,
            }
            if model_override_provenance is not None:
                model_rows[int(entry["modelId"])]["modelCameraOverride"] = model_override_provenance
            display_rows[int(entry["syntheticDisplayId"])] = {
                "displayId": int(entry["syntheticDisplayId"]),
                "modelId": int(entry["modelId"]),
                "textureName": texture_name,
                "sourceKind": "RESERVED_BASELINE",
            }

        # Transform unique active geometry once, then associate all of its
        # display rows.  Hard-coded texture dependencies retain their original
        # internal path because the M2 descriptor still points at that path.
        for model_id, group in sorted(active_by_model.items()):
            first = group[0]
            source_candidates = [inputs["plan"][int(row["appearanceId"])] for row in group]
            model_asset_id = str(source_candidates[0]["refs"]["model"])
            skin_asset_id = str(source_candidates[0]["refs"]["skin"])
            model_asset, raw_model = _shadow_asset(inputs, model_asset_id, "M2")
            skin_asset, raw_skin = _shadow_asset(inputs, skin_asset_id, "SKIN")
            expected_geometry = m2_geometry_key(model_asset, skin_asset)
            require(expected_geometry == str(first["geometryKey"]), f"geometry key drift for {model_id}")
            hardcoded_ids: set[str] = set()
            for source in source_candidates:
                require(source["refs"]["model"] == model_asset_id, f"model source drift for {model_id}")
                require(source["refs"]["skin"] == skin_asset_id, f"skin source drift for {model_id}")
                hardcoded_ids.update(str(value) for value in source.get("hardcodedTextureAssetIds", []))
            prepared, camera_mode = _prepare_active_model(raw_model, model_asset)
            target = creature_model_target(model_id)
            _add_file(
                files, target + ".m2", prepared, "M2",
                {
                    "assetId": model_asset_id,
                    "sourceSha256": model_asset["sha256"],
                    "converterVersion": CONVERTER_VERSION,
                    "cameraHandling": camera_mode,
                    "objectSkinDescriptorCount": model_asset["parse"].get("objectSkinDescriptorCount", 0),
                },
                f"active-model:{model_id}",
            )
            _add_file(
                files, target + "00.skin", raw_skin, "SKIN",
                {"assetId": skin_asset_id, "sourceSha256": skin_asset["sha256"]},
                f"active-model:{model_id}",
            )
            model_rows[model_id] = {
                "modelId": model_id,
                "target": target,
                "sourceKind": "SHADOW_TRANSFORMED",
                "cameraHandling": camera_mode,
            }
            for hardcoded_id in sorted(hardcoded_ids):
                hardcoded_asset, hardcoded_data = _shadow_asset(inputs, hardcoded_id, "BLP")
                _add_file(
                    files,
                    str(hardcoded_asset["internalPath"]),
                    hardcoded_data,
                    "BLP_HARDCODED_M2_REFERENCE",
                    {"assetId": hardcoded_id, "sourceSha256": hardcoded_asset["sha256"]},
                    f"active-model:{model_id}:hardcoded-texture",
                )

        for display_id, group in sorted(active_by_display.items()):
            first = group[0]
            source = inputs["plan"][int(first["appearanceId"])]
            texture_asset_id = str(source["refs"]["displayTexture"])
            hardcoded = [
                inputs["assets"][str(value)] for value in source.get("hardcodedTextureAssetIds", [])
            ]
            texture_asset, texture_data = _shadow_asset(inputs, texture_asset_id, "BLP")
            expected_texture = m2_texture_key(texture_asset, hardcoded)
            require(expected_texture == str(first["textureKey"]), f"texture key drift for {display_id}")
            expected_display = str(first["displayKey"])
            for entry in group:
                candidate = inputs["candidates"][int(entry["appearanceId"])]
                require(int(entry["modelId"]) == int(first["modelId"]), f"display model mismatch {display_id}")
                require(str(entry["displayKey"]) == expected_display, f"display key drift {display_id}")
                require(str(entry["textureKey"]) == str(first["textureKey"]), f"display texture key drift {display_id}")
                require(candidate.get("displayTexturePath") == str(texture_asset["internalPath"]), f"display source drift {display_id}")
            texture_name = f"SCW_D{display_id}"
            _add_file(
                files,
                MODEL_TARGET_ROOT + "/" + texture_name + ".blp",
                texture_data,
                "BLP_DISPLAY",
                {"assetId": texture_asset_id, "sourceSha256": texture_asset["sha256"]},
                f"active-display:{display_id}",
            )
            display_rows[display_id] = {
                "displayId": display_id,
                "modelId": int(first["modelId"]),
                "textureName": texture_name,
                "sourceKind": "SHADOW_TRANSFORMED",
            }

        require(
            {int(row["modelId"]) for row in selected} == set(model_rows),
            "selected model IDs did not close",
        )
        require(
            {int(row["syntheticDisplayId"]) for row in selected} == set(display_rows),
            "selected display IDs did not close",
        )
        dbc = _append_dbc_rows(
            temporary,
            inputs["modelDbc"],
            inputs["displayDbc"],
            list(model_rows.values()),
            list(display_rows.values()),
        )
        for relative, kind in (
            ("DBFilesClient/CreatureModelData.dbc", "DBC_CREATURE_MODEL_DATA"),
            ("DBFilesClient/CreatureDisplayInfo.dbc", "DBC_CREATURE_DISPLAY_INFO"),
        ):
            data = (temporary / Path(relative)).read_bytes()
            _add_file(
                files, relative, data, kind,
                {"baseline": dbc["baseline"], "converterVersion": CONVERTER_VERSION},
                "dbc-append-only",
            )

        # Materialize only declared outputs after all source validation and DBC
        # construction succeed.  A failure leaves a diagnostic temporary
        # directory, never a partial requested stage root.
        for row in sorted(files.values(), key=lambda value: value["relativePath"].lower()):
            path = stage_path(temporary, row["relativePath"])
            if not path.exists():
                write_atomic(path, row["data"])
            require(sha_path(path) == row["sha256"], f"stage write hash drift: {row['relativePath']}")

        manifest_files = []
        for row in sorted(files.values(), key=lambda value: value["relativePath"].lower()):
            manifest_files.append({key: row[key] for key in (
                "relativePath", "kind", "size", "sha256", "source", "references"
            )})
        selection_counts = Counter(row["allocationStatus"] for row in appearance_rows)
        projection_rows = []
        for row in sorted(appearance_rows, key=lambda value: value["appearanceId"]):
            model = model_rows[int(row["modelId"])]
            display = display_rows[int(row["syntheticDisplayId"])]
            projection_rows.append({
                **row,
                "modelPath": model["target"] + ".m2",
                "textureName": display["textureName"],
                "modelSourceKind": model["sourceKind"],
                "displaySourceKind": display["sourceKind"],
            })
        manifest: dict[str, Any] = {
            "schemaVersion": SCHEMA_VERSION,
            "kind": "SoloCollectionsWeaponBundleStage",
            "bundleId": bundle_id,
            "batch": batch,
            "assetPackVersion": asset_pack_version,
            "converter": {"version": CONVERTER_VERSION},
            "inputs": {
                "registrySha256": sha_path(inputs["registryPath"]),
                "registryHash": inputs["registry"]["registryHash"],
                "candidateCsvSha256": sha_bytes(inputs["candidateCsvPath"].read_bytes()),
                "shadowInputHash": inputs["registry"]["inputHash"],
                "shadowAssetPlanHash": inputs["assetPlanHash"],
                "shadowAssetIndexHash": inputs["assetIndexHash"],
                "modelCameraOverridesSha256": inputs["modelCameraOverridesSha256"],
            },
            "bridgeContract": inspect_bridge_contract(),
            "selection": {
                "appearanceCount": len(appearance_rows),
                "allocationCounts": dict(sorted(selection_counts.items())),
                "appearanceRows": sorted(appearance_rows, key=lambda row: row["appearanceId"]),
            },
            "registryProjection": {
                "models": sorted(model_rows.values(), key=lambda row: int(row["modelId"])),
                "displays": sorted(display_rows.values(), key=lambda row: int(row["displayId"])),
                "records": projection_rows,
            },
            "dedup": {
                "uniqueModels": len(model_rows),
                "uniqueDisplays": len(display_rows),
                "uniqueOutputFiles": len(manifest_files),
                "byKind": dict(sorted(Counter(row["kind"] for row in manifest_files).items())),
            },
            "dbc": dbc,
            "files": manifest_files,
        }
        manifest["bundleManifestHash"] = hashlib.sha256(canonical(manifest)).hexdigest()
        write_atomic(
            temporary / "weapon-bundle-manifest.json",
            pretty(manifest).encode("utf-8"),
        )
        os.replace(temporary, stage)
        return {
            "bundleId": bundle_id,
            "batch": batch,
            "stage": str(stage),
            "bundleManifestHash": manifest["bundleManifestHash"],
            "appearanceCount": len(appearance_rows),
            "modelCount": len(model_rows),
            "displayCount": len(display_rows),
            "fileCount": len(manifest_files),
        }
    except Exception:
        # Preserve the non-target temporary directory for diagnosis.  No
        # cleanup is attempted here: source evidence and forensic outputs are
        # intentionally append-only in this workflow.
        raise


def _verify_dbc_records(stage: Path, manifest: dict[str, Any]) -> None:
    model_records, _model_strings, _model_fields, _model_size = parse_wdbc(
        (stage / "DBFilesClient" / "CreatureModelData.dbc").read_bytes(), {(26, 104), (28, 112)}
    )
    display_records, _display_strings, _display_fields, _display_size = parse_wdbc(
        (stage / "DBFilesClient" / "CreatureDisplayInfo.dbc").read_bytes(), {(16, 64)}
    )
    model_ids = {struct.unpack_from("<I", row, 0)[0] for row in model_records}
    display_ids = {struct.unpack_from("<I", row, 0)[0] for row in display_records}
    for row in manifest["selection"]["appearanceRows"]:
        require(int(row["modelId"]) in model_ids, f"DBC lacks model ID {row['modelId']}")
        require(int(row["syntheticDisplayId"]) in display_ids, f"DBC lacks display ID {row['syntheticDisplayId']}")


def check_stage(stage: Path) -> dict[str, Any]:
    stage = ensure_f(stage, "weapon bundle stage")
    require(stage.is_dir(), f"weapon bundle stage is missing: {stage}")
    manifest_path = stage / "weapon-bundle-manifest.json"
    manifest = verify_hash_object(read_json(manifest_path), "bundleManifestHash")
    require(manifest.get("schemaVersion") == SCHEMA_VERSION, "unsupported bundle manifest schema")
    require(manifest.get("kind") == "SoloCollectionsWeaponBundleStage", "bundle manifest kind drift")
    bridge = manifest.get("bridgeContract", {})
    require(
        bridge.get("requestBase") == DISPLAY_REQUEST_BASE
        and bridge.get("maximumDisplayId") == MAX_DISPLAY_ID
        and bridge.get("maximumRequest") == DISPLAY_REQUEST_BASE + MAX_DISPLAY_ID,
        "SoloCam bridge contract drift",
    )
    seen: set[str] = set()
    output_paths: set[str] = set()
    manifest_files_by_path: dict[str, dict[str, Any]] = {}
    for row in manifest.get("files", []):
        relative = normalize_internal(str(row["relativePath"]))
        key = relative.lower()
        require(key not in seen, f"duplicate output file: {relative}")
        seen.add(key)
        path = stage_path(stage, relative)
        require(path.is_file(), f"manifest output is missing: {relative}")
        require(
            path.stat().st_size == int(row["size"]) and sha_path(path) == str(row["sha256"]),
            f"manifest output hash drift: {relative}",
        )
        output_paths.add(key)
        manifest_files_by_path[key] = row
    require(
        all((stage_path(stage, row["relativePath"]).is_file()) for row in manifest["files"]),
        "manifest closure failed",
    )
    _verify_dbc_records(stage, manifest)
    projection = manifest.get("registryProjection", {})
    records = projection.get("records", [])
    require(len(records) == int(manifest["selection"]["appearanceCount"]), "projection row count drift")
    for row in records:
        model_path = stage_path(stage, str(row["modelPath"]))
        require(model_path.is_file(), f"projection model is missing: {row['modelPath']}")
        require(0 < int(row["syntheticDisplayId"]) <= MAX_DISPLAY_ID, "projection display ID is unsafe")
    manifest_inputs = manifest.get("inputs") or {}
    override_source_hash = manifest_inputs.get("modelCameraOverridesSha256")
    if override_source_hash is not None:
        require(isinstance(override_source_hash, str) and len(override_source_hash) == 64,
                "model camera override source hash is invalid")
        configured_signatures: set[str] = set()
        for model in projection.get("models", []):
            override = model.get("modelCameraOverride")
            if override is None:
                continue
            require(model.get("cameraHandling") == "CURATED_VERTEX_MESH_BOUNDS_CAMERA",
                    "model camera override handling drift")
            require(override.get("scope") == "model"
                    and override.get("cameraStrategy") == CAMERA_STRATEGY,
                    "model camera override contract drift")
            signature = override.get("modelSignature")
            require(isinstance(signature, str) and signature not in configured_signatures,
                    "duplicate model camera override projection")
            configured_signatures.add(signature)
            expected_ids = sorted(int(value) for value in override.get("expectedAppearanceIds", []))
            actual_ids = sorted(
                int(row["appearanceId"])
                for row in records
                if row.get("modelSignature") == signature
            )
            require(actual_ids == expected_ids, "model camera override projection scope drift")
            m2_key = normalize_internal(str(model["target"]) + ".m2").lower()
            m2_file = manifest_files_by_path.get(m2_key)
            require(m2_file is not None
                    and m2_file.get("sha256") == override.get("expectedOutputM2Sha256"),
                    "model camera override output hash drift")
            source_override = (m2_file.get("source") or {}).get("modelCameraOverride")
            require(source_override == override, "model camera override file provenance drift")
    files_on_disk = {
        path.relative_to(stage).as_posix().replace("/", "\\").lower()
        for path in stage.rglob("*") if path.is_file() and path.name != "weapon-bundle-manifest.json"
    }
    require(files_on_disk == output_paths, "stage contains unmanifested or missing outputs")
    return {
        "stage": str(stage),
        "bundleId": manifest["bundleId"],
        "batch": manifest["batch"],
        "appearanceCount": manifest["selection"]["appearanceCount"],
        "fileCount": len(manifest["files"]),
        "bundleManifestHash": manifest["bundleManifestHash"],
    }


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest="command", required=True)
    build = commands.add_parser("build")
    build.add_argument("--registry", type=Path, required=True)
    build.add_argument("--candidates", type=Path, required=True)
    build.add_argument("--shadow-evidence-root", type=Path, required=True)
    build.add_argument("--fixed-input-root", type=Path, required=True)
    build.add_argument("--model-camera-overrides", type=Path, default=DEFAULT_MODEL_CAMERA_OVERRIDES)
    build.add_argument("--stage", type=Path, required=True)
    build.add_argument("--batch", choices=("1", "2", "3"), required=True)
    build.add_argument("--bundle-id", required=True)
    build.add_argument("--asset-pack-version", required=True)
    check = commands.add_parser("check")
    check.add_argument("--stage", type=Path, required=True)
    args = parser.parse_args(argv)
    try:
        if args.command == "build":
            result = build_registry_assets(args)
        else:
            result = check_stage(args.stage)
    except (WeaponBundleError, ModelCameraOverrideError, OSError, ValueError, struct.error) as exc:
        parser.error(str(exc))
    print(json.dumps(result, ensure_ascii=False, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
