#!/usr/bin/env python3
"""Select one client-renderable representative for each WotLK weapon subclass.

Read tab-separated rows from stdin in this order:
    subclass, item entry, name, ItemDisplayInfo ID, inventory type, quality, item level

The script checks the supplied 3.3.5 ItemDisplayInfo.dbc before selecting a
row.  That prevents a server-only display ID from reaching the M2 packaging
step, where it would otherwise fail after a much longer MPQ build.
"""

from __future__ import annotations

import argparse
import struct
import sys
from pathlib import Path


WEAPON_SUBCLASSES = {
    0: "单手斧",
    1: "双手斧",
    2: "弓",
    3: "枪械",
    4: "单手锤",
    5: "双手锤",
    6: "长柄武器",
    7: "单手剑",
    8: "双手剑",
    10: "法杖",
    13: "拳套",
    15: "匕首",
    16: "投掷武器",
    18: "弩",
    19: "魔杖",
    20: "钓鱼竿",
}


def load_item_display_info(path: Path) -> dict[int, tuple[str, str, str, str, str]]:
    data = path.read_bytes()
    if len(data) < 20 or data[:4] != b"WDBC":
        raise ValueError("expected a WDBC ItemDisplayInfo.dbc")
    rows, fields, record_size, string_size = struct.unpack_from("<4I", data, 4)
    if (fields, record_size) != (25, 100):
        raise ValueError(
            f"unexpected ItemDisplayInfo layout: fields={fields}, record_size={record_size}"
        )
    records_end = 20 + rows * record_size
    strings = data[records_end : records_end + string_size]
    if len(strings) != string_size:
        raise ValueError("truncated ItemDisplayInfo string block")

    def read_string(offset: int) -> str:
        if offset == 0:
            return ""
        end = strings.find(b"\0", offset)
        if end < 0:
            raise ValueError(f"unterminated string at offset {offset}")
        return strings[offset:end].decode("utf-8", errors="replace")

    result: dict[int, tuple[str, str, str, str, str]] = {}
    for index in range(rows):
        values = struct.unpack_from("<25I", data, 20 + index * record_size)
        display_id = values[0]
        left_model = read_string(values[1])
        right_model = read_string(values[2])
        left_texture = read_string(values[3])
        right_texture = read_string(values[4])
        icon = read_string(values[5])
        # CreatureDisplayInfo uses one M2 + one MONSTER_SKIN_1 texture. The
        # left-hand pair is the stable primary source for a representative
        # item; an empty left pair cannot be packaged by this test route.
        if left_model and left_texture:
            result[display_id] = (
                left_model,
                right_model,
                left_texture,
                right_texture,
                icon,
            )
    return result


def select_samples(displays: dict[int, tuple[str, str, str, str, str]]) -> dict[int, tuple[str, ...]]:
    selected: dict[int, tuple[str, ...]] = {}
    for raw_line in sys.stdin.buffer:
        fields = raw_line.decode("utf-8", errors="replace").rstrip("\r\n").split("\t")
        if len(fields) != 7:
            continue
        try:
            subclass = int(fields[0])
            display_id = int(fields[3])
        except ValueError:
            continue
        if subclass not in WEAPON_SUBCLASSES or subclass in selected or display_id not in displays:
            continue
        # QA/test rows are not useful visual references even if their display
        # data is technically valid.
        if "QA" in fields[2] or "测试" in fields[2]:
            continue
        selected[subclass] = tuple(fields) + displays[display_id]
    return selected


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--item-display-info", type=Path, required=True)
    args = parser.parse_args()

    samples = select_samples(load_item_display_info(args.item_display_info))
    print(
        "subclass\ttype\titem_id\tname\tdisplay_id\tinventory_type\tquality\titem_level"
        "\tleft_model\tright_model\tleft_texture\tright_texture\ticon"
    )
    for subclass, type_name in WEAPON_SUBCLASSES.items():
        sample = samples.get(subclass)
        if not sample:
            print(f"{subclass}\t{type_name}\tMISSING")
            continue
        (
            _input_subclass,
            item_id,
            name,
            display_id,
            inventory_type,
            quality,
            item_level,
            left_model,
            right_model,
            left_texture,
            right_texture,
            icon,
        ) = sample
        print(
            "\t".join(
                [
                    str(subclass),
                    type_name,
                    item_id,
                    name,
                    display_id,
                    inventory_type,
                    quality,
                    item_level,
                    left_model,
                    right_model,
                    left_texture,
                    right_texture,
                    icon,
                ]
            )
        )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
