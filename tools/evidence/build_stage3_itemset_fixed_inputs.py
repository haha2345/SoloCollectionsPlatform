#!/usr/bin/env python3
"""Create an F:-only fixed evidence pack for ItemSet presentation sorting."""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import shutil
import sys
from pathlib import Path


class FixedInputError(ValueError):
    pass


REPLACED_REPOSITORY_FILES = (
    "catalog/review/sets/evidence.json",
    "catalog/review/sets/review-policy.json",
    "catalog/generated/itemset-candidates.csv",
    "catalog/generated/itemset-exclusions.csv",
    "catalog/generated/normalized-itemsets.json",
    "catalog/generated/set-id-registry-view.json",
    "catalog/generated/set-presentations.json",
    "catalog/generated/set-presentation-review.csv",
    "catalog/source/overrides/set_presentations.json",
)


def require(condition: bool, message: str) -> None:
    if not condition:
        raise FixedInputError(message)


def assert_f_drive(path: Path, label: str) -> None:
    if os.name == "nt":
        require(path.drive.upper() == "F:", f"{label} must stay on F:: {path}")


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for block in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def portable_records(root: Path) -> list[dict[str, object]]:
    records = []
    for path in sorted((item for item in root.rglob("*") if item.is_file() and item.name != "evidence-manifest.json"),
                       key=lambda item: item.relative_to(root).as_posix()):
        records.append({
            "relativePath": path.relative_to(root).as_posix(),
            "size": path.stat().st_size,
            "sha256": sha256(path),
        })
    return records


def manifest_pack_hash(records: list[dict[str, object]]) -> str:
    canonical = "".join(
        f"{record['relativePath']}\0{record['size']}\0{record['sha256']}\n" for record in records
    ).encode("utf-8")
    return hashlib.sha256(canonical).hexdigest()


def copy_tree(source: Path, target: Path) -> None:
    for path in source.rglob("*"):
        relative = path.relative_to(source)
        destination = target / relative
        if path.is_dir():
            destination.mkdir(parents=True, exist_ok=True)
        elif path.name != "evidence-manifest.json":
            destination.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(path, destination)


def build(base_root: Path, repo_root: Path, output_root: Path) -> Path:
    base_root = base_root.resolve()
    repo_root = repo_root.resolve()
    output_root = output_root.resolve()
    assert_f_drive(base_root, "base evidence root")
    assert_f_drive(output_root, "output evidence root")
    require((base_root / "evidence-manifest.json").is_file(), "base evidence manifest is missing")
    require(not output_root.exists(), f"output evidence root already exists: {output_root}")
    output_root.mkdir(parents=True)
    copy_tree(base_root, output_root)
    for relative in REPLACED_REPOSITORY_FILES:
        source = repo_root / relative
        require(source.is_file(), f"current repository file is missing: {relative}")
        destination = output_root / "repository" / relative
        destination.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(source, destination)
    records = portable_records(output_root)
    manifest = {
        "schemaVersion": 1,
        "evidenceId": "round3-stage3-itemset-presentation-fixed-inputs",
        "baseEvidenceId": json.loads((base_root / "evidence-manifest.json").read_text(encoding="utf-8"))["evidenceId"],
        "sourceSanitization": {
            "credentialsIncluded": False,
            "databaseDumpIncluded": False,
            "absoluteSourcePathsIncluded": False,
            "clientAssetBodiesIncluded": False,
        },
        "fileCount": len(records),
        "packHash": manifest_pack_hash(records),
        "files": records,
    }
    (output_root / "evidence-manifest.json").write_text(
        json.dumps(manifest, ensure_ascii=False, sort_keys=True, indent=2) + "\n", encoding="utf-8", newline="\n"
    )
    return output_root / "evidence-manifest.json"


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--base-root", type=Path, required=True)
    parser.add_argument("--repo-root", type=Path, default=Path(__file__).resolve().parents[2])
    parser.add_argument("--output-root", type=Path, required=True)
    args = parser.parse_args(argv)
    try:
        path = build(args.base_root, args.repo_root, args.output_root)
        print(f"stage3_itemset_fixed_inputs={path}")
        return 0
    except (OSError, FixedInputError, KeyError, json.JSONDecodeError) as exc:
        print(f"stage3 itemset fixed-input error: {exc}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
