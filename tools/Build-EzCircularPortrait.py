"""Build a local circular-alpha projection of ezCollections' mount portrait."""

from __future__ import annotations

import argparse
import struct
from pathlib import Path

from PIL import Image, ImageDraw


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--source", required=True, type=Path)
    parser.add_argument("--output", required=True, type=Path)
    args = parser.parse_args()

    image = Image.open(args.source).convert("RGBA")
    scale = 4
    mask = Image.new("L", (image.width * scale, image.height * scale), 0)
    draw = ImageDraw.Draw(mask)
    draw.ellipse((0, 0, mask.width - 1, mask.height - 1), fill=255)
    mask = mask.resize(image.size, Image.Resampling.LANCZOS)
    image.putalpha(mask)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    # Pillow writes a bottom-origin TGA (descriptor 0x08) plus a v2 footer.
    # This 3.3.5a client accepts the legacy top-origin, footerless encoding
    # already used by SoloCollections media (descriptor 0x28).
    header = struct.pack(
        "<BBBHHBHHHHBB",
        0, 0, 2,       # no ID, no colour map, uncompressed true-colour
        0, 0, 0,       # empty colour-map specification
        0, 0,           # x/y origin
        image.width, image.height,
        32, 0x28,       # BGRA8888, 8 alpha bits, top-left origin
    )
    args.output.write_bytes(header + image.tobytes("raw", "BGRA"))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
