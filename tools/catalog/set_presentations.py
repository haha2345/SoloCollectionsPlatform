#!/usr/bin/env python3
"""Build audited, display-only sorting metadata for normalized ItemSets.

The ItemSet collection IDs, variants, ownership semantics, and server APPLY
mapping deliberately remain in ``normalized-itemsets.json``.  This tool owns a
separate review projection used only by the AddOn list comparator.
"""

from __future__ import annotations

import argparse
import csv
import hashlib
import io
import json
import sys
from pathlib import Path
from typing import Any


class SetPresentationError(ValueError):
    pass


EXPANSION_RANK = {"UNKNOWN": 0, "CLASSIC": 1, "TBC": 2, "WRATH": 3}
ACQUISITION_RANK = {"UNKNOWN": 0, "PVP": 1, "PVE": 2}
TIER_RANK = {"NONE": 0, "T7": 7, "T8": 8, "T9": 9, "T10": 10}
DIFFICULTY_RANK = {"UNKNOWN": 0, "RAID": 1, "HEROIC": 2}


def require(condition: bool, message: str) -> None:
    if not condition:
        raise SetPresentationError(message)


def read_json(path: Path) -> Any:
    try:
        return json.loads(path.read_text(encoding="utf-8-sig"))
    except (OSError, UnicodeDecodeError, json.JSONDecodeError) as exc:
        raise SetPresentationError(f"cannot read JSON {path}: {exc}") from exc


def canonical_hash(value: Any) -> str:
    payload = json.dumps(value, ensure_ascii=False, sort_keys=True, separators=(",", ":")) + "\n"
    return hashlib.sha256(payload.encode("utf-8")).hexdigest()


def pretty_json(value: Any) -> str:
    return json.dumps(value, ensure_ascii=False, sort_keys=True, indent=2) + "\n"


def csv_bytes(rows: list[dict[str, Any]], fields: list[str]) -> bytes:
    stream = io.StringIO(newline="")
    writer = csv.DictWriter(stream, fieldnames=fields, lineterminator="\n")
    writer.writeheader()
    writer.writerows(rows)
    return stream.getvalue().encode("utf-8")


def validate_policy(policy: dict[str, Any]) -> list[dict[str, Any]]:
    require(policy.get("schemaVersion") == 1, "unsupported set presentation policy schema")
    rules = policy.get("rules")
    require(isinstance(rules, list), "set presentation policy has no rules")
    seen_keys: set[str] = set()
    covered_ids: set[int] = set()
    for rule in rules:
        key = str(rule.get("key", ""))
        bounds = rule.get("itemSetIdRange")
        require(key and key not in seen_keys, f"duplicate or missing set presentation rule key: {key!r}")
        require(isinstance(bounds, list) and len(bounds) == 2, f"invalid ItemSet range for {key}")
        lower, upper = int(bounds[0]), int(bounds[1])
        require(lower > 0 and lower <= upper, f"invalid ItemSet bounds for {key}")
        for item_set_id in range(lower, upper + 1):
            require(item_set_id not in covered_ids, f"overlapping presentation rule for ItemSet {item_set_id}")
            covered_ids.add(item_set_id)
        for field, options in (("expansion", EXPANSION_RANK), ("acquisition", ACQUISITION_RANK),
                               ("raidTier", TIER_RANK), ("difficulty", DIFFICULTY_RANK)):
            require(rule.get(field) in options, f"invalid {field} in {key}")
        require(bool(rule.get("reasonCode")), f"missing presentation reasonCode for {key}")
        seen_keys.add(key)
    return rules


def matching_rule(item_set_id: int, rules: list[dict[str, Any]]) -> dict[str, Any] | None:
    for rule in rules:
        lower, upper = (int(value) for value in rule["itemSetIdRange"])
        if lower <= item_set_id <= upper:
            return rule
    return None


def summary_value(summary: Any, key: str) -> int | float:
    if not isinstance(summary, dict):
        return 0
    value = summary.get(key)
    return value if isinstance(value, (int, float)) else 0


def resolve_presentation(candidate: dict[str, Any], collection_id: int, rule: dict[str, Any] | None) -> dict[str, Any]:
    item_set_id = int(candidate["itemSetId"])
    if rule is None:
        expansion = "UNKNOWN"
        acquisition = "UNKNOWN"
        tier = "NONE"
        difficulty = "UNKNOWN"
        rule_key = "unclassified"
        reason_code = "NO_REVIEWED_ITEMSET_PRESENTATION_RULE"
        status = "UNKNOWN"
    else:
        expansion = str(rule["expansion"])
        acquisition = str(rule["acquisition"])
        tier = str(rule["raidTier"])
        difficulty = str(rule["difficulty"])
        rule_key = str(rule["key"])
        reason_code = str(rule["reasonCode"])
        status = "REVIEWED"
    item_level = candidate.get("itemLevel") or {}
    quality = candidate.get("quality") or {}
    return {
        "collectionId": collection_id,
        "itemSetId": item_set_id,
        "status": status,
        "ruleKey": rule_key,
        "reasonCode": reason_code,
        "expansion": expansion,
        "acquisition": acquisition,
        "raidTier": tier,
        "difficulty": difficulty,
        "itemLevel": item_level,
        "quality": quality,
        "sortRank": {
            "expansion": EXPANSION_RANK[expansion],
            "acquisition": ACQUISITION_RANK[acquisition],
            "tier": TIER_RANK[tier],
            "difficulty": DIFFICULTY_RANK[difficulty],
            "medianItemLevel": summary_value(item_level, "median"),
            "maxItemLevel": summary_value(item_level, "max"),
        },
    }


def build(repo_root: Path) -> tuple[dict[str, Any], list[dict[str, Any]]]:
    evidence = read_json(repo_root / "catalog/review/sets/evidence.json")
    review = read_json(repo_root / "catalog/review/sets/review-policy.json")
    normalized = read_json(repo_root / "catalog/generated/normalized-itemsets.json")
    policy = read_json(repo_root / "catalog/source/overrides/set_presentations.json")
    require(evidence.get("schemaVersion") == 3, "set presentation review requires ItemSet evidence schema 3")
    require(normalized.get("schemaVersion") == 2, "unsupported normalized ItemSet schema")
    rules = validate_policy(policy)
    candidates = {str(row["candidateKey"]): row for row in evidence.get("candidates", [])}
    decisions = {str(row["candidateKey"]): row for row in review.get("decisions", [])}
    require(len(candidates) == 509 and set(candidates) == set(decisions),
            "every ItemSet evidence row needs one review decision")
    active_by_item_set_id = {int(row["itemSetId"]): row for row in normalized.get("sets", [])}
    require(len(active_by_item_set_id) == 465, "expected 465 active normalized ItemSets")

    presentations: list[dict[str, Any]] = []
    review_rows: list[dict[str, Any]] = []
    for candidate in sorted(candidates.values(), key=lambda value: int(value["itemSetId"])):
        item_set_id = int(candidate["itemSetId"])
        decision = decisions[str(candidate["candidateKey"])]
        active = decision.get("decision") == "accepted"
        normalized_row = active_by_item_set_id.get(item_set_id)
        require(active == (normalized_row is not None),
                f"normalized active state differs from review decision: itemset:{item_set_id}")
        presentation = resolve_presentation(candidate, int(normalized_row["collectionId"]) if normalized_row else 0,
                                            matching_rule(item_set_id, rules))
        review_rows.append({
            "candidateKey": candidate["candidateKey"],
            "itemSetId": item_set_id,
            "active": "true" if active else "false",
            "presentationStatus": presentation["status"],
            "expansion": presentation["expansion"],
            "acquisition": presentation["acquisition"],
            "raidTier": presentation["raidTier"],
            "difficulty": presentation["difficulty"],
            "medianItemLevel": presentation["sortRank"]["medianItemLevel"],
            "ruleKey": presentation["ruleKey"],
            "reasonCode": presentation["reasonCode"],
        })
        if active:
            presentations.append(presentation)
    require(len(presentations) == 465, "presentation output lost active ItemSets")
    require(len({row["collectionId"] for row in presentations}) == len(presentations),
            "duplicate active ItemSet presentation collection ID")
    output = {
        "schemaVersion": 1,
        "mappingHash": normalized["mappingHash"],
        "itemSetEvidenceHash": evidence["candidateHash"],
        "reviewPolicyHash": canonical_hash(policy),
        "presentationHash": canonical_hash(presentations),
        "presentations": presentations,
    }
    return output, review_rows


def outputs(repo_root: Path, output: dict[str, Any], review_rows: list[dict[str, Any]]) -> dict[Path, bytes]:
    fields = [
        "candidateKey", "itemSetId", "active", "presentationStatus", "expansion", "acquisition", "raidTier",
        "difficulty", "medianItemLevel", "ruleKey", "reasonCode",
    ]
    return {
        repo_root / "catalog/generated/set-presentations.json": pretty_json(output).encode("utf-8"),
        repo_root / "catalog/generated/set-presentation-review.csv": csv_bytes(review_rows, fields),
    }


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("command", nargs="?", choices=("generate", "check"), default="generate")
    parser.add_argument("--repo-root", type=Path, default=Path(__file__).resolve().parents[2])
    args = parser.parse_args(argv)
    try:
        repo_root = args.repo_root.resolve()
        output, review_rows = build(repo_root)
        for path, content in outputs(repo_root, output, review_rows).items():
            if args.command == "check":
                require(path.is_file() and path.read_bytes().replace(b"\r\n", b"\n") == content,
                        f"generated set presentation output is stale: {path}")
            else:
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_bytes(content)
        print(f"set presentations: active={len(output['presentations'])} hash={output['presentationHash']}")
        return 0
    except (OSError, SetPresentationError) as exc:
        print(f"set presentation error: {exc}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
