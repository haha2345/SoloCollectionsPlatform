#!/usr/bin/env python3
"""Hardcode ItemDisplayInfo's object-skin texture in a WotLK item M2 copy.

WoW 3.3.5's generic Model widget can load an item M2 but cannot supply the
OBJECT_SKIN replacement texture that the equipment renderer normally obtains
from ItemDisplayInfo.dbc.  This tool patches only a separate wardrobe copy:
every type-2 texture descriptor is redirected to one explicit BLP path while
the source model and all existing payload offsets remain unchanged.
"""

from __future__ import annotations

import argparse
import json
import os
import struct
from pathlib import Path


M2_MAGIC = b"MD20"
WOTLK_VERSION = 264
TEXTURE_DESCRIPTOR_OFFSET = 0x50
TEXTURE_RECORD_SIZE = 16
OBJECT_SKIN_TEXTURE_TYPE = 2
REPLACEABLE_TEXTURE_LOOKUP_OFFSET = 0x68
CAMERA_DESCRIPTOR_OFFSET = 0x110
CAMERA_LOOKUP_DESCRIPTOR_OFFSET = 0x118
CAMERA_RECORD_SIZE = 100
BOUNDING_BOX_OFFSET = 0xA0
ALIGNMENT = 16


def _require_range(data: bytes | bytearray, offset: int, size: int, label: str) -> None:
    if offset < 0 or size < 0 or offset + size > len(data):
        raise ValueError(f"{label} range is outside the M2 file")


def _validate_m2(data: bytes | bytearray) -> tuple[int, int]:
    _require_range(data, 0, TEXTURE_DESCRIPTOR_OFFSET + 8, "M2 header")
    if bytes(data[:4]) != M2_MAGIC:
        raise ValueError("expected MD20 magic")
    version = struct.unpack_from("<I", data, 4)[0]
    if version != WOTLK_VERSION:
        raise ValueError(f"unsupported M2 version {version}; expected version 264")
    count, offset = struct.unpack_from("<2I", data, TEXTURE_DESCRIPTOR_OFFSET)
    _require_range(data, offset, count * TEXTURE_RECORD_SIZE, "texture array")
    return count, offset


def _read_m2_string(data: bytes | bytearray, length: int, offset: int) -> str:
    if length == 0:
        return ""
    _require_range(data, offset, length, "texture filename")
    return bytes(data[offset : offset + length]).decode("utf-8").rstrip("\0")


def inspect_textures(data: bytes | bytearray) -> list[dict]:
    count, offset = _validate_m2(data)
    textures = []
    for index in range(count):
        record_offset = offset + index * TEXTURE_RECORD_SIZE
        texture_type, flags, length, filename_offset = struct.unpack_from(
            "<4I", data, record_offset
        )
        textures.append(
            {
                "index": index,
                "type": texture_type,
                "flags": flags,
                "filename": _read_m2_string(data, length, filename_offset),
            }
        )
    return textures


def _normalize_texture_path(texture_path: str) -> str:
    normalized = texture_path.strip().replace("/", "\\").upper()
    if not normalized or not normalized.endswith(".BLP"):
        raise ValueError("texture path must be a non-empty .BLP path")
    if normalized.startswith("\\") or ":" in normalized:
        raise ValueError("texture path must be an MPQ-internal relative path")
    return normalized


def patch_object_skin_bytes(source: bytes, texture_path: str) -> bytes:
    count, offset = _validate_m2(source)
    normalized = _normalize_texture_path(texture_path)
    encoded = normalized.encode("utf-8") + b"\0"
    output = bytearray(source)
    patched_count = 0

    for index in range(count):
        record_offset = offset + index * TEXTURE_RECORD_SIZE
        texture_type = struct.unpack_from("<I", output, record_offset)[0]
        if texture_type != OBJECT_SKIN_TEXTURE_TYPE:
            continue
        filename_offset = len(output)
        output.extend(encoded)
        struct.pack_into("<I", output, record_offset, 0)
        struct.pack_into("<2I", output, record_offset + 8, len(encoded), filename_offset)
        patched_count += 1

    if patched_count == 0:
        raise ValueError("M2 contains no OBJECT_SKIN texture descriptors")

    # A stock item M2 with an ItemDisplayInfo-supplied OBJECT_SKIN has a
    # three-entry replaceable-texture lookup (types 0..2).  Stock item M2s
    # whose diffuse texture is already hardcoded only retain the type-0 entry.
    # Leaving the old type-2 lookup active after changing the descriptor makes
    # the generic Model widget bind an empty replacement texture, producing a
    # black diffuse surface while independent glow/effect batches still render.
    replacement_count, replacement_offset = struct.unpack_from(
        "<2I", output, REPLACEABLE_TEXTURE_LOOKUP_OFFSET
    )
    _require_range(
        output,
        replacement_offset,
        replacement_count * 2,
        "replaceable texture lookup",
    )
    if replacement_count <= OBJECT_SKIN_TEXTURE_TYPE:
        raise ValueError("OBJECT_SKIN M2 has no type-2 replaceable texture lookup")
    struct.pack_into("<I", output, REPLACEABLE_TEXTURE_LOOKUP_OFFSET, 1)
    return bytes(output)


def _aligned_size(size: int, alignment: int = ALIGNMENT) -> int:
    return (size + alignment - 1) & ~(alignment - 1)


def append_static_item_camera(source: bytes) -> bytes:
    """Append camera 0 to a camera-less item M2 for use by a Model widget."""
    _require_range(source, CAMERA_LOOKUP_DESCRIPTOR_OFFSET, 8, "camera descriptors")
    camera_count, camera_offset = struct.unpack_from("<2I", source, CAMERA_DESCRIPTOR_OFFSET)
    lookup_count, lookup_offset = struct.unpack_from("<2I", source, CAMERA_LOOKUP_DESCRIPTOR_OFFSET)
    if camera_count or camera_offset or lookup_count or lookup_offset:
        raise ValueError("item M2 must not already contain cameras")

    _require_range(source, BOUNDING_BOX_OFFSET, 28, "model bounding box")
    min_x, min_y, min_z, max_x, max_y, max_z, radius = struct.unpack_from(
        "<7f", source, BOUNDING_BOX_OFFSET
    )
    center_x = (min_x + max_x) * 0.5
    center_y = (min_y + max_y) * 0.5
    center_z = (min_z + max_z) * 0.5
    # Retail appearance cards keep most weapons within a narrow safety margin:
    # the long axis normally occupies roughly four fifths of the viewport.
    # The first PoC used 3.2 radii and left these models visibly undersized.
    # Keep a minimum distance for tiny daggers while moving normal weapons
    # about 20 percent closer to the camera.
    distance = max(radius * 2.65, 1.45)

    # M2 camera-orientation test 2: the above/back/right profile fixed the
    # diagonal slope but left the hilt at upper-right and the blade at
    # lower-left.  Orbit 180 degrees around the model while keeping the same
    # height and distance.  For flat weapon geometry this preserves the
    # lower-left-to-upper-right diagonal and swaps its endpoints, placing the
    # hilt at lower-left and the blade at upper-right.
    position = (
        center_x - distance * 0.6666667,
        center_y - distance * 0.3333333,
        center_z + distance * 0.6666667,
    )
    target = (center_x, center_y, center_z)
    camera = bytearray(CAMERA_RECORD_SIZE)
    struct.pack_into("<ifff", camera, 0, 0, 0.7853982, 100.0, 0.05)
    struct.pack_into("<3f", camera, 36, *position)
    struct.pack_into("<3f", camera, 68, *target)

    output = bytearray(source)
    output.extend(b"\0" * (_aligned_size(len(output)) - len(output)))
    new_camera_offset = len(output)
    output.extend(camera)
    output.extend(b"\0" * (_aligned_size(len(output)) - len(output)))
    new_lookup_offset = len(output)
    output.extend(struct.pack("<h", 0))
    struct.pack_into("<2I", output, CAMERA_DESCRIPTOR_OFFSET, 1, new_camera_offset)
    struct.pack_into("<2I", output, CAMERA_LOOKUP_DESCRIPTOR_OFFSET, 1, new_lookup_offset)
    return bytes(output)


def _write_atomic(path: Path, data: bytes) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.with_name(path.name + ".tmp")
    temporary.write_bytes(data)
    os.replace(temporary, path)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--input", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--texture", required=True)
    parser.add_argument("--manifest", type=Path)
    args = parser.parse_args()

    input_path = args.input.resolve()
    output_path = args.output.resolve()
    if input_path == output_path:
        raise ValueError("input and output paths must differ")

    patched = append_static_item_camera(
        patch_object_skin_bytes(input_path.read_bytes(), args.texture)
    )
    _write_atomic(output_path, patched)
    manifest = {
        "source": str(input_path),
        "output": str(output_path),
        "texture": _normalize_texture_path(args.texture),
        "textures": inspect_textures(patched),
    }
    if args.manifest:
        _write_atomic(
            args.manifest.resolve(),
            (json.dumps(manifest, ensure_ascii=False, indent=2) + "\n").encode("utf-8"),
        )
    print(json.dumps(manifest, ensure_ascii=False, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
