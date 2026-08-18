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
TIER_RANK = {
    "NONE": 0, "T0": 0.1, "T0.5": 0.5, "T1": 1, "T2": 2, "T2.5": 2.5,
    "D3": 3.1, "T3": 3, "T4": 4, "T5": 5, "T6": 6, "T7": 7, "T8": 8,
    "T9": 9, "T10": 10,
}
SEASON_RANK = {
    "NONE": 0, "S1": 1, "S2": 2, "S3": 3, "S4": 4,
    "S5": 5, "S6": 6, "S7": 7, "S8": 8,
}
DIFFICULTY_RANK = {"UNKNOWN": 0, "DUNGEON": 1, "RAID": 2, "HIGH": 3, "HEROIC": 4}
CLASS_KEYS = {
    "warrior", "paladin", "hunter", "rogue", "priest", "death_knight",
    "shaman", "mage", "warlock", "druid",
}


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


def validate_class_policy(policy: Any, key: str) -> None:
    if policy is None:
        return
    require(isinstance(policy, dict), f"classPolicy must be an object for {key}")
    mode = policy.get("mode")
    classes = policy.get("allowedClassKeys")
    require(mode in {"ANY", "ALLOW_LIST"}, f"invalid classPolicy mode for {key}")
    require(isinstance(classes, list), f"classPolicy allowedClassKeys must be a list for {key}")
    require(len(classes) == len(set(classes)), f"duplicate classPolicy allowedClassKeys for {key}")
    for class_key in classes:
        require(class_key in CLASS_KEYS, f"invalid class key in {key}: {class_key}")
    require((mode == "ALLOW_LIST") == bool(classes), f"invalid classPolicy payload for {key}")


def rule_item_set_ids(rule: dict[str, Any], key: str) -> list[int]:
    bounds = rule.get("itemSetIdRange")
    explicit = rule.get("itemSetIds")
    require((bounds is None) != (explicit is None), f"{key} needs exactly one ItemSet selector")
    if explicit is not None:
        require(isinstance(explicit, list) and explicit, f"invalid ItemSet list for {key}")
        values = [int(value) for value in explicit]
        require(all(value > 0 for value in values), f"invalid ItemSet ID in {key}")
        require(len(values) == len(set(values)), f"duplicate ItemSet ID in {key}")
        return values
    require(isinstance(bounds, list) and len(bounds) == 2, f"invalid ItemSet range for {key}")
    lower, upper = int(bounds[0]), int(bounds[1])
    require(lower > 0 and lower <= upper, f"invalid ItemSet bounds for {key}")
    return list(range(lower, upper + 1))


def validate_policy(policy: dict[str, Any]) -> list[dict[str, Any]]:
    require(policy.get("schemaVersion") == 1, "unsupported set presentation policy schema")
    rules = policy.get("rules")
    require(isinstance(rules, list), "set presentation policy has no rules")
    seen_keys: set[str] = set()
    covered_ids: set[int] = set()
    for rule in rules:
        key = str(rule.get("key", ""))
        require(key and key not in seen_keys, f"duplicate or missing set presentation rule key: {key!r}")
        for item_set_id in rule_item_set_ids(rule, key):
            require(item_set_id not in covered_ids, f"overlapping presentation rule for ItemSet {item_set_id}")
            covered_ids.add(item_set_id)
        for field, options in (("expansion", EXPANSION_RANK), ("acquisition", ACQUISITION_RANK),
                               ("raidTier", TIER_RANK), ("difficulty", DIFFICULTY_RANK)):
            require(rule.get(field) in options, f"invalid {field} in {key}")
        season = rule.get("pvpSeason", "NONE")
        require(season in SEASON_RANK, f"invalid pvpSeason in {key}")
        require(bool(rule.get("reasonCode")), f"missing presentation reasonCode for {key}")
        if rule.get("displayLabel") is not None:
            require(isinstance(rule["displayLabel"], str) and rule["displayLabel"],
                    f"displayLabel must be a non-empty string for {key}")
        if rule.get("pvpSeries") is not None:
            require(isinstance(rule["pvpSeries"], str) and rule["pvpSeries"],
                    f"pvpSeries must be a non-empty string for {key}")
        validate_class_policy(rule.get("classPolicyOverride"), key)
        difficulty_bands = rule.get("difficultyBands", [])
        require(isinstance(difficulty_bands, list), f"difficultyBands must be a list for {key}")
        previous_minimum: int | float | None = None
        for band in difficulty_bands:
            require(isinstance(band, dict), f"invalid difficulty band in {key}")
            minimum = band.get("minimumMedianItemLevel")
            require(isinstance(minimum, (int, float)) and minimum > 0,
                    f"invalid minimumMedianItemLevel in {key}")
            require(previous_minimum is None or minimum > previous_minimum,
                    f"difficulty bands must be ascending in {key}")
            require(band.get("difficulty") in DIFFICULTY_RANK,
                    f"invalid difficulty band value in {key}")
            require(bool(band.get("reasonCode")), f"missing difficulty band reasonCode in {key}")
            previous_minimum = minimum
        seen_keys.add(key)
    return rules


def matching_rule(item_set_id: int, rules: list[dict[str, Any]]) -> dict[str, Any] | None:
    for rule in rules:
        if item_set_id in rule_item_set_ids(rule, str(rule.get("key", ""))):
            return rule
    return None


def summary_value(summary: Any, key: str) -> int | float:
    if not isinstance(summary, dict):
        return 0
    value = summary.get(key)
    return value if isinstance(value, (int, float)) else 0


def resolve_rule_difficulty(rule: dict[str, Any], item_level: dict[str, Any]) -> tuple[str, str]:
    """Choose an evidence-backed difficulty band without inferring from names.

    The base rule is used unless a reviewed median item-level threshold matches.
    This is intentionally narrower than an encounter-mode guess: a source pack
    that does not expose a difficulty distinction remains at its base rank.
    """

    difficulty = str(rule["difficulty"])
    reason_code = str(rule["reasonCode"])
    median = summary_value(item_level, "median")
    for band in rule.get("difficultyBands", []):
        if median >= band["minimumMedianItemLevel"]:
            difficulty = str(band["difficulty"])
            reason_code = str(band["reasonCode"])
    return difficulty, reason_code


def resolve_presentation(candidate: dict[str, Any], collection_id: int, rule: dict[str, Any] | None) -> dict[str, Any]:
    item_set_id = int(candidate["itemSetId"])
    if rule is None:
        expansion = "UNKNOWN"
        acquisition = "UNKNOWN"
        tier = "NONE"
        season = "NONE"
        difficulty = "UNKNOWN"
        rule_key = "unclassified"
        reason_code = "NO_REVIEWED_ITEMSET_PRESENTATION_RULE"
        status = "UNKNOWN"
        display_label = ""
        pvp_series = ""
        class_policy_override = None
    else:
        expansion = str(rule["expansion"])
        acquisition = str(rule["acquisition"])
        tier = str(rule["raidTier"])
        season = str(rule.get("pvpSeason", "NONE"))
        difficulty, reason_code = resolve_rule_difficulty(rule, candidate.get("itemLevel") or {})
        rule_key = str(rule["key"])
        status = "REVIEWED"
        display_label = str(rule.get("displayLabel") or (season if season != "NONE" else tier if tier != "NONE" else ""))
        pvp_series = str(rule.get("pvpSeries") or "")
        class_policy_override = rule.get("classPolicyOverride")
    item_level = candidate.get("itemLevel") or {}
    quality = candidate.get("quality") or {}
    result = {
        "collectionId": collection_id,
        "itemSetId": item_set_id,
        "status": status,
        "ruleKey": rule_key,
        "reasonCode": reason_code,
        "expansion": expansion,
        "acquisition": acquisition,
        "raidTier": tier,
        "pvpSeason": season,
        "pvpSeries": pvp_series,
        "displayLabel": display_label,
        "difficulty": difficulty,
        "itemLevel": item_level,
        "quality": quality,
        "sortRank": {
            "expansion": EXPANSION_RANK[expansion],
            "acquisition": ACQUISITION_RANK[acquisition],
            "tier": TIER_RANK[tier],
            "season": SEASON_RANK[season],
            "difficulty": DIFFICULTY_RANK[difficulty],
            "medianItemLevel": summary_value(item_level, "median"),
            "maxItemLevel": summary_value(item_level, "max"),
        },
    }
    if class_policy_override is not None:
        result["classPolicyOverride"] = class_policy_override
    return result


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
            "pvpSeason": presentation["pvpSeason"],
            "displayLabel": presentation["displayLabel"],
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
        "pvpSeason", "displayLabel", "difficulty", "medianItemLevel", "ruleKey", "reasonCode",
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
