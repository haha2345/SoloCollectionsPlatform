#!/usr/bin/env python3
"""Extract, generate and verify the WotLK character camera profile matrix."""

from __future__ import annotations

import argparse
import hashlib
import json
import math
import shutil
import struct
import subprocess
from pathlib import Path
from typing import Any


SLOTS = ("HEAD", "SHOULDER", "BACK", "CHEST", "WRIST", "HANDS", "WAIST", "LEGS", "FEET")
SEXES = ("MALE", "FEMALE")
RACE_MODELS = {
    "human": ("Human", 1),
    "orc": ("Orc", 2),
    "dwarf": ("Dwarf", 3),
    "night_elf": ("NightElf", 4),
    "undead": ("Scourge", 5),
    "tauren": ("Tauren", 6),
    "gnome": ("Gnome", 7),
    "troll": ("Troll", 8),
    "blood_elf": ("BloodElf", 10),
    "draenei": ("Draenei", 11),
}
ARCHIVE_PRIORITY = (
    "patch-3.MPQ", "patch-2.MPQ", "patch.MPQ", "lichking.MPQ",
    "expansion.MPQ", "common-2.MPQ", "common.MPQ",
)
M2_BOUNDS_OFFSET = 160
NEW_SENTINEL_BASE = 0x6000
RESERVED_ITEM_CAMERA_MIN = 0x51000000


class CameraProfileError(RuntimeError):
    pass


def _require(condition: bool, message: str) -> None:
    if not condition:
        raise CameraProfileError(message)


def _read_json(path: Path) -> Any:
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except (OSError, UnicodeDecodeError, json.JSONDecodeError) as exc:
        raise CameraProfileError(f"cannot read JSON {path}: {exc}") from exc


def _sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def _json_bytes(value: Any) -> bytes:
    return (json.dumps(value, ensure_ascii=False, sort_keys=True, separators=(",", ":")) + "\n").encode("utf-8")


def _pretty(value: Any) -> str:
    return json.dumps(value, ensure_ascii=False, sort_keys=True, indent=2) + "\n"


def _dbc_header(path: Path) -> dict[str, int]:
    data = path.read_bytes()
    _require(len(data) >= 20 and data[:4] == b"WDBC", f"invalid WDBC header: {path}")
    records, fields, record_size, strings = struct.unpack_from("<4I", data, 4)
    _require(len(data) >= 20 + records * record_size + strings, f"truncated DBC: {path}")
    return {"records": records, "fields": fields, "recordSize": record_size, "stringBytes": strings}


def _chr_race_ids(path: Path) -> set[int]:
    header = _dbc_header(path)
    data = path.read_bytes()
    return {struct.unpack_from("<I", data, 20 + index * header["recordSize"])[0] for index in range(header["records"])}


def _dbc_records(path: Path) -> tuple[list[tuple[int, ...]], bytes]:
    header = _dbc_header(path)
    _require(header["recordSize"] % 4 == 0, f"non-32-bit DBC record: {path}")
    data = path.read_bytes()
    field_count = header["recordSize"] // 4
    records = [
        struct.unpack_from("<" + "I" * field_count, data, 20 + index * header["recordSize"])
        for index in range(header["records"])
    ]
    strings_offset = 20 + header["records"] * header["recordSize"]
    return records, data[strings_offset:strings_offset + header["stringBytes"]]


def _dbc_string(strings: bytes, offset: int) -> str:
    _require(0 <= offset < len(strings), f"DBC string offset out of range: {offset}")
    end = strings.find(b"\0", offset)
    _require(end >= 0, f"unterminated DBC string at offset {offset}")
    return strings[offset:end].decode("utf-8", errors="replace")


def _preview_display_info(model_data_path: Path, display_info_path: Path) -> dict[str, dict[str, Any]]:
    model_rows, model_strings = _dbc_records(model_data_path)
    model_ids: dict[str, list[int]] = {}
    for row in model_rows:
        _require(len(row) >= 3, "CreatureModelData.dbc record is too short")
        model_path = _dbc_string(model_strings, row[2]).replace("/", "\\").lower()
        if model_path.startswith("character\\"):
            model_ids.setdefault(model_path, []).append(int(row[0]))

    display_rows, _ = _dbc_records(display_info_path)
    candidates: dict[int, list[dict[str, Any]]] = {}
    for row in display_rows:
        _require(len(row) >= 5, "CreatureDisplayInfo.dbc record is too short")
        model_id = int(row[1])
        extended_id = int(row[3])
        scale = struct.unpack("<f", struct.pack("<I", row[4]))[0]
        if any(model_id in values for values in model_ids.values()) and extended_id > 0 and math.isfinite(scale) and scale > 0:
            candidates.setdefault(model_id, []).append({
                "previewDisplayId": int(row[0]),
                "modelDataId": model_id,
                "extendedDisplayInfoId": extended_id,
                "previewDisplayScale": round(scale, 8),
            })

    result: dict[str, dict[str, Any]] = {}
    for path, path_model_ids in model_ids.items():
        rows = [row for model_id in path_model_ids for row in candidates.get(model_id, [])]
        if not rows:
            continue
        rows.sort(key=lambda row: (abs(float(row["previewDisplayScale"]) - 1.0), int(row["previewDisplayId"])))
        result[path] = rows[0]
    return result


def _m2_bounds(path: Path) -> dict[str, Any]:
    data = path.read_bytes()
    _require(len(data) >= M2_BOUNDS_OFFSET + 24 and data[:4] == b"MD20", f"invalid WotLK M2: {path}")
    version = struct.unpack_from("<I", data, 4)[0]
    _require(version == 264, f"unexpected M2 version {version}: {path}")
    values = struct.unpack_from("<6f", data, M2_BOUNDS_OFFSET)
    _require(all(math.isfinite(value) for value in values), f"non-finite M2 bounds: {path}")
    min_x, min_y, min_z, max_x, max_y, max_z = values
    _require(min_x < max_x and min_y < max_y and min_z < max_z, f"invalid M2 bounds: {path}")
    height = max_z - min_z
    width = max(max_x - min_x, max_y - min_y)
    return {
        "min": {"x": round(min_x, 6), "y": round(min_y, 6), "z": round(min_z, 6)},
        "max": {"x": round(max_x, 6), "y": round(max_y, 6), "z": round(max_z, 6)},
        "height": round(height, 6),
        "width": round(width, 6),
        "centerZ": round((max_z + min_z) / 2.0, 6),
    }


def _model_path(folder: str, sex: str) -> str:
    display_sex = "Male" if sex == "MALE" else "Female"
    return f"Character\\{folder}\\{display_sex}\\{folder}{display_sex}.m2"


def extract(client_root: Path, evidence_root: Path, mpqcli: Path) -> dict[str, Any]:
    _require(client_root.is_dir(), f"client root missing: {client_root}")
    _require(mpqcli.is_file(), f"mpqcli missing: {mpqcli}")
    dbc_root = client_root / "dbc"
    dbc_names = ("ChrRaces.dbc", "CreatureDisplayInfo.dbc", "CreatureModelData.dbc")
    dbcs: dict[str, Any] = {}
    for name in dbc_names:
        path = dbc_root / name
        _require(path.is_file(), f"DBC missing: {path}")
        dbcs[name] = {"path": str(path), "sha256": _sha256(path), **_dbc_header(path)}
    available_ids = _chr_race_ids(dbc_root / "ChrRaces.dbc")
    _require({value[1] for value in RACE_MODELS.values()} <= available_ids, "ChrRaces.dbc lacks a native race")
    preview_by_model = _preview_display_info(
        dbc_root / "CreatureModelData.dbc",
        dbc_root / "CreatureDisplayInfo.dbc",
    )

    model_root = evidence_root / "models"
    scratch = evidence_root / "_extract_tmp"
    model_root.mkdir(parents=True, exist_ok=True)
    models: list[dict[str, Any]] = []
    for race_key, (folder, runtime_id) in RACE_MODELS.items():
        for sex in SEXES:
            archive_path = _model_path(folder, sex)
            selected: Path | None = None
            selected_archive: str | None = None
            for archive_name in ARCHIVE_PRIORITY:
                archive = client_root / "Data" / archive_name
                if not archive.is_file():
                    continue
                attempt = scratch / race_key / sex / archive_name.replace(".", "_")
                if attempt.exists():
                    shutil.rmtree(attempt)
                attempt.mkdir(parents=True)
                result = subprocess.run(
                    [str(mpqcli), "extract", str(archive), "-f", archive_path, "-o", str(attempt)],
                    stdout=subprocess.PIPE,
                    stderr=subprocess.PIPE,
                    text=True,
                    check=False,
                )
                candidate = attempt / Path(archive_path).name
                if result.returncode == 0 and candidate.is_file():
                    target = model_root / race_key / sex / candidate.name
                    target.parent.mkdir(parents=True, exist_ok=True)
                    shutil.copyfile(candidate, target)
                    selected = target
                    selected_archive = archive_name
                    break
            _require(selected is not None, f"cannot extract {archive_path}")
            preview_key = archive_path.replace(".m2", ".mdx").lower()
            preview = preview_by_model.get(preview_key)
            _require(preview is not None, f"no textured preview display for {archive_path}")
            models.append({
                "cameraProfile": f"race.{race_key}",
                "raceKey": race_key,
                "runtimeRaceId": runtime_id,
                "sex": sex,
                "assetPath": archive_path,
                "sourceArchive": selected_archive,
                "evidencePath": str(selected),
                "sha256": _sha256(selected),
                "bytes": selected.stat().st_size,
                "bounds": _m2_bounds(selected),
                **preview,
            })
    if scratch.exists():
        shutil.rmtree(scratch)
    manifest = {
        "schemaVersion": 1,
        "sourceBuild": "3.3.5.12340",
        "clientRoot": str(client_root),
        "clientAssetProfile": "wotlk-3.3.5.12340-client11",
        "dbc": dbcs,
        "models": models,
    }
    manifest["evidenceHash"] = hashlib.sha256(_json_bytes(manifest)).hexdigest()
    output = evidence_root / "camera-profile-evidence.json"
    output.write_text(_pretty(manifest), encoding="utf-8", newline="\n")
    return manifest


def _load_inputs(repo_root: Path, evidence_root: Path) -> tuple[dict[str, Any], dict[str, Any], dict[str, Any]]:
    races = _read_json(repo_root / "catalog/source/races.json")
    overrides = _read_json(repo_root / "catalog/source/overrides/camera_profiles.json")
    evidence = _read_json(evidence_root / "camera-profile-evidence.json")
    _require(races.get("schemaVersion") == 1, "unsupported races schema")
    _require(overrides.get("schemaVersion") == 1, "unsupported camera override schema")
    _require(evidence.get("schemaVersion") == 1 and len(evidence.get("models", [])) == 20,
             "camera evidence must contain 20 native models")
    locked_hash = evidence.pop("evidenceHash", None)
    _require(locked_hash == hashlib.sha256(_json_bytes(evidence)).hexdigest(), "camera evidence hash drift")
    evidence["evidenceHash"] = locked_hash
    for model in evidence["models"]:
        path = Path(model["evidencePath"])
        _require(path.is_file() and _sha256(path) == model["sha256"], f"M2 evidence drift: {path}")
        _require(_m2_bounds(path) == model["bounds"], f"M2 bounds drift: {path}")
    for dbc in evidence["dbc"].values():
        path = Path(dbc["path"])
        _require(path.is_file() and _sha256(path) == dbc["sha256"], f"DBC evidence drift: {path}")
    return races, overrides, evidence


def build_canonical(repo_root: Path, evidence_root: Path) -> dict[str, Any]:
    races, overrides, evidence = _load_inputs(repo_root, evidence_root)
    race_entries = races.get("entries", [])
    _require(len(race_entries) == 10, "exactly 10 native logical races are required")
    models = {(row["cameraProfile"], row["sex"]): row for row in evidence["models"]}
    reference = overrides.get("reference", {})
    reference_key = (reference.get("cameraProfile"), reference.get("sex"))
    reference_model = models.get(reference_key)
    _require(reference_model is not None, "human/female reference model is missing")
    reference_slots = {row["slot"]: row for row in reference.get("slots", [])}
    _require(tuple(row["slot"] for row in reference.get("slots", [])) == SLOTS, "reference slot order drift")
    override_rows = {(row["cameraProfile"], row["sex"], row["slot"]): row for row in overrides.get("entries", [])}

    sentinels: set[int] = set()
    next_sentinel = NEW_SENTINEL_BASE
    profiles: list[dict[str, Any]] = []
    canonical_models: list[dict[str, Any]] = []
    for race in race_entries:
        race_key = race["raceKey"]
        camera_profile = f"race.{race_key}"
        _require(race.get("clientAssetProfile") == camera_profile, f"client asset profile drift: {race_key}")
        _require(race.get("cameraProfile") == camera_profile, f"camera profile family drift: {race_key}")
        for sex in SEXES:
            model = models.get((camera_profile, sex))
            _require(model is not None, f"missing model evidence: {camera_profile}/{sex}")
            canonical_models.append({key: model[key] for key in (
                "cameraProfile", "raceKey", "runtimeRaceId", "sex", "assetPath",
                "sourceArchive", "sha256", "bytes", "bounds", "previewDisplayId",
                "modelDataId", "extendedDisplayInfoId", "previewDisplayScale",
            )})
            for slot in SLOTS:
                ref = reference_slots[slot]
                if (camera_profile, sex) == reference_key:
                    sentinel = int(ref["sentinel"])
                    values = {key: float(ref[key]) for key in (
                        "verticalOffset", "distanceScale", "minimumDistance", "horizontalOffset", "yawOffset",
                    )}
                    status = "verified"
                else:
                    while next_sentinel in sentinels or next_sentinel in {0, 1}:
                        next_sentinel += 1
                    sentinel = next_sentinel
                    next_sentinel += 1
                    ref_bounds = reference_model["bounds"]
                    target_bounds = model["bounds"]
                    values = {
                        "verticalOffset": float(ref["verticalOffset"]) / ref_bounds["height"] * target_bounds["height"],
                        "distanceScale": float(ref["distanceScale"]),
                        "minimumDistance": float(ref["minimumDistance"]) / max(ref_bounds["height"], ref_bounds["width"])
                            * max(target_bounds["height"], target_bounds["width"]),
                        "horizontalOffset": float(ref["horizontalOffset"]) / ref_bounds["width"] * target_bounds["width"],
                        "yawOffset": float(ref["yawOffset"]),
                    }
                    status = "scaled"
                override = override_rows.get((camera_profile, sex, slot))
                if override:
                    values["verticalOffset"] += float(override.get("centerZCorrection", 0.0))
                    for key in values:
                        if key in override:
                            values[key] = float(override[key])
                    status = override.get("status", status)
                _require(sentinel not in sentinels and sentinel < RESERVED_ITEM_CAMERA_MIN, "camera sentinel collision")
                sentinels.add(sentinel)
                profile = {
                    "cameraProfile": camera_profile,
                    "clientAssetProfile": race["clientAssetProfile"],
                    "raceKey": race_key,
                    "runtimeRaceId": int(race["runtimeRaceId"]),
                    "sex": sex,
                    "slot": slot,
                    "sentinel": sentinel,
                    "status": status,
                    **{key: round(value, 8) for key, value in values.items()},
                }
                _require(all(math.isfinite(float(profile[key])) for key in values), "non-finite camera profile")
                _require(0.05 <= profile["distanceScale"] <= 4.0, "unsafe distance scale")
                _require(0.05 <= profile["minimumDistance"] <= 8.0, "unsafe minimum distance")
                _require(abs(profile["verticalOffset"]) <= 8.0 and abs(profile["horizontalOffset"]) <= 4.0,
                         "unsafe camera offset")
                profiles.append(profile)

    _require(len(profiles) == 180 and len(sentinels) == 180, "camera matrix must contain 180 unique profiles")
    reserved = {int(row["sentinel"]): row for row in reference.get("slots", [])}
    for profile in profiles:
        if profile["cameraProfile"] == "race.human" and profile["sex"] == "FEMALE":
            _require(profile["sentinel"] in reserved, "human/female sentinel drift")
    canonical = {
        "schemaVersion": 1,
        "profileVersion": 1,
        "sourceBuild": evidence["sourceBuild"],
        "clientAssetProfile": evidence["clientAssetProfile"],
        "evidenceHash": evidence["evidenceHash"],
        "sourceEvidence": {
            "dbc": {name: {key: value for key, value in row.items() if key != "path"}
                    for name, row in evidence["dbc"].items()},
            "overridesSha256": _sha256(repo_root / "catalog/source/overrides/camera_profiles.json"),
            "racesSha256": _sha256(repo_root / "catalog/source/races.json"),
        },
        "slotOrder": list(SLOTS),
        "models": canonical_models,
        "profiles": profiles,
    }
    canonical["profileHash"] = hashlib.sha256(_json_bytes(canonical)).hexdigest()
    return canonical


def _validate_canonical(canonical: dict[str, Any]) -> None:
    locked = canonical.pop("profileHash", None)
    _require(locked == hashlib.sha256(_json_bytes(canonical)).hexdigest(), "canonical camera profile hash drift")
    canonical["profileHash"] = locked
    profiles = canonical.get("profiles", [])
    _require(canonical.get("slotOrder") == list(SLOTS), "canonical slot order drift")
    _require(len(profiles) == 180, "canonical camera matrix must contain 180 profiles")
    _require(len({int(row["sentinel"]) for row in profiles}) == 180, "canonical sentinels are not unique")


def _render_lua(canonical: dict[str, Any]) -> str:
    families: dict[str, dict[str, dict[str, int]]] = {}
    runtime: dict[str, str] = {}
    for row in canonical["profiles"]:
        families.setdefault(row["cameraProfile"], {}).setdefault(row["sex"], {})[row["slot"]] = int(row["sentinel"])
        runtime[row["raceKey"]] = row["cameraProfile"]
    alias = {"human": "Human", "orc": "Orc", "dwarf": "Dwarf", "night_elf": "NightElf", "undead": "Scourge",
             "tauren": "Tauren", "gnome": "Gnome", "troll": "Troll", "blood_elf": "BloodElf", "draenei": "Draenei"}
    lines = [
        "local SC = SoloCollections", "", "SC.CameraProfiles = SC.CameraProfiles or {}", "",
        "local CameraProfiles = SC.CameraProfiles",
        f"CameraProfiles.schemaVersion = {canonical['schemaVersion']}",
        f"CameraProfiles.profileVersion = {canonical['profileVersion']}",
        f'CameraProfiles.profileHash = "{canonical["profileHash"]}"',
        'CameraProfiles.mode = CameraProfiles.mode or "Generated"', "",
        "CameraProfiles.slotOrder = { " + ", ".join(f'"{slot}"' for slot in SLOTS) + " }", "",
        "CameraProfiles.runtimeRaceProfiles = {",
    ]
    for race_key in RACE_MODELS:
        lines.append(f'    {alias[race_key]} = "{runtime[race_key]}",')
    lines += ["}", "", "CameraProfiles.entries = {"]
    for family in sorted(families):
        lines.append(f'    ["{family}"] = {{')
        for sex in SEXES:
            values = families[family][sex]
            lines.append(f"        {sex} = {{ " + ", ".join(f"{slot} = 0x{values[slot]:04X}" for slot in SLOTS) + " },")
        lines.append("    },")
    model_paths: dict[str, dict[str, str]] = {}
    preview_ids: dict[str, dict[str, int]] = {}
    for model in canonical["models"]:
        model_paths.setdefault(model["cameraProfile"], {})[model["sex"]] = model["assetPath"]
        preview_ids.setdefault(model["cameraProfile"], {})[model["sex"]] = int(model["previewDisplayId"])
    lines += [
        "}", "", "CameraProfiles.modelPaths = {",
    ]
    for family in sorted(model_paths):
        values = model_paths[family]
        lines.append(
            f'    ["{family}"] = {{ MALE = "{values["MALE"].replace(chr(92), chr(92) * 2)}", '
            f'FEMALE = "{values["FEMALE"].replace(chr(92), chr(92) * 2)}" }},'
        )
    lines += [
        "}", "", "CameraProfiles.previewDisplayIds = {",
    ]
    for family in sorted(preview_ids):
        values = preview_ids[family]
        lines.append(f'    ["{family}"] = {{ MALE = {values["MALE"]}, FEMALE = {values["FEMALE"]} }},')
    lines += [
        "}", "", "function CameraProfiles.SetMode(mode)",
        '    if mode ~= "LegacyHumanFemale" and mode ~= "Compare" and mode ~= "Generated" and mode ~= "Native" then',
        "        return false", "    end", "    CameraProfiles.mode = mode", "    return true", "end", "",
        "function CameraProfiles.GetSentinel(raceToken, sex, slot, clientAssetProfile)",
        '    if CameraProfiles.mode == "Native" then return nil end',
        "    local family = CameraProfiles.runtimeRaceProfiles[raceToken]", "    if not family then return nil end",
        "    if clientAssetProfile and clientAssetProfile ~= family then return nil end",
        '    local sexKey = sex == 2 and "MALE" or (sex == 3 and "FEMALE" or nil)',
        "    if not sexKey then return nil end",
        "    local familyEntries = CameraProfiles.entries[family]", "    local sexEntries = familyEntries and familyEntries[sexKey]",
        "    local generated = sexEntries and sexEntries[slot] or nil",
        '    if CameraProfiles.mode == "Compare" then',
        "        -- Ephemeral diagnostics only: do not persist a second mutable profile table.",
        "        CameraProfiles.lastComparison = { family = family, sex = sexKey, slot = slot, generated = generated }",
        '        if family ~= "race.human" or sexKey ~= "FEMALE" then return nil end',
        "        return generated",
        "    end",
        '    if CameraProfiles.mode == "LegacyHumanFemale" then',
        '        if family ~= "race.human" or sexKey ~= "FEMALE" then return nil end',
        "    end",
        "    return generated", "end", "",
    ]
    return "\n".join(lines)


def _float(value: float) -> str:
    text = f"{float(value):.8f}".rstrip("0").rstrip(".")
    if "." not in text:
        text += ".0"
    return text + "f"


def _render_cpp(canonical: dict[str, Any]) -> str:
    lines = [
        "// Generated by tools/catalog/character_camera_profiles.py; do not edit.",
        f'constexpr char kCharacterCameraProfileHash[] = "{canonical["profileHash"]}";',
        f"constexpr std::uint32_t kCharacterCameraProfileVersion = {canonical['profileVersion']}u;", "",
        "constexpr CharacterCameraProfile kCharacterCameraProfiles[] = {",
    ]
    for row in canonical["profiles"]:
        lines.append(
            f"    {{0x{int(row['sentinel']):04X}u, {_float(row['verticalOffset'])}, {_float(row['distanceScale'])}, "
            f"{_float(row['minimumDistance'])}, {_float(row['horizontalOffset'])}, {_float(row['yawOffset'])}}}, "
            f"// {row['cameraProfile']} {row['sex']} {row['slot']} {row['status']}"
        )
    lines += ["};", ""]
    return "\n".join(lines)


def _outputs(repo_root: Path, canonical: dict[str, Any]) -> dict[Path, str]:
    return {
        repo_root / "catalog/source/camera_profiles.json": _pretty(canonical),
        repo_root / "addon/SoloCollections/Data/Generated/CameraProfiles.lua": _render_lua(canonical),
        repo_root / "client-extension/SoloCam/src/generated/CharacterCameraProfiles.inc": _render_cpp(canonical),
    }


def generate(repo_root: Path, evidence_root: Path) -> dict[str, Any]:
    canonical = build_canonical(repo_root, evidence_root)
    for path, rendered in _outputs(repo_root, canonical).items():
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(rendered, encoding="utf-8", newline="\n")
    return canonical


def check(repo_root: Path) -> dict[str, Any]:
    canonical_path = repo_root / "catalog/source/camera_profiles.json"
    canonical = _read_json(canonical_path)
    _validate_canonical(canonical)
    outputs = _outputs(repo_root, canonical)
    outputs.pop(canonical_path)
    for path, rendered in outputs.items():
        _require(path.is_file() and path.read_text(encoding="utf-8") == rendered, f"stale camera projection: {path}")
    return canonical


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("command", choices=("extract", "generate", "check"))
    parser.add_argument("--repo-root", type=Path, default=Path(__file__).resolve().parents[2])
    parser.add_argument("--evidence-root", type=Path)
    parser.add_argument("--client-root", type=Path)
    parser.add_argument("--mpqcli", type=Path)
    args = parser.parse_args(argv)
    try:
        if args.command == "extract":
            _require(args.evidence_root is not None and args.client_root is not None and args.mpqcli is not None,
                     "extract requires --evidence-root, --client-root and --mpqcli")
            result = extract(args.client_root.resolve(), args.evidence_root.resolve(), args.mpqcli.resolve())
            print(f"camera models extracted: {len(result['models'])}")
        elif args.command == "generate":
            _require(args.evidence_root is not None, "generate requires --evidence-root")
            result = generate(args.repo_root.resolve(), args.evidence_root.resolve())
            print(f"camera profiles generated: {len(result['profiles'])}")
            print(f"profile hash: {result['profileHash']}")
        else:
            result = check(args.repo_root.resolve())
            print(f"camera profiles current: {len(result['profiles'])}")
            print(f"profile hash: {result['profileHash']}")
    except (CameraProfileError, OSError, subprocess.SubprocessError) as exc:
        parser.error(str(exc))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
