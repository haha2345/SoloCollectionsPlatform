# Development guide

## Repository layout

```text
addon/SoloCollections/              WoW 3.3.5a AddOn
server/ale/solo_collections.lua     AzerothCore ALE bridge
client-extension/SoloCam/           Optional x86 client extension
tools/collections/                  Contract tests and deployment tools
docs/architecture/                  Current implementation notes
docs/history/                       Historical plans; paths may be obsolete
packaging/                          Release staging scripts and notes
```

Historical documents preserve old absolute paths as evidence. They are not
current commands. Current documentation and scripts use repository-relative
source paths and explicit deployment parameters.

## Recommended loop

```text
feature branch -> edit in repository -> automated tests -> deploy a copy
-> in-game acceptance -> fix in repository -> commit/PR
```

The game installation and server runtime are test targets, not source folders.
Use `git worktree` if two versions must be tested side by side.

## AddOn and server tests

Run from the repository root:

```powershell
$env:PYTHONDONTWRITEBYTECODE = '1'
python -m unittest discover -s tools\collections\tests -p "test_*.py" -v
```

Deployment scripts accept explicit absolute targets. Use `-WhatIf` first. They
copy files literally, preserve unrelated target files, and create backups when
an existing target would be replaced.

## SoloCam

SoloCam is optional and high-risk compared with the AddOn. It is a 32-bit DLL
and patch-copy proof of concept for one exact build-12340 executable. The
currently locked SHA-256 is:

```text
AA63A5750D60EF16746C686B3D5E26876D98953EAB08B1C026CD0FAF78E88CB8
```

Neither Git nor a release may contain `Wow.exe` or a patched game executable.
The user supplies a legally obtained client locally. Tests that inspect the
binary read `SOLOCOLLECTIONS_WOW_EXE`; if the variable is absent, those tests
are skipped.

```powershell
$env:SOLOCOLLECTIONS_WOW_EXE = 'D:\path\to\supported\Wow.exe'
python -m unittest discover -s client-extension\SoloCam\tests -p "test_*.py" -v
& .\client-extension\SoloCam\scripts\build.ps1
```

The build script accepts a Visual Studio environment path or attempts to find
Build Tools through `vswhere`. All generated files stay below the repository's
ignored `client-extension/SoloCam/build` directory.

## Release channels

1. Source: Git tags and repository history.
2. AddOn zip: installable `SoloCollections/` folder with audited placeholders.
3. SoloCam zip: project-built DLL/tooling only; no game binary.
4. Optional media overlay: externally hosted, versioned same-path files and a
   checksum manifest.

See [ASSETS.md](ASSETS.md) before creating any public archive.
