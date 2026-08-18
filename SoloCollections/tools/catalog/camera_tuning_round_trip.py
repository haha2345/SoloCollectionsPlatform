#!/usr/bin/env python3
"""Prove a reviewed weapon-camera export can be staged and regenerated safely.

The normal importer is intentionally review-only.  This companion tool is an
explicit approval *simulation*: it applies the validated candidate only to a
temporary source copy on a caller-provided scratch volume, regenerates the
catalog model, and emits a deterministic audit record.  It never writes the
canonical source or a deployed AddOn.
"""

from __future__ import annotations

import argparse
import copy
import hashlib
import json
import shutil
import sys
import tempfile
from pathlib import Path
from typing import Any


TOOL_DIR = Path(__file__).resolve().parent
if str(TOOL_DIR) not in sys.path:
    sys.path.insert(0, str(TOOL_DIR))

import appearance_presentations
import camera_tuning_import
import generate_catalog


class CameraTuningRoundTripError(RuntimeError):
    """Raised when a reviewed candidate cannot map safely to canonical poses."""


def _require(condition: bool, message: str) -> None:
    if not condition:
        raise CameraTuningRoundTripError(message)


def _read_json(path: Path) -> Any:
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except (OSError, UnicodeDecodeError, json.JSONDecodeError) as exc:
        raise CameraTuningRoundTripError(f"cannot read JSON {path}: {exc}") from exc


def _sha256_bytes(value: bytes) -> str:
    return hashlib.sha256(value).hexdigest()


def _sha256_file(path: Path) -> str:
    try:
        return _sha256_bytes(path.read_bytes())
    except OSError as exc:
        raise CameraTuningRoundTripError(f"cannot hash {path}: {exc}") from exc


def _canonical_json(value: Any) -> str:
    return json.dumps(value, ensure_ascii=False, sort_keys=True, indent=2) + "\n"


def _source_entries(source: dict[str, Any]) -> dict[int, dict[str, Any]]:
    entries = source.get("entries")
    _require(isinstance(entries, list) and entries, "camera presentation source has no entries")
    by_appearance: dict[int, dict[str, Any]] = {}
    for entry in entries:
        _require(isinstance(entry, dict), "camera presentation source entry is invalid")
        appearance_id = entry.get("appearanceId")
        _require(isinstance(appearance_id, int) and appearance_id > 0,
                 "camera presentation source has invalid appearance ID")
        _require(appearance_id not in by_appearance,
                 f"camera presentation source has duplicate appearance ID: {appearance_id}")
        by_appearance[appearance_id] = entry
    return by_appearance


def _report_entries(report: dict[str, Any]) -> dict[int, dict[str, Any]]:
    entries = report.get("entries")
    _require(isinstance(entries, list) and entries, "appearance presentation report has no entries")
    by_appearance: dict[int, dict[str, Any]] = {}
    for entry in entries:
        _require(isinstance(entry, dict), "appearance presentation report entry is invalid")
        appearance_id = entry.get("appearanceId")
        _require(isinstance(appearance_id, int) and appearance_id > 0,
                 "appearance presentation report has invalid appearance ID")
        _require(appearance_id not in by_appearance,
                 f"appearance presentation report has duplicate appearance ID: {appearance_id}")
        by_appearance[appearance_id] = entry
    return by_appearance


def resolve_candidate_targets(
    source: dict[str, Any], report: dict[str, Any], candidates: list[dict[str, Any]]
) -> list[tuple[dict[str, Any], list[int]]]:
    """Resolve each approved scope into concrete canonical appearance rows.

    A source camera is a single baseline, so two candidate scopes may not touch
    the same row in one approval batch.  Rejecting that ambiguity keeps the
    reviewer decision explicit rather than silently choosing an override order.
    """

    source_by_appearance = _source_entries(source)
    report_by_appearance = _report_entries(report)
    _require(set(source_by_appearance) == set(report_by_appearance),
             "source and appearance presentation report have different appearance IDs")

    claimed: set[int] = set()
    resolved: list[tuple[dict[str, Any], list[int]]] = []
    for candidate in candidates:
        _require(isinstance(candidate, dict), "review candidate is invalid")
        scope = candidate.get("scope")
        key = candidate.get("key")
        appearance_id = candidate.get("appearanceId")
        _require(isinstance(appearance_id, int) and appearance_id in report_by_appearance,
                 "review candidate has unknown appearance ID")
        _require(isinstance(key, str) and key, "review candidate has invalid key")
        if scope == "appearance":
            target_ids = [appearance_id]
        elif scope == "model":
            target_ids = sorted(
                row_id for row_id, row in report_by_appearance.items()
                if row.get("modelSignature") == key
            )
        elif scope == "weaponFamily":
            target_ids = sorted(
                row_id for row_id, row in report_by_appearance.items()
                if row.get("cameraTuningKey") == key
            )
        else:
            raise CameraTuningRoundTripError(f"review candidate has unsupported scope: {scope}")
        _require(target_ids, f"review candidate scope resolves to no appearances: {scope}/{key}")
        _require(appearance_id in target_ids,
                 f"review candidate identity is outside its resolved scope: {scope}/{key}")
        _require(not (claimed & set(target_ids)),
                 "review candidates overlap canonical pose targets; approve them separately")
        claimed.update(target_ids)
        resolved.append((candidate, target_ids))
    return resolved


def apply_candidates_to_source(
    source: dict[str, Any], report: dict[str, Any], candidates: list[dict[str, Any]]
) -> tuple[dict[str, Any], list[dict[str, Any]]]:
    """Return a staged source copy and a compact approval decision log."""

    staged = copy.deepcopy(source)
    staged_by_appearance = _source_entries(staged)
    decisions: list[dict[str, Any]] = []
    for candidate, target_ids in resolve_candidate_targets(source, report, candidates):
        pose = candidate.get("pose")
        # The importer already validates bounds; retain this defensive check so
        # direct API callers cannot bypass the review contract.
        normalized_pose = camera_tuning_import.normalize_pose(pose)
        before = {
            str(row_id): {
                "m2Camera": copy.deepcopy(staged_by_appearance[row_id]["m2Camera"]),
                "autoCamera": copy.deepcopy(staged_by_appearance[row_id]["autoCamera"]),
            }
            for row_id in target_ids
        }
        for row_id in target_ids:
            staged_by_appearance[row_id]["m2Camera"] = copy.deepcopy(normalized_pose)
            # The generated AddOn catalog reads ``autoCamera``.  Keep the
            # canonical M2 baseline mirrored so an approved workbench review
            # cannot leave the source internally inconsistent or rebuild to
            # the old pose.
            staged_by_appearance[row_id]["autoCamera"] = copy.deepcopy(normalized_pose)
        decisions.append({
            "scope": candidate["scope"],
            "key": candidate["key"],
            "candidateAppearanceId": candidate["appearanceId"],
            "affectedAppearanceIds": target_ids,
            "before": before,
            "approvedPose": normalized_pose,
        })
    return staged, decisions


def _generated_poses(model: dict[str, Any], appearance_ids: list[int]) -> dict[str, dict[str, Any]]:
    wanted = set(appearance_ids)
    poses: dict[str, dict[str, Any]] = {}
    for collection in model.get("collections", []):
        if collection.get("typeKey") != "appearance":
            continue
        appearance_id = collection.get("collectionId")
        if appearance_id not in wanted:
            continue
        pose = collection.get("autoCamera")
        _require(isinstance(pose, dict), f"generated catalog lacks autoCamera for appearance {appearance_id}")
        poses[str(appearance_id)] = copy.deepcopy(pose)
    _require(set(map(int, poses)) == wanted,
             "generated catalog has different approved appearance IDs")
    return poses


def build_round_trip(
    export_path: Path,
    appearance_report_path: Path,
    source_path: Path,
    appearance_sources_path: Path,
    evidence_root: Path,
    scratch_root: Path,
    generated_catalog_output: Path | None = None,
) -> dict[str, Any]:
    """Import, explicitly stage, and regenerate one reviewed export batch."""

    try:
        header, records = camera_tuning_import.parse_export(export_path.read_text(encoding="utf-8"))
        report = _read_json(appearance_report_path)
        review = camera_tuning_import.validate_export(header, records, report)
        source = _read_json(source_path)
        staged_source, decisions = apply_candidates_to_source(source, report, review["candidates"])
    except (OSError, camera_tuning_import.CameraTuningImportError) as exc:
        raise CameraTuningRoundTripError(str(exc)) from exc

    source_hash_before = _sha256_file(source_path)
    scratch_root.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix="solo-collections-camera-round-trip-", dir=scratch_root) as raw_temp:
        temp_root = Path(raw_temp)
        catalog_root = source_path.parent.parent
        _require((catalog_root / "ids.json").is_file(),
                 "camera presentation source must live under a catalog root with ids.json")
        staged_catalog_root = temp_root / catalog_root.name
        staged_source_root = staged_catalog_root / source_path.parent.name
        try:
            shutil.copytree(catalog_root, staged_catalog_root)
            staged_source_path = staged_source_root / source_path.name
            staged_source_path.write_text(_canonical_json(staged_source), encoding="utf-8", newline="\n")
            regenerated_report = appearance_presentations.build_report(
                staged_source_path, appearance_sources_path, evidence_root
            )
            (staged_catalog_root / "generated" / "appearance-presentation-report.json").write_text(
                _canonical_json(regenerated_report), encoding="utf-8", newline="\n"
            )
            regenerated_model = generate_catalog.build_model(staged_source_root)
            # Rendering the AddOn projection also incorporates the stable
            # legacy bridge from the real repository root.  render_outputs is
            # pure: it returns text and does not write any of these paths.
            render_root = source_path.parents[2]
            rendered = generate_catalog.render_outputs(
                regenerated_model, render_root, render_root / "module-stub"
            )
            generated_catalog = rendered[render_root / "addon/SoloCollections/Data/Generated/Catalog.lua"]
        except (OSError, appearance_presentations.PresentationError, generate_catalog.CatalogError) as exc:
            raise CameraTuningRoundTripError(str(exc)) from exc

    source_hash_after = _sha256_file(source_path)
    _require(source_hash_before == source_hash_after,
             "canonical appearance presentation source changed during staged round-trip")
    affected_ids = sorted({row_id for decision in decisions for row_id in decision["affectedAppearanceIds"]})
    generated_poses = _generated_poses(regenerated_model, affected_ids)
    for decision in decisions:
        for appearance_id in decision["affectedAppearanceIds"]:
            _require(generated_poses[str(appearance_id)] == decision["approvedPose"],
                     f"generated auto camera differs from approved pose for appearance {appearance_id}")

    if generated_catalog_output is not None:
        generated_catalog_output.parent.mkdir(parents=True, exist_ok=True)
        generated_catalog_output.write_text(generated_catalog, encoding="utf-8", newline="\n")

    return {
        "schemaVersion": 1,
        "kind": "SoloCollectionsCameraTuningRoundTrip",
        "sourceUnchanged": True,
        "exportSha256": _sha256_file(export_path),
        "sourceSha256": source_hash_before,
        "candidateSha256": _sha256_bytes(_canonical_json(review).encode("utf-8")),
        "sourceAppearancePresentationHash": camera_tuning_import._presentation_hash(report["entries"]),
        "regeneratedAppearancePresentationHash": camera_tuning_import._presentation_hash(regenerated_report["entries"]),
        "generatedCatalogSha256": _sha256_bytes(generated_catalog.encode("utf-8")),
        "generatedCatalogMappingHash": regenerated_model["mappingHash"],
        "decisions": decisions,
        "generatedAutoCamera": generated_poses,
    }


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--input", type=Path, required=True, help="JSONL copied from the in-game workbench")
    parser.add_argument("--appearance-report", type=Path, required=True)
    parser.add_argument("--source", type=Path, required=True)
    parser.add_argument("--appearance-sources", type=Path, required=True)
    parser.add_argument("--evidence-root", type=Path, required=True)
    parser.add_argument("--scratch-root", type=Path, required=True,
                        help="explicit F/D workspace scratch directory; never defaults to a system temp path")
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--generated-catalog-output", type=Path,
                        help="optional F/D staging target for the regenerated AddOn Catalog.lua")
    parser.add_argument("--approve", action="store_true",
                        help="required acknowledgement that candidates are staged for this audit only")
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args(argv)
    if not args.approve:
        parser.error("--approve is required; imports stay review-only unless explicitly staged for this audit")
    try:
        rendered = _canonical_json(build_round_trip(
            args.input,
            args.appearance_report,
            args.source,
            args.appearance_sources,
            args.evidence_root,
            args.scratch_root,
            args.generated_catalog_output,
        ))
        if args.check:
            _require(args.output.is_file() and args.output.read_text(encoding="utf-8") == rendered,
                     f"generated output is stale: {args.output}")
        else:
            args.output.parent.mkdir(parents=True, exist_ok=True)
            args.output.write_text(rendered, encoding="utf-8", newline="\n")
    except (OSError, CameraTuningRoundTripError) as exc:
        parser.error(str(exc))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
