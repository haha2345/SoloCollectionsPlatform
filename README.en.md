# mod-solo-collections: AzerothCore backend for SoloCollections

[中文](README.md) ·
[Client AddOn](https://github.com/haha2345/SoloCollections) ·
[Configuration](docs/CONFIGURATION.md) ·
[Development](docs/DEVELOPMENT.md) ·
[Contributing](CONTRIBUTING.md)

`mod-solo-collections` is the authoritative AzerothCore WotLK C++ backend for
[SoloCollections](https://github.com/haha2345/SoloCollections). It owns
account collection state, database revisions, SC2 synchronization,
server-side authorization and actions, while retaining the adapted
`mod-transmog` feature set.

![SoloCollections wardrobe sets and dressing-room preview](https://raw.githubusercontent.com/haha2345/SoloCollections/main/docs/images/wardrobe-sets.png)

## Responsibilities

- mount, companion, toy, appearance, set, and title providers;
- account snapshots, incremental revisions, persistence, and audit rows;
- SC2 HELLO, chunked synchronization, resynchronization, and action results;
- mount/pet preview and summon, toy use, and appearance/set application;
- server-side unlock hooks for items, spells, quests, loot, and related paths;
- compatible transmogrification NPC, collection, and configuration support.

The client displays state and sends stable identities. It never authorizes
ownership or a server action.

## Matched repositories

| Repository | Contents | License |
| --- | --- | --- |
| [`SoloCollections`](https://github.com/haha2345/SoloCollections) | AddOn, canonical catalog, SC2 schema, generators, optional SoloCam | GPL-3.0-or-later |
| `mod-solo-collections` | Authoritative C++ backend, SQL, actions, generated server catalog | AGPL-3.0 |

A matched deployment records the AddOn, module, and AzerothCore commits plus
the metadata, asset-pack, mapping, presentation, and SC2 versions. Do not mix
generated catalogs from different source sets.

## Build environment

Follow the current
[AzerothCore Windows requirements](https://www.azerothcore.org/wiki/windows-requirements)
and [core installation guide](https://www.azerothcore.org/wiki/windows-core-installation).
The current official Windows baseline includes:

- Windows 10 or newer;
- Visual Studio 2022 with **Desktop development with C++**;
- CMake 3.27 or newer;
- Boost 1.78 or newer;
- MySQL 8.0 or newer (8.4 is recommended);
- OpenSSL 3.x;
- Git.

This module is compiled as part of AzerothCore; it does not produce a
standalone server. The client target is WoW 3.3.5a build 12340. See the
[client repository](https://github.com/haha2345/SoloCollections#readme) for
AddOn and optional SoloCam requirements.

## Quick installation and build

### 1. Install under the Core module directory

```powershell
git clone https://github.com/azerothcore/azerothcore-wotlk.git
git clone https://github.com/haha2345/mod-solo-collections.git `
  .\azerothcore-wotlk\modules\mod-solo-collections
```

The resulting path must contain:

```text
<AzerothCore>/modules/mod-solo-collections/include.sh
```

### 2. Generate matched build metadata

A clean checkout has an `UNPINNED` fallback for development builds. A
deployable build should generate exact commit and catalog hashes from the
matching AddOn checkout:

```powershell
& <SoloCollections>\tools\release\New-SoloCollectionsBuildInfo.ps1 `
  -AddonRoot <SoloCollections> `
  -ModuleRoot <AzerothCore>\modules\mod-solo-collections `
  -CoreRoot <AzerothCore> `
  -CoreBuildRoot <AzerothCore-build>
```

The ignored output is
`src/generated/SoloCollectionsBuildInfo.inc`. Do not commit personal build
metadata.

### 3. Configure and compile AzerothCore

Set:

```text
MODULES=static
CMAKE_INSTALL_PREFIX=<runtime directory>
```

Example Windows command line:

```powershell
cmake -S <AzerothCore> -B <AzerothCore-build> `
  -G "Visual Studio 17 2022" -A x64 `
  -DMODULES=static `
  -DCMAKE_INSTALL_PREFIX=<AzerothCore-runtime>

cmake --build <AzerothCore-build> --config RelWithDebInfo `
  --target authserver worldserver
```

Re-run CMake whenever the module set changes. Deploy the Core and module from
the same build; do not copy isolated object files between builds.

### 4. Database

Back up the auth, characters, and world databases first. `include.sh`
registers this module's SQL paths with the AzerothCore database updater:

- new characters database:
  `data/sql/db-characters/solo_collections_schema_v1.sql`;
- existing characters database:
  `data/sql/updates/char/2026_07_20_00_solo_collections_schema_v1.sql`;
- RBAC: `data/sql/db-auth/solo_collections_rbac.sql`;
- optional transmog NPC/text/items: `data/sql/db-world/`.

Do not manually import both the base schema and its migration. See the
[schema invariant](docs/schema/account-collections-v1.md).

### 5. Configure the runtime

Copy the installed `transmog.conf.dist` to the Core modules configuration
directory and use:

```ini
SoloCollections.Backend = Cpp
SoloCollections.Preview.Enabled = 1
```

`Compare` is migration-only and `Lua` is the legacy ALE/SC1 route. Never run
ALE/SC1 and C++/SC2 as parallel production writers or success responders.
See [configuration details](docs/CONFIGURATION.md).

### 6. Install the AddOn and verify startup

Install the matching `addon/SoloCollections` from the client repository.
After starting `worldserver`, look for:

```text
event=startup_versions
event=build_info
event=schema_check result=ready
event=provider_registry result=ready
```

An administrator can run:

```text
.solocollections status
```

Stop and fix any build-metadata, mapping-hash, or schema mismatch. Do not
bypass it from the client.

## Documentation

- [Configuration and backend modes](docs/CONFIGURATION.md)
- [Source layout and cross-repository development](docs/DEVELOPMENT.md)
- [Account schema and revision invariant](docs/schema/account-collections-v1.md)
- [Upstream fork base](UPSTREAM_BASE.md)
- [Third-party provenance](THIRD_PARTY_NOTICES.md)
- [Client installation, camera, and Agent development](https://github.com/haha2345/SoloCollections#readme)

## Contributions

The client repository welcomes body/weapon camera parameters for race, sex,
HD/custom models, and unusual weapon bounds. This repository especially
welcomes provider and account-cache work, revision/concurrency hardening, SC2
compatibility and diagnostics, unlock-source coverage, AzerothCore API/Linux
build updates, performance work, and SQL/security review.

Read [CONTRIBUTING.md](CONTRIBUTING.md). When using a coding Agent, require it
to read [AGENTS.md](AGENTS.md) and [the development guide](docs/DEVELOPMENT.md),
limit it to one clear problem, and keep human control over SQL, authorization,
database writes, deployment, and publication.

## License and provenance

This repository preserves the AzerothCore `mod-transmog` Git history and is
licensed under **GNU AGPL-3.0**; see [LICENSE](LICENSE). Upstream provenance
and the fork point are documented in [UPSTREAM_BASE.md](UPSTREAM_BASE.md) and
[THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).

This is an unofficial community project and is not affiliated with or endorsed
by Blizzard Entertainment or AzerothCore.
