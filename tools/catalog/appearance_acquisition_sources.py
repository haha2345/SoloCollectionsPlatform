#!/usr/bin/env python3
"""Generate player-facing acquisition sources for wardrobe appearance items."""

from __future__ import annotations

import argparse
import json
import os
import re
import subprocess
import sys
from collections import defaultdict
from pathlib import Path
from typing import Any


class AcquisitionError(ValueError):
    pass


REWARD_COLUMNS = (
    "RewardItem1", "RewardItem2", "RewardItem3", "RewardItem4",
    "RewardChoiceItemID1", "RewardChoiceItemID2", "RewardChoiceItemID3",
    "RewardChoiceItemID4", "RewardChoiceItemID5", "RewardChoiceItemID6",
)
CRAFT_SKILL_LINES = {
    164,  # Blacksmithing
    165,  # Leatherworking
    197,  # Tailoring
    202,  # Engineering
}
KIND_PRIORITY = {
    "quest": 10,
    "vendor": 20,
    "drop": 30,
    "gameobject": 40,
    "container": 50,
    "crafted": 60,
}
MAP_NAMES = {
    0: "东部王国",
    1: "卡利姆多",
    30: "奥特兰克山谷",
    33: "影牙城堡",
    34: "暴风城监狱",
    36: "死亡矿井",
    43: "哀嚎洞穴",
    47: "剃刀沼泽",
    48: "黑暗深渊",
    70: "奥达曼",
    90: "诺莫瑞根",
    109: "沉没的神庙",
    129: "剃刀高地",
    169: "翡翠梦境",
    189: "血色修道院",
    209: "祖尔法拉克",
    229: "黑石塔",
    230: "黑石深渊",
    249: "奥妮克希亚的巢穴",
    269: "黑色沼泽",
    289: "通灵学院",
    309: "祖尔格拉布",
    329: "斯坦索姆",
    349: "玛拉顿",
    389: "怒焰裂谷",
    409: "熔火之心",
    429: "厄运之槌",
    469: "黑翼之巢",
    489: "战歌峡谷",
    529: "阿拉希盆地",
    530: "外域",
    531: "安其拉神殿",
    532: "卡拉赞",
    533: "纳克萨玛斯",
    534: "海加尔山之战",
    540: "破碎大厅",
    542: "鲜血熔炉",
    543: "地狱火城墙",
    544: "玛瑟里顿的巢穴",
    545: "蒸汽地窟",
    546: "幽暗沼泽",
    547: "奴隶围栏",
    548: "毒蛇神殿",
    550: "风暴要塞",
    552: "禁魔监狱",
    553: "生态船",
    554: "能源舰",
    555: "暗影迷宫",
    556: "塞泰克大厅",
    557: "法力陵墓",
    558: "奥金尼地穴",
    560: "旧希尔斯布莱德丘陵",
    562: "刀锋山竞技场",
    564: "黑暗神殿",
    565: "格鲁尔的巢穴",
    566: "风暴之眼",
    568: "祖阿曼",
    571: "诺森德",
    572: "洛丹伦废墟",
    574: "乌特加德城堡",
    575: "乌特加德之巅",
    576: "魔枢",
    578: "魔环",
    580: "太阳之井高地",
    585: "魔导师平台",
    595: "净化斯坦索姆",
    599: "岩石大厅",
    600: "达克萨隆要塞",
    601: "艾卓-尼鲁布",
    602: "闪电大厅",
    603: "奥杜尔",
    604: "古达克",
    607: "远古海滩",
    608: "紫罗兰监狱",
    615: "黑曜石圣殿",
    616: "永恒之眼",
    619: "安卡赫特：古代王国",
    624: "阿尔卡冯的宝库",
    628: "冠军的试炼",
    631: "冰冠堡垒",
    632: "灵魂洪炉",
    649: "十字军的试炼",
    650: "萨隆矿坑",
    658: "映像大厅",
    668: "洛丹伦之战",
    724: "红玉圣殿",
}
TOKEN_SEPARATOR = "##SCMAP##"


def require(condition: bool, message: str) -> None:
    if not condition:
        raise AcquisitionError(message)


def read_json(path: Path) -> Any:
    try:
        return json.loads(path.read_text(encoding="utf-8-sig"))
    except (OSError, json.JSONDecodeError) as exc:
        raise AcquisitionError(f"cannot read JSON {path}: {exc}") from exc


def parse_database_info(config: Path) -> tuple[str, str, str, str, str]:
    text = config.read_text(encoding="utf-8-sig", errors="replace")
    match = re.search(r'^\s*WorldDatabaseInfo\s*=\s*"([^"]+)"', text, re.MULTILINE)
    require(match is not None, f"WorldDatabaseInfo missing from {config}")
    parts = match.group(1).split(";")
    require(len(parts) >= 5, "WorldDatabaseInfo has an unexpected format")
    return parts[0], parts[1], parts[2], parts[3], parts[4]


def mysql_rows(mysql: Path, config: Path, query: str) -> list[list[str]]:
    host, port, user, password, database = parse_database_info(config)
    environment = os.environ.copy()
    environment["MYSQL_PWD"] = password
    result = subprocess.run(
        [
            str(mysql),
            f"--host={host}",
            f"--port={port}",
            f"--user={user}",
            f"--database={database}",
            "--default-character-set=utf8mb4",
            "--batch",
            "--raw",
            "--skip-column-names",
        ],
        check=False,
        capture_output=True,
        input=query,
        text=True,
        encoding="utf-8",
        errors="replace",
        env=environment,
    )
    require(result.returncode == 0, f"World DB query failed (credentials redacted): {result.stderr.strip()}")
    return [line.split("\t") for line in result.stdout.splitlines() if line]


def chunks(values: list[int], size: int) -> list[list[int]]:
    return [values[index:index + size] for index in range(0, len(values), size)]


def in_list(values: list[int]) -> str:
    return ",".join(str(int(value)) for value in values)


def normalize_text(value: str) -> str:
    return " ".join((value or "").replace("\r", " ").replace("\n", " ").replace("\t", " ").split())


def normalize_source_name(value: str) -> str:
    value = normalize_text(value)
    value = re.sub(r"\s*\([0-9]+\)$", "", value)
    value = re.sub(r"^The (?=[\u3400-\u9fff])", "", value)
    return value


def normalize_source_token(value: str) -> str:
    name, _, map_id = value.partition(TOKEN_SEPARATOR)
    name = normalize_source_name(name)
    if not name:
        return ""
    try:
        map_name = MAP_NAMES.get(int(map_id))
    except ValueError:
        map_name = None
    if map_name:
        return f"{name}（{map_name}）"
    return name


def first_names(names: str, count: int, unit: str) -> str:
    unique_names = []
    seen = set()
    for name in names.split("；"):
        name = normalize_source_token(name)
        if name and name not in seen:
            unique_names.append(name)
            seen.add(name)
    names = "；".join(unique_names[:4])
    if count <= 0:
        return ""
    if count <= 4:
        return names
    return f"{names} 等 {count} 个{unit}"


def source_item_ids(repo: Path) -> list[int]:
    catalog = read_json(repo / "catalog/generated/appearance-sources.json")
    visibility = read_json(repo / "catalog/review/appearances/visibility-evidence.json")
    public_appearances = {
        int(entry["appearanceId"])
        for entry in visibility.get("decisions", [])
        if entry.get("uiLifecycle") == "public"
    }
    result: set[int] = set()
    for group in catalog.get("groups", []):
        if int(group.get("appearanceId", 0)) not in public_appearances:
            continue
        for item_id in group.get("sourceItemIds", []):
            item_id = int(item_id)
            if item_id > 0:
                result.add(item_id)
    return sorted(result)


def add_grouped_rows(
    sources: dict[int, list[dict[str, Any]]],
    kind: str,
    prefix: str,
    rows: list[list[str]],
    unit: str,
) -> None:
    for fields in rows:
        if len(fields) != 3:
            raise AcquisitionError(f"unexpected acquisition row: {fields!r}")
        item_id = int(fields[0])
        count = int(fields[1])
        names = first_names(fields[2], count, unit)
        if names:
            sources[item_id].append({
                "kind": kind,
                "priority": KIND_PRIORITY[kind],
                "text": f"{prefix}：{names}",
                "count": count,
            })


def collect_creature_loot(mysql: Path, config: Path, item_ids: list[int], sources: dict[int, list[dict[str, Any]]]) -> None:
    for batch in chunks(item_ids, 800):
        ids = in_list(batch)
        direct = f"""
SET SESSION group_concat_max_len=8192;
SELECT clt.Item, COUNT(DISTINCT ct.entry),
       SUBSTRING_INDEX(GROUP_CONCAT(DISTINCT CONCAT(COALESCE(NULLIF(ctl.Name,''), ct.name), '{TOKEN_SEPARATOR}', COALESCE(spawn.map, -1)) ORDER BY ct.rank DESC, ct.entry SEPARATOR '；'), '；', 4)
FROM creature_loot_template clt
JOIN creature_template ct ON ct.lootid = clt.Entry
LEFT JOIN (SELECT id, MIN(map) AS map FROM creature GROUP BY id) spawn ON spawn.id = ct.entry
LEFT JOIN creature_template_locale ctl ON ctl.entry = ct.entry AND ctl.locale = 'zhCN'
WHERE clt.Item IN ({ids})
GROUP BY clt.Item
"""
        add_grouped_rows(sources, "drop", "掉落", mysql_rows(mysql, config, direct), "NPC")
        reference = f"""
SET SESSION group_concat_max_len=8192;
SELECT rlt.Item, COUNT(DISTINCT ct.entry),
       SUBSTRING_INDEX(GROUP_CONCAT(DISTINCT CONCAT(COALESCE(NULLIF(ctl.Name,''), ct.name), '{TOKEN_SEPARATOR}', COALESCE(spawn.map, -1)) ORDER BY ct.rank DESC, ct.entry SEPARATOR '；'), '；', 4)
FROM reference_loot_template rlt
JOIN creature_loot_template clt ON clt.Reference = rlt.Entry
JOIN creature_template ct ON ct.lootid = clt.Entry
LEFT JOIN (SELECT id, MIN(map) AS map FROM creature GROUP BY id) spawn ON spawn.id = ct.entry
LEFT JOIN creature_template_locale ctl ON ctl.entry = ct.entry AND ctl.locale = 'zhCN'
WHERE rlt.Item IN ({ids})
GROUP BY rlt.Item
"""
        add_grouped_rows(sources, "drop", "掉落", mysql_rows(mysql, config, reference), "NPC")


def collect_vendors(mysql: Path, config: Path, item_ids: list[int], sources: dict[int, list[dict[str, Any]]]) -> None:
    for batch in chunks(item_ids, 800):
        ids = in_list(batch)
        query = f"""
SET SESSION group_concat_max_len=8192;
SELECT nv.item, COUNT(DISTINCT ct.entry),
       SUBSTRING_INDEX(GROUP_CONCAT(DISTINCT CONCAT(COALESCE(NULLIF(ctl.Name,''), ct.name), '{TOKEN_SEPARATOR}', COALESCE(spawn.map, -1)) ORDER BY ct.entry SEPARATOR '；'), '；', 4)
FROM npc_vendor nv
JOIN creature_template ct ON ct.entry = nv.entry
LEFT JOIN (SELECT id, MIN(map) AS map FROM creature GROUP BY id) spawn ON spawn.id = ct.entry
LEFT JOIN creature_template_locale ctl ON ctl.entry = ct.entry AND ctl.locale = 'zhCN'
WHERE nv.item IN ({ids})
GROUP BY nv.item
"""
        add_grouped_rows(sources, "vendor", "商人", mysql_rows(mysql, config, query), "商人")


def collect_quests(mysql: Path, config: Path, item_ids: list[int], sources: dict[int, list[dict[str, Any]]]) -> None:
    for batch in chunks(item_ids, 500):
        ids = in_list(batch)
        selects = []
        for column in REWARD_COLUMNS:
            selects.append(
                "SELECT qt.{column} AS itemId, qt.ID AS questId, "
                "COALESCE(NULLIF(qtl.Title,''), qt.LogTitle) AS questTitle "
                "FROM quest_template qt "
                "LEFT JOIN quest_template_locale qtl ON qtl.ID = qt.ID AND qtl.locale = 'zhCN' "
                "WHERE qt.{column} IN ({ids})".format(column=column, ids=ids)
            )
        query = f"""
SET SESSION group_concat_max_len=8192;
SELECT itemId, COUNT(DISTINCT questId),
       SUBSTRING_INDEX(GROUP_CONCAT(DISTINCT questTitle ORDER BY questId SEPARATOR '；'), '；', 4)
FROM (
{" UNION ALL ".join(selects)}
) q
WHERE itemId > 0
GROUP BY itemId
"""
        add_grouped_rows(sources, "quest", "任务", mysql_rows(mysql, config, query), "任务")


def collect_gameobjects(mysql: Path, config: Path, item_ids: list[int], sources: dict[int, list[dict[str, Any]]]) -> None:
    for batch in chunks(item_ids, 800):
        ids = in_list(batch)
        query = f"""
SET SESSION group_concat_max_len=8192;
SELECT glt.Item, COUNT(DISTINCT gt.entry),
       SUBSTRING_INDEX(GROUP_CONCAT(DISTINCT CONCAT(COALESCE(NULLIF(gtl.name,''), gt.name), '{TOKEN_SEPARATOR}', COALESCE(spawn.map, -1)) ORDER BY gt.entry SEPARATOR '；'), '；', 4)
FROM gameobject_loot_template glt
JOIN gameobject_template gt ON gt.Data1 = glt.Entry
LEFT JOIN (SELECT id, MIN(map) AS map FROM gameobject GROUP BY id) spawn ON spawn.id = gt.entry
LEFT JOIN gameobject_template_locale gtl ON gtl.entry = gt.entry AND gtl.locale = 'zhCN'
WHERE glt.Item IN ({ids})
GROUP BY glt.Item
"""
        add_grouped_rows(sources, "gameobject", "宝箱/物体", mysql_rows(mysql, config, query), "物体")


def collect_containers(mysql: Path, config: Path, item_ids: list[int], sources: dict[int, list[dict[str, Any]]]) -> None:
    for batch in chunks(item_ids, 800):
        ids = in_list(batch)
        query = f"""
SET SESSION group_concat_max_len=8192;
SELECT ilt.Item, COUNT(DISTINCT it.entry),
       SUBSTRING_INDEX(GROUP_CONCAT(DISTINCT COALESCE(NULLIF(itl.Name,''), it.name) ORDER BY it.entry SEPARATOR '；'), '；', 4)
FROM item_loot_template ilt
JOIN item_template it ON it.entry = ilt.Entry
LEFT JOIN item_template_locale itl ON itl.ID = it.entry AND itl.locale = 'zhCN'
WHERE ilt.Item IN ({ids})
GROUP BY ilt.Item
"""
        add_grouped_rows(sources, "container", "容器", mysql_rows(mysql, config, query), "容器")


def collect_crafted(mysql: Path, config: Path, item_ids: list[int], sources: dict[int, list[dict[str, Any]]]) -> None:
    skills = ",".join(str(value) for value in sorted(CRAFT_SKILL_LINES))
    for batch in chunks(item_ids, 500):
        ids = in_list(batch)
        selects = []
        for index in (1, 2, 3):
            selects.append(
                "SELECT s.EffectItemType_{index} AS itemId, sla.SkillLine AS skillId, "
                "COALESCE(NULLIF(sl.DisplayName_Lang_zhCN,''), sl.DisplayName_Lang_enUS, "
                "NULLIF(s.Name_Lang_zhCN,''), s.Name_Lang_enUS) AS skillName "
                "FROM spell_dbc s "
                "JOIN skilllineability_dbc sla ON sla.Spell = s.ID "
                "LEFT JOIN skillline_dbc sl ON sl.ID = sla.SkillLine "
                "WHERE s.EffectItemType_{index} IN ({ids}) AND sla.SkillLine IN ({skills})".format(
                    index=index, ids=ids, skills=skills
                )
            )
        query = f"""
SET SESSION group_concat_max_len=8192;
SELECT itemId, COUNT(DISTINCT skillId),
       SUBSTRING_INDEX(GROUP_CONCAT(DISTINCT skillName ORDER BY skillId SEPARATOR '；'), '；', 4)
FROM (
{" UNION ALL ".join(selects)}
) crafted
WHERE itemId > 0
GROUP BY itemId
"""
        add_grouped_rows(sources, "crafted", "专业制造", mysql_rows(mysql, config, query), "专业")


def choose_source(candidates: list[dict[str, Any]]) -> dict[str, Any] | None:
    if not candidates:
        return None
    candidates = sorted(candidates, key=lambda row: (row["priority"], row["count"], row["text"]))
    winner = dict(candidates[0])
    other_kinds = []
    seen = {winner["kind"]}
    for candidate in candidates[1:]:
        if candidate["kind"] not in seen:
            other_kinds.append(candidate["text"].split("：", 1)[0])
            seen.add(candidate["kind"])
    if other_kinds:
        winner["also"] = other_kinds[:3]
    return winner


def lua_string(value: str) -> str:
    return json.dumps(value, ensure_ascii=False)


def render_lua(item_sources: dict[int, dict[str, Any]], coverage: dict[str, Any]) -> str:
    lines = [
        "-- Generated by tools/catalog/appearance_acquisition_sources.py. Do not edit.",
        "SoloCollections.GeneratedWardrobeAcquisitionSources = {",
        "    schemaVersion = 1,",
        f"    sourceItemCount = {coverage['sourceItemCount']},",
        f"    mappedItemCount = {coverage['mappedItemCount']},",
        "    itemSources = {",
    ]
    for item_id in sorted(item_sources):
        source = item_sources[item_id]
        also = source.get("also") or []
        also_lua = "{}" if not also else "{ " + ", ".join(lua_string(value) for value in also) + " }"
        lines.append(
            "        [%d] = { kind = %s, text = %s, count = %d, also = %s },"
            % (item_id, lua_string(source["kind"]), lua_string(source["text"]), int(source["count"]), also_lua)
        )
    lines += ["    }", "}", ""]
    return "\n".join(lines)


def pretty_json(value: Any) -> str:
    return json.dumps(value, ensure_ascii=False, sort_keys=True, indent=2) + "\n"


def build(repo: Path, mysql: Path, config: Path) -> tuple[dict[str, Any], str]:
    item_ids = source_item_ids(repo)
    require(item_ids, "no public appearance source items found")
    sources: dict[int, list[dict[str, Any]]] = defaultdict(list)
    collect_quests(mysql, config, item_ids, sources)
    collect_vendors(mysql, config, item_ids, sources)
    collect_creature_loot(mysql, config, item_ids, sources)
    collect_gameobjects(mysql, config, item_ids, sources)
    collect_containers(mysql, config, item_ids, sources)
    collect_crafted(mysql, config, item_ids, sources)

    item_sources: dict[int, dict[str, Any]] = {}
    for item_id in item_ids:
        chosen = choose_source(sources.get(item_id, []))
        if chosen:
            item_sources[item_id] = chosen
    coverage = {
        "schemaVersion": 1,
        "sourceItemCount": len(item_ids),
        "mappedItemCount": len(item_sources),
        "unmappedItemCount": len(item_ids) - len(item_sources),
    }
    report = dict(coverage)
    report["itemSources"] = item_sources
    return report, render_lua(item_sources, coverage)


def write_or_check(path: Path, content: str, check: bool) -> None:
    if check:
        require(path.is_file() and path.read_text(encoding="utf-8") == content, f"generated output drift: {path}")
        return
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(content, encoding="utf-8", newline="\n")


def main(argv: list[str] | None = None) -> int:
    repo = Path(__file__).resolve().parents[2]
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("command", choices=("extract", "check"))
    parser.add_argument("--mysql", type=Path, required=True, help="Path to the MySQL client executable")
    parser.add_argument("--config", type=Path, required=True, help="Path to a local AzerothCore worldserver.conf")
    args = parser.parse_args(argv)
    try:
        report, lua = build(repo, args.mysql, args.config)
        check = args.command == "check"
        write_or_check(repo / "catalog/generated/appearance-acquisition-sources.json", pretty_json(report), check)
        write_or_check(
            repo / "addon/SoloCollections_WardrobeData/Data/Generated/WardrobeAcquisitionSources.lua",
            lua,
            check,
        )
        print(
            "appearance acquisition sources: "
            f"mapped={report['mappedItemCount']} unmapped={report['unmappedItemCount']} "
            f"sourceItems={report['sourceItemCount']}"
        )
        return 0
    except (OSError, AcquisitionError) as exc:
        print(f"appearance acquisition source error: {exc}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
