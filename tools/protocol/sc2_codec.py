#!/usr/bin/env python3
"""Strict reference codec for the SoloCollections SC2 v1 wire protocol."""

from __future__ import annotations

import re
from collections.abc import Callable, Iterable
from typing import Any


PREFIX = "SC2"
PROTOCOL_VERSION = 1
CORE_MESSAGE_LIMIT_BYTES = 255
MAX_BODY_BYTES = 240
MAX_TOKEN_BYTES = 64
MAX_CHUNK_PAYLOAD_BYTES = 160
MAX_SNAPSHOT_BYTES = 32768
MAX_SNAPSHOT_CHUNKS = 256
UINT32_MAX = 4_294_967_295
UINT64_MAX = 18_446_744_073_709_551_615

TOKEN_RE = re.compile(rf"^[A-Za-z0-9._~-]{{1,{MAX_TOKEN_BYTES}}}$")
NONCE_RE = re.compile(r"^[0-9a-f]{16}$")
HASH_RE = re.compile(r"^[0-9a-f]{64}$")
CHECKSUM_RE = re.compile(r"^[0-9a-f]{8}$")
FLAGS_RE = re.compile(r"^[0-9a-f]{8}$")
CHUNK_RE = re.compile(r"^[-0-9a-z,]{1,160}$")
ACTION_RE = re.compile(r"^[A-Z][A-Z0-9_]{0,31}$")

ACTION_STATUSES = {
    "ACCEPTED",
    "DISMISSED",
    "LOADING",
    "NOT_OWNED",
    "CATALOG_MISMATCH",
    "ASSET_MISMATCH",
    "UNKNOWN_IDENTITY",
    "CLASS_RESTRICTED",
    "RACE_RESTRICTED",
    "SKILL_REQUIRED",
    "INVALID_TARGET_SLOT",
    "DB_UNAVAILABLE",
    "RATE_LIMITED",
    "INVALID_REQUEST",
    "UNSUPPORTED",
    "IN_COMBAT",
    "DEAD",
    "IN_VEHICLE",
    "ON_TAXI",
    "INDOORS",
    "FLYING_NOT_ALLOWED",
    "MAP_RESTRICTED",
    "BATTLEGROUND_RESTRICTED",
    "SHAPESHIFT_RESTRICTED",
    "CAST_FAILED",
}

RESYNC_REASONS = {
    "CLIENT_REQUEST",
    "REVISION_GAP",
    "CHECKSUM_MISMATCH",
    "CATALOG_MISMATCH",
    "TRANSFER_TIMEOUT",
}

ERROR_REASONS = {
    "BAD_MESSAGE",
    "BAD_NONCE",
    "RATE_LIMITED",
    "LOADING",
    "UNSUPPORTED_VERSION",
    "REPLAYED_REQUEST",
    "SNAPSHOT_TOO_LARGE",
    "DB_UNAVAILABLE",
}


class ProtocolError(ValueError):
    pass


def _require(condition: bool, message: str) -> None:
    if not condition:
        raise ProtocolError(message)


def _uint(value: Any, name: str, minimum: int, maximum: int) -> int:
    _require(type(value) is int, f"{name} must be an integer")
    _require(minimum <= value <= maximum, f"{name} is out of range")
    return value


def _parse_uint(text: str, name: str, minimum: int, maximum: int) -> int:
    _require(bool(re.fullmatch(r"0|[1-9][0-9]*", text)), f"{name} is not canonical decimal")
    _require(len(text) <= len(str(maximum)), f"{name} is too long")
    return _uint(int(text), name, minimum, maximum)


def _match(value: Any, name: str, pattern: re.Pattern[str]) -> str:
    _require(isinstance(value, str) and bool(pattern.fullmatch(value)), f"invalid {name}")
    return value


def _enum(value: Any, name: str, allowed: set[str]) -> str:
    _require(isinstance(value, str) and value in allowed, f"invalid {name}")
    return value


def _target(value: Any) -> str:
    if value == "-":
        return "-"
    return str(_uint(value, "target", 0, UINT32_MAX))


def _parse_target(text: str) -> int | str:
    return "-" if text == "-" else _parse_uint(text, "target", 0, UINT32_MAX)


def adler32_hex(payload: str) -> str:
    _require(isinstance(payload, str), "payload must be text")
    try:
        encoded = payload.encode("ascii")
    except UnicodeEncodeError as exc:
        raise ProtocolError("payload must be ASCII") from exc
    first = 1
    second = 0
    for byte in encoded:
        first = (first + byte) % 65521
        second = (second + first) % 65521
    return f"{((second << 16) | first):08x}"


def to_base36(value: int) -> str:
    value = _uint(value, "collectionId", 0, UINT32_MAX)
    alphabet = "0123456789abcdefghijklmnopqrstuvwxyz"
    if value == 0:
        return "0"
    digits: list[str] = []
    while value:
        value, remainder = divmod(value, 36)
        digits.append(alphabet[remainder])
    return "".join(reversed(digits))


def canonical_owned_payload(collection_ids: Iterable[int]) -> str:
    values = sorted(set(collection_ids))
    return ",".join(to_base36(value) for value in values) if values else "-"


def chunk_payload(payload: str) -> list[str]:
    _match(payload, "snapshot payload", re.compile(r"^-$|^[0-9a-z,]+$"))
    _require(len(payload.encode("ascii")) <= MAX_SNAPSHOT_BYTES, "snapshot payload is too large")
    chunks = [payload[index:index + MAX_CHUNK_PAYLOAD_BYTES] for index in range(0, len(payload), MAX_CHUNK_PAYLOAD_BYTES)]
    _require(0 < len(chunks) <= MAX_SNAPSHOT_CHUNKS, "snapshot has too many chunks")
    return chunks


def _render(message: dict[str, Any]) -> tuple[str, list[str]]:
    kind = message.get("kind")
    _require(isinstance(kind, str), "message kind is required")
    nonce = lambda: _match(message.get("sessionNonce"), "sessionNonce", NONCE_RE)
    type_id = lambda minimum=1: str(_uint(message.get("typeId"), "typeId", minimum, 65535))
    revision = lambda name="revision": str(_uint(message.get(name), name, 0, UINT64_MAX))
    request_id = lambda: str(_uint(message.get("requestId"), "requestId", 1, UINT32_MAX))
    transfer_id = lambda: str(_uint(message.get("transferId"), "transferId", 1, UINT32_MAX))

    if kind == "HELLO":
        return "H", [
            str(_uint(message.get("protocolVersion"), "protocolVersion", 1, 999)),
            _match(message.get("clientNonce"), "clientNonce", NONCE_RE),
            _match(message.get("clientBuild"), "clientBuild", TOKEN_RE),
            _match(message.get("metadataVersion"), "metadataVersion", TOKEN_RE),
            _match(message.get("assetPackVersion"), "assetPackVersion", TOKEN_RE),
        ]
    if kind == "HELLO_ACK":
        return "A", [
            str(_uint(message.get("protocolVersion"), "protocolVersion", 1, 999)), nonce(),
            revision("accountRevision"), _match(message.get("enabledCategoryFlags"), "enabledCategoryFlags", FLAGS_RE),
            _match(message.get("metadataVersion"), "metadataVersion", TOKEN_RE),
            _match(message.get("assetPackVersion"), "assetPackVersion", TOKEN_RE),
            _match(message.get("backendBuild"), "backendBuild", TOKEN_RE),
            str(_uint(message.get("categoryCount"), "categoryCount", 0, 255)),
        ]
    if kind == "CATEGORY_MAP":
        return "M", [nonce(), type_id(), _match(message.get("mappingHash"), "mappingHash", HASH_RE)]
    if kind == "SNAPSHOT_BEGIN":
        return "B", [
            nonce(), transfer_id(), type_id(),
            str(_uint(message.get("total"), "total", 1, MAX_SNAPSHOT_CHUNKS)),
            revision("baseRevision"), _match(message.get("checksum"), "checksum", CHECKSUM_RE),
            str(_uint(message.get("payloadBytes"), "payloadBytes", 1, MAX_SNAPSHOT_BYTES)),
        ]
    if kind == "SNAPSHOT_CHUNK":
        return "C", [
            nonce(), transfer_id(), str(_uint(message.get("seq"), "seq", 1, MAX_SNAPSHOT_CHUNKS)),
            _match(message.get("payload"), "chunk payload", CHUNK_RE),
        ]
    if kind == "SNAPSHOT_END":
        return "E", [nonce(), transfer_id(), _match(message.get("checksum"), "checksum", CHECKSUM_RE)]
    if kind == "DELTA":
        return "D", [
            nonce(), type_id(), revision(), _enum(message.get("operation"), "operation", {"A", "R"}),
            str(_uint(message.get("collectionId"), "collectionId", 1, UINT32_MAX)),
        ]
    if kind == "ACTION_REQUEST":
        return "Q", [
            nonce(), request_id(), type_id(),
            str(_uint(message.get("collectionId"), "collectionId", 1, UINT32_MAX)),
            _match(message.get("actionId"), "actionId", ACTION_RE), _target(message.get("target")),
        ]
    if kind == "ACTION_RESULT":
        return "R", [
            nonce(), request_id(), _enum(message.get("status"), "status", ACTION_STATUSES), type_id(),
            str(_uint(message.get("collectionId"), "collectionId", 1, UINT32_MAX)), revision(),
        ]
    if kind == "RESYNC":
        return "S", [
            nonce(), _enum(message.get("reason"), "reason", RESYNC_REASONS), type_id(0), revision(),
        ]
    if kind == "ERROR":
        return "X", [nonce(), str(_uint(message.get("requestId"), "requestId", 0, UINT32_MAX)), _enum(message.get("reason"), "reason", ERROR_REASONS)]
    raise ProtocolError(f"unknown message kind: {kind!r}")


def encode(message: dict[str, Any]) -> str:
    code, fields = _render(message)
    packet = "|".join([code, *fields])
    try:
        size = len(packet.encode("ascii"))
    except UnicodeEncodeError as exc:
        raise ProtocolError("packet must be ASCII") from exc
    _require(size <= MAX_BODY_BYTES, "packet exceeds SC2 body limit")
    return packet


def _decode_fields(code: str, fields: list[str]) -> dict[str, Any]:
    def exact(count: int) -> None:
        _require(len(fields) == count, f"{code} expects {count} fields")

    nonce = lambda index=0: _match(fields[index], "sessionNonce", NONCE_RE)
    token = lambda index, name: _match(fields[index], name, TOKEN_RE)
    uint = lambda index, name, minimum, maximum: _parse_uint(fields[index], name, minimum, maximum)

    if code == "H":
        exact(5)
        return {"kind": "HELLO", "protocolVersion": uint(0, "protocolVersion", 1, 999), "clientNonce": _match(fields[1], "clientNonce", NONCE_RE), "clientBuild": token(2, "clientBuild"), "metadataVersion": token(3, "metadataVersion"), "assetPackVersion": token(4, "assetPackVersion")}
    if code == "A":
        exact(8)
        return {"kind": "HELLO_ACK", "protocolVersion": uint(0, "protocolVersion", 1, 999), "sessionNonce": nonce(1), "accountRevision": uint(2, "accountRevision", 0, UINT64_MAX), "enabledCategoryFlags": _match(fields[3], "enabledCategoryFlags", FLAGS_RE), "metadataVersion": token(4, "metadataVersion"), "assetPackVersion": token(5, "assetPackVersion"), "backendBuild": token(6, "backendBuild"), "categoryCount": uint(7, "categoryCount", 0, 255)}
    if code == "M":
        exact(3)
        return {"kind": "CATEGORY_MAP", "sessionNonce": nonce(), "typeId": uint(1, "typeId", 1, 65535), "mappingHash": _match(fields[2], "mappingHash", HASH_RE)}
    if code == "B":
        exact(7)
        return {"kind": "SNAPSHOT_BEGIN", "sessionNonce": nonce(), "transferId": uint(1, "transferId", 1, UINT32_MAX), "typeId": uint(2, "typeId", 1, 65535), "total": uint(3, "total", 1, MAX_SNAPSHOT_CHUNKS), "baseRevision": uint(4, "baseRevision", 0, UINT64_MAX), "checksum": _match(fields[5], "checksum", CHECKSUM_RE), "payloadBytes": uint(6, "payloadBytes", 1, MAX_SNAPSHOT_BYTES)}
    if code == "C":
        exact(4)
        return {"kind": "SNAPSHOT_CHUNK", "sessionNonce": nonce(), "transferId": uint(1, "transferId", 1, UINT32_MAX), "seq": uint(2, "seq", 1, MAX_SNAPSHOT_CHUNKS), "payload": _match(fields[3], "chunk payload", CHUNK_RE)}
    if code == "E":
        exact(3)
        return {"kind": "SNAPSHOT_END", "sessionNonce": nonce(), "transferId": uint(1, "transferId", 1, UINT32_MAX), "checksum": _match(fields[2], "checksum", CHECKSUM_RE)}
    if code == "D":
        exact(5)
        return {"kind": "DELTA", "sessionNonce": nonce(), "typeId": uint(1, "typeId", 1, 65535), "revision": uint(2, "revision", 0, UINT64_MAX), "operation": _enum(fields[3], "operation", {"A", "R"}), "collectionId": uint(4, "collectionId", 1, UINT32_MAX)}
    if code == "Q":
        exact(6)
        return {"kind": "ACTION_REQUEST", "sessionNonce": nonce(), "requestId": uint(1, "requestId", 1, UINT32_MAX), "typeId": uint(2, "typeId", 1, 65535), "collectionId": uint(3, "collectionId", 1, UINT32_MAX), "actionId": _match(fields[4], "actionId", ACTION_RE), "target": _parse_target(fields[5])}
    if code == "R":
        exact(6)
        return {"kind": "ACTION_RESULT", "sessionNonce": nonce(), "requestId": uint(1, "requestId", 1, UINT32_MAX), "status": _enum(fields[2], "status", ACTION_STATUSES), "typeId": uint(3, "typeId", 1, 65535), "collectionId": uint(4, "collectionId", 1, UINT32_MAX), "revision": uint(5, "revision", 0, UINT64_MAX)}
    if code == "S":
        exact(4)
        return {"kind": "RESYNC", "sessionNonce": nonce(), "reason": _enum(fields[1], "reason", RESYNC_REASONS), "typeId": uint(2, "typeId", 0, 65535), "revision": uint(3, "revision", 0, UINT64_MAX)}
    if code == "X":
        exact(3)
        return {"kind": "ERROR", "sessionNonce": nonce(), "requestId": uint(1, "requestId", 0, UINT32_MAX), "reason": _enum(fields[2], "reason", ERROR_REASONS)}
    raise ProtocolError(f"unknown message code: {code!r}")


def decode(packet: str) -> dict[str, Any]:
    _require(isinstance(packet, str), "packet must be text")
    try:
        size = len(packet.encode("ascii"))
    except UnicodeEncodeError as exc:
        raise ProtocolError("packet must be ASCII") from exc
    _require(0 < size <= MAX_BODY_BYTES, "packet exceeds SC2 body limit")
    parts = packet.split("|")
    _require(parts and len(parts[0]) == 1, "invalid message code")
    message = _decode_fields(parts[0], parts[1:])
    _require(encode(message) == packet, "packet is not canonical")
    return message
