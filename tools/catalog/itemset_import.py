#!/usr/bin/env python3
"""Extract, review, and normalize the WotLK ItemSet catalog."""

from __future__ import annotations

import argparse
import csv
import hashlib
import io
import json
import os
import re
import struct
import subprocess
import sys
from pathlib import Path
from typing import Any


SOURCE_BUILD = "3.3.5.12340"
CLASS_KEYS = {
    1: "warrior", 2: "paladin", 3: "hunter", 4: "rogue", 5: "priest",
    6: "death_knight", 7: "shaman", 8: "mage", 9: "warlock", 11: "druid",
}
PLAYABLE_CLASS_MASK = sum(1 << (class_id - 1) for class_id in CLASS_KEYS)
VISIBLE_SLOTS = {
    "HEAD", "SHOULDER", "BACK", "CHEST", "ROBE", "WRIST", "HANDS", "WAIST",
    "LEGS", "FEET", "MAINHAND", "OFFHAND", "RANGED", "SHIRT", "TABARD",
}
SLOT_ORDER = {
    key: index for index, key in enumerate((
        "HEAD", "SHOULDER", "BACK", "CHEST", "ROBE", "WRIST", "HANDS", "WAIST",
        "LEGS", "FEET", "MAINHAND", "OFFHAND", "RANGED", "SHIRT", "TABARD",
    ))
}
OLD_SET_IDENTITIES = {
    201: (300000, "set.arcanist_regalia", 18499),
    203: (300001, "set.felheart_raiment", 18500),
    204: (300002, "set.nightslayer_armor", 18501),
    205: (300003, "set.cenarion_raiment", 18502),
    206: (300004, "set.giantstalker_armor", 18503),
    207: (300005, "set.earthfury", 18504),
    208: (300006, "set.lawbringer_armor", 18505),
    209: (300007, "set.battlegear_of_might", 18506),
}


class ItemSetImportError(ValueError):
    pass


def require(condition: bool, message: str) -> None:
    if not condition:
        raise ItemSetImportError(message)


def read_json(path: Path) -> Any:
    try:
        return json.loads(path.read_text(encoding="utf-8-sig"))
    except (OSError, json.JSONDecodeError) as exc:
        raise ItemSetImportError(f"cannot read JSON {path}: {exc}") from exc


def pretty_json(value: Any) -> str:
    return json.dumps(value, ensure_ascii=False, sort_keys=True, indent=2) + "\n"


def canonical_hash(value: Any) -> str:
    return hashlib.sha256((json.dumps(value, ensure_ascii=False, sort_keys=True,
        separators=(",", ":")) + "\n").encode("utf-8")).hexdigest()


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for block in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def verify_evidence_root(root: Path) -> tuple[dict[str, Any], dict[str, Path]]:
    root = root.resolve()
    if os.name == "nt":
        require(root.drive.upper() == "F:", "ItemSet evidence root must stay on F:")
    manifest = read_json(root / "evidence-manifest.json")
    require(manifest.get("schemaVersion") == 1, "unsupported evidence manifest schema")
    files: dict[str, Path] = {}
    for entry in manifest.get("files", []):
        relative = str(entry.get("relativePath", "")).replace("\\", "/")
        require(relative and relative not in files, f"invalid evidence member: {relative!r}")
        path = root / Path(relative)
        require(path.is_file(), f"missing evidence member: {relative}")
        require(path.stat().st_size == int(entry.get("size", -1)), f"evidence size drift: {relative}")
        require(sha256(path) == entry.get("sha256"), f"evidence hash drift: {relative}")
        files[relative] = path
    for relative in ("dbc/ItemSet.dbc", "repository/catalog/generated/appearance-sources.json"):
        require(relative in files, f"missing ItemSet evidence member: {relative}")
    canonical = "".join(
        f"{relative}\0{files[relative].stat().st_size}\0{sha256(files[relative])}\n"
        for relative in sorted(files)
    ).encode("utf-8")
    require(hashlib.sha256(canonical).hexdigest() == manifest.get("packHash"), "evidence pack hash is stale")
    return manifest, files


def read_dbc(path: Path) -> tuple[list[tuple[int, ...]], bytes]:
    data = path.read_bytes()
    require(len(data) >= 20 and data[:4] == b"WDBC", f"not a WDBC file: {path}")
    row_count, field_count, record_size, string_size = struct.unpack_from("<4I", data, 4)
    require(field_count == 53 and record_size == 212, "ItemSet.dbc schema is not 3.3.5a")
    records_end = 20 + row_count * record_size
    require(records_end + string_size == len(data), "ItemSet.dbc is truncated or extended")
    rows = [struct.unpack_from("<53I", data, 20 + index * record_size) for index in range(row_count)]
    return rows, data[records_end:]


def dbc_string(block: bytes, offset: int) -> str:
    if offset <= 0 or offset >= len(block):
        return ""
    end = block.find(b"\0", offset)
    require(end >= 0, f"unterminated ItemSet string at {offset}")
    return block[offset:end].decode("utf-8", errors="replace")


def parse_world_database_info(config: Path) -> tuple[str, str, str, str, str]:
    text = config.read_text(encoding="utf-8-sig", errors="replace")
    match = re.search(r'^\s*WorldDatabaseInfo\s*=\s*"([^"]+)"', text, re.MULTILINE)
    require(match is not None, f"WorldDatabaseInfo missing from {config}")
    parts = match.group(1).split(";")
    require(len(parts) >= 5, "WorldDatabaseInfo has an unexpected format")
    return parts[0], parts[1], parts[2], parts[3], parts[4]


def mysql_rows(mysql: Path, config: Path, query: str) -> list[list[str]]:
    host, port, user, password, database = parse_world_database_info(config)
    environment = os.environ.copy()
    environment["MYSQL_PWD"] = password
    result = subprocess.run(
        [str(mysql), f"--host={host}", f"--port={port}", f"--user={user}", f"--database={database}",
         "--default-character-set=utf8mb4", "--batch", "--raw", "--skip-column-names", "--execute", query],
        check=False, capture_output=True, text=True, encoding="utf-8", errors="replace", env=environment,
    )
    require(result.returncode == 0, f"World DB query failed: {result.stderr.strip()}")
    return [line.split("\t") for line in result.stdout.splitlines() if line]


def normalize_mask(value: int) -> int:
    if value < 0 or value == 0 or (value & PLAYABLE_CLASS_MASK) == PLAYABLE_CLASS_MASK:
        return PLAYABLE_CLASS_MASK
    return value & PLAYABLE_CLASS_MASK


def class_policy(member_masks: list[int]) -> dict[str, Any]:
    if not member_masks:
        return {"mode": "UNRESOLVED", "allowedClassKeys": []}
    allowed = PLAYABLE_CLASS_MASK
    for mask in member_masks:
        allowed &= mask
    if allowed == 0:
        return {"mode": "UNRESOLVED", "allowedClassKeys": []}
    if allowed == PLAYABLE_CLASS_MASK:
        return {"mode": "ANY", "allowedClassKeys": []}
    return {"mode": "ALLOW_LIST", "allowedClassKeys": [
        key for class_id, key in CLASS_KEYS.items() if allowed & (1 << (class_id - 1))
    ]}


def numeric_summary(values: list[int]) -> dict[str, Any]:
    """Return a deterministic min/max/median summary for reviewed ItemSet inputs.

    The ItemSet DBC only references member item IDs.  Item level and quality
    live in the world DB snapshot, so keeping the aggregate here gives the
    later presentation sorter evidence without leaking it into set identity or
    server-owned mapping fields.
    """
    ordered = sorted(int(value) for value in values if int(value) > 0)
    if not ordered:
        return {"count": 0, "min": None, "max": None, "median": None}
    midpoint = len(ordered) // 2
    if len(ordered) % 2:
        median: int | float = ordered[midpoint]
    else:
        median = (ordered[midpoint - 1] + ordered[midpoint]) / 2
    return {
        "count": len(ordered),
        "min": ordered[0],
        "max": ordered[-1],
        "median": median,
    }


def csv_bytes(rows: list[dict[str, Any]], fields: list[str]) -> bytes:
    stream = io.StringIO(newline="")
    writer = csv.DictWriter(stream, fieldnames=fields, lineterminator="\n")
    writer.writeheader()
    writer.writerows(rows)
    return stream.getvalue().encode("utf-8")


def extract(repo_root: Path, evidence_root: Path, out: Path, mysql: Path, config: Path) -> dict[str, Any]:
    manifest, files = verify_evidence_root(evidence_root)
    rows, strings = read_dbc(files["dbc/ItemSet.dbc"])
    require(len(rows) == 509, f"expected 509 ItemSet rows, found {len(rows)}")
    appearance_catalog = read_json(repo_root / "catalog/generated/appearance-sources.json")
    packed_appearances = read_json(files["repository/catalog/generated/appearance-sources.json"])
    require(appearance_catalog.get("mappingHash") == packed_appearances.get("mappingHash"),
            "appearance mapping differs from named evidence pack")
    appearance_by_item: dict[int, dict[str, Any]] = {}
    for group in appearance_catalog.get("groups", []):
        if group.get("lifecycle") != "active":
            continue
        for item_id in group.get("sourceItemIds", []):
            require(int(item_id) not in appearance_by_item, f"appearance source mapped twice: {item_id}")
            appearance_by_item[int(item_id)] = group

    db_items: dict[int, dict[str, Any]] = {}
    query = ("SELECT entry,itemset,AllowableClass,InventoryType,COALESCE(name,''),displayid,ItemLevel,Quality "
             "FROM item_template WHERE itemset<>0 ORDER BY entry")
    for values in mysql_rows(mysql, config, query):
        db_items[int(values[0])] = {
            "itemId": int(values[0]), "itemSetId": int(values[1]), "allowableClass": int(values[2]),
            "inventoryType": int(values[3]), "name": values[4], "displayId": int(values[5]),
            "itemLevel": int(values[6]), "quality": int(values[7]),
        }
    snapshot_rows = [db_items[key] for key in sorted(db_items)]
    snapshot_hash = canonical_hash(snapshot_rows)

    candidates: list[dict[str, Any]] = []
    decisions: list[dict[str, Any]] = []
    for row in rows:
        item_set_id = int(row[0])
        name_offsets = [int(value) for value in row[1:17] if value]
        name = dbc_string(strings, name_offsets[0]) if name_offsets else f"ItemSet {item_set_id}"
        dbc_items = [int(value) for value in row[18:35] if value]
        members_by_slot: dict[str, dict[str, Any]] = {}
        omissions: list[dict[str, Any]] = []
        missing: list[int] = []
        missing_item_levels: list[int] = []
        item_levels: list[int] = []
        qualities: list[int] = []
        for item_id in dbc_items:
            appearance = appearance_by_item.get(item_id)
            db_item = db_items.get(item_id)
            if db_item is None or int(db_item.get("itemLevel", 0)) <= 0:
                missing_item_levels.append(item_id)
            else:
                item_levels.append(int(db_item["itemLevel"]))
            if db_item is not None and int(db_item.get("quality", -1)) >= 0:
                qualities.append(int(db_item["quality"]))
            if appearance is None:
                omissions.append({"itemId": item_id, "reason": "NO_CANONICAL_APPEARANCE"})
                if db_item and db_item.get("inventoryType") not in {0, 2, 11, 12, 16, 18, 28}:
                    missing.append(item_id)
                continue
            slot_key = str(appearance.get("slotKey", ""))
            if slot_key not in VISIBLE_SLOTS:
                omissions.append({"itemId": item_id, "reason": "NON_VISIBLE_MEMBER", "slotKey": slot_key})
                continue
            member = members_by_slot.setdefault(slot_key, {
                "memberKey": slot_key.lower(), "slotKey": slot_key, "required": True,
                "appearanceIds": [], "sourceItemIds": [], "classMaskUnion": 0,
            })
            appearance_id = int(appearance["appearanceId"])
            if appearance_id not in member["appearanceIds"]:
                member["appearanceIds"].append(appearance_id)
            member["sourceItemIds"].append(item_id)
            mask = normalize_mask(int((db_item or appearance).get("allowableClass", -1)))
            member["classMaskUnion"] |= mask
        members = sorted(members_by_slot.values(), key=lambda value: (SLOT_ORDER[value["slotKey"]], value["memberKey"]))
        for member in members:
            member["appearanceIds"].sort()
            member["sourceItemIds"].sort()
        policy = class_policy([member["classMaskUnion"] for member in members])
        for member in members:
            member.pop("classMaskUnion")
        distinct_appearances = len({appearance_id for member in members for appearance_id in member["appearanceIds"]})
        decision = "accepted"
        reason = "COMPLETE_VISIBLE_MAPPING_AND_RESOLVED_CLASS_POLICY"
        if len(dbc_items) == 0:
            decision, reason = "excluded", "EMPTY_ITEMSET_ROW"
        elif distinct_appearances < 2:
            decision, reason = "deferred", "FEWER_THAN_TWO_VISIBLE_CANONICAL_APPEARANCES"
        elif missing:
            decision, reason = "deferred", "VISIBLE_MEMBER_MAPPING_IS_PARTIAL"
        elif policy["mode"] == "UNRESOLVED":
            decision, reason = "deferred", "CLASS_POLICY_INTERSECTION_IS_EMPTY"
        candidate = {
            "candidateKey": f"itemset:{item_set_id}", "itemSetId": item_set_id, "name": name,
            "dbcItemIds": dbc_items, "members": members, "omissions": sorted(omissions, key=lambda value: value["itemId"]),
            "missingVisibleItemIds": sorted(missing), "classPolicy": policy,
            "visibleMemberCount": len(members), "distinctAppearanceCount": distinct_appearances,
            "itemLevel": numeric_summary(item_levels),
            "quality": numeric_summary(qualities),
            "missingItemLevelIds": sorted(missing_item_levels),
        }
        candidates.append(candidate)
        decisions.append({"candidateKey": candidate["candidateKey"], "decision": decision, "reasonCode": reason})

    counters = {
        "rawRows": len(candidates), "reviewUnits": len(candidates),
        "nonempty": sum(bool(row["dbcItemIds"]) for row in candidates),
        "mapped": sum(row["distinctAppearanceCount"] >= 2 for row in candidates),
        "distinctSignatures": len({tuple((member["slotKey"], tuple(member["appearanceIds"])) for member in row["members"])
                                   for row in candidates if row["members"]}),
        "full": sum(bool(row["dbcItemIds"]) and not row["missingVisibleItemIds"] and row["distinctAppearanceCount"] >= 2
                    for row in candidates),
        "partial": sum(bool(row["missingVisibleItemIds"]) for row in candidates),
        "unresolved": sum(row["classPolicy"]["mode"] == "UNRESOLVED" for row in candidates),
        "variants": sum(row["distinctAppearanceCount"] >= 2 and not row["missingVisibleItemIds"] and
                        row["classPolicy"]["mode"] != "UNRESOLVED" for row in candidates),
    }
    candidate_hash = canonical_hash(candidates)
    evidence = {
        "schemaVersion": 3, "sourceBuild": SOURCE_BUILD, "evidenceId": manifest["evidenceId"],
        "evidencePackHash": manifest["packHash"], "itemSetDbcSha256": sha256(files["dbc/ItemSet.dbc"]),
        "itemTemplateSnapshotSha256": snapshot_hash, "appearanceMappingHash": appearance_catalog["mappingHash"],
        "candidateHash": candidate_hash, "expectedCounters": counters, "candidates": candidates,
    }
    policy = {"schemaVersion": 1, "candidateHash": candidate_hash, "decisions": decisions}
    candidate_rows = [{
        "candidateKey": row["candidateKey"], "itemSetId": row["itemSetId"], "name": row["name"],
        "dbcItems": len(row["dbcItemIds"]), "visibleMembers": row["visibleMemberCount"],
        "appearances": row["distinctAppearanceCount"], "classMode": row["classPolicy"]["mode"],
        "decision": decisions[index]["decision"], "reasonCode": decisions[index]["reasonCode"],
    } for index, row in enumerate(candidates)]
    exclusions = [row for row in candidate_rows if row["decision"] != "accepted"]
    out.mkdir(parents=True, exist_ok=True)
    (out / "evidence.json").write_text(pretty_json(evidence), encoding="utf-8", newline="\n")
    (out / "review-policy.json").write_text(pretty_json(policy), encoding="utf-8", newline="\n")
    fields = ["candidateKey", "itemSetId", "name", "dbcItems", "visibleMembers", "appearances", "classMode", "decision", "reasonCode"]
    (out / "itemset-candidates.csv").write_bytes(csv_bytes(candidate_rows, fields))
    (out / "itemset-exclusions.csv").write_bytes(csv_bytes(exclusions, fields))
    print("ItemSet extract: " + " ".join(f"{key}={value}" for key, value in counters.items()))
    return evidence


def _validate_review(evidence: dict[str, Any], review: dict[str, Any]) -> dict[str, dict[str, Any]]:
    require(evidence.get("schemaVersion") in {2, 3} and review.get("schemaVersion") == 1,
            "unsupported ItemSet review schema")
    require(review.get("candidateHash") == evidence.get("candidateHash"), "ItemSet review candidate hash drift")
    candidates = {row["candidateKey"]: row for row in evidence.get("candidates", [])}
    decisions = {row["candidateKey"]: row for row in review.get("decisions", [])}
    require(len(candidates) == 509 and set(candidates) == set(decisions), "every ItemSet review unit needs one decision")
    for key, decision in decisions.items():
        require(decision.get("decision") in {"accepted", "excluded", "deferred"}, f"invalid decision: {key}")
        require(bool(decision.get("reasonCode")), f"missing decision reason: {key}")
        if decision["decision"] == "accepted":
            candidate = candidates[key]
            require(candidate["distinctAppearanceCount"] >= 2 and not candidate["missingVisibleItemIds"],
                    f"partial ItemSet cannot be active: {key}")
            require(candidate["classPolicy"]["mode"] != "UNRESOLVED", f"unresolved ItemSet cannot be active: {key}")
    return decisions


def build_normalized(repo_root: Path, evidence: dict[str, Any], review: dict[str, Any], ids: dict[str, Any]) -> tuple[dict[str, Any], dict[str, Any]]:
    decisions = _validate_review(evidence, review)
    candidates = {row["candidateKey"]: row for row in evidence["candidates"]}
    reservations = ids["reservations"]["collections"]
    by_key = {row["key"]: row for row in reservations}
    max_set_id = max([row["id"] for row in reservations if str(row["key"]).startswith("set.")] or [299999])
    max_ordinal = max(row["ordinal"] for row in reservations)
    normalized_sets: list[dict[str, Any]] = []
    for candidate in sorted(candidates.values(), key=lambda value: value["itemSetId"]):
        if decisions[candidate["candidateKey"]]["decision"] != "accepted":
            continue
        item_set_id = candidate["itemSetId"]
        if item_set_id in OLD_SET_IDENTITIES:
            collection_id, collection_key, ordinal = OLD_SET_IDENTITIES[item_set_id]
        else:
            collection_key = f"set.itemset.{item_set_id}"
            reservation = by_key.get(collection_key)
            if reservation is None:
                max_set_id += 1
                max_ordinal += 1
                reservation = {"id": max_set_id, "key": collection_key, "lifecycle": "active", "ordinal": max_ordinal}
                reservations.append(reservation)
                by_key[collection_key] = reservation
            collection_id, ordinal = int(reservation["id"]), int(reservation["ordinal"])
        normalized_sets.append({
            "collectionId": collection_id, "collectionKey": collection_key, "ordinal": ordinal,
            "itemSetId": item_set_id, "catalogLifecycle": "ACTIVE", "uiLifecycle": "public",
            "classPolicy": candidate["classPolicy"],
            "name": {"enUS": candidate["name"], "zhCN": candidate["name"]},
            "iconItemId": candidate["members"][0]["sourceItemIds"][0],
            "variants": [{
                "variantKey": "default", "variantOrdinal": 1, "isDefault": True, "lifecycle": "ACTIVE",
                "members": candidate["members"], "omissions": candidate["omissions"],
            }],
        })
    reservations.sort(key=lambda row: (int(row["ordinal"]), str(row["key"])))
    review_policy_hash = canonical_hash(review)
    basis = [{
        "collectionId": row["collectionId"], "collectionKey": row["collectionKey"], "itemSetId": row["itemSetId"],
        "catalogLifecycle": row["catalogLifecycle"], "classPolicy": row["classPolicy"],
        "variants": [{
            "variantOrdinal": variant["variantOrdinal"], "variantKey": variant["variantKey"],
            "isDefault": variant["isDefault"], "lifecycle": variant["lifecycle"],
            "members": [{key: member[key] for key in ("memberKey", "slotKey", "required", "appearanceIds")}
                        for member in variant["members"]],
            "omissions": variant["omissions"],
        } for variant in row["variants"]],
    } for row in normalized_sets]
    model = {
        "schemaVersion": 2,
        "sourceEvidence": {
            "itemSetDbcSha256": evidence["itemSetDbcSha256"],
            "itemTemplateSnapshotSha256": evidence["itemTemplateSnapshotSha256"],
            "appearanceMappingHash": evidence["appearanceMappingHash"],
            "reviewPolicyHash": review_policy_hash,
        },
        "expectedCounters": evidence["expectedCounters"],
        "mappingHash": canonical_hash(basis), "presentationHash": canonical_hash(normalized_sets),
        "sets": normalized_sets,
    }
    return model, ids


def render_collection_csv(model: dict[str, Any]) -> bytes:
    fields = ["typeKey", "collectionId", "collectionKey", "ordinal", "lifecycle", "name_enUS", "name_zhCN",
              "policyKey", "sourceBuild", "sourceKind", "sourceId", "actionKind", "actionId", "assetReady",
              "assetProfile", "aliases"]
    rows = []
    for row in model["sets"]:
        rows.append({
            "typeKey": "set", "collectionId": row["collectionId"], "collectionKey": row["collectionKey"],
            "ordinal": row["ordinal"], "lifecycle": "active", "name_enUS": row["name"]["enUS"],
            "name_zhCN": row["name"]["zhCN"], "policyKey": "unrestricted", "sourceBuild": SOURCE_BUILD,
            "sourceKind": "item_set", "sourceId": row["itemSetId"], "actionKind": "APPLY",
            "actionId": row["collectionId"], "assetReady": "true", "assetProfile": "wotlk_native",
            "aliases": f"itemset:{row['itemSetId']}|variant:1",
        })
    return csv_bytes(rows, fields)


def promote(repo_root: Path, review_root: Path) -> dict[str, Any]:
    evidence = read_json(review_root / "evidence.json")
    review = read_json(review_root / "review-policy.json")
    ids = read_json(repo_root / "catalog/ids.json")
    model, ids = build_normalized(repo_root, evidence, review, ids)
    manual8_sets = [row for row in model["sets"] if row["itemSetId"] in OLD_SET_IDENTITIES]
    manual8 = {
        "schemaVersion": 2, "profile": "manual8", "sourceCommit": "13689d0",
        "mappingHash": canonical_hash(manual8_sets), "sets": manual8_sets,
    }
    destinations = {
        repo_root / "catalog/review/sets/evidence.json": (review_root / "evidence.json").read_bytes(),
        repo_root / "catalog/review/sets/review-policy.json": (review_root / "review-policy.json").read_bytes(),
        repo_root / "catalog/generated/itemset-candidates.csv": (review_root / "itemset-candidates.csv").read_bytes(),
        repo_root / "catalog/generated/itemset-exclusions.csv": (review_root / "itemset-exclusions.csv").read_bytes(),
        repo_root / "catalog/generated/normalized-itemsets.json": pretty_json(model).encode("utf-8"),
        repo_root / "catalog/generated/set-id-registry-view.json": pretty_json({
            "schemaVersion": 1, "sets": [row for row in ids["reservations"]["collections"]
                                          if str(row["key"]).startswith("set.")]
        }).encode("utf-8"),
        repo_root / "catalog/ids.json": pretty_json(ids).encode("utf-8"),
        repo_root / "catalog/source/collections/sets.csv": render_collection_csv(model),
        repo_root / "catalog/fixtures/sets/manual8.normalized.json": pretty_json(manual8).encode("utf-8"),
    }
    for path, content in destinations.items():
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(content)
    print(f"ItemSet promoted: active={len(model['sets'])} hash={model['mappingHash']}")
    return model


def verify_tracked(repo_root: Path, evidence_root: Path | None = None) -> dict[str, Any]:
    evidence = read_json(repo_root / "catalog/review/sets/evidence.json")
    review = read_json(repo_root / "catalog/review/sets/review-policy.json")
    ids = read_json(repo_root / "catalog/ids.json")
    model, _ = build_normalized(repo_root, evidence, review, ids)
    require(pretty_json(model).encode("utf-8") == (repo_root / "catalog/generated/normalized-itemsets.json").read_bytes(),
            "normalized ItemSet output drift")
    require(render_collection_csv(model) == (repo_root / "catalog/source/collections/sets.csv").read_bytes().replace(b"\r\n", b"\n"),
            "ItemSet collection projection drift")
    counters = evidence["expectedCounters"]
    require(counters["rawRows"] == 509 and counters["reviewUnits"] == 509, "ItemSet review denominator drift")
    decisions = _validate_review(evidence, review)
    require(sum(value["decision"] in {"accepted", "excluded", "deferred"} for value in decisions.values()) == 509,
            "ItemSet review coverage drift")
    if evidence.get("schemaVersion") == 3:
        for candidate in evidence["candidates"]:
            item_level = candidate.get("itemLevel")
            quality = candidate.get("quality")
            require(isinstance(item_level, dict) and isinstance(quality, dict),
                    f"ItemSet presentation evidence missing: {candidate.get('candidateKey')}")
            if decisions[str(candidate["candidateKey"])]["decision"] == "accepted":
                require(int(item_level.get("count", 0)) > 0,
                        f"ItemSet has no item-level evidence: {candidate.get('candidateKey')}")
    priest = next((row for row in model["sets"] if row["itemSetId"] == 202), None)
    require(priest is not None and len(priest["variants"][0]["members"]) == 8, "Priest T1 fixture drift")
    for item_set_id, identity in OLD_SET_IDENTITIES.items():
        row = next((value for value in model["sets"] if value["itemSetId"] == item_set_id), None)
        require(row is not None and (row["collectionId"], row["collectionKey"], row["ordinal"]) == identity,
                f"Manual8 identity drift: {item_set_id}")
    if evidence_root is not None:
        manifest, files = verify_evidence_root(evidence_root)
        require(sha256(files["dbc/ItemSet.dbc"]) == evidence["itemSetDbcSha256"], "ItemSet.dbc hash drift")
        for relative in (
            "catalog/review/sets/evidence.json", "catalog/review/sets/review-policy.json",
            "catalog/generated/itemset-candidates.csv", "catalog/generated/itemset-exclusions.csv",
            "catalog/generated/normalized-itemsets.json", "catalog/generated/set-id-registry-view.json",
        ):
            packed = files.get("repository/" + relative)
            if packed is not None:
                require(packed.read_bytes().replace(b"\r\n", b"\n") ==
                        (repo_root / relative).read_bytes().replace(b"\r\n", b"\n"),
                        f"packed ItemSet review output drift: {relative}")
    print(f"ItemSet check: review=509 active={len(model['sets'])} hash={model['mappingHash']}")
    return model


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("command", nargs="?", choices=("extract", "generate", "check", "profile"))
    parser.add_argument("--repo-root", type=Path, default=Path(__file__).resolve().parents[2])
    parser.add_argument("--evidence-root", type=Path)
    parser.add_argument("--out", type=Path)
    parser.add_argument("--review-root", type=Path)
    parser.add_argument("--mysql", type=Path)
    parser.add_argument("--worldserver-config", type=Path)
    parser.add_argument("--profile", choices=("manual8",))
    parser.add_argument("--output", type=Path)
    args = parser.parse_args(argv)
    try:
        if args.command is None and args.profile is not None:
            args.command = "profile"
        require(args.command is not None, "command is required")
        repo_root = args.repo_root.resolve()
        if args.command == "extract":
            require(all((args.evidence_root, args.out, args.mysql, args.worldserver_config)),
                    "extract requires --evidence-root, --out, --mysql and --worldserver-config")
            extract(repo_root, args.evidence_root.resolve(), args.out.resolve(), args.mysql.resolve(),
                    args.worldserver_config.resolve())
        elif args.command == "generate":
            require(args.review_root is not None, "generate requires --review-root")
            promote(repo_root, args.review_root.resolve())
        elif args.command == "check":
            verify_tracked(repo_root, args.evidence_root.resolve() if args.evidence_root else None)
        else:
            require(args.profile == "manual8" and args.output is not None,
                    "profile requires --profile manual8 and --output")
            fixture = repo_root / "catalog/fixtures/sets/manual8.normalized.json"
            require(fixture.is_file(), "Manual8 fixture is missing")
            output = args.output.resolve()
            if os.name == "nt": require(output.drive.upper() == "F:", "Manual8 output must stay on F:")
            output.parent.mkdir(parents=True, exist_ok=True)
            output.write_bytes(fixture.read_bytes())
            print(f"Manual8 profile rebuilt: {output}")
        return 0
    except (OSError, ItemSetImportError) as exc:
        print(f"ItemSet error: {exc}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
