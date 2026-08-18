#!/usr/bin/env python3
"""Validate the temporary Stage 4 21-weapon camera-regression audit."""

from __future__ import annotations

import argparse
import json
from pathlib import Path
from typing import Any

from export_camera_runtime_matrix import (
    CameraRuntimeMatrixError,
    _extract_lua_table,
    _parse_lua_object,
    _read_json,
    _saved_scalar,
    _top_level_objects,
)


EXPECTED_ROW_COUNT = 21
EXPECTED_PAGE_COUNT = 3


def _require(condition: bool, message: str) -> None:
    if not condition:
        raise CameraRuntimeMatrixError(message)


def _read_saved(path: Path) -> str:
    try:
        return path.read_text(encoding="utf-8")
    except (OSError, UnicodeDecodeError) as exc:
        raise CameraRuntimeMatrixError(f"cannot read SavedVariables {path}: {exc}") from exc


def check_weapon_camera_audit(
    saved_path: Path,
    presentation_source: Path,
    screenshot_directory: Path | None = None,
) -> dict[str, Any]:
    """Validate one completed full-catalogue weapon-camera visual matrix."""
    saved_text = _read_saved(saved_path)
    source = _read_json(presentation_source)
    source_rows = source.get("entries") if isinstance(source, dict) else None
    _require(isinstance(source_rows, list), "presentation source has no entries list")
    expected = {
        int(row["appearanceId"]): row
        for row in source_rows
        if row.get("presentationStatus") == "verified"
    }
    _require(len(expected) == EXPECTED_ROW_COUNT,
             f"presentation source does not contain {EXPECTED_ROW_COUNT} verified weapons")

    _require(_saved_scalar(saved_text, "completed") is True, "weapon audit did not complete")
    _require(_saved_scalar(saved_text, "ready") is True, "weapon audit did not report ready")
    _require(_saved_scalar(saved_text, "reloadObserved") is True,
             "weapon audit reload persistence was not observed")
    _require(_saved_scalar(saved_text, "rowCount") == EXPECTED_ROW_COUNT,
             f"weapon audit row count is not {EXPECTED_ROW_COUNT}")
    _require(_saved_scalar(saved_text, "pageCount") == EXPECTED_PAGE_COUNT,
             f"weapon audit page count is not {EXPECTED_PAGE_COUNT}")

    rows = [_parse_lua_object(value) for value in _top_level_objects(_extract_lua_table(saved_text, "rows"))]
    _require(len(rows) == EXPECTED_ROW_COUNT, "SavedVariables weapon row table is incomplete")
    actual = {int(row.get("appearanceId", 0)): row for row in rows}
    _require(set(actual) == set(expected) and len(actual) == EXPECTED_ROW_COUNT,
             "weapon appearance identities are incomplete or duplicated")
    for appearance_id, row in actual.items():
        source_row = expected[appearance_id]
        _require(row.get("modelReady") is True, f"runtime model was not ready: {appearance_id}")
        _require(row.get("cameraApplied") is True, f"M2 camera was not applied: {appearance_id}")
        _require(str(row.get("actualModel", "")).lower() == str(row.get("expectedModel", "")).lower(),
                 f"runtime model path drift: {appearance_id}")
        _require(str(row.get("expectedModel", "")).lower() == str(source_row.get("modelPath", "")).lower(),
                 f"presentation source model mismatch: {appearance_id}")
        _require(int(row.get("syntheticDisplayId", 0)) == int(source_row.get("syntheticDisplayId", 0)),
                 f"presentation source synthetic-display mismatch: {appearance_id}")

    pages = [_parse_lua_object(value) for value in _top_level_objects(_extract_lua_table(saved_text, "pages"))]
    _require(len(pages) == EXPECTED_PAGE_COUNT and all(page.get("ready") is True for page in pages),
             "one or more weapon-audit pages were not ready")
    _require({int(page.get("page", 0)) for page in pages} == set(range(1, EXPECTED_PAGE_COUNT + 1)),
             "weapon-audit pages are incomplete")
    if screenshot_directory is not None:
        _require(screenshot_directory.is_dir(), f"screenshot directory is missing: {screenshot_directory}")
        for page in range(1, EXPECTED_PAGE_COUNT + 1):
            _require((screenshot_directory / f"weapon-camera-{page:02d}.jpg").is_file(),
                     f"weapon screenshot is missing for page {page}")
        _require((screenshot_directory / "weapon-camera-reload.jpg").is_file(),
                 "weapon reload screenshot is missing")

    return {
        "mode": "weapons",
        "rows": len(rows),
        "pages": len(pages),
        "models": len({str(row.get("expectedModel", "")).lower() for row in rows}),
        "includesUnobtainableReviewedWeapon": 212036 in actual,
    }


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--saved-variables", type=Path, required=True)
    parser.add_argument("--presentation-source", type=Path, required=True)
    parser.add_argument("--screenshot-directory", type=Path)
    args = parser.parse_args(argv)
    try:
        print(json.dumps(check_weapon_camera_audit(
            args.saved_variables,
            args.presentation_source,
            args.screenshot_directory,
        ), sort_keys=True))
    except (OSError, CameraRuntimeMatrixError) as exc:
        parser.error(str(exc))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
