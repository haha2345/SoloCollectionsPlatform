#!/usr/bin/env python3
"""Validate and project verified standalone weapon presentations."""

from __future__ import annotations

import argparse
import csv
import hashlib
import json
from pathlib import Path
from typing import Any


class PresentationError(RuntimeError):
    pass


def _require(condition: bool, message: str) -> None:
    if not condition:
        raise PresentationError(message)


def _read_json(path: Path) -> Any:
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except (OSError, UnicodeDecodeError, json.JSONDecodeError) as exc:
        raise PresentationError(f"cannot read JSON {path}: {exc}") from exc


def _sha256(path: Path) -> str:
    digest = hashlib.sha256()
    try:
        with path.open("rb") as handle:
            for chunk in iter(lambda: handle.read(1024 * 1024), b""):
                digest.update(chunk)
    except OSError as exc:
        raise PresentationError(f"cannot hash {path}: {exc}") from exc
    return digest.hexdigest()


def _norm(value: str) -> str:
    return value.replace("\\", "/").strip("/").lower()


def build_report(source_path: Path, appearance_sources_path: Path, evidence_root: Path) -> dict[str, Any]:
    source = _read_json(source_path)
    appearances = _read_json(appearance_sources_path)
    _require(source.get("schemaVersion") == 1, "unsupported appearance presentation schema")
    entries = source.get("entries")
    _require(isinstance(entries, list) and len(entries) == 21, "exactly 21 verified presentations are required")
    _require(source.get("assetPackVersion") == "wotlk-3.3.5a-local-1", "unexpected asset pack version")

    weapon_root = evidence_root / "weapon-resources"
    manifest_path = weapon_root / "weapon-creature-build.json"
    verification_path = weapon_root / "weapon-model-verification.csv"
    _require(_sha256(manifest_path) == source.get("weaponManifestSha256"), "weapon manifest hash drift")
    _require(_sha256(verification_path) == source.get("verificationSha256"), "weapon verification hash drift")
    manifest = _read_json(manifest_path)
    _require(isinstance(manifest, list) and len(manifest) == 21, "weapon manifest must contain 21 entries")

    try:
        with verification_path.open("r", encoding="utf-8-sig", newline="") as handle:
            verification = list(csv.DictReader(handle))
    except OSError as exc:
        raise PresentationError(f"cannot read verification CSV: {exc}") from exc
    _require(len(verification) >= 63, "weapon verification does not cover M2, skin and texture assets")
    verified_paths: dict[str, dict[str, str]] = {}
    for row in verification:
        _require(row.get("Match", "").lower() == "true", f"weapon asset mismatch: {row.get('Path')}")
        _require(row.get("StageLength") == row.get("VerifyLength"), f"weapon asset length mismatch: {row.get('Path')}")
        _require(row.get("StageSHA256", "").lower() == row.get("VerifySHA256", "").lower(),
                 f"weapon asset hash mismatch: {row.get('Path')}")
        verified_paths[_norm(row.get("Path", ""))] = row

    groups = appearances.get("groups")
    _require(isinstance(groups, list), "appearance-sources.json has no groups")
    by_item: dict[int, list[dict[str, Any]]] = {}
    for group in groups:
        for item_id in group.get("sourceItemIds", []):
            by_item.setdefault(int(item_id), []).append(group)
    manifest_by_item = {int(row["item_id"]): row for row in manifest}
    _require(len(manifest_by_item) == 21, "weapon manifest item IDs are not unique")

    seen_items: set[int] = set()
    seen_appearances: set[int] = set()
    seen_displays: set[int] = set()
    report_entries: list[dict[str, Any]] = []
    for entry in entries:
        item_id = int(entry.get("sourceItemId", 0))
        appearance_id = int(entry.get("appearanceId", 0))
        display_id = int(entry.get("syntheticDisplayId", 0))
        _require(item_id > 0 and item_id not in seen_items, f"duplicate or invalid source item: {item_id}")
        _require(appearance_id > 0 and appearance_id not in seen_appearances,
                 f"duplicate or invalid canonical appearance: {appearance_id}")
        _require(display_id not in seen_displays, f"duplicate synthetic display ID: {display_id}")
        seen_items.add(item_id)
        seen_appearances.add(appearance_id)
        seen_displays.add(display_id)

        matches = by_item.get(item_id, [])
        _require(len(matches) == 1, f"item {item_id} maps to {len(matches)} canonical appearances")
        _require(int(matches[0].get("appearanceId", 0)) == appearance_id,
                 f"item {item_id} canonical appearance drift")
        manifest_entry = manifest_by_item.get(item_id)
        _require(manifest_entry is not None, f"item {item_id} is missing from weapon manifest")
        _require(int(manifest_entry.get("display_id", 0)) == display_id,
                 f"item {item_id} synthetic display drift")
        _require(entry.get("assetPackVersion") == source["assetPackVersion"],
                 f"item {item_id} asset pack mismatch")
        _require(entry.get("presentationStatus") == "verified", f"item {item_id} is not verified")
        _require(isinstance(entry.get("modelScale"), (int, float)) and float(entry["modelScale"]) > 0,
                 f"item {item_id} has invalid model scale")
        _require(entry.get("weaponType") and entry.get("weaponCategory") and entry.get("cameraTuningKey"),
                 f"item {item_id} has incomplete weapon classification")
        camera = entry.get("m2Camera")
        _require(isinstance(camera, dict) and all(key in camera for key in ("yaw", "pitch", "roll", "distanceScale", "target")),
                 f"item {item_id} has incomplete M2 camera")
        _require(isinstance(camera["target"], dict) and all(key in camera["target"] for key in ("x", "y", "z")),
                 f"item {item_id} has incomplete M2 camera target")

        target = _norm(str(manifest_entry["target"]))
        expected_model = target + ".m2"
        expected_skin = target + "00.skin"
        expected_texture = target + ".blp"
        _require(_norm(str(entry.get("modelPath", ""))) == expected_model,
                 f"item {item_id} model path does not match manifest")
        for expected in (expected_model, expected_skin, expected_texture):
            _require(expected in verified_paths, f"item {item_id} missing verified asset: {expected}")
        report_entries.append({
            **entry,
            "sourceAlias": f"item:{item_id}",
            "collectionKey": matches[0]["collectionKey"],
            "nativeDisplayId": int(matches[0]["displayId"]),
            "assetHashes": {
                "m2": verified_paths[expected_model]["StageSHA256"].lower(),
                "skin": verified_paths[expected_skin]["StageSHA256"].lower(),
                "texture": verified_paths[expected_texture]["StageSHA256"].lower(),
            },
        })

    _require(seen_displays == set(range(40000, 40021)), "synthetic display IDs must be exactly 40000..40020")
    _require(set(manifest_by_item) == seen_items, "source and weapon manifest item sets differ")
    return {
        "schemaVersion": 1,
        "assetPackVersion": source["assetPackVersion"],
        "weaponManifestSha256": source["weaponManifestSha256"],
        "verificationSha256": source["verificationSha256"],
        "presentationCount": len(report_entries),
        "entries": sorted(report_entries, key=lambda row: int(row["syntheticDisplayId"])),
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
