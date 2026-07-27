#!/usr/bin/env python3
"""Validate the temporary Stage 2 set-scroll and clean-preview client audit."""

from __future__ import annotations

import argparse
import json
from pathlib import Path
from typing import Any

from export_camera_runtime_matrix import (
    CameraRuntimeMatrixError,
    _extract_lua_table,
    _parse_lua_object,
    _saved_scalar,
    _top_level_objects,
)


EXPECTED_SET_COUNT = 465
EXPECTED_SAMPLE_LABELS = {
    "synthetic selected variant 2/9",
    "sample 2 pieces",
    "sample 3 pieces",
    "sample 5 pieces",
    "sample 8 pieces",
    "pregear-clear two-piece",
    "rapid final of 20",
}
EXPECTED_PAGINATION = {
    "empty": {"recordCount": 0, "offset": 0, "page": 1, "totalPages": 1, "visible": 0, "maximum": 0},
    "single": {"recordCount": 1, "offset": 0, "page": 1, "totalPages": 1, "visible": 1, "maximum": 0},
    "exact-window": {"recordCount": 8, "offset": 0, "page": 1, "totalPages": 1, "visible": 8, "maximum": 0},
    "multi-last-partial": {"recordCount": 17, "offset": 9, "page": 3, "totalPages": 3, "visible": 8, "maximum": 9},
}
REQUIRED_SCREENSHOTS = (
    "pagination-last-partial.jpg",
    "pregear-clear.jpg",
    "reload-ready.jpg",
)


def _require(condition: bool, message: str) -> None:
    if not condition:
        raise CameraRuntimeMatrixError(message)


def _read_saved(path: Path) -> str:
    try:
        return path.read_text(encoding="utf-8")
    except (OSError, UnicodeDecodeError) as exc:
        raise CameraRuntimeMatrixError(f"cannot read SavedVariables {path}: {exc}") from exc


def _objects(saved_text: str, key: str) -> list[dict[str, Any]]:
    return [_parse_lua_object(value) for value in _top_level_objects(_extract_lua_table(saved_text, key))]


def check_set_preview_audit(
    saved_path: Path,
    screenshot_directory: Path | None = None,
) -> dict[str, Any]:
    """Validate one completed 465-active-set runtime preview matrix."""
    saved_text = _read_saved(saved_path)
    _require(_saved_scalar(saved_text, "completed") is True, "set audit did not complete")
    _require(_saved_scalar(saved_text, "ready") is True, "set audit did not report ready")
    _require(_saved_scalar(saved_text, "reloadObserved") is True,
             "set audit reload persistence was not observed")
    _require(_saved_scalar(saved_text, "rowCount") == EXPECTED_SET_COUNT,
             f"set audit row count is not {EXPECTED_SET_COUNT}")
    _require(_saved_scalar(saved_text, "uniqueSetCount") == EXPECTED_SET_COUNT,
             f"set audit unique-set count is not {EXPECTED_SET_COUNT}")
    _require(_saved_scalar(saved_text, "sampleCount") == len(EXPECTED_SAMPLE_LABELS),
             "set audit sample count is incomplete")
    for field in ("paginationPassed", "syntheticFixturePassed", "rapidPassed"):
        _require(_saved_scalar(saved_text, field) is True, f"set audit did not pass {field}")
    _require(not _extract_lua_table(saved_text, "errors").strip(), "set audit emitted runtime errors")

    scan_rows = _objects(saved_text, "scanRows")
    _require(len(scan_rows) == EXPECTED_SET_COUNT, "set audit scan rows are incomplete")
    scan_by_id = {int(row.get("setId", 0)): row for row in scan_rows}
    _require(len(scan_by_id) == EXPECTED_SET_COUNT and 0 not in scan_by_id,
             "set audit scan IDs are duplicated or invalid")
    for set_id, row in scan_by_id.items():
        _require(row.get("pass") is True, f"preview mismatch for set {set_id}")
        _require(int(row.get("undressCount", 0)) >= 1, f"set {set_id} was not undressed")
        _require(int(row.get("expectedCount", -1)) == int(row.get("actualCount", -2)),
                 f"set {set_id} TryOn count mismatched")

    samples = _objects(saved_text, "samples")
    sample_by_label = {str(row.get("label", "")): row for row in samples}
    _require(set(sample_by_label) == EXPECTED_SAMPLE_LABELS,
             "set audit samples are missing, duplicated, or unexpected")
    for label, row in sample_by_label.items():
        _require(row.get("pass") is True, f"sample did not pass: {label}")
        _require(int(row.get("undressCount", 0)) >= 1, f"sample was not undressed: {label}")
        _require(int(row.get("expectedCount", -1)) == int(row.get("actualCount", -2)),
                 f"sample TryOn count mismatched: {label}")
    _require(int(sample_by_label["synthetic selected variant 2/9"].get("expectedCount", 0)) == 9,
             "synthetic selected-variant fixture is not nine pieces")
    _require(int(sample_by_label["rapid final of 20"].get("expectedCount", 0)) > 0,
             "rapid-switch final preview is empty")

    pagination = _objects(saved_text, "pagination")
    pagination_by_label = {str(row.get("label", "")): row for row in pagination}
    _require(set(pagination_by_label) == set(EXPECTED_PAGINATION),
             "set pagination audit is incomplete")
    for label, expected in EXPECTED_PAGINATION.items():
        row = pagination_by_label[label]
        _require(row.get("pass") is True, f"pagination case failed: {label}")
        for field, expected_value in expected.items():
            _require(int(row.get(field, -1)) == expected_value,
                     f"pagination {label} has wrong {field}")

    scroll = _parse_lua_object(_extract_lua_table(saved_text, "scroll"))
    maximum_offset = EXPECTED_SET_COUNT - 8
    _require(scroll.get("pass") is True, "mid-list slider/wheel continuity failed")
    _require(int(scroll.get("afterWheel", -1)) == min(int(scroll.get("middle", -1)) + 1, maximum_offset),
             "wheel did not continue from the mid-list slider offset")
    _require(int(scroll.get("scrollbarValue", -1)) == int(scroll.get("afterWheel", -2)),
             "scrollbar diverged from the set-list offset")

    if screenshot_directory is not None:
        _require(screenshot_directory.is_dir(), f"screenshot directory is missing: {screenshot_directory}")
        for filename in REQUIRED_SCREENSHOTS:
            _require((screenshot_directory / filename).is_file(),
                     f"set-audit screenshot is missing: {filename}")

    return {
        "mode": "sets",
        "sets": len(scan_rows),
        "samples": len(samples),
        "paginationCases": len(pagination),
        "reloadObserved": True,
        "syntheticNinePiece": True,
    }


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--saved-variables", type=Path, required=True)
    parser.add_argument("--screenshot-directory", type=Path)
    args = parser.parse_args(argv)
    try:
        print(json.dumps(check_set_preview_audit(args.saved_variables, args.screenshot_directory), sort_keys=True))
    except (OSError, CameraRuntimeMatrixError) as exc:
        parser.error(str(exc))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
