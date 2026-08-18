#!/usr/bin/env python3
"""Render a temporary stage-seven direct-display audit input from a bundle."""

from __future__ import annotations

import argparse
import json
import os
from pathlib import Path


def require(value: bool, message: str) -> None:
    if not value:
        raise ValueError(message)


def ensure_f(path: Path, label: str) -> Path:
    value = path.resolve()
    if os.name == "nt":
        require(value.drive.upper() == "F:", f"{label} must be on F:, got {value}")
    return value


def lua_quote(value: str) -> str:
    return '"' + value.replace("\\", "\\\\").replace('"', '\\"') + '"'


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--stage", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument(
        "--start-index",
        type=int,
        default=1,
        help="1-based index in the stable synthetic-display ordering (default: 1)",
    )
    parser.add_argument(
        "--count",
        type=int,
        help="number of records to emit; omit for the remainder of the stable ordering",
    )
    parser.add_argument(
        "--auto-logout",
        action="store_true",
        help="ask the temporary audit AddOn to logout after a completed audit",
    )
    parser.add_argument(
        "--auto-logout-delay",
        type=float,
        default=8.0,
        help="seconds to preserve the completed audit panel before auto logout",
    )
    args = parser.parse_args()
    stage = ensure_f(args.stage, "stage")
    output = ensure_f(args.output, "output")
    manifest = json.loads((stage / "weapon-bundle-manifest.json").read_text(encoding="utf-8"))
    require(manifest.get("kind") == "SoloCollectionsWeaponBundleStage", "unexpected bundle manifest")
    records = manifest.get("registryProjection", {}).get("records", [])
    require(len(records) == int(manifest.get("selection", {}).get("appearanceCount", -1)), "projection is incomplete")
    # A display can legally back multiple appearances.  Keep the secondary
    # appearance key explicit so a bounded audit slice has the exact same
    # membership in Python, PowerShell, and the merged client report.
    ordered_records = sorted(
        records,
        key=lambda value: (int(value["syntheticDisplayId"]), int(value["appearanceId"])),
    )
    for row in ordered_records:
        display_id = int(row["syntheticDisplayId"])
        model_path = str(row["modelPath"]).replace("/", "\\")
        require(0 < display_id <= 0x00FFFFFF, f"unsafe display ID: {display_id}")
        require(model_path.lower().endswith(".m2") and ".." not in model_path, f"unsafe model path: {model_path}")
    start_index = args.start_index
    require(start_index >= 1, f"start index must be positive: {start_index}")
    count = args.count if args.count is not None else len(ordered_records) - start_index + 1
    require(count > 0, f"audit slice count must be positive: {count}")
    end_index = start_index - 1 + count
    require(end_index <= len(ordered_records), f"audit slice exceeds projection: {start_index}+{count}>{len(ordered_records)}")
    require(1.0 <= args.auto_logout_delay <= 60.0, "auto logout delay must be between 1 and 60 seconds")
    selected_records = ordered_records[start_index - 1 : end_index]
    rows = []
    for row in selected_records:
        display_id = int(row["syntheticDisplayId"])
        model_path = str(row["modelPath"]).replace("/", "\\")
        rows.append(
            "    { appearanceId = %d, syntheticDisplayId = %d, modelPath = %s },"
            % (int(row["appearanceId"]), display_id, lua_quote(model_path))
        )
    text = "\n".join(
        [
            "-- Generated from a named F-drive weapon bundle; do not hand edit.",
            "SoloCollectionsWeaponShadowAuditData = {",
            "    bundleId = %s," % lua_quote(str(manifest["bundleId"])),
            "    autoLogout = %s," % ("true" if args.auto_logout else "false"),
            "    autoLogoutDelay = %.3f," % args.auto_logout_delay,
            "    records = {",
            *rows,
            "    },",
            "}",
            "",
        ]
    )
    output.parent.mkdir(parents=True, exist_ok=True)
    temporary = output.with_name(output.name + ".tmp")
    temporary.write_text(text, encoding="utf-8", newline="\n")
    os.replace(temporary, output)
    print(
        json.dumps(
            {
                "bundleId": manifest["bundleId"],
                "records": len(rows),
                "startIndex": start_index,
                "count": count,
                "projectionCount": len(ordered_records),
                "autoLogout": bool(args.auto_logout),
                "autoLogoutDelay": args.auto_logout_delay,
                "output": str(output),
            },
            ensure_ascii=False,
        )
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
