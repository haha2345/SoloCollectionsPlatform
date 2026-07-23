#!/usr/bin/env python3
"""Validate the temporary Stage 3 set-presentation client audit."""

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
REQUIRED_SCREENSHOTS = (
    "paladin-reload-ready.jpg",
    "paladin-relog-ready.jpg",
    "second-class-ready.jpg",
)


def _require(condition: bool, message: str) -> None:
    if not condition:
        raise CameraRuntimeMatrixError(message)


def _read_saved(path: Path) -> str:
    try:
        return path.read_text(encoding="utf-8")
    except (OSError, UnicodeDecodeError) as exc:
        raise CameraRuntimeMatrixError(f"cannot read SavedVariables {path}: {exc}") from exc


def _runs(saved_text: str) -> list[dict[str, Any]]:
    return [_parse_lua_object(value) for value in _top_level_objects(_extract_lua_table(saved_text, "runs"))]


def _signature_ids(value: Any) -> list[int]:
    _require(isinstance(value, str) and value, "set-order audit has no order signature")
    try:
        ids = [int(part) for part in value.split(",")]
    except ValueError as exc:
        raise CameraRuntimeMatrixError("set-order audit order signature is malformed") from exc
    _require(len(ids) == EXPECTED_SET_COUNT, "set-order audit signature has wrong set count")
    _require(len(set(ids)) == EXPECTED_SET_COUNT and all(item_set_id > 0 for item_set_id in ids),
             "set-order audit signature is duplicated or invalid")
    return ids


def check_set_order_audit(saved_path: Path, screenshot_directory: Path | None = None) -> dict[str, Any]:
    saved_text = _read_saved(saved_path)
    _require(_saved_scalar(saved_text, "completed") is True, "set-order audit did not complete")
    _require(_saved_scalar(saved_text, "ready") is True, "set-order audit did not report ready")
    _require(_saved_scalar(saved_text, "reloadPass") is True, "set-order audit reload persistence failed")
    _require(_saved_scalar(saved_text, "relogPass") is True, "set-order audit relog persistence failed")
    _require(_saved_scalar(saved_text, "differentClassPass") is True,
             "set-order audit did not verify a second character class")

    runs = _runs(saved_text)
    _require(len(runs) >= 2, "set-order audit requires at least two character runs")
    classes = {str(run.get("playerClass", "")) for run in runs}
    _require(len(classes) >= 2 and "UNKNOWN" not in classes,
             "set-order audit did not retain two distinct player classes")
    for run in runs:
        _require(run.get("completed") is True and run.get("ready") is True,
                 f"incomplete character run: {run.get('runKey', '?')}")
        _require(int(run.get("allCount", 0)) == EXPECTED_SET_COUNT,
                 f"wrong active set count for {run.get('playerClass', '?')}")
        for field in (
            "allOrderSorted", "t10PrefixPass", "higherCohortPass", "searchPass",
            "classFilterPass", "pageStartPass", "pageEndPass",
        ):
            _require(run.get(field) is True, f"character run did not pass {field}: {run.get('playerClass', '?')}")
        _require(int(run.get("searchCount", 0)) > 0, "real UI search returned no result")
        _require(int(run.get("classFilterCount", 0)) > 0, "real UI class filter returned no result")
        _require(int(run.get("errorCount", -1)) == 0,
                 f"character run recorded errors: {run.get('playerClass', '?')}")
        _signature_ids(run.get("allSignature"))

    if screenshot_directory is not None:
        _require(screenshot_directory.is_dir(), f"screenshot directory is missing: {screenshot_directory}")
        for filename in REQUIRED_SCREENSHOTS:
            _require((screenshot_directory / filename).is_file(),
                     f"set-order screenshot is missing: {filename}")

    return {
        "mode": "set-ordering",
        "sets": EXPECTED_SET_COUNT,
        "classes": sorted(classes),
        "runs": len(runs),
        "reload": True,
        "relog": True,
        "crossClass": True,
    }


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--saved-variables", type=Path, required=True)
    parser.add_argument("--screenshot-directory", type=Path)
    args = parser.parse_args(argv)
    try:
        print(json.dumps(check_set_order_audit(args.saved_variables, args.screenshot_directory), sort_keys=True))
    except (OSError, CameraRuntimeMatrixError) as exc:
        parser.error(str(exc))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
