#!/usr/bin/env python3
"""Build creature-renderable copies of camera-equipped item M2 models and DBC rows."""

from __future__ import annotations

import argparse
import json
import struct
import sys
from pathlib import Path

from patch_item_m2_textures import (
    OBJECT_SKIN_TEXTURE_TYPE,
    REPLACEABLE_TEXTURE_LOOKUP_OFFSET,
    TEXTURE_DESCRIPTOR_OFFSET,
    TEXTURE_RECORD_SIZE,
    _require_range,
    _validate_m2,
    append_static_item_camera,
)

MONSTER_SKIN_1 = 11
LOOKUP_COUNT = 13


def convert_object_skin(source: bytes) -> bytes:
    count, texture_offset = _validate_m2(source)
    output = bytearray(source)
    object_skin_indices: list[int] = []
    for index in range(count):
        record_offset = texture_offset + index * TEXTURE_RECORD_SIZE
        texture_type = struct.unpack_from("<I", output, record_offset)[0]
        if texture_type == OBJECT_SKIN_TEXTURE_TYPE:
            struct.pack_into("<I", output, record_offset, MONSTER_SKIN_1)
            # Replacement texture names are supplied by CreatureDisplayInfo.
            struct.pack_into("<2I", output, record_offset + 8, 0, 0)
            object_skin_indices.append(index)
    if not object_skin_indices:
        raise ValueError("M2 contains no OBJECT_SKIN texture descriptors")

    old_count, old_offset = struct.unpack_from("<2I", output, REPLACEABLE_TEXTURE_LOOKUP_OFFSET)
    _require_range(output, old_offset, old_count * 2, "replaceable texture lookup")
    old_lookup = list(struct.unpack_from(f"<{old_count}h", output, old_offset))
    lookup = [-1] * LOOKUP_COUNT
    if old_lookup:
        lookup[0] = old_lookup[0]
    lookup[MONSTER_SKIN_1] = object_skin_indices[0]

    while len(output) % 16:
        output.append(0)
    lookup_offset = len(output)
    output.extend(struct.pack(f"<{LOOKUP_COUNT}h", *lookup))
    struct.pack_into("<2I", output, REPLACEABLE_TEXTURE_LOOKUP_OFFSET, LOOKUP_COUNT, lookup_offset)
    return bytes(output)


def parse_wdbc(
    data: bytes, expected_layouts: set[tuple[int, int]]
) -> tuple[list[bytes], bytearray, int, int]:
    if len(data) < 20 or data[:4] != b"WDBC":
        raise ValueError("expected a WDBC file")
    rows, fields, record_size, string_size = struct.unpack_from("<4I", data, 4)
    if (fields, record_size) not in expected_layouts:
        raise ValueError(f"unexpected DBC layout: fields={fields}, record_size={record_size}")
    records_end = 20 + rows * record_size
    strings_end = records_end + string_size
    if strings_end > len(data):
        raise ValueError("truncated DBC")
    records = [data[20 + i * record_size : 20 + (i + 1) * record_size] for i in range(rows)]
    return records, bytearray(data[records_end:strings_end]), fields, record_size


def add_string(strings: bytearray, value: str) -> int:
    encoded = value.encode("utf-8") + b"\0"
    offset = len(strings)
    strings.extend(encoded)
    return offset


def write_wdbc(path: Path, records: list[bytes], strings: bytearray, fields: int, record_size: int) -> None:
    payload = bytearray(b"WDBC")
    payload.extend(struct.pack("<4I", len(records), fields, record_size, len(strings)))
    payload.extend(b"".join(records))
    payload.extend(strings)
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(payload)


def find_record(records: list[bytes], record_id: int) -> bytes:
    for record in records:
        if struct.unpack_from("<I", record, 0)[0] == record_id:
            return record
    raise ValueError(f"template DBC row {record_id} not found")


def validate_new_ids(config: list[dict], model_records: list[bytes], display_records: list[bytes]) -> None:
    existing_model_ids = {struct.unpack_from("<I", record, 0)[0] for record in model_records}
    existing_display_ids = {struct.unpack_from("<I", record, 0)[0] for record in display_records}
    requested_model_ids: set[int] = set()
    requested_display_ids: set[int] = set()

    for entry in config:
        model_id = int(entry["model_id"])
        display_id = int(entry["display_id"])
        if model_id <= 0 or display_id <= 0:
            raise ValueError("custom DBC IDs must be positive")
        if model_id in existing_model_ids:
            raise ValueError(f"CreatureModelData ID {model_id} already exists in the baseline DBC")
        if display_id in existing_display_ids:
            raise ValueError(f"CreatureDisplayInfo ID {display_id} already exists in the baseline DBC")
        if model_id in requested_model_ids:
            raise ValueError(f"duplicate custom CreatureModelData ID {model_id}")
        if display_id in requested_display_ids:
            raise ValueError(f"duplicate custom CreatureDisplayInfo ID {display_id}")
        requested_model_ids.add(model_id)
        requested_display_ids.add(display_id)


def build(args: argparse.Namespace) -> dict:
    config = json.loads(args.config.read_text(encoding="utf-8-sig"))
    stage = args.stage
    stage.mkdir(parents=True, exist_ok=True)

    # Locale patches in this client use the later 28-field CreatureModelData
    # layout, while an unpatched 3.3.5 locale can still expose 26 fields.  The
    # fields edited below have identical offsets in both layouts; preserve the
    # baseline layout and every untouched trailing field verbatim.
    model_records, model_strings, model_fields, model_record_size = parse_wdbc(
        args.creature_model_data.read_bytes(), {(26, 104), (28, 112)}
    )
    display_records, display_strings, display_fields, display_record_size = parse_wdbc(
        args.creature_display_info.read_bytes(), {(16, 64)}
    )
    validate_new_ids(config, model_records, display_records)
    model_template = find_record(model_records, 1)
    display_template = find_record(display_records, 141)

    manifest = []
    for entry in config:
        source_m2 = Path(entry["source_m2"])
        target_internal = entry["target"]
        target_m2 = stage / (target_internal + ".m2")
        target_skin = stage / (target_internal + "00.skin")
        texture_name = entry["texture_name"]
        target_texture = stage / "Item/ObjectComponents/SoloCollections" / (texture_name + ".blp")

        target_m2.parent.mkdir(parents=True, exist_ok=True)
        target_m2.write_bytes(append_static_item_camera(convert_object_skin(source_m2.read_bytes())))
        target_skin.parent.mkdir(parents=True, exist_ok=True)
        target_skin.write_bytes(Path(entry["source_skin"]).read_bytes())
        target_texture.parent.mkdir(parents=True, exist_ok=True)
        target_texture.write_bytes(Path(entry["source_texture"]).read_bytes())

        model = bytearray(model_template)
        struct.pack_into("<I", model, 0, entry["model_id"])
        struct.pack_into("<I", model, 8, add_string(model_strings, target_internal + ".mdx"))
        struct.pack_into("<f", model, 16, 1.0)
        model_records.append(bytes(model))

        display = bytearray(display_template)
        struct.pack_into("<I", display, 0, entry["display_id"])
        struct.pack_into("<I", display, 4, entry["model_id"])
        struct.pack_into("<I", display, 8, 0)
        struct.pack_into("<I", display, 12, 0)
        struct.pack_into("<f", display, 16, 1.0)
        struct.pack_into("<B", display, 20, 255)
        struct.pack_into("<I", display, 24, add_string(display_strings, texture_name))
        struct.pack_into("<I", display, 28, 0)
        struct.pack_into("<I", display, 32, 0)
        struct.pack_into("<I", display, 36, 0)
        display_records.append(bytes(display))
        manifest.append({"display_id": entry["display_id"], "model_id": entry["model_id"], "target": target_internal, "texture": texture_name})

    write_wdbc(
        stage / "DBFilesClient/CreatureModelData.dbc",
        model_records,
        model_strings,
        model_fields,
        model_record_size,
    )
    write_wdbc(
        stage / "DBFilesClient/CreatureDisplayInfo.dbc",
        display_records,
        display_strings,
        display_fields,
        display_record_size,
    )
    return {"records": manifest}


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--config", type=Path)
    parser.add_argument("--stage", type=Path, required=True)
    parser.add_argument("--creature-model-data", type=Path)
    parser.add_argument("--creature-display-info", type=Path)
    # Registry mode is the append-only stage-seven successor to the manual
    # 21-item config.  Keep the original mode intact for its regression
    # fixture, but route the full shadow through the same DBC/M2 primitives.
    parser.add_argument("--registry", type=Path)
    parser.add_argument("--candidates", type=Path)
    parser.add_argument("--shadow-evidence-root", type=Path)
    parser.add_argument("--fixed-input-root", type=Path)
    parser.add_argument("--model-camera-overrides", type=Path)
    parser.add_argument("--batch", choices=("1", "2", "3"))
    parser.add_argument("--bundle-id")
    parser.add_argument("--asset-pack-version")
    args = parser.parse_args()
    if args.registry is not None:
        required = (
            "candidates",
            "shadow_evidence_root",
            "fixed_input_root",
            "batch",
            "bundle_id",
            "asset_pack_version",
        )
        missing = [name for name in required if getattr(args, name) is None]
        if missing:
            parser.error("registry mode requires: " + ", ".join("--" + name.replace("_", "-") for name in missing))
        if args.config or args.creature_model_data or args.creature_display_info:
            parser.error("registry mode cannot be combined with legacy --config/DBC inputs")
        catalog_root = Path(__file__).resolve().parents[3] / "tools" / "catalog"
        if str(catalog_root) not in sys.path:
            sys.path.insert(0, str(catalog_root))
        from weapon_bundle import build_registry_assets

        result = build_registry_assets(args)
    else:
        missing = [
            name
            for name in ("config", "creature_model_data", "creature_display_info")
            if getattr(args, name) is None
        ]
        if missing:
            parser.error("legacy mode requires: " + ", ".join("--" + name.replace("_", "-") for name in missing))
        result = build(args)
    print(json.dumps(result, ensure_ascii=False, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
