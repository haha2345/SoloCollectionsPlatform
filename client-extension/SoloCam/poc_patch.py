"""Safe copy-only loader patch for the supported WoW 3.3.5a build 12340 client.

This is deliberately narrower than the reference WotLK-Extensions patcher:
it does not enable Large Address Aware, alter GlueXML checks, or touch the
original executable.  It only installs the already-researched DLL loader
trampoline and the DLL name used by this PoC.
"""

from __future__ import annotations

import argparse
import hashlib
import os
import shutil
import struct
from dataclasses import dataclass
from pathlib import Path
from typing import Iterable


SUPPORTED_SHA256 = "AA63A5750D60EF16746C686B3D5E26876D98953EAB08B1C026CD0FAF78E88CB8"
DLL_NAME = b"SoloCam.dll"


@dataclass(frozen=True)
class Patch:
    name: str
    offset: int
    expected: bytes
    replacement: bytes


def _loader_stub(dll_name_va: int) -> bytes:
    # Preserve the original function prologue/call and return to 0x40B7D8
    # after loading the PoC DLL.  Addresses are valid only for the locked
    # build-12340 image identified by SUPPORTED_SHA256.
    return bytes.fromhex(
        "B8 01 00 00 00 "
        "A3 74 B4 B6 00 "
        "68"
    ) + struct.pack("<I", dll_name_va) + bytes.fromhex(
        "E8 1C 68 38 00 "
        "83 C4 04 "
        "55 8B EC "
        "E8 A1 10 F2 FF "
        "E9 04 5B F2 FF"
    )


def build_patch_plan(image: bytes) -> tuple[Patch, ...]:
    del image  # The fixed plan is guarded by validate_supported_image().
    name_slot = DLL_NAME + b"\x00" * (32 - len(DLL_NAME))
    return (
        Patch(
            "startup trampoline",
            0xABD0,
            bytes.fromhex("55 8B EC E8 98 B5 FF FF"),
            bytes.fromhex("E9 DB A4 0D 00 90 90 90"),
        ),
        Patch(
            "DLL loader stub",
            0xE50B0,
            bytes.fromhex(
                "55 8B EC 56 33 F6 39 35 6C B4 B6 00 0F 85 DB 01 00 00 "
                "39 35 68 B4 B6 00 0F 85 CF 01 00 00 33 C0 B9 68 B4 B6"
            ),
            _loader_stub(0x009E4270),
        ),
        Patch(
            "DLL scan allow",
            0xDC0F0,
            bytes.fromhex("55 8B EC 56 8B 75"),
            bytes.fromhex("B8 01 00 00 00 C3"),
        ),
        Patch(
            "PoC DLL name",
            0x5E2A70,
            b"\x00" * 32,
            name_slot,
        ),
    )


def validate_supported_image(image: bytes) -> None:
    digest = hashlib.sha256(image).hexdigest().upper()
    if digest != SUPPORTED_SHA256:
        raise ValueError(
            "unsupported Wow.exe: expected SHA256 "
            f"{SUPPORTED_SHA256}, got {digest}"
        )

    for patch in build_patch_plan(image):
        current = image[patch.offset : patch.offset + len(patch.expected)]
        if current != patch.expected:
            raise ValueError(
                f"unsupported Wow.exe: {patch.name} bytes at 0x{patch.offset:X} "
                f"are {current.hex(' ')}, expected {patch.expected.hex(' ')}"
            )


def apply_patch_plan(image: bytes, patches: Iterable[Patch]) -> bytes:
    output = bytearray(image)
    for patch in patches:
        current = bytes(output[patch.offset : patch.offset + len(patch.expected)])
        if current != patch.expected:
            raise ValueError(
                f"refusing to patch {patch.name}: original bytes do not match"
            )
        output[patch.offset : patch.offset + len(patch.replacement)] = patch.replacement
    return bytes(output)


def patch_copy(source: Path, target: Path) -> None:
    source = source.resolve()
    target = target.resolve()
    if source == target:
        raise ValueError("source and target must be different; the original client is never overwritten")

    image = source.read_bytes()
    validate_supported_image(image)
    patched = apply_patch_plan(image, build_patch_plan(image))

    target.parent.mkdir(parents=True, exist_ok=True)
    temporary = target.with_suffix(target.suffix + ".tmp")
    temporary.write_bytes(patched)
    shutil.copystat(source, temporary)
    os.replace(temporary, target)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("source", type=Path, help="untouched supported Wow.exe")
    parser.add_argument("target", type=Path, help="new Wow-SoloCam-PoC.exe path")
    args = parser.parse_args()
    patch_copy(args.source, args.target)
    print(f"Created isolated PoC client: {args.target.resolve()}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
