#!/usr/bin/env python3
"""Append the SoloCollections portrait camera without changing M2 textures."""

from __future__ import annotations

import argparse
from pathlib import Path

from patch_item_m2_textures import _write_atomic, append_static_item_camera


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--input", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()

    input_path = args.input.resolve()
    output_path = args.output.resolve()
    if input_path == output_path:
        raise ValueError("input and output paths must differ")
    _write_atomic(output_path, append_static_item_camera(input_path.read_bytes()))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
