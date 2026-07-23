#!/usr/bin/env python3
"""Freeze and audit the non-production WotLK weapon resource shadow.

Only capture receives a client data path. Hydrate, audit, and check consume a
named evidence root, so review generation cannot silently read a developer's
arbitrary client installation. Extracted client assets remain in that external
evidence root and are never written into the repository.
"""

from __future__ import annotations

import argparse
import csv
import hashlib
import io
import json
import math
import os
import random
import shutil
import statistics
import struct
import subprocess
from collections import Counter, defaultdict
from copy import deepcopy
from pathlib import Path
from typing import Any, Iterable


SOURCE_BUILD = "3.3.5.12340"
EXPECTED_PUBLIC = 3690
EXPECTED_ALL = 5957
EXPECTED_RESERVED = 21
WOTLK_M2_VERSION = 264
M2_TEXTURE_DESCRIPTOR = 0x50
M2_TEXTURE_SIZE = 16
M2_REPLACEABLE_LOOKUP = 0x68
M2_BOUNDS = 0xA0
M2_CAMERA = 0x110
M2_CAMERA_LOOKUP = 0x118
OBJECT_SKIN = 2
WEAPON_SLOTS = {"MAINHAND", "OFFHAND"}
ARCHIVE_PRIORITY = (
    "patch-w.mpq", "patch-v.mpq", "patch-u.mpq", "patch-j.mpq",
    "patch-3.mpq", "patch-2.mpq", "patch.mpq", "lichking.mpq",
    "expansion.mpq", "common-2.mpq", "common.mpq",
)
REQUIRED_ARCHIVES = {
    "common.mpq", "common-2.mpq", "expansion.mpq", "lichking.mpq",
    "patch.mpq", "patch-2.mpq", "patch-3.mpq",
}
FAMILY_BY_SUBCLASS = {
    0: "ONE_HAND_AXE", 1: "TWO_HAND_AXE", 2: "BOW", 3: "GUN",
    4: "ONE_HAND_MACE", 5: "TWO_HAND_MACE", 6: "POLEARM",
    7: "ONE_HAND_SWORD", 8: "TWO_HAND_SWORD", 10: "STAFF",
    13: "FIST_WEAPON", 15: "DAGGER", 16: "THROWN", 18: "CROSSBOW",
    19: "WAND", 20: "FISHING_POLE",
}


class ShadowError(RuntimeError):
    pass


def require(value: bool, message: str) -> None:
    if not value:
        raise ShadowError(message)


def canonical(value: Any) -> bytes:
    return (json.dumps(value, ensure_ascii=False, sort_keys=True, separators=(",", ":")) + "\n").encode("utf-8")


def pretty(value: Any) -> str:
    return json.dumps(value, ensure_ascii=False, sort_keys=True, indent=2) + "\n"


def sha(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def read_json(path: Path) -> Any:
    try:
        return json.loads(path.read_text(encoding="utf-8-sig"))
    except (OSError, UnicodeDecodeError, json.JSONDecodeError) as exc:
        raise ShadowError(f"cannot read JSON {path}: {exc}") from exc


def write_text(path: Path, value: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    temp = path.with_name(path.name + ".tmp")
    temp.write_text(value, encoding="utf-8", newline="\n")
    os.replace(temp, path)


def ensure_f(path: Path, label: str) -> Path:
    value = path.resolve()
    if os.name == "nt":
        require(value.drive.upper() == "F:", f"{label} must be on F:, got {value}")
    return value


def norm(value: str) -> str:
    text = value.strip().replace("/", "\\").strip("\\")
    require(text and ":" not in text and not text.startswith("\\"), f"invalid MPQ path: {value!r}")
    return text.lower()


def name(value: str) -> str:
    return norm(value).rsplit("\\", 1)[-1]


def stem(value: str) -> str:
    leaf = name(value)
    return leaf.rsplit(".", 1)[0] if "." in leaf else leaf


def parent(value: str) -> str:
    value = norm(value)
    return value.rsplit("\\", 1)[0] if "\\" in value else ""


def evidence_asset_path(root: Path, internal: str) -> Path:
    return root / "asset-cache" / Path(*norm(internal).split("\\"))


def verify_hash_object(value: dict[str, Any], field: str) -> dict[str, Any]:
    copy = deepcopy(value)
    locked = copy.pop(field, None)
    require(isinstance(locked, str) and locked == hashlib.sha256(canonical(copy)).hexdigest(), f"{field} drift")
    return value


def verify_fixed_pack(root: Path) -> tuple[dict[str, Any], dict[str, Path]]:
    root = ensure_f(root, "fixed evidence root")
    manifest = read_json(root / "evidence-manifest.json")
    require(manifest.get("schemaVersion") == 1, "unsupported fixed evidence schema")
    members: dict[str, Path] = {}
    for row in manifest.get("files", []):
        relative = str(row.get("relativePath", "")).replace("\\", "/")
        path = root / Path(relative)
        require(relative and path.is_file() and relative not in members, f"missing fixed evidence: {relative}")
        require(path.stat().st_size == int(row.get("size", -1)) and sha(path) == row.get("sha256"),
                f"fixed evidence drift: {relative}")
        members[relative] = path
    payload = "".join(
        f"{relative}\0{members[relative].stat().st_size}\0{sha(members[relative])}\n"
        for relative in sorted(members)
    ).encode("utf-8")
    require(hashlib.sha256(payload).hexdigest() == manifest.get("packHash"), "fixed evidence pack hash drift")
    for dbc in ("dbc/Item.dbc", "dbc/ItemDisplayInfo.dbc"):
        require(dbc in members, f"fixed evidence lacks {dbc}")
    return manifest, members


def read_dbc(path: Path) -> tuple[dict[str, int], list[tuple[int, ...]], bytes]:
    data = path.read_bytes()
    require(len(data) >= 20 and data[:4] == b"WDBC", f"not WDBC: {path}")
    rows, fields, record_size, string_size = struct.unpack_from("<4I", data, 4)
    require(record_size == fields * 4 and 20 + rows * record_size + string_size == len(data),
            f"invalid DBC layout: {path}")
    records = [
        struct.unpack_from(f"<{fields}I", data, 20 + index * record_size)
        for index in range(rows)
    ]
    return {"rows": rows, "fields": fields, "recordSize": record_size, "stringSize": string_size}, records, data[20 + rows * record_size:]


def dbc_string(block: bytes, offset: int) -> str:
    if offset == 0:
        return ""
    require(0 <= offset < len(block), f"DBC string offset out of range: {offset}")
    end = block.find(b"\0", offset)
    require(end >= 0, f"unterminated DBC string: {offset}")
    return block[offset:end].decode("utf-8", errors="replace")


def read_displays(path: Path) -> dict[int, dict[str, Any]]:
    header, rows, strings = read_dbc(path)
    require((header["fields"], header["recordSize"]) == (25, 100), "unexpected ItemDisplayInfo schema")
    displays: dict[int, dict[str, Any]] = {}
    for row in rows:
        display_id = int(row[0])
        require(display_id not in displays, f"duplicate ItemDisplayInfo {display_id}")
        displays[display_id] = {
            "displayId": display_id,
            "leftModel": dbc_string(strings, row[1]),
            "rightModel": dbc_string(strings, row[2]),
            "leftTexture": dbc_string(strings, row[3]),
            "rightTexture": dbc_string(strings, row[4]),
            "inventoryIcon": dbc_string(strings, row[5]),
            "visual": {
                "geosetGroups": list(row[6:9]), "flags": int(row[9]),
                "spellVisualId": int(row[10]), "groupSoundIndex": int(row[11]),
                "helmetGeosetVis": list(row[12:14]), "textureIds": list(row[14:16]),
                "itemVisualIds": list(row[16:24]), "particleColorId": int(row[24]),
            },
        }
    return displays


def parse_sql_snapshot(path: Path, expected: dict[int, dict[str, Any]]) -> list[dict[str, int]]:
    require(path.is_file(), f"item_template SQL missing: {path}")
    found: dict[int, dict[str, int]] = {}
    with path.open("r", encoding="utf-8", errors="replace", newline="") as handle:
        for line in handle:
            if not line.startswith("("):
                continue
            body = line.strip()
            body = body[:-2] if body.endswith(");") else body[:-1] if body.endswith(",") else body
            if not body.startswith("("):
                continue
            row = next(csv.reader([body[1:]], quotechar="'", escapechar="\\"))
            if len(row) <= 15:
                continue
            entry = int(row[0])
            fact = expected.get(entry)
            if fact is None:
                continue
            current = {
                "entry": entry, "itemClass": int(row[1]), "itemSubclass": int(row[2]),
                "displayId": int(row[5]), "quality": int(row[6]),
                "inventoryType": int(row[12]), "itemLevel": int(row[15]),
            }
            for key in ("displayId", "quality", "inventoryType", "itemClass", "itemSubclass"):
                require(current[key] == int(fact[key]), f"item_template source drift: {entry}:{key}")
            require(entry not in found, f"duplicate item_template source: {entry}")
            found[entry] = current
    require(set(found) == set(expected), f"item_template coverage drift: expected {len(expected)}, got {len(found)}")
    return [found[key] for key in sorted(found)]


def candidate_basis(visibility: dict[str, Any], appearances: dict[str, Any], strict: bool = True) -> tuple[dict[str, Any], dict[int, dict[str, int]]]:
    require(visibility.get("schemaVersion") == 1 and appearances.get("schemaVersion") == 1, "unsupported appearance evidence")
    require(visibility.get("sourceBuild") == SOURCE_BUILD and appearances.get("sourceBuild") == SOURCE_BUILD,
            "appearance source build drift")
    require(visibility.get("appearanceMappingHash") == appearances.get("mappingHash"), "appearance mapping hash drift")
    facts: dict[int, dict[str, int]] = {}
    candidates: list[dict[str, Any]] = []
    seen: set[int] = set()
    for decision in visibility.get("decisions", []):
        if decision.get("slotKey") not in WEAPON_SLOTS:
            continue
        appearance_id = int(decision["appearanceId"])
        require(appearance_id not in seen, f"duplicate weapon appearance {appearance_id}")
        seen.add(appearance_id)
        source_items: list[dict[str, int]] = []
        for raw in decision.get("itemFacts", []):
            value = {
                "entry": int(raw["entry"]), "displayId": int(raw["displayId"]),
                "inventoryType": int(raw["inventoryType"]), "itemClass": int(raw["itemClass"]),
                "itemSubclass": int(raw["itemSubclass"]), "quality": int(raw["quality"]),
            }
            previous = facts.get(value["entry"])
            require(previous is None or previous == value, f"inconsistent item source {value['entry']}")
            facts[value["entry"]] = value
            source_items.append(value)
        primary = int(decision["primarySourceItemId"])
        require(primary in {item["entry"] for item in source_items}, f"missing primary item {appearance_id}")
        candidates.append({
            "appearanceId": appearance_id, "collectionKey": str(decision["collectionKey"]),
            "displayId": int(decision["displayId"]), "slotKey": str(decision["slotKey"]),
            "public": decision.get("uiLifecycle") == "public", "uiLifecycle": str(decision["uiLifecycle"]),
            "primarySourceItemId": primary, "sourceItems": sorted(source_items, key=lambda item: item["entry"]),
            "sourceItemIds": sorted(int(item) for item in decision.get("sourceItemIds", [])),
            "sourceReasonCode": str(decision.get("reasonCode", "")),
        })
    candidates.sort(key=lambda item: item["appearanceId"])
    public = sum(item["public"] for item in candidates)
    if strict:
        require(len(candidates) == EXPECTED_ALL and public == EXPECTED_PUBLIC,
                f"candidate denominator drift: all={len(candidates)} public={public}")
    result = {
        "schemaVersion": 1, "sourceBuild": SOURCE_BUILD,
        "appearanceMappingHash": visibility["appearanceMappingHash"],
        "visibilityDecisionHash": visibility.get("decisionHash"),
        "counts": {"all": len(candidates), "public": public}, "candidates": candidates,
    }
    result["candidateBasisHash"] = hashlib.sha256(canonical(result)).hexdigest()
    return result, facts


def reserved_import(source_path: Path, fixed: dict[str, Path], candidates: list[dict[str, Any]]) -> dict[str, Any]:
    source = read_json(source_path)
    entries = source.get("entries", [])
    require(source.get("schemaVersion") == 1 and len(entries) == EXPECTED_RESERVED,
            "production presentation baseline drift")
    weapon_manifest = fixed.get("weapon-resources/weapon-creature-build.json")
    verification = fixed.get("weapon-resources/weapon-model-verification.csv")
    require(weapon_manifest is not None and verification is not None, "fixed evidence lacks weapon baseline")
    require(sha(weapon_manifest) == source.get("weaponManifestSha256"), "weapon manifest hash drift")
    require(sha(verification) == source.get("verificationSha256"), "weapon verification hash drift")
    manifest = read_json(weapon_manifest)
    by_item = {int(row["item_id"]): row for row in manifest}
    require(len(by_item) == EXPECTED_RESERVED, "reserved weapon manifest drift")
    verified: dict[str, dict[str, str]] = {}
    with verification.open("r", encoding="utf-8-sig", newline="") as handle:
        for row in csv.DictReader(handle):
            path = norm(str(row["Path"]))
            require(row.get("Match", "").lower() == "true"
                    and row.get("StageLength") == row.get("VerifyLength")
                    and row.get("StageSHA256", "").lower() == row.get("VerifySHA256", "").lower(),
                    f"reserved asset verification drift: {path}")
            verified[path] = row
    candidate_by_id = {int(row["appearanceId"]): row for row in candidates}
    rows: list[dict[str, Any]] = []
    seen_models: set[int] = set()
    seen_displays: set[int] = set()
    for row in sorted(entries, key=lambda item: int(item["syntheticDisplayId"])):
        appearance_id = int(row["appearanceId"])
        source_item = int(row["sourceItemId"])
        display_id = int(row["syntheticDisplayId"])
        candidate = candidate_by_id.get(appearance_id)
        require(candidate is not None
                and source_item in {int(item["entry"]) for item in candidate["sourceItems"]},
                f"reserved canonical identity drift: {appearance_id}")
        asset = by_item.get(source_item)
        require(asset is not None and int(asset["display_id"]) == display_id, f"reserved display drift: {source_item}")
        target = norm(str(asset["target"]))
        asset_hashes: dict[str, str] = {}
        for kind, path in {
            "m2": target + ".m2", "skin": target + "00.skin", "texture": target + ".blp",
        }.items():
            check = verified.get(path)
            require(check is not None, f"reserved asset absent: {path}")
            asset_hashes[kind] = str(check["StageSHA256"]).lower()
        model_id = int(asset["model_id"])
        require(model_id not in seen_models and display_id not in seen_displays, "reserved ID collision")
        seen_models.add(model_id)
        seen_displays.add(display_id)
        rows.append({
            "appearanceId": appearance_id, "sourceItemId": source_item,
            "modelId": model_id, "syntheticDisplayId": display_id,
            "cameraTuningKey": str(row["cameraTuningKey"]), "m2Camera": deepcopy(row["m2Camera"]),
            "modelPath": str(row["modelPath"]), "assetHashes": asset_hashes,
        })
    result = {
        "schemaVersion": 1, "presentationSourceSha256": sha(source_path),
        "weaponManifestSha256": sha(weapon_manifest), "verificationSha256": sha(verification),
        "entries": rows,
    }
    result["reservedImportHash"] = hashlib.sha256(canonical(result)).hexdigest()
    return result


def archive_key(path: Path) -> tuple[int, str]:
    value = path.name.lower()
    return (ARCHIVE_PRIORITY.index(value) if value in ARCHIVE_PRIORITY else len(ARCHIVE_PRIORITY), value)


def mpq_list(mpqcli: Path, archive: Path) -> list[str]:
    run = subprocess.run(
        [str(mpqcli), "list", str(archive)], check=False, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
        text=True, encoding="utf-8", errors="replace",
    )
    require(run.returncode == 0, f"MPQ list failed {archive.name}: {run.stderr.strip() or run.stdout.strip()}")
    values = sorted({norm(line) for line in run.stdout.splitlines() if line.strip()})
    require(values, f"MPQ list empty: {archive.name}")
    return values


def capture(
    evidence_root: Path, fixed_root: Path, client_data_root: Path, mpqcli: Path,
    visibility_path: Path, appearance_sources_path: Path, presentation_source_path: Path,
    item_template_sql: Path,
) -> dict[str, Any]:
    evidence_root = ensure_f(evidence_root, "weapon shadow evidence root")
    fixed_manifest, fixed_members = verify_fixed_pack(fixed_root)
    require(mpqcli.is_file() and client_data_root.is_dir(), "client data root or mpqcli missing")
    require(not (evidence_root / "input-manifest.json").exists(), "evidence root already initialized")
    evidence_root.mkdir(parents=True, exist_ok=True)
    visibility = read_json(visibility_path)
    appearances = read_json(appearance_sources_path)
    basis, source_facts = candidate_basis(visibility, appearances)
    world_items = parse_sql_snapshot(item_template_sql, source_facts)
    by_entry = {int(row["entry"]): row for row in world_items}
    for candidate in basis["candidates"]:
        candidate["sourceItems"] = [by_entry[int(row["entry"])] for row in candidate["sourceItems"]]
    basis["candidateBasisHash"] = hashlib.sha256(canonical({
        key: value for key, value in basis.items() if key != "candidateBasisHash"
    })).hexdigest()
    snapshot = {
        "schemaVersion": 1, "sourceBuild": SOURCE_BUILD,
        "sourceContract": visibility.get("worldSnapshotContract"),
        "sourceItemTemplateSqlSha256": sha(item_template_sql), "items": world_items,
    }
    snapshot["snapshotHash"] = hashlib.sha256(canonical(snapshot)).hexdigest()
    reserved = reserved_import(presentation_source_path, fixed_members, basis["candidates"])

    dbc: list[dict[str, Any]] = []
    for relative, source in sorted(fixed_members.items()):
        if not relative.startswith("dbc/"):
            continue
        target = evidence_root / Path(relative)
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(source, target)
        require(sha(target) == sha(source), f"copied DBC hash drift: {relative}")
        dbc.append({"relativePath": relative, "size": target.stat().st_size, "sha256": sha(target)})
    require(all(any(row["relativePath"] == f"dbc/{name}" for row in dbc) for name in ("Item.dbc", "ItemDisplayInfo.dbc")),
            "captured DBC lacks weapon inputs")

    archives_path = sorted(
        [path for path in client_data_root.iterdir() if path.is_file() and path.suffix.lower() == ".mpq"],
        key=archive_key,
    )
    require(REQUIRED_ARCHIVES <= {path.name.lower() for path in archives_path}, "required WotLK MPQ missing")
    file_lists = evidence_root / "mpq-file-lists"
    file_lists.mkdir(parents=True, exist_ok=True)
    archives: list[dict[str, Any]] = []
    for priority, archive in enumerate(archives_path):
        print(f"freezing MPQ {priority + 1}/{len(archives_path)}: {archive.name}", flush=True)
        entries = mpq_list(mpqcli, archive)
        relative = f"mpq-file-lists/{archive.name.lower()}.lst"
        text = "\n".join(entries) + "\n"
        write_text(evidence_root / Path(relative), text)
        archives.append({
            "archiveName": archive.name, "archivePath": str(archive.resolve()), "priority": priority,
            "size": archive.stat().st_size, "sha256": sha(archive), "fileListRelativePath": relative,
            "fileListSha256": hashlib.sha256(text.encode("utf-8")).hexdigest(), "fileCount": len(entries),
        })
    write_text(evidence_root / "candidate-basis.json", pretty(basis))
    write_text(evidence_root / "world-item-template-snapshot.json", pretty(snapshot))
    write_text(evidence_root / "reserved-baseline.json", pretty(reserved))
    output = {
        "schemaVersion": 1, "sourceBuild": SOURCE_BUILD,
        "clientBuild": fixed_manifest.get("clientBuild"), "clientLocale": fixed_manifest.get("clientLocale"),
        "fixedInputEvidence": {"evidenceId": fixed_manifest.get("evidenceId"), "packHash": fixed_manifest.get("packHash")},
        "dbc": dbc, "candidateBasisSha256": sha(evidence_root / "candidate-basis.json"),
        "worldItemTemplateSnapshotSha256": sha(evidence_root / "world-item-template-snapshot.json"),
        "reservedBaselineSha256": sha(evidence_root / "reserved-baseline.json"),
        "visibilityEvidenceSha256": sha(visibility_path), "appearanceSourcesSha256": sha(appearance_sources_path),
        "mpqCliSha256": sha(mpqcli), "archives": archives, "assetBodiesCommittedToRepository": False,
    }
    output["inputHash"] = hashlib.sha256(canonical(output)).hexdigest()
    write_text(evidence_root / "input-manifest.json", pretty(output))
    print(f"frozen candidates: all={basis['counts']['all']} public={basis['counts']['public']}", flush=True)
    print(f"input hash: {output['inputHash']}", flush=True)
    return output


def load_inputs(root: Path, verify_archives: bool) -> tuple[dict[str, Any], dict[str, Any], dict[str, Any]]:
    root = ensure_f(root, "weapon shadow evidence root")
    manifest = verify_hash_object(read_json(root / "input-manifest.json"), "inputHash")
    require(manifest.get("sourceBuild") == SOURCE_BUILD, "input source build drift")
    for row in manifest.get("dbc", []):
        path = root / Path(str(row["relativePath"]))
        require(path.is_file() and path.stat().st_size == int(row["size"]) and sha(path) == row["sha256"],
                f"captured DBC drift: {row['relativePath']}")
    for filename, hash_field in (
        ("candidate-basis.json", "candidateBasisSha256"),
        ("world-item-template-snapshot.json", "worldItemTemplateSnapshotSha256"),
        ("reserved-baseline.json", "reservedBaselineSha256"),
    ):
        require(sha(root / filename) == manifest.get(hash_field), f"captured source drift: {filename}")
    basis = verify_hash_object(read_json(root / "candidate-basis.json"), "candidateBasisHash")
    reserved = verify_hash_object(read_json(root / "reserved-baseline.json"), "reservedImportHash")
    require(basis.get("counts") == {"all": EXPECTED_ALL, "public": EXPECTED_PUBLIC}, "candidate counts drift")
    require(len(reserved.get("entries", [])) == EXPECTED_RESERVED, "reserved count drift")
    for archive in manifest.get("archives", []):
        listing = root / Path(str(archive["fileListRelativePath"]))
        source = Path(str(archive["archivePath"]))
        require(listing.is_file() and sha(listing) == archive["fileListSha256"], f"MPQ list drift: {archive['archiveName']}")
        require(source.is_file() and source.stat().st_size == int(archive["size"]), f"MPQ source drift: {archive['archiveName']}")
        if verify_archives:
            require(sha(source) == archive["sha256"], f"MPQ hash drift: {archive['archiveName']}")
    return manifest, basis, reserved


def build_index(root: Path, manifest: dict[str, Any]) -> dict[str, Any]:
    by_name: dict[str, list[dict[str, Any]]] = defaultdict(list)
    by_archive_path: dict[tuple[str, str], dict[str, Any]] = {}
    by_path: dict[str, list[dict[str, Any]]] = defaultdict(list)
    archives = {str(row["archiveName"]).lower(): row for row in manifest["archives"]}
    for archive_key, archive in archives.items():
        listing = root / Path(str(archive["fileListRelativePath"]))
        for raw in listing.read_text(encoding="utf-8").splitlines():
            internal = norm(raw)
            extension = Path(name(internal)).suffix.lower()
            if extension not in {".m2", ".mdx", ".skin", ".blp"}:
                continue
            ref = {
                "archiveKey": archive_key, "archiveName": archive["archiveName"],
                "priority": int(archive["priority"]), "internalPath": internal, "extension": extension,
            }
            by_name[name(internal)].append(ref)
            by_path[internal].append(ref)
            by_archive_path[(archive_key, internal)] = ref
    return {"archives": archives, "byName": by_name, "byPath": by_path, "byArchivePath": by_archive_path}


def asset_id(ref: dict[str, Any]) -> str:
    return f"{ref['archiveKey']}|{ref['internalPath']}"


def preferred_roots(route: str) -> list[str]:
    if route == "SHIELD":
        return ["item\\objectcomponents\\shield\\", "item\\objectcomponents\\weapon\\", "item\\objectcomponents\\"]
    if route == "HELD_IN_OFFHAND":
        return ["item\\objectcomponents\\weapon\\", "item\\objectcomponents\\shield\\", "item\\objectcomponents\\"]
    return ["item\\objectcomponents\\weapon\\", "item\\objectcomponents\\"]


def choose(
    refs: Iterable[dict[str, Any]], roots: list[str], preferred_parent: str | None = None,
) -> tuple[dict[str, Any] | None, list[str], bool]:
    def rank(ref: dict[str, Any]) -> tuple[int, int, int, str]:
        internal = str(ref["internalPath"])
        exact_parent = 0 if preferred_parent and parent(internal) == preferred_parent else 1
        root_rank = next((index for index, root in enumerate(roots) if internal.startswith(root)), len(roots))
        return exact_parent, root_rank, int(ref["priority"]), internal
    ordered = sorted(refs, key=rank)
    if not ordered:
        return None, [], False
    first = rank(ordered[0])[:3]
    ties = [item for item in ordered if rank(item)[:3] == first]
    return ordered[0], [asset_id(item) for item in ordered], len({item["internalPath"] for item in ties}) > 1


def route_for(candidate: dict[str, Any], item: dict[str, Any]) -> str:
    inventory = int(item["inventoryType"])
    if inventory == 14:
        return "SHIELD"
    if inventory == 23:
        return "HELD_IN_OFFHAND"
    if candidate["slotKey"] == "OFFHAND":
        return "OFFHAND_WEAPON"
    if inventory in {15, 25, 26}:
        return "RANGED"
    return "MAINHAND"


def select_side(route: str, display: dict[str, Any]) -> tuple[str, str, str, list[str]]:
    use_right = route in {"SHIELD", "HELD_IN_OFFHAND", "OFFHAND_WEAPON"}
    notes: list[str] = []
    if use_right and display["rightModel"] and display["rightTexture"]:
        return "RIGHT", display["rightModel"], display["rightTexture"], notes
    if use_right:
        notes.append("OFFHAND_RIGHT_PAIR_UNAVAILABLE_USED_LEFT")
    if display["leftModel"] and display["leftTexture"]:
        return "LEFT", display["leftModel"], display["leftTexture"], notes
    if display["rightModel"] and display["rightTexture"]:
        notes.append("LEFT_PAIR_UNAVAILABLE_USED_RIGHT")
        return "RIGHT", display["rightModel"], display["rightTexture"], notes
    return ("RIGHT" if use_right else "LEFT",
            display["rightModel"] if use_right else display["leftModel"],
            display["rightTexture"] if use_right else display["leftTexture"], notes)


def resolve_model(index: dict[str, Any], route: str, model_name: str) -> tuple[dict[str, Any] | None, list[str], bool]:
    if not model_name:
        return None, [], False
    values = [
        ref for suffix in (".m2", ".mdx") for ref in index["byName"].get(stem(model_name) + suffix, [])
        if str(ref["internalPath"]).startswith("item\\objectcomponents\\")
    ]
    return choose(values, preferred_roots(route))


def resolve_skin(index: dict[str, Any], route: str, model: dict[str, Any]) -> tuple[dict[str, Any] | None, list[str], bool]:
    internal = str(model["internalPath"])
    expected = internal.rsplit(".", 1)[0] + "00.skin"
    exact = index["byArchivePath"].get((str(model["archiveKey"]), expected))
    if exact:
        return exact, [asset_id(exact)], False
    return choose(index["byName"].get(name(expected), []), preferred_roots(route), parent(internal))


def normalize_texture(value: str) -> str:
    if not value.strip():
        return ""
    raw = value.strip().replace("/", "\\")
    return norm(raw if raw.lower().endswith(".blp") else raw + ".blp")


def resolve_texture(
    index: dict[str, Any], route: str, texture_name: str, model: dict[str, Any] | None,
) -> tuple[dict[str, Any] | None, list[str], bool]:
    texture = normalize_texture(texture_name)
    if not texture:
        return None, [], False
    refs = index["byPath"].get(texture, []) if "\\" in texture else []
    if not refs:
        refs = index["byName"].get(name(texture), [])
    return choose(refs, preferred_roots(route), parent(str(model["internalPath"])) if model else None)


def resolve_candidate(candidate: dict[str, Any], displays: dict[int, dict[str, Any]], index: dict[str, Any]) -> dict[str, Any]:
    primary = next(item for item in candidate["sourceItems"] if int(item["entry"]) == int(candidate["primarySourceItemId"]))
    route = route_for(candidate, primary)
    display = displays.get(int(candidate["displayId"]))
    if display is None:
        return {
            **candidate, "route": route, "sourceSide": "", "nativeDisplay": None,
            "refs": {}, "failures": [{"reasonCode": "MISSING_ITEM_DISPLAY_INFO",
                                      "missingRelativePath": f"ItemDisplayInfo:{candidate['displayId']}"}],
        }
    side, model_name, texture_name, notes = select_side(route, display)
    refs: dict[str, dict[str, Any]] = {}
    failures: list[dict[str, str]] = []
    model: dict[str, Any] | None = None
    if not model_name:
        failures.append({"reasonCode": "MISSING_MODEL_NAME", "missingRelativePath": f"ItemDisplayInfo:{display['displayId']}:{side}:model"})
    else:
        model, alternatives, ambiguous = resolve_model(index, route, model_name)
        if ambiguous:
            failures.append({"reasonCode": "AMBIGUOUS_MODEL_PATH", "missingRelativePath": ";".join(alternatives)})
        if model is None:
            folder = "Shield" if route == "SHIELD" else "Weapon"
            failures.append({"reasonCode": "MISSING_MODEL_ASSET",
                             "missingRelativePath": f"Item\\ObjectComponents\\{folder}\\{stem(model_name)}.m2"})
        else:
            refs["model"] = model
            skin, alternatives, ambiguous = resolve_skin(index, route, model)
            if ambiguous:
                failures.append({"reasonCode": "AMBIGUOUS_SKIN_PATH", "missingRelativePath": ";".join(alternatives)})
            if skin is None:
                failures.append({"reasonCode": "MISSING_SKIN_ASSET",
                                 "missingRelativePath": str(model["internalPath"]).rsplit(".", 1)[0] + "00.skin"})
            else:
                refs["skin"] = skin
    if not texture_name:
        failures.append({"reasonCode": "MISSING_TEXTURE_NAME", "missingRelativePath": f"ItemDisplayInfo:{display['displayId']}:{side}:texture"})
    else:
        texture, alternatives, ambiguous = resolve_texture(index, route, texture_name, model)
        if ambiguous:
            failures.append({"reasonCode": "AMBIGUOUS_TEXTURE_PATH", "missingRelativePath": ";".join(alternatives)})
        if texture is None:
            failures.append({"reasonCode": "MISSING_TEXTURE_ASSET", "missingRelativePath": normalize_texture(texture_name)})
        else:
            refs["displayTexture"] = texture
    return {
        **candidate, "route": route, "sourceSide": side, "sourceSideNotes": notes,
        "nativeDisplay": display, "refs": refs, "failures": failures,
    }


def extract_refs(root: Path, manifest: dict[str, Any], stormlib: Path, refs: Iterable[dict[str, Any]]) -> None:
    wanted = {asset_id(ref): ref for ref in refs}
    if not wanted:
        return
    asset_root = root / "asset-cache"
    request_root = root / "mpq-requests"
    asset_root.mkdir(parents=True, exist_ok=True)
    request_root.mkdir(parents=True, exist_ok=True)
    archives = {str(row["archiveName"]).lower(): row for row in manifest["archives"]}
    grouped: dict[str, list[dict[str, Any]]] = defaultdict(list)
    for ref in wanted.values():
        if not evidence_asset_path(root, str(ref["internalPath"])).is_file():
            grouped[str(ref["archiveKey"])].append(ref)
    for archive_key, values in sorted(grouped.items(), key=lambda pair: int(archives[pair[0]]["priority"])):
        archive = archives[archive_key]
        request = request_root / f"{archive_key}.lst"
        write_text(request, "\n".join(sorted({str(row["internalPath"]) for row in values})) + "\n")
        print(f"extracting {len(values)} source assets from {archive['archiveName']}", flush=True)
        script = Path(__file__).resolve().parents[1] / "mpq" / "Extract-StormMpqBatch.ps1"
        require(script.is_file(), f"batch MPQ extractor missing: {script}")
        run = subprocess.run(
            [
                "powershell.exe", "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", str(script),
                "-Archive", str(archive["archivePath"]), "-ListFile", str(request),
                "-OutputRoot", str(asset_root), "-StormLib", str(stormlib),
            ],
            check=False, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True,
            encoding="utf-8", errors="replace",
        )
        require(run.returncode == 0, f"MPQ extraction failed {archive['archiveName']}: {run.stderr.strip() or run.stdout.strip()}")
    for ref in wanted.values():
        require(evidence_asset_path(root, str(ref["internalPath"])).is_file(),
                f"extracted asset missing: {ref['internalPath']}")


def require_range(data: bytes, offset: int, size: int, label: str) -> None:
    require(offset >= 0 and size >= 0 and offset + size <= len(data), f"{label} outside source asset")


def inspect_m2(path: Path) -> dict[str, Any]:
    data = path.read_bytes()
    require(len(data) >= M2_CAMERA_LOOKUP + 8 and data[:4] == b"MD20", f"invalid M2: {path.name}")
    require(struct.unpack_from("<I", data, 4)[0] == WOTLK_M2_VERSION, f"unsupported M2 version: {path.name}")
    count, offset = struct.unpack_from("<2I", data, M2_TEXTURE_DESCRIPTOR)
    require_range(data, offset, count * M2_TEXTURE_SIZE, "M2 texture descriptors")
    textures: list[dict[str, Any]] = []
    for index in range(count):
        texture_type, flags, length, filename_offset = struct.unpack_from("<4I", data, offset + index * M2_TEXTURE_SIZE)
        filename = ""
        if length:
            require_range(data, filename_offset, length, "M2 texture filename")
            filename = data[filename_offset:filename_offset + length].decode("utf-8", errors="replace").rstrip("\0")
        textures.append({"index": index, "type": int(texture_type), "flags": int(flags), "filename": filename})
    lookup_count, lookup_offset = struct.unpack_from("<2I", data, M2_REPLACEABLE_LOOKUP)
    require_range(data, lookup_offset, lookup_count * 2, "M2 replaceable texture lookup")
    lookup = list(struct.unpack_from(f"<{lookup_count}H", data, lookup_offset)) if lookup_count else []
    require_range(data, M2_BOUNDS, 28, "M2 bounds")
    min_x, min_y, min_z, max_x, max_y, max_z, radius = struct.unpack_from("<7f", data, M2_BOUNDS)
    require(all(math.isfinite(value) for value in (min_x, min_y, min_z, max_x, max_y, max_z, radius))
            and min_x < max_x and min_y < max_y and min_z < max_z and radius >= 0, f"invalid M2 bounds: {path.name}")
    camera_count, camera_offset = struct.unpack_from("<2I", data, M2_CAMERA)
    lookup_camera_count, lookup_camera_offset = struct.unpack_from("<2I", data, M2_CAMERA_LOOKUP)
    if camera_count:
        require_range(data, camera_offset, camera_count * 100, "M2 cameras")
    if lookup_camera_count:
        require_range(data, lookup_camera_offset, lookup_camera_count * 2, "M2 camera lookup")
    layout = "CAMERALESS" if not any((camera_count, camera_offset, lookup_camera_count, lookup_camera_offset)) else (
        "HAS_CAMERA" if all((camera_count, camera_offset, lookup_camera_count, lookup_camera_offset))
        else "INCONSISTENT_CAMERA_LAYOUT"
    )
    return {
        "kind": "M2", "m2Version": WOTLK_M2_VERSION, "textureDescriptors": textures,
        "objectSkinDescriptorCount": sum(value["type"] == OBJECT_SKIN for value in textures),
        "replaceableTextureLookup": lookup, "cameraLayout": layout,
        "bounds": {
            "min": {"x": round(min_x, 6), "y": round(min_y, 6), "z": round(min_z, 6)},
            "max": {"x": round(max_x, 6), "y": round(max_y, 6), "z": round(max_z, 6)},
            "width": round(max_x - min_x, 6), "depth": round(max_y - min_y, 6),
            "height": round(max_z - min_z, 6), "radius": round(radius, 6),
            "center": {"x": round((min_x + max_x) / 2, 6), "y": round((min_y + max_y) / 2, 6),
                       "z": round((min_z + max_z) / 2, 6)},
        },
    }


def inspect_skin(path: Path) -> dict[str, Any]:
    data = path.read_bytes()
    require(len(data) >= 44 and data[:4] == b"SKIN", f"invalid SKIN: {path.name}")
    values = struct.unpack_from("<10I", data, 4)
    names = ("indexCount", "indexOffset", "triangleCount", "triangleOffset", "propertyCount", "propertyOffset",
             "submeshCount", "submeshOffset", "textureUnitCount", "textureUnitOffset")
    facts = dict(zip(names, (int(value) for value in values), strict=True))
    for field in ("indexOffset", "triangleOffset", "propertyOffset", "submeshOffset", "textureUnitOffset"):
        require(0 <= facts[field] <= len(data), f"SKIN offset out of range: {path.name}:{field}")
    return {"kind": "SKIN", **facts}


def inspect_blp(path: Path) -> dict[str, Any]:
    data = path.read_bytes()
    require(len(data) >= 4 and data[:4] in {b"BLP1", b"BLP2"}, f"invalid BLP: {path.name}")
    return {"kind": "BLP", "magic": data[:4].decode("ascii")}


def inspect_asset(root: Path, ref: dict[str, Any]) -> dict[str, Any]:
    path = evidence_asset_path(root, str(ref["internalPath"]))
    try:
        if ref["extension"] in {".m2", ".mdx"}:
            parsed = inspect_m2(path)
        elif ref["extension"] == ".skin":
            parsed = inspect_skin(path)
        else:
            parsed = inspect_blp(path)
        error = None
    except (OSError, ShadowError, struct.error) as exc:
        parsed = {}
        error = str(exc)
    return {
        **ref, "assetId": asset_id(ref),
        "evidenceRelativePath": str(path.relative_to(root)).replace("\\", "/"),
        "bytes": path.stat().st_size if path.is_file() else 0, "sha256": sha(path) if path.is_file() else "",
        "parse": parsed, "parseError": error,
    }


def hydrate(root: Path, mpqcli: Path, stormlib: Path) -> dict[str, Any]:
    root = ensure_f(root, "weapon shadow evidence root")
    require(mpqcli.is_file() and stormlib.is_file(), "mpqcli or StormLib missing")
    manifest, basis, _reserved = load_inputs(root, verify_archives=True)
    require(sha(mpqcli) == manifest["mpqCliSha256"], "mpqcli hash drift")
    index_path = root / "asset-index.json"
    if index_path.exists():
        existing = verify_hash_object(read_json(index_path), "assetIndexHash")
        require(existing.get("inputHash") == manifest["inputHash"], "existing asset index input drift")
        for asset in existing.get("assets", []):
            file = root / Path(str(asset["evidenceRelativePath"]))
            require(file.is_file() and sha(file) == asset["sha256"], f"existing asset drift: {asset['internalPath']}")
        return existing
    require(not (root / "asset-cache").exists(), "partial asset cache exists; select a new named evidence root")
    index = build_index(root, manifest)
    displays = read_displays(root / "dbc" / "ItemDisplayInfo.dbc")
    planned = [resolve_candidate(candidate, displays, index) for candidate in basis["candidates"]]
    refs = {asset_id(ref): ref for row in planned for ref in row["refs"].values()}
    extract_refs(root, manifest, stormlib, refs.values())
    assets = {key: inspect_asset(root, value) for key, value in refs.items()}
    supplemental: dict[str, dict[str, Any]] = {}
    for row in planned:
        model = assets.get(asset_id(row["refs"]["model"])) if "model" in row["refs"] else None
        unresolved: list[str] = []
        hardcoded: list[str] = []
        if model and not model["parseError"]:
            for texture in model["parse"].get("textureDescriptors", []):
                if texture["type"] == OBJECT_SKIN or not texture["filename"]:
                    continue
                resolved, _alternatives, ambiguous = resolve_texture(index, row["route"], texture["filename"], row["refs"]["model"])
                if resolved is None or ambiguous:
                    unresolved.append(normalize_texture(texture["filename"]))
                else:
                    supplemental[asset_id(resolved)] = resolved
                    hardcoded.append(asset_id(resolved))
        row["hardcodedTextureAssetIds"] = sorted(set(hardcoded))
        row["unresolvedHardcodedTexturePaths"] = sorted(set(unresolved))
    extract_refs(root, manifest, stormlib, supplemental.values())
    for key, value in supplemental.items():
        assets[key] = inspect_asset(root, value)
    for row in planned:
        row["refs"] = {role: asset_id(ref) for role, ref in row["refs"].items()}
    plan = {"schemaVersion": 1, "inputHash": manifest["inputHash"],
            "candidateBasisHash": basis["candidateBasisHash"], "candidates": planned}
    plan["assetPlanHash"] = hashlib.sha256(canonical(plan)).hexdigest()
    output = {"schemaVersion": 1, "inputHash": manifest["inputHash"], "assetPlanHash": plan["assetPlanHash"],
              "assets": [assets[key] for key in sorted(assets)]}
    output["assetIndexHash"] = hashlib.sha256(canonical(output)).hexdigest()
    write_text(root / "asset-plan.json", pretty(plan))
    write_text(index_path, pretty(output))
    print(f"hydrated source assets: {len(output['assets'])}", flush=True)
    print(f"asset index hash: {output['assetIndexHash']}", flush=True)
    return output


def asset_ok(asset: dict[str, Any] | None, kind: str) -> bool:
    return bool(asset and not asset.get("parseError") and asset.get("parse", {}).get("kind") == kind)


def add_failure(failures: list[dict[str, str]], reason_code: str, missing: str) -> None:
    value = {"reasonCode": reason_code, "missingRelativePath": missing}
    if value not in failures:
        failures.append(value)


def preset_map(reserved: dict[str, Any]) -> dict[str, dict[str, Any]]:
    values: dict[str, dict[str, Any]] = {}
    for row in reserved["entries"]:
        key = str(row["cameraTuningKey"])
        pose = row["m2Camera"]
        if key in values:
            require(values[key] == pose, f"reserved family pose drift: {key}")
        else:
            values[key] = deepcopy(pose)
    require(len(values) >= 18 and "ONE_HAND_SWORD" in values and "SHIELD" in values,
            "reserved camera family preset coverage drift")
    return values


def family_for(row: dict[str, Any], model: dict[str, Any]) -> tuple[str, str | None]:
    path = str(model["internalPath"]).lower()
    if "glave" in path:
        return ("WAR_GLAIVE_OFFHAND" if row["sourceSide"] == "RIGHT" else "WAR_GLAIVE_MAINHAND"), None
    if row["route"] == "SHIELD":
        return "SHIELD", None
    primary = next(item for item in row["sourceItems"] if int(item["entry"]) == int(row["primarySourceItemId"]))
    family = FAMILY_BY_SUBCLASS.get(int(primary["itemSubclass"]))
    if family:
        return family, None
    if row["route"] == "HELD_IN_OFFHAND":
        return "SHIELD", "HELD_OFFHAND_FALLBACK_SHIELD_PRESET"
    return "ONE_HAND_SWORD", "UNKNOWN_WEAPON_FALLBACK_ONE_HAND_SWORD_PRESET"


def auto_camera(row: dict[str, Any], model: dict[str, Any], presets: dict[str, dict[str, Any]]) -> tuple[dict[str, Any], str | None]:
    bounds = model["parse"]["bounds"]
    family, fallback = family_for(row, model)
    pose = presets.get(family, presets["ONE_HAND_SWORD"])
    if family not in presets:
        fallback = (fallback + ";" if fallback else "") + "MISSING_FAMILY_PRESET_USED_ONE_HAND_SWORD"
    dimensions = [float(bounds["width"]), float(bounds["depth"]), float(bounds["height"])]
    ratio = max(dimensions) / min(dimensions) if min(dimensions) > 0 else None
    if row["route"] == "SHIELD":
        shape = "SHIELD"
    elif row["route"] == "HELD_IN_OFFHAND":
        shape = "HELD_OFFHAND"
    elif row["route"] == "RANGED":
        shape = "RANGED"
    elif ratio is not None and ratio >= 4:
        shape = "LONG_AXIS"
    elif ratio is not None and ratio >= 2:
        shape = "FLAT"
    else:
        shape = "COMPACT"
    return {
        "baselineKind": "AUTO_FROM_RESERVED_FAMILY_PRESET", "presetKey": family if family in presets else "ONE_HAND_SWORD",
        "presetPose": deepcopy(pose), "shapeClass": shape, "extentRatio": round(ratio, 6) if ratio is not None else None,
        "minimumCameraDistance": round(max(float(bounds["radius"]) * 2.65, 1.45), 6),
        "targetCenter": deepcopy(bounds["center"]), "cameraLayout": model["parse"]["cameraLayout"],
    }, fallback


def terminal_rows(
    plan: dict[str, Any],
    assets: dict[str, dict[str, Any]],
    presets: dict[str, dict[str, Any]],
    reserved_appearances: set[int],
) -> list[dict[str, Any]]:
    rows: list[dict[str, Any]] = []
    for source in plan["candidates"]:
        failures = [dict(value) for value in source.get("failures", [])]
        refs = source.get("refs", {})
        model = assets.get(refs.get("model", ""))
        skin = assets.get(refs.get("skin", ""))
        texture = assets.get(refs.get("displayTexture", ""))
        if not asset_ok(model, "M2"):
            add_failure(failures, "INVALID_OR_MISSING_M2", str(refs.get("model", "<model>")))
        if not asset_ok(skin, "SKIN"):
            add_failure(failures, "INVALID_OR_MISSING_SKIN", str(refs.get("skin", "<skin>")))
        if not asset_ok(texture, "BLP"):
            add_failure(failures, "INVALID_OR_MISSING_DISPLAY_TEXTURE", str(refs.get("displayTexture", "<texture>")))
        hardcoded: list[dict[str, Any]] = []
        for key in source.get("hardcodedTextureAssetIds", []):
            asset = assets.get(key)
            if not asset_ok(asset, "BLP"):
                add_failure(failures, "INVALID_OR_MISSING_M2_TEXTURE", str(key))
            else:
                hardcoded.append(asset)
        for path in source.get("unresolvedHardcodedTexturePaths", []):
            add_failure(failures, "UNRESOLVED_M2_TEXTURE_REFERENCE", str(path))
        asset_status = "READY" if not failures else "UNAVAILABLE"
        inherited = int(source["appearanceId"]) in reserved_appearances
        camera = None
        fallback = None
        if asset_status == "READY" and model is not None:
            camera, fallback = auto_camera(source, model, presets)
        geometry = texture_key = display_key = signature = None
        if asset_status == "READY" and model is not None and skin is not None:
            geometry = hashlib.sha256(canonical({"m2": model["sha256"], "skin": skin["sha256"]})).hexdigest()
            texture_key = hashlib.sha256(canonical({"blp": sorted(
                asset["sha256"] for asset in [texture, *hardcoded] if asset is not None
            )})).hexdigest()
            display_key = hashlib.sha256(canonical({
                "route": source["route"], "side": source["sourceSide"],
                "geometry": geometry, "texture": texture_key, "visual": source["nativeDisplay"]["visual"],
            })).hexdigest()
            signature = "m2:" + model["sha256"]
        rows.append({
            "appearanceId": int(source["appearanceId"]), "collectionKey": source["collectionKey"],
            "public": bool(source["public"]), "slotKey": source["slotKey"], "route": source["route"],
            "sourceSide": source["sourceSide"], "primarySourceItemId": int(source["primarySourceItemId"]),
            "sourceItems": deepcopy(source["sourceItems"]), "nativeDisplayId": int(source["displayId"]),
            "nativeDisplay": deepcopy(source.get("nativeDisplay")), "assetStatus": asset_status,
            "terminalStatus": ("READY" if inherited else asset_status) if source["public"] else "NONPUBLIC",
            "presentationStatus": "INHERITED_VERIFIED" if inherited else ("SHADOW_READY" if asset_status == "READY" else "SHADOW_UNAVAILABLE"),
            "failures": failures, "model": model, "skin": skin, "texture": texture, "hardcoded": hardcoded,
            "bounds": deepcopy(model["parse"]["bounds"]) if asset_ok(model, "M2") else None,
            "autoCamera": camera, "geometryKey": geometry, "textureKey": texture_key,
            "displayKey": display_key, "modelSignature": signature,
            "cameraNotes": fallback.split(";") if fallback else [],
        })
    require(len(rows) == EXPECTED_ALL and sum(row["public"] for row in rows) == EXPECTED_PUBLIC,
            "terminal coverage drift")
    return rows


def apply_outliers(rows: list[dict[str, Any]]) -> tuple[list[dict[str, Any]], dict[str, float]]:
    ready = [row for row in rows if row["bounds"]]
    radii = [float(row["bounds"]["radius"]) for row in ready if float(row["bounds"]["radius"]) > 0]
    require(radii, "no finite source bounds")
    limits = {
        "medianRadius": round(statistics.median(radii), 6),
        "oversizedRadius": round(max(10.0, statistics.median(radii) * 5), 6),
        "extremeAspectRatio": 16.0, "nearZeroExtent": 0.001,
    }
    outliers: list[dict[str, Any]] = []
    for row in ready:
        bounds = row["bounds"]
        values = [float(bounds["width"]), float(bounds["depth"]), float(bounds["height"])]
        reasons: list[str] = []
        if min(values) < limits["nearZeroExtent"]:
            reasons.append("NEAR_ZERO_BOUNDS")
        if float(bounds["radius"]) > limits["oversizedRadius"]:
            reasons.append("OVERSIZED_RADIUS")
        if row["autoCamera"] and row["autoCamera"]["extentRatio"] and row["autoCamera"]["extentRatio"] > limits["extremeAspectRatio"]:
            reasons.append("EXTREME_ASPECT_RATIO")
        row["outlierReasons"] = reasons
        if reasons:
            outliers.append(row)
    return outliers, limits


def previous_registry(path: Path | None, input_hash: str) -> dict[str, Any] | None:
    if path is None:
        return None
    value = verify_hash_object(read_json(path), "registryHash")
    require(value.get("schemaVersion") == 1 and value.get("inputHash") == input_hash, "previous registry input drift")
    return value


def registry(rows: list[dict[str, Any]], reserved: dict[str, Any], input_hash: str, previous: dict[str, Any] | None) -> dict[str, Any]:
    reserved_by_appearance = {int(row["appearanceId"]): row for row in reserved["entries"]}
    ready = [row for row in rows if row["public"] and row["terminalStatus"] == "READY"]
    ready_by_appearance = {int(row["appearanceId"]): row for row in ready}
    prior_active: dict[int, dict[str, Any]] = {}
    tombstones: list[dict[str, Any]] = []
    if previous:
        prior_active = {
            int(row["appearanceId"]): row for row in previous.get("entries", [])
            if row.get("allocationStatus") == "ACTIVE"
        }
        tombstones = [deepcopy(row) for row in previous.get("tombstones", [])]
        for appearance_id, prior in prior_active.items():
            if appearance_id not in ready_by_appearance and appearance_id not in reserved_by_appearance:
                tombstones.append({**deepcopy(prior), "allocationStatus": "TOMBSTONE",
                                   "tombstoneReason": "NO_LONGER_READY_OR_PUBLIC"})
    tombstoned = {int(row["appearanceId"]) for row in tombstones}
    require(len(tombstoned) == len(tombstones), "duplicate tombstone")
    used_models = {int(row["modelId"]) for row in reserved["entries"]}
    used_displays = {int(row["syntheticDisplayId"]) for row in reserved["entries"]}
    for row in [*prior_active.values(), *tombstones]:
        used_models.add(int(row["modelId"]))
        used_displays.add(int(row["syntheticDisplayId"]))
    next_model = max(used_models) + 1
    next_display = max(used_displays) + 1
    geometries = {
        str(row["geometryKey"]): int(row["modelId"]) for row in prior_active.values()
        if int(row["appearanceId"]) in ready_by_appearance
    }
    displays = {
        str(row["displayKey"]): int(row["syntheticDisplayId"]) for row in prior_active.values()
        if int(row["appearanceId"]) in ready_by_appearance
    }
    entries: list[dict[str, Any]] = []
    for appearance_id, imported in sorted(reserved_by_appearance.items()):
        source = next(row for row in rows if int(row["appearanceId"]) == appearance_id)
        entries.append({
            "appearanceId": appearance_id, "collectionKey": source["collectionKey"],
            "sourceItemId": int(imported["sourceItemId"]), "allocationStatus": "RESERVED",
            "modelId": int(imported["modelId"]), "syntheticDisplayId": int(imported["syntheticDisplayId"]),
            "geometryKey": "reserved:" + str(appearance_id), "textureKey": "reserved:" + str(appearance_id),
            "displayKey": "reserved:" + str(appearance_id),
            "modelSignature": "m2:" + imported["assetHashes"]["m2"],
            "reservedImportHash": reserved["reservedImportHash"],
        })
    for row in sorted(ready, key=lambda item: item["appearanceId"]):
        appearance_id = int(row["appearanceId"])
        imported = reserved_by_appearance.get(appearance_id)
        if imported:
            continue
        prior = prior_active.get(appearance_id)
        if prior:
            require(all(str(prior[key]) == str(row[key]) for key in ("geometryKey", "textureKey", "displayKey", "modelSignature")),
                    f"prior registry source key drift for {appearance_id}")
            entries.append(deepcopy(prior))
            continue
        model_id = geometries.get(str(row["geometryKey"]))
        if model_id is None:
            while next_model in used_models:
                next_model += 1
            model_id = next_model
            used_models.add(model_id)
            geometries[str(row["geometryKey"])] = model_id
            next_model += 1
        display_id = displays.get(str(row["displayKey"]))
        if display_id is None:
            while next_display in used_displays:
                next_display += 1
            display_id = next_display
            used_displays.add(display_id)
            displays[str(row["displayKey"])] = display_id
            next_display += 1
        entries.append({
            "appearanceId": appearance_id, "collectionKey": row["collectionKey"],
            "sourceItemId": row["primarySourceItemId"], "allocationStatus": "ACTIVE",
            "modelId": model_id, "syntheticDisplayId": display_id,
            "geometryKey": row["geometryKey"], "textureKey": row["textureKey"],
            "displayKey": row["displayKey"], "modelSignature": row["modelSignature"],
        })
    display_identity: dict[int, str] = {}
    for row in entries:
        display_id = int(row["syntheticDisplayId"])
        existing = display_identity.get(display_id)
        require(existing is None or existing == str(row["displayKey"]),
                f"synthetic display collision: {display_id}")
        display_identity[display_id] = str(row["displayKey"])
    require(all(0 < int(row["syntheticDisplayId"]) <= 0x00FFFFFF for row in entries), "synthetic display outside range")
    require(not tombstoned & {int(row["appearanceId"]) for row in entries}, "tombstone recycled")
    active = [row for row in entries if row["allocationStatus"] == "ACTIVE"]
    value = {
        "schemaVersion": 1, "inputHash": input_hash, "reservedImportHash": reserved["reservedImportHash"],
        "idRanges": {
            "reservedModelIds": [min(int(row["modelId"]) for row in reserved["entries"]),
                                 max(int(row["modelId"]) for row in reserved["entries"])],
            "reservedDisplayIds": [min(int(row["syntheticDisplayId"]) for row in reserved["entries"]),
                                   max(int(row["syntheticDisplayId"]) for row in reserved["entries"])],
            "nextModelId": next_model, "nextSyntheticDisplayId": next_display,
        },
        "entries": entries, "tombstones": sorted(tombstones, key=lambda item: int(item["appearanceId"])),
        "dedup": {
            "readyPublicAppearances": len(ready), "reservedAppearances": EXPECTED_RESERVED,
            "newlyAllocatedAppearances": len(active),
            "uniqueNewGeometry": len({str(row["geometryKey"]) for row in active}),
            "uniqueNewDisplays": len({str(row["displayKey"]) for row in active}),
            "reusedGeometryAppearances": len(active) - len({str(row["geometryKey"]) for row in active}),
            "reusedDisplayAppearances": len(active) - len({str(row["displayKey"]) for row in active}),
        },
    }
    value["registryHash"] = hashlib.sha256(canonical(value)).hexdigest()
    return value


def csv_text(fields: list[str], rows: list[dict[str, Any]]) -> str:
    out = io.StringIO(newline="")
    writer = csv.DictWriter(out, fieldnames=fields, lineterminator="\n")
    writer.writeheader()
    writer.writerows(rows)
    return out.getvalue()


def candidate_csv(rows: list[dict[str, Any]], assigned: dict[int, dict[str, Any]]) -> str:
    fields = [
        "appearanceId", "collectionKey", "scope", "terminalStatus", "assetStatus", "presentationStatus", "reasonCodes",
        "missingRelativePaths", "slotKey", "route", "sourceSide", "primarySourceItemId", "primaryItemLevel",
        "nativeDisplayId", "modelPath", "skinPath", "displayTexturePath", "modelSignature", "geometryKey",
        "textureKey", "displayKey", "modelId", "syntheticDisplayId", "allocationStatus", "cameraPreset",
        "shapeClass", "extentRatio", "radius", "cameraLayout", "cameraNotes", "outlierReasons",
    ]
    data: list[dict[str, Any]] = []
    for row in sorted(rows, key=lambda item: item["appearanceId"]):
        primary = next(item for item in row["sourceItems"] if int(item["entry"]) == int(row["primarySourceItemId"]))
        allocation = assigned.get(int(row["appearanceId"]), {})
        camera = row.get("autoCamera") or {}
        data.append({
            "appearanceId": row["appearanceId"], "collectionKey": row["collectionKey"],
            "scope": "PUBLIC" if row["public"] else "NONPUBLIC", "terminalStatus": row["terminalStatus"],
            "assetStatus": row["assetStatus"], "presentationStatus": row["presentationStatus"],
            "reasonCodes": ";".join(item["reasonCode"] for item in row["failures"]) or "READY",
            "missingRelativePaths": ";".join(item["missingRelativePath"] for item in row["failures"] if item["missingRelativePath"]),
            "slotKey": row["slotKey"], "route": row["route"], "sourceSide": row["sourceSide"],
            "primarySourceItemId": row["primarySourceItemId"], "primaryItemLevel": primary["itemLevel"],
            "nativeDisplayId": row["nativeDisplayId"],
            "modelPath": row["model"]["internalPath"] if row["model"] else "",
            "skinPath": row["skin"]["internalPath"] if row["skin"] else "",
            "displayTexturePath": row["texture"]["internalPath"] if row["texture"] else "",
            "modelSignature": row["modelSignature"] or "", "geometryKey": row["geometryKey"] or "",
            "textureKey": row["textureKey"] or "", "displayKey": row["displayKey"] or "",
            "modelId": allocation.get("modelId", ""), "syntheticDisplayId": allocation.get("syntheticDisplayId", ""),
            "allocationStatus": allocation.get("allocationStatus", ""), "cameraPreset": camera.get("presetKey", ""),
            "shapeClass": camera.get("shapeClass", ""), "extentRatio": camera.get("extentRatio", ""),
            "radius": row["bounds"]["radius"] if row["bounds"] else "",
            "cameraLayout": camera.get("cameraLayout", ""), "cameraNotes": ";".join(row.get("cameraNotes", [])),
            "outlierReasons": ";".join(row.get("outlierReasons", [])),
        })
    return csv_text(fields, data)


def sample_csv(rows: list[dict[str, Any]], seed: str) -> str:
    ready = [row for row in rows if row["public"] and row["terminalStatus"] == "READY" and row.get("autoCamera")]
    selected: dict[int, str] = {}
    for route in sorted({str(row["route"]) for row in ready}):
        item = next(row for row in sorted(ready, key=lambda value: value["appearanceId"]) if row["route"] == route)
        selected[item["appearanceId"]] = "ROUTE_STRATIFIED"
    for preset in sorted({str(row["autoCamera"]["presetKey"]) for row in ready}):
        item = next(row for row in sorted(ready, key=lambda value: value["appearanceId"])
                    if row["autoCamera"]["presetKey"] == preset)
        selected.setdefault(item["appearanceId"], "FAMILY_STRATIFIED")
    chooser = random.Random(seed)
    for item in chooser.sample(sorted(ready, key=lambda value: value["appearanceId"]), min(24, len(ready))):
        selected.setdefault(item["appearanceId"], "SEEDED_RANDOM")
    fields = [
        "sampleKind", "appearanceId", "collectionKey", "route", "sourceSide", "sourceItemId", "itemLevel",
        "nativeDisplayId", "itemDisplayModel", "itemDisplayTexture", "resolvedModelPath", "resolvedSkinPath",
        "resolvedTexturePath", "modelArchive", "textureArchive", "cameraPreset",
    ]
    data: list[dict[str, Any]] = []
    by_id = {row["appearanceId"]: row for row in ready}
    for appearance_id in sorted(selected):
        row = by_id[appearance_id]
        primary = next(item for item in row["sourceItems"] if int(item["entry"]) == int(row["primarySourceItemId"]))
        display = row["nativeDisplay"]
        model_key = "leftModel" if row["sourceSide"] == "LEFT" else "rightModel"
        texture_key = "leftTexture" if row["sourceSide"] == "LEFT" else "rightTexture"
        data.append({
            "sampleKind": selected[appearance_id], "appearanceId": appearance_id, "collectionKey": row["collectionKey"],
            "route": row["route"], "sourceSide": row["sourceSide"], "sourceItemId": row["primarySourceItemId"],
            "itemLevel": primary["itemLevel"], "nativeDisplayId": row["nativeDisplayId"],
            "itemDisplayModel": display[model_key], "itemDisplayTexture": display[texture_key],
            "resolvedModelPath": row["model"]["internalPath"], "resolvedSkinPath": row["skin"]["internalPath"],
            "resolvedTexturePath": row["texture"]["internalPath"], "modelArchive": row["model"]["archiveName"],
            "textureArchive": row["texture"]["archiveName"], "cameraPreset": row["autoCamera"]["presetKey"],
        })
    return csv_text(fields, data)


def outlier_csv(rows: list[dict[str, Any]]) -> str:
    fields = ["appearanceId", "collectionKey", "scope", "route", "modelPath", "radius", "width", "depth",
              "height", "extentRatio", "outlierReasons"]
    data: list[dict[str, Any]] = []
    for row in sorted((row for row in rows if row.get("outlierReasons")), key=lambda item: item["appearanceId"]):
        bounds = row["bounds"]
        data.append({
            "appearanceId": row["appearanceId"], "collectionKey": row["collectionKey"],
            "scope": "PUBLIC" if row["public"] else "NONPUBLIC", "route": row["route"],
            "modelPath": row["model"]["internalPath"] if row["model"] else "", "radius": bounds["radius"],
            "width": bounds["width"], "depth": bounds["depth"], "height": bounds["height"],
            "extentRatio": row["autoCamera"]["extentRatio"] if row["autoCamera"] else "",
            "outlierReasons": ";".join(row["outlierReasons"]),
        })
    return csv_text(fields, data)


def render(root: Path, previous_path: Path | None) -> dict[str, str]:
    manifest, basis, reserved = load_inputs(root, verify_archives=False)
    plan = verify_hash_object(read_json(root / "asset-plan.json"), "assetPlanHash")
    index = verify_hash_object(read_json(root / "asset-index.json"), "assetIndexHash")
    require(plan.get("inputHash") == manifest["inputHash"] and index.get("inputHash") == manifest["inputHash"]
            and index.get("assetPlanHash") == plan["assetPlanHash"], "hydrated input hash drift")
    assets = {str(row["assetId"]): row for row in index["assets"]}
    require(len(assets) == len(index["assets"]), "duplicate asset index ID")
    rows = terminal_rows(
        plan, assets, preset_map(reserved),
        {int(row["appearanceId"]) for row in reserved["entries"]},
    )
    outliers, limits = apply_outliers(rows)
    result_registry = registry(rows, reserved, manifest["inputHash"], previous_registry(previous_path, manifest["inputHash"]))
    assigned = {int(row["appearanceId"]): row for row in result_registry["entries"]}
    public = [row for row in rows if row["public"]]
    require(all(row["terminalStatus"] in {"READY", "UNAVAILABLE"} for row in public), "public candidate missing terminal state")
    reasons = Counter(
        failure["reasonCode"] for row in public if row["terminalStatus"] == "UNAVAILABLE"
        for failure in row["failures"]
    )
    raw_source_reasons = Counter(
        failure["reasonCode"] for row in public if row["assetStatus"] == "UNAVAILABLE"
        for failure in row["failures"]
    )
    ready = [row for row in public if row["terminalStatus"] == "READY"]
    asset_ids = {
        asset["assetId"] for row in ready
        for asset in [row["model"], row["skin"], row["texture"], *row["hardcoded"]] if asset is not None
    }
    candidate_output = candidate_csv(rows, assigned)
    sample_output = sample_csv(rows, manifest["inputHash"])
    outlier_output = outlier_csv(rows)
    summary = {
        "schemaVersion": 1, "inputHash": manifest["inputHash"], "candidateBasisHash": basis["candidateBasisHash"],
        "assetPlanHash": plan["assetPlanHash"], "assetIndexHash": index["assetIndexHash"],
        "reservedImportHash": reserved["reservedImportHash"], "registryHash": result_registry["registryHash"],
        "denominators": {"public": EXPECTED_PUBLIC, "allWeaponCandidates": EXPECTED_ALL},
        "terminalCounts": {
            "publicReady": len(ready), "publicUnavailable": EXPECTED_PUBLIC - len(ready),
            "nonpublic": EXPECTED_ALL - EXPECTED_PUBLIC,
        },
        "reasonCodeCounts": dict(sorted(reasons.items())),
        "rawSourceAssetReasonCodeCounts": dict(sorted(raw_source_reasons.items())),
        "dedup": result_registry["dedup"],
        "sourceAssetEstimate": {
            "uniqueReferencedAssets": len(asset_ids),
            "bytes": sum(int(assets[key]["bytes"]) for key in asset_ids),
        },
        "cameraBaseline": {
            "presetCount": len(preset_map(reserved)), "outlierLimits": limits, "outlierCount": len(outliers),
            "cameraLayoutCounts": dict(sorted(Counter(
                row["autoCamera"]["cameraLayout"] for row in rows if row.get("autoCamera")
            ).items())),
        },
        "productionBoundary": {
            "appearancePresentationsModified": False, "dbcOrMpqDeployed": False,
            "assetBodiesCommittedToRepository": False,
        },
    }
    summary["candidateCsvSha256"] = hashlib.sha256(candidate_output.encode("utf-8")).hexdigest()
    summary["samplesCsvSha256"] = hashlib.sha256(sample_output.encode("utf-8")).hexdigest()
    summary["outliersCsvSha256"] = hashlib.sha256(outlier_output.encode("utf-8")).hexdigest()
    summary["summaryHash"] = hashlib.sha256(canonical(summary)).hexdigest()
    return {
        "shadow-summary.json": pretty(summary), "shadow-registry.json": pretty(result_registry),
        "shadow-candidates.csv": candidate_output, "shadow-samples.csv": sample_output,
        "shadow-outliers.csv": outlier_output,
    }


def audit(root: Path, output: Path, previous_path: Path | None, check: bool) -> dict[str, str]:
    root = ensure_f(root, "weapon shadow evidence root")
    result = render(root, previous_path)
    if check:
        for filename, text in result.items():
            path = output / filename
            require(path.is_file() and path.read_text(encoding="utf-8") == text, f"stale shadow review: {path}")
    else:
        for filename, text in result.items():
            write_text(output / filename, text)
    return result


def _runtime_csv_rows(path: Path) -> tuple[list[str], list[dict[str, str]]]:
    """Read a reviewed candidate CSV without silently changing its schema."""

    try:
        with path.open("r", encoding="utf-8-sig", newline="") as handle:
            reader = csv.DictReader(handle)
            fieldnames = list(reader.fieldnames or [])
            rows = [dict(row) for row in reader]
    except (OSError, UnicodeDecodeError, csv.Error) as exc:
        raise ShadowError(f"cannot read runtime candidate CSV {path}: {exc}") from exc
    require(fieldnames and "appearanceId" in fieldnames, "runtime candidate CSV has no appearanceId")
    required = {
        "scope", "terminalStatus", "assetStatus", "presentationStatus", "reasonCodes",
        "allocationStatus", "modelId", "syntheticDisplayId", "collectionKey", "primarySourceItemId",
    }
    require(required.issubset(fieldnames), "runtime candidate CSV schema is incomplete")
    ids = [int(row["appearanceId"]) for row in rows]
    require(len(ids) == len(set(ids)), "runtime candidate CSV duplicates appearance")
    return fieldnames, rows


def _runtime_csv_text(fieldnames: list[str], rows: list[dict[str, str]]) -> str:
    out = io.StringIO(newline="")
    writer = csv.DictWriter(out, fieldnames=fieldnames, lineterminator="\n")
    writer.writeheader()
    writer.writerows(sorted(rows, key=lambda row: int(row["appearanceId"])))
    return out.getvalue()


def _safe_evidence_relative(value: str) -> Path:
    text = value.strip().replace("\\", "/")
    pieces = text.split("/")
    require(
        text and not Path(text).is_absolute() and ":" not in text
        and all(piece not in {"", ".", ".."} for piece in pieces),
        f"unsafe runtime evidence path: {value!r}",
    )
    return Path(*pieces)


def _runtime_reason_counts(rows: Iterable[dict[str, str]]) -> dict[str, int]:
    values: Counter[str] = Counter()
    for row in rows:
        if row.get("scope") != "PUBLIC" or row.get("terminalStatus") != "UNAVAILABLE":
            continue
        for reason in str(row.get("reasonCodes", "")).split(";"):
            if reason and reason != "READY":
                values[reason] += 1
    return dict(sorted(values.items()))


def _runtime_registry(
    base_registry: dict[str, Any],
    candidates: dict[int, dict[str, str]],
    quarantines: dict[int, dict[str, Any]],
) -> dict[str, Any]:
    """Move runtime-unsafe active records to permanent, non-recyclable tombstones."""

    result = deepcopy(base_registry)
    entries: list[dict[str, Any]] = []
    tombstones = [deepcopy(row) for row in result.get("tombstones", [])]
    seen_tombstones = {int(row["appearanceId"]) for row in tombstones}
    for entry in result.get("entries", []):
        appearance_id = int(entry["appearanceId"])
        candidate = candidates.get(appearance_id)
        require(candidate is not None, f"runtime registry entry absent from candidates: {appearance_id}")
        quarantine = quarantines.get(appearance_id)
        if quarantine is None:
            entries.append(deepcopy(entry))
            continue
        require(entry.get("allocationStatus") == "ACTIVE", f"runtime quarantine is not active: {appearance_id}")
        require(candidate.get("scope") == "PUBLIC", f"runtime quarantine is not public: {appearance_id}")
        require(candidate.get("terminalStatus") == "UNAVAILABLE", f"runtime quarantine was not applied: {appearance_id}")
        require(appearance_id not in seen_tombstones, f"runtime quarantine already tombstoned: {appearance_id}")
        tombstone = deepcopy(entry)
        tombstone["allocationStatus"] = "TOMBSTONE"
        tombstone["tombstoneReason"] = str(quarantine["reasonCode"])
        tombstone["runtimeQuarantineId"] = str(quarantine["quarantineId"])
        tombstones.append(tombstone)
        seen_tombstones.add(appearance_id)

    require(len(entries) + len(tombstones) >= len(base_registry.get("entries", [])), "runtime registry lost records")
    require(
        not ({int(row["appearanceId"]) for row in entries} & seen_tombstones),
        "runtime registry recycled tombstone",
    )
    active = [row for row in entries if row.get("allocationStatus") == "ACTIVE"]
    reserved = [row for row in entries if row.get("allocationStatus") == "RESERVED"]
    require(len(reserved) == EXPECTED_RESERVED, "runtime registry reserved baseline drift")
    require(all(row.get("allocationStatus") in {"ACTIVE", "RESERVED"} for row in entries),
            "runtime registry has unsupported active allocation")
    result["entries"] = sorted(entries, key=lambda row: int(row["appearanceId"]))
    result["tombstones"] = sorted(tombstones, key=lambda row: int(row["appearanceId"]))
    result["dedup"] = {
        "readyPublicAppearances": sum(
            row.get("scope") == "PUBLIC" and row.get("terminalStatus") == "READY"
            for row in candidates.values()
        ),
        "reservedAppearances": len(reserved),
        "newlyAllocatedAppearances": len(active),
        "uniqueNewGeometry": len({str(row["geometryKey"]) for row in active}),
        "uniqueNewDisplays": len({str(row["displayKey"]) for row in active}),
        "reusedGeometryAppearances": len(active) - len({str(row["geometryKey"]) for row in active}),
        "reusedDisplayAppearances": len(active) - len({str(row["displayKey"]) for row in active}),
    }
    result.pop("registryHash", None)
    result["registryHash"] = hashlib.sha256(canonical(result)).hexdigest()
    return result


def _load_runtime_quarantine(
    path: Path,
    base_summary: dict[str, Any],
    base_registry: dict[str, Any],
    base_candidate_bytes: bytes,
    candidate_by_appearance: dict[int, dict[str, str]],
    evidence_root: Path,
) -> tuple[dict[str, Any], dict[int, dict[str, Any]]]:
    value = verify_hash_object(read_json(path), "quarantineHash")
    require(value.get("schemaVersion") == 1, "unsupported runtime quarantine schema")
    base = value.get("baseReview")
    require(isinstance(base, dict), "runtime quarantine lacks base review lock")
    require(base.get("summaryHash") == base_summary.get("summaryHash"), "runtime quarantine summary drift")
    require(base.get("registryHash") == base_registry.get("registryHash"), "runtime quarantine registry drift")
    require(base.get("candidateCsvSha256") == hashlib.sha256(base_candidate_bytes).hexdigest(),
            "runtime quarantine candidate CSV drift")
    entries = value.get("entries")
    require(isinstance(entries, list) and entries, "runtime quarantine has no entries")
    by_appearance: dict[int, dict[str, Any]] = {}
    for raw in entries:
        require(isinstance(raw, dict), "runtime quarantine entry is not an object")
        appearance_id = int(raw.get("appearanceId", 0))
        require(appearance_id > 0 and appearance_id not in by_appearance,
                f"invalid or duplicate runtime quarantine appearance: {appearance_id}")
        required = (
            "quarantineId", "reasonCode", "collectionKey", "sourceItemId", "modelId",
            "syntheticDisplayId", "modelSignature", "evidenceFiles",
        )
        require(all(raw.get(name) not in (None, "") for name in required),
                f"runtime quarantine entry is incomplete: {appearance_id}")
        require(str(raw["reasonCode"]).startswith("CLIENT_RUNTIME_"),
                f"runtime quarantine reason is not client-scoped: {appearance_id}")
        candidate = candidate_by_appearance.get(appearance_id)
        require(candidate is not None, f"runtime quarantine candidate absent: {appearance_id}")
        require(candidate.get("scope") == "PUBLIC" and candidate.get("terminalStatus") == "READY",
                f"runtime quarantine candidate is not public READY: {appearance_id}")
        registry_entry = next(
            (row for row in base_registry.get("entries", []) if int(row["appearanceId"]) == appearance_id),
            None,
        )
        require(registry_entry is not None and registry_entry.get("allocationStatus") == "ACTIVE",
                f"runtime quarantine registry entry is not active: {appearance_id}")
        for key, expected in (
            ("collectionKey", candidate.get("collectionKey")),
            ("sourceItemId", candidate.get("primarySourceItemId")),
            ("modelId", registry_entry.get("modelId")),
            ("syntheticDisplayId", registry_entry.get("syntheticDisplayId")),
            ("modelSignature", registry_entry.get("modelSignature")),
        ):
            require(str(raw[key]) == str(expected), f"runtime quarantine {key} drift: {appearance_id}")
        evidence_files = raw["evidenceFiles"]
        require(isinstance(evidence_files, list) and evidence_files,
                f"runtime quarantine lacks evidence files: {appearance_id}")
        for evidence in evidence_files:
            require(isinstance(evidence, dict), f"runtime evidence is invalid: {appearance_id}")
            relative = _safe_evidence_relative(str(evidence.get("relativePath", "")))
            target = evidence_root / relative
            require(target.is_file(), f"runtime evidence is missing: {relative}")
            require(target.stat().st_size == int(evidence.get("size", -1))
                    and sha(target) == str(evidence.get("sha256", "")).lower(),
                    f"runtime evidence hash drift: {relative}")
        by_appearance[appearance_id] = deepcopy(raw)
    return value, by_appearance


def render_runtime_projection(
    review_root: Path,
    quarantine_path: Path,
    evidence_root: Path,
) -> dict[str, str]:
    """Create a runtime-safe review projection from the immutable Stage 6 review.

    Asset extraction may prove a model is structurally complete while an actual
    3.3.5 client still rejects it.  Such a model is not allowed to remain an
    active synthetic display: it becomes a tombstone with a client-runtime
    reason, while the source review remains unchanged for forensic replay.
    """

    review_root = ensure_f(review_root, "runtime base review root")
    evidence_root = ensure_f(evidence_root, "runtime evidence root")
    summary_path = review_root / "shadow-summary.json"
    registry_path = review_root / "shadow-registry.json"
    candidates_path = review_root / "shadow-candidates.csv"
    summary = verify_hash_object(read_json(summary_path), "summaryHash")
    registry_value = verify_hash_object(read_json(registry_path), "registryHash")
    require(summary.get("registryHash") == registry_value.get("registryHash"), "runtime review registry drift")
    candidate_bytes = candidates_path.read_bytes()
    require(hashlib.sha256(candidate_bytes).hexdigest() == summary.get("candidateCsvSha256"),
            "runtime review candidate CSV drift")
    fieldnames, rows = _runtime_csv_rows(candidates_path)
    by_appearance = {int(row["appearanceId"]): row for row in rows}
    require(len(by_appearance) == len(rows), "runtime review duplicate candidate")
    quarantine, quarantine_by_appearance = _load_runtime_quarantine(
        quarantine_path, summary, registry_value, candidate_bytes, by_appearance, evidence_root
    )

    for appearance_id, verdict in quarantine_by_appearance.items():
        row = by_appearance[appearance_id]
        row["terminalStatus"] = "UNAVAILABLE"
        row["presentationStatus"] = "RUNTIME_UNAVAILABLE"
        row["reasonCodes"] = str(verdict["reasonCode"])
        row["missingRelativePaths"] = ""
        row["allocationStatus"] = "TOMBSTONE"

    runtime_registry = _runtime_registry(registry_value, by_appearance, quarantine_by_appearance)
    candidate_output = _runtime_csv_text(fieldnames, rows)
    terminal_counts = {
        "publicReady": sum(row.get("scope") == "PUBLIC" and row.get("terminalStatus") == "READY" for row in rows),
        "publicUnavailable": sum(row.get("scope") == "PUBLIC" and row.get("terminalStatus") == "UNAVAILABLE" for row in rows),
        "nonpublic": sum(row.get("scope") != "PUBLIC" for row in rows),
    }
    denominators = summary.get("denominators", {})
    expected_public = int(denominators.get("public", -1))
    expected_all = int(denominators.get("allWeaponCandidates", -1))
    require(expected_public > 0 and expected_all >= expected_public, "runtime projection denominator schema drift")
    require(terminal_counts["publicReady"] + terminal_counts["publicUnavailable"] == expected_public,
            "runtime projection public denominator drift")
    require(terminal_counts["nonpublic"] == expected_all - expected_public,
            "runtime projection non-public denominator drift")
    runtime_summary = deepcopy(summary)
    runtime_summary["registryHash"] = runtime_registry["registryHash"]
    runtime_summary["candidateCsvSha256"] = hashlib.sha256(candidate_output.encode("utf-8")).hexdigest()
    runtime_summary["terminalCounts"] = terminal_counts
    runtime_summary["reasonCodeCounts"] = _runtime_reason_counts(rows)
    runtime_summary["dedup"] = runtime_registry["dedup"]
    runtime_summary["runtimeQuarantine"] = {
        "quarantineHash": quarantine["quarantineHash"],
        "count": len(quarantine_by_appearance),
        "reasonCodeCounts": dict(sorted(Counter(
            str(row["reasonCode"]) for row in quarantine_by_appearance.values()
        ).items())),
    }
    runtime_summary.pop("summaryHash", None)
    runtime_summary["summaryHash"] = hashlib.sha256(canonical(runtime_summary)).hexdigest()
    projection = {
        "schemaVersion": 1,
        "kind": "SoloCollectionsWeaponRuntimeProjection",
        "baseReview": {
            "summaryHash": summary["summaryHash"],
            "registryHash": registry_value["registryHash"],
            "candidateCsvSha256": hashlib.sha256(candidate_bytes).hexdigest(),
        },
        "runtimeQuarantineHash": quarantine["quarantineHash"],
        "runtimeQuarantines": [
            {
                "appearanceId": appearance_id,
                "quarantineId": str(row["quarantineId"]),
                "reasonCode": str(row["reasonCode"]),
                "modelId": int(row["modelId"]),
                "syntheticDisplayId": int(row["syntheticDisplayId"]),
            }
            for appearance_id, row in sorted(quarantine_by_appearance.items())
        ],
        "result": {
            "summaryHash": runtime_summary["summaryHash"],
            "registryHash": runtime_registry["registryHash"],
            "candidateCsvSha256": runtime_summary["candidateCsvSha256"],
            "terminalCounts": terminal_counts,
        },
    }
    projection["runtimeProjectionHash"] = hashlib.sha256(canonical(projection)).hexdigest()
    return {
        "shadow-summary.json": pretty(runtime_summary),
        "shadow-registry.json": pretty(runtime_registry),
        "shadow-candidates.csv": candidate_output,
        "runtime-projection.json": pretty(projection),
    }


def runtime_projection(
    review_root: Path,
    quarantine_path: Path,
    evidence_root: Path,
    output: Path,
    check: bool,
) -> dict[str, Any]:
    output = ensure_f(output, "runtime projection output")
    result = render_runtime_projection(review_root, quarantine_path, evidence_root)
    if check:
        for filename, text in result.items():
            path = output / filename
            require(path.is_file() and path.read_text(encoding="utf-8") == text,
                    f"stale runtime projection: {path}")
    else:
        require(not output.exists(), f"runtime projection output must be absent: {output}")
        temporary = output.with_name(output.name + ".tmp-" + hashlib.sha256(os.urandom(32)).hexdigest()[:12])
        require(not temporary.exists(), f"runtime projection temporary exists: {temporary}")
        temporary.mkdir(parents=True)
        try:
            for filename, text in result.items():
                write_text(temporary / filename, text)
            os.replace(temporary, output)
        except Exception:
            # Keep non-target diagnostics intact; a partial requested output is
            # never published as a valid runtime projection.
            raise
    projection = verify_hash_object(read_json(output / "runtime-projection.json"), "runtimeProjectionHash")
    return {
        "output": str(output),
        "runtimeProjectionHash": projection["runtimeProjectionHash"],
        "runtimeQuarantineCount": len(projection["runtimeQuarantines"]),
        "terminalCounts": projection["result"]["terminalCounts"],
    }


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest="command", required=True)
    capture_parser = commands.add_parser("capture")
    capture_parser.add_argument("--evidence-root", type=Path, required=True)
    capture_parser.add_argument("--fixed-input-root", type=Path, required=True)
    capture_parser.add_argument("--client-data-root", type=Path, required=True)
    capture_parser.add_argument("--mpqcli", type=Path, required=True)
    capture_parser.add_argument("--visibility-evidence", type=Path, required=True)
    capture_parser.add_argument("--appearance-sources", type=Path, required=True)
    capture_parser.add_argument("--presentation-source", type=Path, required=True)
    capture_parser.add_argument("--world-item-template-sql", type=Path, required=True)
    hydrate_parser = commands.add_parser("hydrate")
    hydrate_parser.add_argument("--evidence-root", type=Path, required=True)
    hydrate_parser.add_argument("--mpqcli", type=Path, required=True)
    hydrate_parser.add_argument("--stormlib", type=Path, required=True)
    for name in ("audit", "check"):
        current = commands.add_parser(name)
        current.add_argument("--evidence-root", type=Path, required=True)
        current.add_argument("--output-dir", type=Path, required=True)
        current.add_argument("--previous-registry", type=Path)
    for name in ("runtime-projection", "runtime-check"):
        current = commands.add_parser(name)
        current.add_argument("--review-root", type=Path, required=True)
        current.add_argument("--runtime-quarantine", type=Path, required=True)
        current.add_argument("--runtime-evidence-root", type=Path, required=True)
        current.add_argument("--output-dir", type=Path, required=True)
    args = parser.parse_args(argv)
    try:
        if args.command == "capture":
            capture(args.evidence_root, args.fixed_input_root, args.client_data_root, args.mpqcli,
                    args.visibility_evidence, args.appearance_sources, args.presentation_source,
                    args.world_item_template_sql)
        elif args.command == "hydrate":
            hydrate(args.evidence_root, args.mpqcli, args.stormlib)
        elif args.command in {"runtime-projection", "runtime-check"}:
            print(json.dumps(runtime_projection(
                args.review_root, args.runtime_quarantine, args.runtime_evidence_root,
                args.output_dir, args.command == "runtime-check",
            ), ensure_ascii=False, sort_keys=True))
        else:
            audit(args.evidence_root, args.output_dir, args.previous_registry, args.command == "check")
    except (ShadowError, OSError, struct.error, subprocess.SubprocessError) as exc:
        parser.error(str(exc))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
