#!/usr/bin/env python3
"""Read the reviewed, model-scoped weapon-camera override contract.

The client workbench deliberately writes SavedVariables as a player-local
experiment.  This module is the narrow promotion boundary: only a reviewed
JSON source with an explicit model signature, fixed input/output M2 hashes,
and a bounded appearance set can become a generated default.
"""

from __future__ import annotations

import hashlib
import json
import math
import re
from pathlib import Path
from typing import Any


SHA256_RE = re.compile(r"^[a-f0-9]{64}$")
MODEL_SIGNATURE_RE = re.compile(r"^m2:[a-f0-9]{64}$")
CAMERA_STRATEGY = "VERTEX_MESH_BOUNDS_CAMERA"


class ModelCameraOverrideError(RuntimeError):
    """Raised when a promoted camera override is not safe to consume."""


def _require(value: bool, message: str) -> None:
    if not value:
        raise ModelCameraOverrideError(message)


def sha_path(path: Path) -> str:
    digest = hashlib.sha256()
    try:
        with path.open("rb") as handle:
            for chunk in iter(lambda: handle.read(1024 * 1024), b""):
                digest.update(chunk)
    except OSError as exc:
        raise ModelCameraOverrideError(f"cannot hash model camera override source {path}: {exc}") from exc
    return digest.hexdigest()


def _read_json(path: Path) -> Any:
    try:
        return json.loads(path.read_text(encoding="utf-8-sig"))
    except (OSError, UnicodeDecodeError, json.JSONDecodeError) as exc:
        raise ModelCameraOverrideError(f"cannot read model camera override source {path}: {exc}") from exc


def _valid_hash(value: Any) -> bool:
    return isinstance(value, str) and SHA256_RE.fullmatch(value) is not None


def normalize_pose(value: Any) -> dict[str, Any]:
    _require(isinstance(value, dict), "model camera override pose is missing")
    fields = ("yaw", "pitch", "roll", "distanceScale")
    _require(all(isinstance(value.get(field), (int, float)) for field in fields),
             "model camera override pose is incomplete")
    target = value.get("target")
    _require(isinstance(target, dict)
             and all(isinstance(target.get(field), (int, float)) for field in ("x", "y", "z")),
             "model camera override target is incomplete")
    normalized = {
        "yaw": float(value["yaw"]),
        "pitch": float(value["pitch"]),
        "roll": float(value["roll"]),
        "distanceScale": float(value["distanceScale"]),
        "target": {field: float(target[field]) for field in ("x", "y", "z")},
    }
    _require(all(math.isfinite(component) for component in (
        normalized["yaw"], normalized["pitch"], normalized["roll"], normalized["distanceScale"],
        normalized["target"]["x"], normalized["target"]["y"], normalized["target"]["z"],
    )), "model camera override pose must be finite")
    _require(normalized["distanceScale"] > 0, "model camera override distance scale must be positive")
    return normalized


def load_model_camera_overrides(path: Path) -> dict[str, Any]:
    """Return the normalized source plus its content hash, keyed by signature."""

    path = path.resolve()
    _require(path.is_file(), f"model camera override source is missing: {path}")
    source = _read_json(path)
    _require(isinstance(source, dict), "model camera override source must be an object")
    _require(source.get("schemaVersion") == 1, "unsupported model camera override schema")
    _require(source.get("kind") == "SoloCollectionsWeaponModelCameraOverrides",
             "model camera override kind drift")
    rows = source.get("overrides")
    _require(isinstance(rows, list), "model camera override list is missing")
    overrides: dict[str, dict[str, Any]] = {}
    for raw in rows:
        _require(isinstance(raw, dict), "model camera override row is not an object")
        signature = raw.get("modelSignature")
        _require(raw.get("scope") == "model"
                 and isinstance(signature, str)
                 and MODEL_SIGNATURE_RE.fullmatch(signature) is not None,
                 "model camera override must use a valid model signature")
        _require(signature not in overrides, f"duplicate model camera override: {signature}")
        appearance_ids = raw.get("expectedAppearanceIds")
        _require(isinstance(appearance_ids, list) and appearance_ids,
                 f"model camera override has no expected appearances: {signature}")
        normalized_ids = sorted({int(value) for value in appearance_ids})
        _require(all(value > 0 for value in normalized_ids)
                 and len(normalized_ids) == len(appearance_ids),
                 f"model camera override has invalid expected appearances: {signature}")
        _require(int(raw.get("expectedAppearanceCount", 0)) == len(normalized_ids),
                 f"model camera override appearance count drift: {signature}")
        _require(raw.get("cameraStrategy") == CAMERA_STRATEGY,
                 f"unsupported model camera strategy: {signature}")
        _require(isinstance(raw.get("reasonCode"), str) and raw["reasonCode"],
                 f"model camera override reason is missing: {signature}")
        for field in ("expectedInputM2Sha256", "expectedOutputM2Sha256", "workbenchExportSha256"):
            _require(_valid_hash(raw.get(field)), f"model camera override has invalid {field}: {signature}")
        overrides[signature] = {
            "scope": "model",
            "modelSignature": signature,
            "expectedAppearanceIds": normalized_ids,
            "expectedAppearanceCount": len(normalized_ids),
            "expectedInputM2Sha256": str(raw["expectedInputM2Sha256"]),
            "expectedOutputM2Sha256": str(raw["expectedOutputM2Sha256"]),
            "cameraStrategy": CAMERA_STRATEGY,
            "reasonCode": str(raw["reasonCode"]),
            "presentationPose": normalize_pose(raw.get("presentationPose")),
            "workbenchExportSha256": str(raw["workbenchExportSha256"]),
        }
    return {
        "path": path,
        "sha256": sha_path(path),
        "overrides": overrides,
    }
