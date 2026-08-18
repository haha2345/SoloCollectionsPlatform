from __future__ import annotations

import hashlib
import json
import re
from pathlib import Path


ROOT = Path(__file__).resolve().parents[3]
ADDON = ROOT / "addon" / "SoloCollections"
SERVER_LUA = ROOT / "server" / "ale" / "solo_collections.lua"
TOOLS = ROOT / "tools" / "collections"


def read_text(path: Path) -> str:
    return path.read_text(encoding="utf-8-sig")


def lua_files() -> list[Path]:
    if not ADDON.exists():
        return []
    return sorted(ADDON.rglob("*.lua"))


def all_lua_text() -> str:
    return "\n".join(read_text(path) for path in lua_files())


def parse_lua_records(path: Path) -> list[str]:
    """Return top-level one-line demo records written as `{ id = ... }`."""
    text = read_text(path)
    return re.findall(r"(?m)^\s*\{\s*id\s*=.*?\}\s*,?\s*$", text)


def extract_int(record: str, field: str) -> int | None:
    match = re.search(rf"\b{re.escape(field)}\s*=\s*(\d+)", record)
    return int(match.group(1)) if match else None


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest().upper()


def load_json(path: Path):
    return json.loads(read_text(path))
