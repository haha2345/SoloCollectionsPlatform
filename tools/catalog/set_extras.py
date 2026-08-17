"""Attach name-family offset pieces to normalized ItemSet members."""

from __future__ import annotations

import json
from pathlib import Path
from typing import Any

CLASS_KEYS = {
    1: "warrior", 2: "paladin", 3: "hunter", 4: "rogue", 5: "priest",
    6: "death_knight", 7: "shaman", 8: "mage", 9: "warlock", 11: "druid",
}
SLOT_ORDER = {
    key: index for index, key in enumerate((
        "HEAD", "SHOULDER", "BACK", "CHEST", "ROBE", "WRIST", "HANDS", "WAIST",
        "LEGS", "FEET", "MAINHAND", "OFFHAND", "RANGED", "SHIRT", "TABARD",
    ))
}
EXTRA_SLOTS = ("WRIST", "WAIST", "FEET", "BACK")
CORE_ARMOR_SLOTS = ("HEAD", "SHOULDER", "CHEST", "HANDS", "LEGS")
ARMOR_ITEM_CLASS = 4
MIN_CJK = 2
MIN_CORE_CJK = 2
DIFFICULTY_PREFIXES = ("英雄的", "勇猛的", "征服者的", "勇敢的", "圣洁的", "华丽的")
SLOT_SUFFIXES = (
    "护腕", "腕甲", "腕轮", "护臂",
    "腰带", "束带", "护腰", "腰索",
    "长靴", "战靴", "便鞋", "布鞋", "长鞋", "护足", "胫甲",
    "披风", "斗篷",
)


def read_json(path: Path) -> Any:
    return json.loads(path.read_text(encoding="utf-8-sig"))


def cjk_count(text: str) -> int:
    return sum(1 for char in text if "\u4e00" <= char <= "\u9fff")


def longest_common_prefix(names: list[str]) -> str:
    if not names:
        return ""
    prefix = names[0]
    for name in names[1:]:
        while prefix and not name.startswith(prefix):
            prefix = prefix[:-1]
        if not prefix:
            return ""
    return prefix


def class_mask_for_policy(policy: dict[str, Any]) -> int:
    if policy.get("mode") == "ANY":
        return -1
    mask = 0
    reverse = {name: class_id for class_id, name in CLASS_KEYS.items()}
    for key in policy.get("allowedClassKeys") or []:
        class_id = reverse.get(str(key))
        if class_id:
            mask |= 1 << (class_id - 1)
    return mask


def class_compatible(allowable: int, set_mask: int) -> bool:
    if set_mask == -1 or allowable in (-1, 0):
        return True
    return (allowable & set_mask) != 0


def override_map(entries: list[dict[str, Any]]) -> dict[int, dict[str, Any]]:
    result: dict[int, dict[str, Any]] = {}
    for entry in entries:
        item_set_id = int(entry.get("itemSetId") or 0)
        if item_set_id:
            result[item_set_id] = entry
    return result


def appearance_indexes(catalog: dict[str, Any]) -> tuple[dict[int, dict[str, Any]], dict[str, list[dict[str, Any]]]]:
    by_item: dict[int, dict[str, Any]] = {}
    by_slot: dict[str, list[dict[str, Any]]] = {slot: [] for slot in EXTRA_SLOTS}
    for group in catalog.get("groups", []):
        if group.get("lifecycle") != "active":
            continue
        for item_id in group.get("sourceItemIds") or []:
            by_item[int(item_id)] = group
        slot = str(group.get("slotKey") or "")
        if slot in by_slot and int(group.get("itemClass") or 0) == ARMOR_ITEM_CLASS:
            by_slot[slot].append(group)
    return by_item, by_slot


def member_names(members: list[dict[str, Any]], by_item: dict[int, dict[str, Any]]) -> list[str]:
    names: list[str] = []
    for member in members:
        for item_id in member.get("sourceItemIds") or []:
            group = by_item.get(int(item_id))
            name = str(group.get("name") or "") if group else ""
            if name:
                names.append(name)
                break
    return names


def member_armor_subclass(members: list[dict[str, Any]], by_item: dict[int, dict[str, Any]]) -> int | None:
    counts: dict[int, int] = {}
    for member in members:
        for item_id in member.get("sourceItemIds") or []:
            group = by_item.get(int(item_id))
            if not group or int(group.get("itemClass") or 0) != ARMOR_ITEM_CLASS:
                continue
            subclass = int(group.get("itemSubclass") or 0)
            if subclass:
                counts[subclass] = counts.get(subclass, 0) + 1
            break
    if not counts:
        return None
    return max(counts.items(), key=lambda item: (item[1], -item[0]))[0]


def occupied_slots(members: list[dict[str, Any]]) -> set[str]:
    return {str(member.get("slotKey") or "") for member in members}


def strip_difficulty(name: str) -> tuple[str, str]:
    for prefix in DIFFICULTY_PREFIXES:
        if name.startswith(prefix):
            return prefix, name[len(prefix):]
    return "", name


def remainder_is_slot_piece(name: str, prefix: str) -> bool:
    if not name.startswith(prefix):
        return False
    remainder = name[len(prefix):]
    if remainder.startswith("的"):
        remainder = remainder[1:]
    return remainder in SLOT_SUFFIXES


def family_prefixes(names: list[str]) -> list[str]:
    prefixes: list[str] = []
    if len(names) >= 2:
        prefix = longest_common_prefix(names)
        if cjk_count(prefix) >= MIN_CJK:
            prefixes.append(prefix)
    cores = [strip_difficulty(name)[1] for name in names]
    if len(cores) >= 2:
        core = longest_common_prefix(cores)
        if cjk_count(core) >= MIN_CORE_CJK and core not in prefixes:
            prefixes.append(core)
    return prefixes


def member_difficulty(names: list[str]) -> str:
    prefixes = [strip_difficulty(name)[0] for name in names]
    prefixes = [prefix for prefix in prefixes if prefix]
    if prefixes and all(prefix == prefixes[0] for prefix in prefixes):
        return prefixes[0]
    return ""


def attach_name_family_extras(
    repo_root: Path,
    normalized_sets: list[dict[str, Any]],
    candidates: list[dict[str, Any]],
) -> dict[str, int]:
    catalog = read_json(repo_root / "catalog/generated/appearance-sources.json")
    overrides_source = read_json(repo_root / "catalog/source/overrides/sets.json")
    by_item, by_slot = appearance_indexes(catalog)
    overrides = override_map(overrides_source.get("entries") or [])
    reserved = {int(item_id) for row in candidates for item_id in row.get("dbcItemIds") or []}
    stats = {
        "setsConsidered": 0,
        "setsWithExtras": 0,
        "extrasAdded": 0,
        "feet": 0,
        "wrist": 0,
        "waist": 0,
        "back": 0,
        "skippedShortPrefix": 0,
    }
    slot_stat = {"FEET": "feet", "WRIST": "wrist", "WAIST": "waist", "BACK": "back"}

    for definition in normalized_sets:
        variants = definition.get("variants") or []
        if not variants:
            continue
        variant = variants[0]
        members = list(variant.get("members") or [])
        stats["setsConsidered"] += 1
        names = member_names(members, by_item)
        prefixes = family_prefixes(names)
        core_slots = occupied_slots(members) & set(CORE_ARMOR_SLOTS)
        if len(core_slots) < 3 or not prefixes:
            stats["skippedShortPrefix"] += 1
            continue
        item_set_id = int(definition.get("itemSetId") or 0)
        rule = overrides.get(item_set_id) or {}
        excluded_slots = {str(slot) for slot in rule.get("excludeSlots") or []}
        excluded_items = {int(item_id) for item_id in rule.get("excludeItemIds") or []}
        set_mask = class_mask_for_policy(definition.get("classPolicy") or {})
        armor_subclass = member_armor_subclass(members, by_item)
        present = occupied_slots(members)
        difficulty = member_difficulty(names)
        added = 0
        for slot in EXTRA_SLOTS:
            if slot in present or slot in excluded_slots:
                continue
            chosen: dict[str, Any] | None = None
            chosen_item_id = 0
            chosen_rank = 99
            for group in by_slot.get(slot) or []:
                name = str(group.get("name") or "")
                matched_prefix = next((prefix for prefix in prefixes if remainder_is_slot_piece(name, prefix)
                                       or remainder_is_slot_piece(strip_difficulty(name)[1], prefix)), None)
                if not matched_prefix:
                    continue
                if armor_subclass and int(group.get("itemSubclass") or 0) != armor_subclass:
                    continue
                if not class_compatible(int(group.get("allowableClass") or -1), set_mask):
                    continue
                source_ids = [int(item_id) for item_id in group.get("sourceItemIds") or []]
                usable = [
                    item_id for item_id in source_ids
                    if item_id not in reserved and item_id not in excluded_items
                ]
                if not usable:
                    continue
                item_id = min(usable)
                extra_difficulty, _ = strip_difficulty(name)
                rank = 0 if difficulty and extra_difficulty == difficulty else 1
                if chosen is None or rank < chosen_rank or (rank == chosen_rank and item_id < chosen_item_id):
                    chosen = group
                    chosen_item_id = item_id
                    chosen_rank = rank
            if chosen is None:
                continue
            members.append({
                "appearanceIds": [int(chosen["appearanceId"])],
                "memberKey": slot.lower(),
                "required": True,
                "slotKey": slot,
                "sourceItemIds": [chosen_item_id],
            })
            present.add(slot)
            added += 1
            stats[slot_stat[slot]] += 1
        if added:
            members.sort(key=lambda member: (SLOT_ORDER.get(str(member.get("slotKey")), 99),
                                             str(member.get("memberKey") or "")))
            variant["members"] = members
            stats["setsWithExtras"] += 1
            stats["extrasAdded"] += added
    return stats
