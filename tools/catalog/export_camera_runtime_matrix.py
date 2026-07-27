#!/usr/bin/env python3
"""Build the checked-in character-camera review matrix from QA SavedVariables.

The live audit owns runtime facts (the 180 model-path checks, page readiness,
profile hash and reload persistence).  The prior checked-in review owns the
human visual annotations.  This exporter only carries those annotations
forward when the corresponding profile has not changed status; any newly
approved body-profile delta must be explicitly named as rechecked.
"""

from __future__ import annotations

import argparse
import csv
import io
import json
import re
from pathlib import Path
from typing import Any, Iterable


class CameraRuntimeMatrixError(RuntimeError):
    """Raised when a live camera-audit result is incomplete or inconsistent."""


CSV_FIELDS = (
    "profileHash", "raceKey", "sex", "slot", "sentinel", "profileStatus",
    "page", "screenshot", "previewDisplayId", "previewItemId", "expectedModel",
    "modelReady", "inSafeFrame", "targetVisible", "targetCentered",
    "unexpectedClipping", "overrideRequired", "visualReview", "evidenceRun",
)
VISUAL_FIELDS = (
    "inSafeFrame", "targetVisible", "targetCentered", "unexpectedClipping",
    "overrideRequired", "visualReview",
)
SCALAR_RE = re.compile(
    r'\["(?P<key>[^"]+)"\]\s*=\s*'
    r'(?P<value>true|false|-?\d+(?:\.\d+)?|"(?:\\.|[^"\\])*")\s*,?'
)


def _require(condition: bool, message: str) -> None:
    if not condition:
        raise CameraRuntimeMatrixError(message)


def _read_json(path: Path) -> dict[str, Any]:
    try:
        value = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, UnicodeDecodeError, json.JSONDecodeError) as exc:
        raise CameraRuntimeMatrixError(f"cannot read JSON {path}: {exc}") from exc
    _require(isinstance(value, dict), f"JSON root must be an object: {path}")
    return value


def _decode_lua_scalar(value: str) -> Any:
    if value == "true":
        return True
    if value == "false":
        return False
    if value.startswith('"'):
        # The SavedVariables serializer uses Lua escapes compatible with the
        # JSON subset used by its string fields (backslash and quote).
        return json.loads(value)
    return float(value) if "." in value else int(value)


def _extract_lua_table(text: str, key: str) -> str:
    marker = f'["{key}"] = {{'
    marker_index = text.find(marker)
    _require(marker_index >= 0, f"SavedVariables is missing table: {key}")
    start = marker_index + len(marker) - 1
    depth = 0
    in_string = False
    escaped = False
    for index in range(start, len(text)):
        character = text[index]
        if in_string:
            if escaped:
                escaped = False
            elif character == "\\":
                escaped = True
            elif character == '"':
                in_string = False
            continue
        if character == '"':
            in_string = True
        elif character == "{":
            depth += 1
        elif character == "}":
            depth -= 1
            if depth == 0:
                return text[start + 1:index]
    raise CameraRuntimeMatrixError(f"SavedVariables table is unterminated: {key}")


def _top_level_objects(table_body: str) -> Iterable[str]:
    depth = 0
    start: int | None = None
    in_string = False
    escaped = False
    for index, character in enumerate(table_body):
        if in_string:
            if escaped:
                escaped = False
            elif character == "\\":
                escaped = True
            elif character == '"':
                in_string = False
            continue
        if character == '"':
            in_string = True
        elif character == "{":
            if depth == 0:
                start = index
            depth += 1
        elif character == "}":
            depth -= 1
            if depth == 0:
                _require(start is not None, "SavedVariables object parser lost its start")
                yield table_body[start + 1:index]
                start = None
            _require(depth >= 0, "SavedVariables object parser saw an unexpected closing brace")
    _require(depth == 0, "SavedVariables object table is unterminated")


def _parse_lua_object(text: str) -> dict[str, Any]:
    result = {match.group("key"): _decode_lua_scalar(match.group("value")) for match in SCALAR_RE.finditer(text)}
    _require(result, "SavedVariables object has no scalar fields")
    return result


def _saved_scalar(text: str, key: str) -> Any:
    match = re.search(
        r'\["' + re.escape(key) + r'"\]\s*=\s*'
        r'(true|false|-?\d+(?:\.\d+)?|"(?:\\.|[^"\\])*")\s*,?',
        text,
    )
    _require(match is not None, f"SavedVariables is missing scalar: {key}")
    return _decode_lua_scalar(match.group(1))


def _profile_key(row: dict[str, Any]) -> str:
    return f"{row['raceKey']}:{str(row['sex']).lower()}:{row['slot']}"


def _previous_visual_rows(path: Path) -> dict[str, dict[str, str]]:
    try:
        with path.open(encoding="utf-8-sig", newline="") as handle:
            rows = list(csv.DictReader(handle))
    except OSError as exc:
        raise CameraRuntimeMatrixError(f"cannot read previous review {path}: {exc}") from exc
    result = {_profile_key(row): row for row in rows}
    _require(len(result) == len(rows) == 180, "previous review must contain 180 unique rows")
    return result


def build_matrix(
    saved_path: Path,
    canonical_path: Path,
    previous_review_path: Path,
    evidence_run: str,
    rechecked_profiles: set[str],
    screenshot_directory: Path | None,
) -> list[dict[str, str]]:
    try:
        saved_text = saved_path.read_text(encoding="utf-8")
    except (OSError, UnicodeDecodeError) as exc:
        raise CameraRuntimeMatrixError(f"cannot read SavedVariables {saved_path}: {exc}") from exc
    canonical = _read_json(canonical_path)
    _require(_saved_scalar(saved_text, "completed") is True, "camera audit did not complete")
    _require(_saved_scalar(saved_text, "ready") is True, "camera audit did not report ready")
    _require(_saved_scalar(saved_text, "reloadObserved") is True, "camera audit reload persistence was not observed")
    _require(_saved_scalar(saved_text, "rowCount") == 180, "camera audit row count is not 180")
    _require(_saved_scalar(saved_text, "pageCount") == 20, "camera audit page count is not 20")
    _require(_saved_scalar(saved_text, "profileVersion") == canonical.get("profileVersion"), "profile version mismatch")
    _require(_saved_scalar(saved_text, "profileHash") == canonical.get("profileHash"), "profile hash mismatch")
    unknown_fallback = _parse_lua_object(_extract_lua_table(saved_text, "unknownFallback"))
    _require(all(unknown_fallback.get(name) is True for name in ("syntheticRace", "unknownSex", "assetMismatch")),
             "camera audit unknown-profile fallback failed")

    canonical_profiles = canonical.get("profiles")
    _require(isinstance(canonical_profiles, list) and len(canonical_profiles) == 180,
             "canonical profile matrix is incomplete")
    canonical_by_key = {_profile_key(row): row for row in canonical_profiles}
    _require(len(canonical_by_key) == 180, "canonical profile matrix has duplicate keys")
    previous_by_key = _previous_visual_rows(previous_review_path)

    runtime_rows = [_parse_lua_object(value) for value in _top_level_objects(_extract_lua_table(saved_text, "rows"))]
    _require(len(runtime_rows) == 180, "SavedVariables row table is incomplete")
    runtime_by_key = {_profile_key(row): row for row in runtime_rows}
    _require(len(runtime_by_key) == 180 and set(runtime_by_key) == set(canonical_by_key),
             "SavedVariables profile identities do not match canonical matrix")

    pages = [_parse_lua_object(value) for value in _top_level_objects(_extract_lua_table(saved_text, "pages"))]
    _require(len(pages) == 20 and all(row.get("ready") is True for row in pages),
             "one or more camera-audit pages were not ready")
    _require({int(row.get("page", 0)) for row in pages} == set(range(1, 21)),
             "camera-audit pages are incomplete")

    if screenshot_directory is not None:
        _require(screenshot_directory.is_dir(), f"screenshot directory is missing: {screenshot_directory}")
        for page in range(1, 21):
            _require((screenshot_directory / f"camera-{page:02d}.jpg").is_file(),
                     f"matrix screenshot is missing for page {page}")

    rows: list[dict[str, str]] = []
    for key in sorted(canonical_by_key):
        profile = canonical_by_key[key]
        runtime = runtime_by_key[key]
        prior = previous_by_key[key]
        _require(runtime.get("modelReady") is True, f"runtime model was not ready: {key}")
        _require(str(runtime.get("actualModel", "")).lower() == str(runtime.get("expectedModel", "")).lower(),
                 f"runtime model path drift: {key}")
        _require(int(runtime.get("sentinel", -1)) == int(profile["sentinel"]), f"runtime sentinel drift: {key}")
        changed_status = prior.get("profileStatus") != str(profile["status"])
        if changed_status:
            _require(key in rechecked_profiles,
                     f"changed profile status needs explicit visual recheck: {key}")
        screenshot = f"camera-{int(runtime['page']):02d}.jpg"
        rows.append({
            "profileHash": str(canonical["profileHash"]),
            "raceKey": str(runtime["raceKey"]),
            "sex": str(runtime["sex"]),
            "slot": str(runtime["slot"]),
            "sentinel": f"0x{int(runtime['sentinel']):04X}",
            "profileStatus": str(profile["status"]),
            "page": str(int(runtime["page"])),
            "screenshot": screenshot,
            "previewDisplayId": str(int(runtime["previewDisplayId"])),
            "previewItemId": str(int(runtime["previewItemId"])),
            "expectedModel": str(runtime["expectedModel"]),
            "modelReady": "PASS",
            **{field: prior[field] for field in VISUAL_FIELDS},
            "evidenceRun": evidence_run,
        })
    return rows


def render_matrix(rows: list[dict[str, str]]) -> str:
    buffer = io.StringIO(newline="")
    writer = csv.DictWriter(buffer, fieldnames=CSV_FIELDS, quoting=csv.QUOTE_ALL, lineterminator="\n")
    writer.writeheader()
    writer.writerows(rows)
    return buffer.getvalue()


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--saved-variables", type=Path, required=True)
    parser.add_argument("--canonical", type=Path, required=True)
    parser.add_argument("--previous-review", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--evidence-run", required=True)
    parser.add_argument("--rechecked-profile", action="append", default=[])
    parser.add_argument("--screenshot-directory", type=Path)
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args(argv)
    try:
        rows = build_matrix(
            args.saved_variables,
            args.canonical,
            args.previous_review,
            args.evidence_run,
            set(args.rechecked_profile),
            args.screenshot_directory,
        )
        rendered = render_matrix(rows)
        if args.check:
            _require(args.output.is_file() and args.output.read_text(encoding="utf-8") == rendered,
                     f"generated output is stale: {args.output}")
        else:
            args.output.parent.mkdir(parents=True, exist_ok=True)
            args.output.write_text(rendered, encoding="utf-8", newline="")
        print(json.dumps({"rows": len(rows), "profileHash": rows[0]["profileHash"], "evidenceRun": args.evidence_run}))
    except (OSError, CameraRuntimeMatrixError) as exc:
        parser.error(str(exc))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
