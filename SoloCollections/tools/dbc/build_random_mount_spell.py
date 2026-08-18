#!/usr/bin/env python3
"""Build private 3.3.5a DBC overrides for SoloCollections random mount spell.

The generated DBC files are local integration artifacts and must not be committed.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import re
import struct
from pathlib import Path


SPELL_ID = 150544
SKILL_LINE_ID = 183
SPELL_FIELDS = 234
SPELL_RECORD_SIZE = 936
SKILL_FIELDS = 14
SKILL_RECORD_SIZE = 56
SPELL_ICON_FIELDS = 2
SPELL_ICON_RECORD_SIZE = 8
RANDOM_MOUNT_ICON_PATH = "Interface\\Icons\\SoloCollections_RandomMount"
SPELL_ATTR4_ONLY_FLYING_AREAS = 0x04000000


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def read_dbc(path: Path, fields: int, record_size: int):
    data = path.read_bytes()
    if len(data) < 20:
        raise ValueError(f"truncated DBC: {path}")
    magic, count, actual_fields, actual_size, string_size = struct.unpack_from("<4s4I", data)
    if magic != b"WDBC" or actual_fields != fields or actual_size != record_size:
        raise ValueError(
            f"unexpected DBC schema: {path} fields={actual_fields} recordSize={actual_size}"
        )
    records_end = 20 + count * record_size
    if records_end + string_size != len(data):
        raise ValueError(f"DBC size mismatch: {path}")
    rows = [list(struct.unpack_from(f"<{fields}I", data, 20 + i * record_size)) for i in range(count)]
    return rows, bytearray(data[records_end:])


def write_dbc(path: Path, rows: list[list[int]], strings: bytearray) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    fields = len(rows[0])
    record_size = fields * 4
    payload = bytearray(struct.pack("<4s4I", b"WDBC", len(rows), fields, record_size, len(strings)))
    for row in rows:
        payload.extend(struct.pack(f"<{fields}I", *row))
    payload.extend(strings)
    path.write_bytes(payload)


def append_string(strings: bytearray, value: str) -> int:
    encoded = value.encode("utf-8")
    needle = encoded + b"\0"
    found = strings.find(needle)
    if found >= 0:
        return found
    offset = len(strings)
    strings.extend(needle)
    return offset


def flying_catalog_actions(path: Path) -> set[int]:
    result: set[int] = set()
    for line in path.read_text(encoding="utf-8").splitlines():
        match = re.search(
            r'CatalogLifecycle::Active, true, true, true, .*?, (\d+)u, MountCapability::Flying,',
            line,
        )
        if match:
            result.add(int(match.group(1)))
    if not result:
        raise ValueError(f"no active flying mount actions found in {path}")
    return result


def build_spell(
    source: Path,
    output: Path,
    icon_id: int,
    client_ground_fallback_actions: set[int] | None = None,
) -> dict:
    rows, strings = read_dbc(source, SPELL_FIELDS, SPELL_RECORD_SIZE)
    if any(row[0] == SPELL_ID for row in rows):
        raise ValueError(f"Spell ID {SPELL_ID} already exists; refusing to overwrite")

    row = [0] * SPELL_FIELDS
    row[0] = SPELL_ID
    row[28] = 1                  # instant SpellCastTimes row
    row[46] = 1                  # self range
    row[68] = 0xFFFFFFFF         # no equipped-item class requirement
    row[69] = 0
    row[70] = 0
    row[71] = 3                  # SPELL_EFFECT_DUMMY; SpellScript owns behavior
    row[86] = 1                  # TARGET_UNIT_CASTER
    row[133] = icon_id           # private random-mount icon shared with the journal button
    row[225] = 1                 # physical school mask

    names = {
        0: "Summon Random Favorite Mount",
        4: "召唤随机偏好坐骑",
        5: "召喚隨機偏好坐騎",
    }
    descriptions = {
        0: "Summons a random usable favorite mount, or any usable collected mount when no favorite is available.",
        4: "随机召唤一只当前可用的偏好坐骑；没有可用偏好时，从已获得坐骑中选择。",
        5: "隨機召喚一隻目前可用的偏好坐騎；沒有可用偏好時，從已取得坐騎中選擇。",
    }
    tooltips = {
        0: "Uses the authoritative SoloCollections mount pool.",
        4: "使用服务端权威收藏与偏好池。再次使用可下坐骑。",
        5: "使用伺服器權威收藏與偏好池。再次使用可下坐騎。",
    }
    for locale, text in names.items():
        row[136 + locale] = append_string(strings, text)
    for locale, text in descriptions.items():
        row[170 + locale] = append_string(strings, text)
    for locale, text in tooltips.items():
        row[187 + locale] = append_string(strings, text)

    rows.append(row)
    rows.sort(key=lambda item: item[0])
    cleared = []
    if client_ground_fallback_actions:
        for candidate in rows:
            if candidate[0] in client_ground_fallback_actions and candidate[8] & SPELL_ATTR4_ONLY_FLYING_AREAS:
                candidate[8] &= ~SPELL_ATTR4_ONLY_FLYING_AREAS
                cleared.append(candidate[0])
    write_dbc(output, rows, strings)
    return {
        "beforeRows": len(rows) - 1,
        "afterRows": len(rows),
        "iconId": row[133],
        "clientGroundFallbackAttributeCleared": cleared,
    }


def build_spell_icon(source: Path, output: Path) -> dict:
    rows, strings = read_dbc(source, SPELL_ICON_FIELDS, SPELL_ICON_RECORD_SIZE)
    for row in rows:
        start = row[1]
        end = strings.find(b"\0", start)
        if end < 0:
            raise ValueError(f"unterminated SpellIcon path at ID {row[0]}")
        existing = strings[start:end].decode("utf-8")
        if existing.casefold() == RANDOM_MOUNT_ICON_PATH.casefold():
            raise ValueError(
                f"SpellIcon path {RANDOM_MOUNT_ICON_PATH} already exists at ID {row[0]}; "
                "refusing to create an ambiguous baseline"
            )
    icon_id = max(row[0] for row in rows) + 1
    rows.append([icon_id, append_string(strings, RANDOM_MOUNT_ICON_PATH)])
    rows.sort(key=lambda item: item[0])
    write_dbc(output, rows, strings)
    return {
        "beforeRows": len(rows) - 1,
        "afterRows": len(rows),
        "iconId": icon_id,
        "iconPath": RANDOM_MOUNT_ICON_PATH,
    }


def build_skill(source: Path, output: Path) -> dict:
    rows, strings = read_dbc(source, SKILL_FIELDS, SKILL_RECORD_SIZE)
    if any(row[2] == SPELL_ID for row in rows):
        raise ValueError(f"SkillLineAbility already references spell {SPELL_ID}; refusing to overwrite")
    new_id = max(row[0] for row in rows) + 1
    row = [new_id, SKILL_LINE_ID, SPELL_ID, 0, 0, 0, 0, 1, 0, 2, 0, 0, 0, 0]
    rows.append(row)
    rows.sort(key=lambda item: item[0])
    write_dbc(output, rows, strings)
    return {"beforeRows": len(rows) - 1, "afterRows": len(rows), "rowId": new_id, "skillLine": SKILL_LINE_ID}


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--spell", type=Path, required=True)
    parser.add_argument("--skill-line-ability", type=Path, required=True)
    parser.add_argument("--spell-icon", type=Path, required=True)
    parser.add_argument("--output-root", type=Path, required=True)
    parser.add_argument("--mount-catalog-inc", type=Path, required=True)
    parser.add_argument("--change-id", required=True)
    args = parser.parse_args()

    output_dir = args.output_root / "DBFilesClient"
    output_spell = output_dir / "Spell.dbc"
    output_skill = output_dir / "SkillLineAbility.dbc"
    output_icon = output_dir / "SpellIcon.dbc"
    server_output_dir = args.output_root / "server" / "DBFilesClient"
    server_output_spell = server_output_dir / "Spell.dbc"
    server_output_skill = server_output_dir / "SkillLineAbility.dbc"
    server_output_icon = server_output_dir / "SpellIcon.dbc"
    before = {
        "Spell.dbc": sha256(args.spell),
        "SkillLineAbility.dbc": sha256(args.skill_line_ability),
        "SpellIcon.dbc": sha256(args.spell_icon),
    }
    actions = flying_catalog_actions(args.mount_catalog_inc)
    icon_result = build_spell_icon(args.spell_icon, output_icon)
    spell_result = build_spell(args.spell, output_spell, icon_result["iconId"], actions)
    skill_result = build_skill(args.skill_line_ability, output_skill)
    server_icon_result = build_spell_icon(args.spell_icon, server_output_icon)
    if server_icon_result["iconId"] != icon_result["iconId"]:
        raise ValueError("client and server SpellIcon IDs diverged")
    server_spell_result = build_spell(args.spell, server_output_spell, server_icon_result["iconId"])
    server_skill_result = build_skill(args.skill_line_ability, server_output_skill)
    manifest = {
        "schemaVersion": 1,
        "changeId": args.change_id,
        "spellId": SPELL_ID,
        "nameZhCN": "召唤随机偏好坐骑",
        "sourceSha256": before,
        "outputSha256": {
            "Spell.dbc": sha256(output_spell),
            "SkillLineAbility.dbc": sha256(output_skill),
            "SpellIcon.dbc": sha256(output_icon),
        },
        "serverOutputSha256": {
            "Spell.dbc": sha256(server_output_spell),
            "SkillLineAbility.dbc": sha256(server_output_skill),
            "SpellIcon.dbc": sha256(server_output_icon),
        },
        "spell": spell_result,
        "skillLineAbility": skill_result,
        "spellIcon": icon_result,
        "serverSpell": server_spell_result,
        "serverSkillLineAbility": server_skill_result,
        "serverSpellIcon": server_icon_result,
    }
    (args.output_root / "random-mount-spell-manifest.json").write_text(
        json.dumps(manifest, ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
    )
    print(json.dumps(manifest, ensure_ascii=False, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
