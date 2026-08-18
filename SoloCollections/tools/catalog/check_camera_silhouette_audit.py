#!/usr/bin/env python3
"""Verify a completed 540-row three-silhouette character-camera audit.

This verifier deliberately accepts only the temporary runtime audit's evidence
shape.  It does not update a production catalog or its 180-row visual review;
the result is an auditable acceptance artifact for the three armor-weight
passes that sit behind every canonical body-camera profile.
"""

from __future__ import annotations

import argparse
import json
from pathlib import Path
from typing import Any

from export_camera_runtime_matrix import (
    CameraRuntimeMatrixError,
    _extract_lua_table,
    _parse_lua_object,
    _profile_key,
    _read_json,
    _saved_scalar,
    _top_level_objects,
)


SILHOUETTES = ("SMALL", "NORMAL", "LARGE")
EXPECTED_PAGE_COUNT = 60
EXPECTED_ROW_COUNT = 540


def _require(condition: bool, message: str) -> None:
    if not condition:
        raise CameraRuntimeMatrixError(message)


def _read_saved(path: Path) -> str:
    try:
        return path.read_text(encoding="utf-8")
    except (OSError, UnicodeDecodeError) as exc:
        raise CameraRuntimeMatrixError(f"cannot read SavedVariables {path}: {exc}") from exc


def check_silhouette_audit(
    saved_path: Path,
    canonical_path: Path,
    screenshot_directory: Path | None = None,
) -> dict[str, Any]:
    """Validate one completed small/normal/large runtime matrix."""
    saved_text = _read_saved(saved_path)
    canonical = _read_json(canonical_path)
    _require(_saved_scalar(saved_text, "completed") is True, "silhouette audit did not complete")
    _require(_saved_scalar(saved_text, "ready") is True, "silhouette audit did not report ready")
    _require(_saved_scalar(saved_text, "reloadObserved") is True,
             "silhouette audit reload persistence was not observed")
    _require(_saved_scalar(saved_text, "mode") == "silhouettes", "audit was not run in silhouettes mode")
    _require(_saved_scalar(saved_text, "rowCount") == EXPECTED_ROW_COUNT,
             f"silhouette audit row count is not {EXPECTED_ROW_COUNT}")
    _require(_saved_scalar(saved_text, "pageCount") == EXPECTED_PAGE_COUNT,
             f"silhouette audit page count is not {EXPECTED_PAGE_COUNT}")
    _require(_saved_scalar(saved_text, "profileVersion") == canonical.get("profileVersion"),
             "silhouette audit profile version mismatch")
    _require(_saved_scalar(saved_text, "profileHash") == canonical.get("profileHash"),
             "silhouette audit profile hash mismatch")

    canonical_profiles = canonical.get("profiles")
    _require(isinstance(canonical_profiles, list) and len(canonical_profiles) == 180,
             "canonical profile matrix is incomplete")
    canonical_by_key = {_profile_key(row): row for row in canonical_profiles}
    _require(len(canonical_by_key) == 180, "canonical profile matrix has duplicate keys")

    rows = [_parse_lua_object(value) for value in _top_level_objects(_extract_lua_table(saved_text, "rows"))]
    _require(len(rows) == EXPECTED_ROW_COUNT, "SavedVariables silhouette row table is incomplete")
    expected_keys = {(key, silhouette) for key in canonical_by_key for silhouette in SILHOUETTES}
    actual_keys = {(_profile_key(row), str(row.get("silhouette"))) for row in rows}
    _require(actual_keys == expected_keys and len(actual_keys) == EXPECTED_ROW_COUNT,
             "silhouette profile identities are incomplete or duplicated")

    for row in rows:
        key = _profile_key(row)
        profile = canonical_by_key[key]
        _require(row.get("modelReady") is True, f"runtime model was not ready: {key}")
        _require(str(row.get("actualModel", "")).lower() == str(row.get("expectedModel", "")).lower(),
                 f"runtime model path drift: {key}")
        _require(int(row.get("sentinel", -1)) == int(profile["sentinel"]),
                 f"runtime sentinel drift: {key}")
        _require(int(row.get("previewItemId", 0)) > 0,
                 f"silhouette sample item is missing: {key}/{row.get('silhouette')}")

    pages = [_parse_lua_object(value) for value in _top_level_objects(_extract_lua_table(saved_text, "pages"))]
    _require(len(pages) == EXPECTED_PAGE_COUNT and all(row.get("ready") is True for row in pages),
             "one or more silhouette-audit pages were not ready")
    _require({int(row.get("page", 0)) for row in pages} == set(range(1, EXPECTED_PAGE_COUNT + 1)),
             "silhouette-audit pages are incomplete")
    silhouette_counts = {name: sum(row.get("silhouette") == name for row in rows) for name in SILHOUETTES}
    _require(silhouette_counts == {name: 180 for name in SILHOUETTES},
             "silhouette audit does not contain 180 rows per armor weight")

    if screenshot_directory is not None:
        _require(screenshot_directory.is_dir(), f"screenshot directory is missing: {screenshot_directory}")
        for page in range(1, EXPECTED_PAGE_COUNT + 1):
            _require((screenshot_directory / f"silhouette-{page:02d}.jpg").is_file(),
                     f"silhouette screenshot is missing for page {page}")
        _require((screenshot_directory / "silhouette-reload.jpg").is_file(),
                 "silhouette reload screenshot is missing")

    return {
        "mode": "silhouettes",
        "rows": len(rows),
        "pages": len(pages),
        "profileHash": canonical["profileHash"],
        "silhouetteRows": silhouette_counts,
    }


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--saved-variables", type=Path, required=True)
    parser.add_argument("--canonical", type=Path, required=True)
    parser.add_argument("--screenshot-directory", type=Path)
    args = parser.parse_args(argv)
    try:
        print(json.dumps(check_silhouette_audit(
            args.saved_variables,
            args.canonical,
            args.screenshot_directory,
        ), sort_keys=True))
    except (OSError, CameraRuntimeMatrixError) as exc:
        parser.error(str(exc))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
