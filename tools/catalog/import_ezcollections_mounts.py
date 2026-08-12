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

SOURCE_VALUE_LABELS = {
    "Recruit-a-Friend": "战友招募",
    "Trading Card Game": "集换式卡牌",
    "Blizzard Store": "暴雪游戏商城",
    "In-Game Shop": "游戏商城",
    "Annual Pass": "年度订阅",
    "Promotion": "促销",
    "Legacy": "绝版",
    "BlizzCon": "暴雪嘉年华",
}

# Keep committed source encoding deterministic: use Unicode escapes for all
# labels consumed by the generated UTF-8 JSON instead of locale-sensitive
# literal bytes inherited from the original importer.
SOURCE_LABELS = {
    "Vendor": "\u5546\u4eba", "Cost": "\u8d39\u7528", "Zone": "\u5730\u533a",
    "Location": "\u5730\u533a", "Drop": "\u6389\u843d", "Quest": "\u4efb\u52a1",
    "Achievement": "\u6210\u5c31", "Category": "\u5206\u7c7b", "Profession": "\u4e13\u4e1a",
    "Trainer": "\u8bad\u7ec3\u5e08", "Reputation": "\u58f0\u671b", "Faction": "\u9635\u8425",
    "Class": "\u804c\u4e1a", "World Event": "\u4e16\u754c\u4e8b\u4ef6",
    "Event": "\u4e16\u754c\u4e8b\u4ef6", "Holiday": "\u8282\u65e5", "Fishing": "\u9493\u9c7c",
}
SOURCE_VALUE_LABELS = {
    "Recruit-a-Friend": "\u6218\u53cb\u62db\u52df", "Trading Card Game": "\u96c6\u6362\u5f0f\u5361\u724c",
    "Blizzard Store": "\u66b4\u96ea\u6e38\u620f\u5546\u57ce", "In-Game Shop": "\u6e38\u620f\u5546\u57ce",
    "Annual Pass": "\u5e74\u5ea6\u8ba2\u9605", "Promotion": "\u4fc3\u9500", "Legacy": "\u7edd\u7248",
    "BlizzCon": "\u66b4\u96ea\u5609\u5e74\u534e",
}

VISIBILITY_BY_CLASS = {
    "STANDARD": True,
    "LEGACY": True,
    "PROMOTION": True,
    "SUPERSEDED_INTERNAL_DUPLICATE": False,
    "CLASS_SUMMON": False,
    "INTERNAL": False,
    "SERVER_ONLY": False,
    "MISSING_RECORD": False,
}

ACTION_EXCLUSION_BY_CLASS = {
    "SUPERSEDED_INTERNAL_DUPLICATE": "DUPLICATE",
    "CLASS_SUMMON": "CLASS_FORM",
    "INTERNAL": "TEST",
    "SERVER_ONLY": "INTERNAL",
    "MISSING_RECORD": "INTERNAL",
}


def mount_capability(spell_id: int, mount_type: int | None, flags: int,
                     action: dict[str, Any], overrides: dict[str, str]) -> str:
    override = overrides.get(str(spell_id))
    if override:
        return override
    # ezCollections stores a bit field here: 0x1 is flying-only and 0x4 is a
    # scripted ground/flying mount.  The source file applies several Set(2,
    # ...) mutations after declaring the table, so use the effective value.
    if (int(mount_type or 0) & 0x5) != 0 or any(
            bool(variant.get("isFlying")) for variant in action["actionVariants"]):
        return "FLYING"
    if (flags & 0x10) != 0:
        return "AQUATIC"
    return "GROUND"


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
    set_call = re.compile(r"\s*Set\((\d+)\s*,\s*(-?\d+)\s*,\s*(.*?)\)\s*;?.*$")
    lines = path.read_text(encoding="utf-8").splitlines()
    for line in lines:
        match = row.match(line)
        if match:
            mounts[int(match.group(1))] = [lua_literal(value) for value in split_lua_fields(match.group(2))]
    if not mounts:
        raise ValueError(f"no ezCollections mount rows found in {path}")
    # Replay only literal numeric Set mutations.  Function-valued predicates
    # are runtime usability checks and are deliberately not imported here.
    for line in lines:
        match = set_call.match(line)
        if not match:
            continue
        index = int(match.group(1)) - 1
        value = int(match.group(2))
        for spell_text in split_lua_fields(match.group(3)):
            spell_id = lua_literal(spell_text)
            if not isinstance(spell_id, int) or spell_id not in mounts:
                continue
            while len(mounts[spell_id]) <= index:
                mounts[spell_id].append(None)
            mounts[spell_id][index] = value
    return mounts


def localize_source(source: str) -> str:
    localized = source
    for english, chinese in SOURCE_LABELS.items():
        localized = localized.replace(f"|cFFFFD200{english}: |r", f"|cFFFFD200{chinese}：|r")
        localized = localized.replace(f"|cFFFFD200{english}:|r", f"|cFFFFD200{chinese}：|r")
    for english, chinese in SOURCE_VALUE_LABELS.items():
        localized = localized.replace(english, chinese)
    return localized


def read_zhcn_spell_texts(path: Path) -> dict[int, dict[str, str]]:
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
    result: dict[int, dict[str, str]] = {}
    name_field = 136 if fields == 234 else 143
    description_field = 170 if fields == 234 else 179

    def read_string(offset: int) -> str:
        if offset <= 0 or offset >= len(strings):
            return ""
        end = strings.find(b"\0", offset)
        if end < 0:
            return ""
        return strings[offset:end].decode("utf-8", errors="strict")

    for index in range(rows):
        record = struct.unpack_from(f"<{fields}I", data, 20 + index * record_size)
        name = read_string(int(record[name_field]))
        description = read_string(int(record[description_field]))
        if name or description:
            result[int(record[0])] = {"name": name, "description": description}
    return result


def lua_quote(text: str) -> str:
    return '"' + text.replace("\\", "\\\\").replace('"', '\\"').replace("\r", "").replace("\n", "\\n") + '"'


def write_description_lua(path: Path, descriptions: dict[int, str]) -> None:
    lines = [
        "-- Generated from the locked zhCN 3.3.5a Spell.dbc. Local integration only.",
        "SoloCollections_EzUI = SoloCollections_EzUI or {}",
        "SoloCollections_EzUI.MountDescriptionsZhCN = {",
    ]
    for spell_id in sorted(descriptions):
        lines.append(f"    [{spell_id}] = {lua_quote(descriptions[spell_id])},")
    lines.extend(["}", ""])
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text("\n".join(lines), encoding="utf-8", newline="\n")


def localize_source(source: str) -> str:
    localized = source
    for english, chinese in SOURCE_LABELS.items():
        localized = localized.replace(
            f"|cFFFFD200{english}: |r", f"|cFFFFD200{chinese}\uff1a|r"
        )
        localized = localized.replace(
            f"|cFFFFD200{english}:|r", f"|cFFFFD200{chinese}\uff1a|r"
        )
    for english, chinese in SOURCE_VALUE_LABELS.items():
        localized = localized.replace(english, chinese)
    return localized


def translate_source(source: str, translations: dict[str, str]) -> str:
    localized = localize_source(source)
    for english in sorted(translations, key=len, reverse=True):
        localized = localized.replace(english, translations[english])
    return localized


def reviewed_source(source: str, acquisition_class: str, translations: dict[str, str]) -> str:
    if acquisition_class == "LEGACY":
        return "|cFFFFD200\u83b7\u53d6\u7c7b\u578b\uff1a|r\u7edd\u7248"
    if acquisition_class == "PROMOTION":
        if "Trading Card Game" in source:
            channel = "\u96c6\u6362\u5f0f\u5361\u724c"
        elif "Recruit-a-Friend" in source:
            channel = "\u6218\u53cb\u62db\u52df"
        elif "BlizzCon" in source:
            channel = "\u66b4\u96ea\u5609\u5e74\u534e"
        elif "Blizzard Store" in source or "In-Game Shop" in source:
            channel = "\u6e38\u620f\u5546\u57ce"
        elif "Annual Pass" in source:
            channel = "\u5e74\u5ea6\u8ba2\u9605"
        else:
            channel = "\u4fc3\u9500"
        return "|cFFFFD200\u5386\u53f2\u83b7\u53d6\u6e20\u9053\uff1a|r" + channel
    return translate_source(source, translations)


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
    parser.add_argument("--visibility-policy", required=True, type=Path)
    parser.add_argument("--action-policy", required=True, type=Path)
    parser.add_argument("--visibility-report", type=Path)
    parser.add_argument("--action-audit-report", type=Path)
    parser.add_argument("--description-provenance-output", type=Path)
    parser.add_argument("--description-lua-output", type=Path)
    parser.add_argument("--output", required=True, type=Path)
    args = parser.parse_args()

    source_bytes = args.source.read_bytes()
    mounts = parse_mounts(args.source)
    dbc_bytes = args.zhcn_spell_dbc.read_bytes()
    spell_texts = read_zhcn_spell_texts(args.zhcn_spell_dbc)
    source_zhcn = json.loads(args.source_zhcn.read_text(encoding="utf-8"))
    policy = json.loads(args.visibility_policy.read_text(encoding="utf-8"))
    action_policy = json.loads(args.action_policy.read_text(encoding="utf-8"))
    if action_policy.get("schemaVersion") != 1:
        raise ValueError("unsupported mount action policy schema")
    capability_overrides = action_policy.get("capabilityOverrides", {})
    allowed_capabilities = {"GROUND", "FLYING", "AQUATIC", "SPECIAL"}
    if not set(capability_overrides.values()) <= allowed_capabilities:
        raise ValueError("mount capability override is invalid")
    source_hash = hashlib.sha256(source_bytes).hexdigest()
    dbc_hash = hashlib.sha256(dbc_bytes).hexdigest()
    if policy["inputs"]["ezCollectionsMountsSha256"] != source_hash:
        raise ValueError("visibility policy ezCollections input hash mismatch")
    if policy["inputs"]["zhcnSpellDbcSha256"] != dbc_hash:
        raise ValueError("visibility policy zhCN Spell.dbc hash mismatch")
    legacy_ids = {int(value) for value in policy["visibleLegacySpellIds"]}
    promotion_ids = {int(value) for value in policy["visiblePromotionSpellIds"]}
    duplicate_ids = {int(value) for value in policy["supersededDuplicateSpellIds"]}
    translations = source_zhcn["translations"]
    actions = json.loads(args.mount_actions.read_text(encoding="utf-8"))["collections"]
    entries = []
    classification_counts: dict[str, int] = {}
    visibility_counts = {"VISIBLE": 0, "HIDDEN": 0}
    descriptions: dict[int, str] = {}
    provenance_entries: list[dict[str, Any]] = []
    for action in sorted(actions, key=lambda entry: int(entry["collectionId"])):
        spell_id = int(action["canonicalSpellId"])
        fields = mounts.get(spell_id)
        candidate = classify(fields)
        if spell_id in duplicate_ids:
            acquisition_class = "SUPERSEDED_INTERNAL_DUPLICATE"
        elif candidate == "LEGACY":
            if spell_id not in legacy_ids:
                raise ValueError(f"unreviewed legacy mount spell {spell_id}")
            acquisition_class = "LEGACY"
        elif candidate == "PROMOTION":
            if spell_id not in promotion_ids:
                raise ValueError(f"unreviewed promotion mount spell {spell_id}")
            acquisition_class = "PROMOTION"
        elif candidate == "CLASS_SUMMON":
            acquisition_class = "CLASS_SUMMON"
        elif candidate == "NO_JOURNAL_METADATA":
            acquisition_class = "INTERNAL"
        elif candidate == "SERVER_ONLY":
            acquisition_class = "SERVER_ONLY"
        elif candidate == "MISSING_EZ_RECORD":
            acquisition_class = "MISSING_RECORD"
        else:
            acquisition_class = "STANDARD"
        journal_visible = VISIBILITY_BY_CLASS[acquisition_class]
        visibility_reason = None if journal_visible else acquisition_class
        exclusion_reason = None if journal_visible else ACTION_EXCLUSION_BY_CLASS[acquisition_class]
        classification_counts[acquisition_class] = classification_counts.get(acquisition_class, 0) + 1
        visibility_counts["VISIBLE" if journal_visible else "HIDDEN"] += 1
        rich = fields is not None and len(fields) >= 7
        source = str(fields[6]) if rich and fields[6] else ""
        spell_text = spell_texts.get(spell_id, {})
        zhcn_name = spell_text.get("name", "")
        description = spell_text.get("description", "").strip()
        description_status = "OFFICIAL_335_SPELL_DBC" if description and journal_visible else "NOT_INTEGRATED"
        if journal_visible and not description:
            raise ValueError(f"visible mount spell {spell_id} has no zhCN Description in Spell.dbc")
        if journal_visible:
            descriptions[spell_id] = description
        provenance_entries.append({
            "collectionId": int(action["collectionId"]),
            "spellId": spell_id,
            "clientBuild": "3.3.5.12340",
            "locale": "zhCN",
            "sourceType": "SPELL_DBC_DESCRIPTION_170",
            "textHash": hashlib.sha256(description.encode("utf-8")).hexdigest() if description and journal_visible else None,
            "status": description_status,
        })
        entries.append({
            "collectionId": int(action["collectionId"]),
            "spellId": spell_id,
            "journalName": str(fields[3]) if rich and fields[3] else "",
            "journalNameZhCN": zhcn_name,
            "mountType": int(fields[1]) if rich and fields[1] is not None else None,
            "sourceType": int(fields[5]) if rich and fields[5] is not None else None,
            "source": reviewed_source(source, acquisition_class, translations),
            "flags": int(fields[2] or 0) if fields else 0,
            "descriptionKey": spell_id,
            "descriptionStatus": description_status,
            "journalVisible": journal_visible,
            "actionable": journal_visible,
            "draggable": journal_visible,
            "randomEligible": journal_visible,
            "canonicalActionSpellId": spell_id if journal_visible else None,
            "capability": mount_capability(
                spell_id,
                int(fields[1]) if rich and fields[1] is not None else None,
                int(fields[2] or 0) if fields else 0,
                action,
                capability_overrides,
            ),
            "acquisitionClass": acquisition_class,
            "visibilityReason": visibility_reason,
            "uiCollectible": journal_visible,
            "exclusionReason": exclusion_reason,
        })

    if {int(entry["spellId"]) for entry in entries if entry["acquisitionClass"] == "LEGACY"} != legacy_ids:
        raise ValueError("reviewed LEGACY set does not match imported candidate set")
    if {int(entry["spellId"]) for entry in entries if entry["acquisitionClass"] == "PROMOTION"} != promotion_ids:
        raise ValueError("reviewed PROMOTION set does not match imported candidate set")
    expected_counts = {"STANDARD": 215, "LEGACY": 29, "PROMOTION": 14,
                       "SUPERSEDED_INTERNAL_DUPLICATE": 2, "CLASS_SUMMON": 7, "INTERNAL": 14}
    if classification_counts != expected_counts or visibility_counts != {"VISIBLE": 258, "HIDDEN": 23}:
        raise ValueError(f"unexpected mount visibility counts: {classification_counts} {visibility_counts}")

    output = {
        "schemaVersion": 2,
        "provenance": {
            "project": "ezCollections",
            "version": "2.2",
            "resource": "Data/Mounts.enUS.lua",
            "sha256": source_hash,
        },
        "zhCNProvenance": {
            "spellDbcSha256": dbc_hash,
            "sourceMapSha256": hashlib.sha256(args.source_zhcn.read_bytes()).hexdigest(),
            "locale": "zhCN",
        },
        "visibilityPolicy": {
            "included": ["standard", "legacy", "promotion"],
            "excluded": ["superseded internal duplicate", "class summon", "internal", "server-only", "missing record"],
        },
        "classificationCounts": dict(sorted(classification_counts.items())),
        "visibilityCounts": visibility_counts,
        "entries": entries,
    }
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(output, ensure_ascii=False, indent=2, sort_keys=True) + "\n", encoding="utf-8", newline="\n")
    report = {
        "schemaVersion": 1,
        "classificationCounts": dict(sorted(classification_counts.items())),
        "visibilityCounts": visibility_counts,
        "visibleSpellIds": [entry["spellId"] for entry in entries if entry["journalVisible"]],
        "hidden": [{"collectionId": entry["collectionId"], "spellId": entry["spellId"],
                    "reason": entry["visibilityReason"]} for entry in entries if not entry["journalVisible"]],
    }
    if args.visibility_report:
        args.visibility_report.parent.mkdir(parents=True, exist_ok=True)
        args.visibility_report.write_text(json.dumps(report, ensure_ascii=False, indent=2, sort_keys=True) + "\n", encoding="utf-8", newline="\n")
    if args.action_audit_report:
        visible = [entry for entry in entries if entry["journalVisible"]]
        hidden = [entry for entry in entries if not entry["journalVisible"]]
        canonical_action_ids = [int(entry["canonicalActionSpellId"]) for entry in visible]
        if len(canonical_action_ids) != len(set(canonical_action_ids)):
            raise ValueError("visible mount canonical action spell is not unique")
        pre_canonical = action_policy.get("preCanonicalExclusions", {})
        action_audit = {
            "schemaVersion": 1,
            "changeId": "CLIENT-20260812-089",
            "totalCanonical": len(entries),
            "journalVisible": len(visible),
            "excludedCanonical": len(hidden),
            "actionable": sum(bool(entry["actionable"]) for entry in entries),
            "draggable": sum(bool(entry["draggable"]) for entry in entries),
            "randomEligible": sum(bool(entry["randomEligible"]) for entry in entries),
            "uniqueCanonicalActionSpellCount": len(set(canonical_action_ids)),
            "capabilityCounts": {
                capability: sum(entry["capability"] == capability for entry in entries)
                for capability in sorted(allowed_capabilities)
            },
            "exclusionReasonCounts": {
                reason: sum(entry["exclusionReason"] == reason for entry in hidden)
                for reason in sorted({entry["exclusionReason"] for entry in hidden})
            },
            "excluded": [{
                "collectionId": entry["collectionId"],
                "spellId": entry["spellId"],
                "reason": entry["exclusionReason"],
            } for entry in hidden],
            "preCanonicalExclusions": pre_canonical,
            "taxiSpellIdsInCanonicalCatalog": sorted(
                set(int(value) for value in pre_canonical.get("TAXI", []))
                & {int(entry["spellId"]) for entry in entries}
            ),
        }
        args.action_audit_report.parent.mkdir(parents=True, exist_ok=True)
        args.action_audit_report.write_text(
            json.dumps(action_audit, ensure_ascii=False, indent=2, sort_keys=True) + "\n",
            encoding="utf-8", newline="\n")
    if args.description_provenance_output:
        provenance = {
            "schemaVersion": 2,
            "descriptionSourcePolicy": "Locked zhCN WoW 3.3.5a Spell.dbc Description field 170; no tooltip scraping or generated prose.",
            "spellDbcSha256": dbc_hash,
            "visibleCoverage": {"covered": len(descriptions), "expected": 258},
            "entries": provenance_entries,
        }
        args.description_provenance_output.parent.mkdir(parents=True, exist_ok=True)
        args.description_provenance_output.write_text(json.dumps(provenance, ensure_ascii=False, indent=2, sort_keys=True) + "\n", encoding="utf-8", newline="\n")
    if args.description_lua_output:
        write_description_lua(args.description_lua_output, descriptions)
    print(f"imported {len(entries)} mount rows: {dict(sorted(classification_counts.items()))}; visible={visibility_counts['VISIBLE']}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
