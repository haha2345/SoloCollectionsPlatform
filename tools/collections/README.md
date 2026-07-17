# SoloCollections Phase 1 tooling

This directory contains contract tests, catalog verification, safe deployment, and source/live hash verification for the standalone WoW 3.3.5a `SoloCollections` AddOn.

Run all contracts with:

```powershell
python -m unittest discover -s tools\collections\tests -p "test_*.py" -v
```

Current architecture documentation lives under `docs/architecture`; preserved
historical plans live under `docs/history` and may contain obsolete paths.

## WotLK M2 camera research tool

`m2_camera_patch.py` appends a camera to a version-264 `MD20` model without
relocating existing M2 data. It is an offline format-research tool, not a
supported player-model deployment tool.

**Do not deploy a third camera to a playable character M2.** Runtime testing on
the 3.3.5 client produced deterministic `ERROR #132` access violations while
loading HumanFemale.m2, even though independent parsers accepted the appended
array. Player-model inputs are therefore blocked unless the explicitly unsafe
offline-research flag is supplied.

The patcher accepts only the known two-camera WotLK layout with lookup
`[0, 1]`; already-patched or structurally different models fail closed.
