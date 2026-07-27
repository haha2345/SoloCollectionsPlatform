#!/usr/bin/env python3
"""Verify the repository-safe Stage 6 weapon shadow review products."""

from __future__ import annotations

import argparse
import csv
import importlib.util
import json
from collections import Counter
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
SHADOW_PATH = ROOT / "tools" / "catalog" / "weapon_shadow.py"
SPEC = importlib.util.spec_from_file_location("solo_weapon_shadow_check", SHADOW_PATH)
assert SPEC and SPEC.loader
shadow = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(shadow)


def require(value: bool, message: str) -> None:
    if not value:
        raise RuntimeError(message)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--evidence-root", type=Path, required=True)
    parser.add_argument("--review-root", type=Path, default=ROOT / "catalog" / "review" / "weapons")
    args = parser.parse_args()
    evidence = args.evidence_root.resolve()
    review = args.review_root.resolve()
    shadow.audit(evidence, review, None, check=True)
    with (review / "shadow-candidates.csv").open(encoding="utf-8", newline="") as handle:
        candidates = list(csv.DictReader(handle))
    with (review / "shadow-samples.csv").open(encoding="utf-8", newline="") as handle:
        samples = list(csv.DictReader(handle))
    summary = json.loads((review / "shadow-summary.json").read_text(encoding="utf-8"))
    registry = json.loads((review / "shadow-registry.json").read_text(encoding="utf-8"))
    baseline = json.loads((evidence / "reserved-baseline.json").read_text(encoding="utf-8"))
    require(len(candidates) == 5957, f"candidate coverage drift: {len(candidates)}")
    public = [row for row in candidates if row["scope"] == "PUBLIC"]
    require(len(public) == 3690, f"public denominator drift: {len(public)}")
    require(all(row["terminalStatus"] in {"READY", "UNAVAILABLE"} for row in public),
            "public candidate lacks terminal state")
    require(summary["terminalCounts"]["publicReady"] + summary["terminalCounts"]["publicUnavailable"] == 3690,
            "summary public terminal denominator drift")
    reserved = [row for row in registry["entries"] if row["allocationStatus"] == "RESERVED"]
    require(len(reserved) == 21, f"reserved registry drift: {len(reserved)}")
    require({row["syntheticDisplayId"] for row in reserved} == set(range(40000, 40021)),
            "reserved synthetic display IDs drift")
    baseline_by_appearance = {row["appearanceId"]: row for row in baseline["entries"]}
    require(
        all(
            baseline_by_appearance.get(row["appearanceId"], {}).get("modelId") == row["modelId"]
            and baseline_by_appearance.get(row["appearanceId"], {}).get("syntheticDisplayId") == row["syntheticDisplayId"]
            and baseline_by_appearance.get(row["appearanceId"], {}).get("sourceItemId") == row["sourceItemId"]
            for row in reserved
        ),
        "reserved model/display/source IDs drift",
    )
    require(samples, "manual sample review is empty")
    route_samples = {row["route"] for row in samples if row["sampleKind"] == "ROUTE_STRATIFIED"}
    require({"MAINHAND", "OFFHAND_WEAPON", "SHIELD", "HELD_IN_OFFHAND", "RANGED"} <= route_samples,
            f"route sample coverage drift: {sorted(route_samples)}")
    for row in samples:
        for field in ("resolvedModelPath", "resolvedSkinPath", "resolvedTexturePath"):
            path = evidence / "asset-cache" / Path(*row[field].lower().split("\\"))
            require(path.is_file(), f"sample source asset missing: {field}:{row['appearanceId']}")
    output = {
        "mode": "weapon-shadow",
        "candidates": len(candidates),
        "public": len(public),
        "terminal": dict(sorted(Counter(row["terminalStatus"] for row in candidates).items())),
        "samples": len(samples),
        "routeSamples": sorted(route_samples),
        "reserved": len(reserved),
        "registryHash": registry["registryHash"],
        "summaryHash": summary["summaryHash"],
    }
    print(json.dumps(output, ensure_ascii=False, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
