#!/usr/bin/env python3
"""Validate body-profile workbench JSONL into review-only candidates.

Exports never alter ``camera_profiles.json`` or its override source directly.
They must first match the exact generated profile version/hash and become a
deterministic review artifact for a human approval step.
"""

from __future__ import annotations

import argparse
import json
import math
import re
from pathlib import Path
from typing import Any


SCHEMA_VERSION = 1
EXPORT_KIND = "SoloCollectionsBodyCameraTuningExport"
PROFILE_KEY_RE = re.compile(r"^[a-z_]+:[a-z]+:[A-Z_]+$")
HEX_HASH_RE = re.compile(r"^[a-f0-9]{64}$")
DELTA_LIMITS = {
    "verticalOffsetDelta": (-2.0, 2.0),
    "horizontalOffsetDelta": (-2.0, 2.0),
    "distanceScaleMultiplier": (0.5, 2.0),
    "minimumDistanceDelta": (-2.0, 2.0),
    "yawOffsetDelta": (-math.pi, math.pi),
}
RACE_TOKENS = {
    "human": "Human", "orc": "Orc", "dwarf": "Dwarf", "night_elf": "NightElf",
    "undead": "Scourge", "tauren": "Tauren", "gnome": "Gnome", "troll": "Troll",
    "blood_elf": "BloodElf", "draenei": "Draenei",
}


class BodyCameraTuningImportError(RuntimeError):
    """Raised for malformed or mismatched body-profile exports."""


def _require(condition: bool, message: str) -> None:
    if not condition:
        raise BodyCameraTuningImportError(message)


def _read_json(path: Path) -> Any:
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except (OSError, UnicodeDecodeError, json.JSONDecodeError) as exc:
        raise BodyCameraTuningImportError(f"cannot read JSON {path}: {exc}") from exc


def _nonempty_string(value: Any, label: str) -> str:
    _require(isinstance(value, str) and value.strip(), f"invalid {label}")
    return value


def _integer(value: Any, label: str) -> int:
    _require(isinstance(value, int) and not isinstance(value, bool) and value > 0, f"invalid {label}")
    return value


def _finite_in_range(value: Any, minimum: float, maximum: float, label: str) -> float:
    _require(isinstance(value, (int, float)) and not isinstance(value, bool), f"invalid {label}")
    number = float(value)
    _require(math.isfinite(number), f"non-finite {label}")
    _require(minimum <= number <= maximum, f"out-of-range {label}")
    return number


def profile_key(profile: dict[str, Any]) -> str:
    return f"{profile['raceKey']}:{str(profile['sex']).lower()}:{profile['slot']}"


def normalize_delta(delta: Any) -> dict[str, float]:
    _require(isinstance(delta, dict), "delta must be an object")
    return {
        name: _finite_in_range(delta.get(name), minimum, maximum, f"delta.{name}")
        for name, (minimum, maximum) in DELTA_LIMITS.items()
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
            raise BodyCameraTuningImportError(f"line {line_number}: invalid JSON: {exc.msg}") from exc
        _require(isinstance(parsed, dict), f"line {line_number}: export row must be an object")
        if parsed.get("kind") == EXPORT_KIND:
            _require(header is None, f"line {line_number}: duplicate export header")
            header = parsed
        else:
            _require(header is not None, f"line {line_number}: record appears before export header")
            records.append(parsed)
    _require(header is not None, "missing body camera tuning export header")
    _require(records, "body camera tuning export contains no records")
    return header, records


def validate_export(
    header: dict[str, Any],
    records: list[dict[str, Any]],
    camera_profiles: dict[str, Any],
) -> dict[str, Any]:
    _require(header.get("kind") == EXPORT_KIND, "unexpected body camera tuning export kind")
    _require(header.get("schemaVersion") == SCHEMA_VERSION, "unsupported body camera tuning export schema")
    metadata_version = _nonempty_string(header.get("metadataVersion"), "metadataVersion")
    asset_pack_version = _nonempty_string(header.get("assetPackVersion"), "assetPackVersion")
    _require(camera_profiles.get("schemaVersion") == 1, "unsupported camera profiles schema")
    profile_version = camera_profiles.get("profileVersion")
    profile_hash = camera_profiles.get("profileHash")
    _require(isinstance(profile_version, int) and profile_version > 0, "invalid generated profile version")
    _require(isinstance(profile_hash, str) and HEX_HASH_RE.fullmatch(profile_hash) is not None,
             "invalid generated profile hash")
    _require(header.get("cameraProfileVersion") == profile_version, "camera profile version mismatch")
    _require(header.get("cameraProfileHash") == profile_hash, "camera profile hash mismatch")

    profiles = camera_profiles.get("profiles")
    _require(isinstance(profiles, list) and len(profiles) == 180, "camera profile matrix is incomplete")
    by_key = {profile_key(row): row for row in profiles}
    _require(len(by_key) == len(profiles), "camera profile matrix has duplicate profile keys")
    candidates: list[dict[str, Any]] = []
    seen_keys: set[str] = set()
    for row in records:
        _require(row.get("scope") == "bodyProfile", "invalid body profile scope")
        key = row.get("profileKey")
        _require(isinstance(key, str) and PROFILE_KEY_RE.fullmatch(key) is not None, "invalid profileKey")
        profile = by_key.get(key)
        _require(profile is not None, f"unknown profileKey: {key}")
        _require(key not in seen_keys, f"duplicate or conflicting body profile target: {key}")
        seen_keys.add(key)
        sentinel = _integer(row.get("sentinel"), "sentinel")
        _require(sentinel == int(profile["sentinel"]), f"profile {key} sentinel mismatch")
        _require(row.get("raceToken") == RACE_TOKENS.get(profile["raceKey"]),
                 f"profile {key} race token mismatch")
        _require(row.get("clientAssetProfile") == profile["cameraProfile"],
                 f"profile {key} client asset profile mismatch")
        _require(row.get("sex") == profile["sex"], f"profile {key} sex mismatch")
        _require(row.get("slot") == profile["slot"], f"profile {key} slot mismatch")
        _require(row.get("cameraProfileVersion") == profile_version, "record camera profile version mismatch")
        _require(row.get("cameraProfileHash") == profile_hash, "record camera profile hash mismatch")
        _require(row.get("metadataVersion") == metadata_version, "record metadata version mismatch")
        _require(row.get("assetPackVersion") == asset_pack_version, "record asset pack version mismatch")
        candidates.append({
            "profileKey": key,
            "sentinel": sentinel,
            "raceKey": profile["raceKey"],
            "cameraProfile": profile["cameraProfile"],
            "sex": profile["sex"],
            "slot": profile["slot"],
            "cameraProfileVersion": profile_version,
            "cameraProfileHash": profile_hash,
            "delta": normalize_delta(row.get("delta")),
        })

    return {
        "schemaVersion": 1,
        "kind": "SoloCollectionsBodyCameraTuningReviewCandidates",
        "metadataVersion": metadata_version,
        "assetPackVersion": asset_pack_version,
        "cameraProfileVersion": profile_version,
        "cameraProfileHash": profile_hash,
        "candidates": sorted(candidates, key=lambda row: (row["profileKey"], row["sentinel"])),
    }


def render_candidates(export_path: Path, camera_profiles_path: Path) -> str:
    header, records = parse_export(export_path.read_text(encoding="utf-8"))
    candidates = validate_export(header, records, _read_json(camera_profiles_path))
    return json.dumps(candidates, ensure_ascii=False, sort_keys=True, indent=2) + "\n"


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--input", type=Path, required=True, help="JSONL copied from the body-profile workbench")
    parser.add_argument("--camera-profiles", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args(argv)
    try:
        rendered = render_candidates(args.input, args.camera_profiles)
        if args.check:
            _require(args.output.is_file() and args.output.read_text(encoding="utf-8") == rendered,
                     f"generated output is stale: {args.output}")
        else:
            args.output.parent.mkdir(parents=True, exist_ok=True)
            args.output.write_text(rendered, encoding="utf-8", newline="\n")
    except (OSError, BodyCameraTuningImportError) as exc:
        parser.error(str(exc))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
