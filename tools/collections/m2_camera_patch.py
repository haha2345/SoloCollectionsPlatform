#!/usr/bin/env python3
"""Append a WotLK M2 camera without relocating any existing M2 payload.

The 3.3.5 MD20 header stores the camera array descriptor at 0x110 and the
camera-lookup array descriptor at 0x118.  Inserting a camera beside the old
array would invalidate offsets held by the rest of the model.  This tool keeps
the source byte-for-byte intact (apart from those four header integers), copies
the complete arrays to aligned EOF storage, and appends one cloned camera.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import math
import os
import struct
import sys
from pathlib import Path
from typing import NamedTuple, Sequence


M2_MAGIC = b"MD20"
WOTLK_VERSION = 264
CAMERA_DESCRIPTOR_OFFSET = 0x110
CAMERA_LOOKUP_DESCRIPTOR_OFFSET = 0x118
CAMERA_RECORD_SIZE = 100
CAMERA_TYPE_OFFSET = 0
CAMERA_FOV_OFFSET = 4
CAMERA_POSITION_BASE_OFFSET = 36
CAMERA_TARGET_BASE_OFFSET = 68
ALIGNMENT = 16
PLAYER_CHARACTER_MODEL_STEMS = frozenset(
    race + sex
    for race in (
        "BloodElf",
        "Draenei",
        "Dwarf",
        "Gnome",
        "Human",
        "NightElf",
        "Orc",
        "Scourge",
        "Tauren",
        "Troll",
    )
    for sex in ("Female", "Male")
)


class CameraConfig(NamedTuple):
    camera_type: int
    fov: float
    position: tuple[float, float, float]
    target: tuple[float, float, float]


def _aligned_size(size: int, alignment: int = ALIGNMENT) -> int:
    return (size + alignment - 1) & ~(alignment - 1)


def _require_range(data: bytes | bytearray, offset: int, size: int, label: str) -> None:
    if offset < 0 or size < 0 or offset + size > len(data):
        raise ValueError(f"{label} range is outside the M2 file")


def _read_array_descriptor(data: bytes | bytearray, offset: int, label: str) -> tuple[int, int]:
    _require_range(data, offset, 8, label)
    return struct.unpack_from("<2I", data, offset)


def _read_camera(data: bytes | bytearray, offset: int) -> dict:
    _require_range(data, offset, CAMERA_RECORD_SIZE, "camera")
    camera_type, fov, far_clip, near_clip = struct.unpack_from("<ifff", data, offset)
    position = struct.unpack_from("<3f", data, offset + CAMERA_POSITION_BASE_OFFSET)
    target = struct.unpack_from("<3f", data, offset + CAMERA_TARGET_BASE_OFFSET)
    return {
        "type": camera_type,
        "fov": fov,
        "far_clip": far_clip,
        "near_clip": near_clip,
        "position": position,
        "target": target,
    }


def inspect_m2(data: bytes | bytearray) -> dict:
    if len(data) < CAMERA_LOOKUP_DESCRIPTOR_OFFSET + 8:
        raise ValueError("file is too small to contain a WotLK MD20 header")
    if bytes(data[0:4]) != M2_MAGIC:
        raise ValueError("expected MD20 magic")
    version = struct.unpack_from("<I", data, 4)[0]
    if version != WOTLK_VERSION:
        raise ValueError(f"unsupported M2 version {version}; expected {WOTLK_VERSION}")

    camera_count, camera_offset = _read_array_descriptor(data, CAMERA_DESCRIPTOR_OFFSET, "camera descriptor")
    lookup_count, lookup_offset = _read_array_descriptor(
        data, CAMERA_LOOKUP_DESCRIPTOR_OFFSET, "camera lookup descriptor"
    )
    _require_range(data, camera_offset, camera_count * CAMERA_RECORD_SIZE, "camera array")
    _require_range(data, lookup_offset, lookup_count * 2, "camera lookup array")

    cameras = [
        _read_camera(data, camera_offset + index * CAMERA_RECORD_SIZE)
        for index in range(camera_count)
    ]
    lookup = list(struct.unpack_from(f"<{lookup_count}h", data, lookup_offset)) if lookup_count else []
    return {
        "magic": "MD20",
        "version": version,
        "camera_count": camera_count,
        "camera_offset": camera_offset,
        "camera_lookup_count": lookup_count,
        "camera_lookup_offset": lookup_offset,
        "camera_lookup": lookup,
        "cameras": cameras,
    }


def _validate_config(config: CameraConfig) -> None:
    if config.camera_type < 0 or config.camera_type > 0x7FFFFFFF:
        raise ValueError("camera type must be a non-negative signed 32-bit integer")
    if not math.isfinite(config.fov) or config.fov <= 0:
        raise ValueError("camera fov must be a positive finite number")
    if len(config.position) != 3 or len(config.target) != 3:
        raise ValueError("camera position and target must each contain three values")
    if not all(math.isfinite(value) for value in (*config.position, *config.target)):
        raise ValueError("camera position and target must be finite")


def patch_m2_bytes(source: bytes, config: CameraConfig) -> bytes:
    """Return an append-only M2 camera patch for a stock two-camera source."""
    _validate_config(config)
    info = inspect_m2(source)
    if info["camera_count"] != 2 or info["camera_lookup_count"] != 2:
        raise ValueError("source must contain exactly 2 cameras and 2 camera lookup entries")
    if info["camera_lookup"] != [0, 1]:
        raise ValueError("source camera lookup must be [0, 1]")

    old_camera_offset = info["camera_offset"]
    old_camera_size = info["camera_count"] * CAMERA_RECORD_SIZE
    old_lookup_offset = info["camera_lookup_offset"]
    old_lookup_size = info["camera_lookup_count"] * 2
    camera_array = source[old_camera_offset : old_camera_offset + old_camera_size]
    camera1 = bytearray(camera_array[CAMERA_RECORD_SIZE : CAMERA_RECORD_SIZE * 2])

    # Clone the full-body camera so all three M2Track descriptors and their
    # referenced animation payload remain valid.  Only static framing fields
    # are changed for the new camera.
    struct.pack_into("<i", camera1, CAMERA_TYPE_OFFSET, config.camera_type)
    struct.pack_into("<f", camera1, CAMERA_FOV_OFFSET, config.fov)
    struct.pack_into("<3f", camera1, CAMERA_POSITION_BASE_OFFSET, *config.position)
    struct.pack_into("<3f", camera1, CAMERA_TARGET_BASE_OFFSET, *config.target)

    output = bytearray(source)
    output.extend(b"\0" * (_aligned_size(len(output)) - len(output)))
    new_camera_offset = len(output)
    output.extend(camera_array)
    output.extend(camera1)

    output.extend(b"\0" * (_aligned_size(len(output)) - len(output)))
    new_lookup_offset = len(output)
    output.extend(source[old_lookup_offset : old_lookup_offset + old_lookup_size])
    output.extend(struct.pack("<h", config.camera_type))

    if new_camera_offset > 0xFFFFFFFF or new_lookup_offset > 0xFFFFFFFF:
        raise ValueError("patched arrays exceed the 32-bit M2 offset range")
    struct.pack_into("<2I", output, CAMERA_DESCRIPTOR_OFFSET, 3, new_camera_offset)
    struct.pack_into("<2I", output, CAMERA_LOOKUP_DESCRIPTOR_OFFSET, 3, new_lookup_offset)
    return bytes(output)


def _parse_vector(value: str) -> tuple[float, float, float]:
    try:
        parts = tuple(float(part.strip()) for part in value.split(","))
    except ValueError as exc:
        raise argparse.ArgumentTypeError("expected three comma-separated numbers") from exc
    if len(parts) != 3:
        raise argparse.ArgumentTypeError("expected three comma-separated numbers")
    return parts


def _sha256(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest().upper()


def _camera_for_json(camera: dict) -> dict:
    return {
        **camera,
        "position": list(camera["position"]),
        "target": list(camera["target"]),
    }


def _write_atomic(path: Path, data: bytes) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.with_name(path.name + ".tmp")
    temporary.write_bytes(data)
    os.replace(temporary, path)


def _is_player_character_model(path: Path) -> bool:
    return path.stem.casefold() in {name.casefold() for name in PLAYER_CHARACTER_MODEL_STEMS}


def _run_patch(args: argparse.Namespace) -> int:
    input_path = args.input.resolve()
    output_path = args.output.resolve()
    if input_path == output_path:
        raise ValueError("input and output paths must differ")
    if _is_player_character_model(input_path) and not args.allow_unsafe_player_model:
        raise ValueError(
            "adding a third camera to a playable character M2 is blocked: "
            "the WoW 3.3.5 client crashes with ERROR #132 while loading the character; "
            "use --allow-unsafe-player-model only for quarantined offline research"
        )
    source = input_path.read_bytes()
    config = CameraConfig(args.camera_type, args.fov, args.position, args.target)
    patched = patch_m2_bytes(source, config)
    _write_atomic(output_path, patched)
    info = inspect_m2(patched)
    manifest = {
        "format": "SoloCollections M2 camera patch v1",
        "source": str(input_path),
        "output": str(output_path),
        "source_size": len(source),
        "output_size": len(patched),
        "source_sha256": _sha256(source),
        "output_sha256": _sha256(patched),
        "camera_count": info["camera_count"],
        "camera_offset": info["camera_offset"],
        "camera_lookup": info["camera_lookup"],
        "camera_lookup_offset": info["camera_lookup_offset"],
        "added_camera": _camera_for_json(info["cameras"][2]),
    }
    if args.manifest:
        _write_atomic(args.manifest.resolve(), (json.dumps(manifest, ensure_ascii=False, indent=2) + "\n").encode("utf-8"))
    print(json.dumps(manifest, ensure_ascii=False, indent=2))
    return 0


def _run_inspect(args: argparse.Namespace) -> int:
    info = inspect_m2(args.input.read_bytes())
    serializable = {
        **info,
        "cameras": [_camera_for_json(camera) for camera in info["cameras"]],
    }
    print(json.dumps(serializable, ensure_ascii=False, indent=2))
    return 0


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description=__doc__)
    subparsers = parser.add_subparsers(dest="command", required=True)

    patch_parser = subparsers.add_parser("patch", help="append one camera and write a new M2")
    patch_parser.add_argument("--input", type=Path, required=True)
    patch_parser.add_argument("--output", type=Path, required=True)
    patch_parser.add_argument("--manifest", type=Path)
    patch_parser.add_argument("--camera-type", type=int, default=2)
    patch_parser.add_argument("--fov", type=float, required=True)
    patch_parser.add_argument("--position", type=_parse_vector, required=True)
    patch_parser.add_argument("--target", type=_parse_vector, required=True)
    patch_parser.add_argument(
        "--allow-unsafe-player-model",
        action="store_true",
        help="permit a known crash-causing player-model experiment; never use for a live client",
    )
    patch_parser.set_defaults(handler=_run_patch)

    inspect_parser = subparsers.add_parser("inspect", help="print camera metadata as JSON")
    inspect_parser.add_argument("--input", type=Path, required=True)
    inspect_parser.set_defaults(handler=_run_inspect)
    return parser


def main(argv: Sequence[str] | None = None) -> int:
    parser = build_parser()
    args = parser.parse_args(argv)
    try:
        return args.handler(args)
    except (OSError, ValueError) as exc:
        print(f"error: {exc}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
