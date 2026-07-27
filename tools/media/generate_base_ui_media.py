#!/usr/bin/env python3
"""Generate the project-authored, redistributable base wardrobe UI media.

The renderer deliberately uses uncompressed top-left 32-bit TGA files because
the 3.3.5 client reads them without a conversion step.  It does not read any
Retail game installation or extracted Blizzard asset.
"""

from __future__ import annotations

import argparse
import hashlib
from pathlib import Path
from typing import Iterable


RGBA = tuple[int, int, int, int]

ATLAS_SIZE = 512
ROUND_HIGHLIGHT_SIZE = (512, 256)
SLOT_REGIONS = {
    "back": (145, 180, 369, 406),
    "chest": (105, 140, 409, 446),
    "feet": (142, 177, 409, 446),
    "hands": (105, 140, 448, 485),
    "head": (142, 177, 448, 485),
    "legs": (203, 238, 115, 152),
    "mainhand": (240, 275, 115, 152),
    "secondaryhand": (277, 312, 115, 152),
    "shoulder": (351, 386, 115, 152),
    "waist": (425, 460, 115, 152),
    "wrist": (462, 497, 115, 152),
}
SELECTED_REGION = (381, 426, 65, 112)
ROUND_HIGHLIGHT_REGION = (261, 297, 166, 202)

TRANSPARENT: RGBA = (0, 0, 0, 0)
PANEL: RGBA = (13, 18, 25, 238)
PANEL_EDGE: RGBA = (101, 80, 44, 255)
BRONZE: RGBA = (184, 137, 60, 255)
GOLD: RGBA = (255, 211, 111, 255)
SILVER: RGBA = (172, 197, 207, 255)
BLUE: RGBA = (82, 160, 220, 210)
SHADOW: RGBA = (0, 0, 0, 185)


def _canvas(width: int, height: int, color: RGBA = TRANSPARENT) -> bytearray:
    red, green, blue, alpha = color
    return bytearray((blue, green, red, alpha)) * (width * height)


def _pixel(canvas: bytearray, width: int, height: int, x: int, y: int, color: RGBA) -> None:
    if not (0 <= x < width and 0 <= y < height):
        return
    red, green, blue, alpha = color
    offset = ((y * width) + x) * 4
    canvas[offset:offset + 4] = bytes((blue, green, red, alpha))


def _rect(
    canvas: bytearray,
    width: int,
    height: int,
    left: int,
    top: int,
    right: int,
    bottom: int,
    color: RGBA,
) -> None:
    for y in range(max(0, top), min(height, bottom)):
        for x in range(max(0, left), min(width, right)):
            _pixel(canvas, width, height, x, y, color)


def _circle(
    canvas: bytearray,
    width: int,
    height: int,
    center_x: int,
    center_y: int,
    radius: int,
    color: RGBA,
    *,
    filled: bool = True,
    thickness: int = 1,
) -> None:
    outer = radius * radius
    inner_radius = max(0, radius - thickness)
    inner = inner_radius * inner_radius
    for y in range(center_y - radius, center_y + radius + 1):
        for x in range(center_x - radius, center_x + radius + 1):
            distance = (x - center_x) ** 2 + (y - center_y) ** 2
            if distance > outer:
                continue
            if not filled and distance < inner:
                continue
            _pixel(canvas, width, height, x, y, color)


def _line(
    canvas: bytearray,
    width: int,
    height: int,
    x0: int,
    y0: int,
    x1: int,
    y1: int,
    color: RGBA,
    *,
    thickness: int = 1,
) -> None:
    dx = abs(x1 - x0)
    dy = -abs(y1 - y0)
    step_x = 1 if x0 < x1 else -1
    step_y = 1 if y0 < y1 else -1
    error = dx + dy
    while True:
        half = max(0, thickness // 2)
        _rect(canvas, width, height, x0 - half, y0 - half, x0 + half + 1, y0 + half + 1, color)
        if x0 == x1 and y0 == y1:
            break
        double_error = error * 2
        if double_error >= dy:
            error += dy
            x0 += step_x
        if double_error <= dx:
            error += dx
            y0 += step_y


def _slot_background(canvas: bytearray, region: tuple[int, int, int, int]) -> tuple[int, int, int, int, int, int]:
    left, right, top, bottom = region
    _rect(canvas, ATLAS_SIZE, ATLAS_SIZE, left, top, right, bottom, PANEL)
    _rect(canvas, ATLAS_SIZE, ATLAS_SIZE, left, top, right, top + 1, PANEL_EDGE)
    _rect(canvas, ATLAS_SIZE, ATLAS_SIZE, left, bottom - 1, right, bottom, PANEL_EDGE)
    _rect(canvas, ATLAS_SIZE, ATLAS_SIZE, left, top, left + 1, bottom, PANEL_EDGE)
    _rect(canvas, ATLAS_SIZE, ATLAS_SIZE, right - 1, top, right, bottom, PANEL_EDGE)
    return left, right, top, bottom, (left + right) // 2, (top + bottom) // 2


def _draw_slot_glyph(canvas: bytearray, slot: str, region: tuple[int, int, int, int]) -> None:
    left, right, top, bottom, center_x, center_y = _slot_background(canvas, region)
    width = right - left
    height = bottom - top
    icon_left = left + 5
    icon_right = right - 5
    icon_top = top + 4
    icon_bottom = bottom - 4

    if slot == "head":
        _circle(canvas, ATLAS_SIZE, ATLAS_SIZE, center_x, icon_top + 8, 6, SILVER)
        _rect(canvas, ATLAS_SIZE, ATLAS_SIZE, center_x - 9, icon_top + 15, center_x + 10, icon_bottom - 2, BRONZE)
        _line(canvas, ATLAS_SIZE, ATLAS_SIZE, center_x - 6, icon_top + 18, center_x - 12, icon_bottom - 2, GOLD, thickness=2)
        _line(canvas, ATLAS_SIZE, ATLAS_SIZE, center_x + 6, icon_top + 18, center_x + 12, icon_bottom - 2, GOLD, thickness=2)
    elif slot == "shoulder":
        _circle(canvas, ATLAS_SIZE, ATLAS_SIZE, icon_left + 6, center_y, 7, BRONZE)
        _circle(canvas, ATLAS_SIZE, ATLAS_SIZE, icon_right - 6, center_y, 7, BRONZE)
        _rect(canvas, ATLAS_SIZE, ATLAS_SIZE, icon_left + 6, center_y - 4, icon_right - 6, center_y + 5, SILVER)
    elif slot == "back":
        _line(canvas, ATLAS_SIZE, ATLAS_SIZE, center_x, icon_top + 1, icon_left + 3, icon_bottom - 1, SILVER, thickness=2)
        _line(canvas, ATLAS_SIZE, ATLAS_SIZE, center_x, icon_top + 1, icon_right - 3, icon_bottom - 1, SILVER, thickness=2)
        _line(canvas, ATLAS_SIZE, ATLAS_SIZE, icon_left + 3, icon_bottom - 1, icon_right - 3, icon_bottom - 1, BRONZE, thickness=2)
    elif slot == "chest":
        _rect(canvas, ATLAS_SIZE, ATLAS_SIZE, center_x - 8, icon_top + 2, center_x + 9, icon_bottom - 1, SILVER)
        _rect(canvas, ATLAS_SIZE, ATLAS_SIZE, center_x - 12, icon_top + 6, center_x - 7, icon_top + 17, BRONZE)
        _rect(canvas, ATLAS_SIZE, ATLAS_SIZE, center_x + 8, icon_top + 6, center_x + 13, icon_top + 17, BRONZE)
        _line(canvas, ATLAS_SIZE, ATLAS_SIZE, center_x, icon_top + 5, center_x, icon_bottom - 3, GOLD)
    elif slot == "wrist":
        _rect(canvas, ATLAS_SIZE, ATLAS_SIZE, center_x - 8, icon_top + 5, center_x + 9, icon_bottom - 4, SILVER)
        _rect(canvas, ATLAS_SIZE, ATLAS_SIZE, center_x - 10, center_y - 2, center_x + 11, center_y + 3, BRONZE)
    elif slot == "hands":
        _circle(canvas, ATLAS_SIZE, ATLAS_SIZE, center_x - 6, center_y + 3, 7, SILVER)
        _circle(canvas, ATLAS_SIZE, ATLAS_SIZE, center_x + 6, center_y + 3, 7, SILVER)
        _rect(canvas, ATLAS_SIZE, ATLAS_SIZE, center_x - 11, icon_top + 3, center_x - 2, center_y + 3, BRONZE)
        _rect(canvas, ATLAS_SIZE, ATLAS_SIZE, center_x + 2, icon_top + 3, center_x + 11, center_y + 3, BRONZE)
    elif slot == "waist":
        _rect(canvas, ATLAS_SIZE, ATLAS_SIZE, icon_left + 1, center_y - 3, icon_right - 1, center_y + 4, BRONZE)
        _rect(canvas, ATLAS_SIZE, ATLAS_SIZE, center_x - 3, center_y - 5, center_x + 4, center_y + 6, GOLD)
    elif slot == "legs":
        _rect(canvas, ATLAS_SIZE, ATLAS_SIZE, center_x - 9, icon_top + 1, center_x - 2, icon_bottom - 2, SILVER)
        _rect(canvas, ATLAS_SIZE, ATLAS_SIZE, center_x + 2, icon_top + 1, center_x + 9, icon_bottom - 2, SILVER)
        _line(canvas, ATLAS_SIZE, ATLAS_SIZE, center_x - 8, icon_bottom - 2, center_x - 12, icon_bottom, BRONZE, thickness=2)
        _line(canvas, ATLAS_SIZE, ATLAS_SIZE, center_x + 8, icon_bottom - 2, center_x + 12, icon_bottom, BRONZE, thickness=2)
    elif slot == "feet":
        _rect(canvas, ATLAS_SIZE, ATLAS_SIZE, center_x - 11, center_y - 2, center_x - 1, icon_bottom - 2, SILVER)
        _rect(canvas, ATLAS_SIZE, ATLAS_SIZE, center_x + 1, center_y - 2, center_x + 11, icon_bottom - 2, SILVER)
        _rect(canvas, ATLAS_SIZE, ATLAS_SIZE, center_x - 14, icon_bottom - 4, center_x - 1, icon_bottom, BRONZE)
        _rect(canvas, ATLAS_SIZE, ATLAS_SIZE, center_x + 1, icon_bottom - 4, center_x + 14, icon_bottom, BRONZE)
    elif slot == "mainhand":
        _line(canvas, ATLAS_SIZE, ATLAS_SIZE, center_x - 10, icon_bottom - 1, center_x + 10, icon_top + 2, SILVER, thickness=2)
        _line(canvas, ATLAS_SIZE, ATLAS_SIZE, center_x - 6, center_y + 5, center_x + 4, center_y + 10, BRONZE, thickness=2)
        _circle(canvas, ATLAS_SIZE, ATLAS_SIZE, center_x - 11, icon_bottom, 3, GOLD)
    elif slot == "secondaryhand":
        _circle(canvas, ATLAS_SIZE, ATLAS_SIZE, center_x, center_y, min(width, height) // 3, SILVER)
        _circle(canvas, ATLAS_SIZE, ATLAS_SIZE, center_x, center_y, min(width, height) // 5, BRONZE)
        _line(canvas, ATLAS_SIZE, ATLAS_SIZE, center_x, icon_top + 3, center_x, icon_bottom - 3, GOLD)
    else:
        raise ValueError(f"unknown slot {slot}")


def _draw_selected_ring(canvas: bytearray) -> None:
    left, right, top, bottom = SELECTED_REGION
    center_x = (left + right) // 2
    center_y = (top + bottom) // 2
    radius = min(right - left, bottom - top) // 2 - 2
    _circle(canvas, ATLAS_SIZE, ATLAS_SIZE, center_x, center_y, radius, (255, 193, 59, 230), filled=False, thickness=2)
    _circle(canvas, ATLAS_SIZE, ATLAS_SIZE, center_x, center_y, radius - 4, (255, 231, 150, 170), filled=False, thickness=1)
    _circle(canvas, ATLAS_SIZE, ATLAS_SIZE, center_x, center_y, radius + 1, (94, 53, 15, 240), filled=False, thickness=1)


def _draw_round_highlight(canvas: bytearray) -> None:
    left, right, top, bottom = ROUND_HIGHLIGHT_REGION
    center_x = (left + right) // 2
    center_y = (top + bottom) // 2
    radius = min(right - left, bottom - top) // 2 - 2
    _circle(canvas, ROUND_HIGHLIGHT_SIZE[0], ROUND_HIGHLIGHT_SIZE[1], center_x, center_y, radius, BLUE, filled=False, thickness=2)
    _circle(
        canvas,
        ROUND_HIGHLIGHT_SIZE[0],
        ROUND_HIGHLIGHT_SIZE[1],
        center_x,
        center_y,
        radius - 4,
        (212, 242, 255, 155),
        filled=False,
        thickness=1,
    )


def _draw_mount_portrait(canvas: bytearray) -> None:
    size = 64
    _circle(canvas, size, size, 32, 32, 30, (26, 42, 43, 255))
    _circle(canvas, size, size, 32, 32, 28, (78, 62, 35, 255), filled=False, thickness=2)
    _circle(canvas, size, size, 32, 31, 16, (38, 28, 19, 255))
    _rect(canvas, size, size, 27, 21, 38, 47, BRONZE)
    _circle(canvas, size, size, 32, 22, 9, BRONZE)
    _line(canvas, size, size, 26, 17, 20, 8, SILVER, thickness=2)
    _line(canvas, size, size, 38, 17, 44, 8, SILVER, thickness=2)
    _circle(canvas, size, size, 29, 22, 1, SHADOW)
    _circle(canvas, size, size, 35, 22, 1, SHADOW)
    _rect(canvas, size, size, 28, 33, 37, 36, SILVER)
    _line(canvas, size, size, 27, 48, 21, 58, BRONZE, thickness=3)
    _line(canvas, size, size, 37, 48, 43, 58, BRONZE, thickness=3)


def _tga(width: int, height: int, pixels: bytearray) -> bytes:
    header = bytearray(18)
    header[2] = 2  # uncompressed true-color
    header[12:14] = width.to_bytes(2, "little")
    header[14:16] = height.to_bytes(2, "little")
    header[16] = 32
    header[17] = 0x28  # eight alpha bits and top-left origin
    return bytes(header + pixels)


def render_assets() -> dict[str, bytes]:
    slot_atlas = _canvas(ATLAS_SIZE, ATLAS_SIZE)
    for slot, region in SLOT_REGIONS.items():
        _draw_slot_glyph(slot_atlas, slot, region)
    _draw_selected_ring(slot_atlas)

    highlight = _canvas(*ROUND_HIGHLIGHT_SIZE)
    _draw_round_highlight(highlight)

    mount = _canvas(64, 64)
    _draw_mount_portrait(mount)

    return {
        "Icons/WardrobeSlots/slot-atlas.tga": _tga(ATLAS_SIZE, ATLAS_SIZE, slot_atlas),
        "Icons/WardrobeSlots/round-highlight.tga": _tga(*ROUND_HIGHLIGHT_SIZE, highlight),
        "Icons/mount-portrait.tga": _tga(64, 64, mount),
    }


def _default_output_root() -> Path:
    return Path(__file__).resolve().parents[2] / "addon" / "SoloCollections" / "Media"


def _status_lines(assets: dict[str, bytes], root: Path) -> Iterable[str]:
    for relative, data in sorted(assets.items()):
        path = root / relative
        yield f"{relative} sha256={hashlib.sha256(data).hexdigest().upper()} bytes={len(data)} path={path}"


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output-root", type=Path, default=_default_output_root())
    parser.add_argument("--check", action="store_true", help="fail when a generated asset is absent or stale")
    parser.add_argument("--print-hashes", action="store_true")
    args = parser.parse_args(argv)

    assets = render_assets()
    stale: list[str] = []
    for relative, data in assets.items():
        path = args.output_root / relative
        if args.check:
            if not path.is_file() or path.read_bytes() != data:
                stale.append(relative)
        else:
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_bytes(data)

    if args.print_hashes:
        for line in _status_lines(assets, args.output_root):
            print(line)
    if stale:
        parser.error("generated base UI media is stale: " + ", ".join(stale))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
