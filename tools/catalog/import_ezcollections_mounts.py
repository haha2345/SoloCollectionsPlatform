#!/usr/bin/env python3
"""Import the ezCollections mount journal projection for SoloCollections UI."""

from __future__ import annotations

import argparse
import ast
import hashlib
import json
import re
import struct
from pathlib import Path
from typing import Any


CLASS_SOURCE = re.compile(
    r"Class:|Trainer:.*Death Knight|\|cFFFFD200(?:Paladin|Warlock)\|r",
    re.IGNORECASE,
)
PROMOTION_SOURCE = re.compile(
    r"Promotion|Trading Card Game|Blizzard Store|In-Game Shop|Recruit-a-Friend|Annual Pass",
    re.IGNORECASE,
)

SOURCE_LABELS = {
    "Vendor": "商人",
    "Cost": "费用",
    "Zone": "地区",
    "Location": "地区",
    "Drop": "掉落",
    "Quest": "任务",
    "Achievement": "成就",
    "Category": "分类",
    "Profession": "专业",
    "Trainer": "训练师",
    "Reputation": "声望",
    "Faction": "阵营",
    "Class": "职业",
    "World Event": "世界事件",
    "Event": "世界事件",
    "Holiday": "节日",
    "Fishing": "钓鱼",
}


def split_lua_fields(text: str) -> list[str]:
    fields: list[str] = []
    field: list[str] = []
    quote: str | None = None
    escaped = False
    depth = 0
    for character in text:
        if quote:
            field.append(character)
            if escaped:
                escaped = False
            elif character == "\\":
                escaped = True
            elif character == quote:
                quote = None
        elif character in {'"', "'"}:
            quote = character
            field.append(character)
        elif character in "([{":
            depth += 1
            field.append(character)
        elif character in ")]}":
            depth -= 1
            field.append(character)
        elif character == "," and depth == 0:
            fields.append("".join(field).strip())
            field = []
        else:
            field.append(character)
    if field:
        fields.append("".join(field).strip())
    return fields


def lua_literal(text: str) -> Any:
    if not text:
        return None
    if text[0] in {'"', "'"}:
        return ast.literal_eval(text)
    if re.fullmatch(r"-?\d+", text):
        return int(text)
    return None


def parse_mounts(path: Path) -> dict[int, list[Any]]:
    mounts: dict[int, list[Any]] = {}
    row = re.compile(r"\s*\[(\d+)\]\s*=\s*\{(.*)\},?\s*$")
    for line in path.read_text(encoding="utf-8").splitlines():
        match = row.match(line)
        if match:
            mounts[int(match.group(1))] = [lua_literal(value) for value in split_lua_fields(match.group(2))]
    if not mounts:
        raise ValueError(f"no ezCollections mount rows found in {path}")
    return mounts


def localize_source(source: str) -> str:
    localized = source
    for english, chinese in SOURCE_LABELS.items():
        localized = localized.replace(f"|cFFFFD200{english}: |r", f"|cFFFFD200{chinese}：|r")
        localized = localized.replace(f"|cFFFFD200{english}:|r", f"|cFFFFD200{chinese}：|r")
    return localized


def read_zhcn_spell_names(path: Path) -> dict[int, str]:
    data = path.read_bytes()
    if len(data) < 20 or data[:4] != b"WDBC":
        raise ValueError(f"not a WDBC file: {path}")
    rows, fields, record_size, string_size = struct.unpack_from("<4I", data, 4)
    if fields not in (231, 234) or record_size != fields * 4:
        raise ValueError(f"Spell.dbc is not the 3.3.5a schema: {path}")
    records_end = 20 + rows * record_size
    if records_end + string_size != len(data):
        raise ValueError(f"truncated Spell.dbc: {path}")
    strings = data[records_end:]
    result: dict[int, str] = {}
    name_field = 136 if fields == 234 else 143
    for index in range(rows):
        record = struct.unpack_from(f"<{fields}I", data, 20 + index * record_size)
        offset = int(record[name_field])
        if offset <= 0 or offset >= len(strings):
            continue
        end = strings.find(b"\0", offset)
        if end >= 0:
            result[int(record[0])] = strings[offset:end].decode("utf-8", errors="strict")
    return result


def translate_source(source: str, translations: dict[str, str]) -> str:
    localized = localize_source(source)
    for english in sorted(translations, key=len, reverse=True):
        localized = localized.replace(english, translations[english])
    return localized


def classify(fields: list[Any] | None) -> str | None:
    if fields is None:
        return "MISSING_EZ_RECORD"
    if len(fields) < 7 or not fields[3] or not fields[4] or not fields[6]:
        return "NO_JOURNAL_METADATA"
    flags = int(fields[2] or 0)
    source = str(fields[6])
    if flags & 0x001:
        return "SERVER_ONLY"
    if re.search(r"Legacy", source, re.IGNORECASE):
        return "LEGACY"
    if CLASS_SOURCE.search(source):
        return "CLASS_SUMMON"
    if PROMOTION_SOURCE.search(source):
        return "PROMOTION"
    return None


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source", required=True, type=Path)
    parser.add_argument("--mount-actions", required=True, type=Path)
    parser.add_argument("--zhcn-spell-dbc", required=True, type=Path)
    parser.add_argument("--source-zhcn", required=True, type=Path)
    parser.add_argument("--output", required=True, type=Path)
    args = parser.parse_args()

    source_bytes = args.source.read_bytes()
    mounts = parse_mounts(args.source)
    zhcn_names = read_zhcn_spell_names(args.zhcn_spell_dbc)
    source_zhcn = json.loads(args.source_zhcn.read_text(encoding="utf-8"))
    translations = source_zhcn["translations"]
    actions = json.loads(args.mount_actions.read_text(encoding="utf-8"))["collections"]
    entries = []
    counts: dict[str, int] = {}
    for action in sorted(actions, key=lambda entry: int(entry["collectionId"])):
        spell_id = int(action["canonicalSpellId"])
        fields = mounts.get(spell_id)
        exclusion = classify(fields)
        status = exclusion or "ELIGIBLE"
        counts[status] = counts.get(status, 0) + 1
        rich = fields is not None and len(fields) >= 7
        source = str(fields[6]) if rich and fields[6] else ""
        zhcn_name = zhcn_names.get(spell_id, "")
        entries.append({
            "collectionId": int(action["collectionId"]),
            "spellId": spell_id,
            "journalName": str(fields[3]) if rich and fields[3] else "",
            "journalNameZhCN": zhcn_name,
            "description": (f"这是国服客户端中的“{zhcn_name}”坐骑。获取方式请参见来源信息。"
                            if zhcn_name else "获取方式请参见来源信息。"),
            "sourceType": int(fields[5]) if rich and fields[5] is not None else None,
            "source": translate_source(source, translations),
            "flags": int(fields[2] or 0) if fields else 0,
            "uiCollectible": exclusion is None,
            "exclusionReason": exclusion,
        })

    output = {
        "schemaVersion": 1,
        "provenance": {
            "project": "ezCollections",
            "version": "2.2",
            "resource": "Data/Mounts.enUS.lua",
            "sha256": hashlib.sha256(source_bytes).hexdigest(),
        },
        "zhCNProvenance": {
            "spellDbcSha256": hashlib.sha256(args.zhcn_spell_dbc.read_bytes()).hexdigest(),
            "sourceMapSha256": hashlib.sha256(args.source_zhcn.read_bytes()).hexdigest(),
            "locale": "zhCN",
        },
        "eligibilityPolicy": {
            "included": ["vendor", "drop", "quest reward", "achievement", "profession", "world event", "fishing"],
            "excluded": ["class summon", "legacy", "promotion or out-of-game entitlement", "server-only", "missing mount-journal metadata"],
        },
        "counts": dict(sorted(counts.items())),
        "entries": entries,
    }
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(output, ensure_ascii=False, indent=2, sort_keys=True) + "\n", encoding="utf-8", newline="\n")
    print(f"imported {len(entries)} mount rows: {dict(sorted(counts.items()))}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
