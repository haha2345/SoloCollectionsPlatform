#!/usr/bin/env python3
"""Render review diffs and explicitly merge approved body-camera deltas.

The normal path is read-only: candidates become a base-vs-proposed report.
Writing canonical override source requires both an explicit approve list and
``--write-approved-overrides``; this tool never applies an unreviewed export.
"""

from __future__ import annotations

import argparse
import copy
import json
import math
from pathlib import Path
from typing import Any

from body_camera_tuning_import import (
    BodyCameraTuningImportError,
    DELTA_LIMITS,
    profile_key,
)


class BodyCameraReviewError(RuntimeError):
    """Raised when candidates cannot safely enter the review/merge path."""


def _require(condition: bool, message: str) -> None:
    if not condition:
        raise BodyCameraReviewError(message)


def _read_json(path: Path) -> Any:
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except (OSError, UnicodeDecodeError, json.JSONDecodeError) as exc:
        raise BodyCameraReviewError(f"cannot read JSON {path}: {exc}") from exc


def _render(value: Any) -> str:
    return json.dumps(value, ensure_ascii=False, sort_keys=True, indent=2) + "\n"


def _profiles_by_key(camera_profiles: dict[str, Any]) -> dict[str, dict[str, Any]]:
    profiles = camera_profiles.get("profiles")
    _require(isinstance(profiles, list) and len(profiles) == 180, "camera profile matrix is incomplete")
    result = {profile_key(row): row for row in profiles}
    _require(len(result) == len(profiles), "camera profile matrix has duplicate profile keys")
    return result


def validate_candidates(candidates: dict[str, Any], camera_profiles: dict[str, Any]) -> list[dict[str, Any]]:
    _require(candidates.get("kind") == "SoloCollectionsBodyCameraTuningReviewCandidates",
             "unexpected review candidate kind")
    _require(candidates.get("schemaVersion") == 1, "unsupported review candidate schema")
    _require(candidates.get("cameraProfileVersion") == camera_profiles.get("profileVersion"),
             "candidate camera profile version mismatch")
    _require(candidates.get("cameraProfileHash") == camera_profiles.get("profileHash"),
             "candidate camera profile hash mismatch")
    rows = candidates.get("candidates")
    _require(isinstance(rows, list) and rows, "review candidate file has no rows")
    profiles = _profiles_by_key(camera_profiles)
    seen: set[str] = set()
    validated: list[dict[str, Any]] = []
    for row in rows:
        _require(isinstance(row, dict), "review candidate row must be an object")
        key = row.get("profileKey")
        _require(isinstance(key, str) and key in profiles, "candidate profile key is unknown")
        _require(key not in seen, "duplicate review candidate profile key")
        seen.add(key)
        profile = profiles[key]
        _require(row.get("sentinel") == profile["sentinel"], "candidate sentinel mismatch")
        _require(row.get("cameraProfileVersion") == camera_profiles["profileVersion"],
                 "candidate profile version mismatch")
        _require(row.get("cameraProfileHash") == camera_profiles["profileHash"],
                 "candidate profile hash mismatch")
        delta = row.get("delta")
        _require(isinstance(delta, dict), "candidate delta must be an object")
        for name, (minimum, maximum) in DELTA_LIMITS.items():
            value = delta.get(name)
            _require(isinstance(value, (int, float)) and not isinstance(value, bool)
                     and math.isfinite(float(value)) and minimum <= float(value) <= maximum,
                     f"candidate delta is invalid: {name}")
        validated.append({"profile": profile, "candidate": row})
    return validated


def build_review_report(candidates: dict[str, Any], camera_profiles: dict[str, Any]) -> dict[str, Any]:
    rows = []
    for entry in validate_candidates(candidates, camera_profiles):
        profile = entry["profile"]
        candidate = entry["candidate"]
        delta = candidate["delta"]
        proposed = {
            "verticalOffset": profile["verticalOffset"] + delta["verticalOffsetDelta"],
            "horizontalOffset": profile["horizontalOffset"] + delta["horizontalOffsetDelta"],
            "distanceScale": profile["distanceScale"] * delta["distanceScaleMultiplier"],
            "minimumDistance": profile["minimumDistance"] + delta["minimumDistanceDelta"],
            "yawOffset": profile["yawOffset"] + delta["yawOffsetDelta"],
        }
        rows.append({
            "profileKey": candidate["profileKey"],
            "sentinel": candidate["sentinel"],
            "raceKey": profile["raceKey"],
            "sex": profile["sex"],
            "slot": profile["slot"],
            "base": {
                name: profile[name]
                for name in ("verticalOffset", "horizontalOffset", "distanceScale", "minimumDistance", "yawOffset")
            },
            "delta": delta,
            "proposed": proposed,
            "magnitude": {
                "maxAbsoluteOffset": max(
                    abs(delta["verticalOffsetDelta"]),
                    abs(delta["horizontalOffsetDelta"]),
                    abs(delta["minimumDistanceDelta"]),
                ),
                "distanceScaleMultiplier": delta["distanceScaleMultiplier"],
                "absoluteYawOffset": abs(delta["yawOffsetDelta"]),
            },
        })
    return {
        "schemaVersion": 1,
        "kind": "SoloCollectionsBodyCameraTuningReview",
        "metadataVersion": candidates["metadataVersion"],
        "assetPackVersion": candidates["assetPackVersion"],
        "cameraProfileVersion": candidates["cameraProfileVersion"],
        "cameraProfileHash": candidates["cameraProfileHash"],
        "affectedProfileKeys": [row["profileKey"] for row in sorted(rows, key=lambda row: row["profileKey"])],
        "rows": sorted(rows, key=lambda row: row["profileKey"]),
    }


def merge_approved_deltas(
    candidates: dict[str, Any],
    camera_profiles: dict[str, Any],
    overrides: dict[str, Any],
    approved_profile_keys: set[str],
) -> dict[str, Any]:
    _require(approved_profile_keys, "at least one approved profile key is required")
    validated = validate_candidates(candidates, camera_profiles)
    candidate_by_key = {entry["candidate"]["profileKey"]: entry["candidate"] for entry in validated}
    unknown = approved_profile_keys - set(candidate_by_key)
    if unknown:
        raise BodyCameraReviewError(
            f"approved profile key has no reviewed candidate: {sorted(unknown)[0]}"
        )
    output = copy.deepcopy(overrides)
    _require(output.get("schemaVersion") == 1, "unsupported camera override schema")
    existing = output.get("approvedBodyDeltas", [])
    _require(isinstance(existing, list), "approved body deltas must be a list")
    retained = [row for row in existing if row.get("profileKey") not in approved_profile_keys]
    for profile_key_value in sorted(approved_profile_keys):
        candidate = candidate_by_key[profile_key_value]
        retained.append({
            "profileKey": profile_key_value,
            "sentinel": candidate["sentinel"],
            "cameraProfileVersion": candidate["cameraProfileVersion"],
            "cameraProfileHash": candidate["cameraProfileHash"],
            **candidate["delta"],
        })
    output["approvedBodyDeltas"] = sorted(
        retained,
        key=lambda row: str(row.get("profileKey", "")),
    )
    return output


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--candidates", type=Path, required=True)
    parser.add_argument("--camera-profiles", type=Path, required=True)
    parser.add_argument("--review-output", type=Path, required=True)
    parser.add_argument("--check", action="store_true")
    parser.add_argument("--approved-profile", action="append", default=[])
    parser.add_argument("--overrides", type=Path)
    parser.add_argument("--write-approved-overrides", action="store_true")
    args = parser.parse_args(argv)
    try:
        candidates = _read_json(args.candidates)
        camera_profiles = _read_json(args.camera_profiles)
        review = _render(build_review_report(candidates, camera_profiles))
        if args.check:
            _require(args.review_output.is_file() and args.review_output.read_text(encoding="utf-8") == review,
                     f"generated output is stale: {args.review_output}")
        else:
            args.review_output.parent.mkdir(parents=True, exist_ok=True)
            args.review_output.write_text(review, encoding="utf-8", newline="\n")

        if args.write_approved_overrides:
            _require(not args.check, "--check cannot write approved overrides")
            _require(args.overrides is not None, "--write-approved-overrides requires --overrides")
            approved = set(args.approved_profile)
            merged = merge_approved_deltas(candidates, camera_profiles, _read_json(args.overrides), approved)
            args.overrides.write_text(_render(merged), encoding="utf-8", newline="\n")
        elif args.approved_profile:
            raise BodyCameraReviewError("--approved-profile requires --write-approved-overrides")
    except (OSError, BodyCameraTuningImportError, BodyCameraReviewError) as exc:
        parser.error(str(exc))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
