#!/usr/bin/env python3
"""Validate and project the production standalone weapon presentation source.

The source is deliberately distinct from server appearance identity.  It is a
registry-backed client projection: changing a model, a pose, or a terminal
resource verdict changes presentation hashes, never the server mapping hash.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import re
from copy import deepcopy
from pathlib import Path
from typing import Any


class PresentationError(RuntimeError):
    pass


SHA256_RE = re.compile(r"^[a-f0-9]{64}$")
MODEL_SIGNATURE_RE = re.compile(r"^m2:[a-f0-9]{64}$")
DIRECT_DISPLAY_CAPABILITY = "DIRECT_DISPLAY_V1"
UNAVAILABLE_CAPABILITY = "UNAVAILABLE"
MODEL_CAMERA_STRATEGY = "VERTEX_MESH_BOUNDS_CAMERA"


def _require(condition: bool, message: str) -> None:
    if not condition:
        raise PresentationError(message)


def _read_json(path: Path) -> Any:
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except (OSError, UnicodeDecodeError, json.JSONDecodeError) as exc:
        raise PresentationError(f"cannot read JSON {path}: {exc}") from exc


def _norm(value: str) -> str:
    return value.replace("\\", "/").strip("/").lower()


def _valid_hash(value: Any) -> bool:
    return isinstance(value, str) and SHA256_RE.fullmatch(value) is not None


def _validate_pose(value: Any, item_id: int) -> None:
    _require(isinstance(value, dict), f"item {item_id} has no M2 camera pose")
    _require(all(isinstance(value.get(key), (int, float)) for key in ("yaw", "pitch", "roll", "distanceScale")),
             f"item {item_id} has incomplete M2 camera pose")
    target = value.get("target")
    _require(isinstance(target, dict) and all(isinstance(target.get(key), (int, float)) for key in ("x", "y", "z")),
             f"item {item_id} has incomplete M2 camera target")


def _validate_generated_model_camera_override(entry: dict[str, Any], item_id: int) -> None:
    override = entry.get("generatedModelCameraOverride")
    if override is None:
        return
    _require(isinstance(override, dict), f"item {item_id} generated model camera override is invalid")
    signature = str(entry.get("modelSignature", ""))
    _require(override.get("scope") == "model"
             and override.get("key") == signature
             and override.get("modelSignature") == signature,
             f"item {item_id} generated model camera override scope drift")
    _require(override.get("cameraStrategy") == MODEL_CAMERA_STRATEGY,
             f"item {item_id} generated model camera strategy drift")
    _require(isinstance(override.get("reasonCode"), str) and override["reasonCode"],
             f"item {item_id} generated model camera reason is missing")
    _require(_valid_hash(override.get("workbenchExportSha256")),
             f"item {item_id} generated model camera evidence hash is invalid")
    _validate_pose(override.get("pose"), item_id)


def _validate_source_contract(source: dict[str, Any]) -> None:
    _require(source.get("schemaVersion") == 2, "unsupported appearance presentation source schema")
    _require(isinstance(source.get("assetPackVersion"), str) and source["assetPackVersion"],
             "appearance presentation asset pack version is missing")
    _require(_valid_hash(source.get("baselineSourceSha256")), "baseline presentation hash is invalid")
    _require(int(source.get("publicAppearanceCount", 0)) > 0, "public presentation count is invalid")
    terminal_counts = source.get("terminalCounts")
    _require(isinstance(terminal_counts, dict)
             and all(isinstance(terminal_counts.get(key), int) and terminal_counts[key] >= 0
                     for key in ("READY", "UNAVAILABLE")),
             "terminal presentation counts are invalid")
    _require(sum(terminal_counts.values()) == int(source["publicAppearanceCount"]),
             "terminal presentation count does not close public denominator")
    _require(isinstance(source.get("retainedNonPublicBaselineCount"), int)
             and int(source["retainedNonPublicBaselineCount"]) >= 0,
             "retained non-public baseline count is invalid")

    runtime = source.get("runtimeProjection")
    _require(isinstance(runtime, dict) and all(_valid_hash(runtime.get(key)) for key in (
        "runtimeProjectionHash", "runtimeQuarantineHash", "summaryHash", "registryHash", "candidateCsvSha256",
    )), "runtime projection evidence is incomplete")
    bundle = source.get("assetBundle")
    _require(isinstance(bundle, dict) and all(isinstance(bundle.get(key), str) and bundle[key]
                                               for key in ("bundleId", "assetPackVersion")),
             "asset bundle identity is incomplete")
    _require(bundle.get("assetPackVersion") == source.get("assetPackVersion"),
             "asset bundle/version contract drift")
    _require(all(_valid_hash(bundle.get(key)) for key in (
        "bundleManifestHash", "registryHash", "candidateCsvSha256",
    )), "asset bundle hash contract is incomplete")
    _require(bundle["registryHash"] == runtime["registryHash"]
             and bundle["candidateCsvSha256"] == runtime["candidateCsvSha256"],
             "asset bundle/runtime registry contract drift")
    model_camera_overrides = source.get("modelCameraOverrides")
    _require(isinstance(model_camera_overrides, dict)
             and _valid_hash(model_camera_overrides.get("sourceSha256"))
             and isinstance(model_camera_overrides.get("count"), int)
             and model_camera_overrides["count"] >= 0,
             "model camera override source contract is incomplete")


def build_report(source_path: Path, appearance_sources_path: Path, evidence_root: Path | None = None) -> dict[str, Any]:
    """Return the canonical report consumed by ``generate_catalog.py``.

    ``evidence_root`` remains part of the CLI/API for compatibility.  The
    resource-bytes check is intentionally performed by ``weapon_presentations
    check`` because it requires the explicitly named runtime review, bundle
    stage, and fixed shadow evidence roots rather than a guessed local client.
    """

    del evidence_root
    source = _read_json(source_path)
    appearances = _read_json(appearance_sources_path)
    _validate_source_contract(source)
    entries = source.get("entries")
    _require(isinstance(entries, list) and entries, "appearance presentation source has no entries")

    groups = appearances.get("groups")
    _require(isinstance(groups, list), "appearance-sources.json has no groups")
    by_item: dict[int, dict[str, Any]] = {}
    by_appearance: dict[int, dict[str, Any]] = {}
    for group in groups:
        if group.get("lifecycle") != "active":
            continue
        appearance_id = int(group.get("appearanceId", 0))
        _require(appearance_id > 0 and appearance_id not in by_appearance,
                 f"duplicate active canonical appearance: {appearance_id}")
        by_appearance[appearance_id] = group
        for raw_item_id in group.get("sourceItemIds", []):
            item_id = int(raw_item_id)
            _require(item_id > 0 and item_id not in by_item, f"duplicate active source item: {item_id}")
            by_item[item_id] = group

    seen_items: set[int] = set()
    seen_appearances: set[int] = set()
    display_assets: dict[int, tuple[str, tuple[tuple[str, str], ...]]] = {}
    public_ready = 0
    public_unavailable = 0
    retained_nonpublic = 0
    report_entries: list[dict[str, Any]] = []
    for entry in entries:
        item_id = int(entry.get("sourceItemId", 0))
        appearance_id = int(entry.get("appearanceId", 0))
        _require(item_id > 0 and item_id not in seen_items, f"duplicate or invalid source item: {item_id}")
        _require(appearance_id > 0 and appearance_id not in seen_appearances,
                 f"duplicate or invalid canonical appearance: {appearance_id}")
        seen_items.add(item_id)
        seen_appearances.add(appearance_id)
        canonical = by_item.get(item_id)
        _require(canonical is not None and int(canonical.get("appearanceId", 0)) == appearance_id,
                 f"item {item_id} canonical appearance drift")
        _require(int(entry.get("nativeDisplayId", 0)) == int(canonical.get("displayId", 0)),
                 f"item {item_id} native display drift")
        _require(entry.get("assetPackVersion") == source["assetPackVersion"],
                 f"item {item_id} asset pack mismatch")
        _require(entry.get("weaponType") and entry.get("weaponCategory"),
                 f"item {item_id} has incomplete weapon classification")

        status = entry.get("presentationStatus")
        render_mode = entry.get("renderMode")
        capability = entry.get("presentationCapability")
        if status in {"READY", "RETAINED_BASELINE"}:
            _require(render_mode == "STANDALONE" and capability == DIRECT_DISPLAY_CAPABILITY,
                     f"item {item_id} standalone capability drift")
            _require(isinstance(entry.get("cameraTuningKey"), str) and entry["cameraTuningKey"],
                     f"item {item_id} standalone camera family is missing")
            display_id = int(entry.get("syntheticDisplayId", 0))
            _require(0 < display_id <= 0x00FFFFFF, f"item {item_id} synthetic display is unsafe")
            model_path = str(entry.get("modelPath", ""))
            _require(model_path.lower().endswith(".m2"), f"item {item_id} model path is invalid")
            _require(isinstance(entry.get("modelScale"), (int, float)) and float(entry["modelScale"]) > 0,
                     f"item {item_id} has invalid model scale")
            _require(MODEL_SIGNATURE_RE.fullmatch(str(entry.get("modelSignature", ""))) is not None,
                     f"item {item_id} has invalid model signature")
            _validate_pose(entry.get("m2Camera"), item_id)
            _validate_pose(entry.get("autoCamera"), item_id)
            _validate_generated_model_camera_override(entry, item_id)
            hashes = entry.get("assetHashes")
            _require(isinstance(hashes, dict) and all(_valid_hash(hashes.get(key)) for key in ("m2", "skin", "texture")),
                     f"item {item_id} asset hash contract is incomplete")
            projection = (_norm(model_path), tuple(sorted((key, str(value).lower()) for key, value in hashes.items())))
            existing = display_assets.get(display_id)
            if existing is None:
                display_assets[display_id] = projection
            else:
                _require(existing == projection, f"synthetic display asset drift: {display_id}")
            if status == "READY":
                public_ready += 1
            else:
                _require(entry.get("presentationAudience") == "NONPUBLIC_BASELINE",
                         f"item {item_id} retained baseline audience is invalid")
                retained_nonpublic += 1
        elif status == "UNAVAILABLE":
            _require(render_mode == "UNAVAILABLE" and capability == UNAVAILABLE_CAPABILITY,
                     f"item {item_id} unavailable capability drift")
            _require(isinstance(entry.get("presentationReasonCode"), str)
                     and entry["presentationReasonCode"],
                     f"item {item_id} unavailable reason is missing")
            _require(not entry.get("syntheticDisplayId") and not entry.get("modelPath"),
                     f"item {item_id} unavailable record exposes direct-display data")
            public_unavailable += 1
        else:
            raise PresentationError(f"item {item_id} has unsupported presentation status: {status}")

        report_entries.append({
            **deepcopy(entry),
            "sourceAlias": f"item:{item_id}",
            "collectionKey": canonical["collectionKey"],
        })

    _require(public_ready == int(source["terminalCounts"]["READY"]), "READY terminal count drift")
    _require(public_unavailable == int(source["terminalCounts"]["UNAVAILABLE"]), "UNAVAILABLE terminal count drift")
    _require(public_ready + public_unavailable == int(source["publicAppearanceCount"]),
             "public presentation denominator drift")
    _require(retained_nonpublic == int(source["retainedNonPublicBaselineCount"]),
             "retained baseline count drift")
    return {
        "schemaVersion": 3,
        "assetPackVersion": source["assetPackVersion"],
        "baselineSourceSha256": source["baselineSourceSha256"],
        "publicAppearanceCount": source["publicAppearanceCount"],
        "retainedNonPublicBaselineCount": source["retainedNonPublicBaselineCount"],
        "terminalCounts": deepcopy(source["terminalCounts"]),
        "runtimeProjection": deepcopy(source["runtimeProjection"]),
        "assetBundle": deepcopy(source["assetBundle"]),
        "modelCameraOverrides": deepcopy(source["modelCameraOverrides"]),
        "presentationCount": len(report_entries),
        "entries": sorted(report_entries, key=lambda row: int(row["appearanceId"])),
    }


def _render(report: dict[str, Any]) -> str:
    return json.dumps(report, ensure_ascii=False, sort_keys=True, indent=2) + "\n"


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source", type=Path, required=True)
    parser.add_argument("--appearance-sources", type=Path, required=True)
    parser.add_argument("--evidence-root", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args(argv)
    try:
        rendered = _render(build_report(args.source, args.appearance_sources, args.evidence_root))
        if args.check:
            _require(args.output.is_file() and args.output.read_text(encoding="utf-8") == rendered,
                     f"generated output is stale: {args.output}")
        else:
            args.output.parent.mkdir(parents=True, exist_ok=True)
            args.output.write_text(rendered, encoding="utf-8", newline="\n")
    except PresentationError as exc:
        parser.error(str(exc))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
