#!/usr/bin/env python3
"""Validate camera-workbench JSONL exports into review-only candidates.

The tool deliberately does not modify ``appearance_presentations.json`` or a
camera override source.  A player export first becomes a deterministic review
artifact; a separate reviewed change is required to alter canonical poses.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import math
import re
from pathlib import Path
from typing import Any


SCHEMA_VERSION = 2
EXPORT_KIND = "SoloCollectionsCameraTuningExport"
MODEL_SIGNATURE_RE = re.compile(r"^m2:[a-f0-9]{64}$")
FAMILY_KEY_RE = re.compile(r"^[A-Z][A-Z0-9_]*$")
APPEARANCE_KEY_RE = re.compile(r"^appearance:\d+$")
POSE_LIMITS = {
    "yaw": (-math.pi, math.pi),
    "pitch": (-1.20, 1.20),
    "roll": (-math.pi, math.pi),
    "distanceScale": (0.25, 4.00),
    "target": (-4.00, 4.00),
}


class CameraTuningImportError(RuntimeError):
    """Raised for malformed or mismatched exported tuning records."""


def _require(condition: bool, message: str) -> None:
    if not condition:
        raise CameraTuningImportError(message)


def _read_json(path: Path) -> Any:
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except (OSError, UnicodeDecodeError, json.JSONDecodeError) as exc:
        raise CameraTuningImportError(f"cannot read JSON {path}: {exc}") from exc


def _presentation_hash(entries: list[dict[str, Any]]) -> str:
    encoded = json.dumps(entries, ensure_ascii=False, sort_keys=True, separators=(",", ":")).encode("utf-8")
    return hashlib.sha256(encoded).hexdigest()


def _integer(value: Any, label: str) -> int:
    _require(isinstance(value, int) and not isinstance(value, bool) and value > 0, f"invalid {label}")
    return value


def _nonempty_string(value: Any, label: str) -> str:
    _require(isinstance(value, str) and value.strip(), f"invalid {label}")
    return value


def _finite_in_range(value: Any, minimum: float, maximum: float, label: str) -> float:
    _require(isinstance(value, (int, float)) and not isinstance(value, bool), f"invalid {label}")
    number = float(value)
    _require(math.isfinite(number), f"non-finite {label}")
    _require(minimum <= number <= maximum, f"out-of-range {label}")
    return number


def normalize_pose(pose: Any) -> dict[str, Any]:
    _require(isinstance(pose, dict), "pose must be an object")
    target = pose.get("target")
    _require(isinstance(target, dict), "pose.target must be an object")
    return {
        "yaw": _finite_in_range(pose.get("yaw"), *POSE_LIMITS["yaw"], "pose.yaw"),
        "pitch": _finite_in_range(pose.get("pitch"), *POSE_LIMITS["pitch"], "pose.pitch"),
        "roll": _finite_in_range(pose.get("roll"), *POSE_LIMITS["roll"], "pose.roll"),
        "distanceScale": _finite_in_range(
            pose.get("distanceScale"), *POSE_LIMITS["distanceScale"], "pose.distanceScale"
        ),
        "target": {
            "x": _finite_in_range(target.get("x"), *POSE_LIMITS["target"], "pose.target.x"),
            "y": _finite_in_range(target.get("y"), *POSE_LIMITS["target"], "pose.target.y"),
            "z": _finite_in_range(target.get("z"), *POSE_LIMITS["target"], "pose.target.z"),
        },
    }


def parse_export(text: str) -> tuple[dict[str, Any], list[dict[str, Any]]]:
    header: dict[str, Any] | None = None
    records: list[dict[str, Any]] = []
    for line_number, raw_line in enumerate(text.splitlines(), start=1):
        line = raw_line.strip()
        if not line:
            continue
        try:
            parsed = json.loads(line)
        except json.JSONDecodeError as exc:
            raise CameraTuningImportError(f"line {line_number}: invalid JSON: {exc.msg}") from exc
        _require(isinstance(parsed, dict), f"line {line_number}: export row must be an object")
        if parsed.get("kind") == EXPORT_KIND:
            _require(header is None, f"line {line_number}: duplicate export header")
            header = parsed
        else:
            _require(header is not None, f"line {line_number}: record appears before export header")
            records.append(parsed)
    _require(header is not None, "missing camera tuning export header")
    _require(records, "camera tuning export contains no records")
    return header, records


def _validated_scope_key(scope: Any, key: Any, appearance_id: int, model_signature: str, family: str) -> tuple[str, str]:
    _require(scope in {"appearance", "model", "weaponFamily"}, "unknown camera tuning scope")
    _require(isinstance(key, str), "camera tuning key must be a string")
    if scope == "appearance":
        _require(APPEARANCE_KEY_RE.fullmatch(key) is not None, "invalid appearance scope key")
        _require(key == f"appearance:{appearance_id}", "appearance scope key does not match appearance ID")
    elif scope == "model":
        _require(MODEL_SIGNATURE_RE.fullmatch(key) is not None, "invalid model scope key")
        _require(key == model_signature, "model scope key does not match model signature")
    else:
        _require(FAMILY_KEY_RE.fullmatch(key) is not None, "invalid weapon family scope key")
        _require(key == family, "weapon family scope key does not match presentation")
    return scope, key


def validate_export(header: dict[str, Any], records: list[dict[str, Any]], report: dict[str, Any]) -> dict[str, Any]:
    _require(header.get("kind") == EXPORT_KIND, "unexpected camera tuning export kind")
    _require(header.get("schemaVersion") == SCHEMA_VERSION, "unsupported camera tuning export schema")
    metadata_version = _nonempty_string(header.get("metadataVersion"), "metadataVersion")
    _require(report.get("schemaVersion") == 2, "unsupported appearance presentation report schema")
    entries = report.get("entries")
    _require(isinstance(entries, list) and entries, "appearance presentation report has no entries")
    expected_hash = _presentation_hash(entries)
    _require(header.get("assetPackVersion") == report.get("assetPackVersion"), "asset pack version mismatch")
    _require(header.get("appearancePresentationHash") == expected_hash, "appearance presentation hash mismatch")

    by_appearance = {int(entry["appearanceId"]): entry for entry in entries}
    _require(len(by_appearance) == len(entries), "appearance presentation report has duplicate IDs")
    candidates: list[dict[str, Any]] = []
    seen_scope_keys: set[tuple[str, str]] = set()
    for row in records:
        appearance_id = _integer(row.get("appearanceId"), "appearanceId")
        source = by_appearance.get(appearance_id)
        _require(source is not None, f"unknown appearance ID: {appearance_id}")
        _require(source.get("presentationStatus") == "verified", f"appearance {appearance_id} is not verified")
        source_item_id = _integer(row.get("sourceItemId"), "sourceItemId")
        native_display_id = _integer(row.get("nativeDisplayId"), "nativeDisplayId")
        synthetic_display_id = _integer(row.get("syntheticDisplayId"), "syntheticDisplayId")
        model_signature = row.get("modelSignature")
        family = row.get("weaponFamily")
        _require(isinstance(model_signature, str) and MODEL_SIGNATURE_RE.fullmatch(model_signature), "invalid modelSignature")
        _require(isinstance(family, str) and FAMILY_KEY_RE.fullmatch(family), "invalid weaponFamily")
        _require(source_item_id == int(source["sourceItemId"]), f"appearance {appearance_id} source item mismatch")
        _require(native_display_id == int(source["nativeDisplayId"]), f"appearance {appearance_id} native display mismatch")
        _require(synthetic_display_id == int(source["syntheticDisplayId"]), f"appearance {appearance_id} synthetic display mismatch")
        _require(model_signature == source.get("modelSignature"), f"appearance {appearance_id} model signature mismatch")
        _require(family == source.get("cameraTuningKey"), f"appearance {appearance_id} weapon family mismatch")
        weapon_type = _nonempty_string(row.get("weaponType"), "weaponType")
        slot = _nonempty_string(row.get("slot"), "slot")
        _require(weapon_type == source.get("weaponType"), f"appearance {appearance_id} weapon type mismatch")
        _require(slot in {"MAINHAND", "OFFHAND"}, "invalid weapon slot")
        _require(row.get("metadataVersion") == metadata_version, "record metadata version mismatch")
        _require(row.get("assetPackVersion") == header.get("assetPackVersion"), "record asset pack version mismatch")
        _require(
            row.get("appearancePresentationHash") == header.get("appearancePresentationHash"),
            "record appearance presentation hash mismatch",
        )
        scope, key = _validated_scope_key(row.get("scope"), row.get("key"), appearance_id, model_signature, family)
        identity = (scope, key)
        _require(identity not in seen_scope_keys, f"duplicate or conflicting tuning target: {scope}/{key}")
        seen_scope_keys.add(identity)
        candidates.append({
            "scope": scope,
            "key": key,
            "appearanceId": appearance_id,
            "sourceItemId": source_item_id,
            "nativeDisplayId": native_display_id,
            "syntheticDisplayId": synthetic_display_id,
            "modelSignature": model_signature,
            "weaponFamily": family,
            "weaponType": weapon_type,
            "slot": slot,
            "pose": normalize_pose(row.get("pose")),
        })

    return {
        "schemaVersion": 1,
        "kind": "SoloCollectionsCameraTuningReviewCandidates",
        "metadataVersion": metadata_version,
        "assetPackVersion": report["assetPackVersion"],
        "appearancePresentationHash": expected_hash,
        "candidates": sorted(candidates, key=lambda row: (row["scope"], row["key"], row["appearanceId"])),
    }


def render_candidates(export_path: Path, report_path: Path) -> str:
    header, records = parse_export(export_path.read_text(encoding="utf-8"))
    candidates = validate_export(header, records, _read_json(report_path))
    return json.dumps(candidates, ensure_ascii=False, sort_keys=True, indent=2) + "\n"


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--input", type=Path, required=True, help="JSONL copied from the in-game workbench")
    parser.add_argument("--appearance-report", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args(argv)
    try:
        rendered = render_candidates(args.input, args.appearance_report)
        if args.check:
            _require(args.output.is_file() and args.output.read_text(encoding="utf-8") == rendered,
                     f"generated output is stale: {args.output}")
        else:
            args.output.parent.mkdir(parents=True, exist_ok=True)
            args.output.write_text(rendered, encoding="utf-8", newline="\n")
    except (OSError, CameraTuningImportError) as exc:
        parser.error(str(exc))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
