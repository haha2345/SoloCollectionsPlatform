# Using the SoloCollections v0.2.0 release

[中文](RELEASE_USAGE.zh-CN.md) ·
[Full installation and rollback](INSTALLATION.en.md) ·
[Server module](https://github.com/haha2345/mod-solo-collections)

`v0.2.0` is the first public source release built around the separate
`mod-solo-collections` C++/SC2 authoritative backend. Do not mix it with the
ALE/SC1 bridge, catalog, or client patches from `v0.1.0`.

## Which file to download

| File | Purpose |
| --- | --- |
| `SoloCollections-v0.2.0-unified-source.zip` | Recommended; includes the AddOn, module source, manifests, bilingual instructions, and licenses |
| `SoloCollections-v0.2.0-addon.zip` | Runtime WoW AddOn only |
| `mod-solo-collections-v0.2.0-source.zip` | Module source to place in and compile with AzerothCore |
| `release-manifest.json` | Exact AddOn, module, AzerothCore, SC2, catalog, and SQL versions |
| `RELEASE_SHA256SUMS.txt` | Checksums for the public download assets |

GitHub's automatically generated source archives are useful for development.
Most installers should start with `unified-source.zip`.

## What is not included

The release contains no `Wow.exe`, patched executable, DLL, MPQ, DBC, DB2,
M2, SKIN, BLP, WDB, database dump, credential, or client-extracted media.
The AddOn's base UI media is project-authored. SoloCam and standalone weapon
resources are optional local builds, not prerequisites for collection state
or the base UI.

## 1. Verify the download

Place `RELEASE_SHA256SUMS.txt` beside the downloaded assets and run:

```powershell
Get-FileHash .\SoloCollections-v0.2.0-unified-source.zip -Algorithm SHA256
Get-Content .\RELEASE_SHA256SUMS.txt
```

The value must match the corresponding line. After extracting the unified
archive, use its `SHA256SUMS.txt` to verify the files inside it.

## 2. Install and build the server module

Stop `worldserver` and back up the auth, characters, and world databases,
module configuration, and current server files. Extract:

```text
mod-solo-collections-v0.2.0-source.zip
```

so that this path exists:

```text
<AzerothCore source>/modules/mod-solo-collections/include.sh
```

Re-run CMake and compile the module with AzerothCore:

```powershell
cmake -S <AzerothCore> -B <AzerothCore-build> `
  -G "Visual Studio 17 2022" -A x64 `
  -DMODULES=static `
  -DCMAKE_INSTALL_PREFIX=<AzerothCore-runtime>

cmake --build <AzerothCore-build> --config RelWithDebInfo `
  --target authserver worldserver
```

`include.sh` registers the module's SQL. A new characters database uses the
schema snapshot; an existing database uses the append-only migration. Do not
manually apply both to the same database.

Copy the installed `transmog.conf.dist` to the runtime `transmog.conf` and
confirm:

```ini
SoloCollections.Backend = Cpp
SoloCollections.Preview.Enabled = 1
```

`Compare` is migration-only and `Lua` is legacy ownership. Never run ALE/SC1
and C++/SC2 as parallel production writers.

## 3. Install the AddOn

Extract `SoloCollections-v0.2.0-addon.zip` and copy its `SoloCollections`
directory to:

```text
<WoW>/Interface/AddOns/SoloCollections/
```

The final path must contain:

```text
<WoW>/Interface/AddOns/SoloCollections/SoloCollections.toc
```

Enable `Solo Collections` at the character-selection screen. The AddOn has no
compile step.

## 4. Verify the first startup

Start the newly built `worldserver` and require:

```text
event=startup_versions
event=build_info
event=schema_check result=ready
event=provider_registry result=ready
```

Run this as an in-game administrator:

```text
.solocollections status
```

Confirm `Cpp` ownership, ready schema/providers, a completed SC2 handshake,
and fail-closed behavior for metadata, asset-token, or mapping-hash mismatch.
Open all five collection pages, then check one `/reload` and one relog.

## 5. Optional SoloCam

Collection state, synchronization, and most UI features work without SoloCam.
Local body framing and some standalone weapon previews use stock fallback or
show `UNAVAILABLE` when it is absent.

SoloCam only supports the original x86 WoW 3.3.5a build-12340 executable with
this SHA-256:

```text
AA63A5750D60EF16746C686B3D5E26876D98953EAB08B1C026CD0FAF78E88CB8
```

Stop if the hash differs. Build from the release-tag source and follow the
[SoloCam README](../client-extension/SoloCam/README.md) for copy, backup, and
rollback rules.

## 6. Upgrading from v0.1.0

Do not copy `v0.2.0` over a `v0.1.0` environment that still runs ALE/SC1:

1. record and back up the old AddOn, ALE script, same-name client files, and databases;
2. stop the old ALE/SC1 collection responder;
3. identify or restore old MPQ/DLL/patched-EXE files instead of deleting by name;
4. deploy the C++ module, SQL, configuration, and matching AddOn;
5. use `.solocollections status` to confirm that `Cpp` is the only production backend.

## 7. Known issue and contributions

Item-page framing is not uniform across every race, sex, HD/custom model, and
extreme-aspect weapon. This does not change server authority, but a model may
appear too close, too far away, offset, or clipped. Follow the
[camera contribution guide](CAMERA_CONTRIBUTIONS.md) and include the client
build/hash, target identity, before/after screenshots, and workbench JSONL.

See [INSTALLATION.en.md](INSTALLATION.en.md) for the complete environment,
database, acceptance, and rollback boundaries.
