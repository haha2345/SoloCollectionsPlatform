"""Build a local circular-alpha projection of ezCollections' mount portrait."""

from __future__ import annotations

import argparse
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
    image.save(args.output, format="TGA", compression=None)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
