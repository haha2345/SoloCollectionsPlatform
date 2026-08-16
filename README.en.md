# SoloCollections client for WoW 3.3.5a

[中文](README.md) · [Download v0.2.0](https://github.com/haha2345/SoloCollections/releases/tag/v0.2.0) · [Server module](https://github.com/haha2345/mod-solo-collections) · [Installation](docs/INSTALLATION.en.md) · [Contributing](CONTRIBUTING.md)

SoloCollections adds a Retail-inspired collection journal to World of Warcraft
3.3.5a build 12340. It presents mounts, non-battle pets, toys, equipment
appearances, and sets in one AddOn. This repository contains the AddOn,
reproducible catalog sources, the SC2 protocol, catalog tooling, and an optional
x86 SoloCam camera extension.

The separate
[`mod-solo-collections`](https://github.com/haha2345/mod-solo-collections)
repository is the sole authority for account collections, authorization,
revisions, synchronization, and actions. Production installations must use the
C++/SC2 backend. The ALE/SC1 file retained here is only a legacy migration and
protocol reference; it must not answer production actions beside the C++
backend.

> The current source release is `v0.2.0`. Use the AddOn, server module, and
> `release-manifest.json` from that matched tag. The old `v0.1.0` package is
> an incompatible ALE/SC1 development preview.

![Set collection and dressing-room preview](docs/images/wardrobe-sets.png)

## Features and status

- A unified window for mounts, companions, toys, appearance items, and sets.
  Transmogrification uses a separate Wardrobe window opened by its own button.
- Server-authoritative SC2 handshakes, account snapshots, revision deltas, and
  action results.
- Appearance filters, collection progress, set previews, favorites, and stable
  catalog IDs.
- Race/sex/slot body-camera profiles and an in-game camera workbench for
  standalone weapon and off-hand models.
- Reproducible canonical sources, review decisions, generated outputs, and
  matched Lua/C++ catalog projections.
- An optional SoloCam extension for one exact 32-bit 3.3.5a client build.

The current generated catalog contains 19,146 canonical records: 281 mounts,
201 companions, 9 reviewed toys, 18,190 appearances, and 465 sets. The public
weapon presentation baseline contains 3,690 candidates: 3,541 `READY` and 149
explicitly `UNAVAILABLE`. These values describe the checked-in generated
manifest, not a live player's database.

The reference client has local acceptance evidence, but item-page framing still
needs community tuning. Different races, sexes, HD/custom models, and
extreme-aspect weapons can be too close, too far away, offset, or clipped. See
the [camera contribution guide](docs/CAMERA_CONTRIBUTIONS.md).

## Screenshots

| Mounts | Non-battle pets |
| --- | --- |
| ![Mount collection and model preview](docs/images/mounts.png) | ![Non-battle pet collection and model preview](docs/images/pets.png) |

| Toy box | Item appearances |
| --- | --- |
| ![Toy box and tooltip](docs/images/toys.png) | ![Item appearances and slot filters](docs/images/wardrobe-items.png) |

## The two repositories

| Repository | Responsibility | License |
| --- | --- | --- |
| [`SoloCollections`](https://github.com/haha2345/SoloCollections) | 3.3.5a AddOn, catalog sources, SC2 schema, generators, and SoloCam | GPL-3.0-or-later |
| [`mod-solo-collections`](https://github.com/haha2345/mod-solo-collections) | Authoritative AzerothCore C++ backend, account state, SQL, server actions, and compatible transmogrification code | AGPL-3.0 |

The client never decides ownership. It sends stable
`typeId/collectionId/actionId` values; the server performs authorization,
state changes, and the final action.

## Runtime environment

### Required

- A 32-bit World of Warcraft 3.3.5a build-12340 client;
- AddOn interface version `30300`;
- an AzerothCore WotLK server;
- [`mod-solo-collections`](https://github.com/haha2345/mod-solo-collections);
- matching metadata, mapping hashes, and SC2 protocol versions across the
  AddOn and module.

### Development

- Git 2.40 or newer;
- Python 3.10 for catalog tooling and contracts;
- Windows PowerShell 5.1 or PowerShell 7;
- Windows 10/11, Visual Studio 2022, the MSVC v143 x86 toolchain, and a Windows
  SDK when building SoloCam;
- the official
  [AzerothCore Windows requirements](https://www.azerothcore.org/wiki/windows-requirements)
  or the equivalent official guide for the platform used to build the module.

The AddOn itself uses the WoW 3.3.5 Lua 5.1/FrameXML API and is not compiled.
Retail-only APIs such as `C_MountJournal`, `SetAtlas`, and `ModelScene` are not
available.

## Quick setup

### 1. Get the matched version

```powershell
git clone --branch v0.2.0 https://github.com/haha2345/SoloCollections.git
git clone --branch v0.2.0 https://github.com/haha2345/mod-solo-collections.git
```

Most installers can instead download
[`SoloCollections-v0.2.0-unified-source.zip`](https://github.com/haha2345/SoloCollections/releases/tag/v0.2.0)
and follow its `README.en.md`. See the
[release usage guide](docs/RELEASE_USAGE.en.md).

### 2. Install and build the server module

Place the module at:

```text
<AzerothCore>/modules/mod-solo-collections/
```

Re-run CMake and build `authserver` and `worldserver` with
`MODULES=static`. Copy `conf/transmog.conf.dist` into the runtime configuration
directory and use this production ownership mode:

```ini
SoloCollections.Backend = Cpp
SoloCollections.Preview.Enabled = 1
```

See the module repository's
[English README](https://github.com/haha2345/mod-solo-collections/blob/main/README.en.md)
for full build, SQL, configuration, and startup instructions.

### 3. Install the AddOn

Copy the complete directory:

```text
SoloCollections/addon/SoloCollections
    -> <WoW>/Interface/AddOns/SoloCollections
```

The final path must contain:

```text
<WoW>/Interface/AddOns/SoloCollections/SoloCollections.toc
```

### 4. Verify the connection

The server should log `event=startup_versions` and
`event=schema_check result=ready`. An administrator can run:

```text
.solocollections status
```

Opening the collection window should complete the SC2 handshake and enter an
authoritative state. A metadata or asset mismatch must fail closed rather than
allowing client-side authorization.

See [INSTALLATION.en.md](docs/INSTALLATION.en.md) for database, install, and
rollback details.

## Optional client camera extension

Collection state, catalogs, and most UI features work without SoloCam. Local
body framing and some standalone weapon previews fall back to stock behavior
or an explicit unavailable state when it is absent.

SoloCam only supports x86 WoW 3.3.5a build 12340 and locks the original
`Wow.exe` SHA-256:

```text
AA63A5750D60EF16746C686B3D5E26876D98953EAB08B1C026CD0FAF78E88CB8
```

The patcher creates a copy and never overwrites the original executable. Stop
if the hash differs. Neither source repository nor a source release contains
`Wow.exe`, a patched executable, MPQs, DBCs, M2/SKIN/BLP files, or other
client-extracted assets. Read the
[SoloCam guide](client-extension/SoloCam/README.md) and the
[MPQ build guide](docs/BUILD_MPQ.zh-CN.md) before using this optional path.

## Build and checks

| Area | Command or entry point |
| --- | --- |
| AddOn | No compile step; copy `addon/SoloCollections` |
| Python dependencies | `python -m pip install -r client-extension/SoloCam/requirements-dev.txt` |
| AddOn/catalog contracts | `python -m unittest discover -s tools/collections/tests -p "test_*.py"` |
| SoloCam portable contracts | `python -m unittest discover -s client-extension/SoloCam/tests -p "test_*.py"` |
| SoloCam x86 DLL | `client-extension/SoloCam/scripts/build.ps1` |
| Catalog generation | `tools/catalog/generate_catalog.py`, with legally obtained external evidence inputs |
| Unified source package | `tools/release/build_unified_release.py` |
| Optional integrated client UI | Add `--client-suite-root <AddOns> --suite-lock <suite-lock.json>`; emitted separately from public source |

See [BUILDING.en.md](docs/BUILDING.en.md) for dependencies, environment
variables, output locations, and catalog-generation boundaries.

### Two deliverables

The public SoloCollections AddOn/server source bundle continues to contain only project-owned source and reviewed media; it does not vendor DragonUI BLP files. A local one-install UI build may separately produce an `integrated-client-ui.zip` and per-file SHA-256 manifest from the SoloClientSuite's exact five AddOn roots. `suite-lock.json` records third-party origins, pinned commits, project patch state, and directory hashes. The integrated archive is not a default public-source attachment, and no build command writes to a real client.

## Documentation

- [Using the v0.2.0 release](docs/RELEASE_USAGE.en.md)
- [Installation and rollback](docs/INSTALLATION.en.md)
- [Build and development environment](docs/BUILDING.en.md)
- [Development workflow and repository map](docs/DEVELOPMENT.md)
- [Current source status and known limits](docs/STATUS.md)
- [Camera parameter contributions](docs/CAMERA_CONTRIBUTIONS.md)
- [Continuing development with an agent](docs/AGENT_DEVELOPMENT.md)
- [Architecture index](docs/architecture/README.md)
- [SC2 protocol](docs/protocol/sc2-wire-v1.md)
- [Asset and publication boundary](docs/ASSETS.md)
- [Licensing](docs/LICENSING.md)
- [Downloads and version matching](docs/DOWNLOADS.md)

## Contributing

Contributions are welcome in Lua, C++, Python, catalog review, documentation,
compatibility, and camera parameters. High-value areas include:

- body-camera profiles for additional race/sex/custom-model combinations;
- weapon-family, shared-model, and isolated appearance camera corrections;
- English UI and other locale improvements;
- catalog provenance, performance, and SC2 compatibility work;
- reproducible screenshots and failure samples that do not redistribute game
  assets.

Fork the repository, branch from `main`, and keep each pull request focused.
Camera pull requests should include the race/sex/slot or weapon identity,
client build/hash, before-and-after screenshots, the workbench JSONL export,
and the reason for the selected scope. Read [CONTRIBUTING.md](CONTRIBUTING.md).

## Continuing with an agent

Both repositories include a root `AGENTS.md` and this repository includes a
human-readable [agent development guide](docs/AGENT_DEVELOPMENT.md). Clone the
repositories as siblings, ask the agent to read those files first, and give it
one bounded objective. Do not authorize an agent to download client assets,
modify a real database, overwrite a game installation, or commit runtime
outputs.

Example:

```text
Read AGENTS.md, docs/DEVELOPMENT.md, and docs/CAMERA_CONTRIBUTIONS.md first.
Work only on the camera issue for <race/sex/slot or weapon identity>.
Preserve server authority and the SC2 boundary. Do not add client binaries or
extracted assets. Produce the smallest code/parameter change, list the real
3.3.5a client checks I must perform, and update the relevant documentation.
```

## License and disclaimer

Project-authored code in this repository is licensed under
**GPL-3.0-or-later**; see [LICENSE](LICENSE). Third-party notices are in
[THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md). Client-extracted assets,
game binaries, and the separate server module retain their own terms.

This is an unofficial community compatibility project and is not endorsed by
Blizzard Entertainment or AzerothCore. Use only clients, servers, and assets
you are entitled to use.
