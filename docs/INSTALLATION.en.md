# SoloCollections installation and rollback

## Supported environment

- A 32-bit World of Warcraft 3.3.5a build-12340 client;
- AzerothCore WotLK;
- the `SoloCollections` AddOn and `mod-solo-collections` C++ module;
- AzerothCore's normal MySQL and client-data requirements;
- the optional SoloCam extension only on its exact supported executable hash.

Do not combine `v0.2.0` with the old `v0.1.0` ALE demo package. Start with the
matched assets in the [release usage guide](RELEASE_USAGE.en.md), and record
the AddOn commit, module commit, metadata, and asset version as one set.

## Install the module

Place the server repository at:

```text
<AzerothCore source>/modules/mod-solo-collections/
```

Re-run CMake with `MODULES=static`, then build and install `authserver` and
`worldserver`. Follow the
[module README](https://github.com/haha2345/mod-solo-collections/blob/main/README.en.md).

The module registers its SQL snapshot and update paths through `include.sh`.
New databases use
`data/sql/db-characters/solo_collections_schema_v1.sql`; existing databases use
the append-only
`data/sql/updates/char/2026_07_20_00_solo_collections_schema_v1.sql`.
Do not manually apply both to the same database.

Copy the installed `transmog.conf.dist` to the runtime `transmog.conf` and set:

```ini
SoloCollections.Backend = Cpp
SoloCollections.Preview.Enabled = 1
```

`Compare` is a controlled migration mode and `Lua` is legacy ownership.
Do not leave ALE/SC1 answering production actions beside `Cpp`.

## Install the AddOn

Copy:

```text
<SoloCollections repo>/addon/SoloCollections/
    -> <WoW>/Interface/AddOns/SoloCollections/
```

The final path must be:

```text
<WoW>/Interface/AddOns/SoloCollections/SoloCollections.toc
```

Start the world server and require `event=startup_versions` plus
`event=schema_check result=ready`. In game, run:

```text
.solocollections status
```

Verify `Cpp` ownership, ready schema/providers, reasonable pending writes, a
completed SC2 handshake, and fail-closed metadata/asset mismatch behavior.

## Optional SoloCam and client resources

SoloCam only accepts this original `Wow.exe` SHA-256:

```text
AA63A5750D60EF16746C686B3D5E26876D98953EAB08B1C026CD0FAF78E88CB8
```

Read the [SoloCam guide](../client-extension/SoloCam/README.md). Its deployment
path creates a patched copy and DLL and does not overwrite the original
executable. Stop on any hash, signature, or build mismatch.

Standalone weapon resources must be built from client data the user is
entitled to use. This repository does not distribute game M2/SKIN/BLP/DBC/MPQ
content.

## Acceptance and rollback

Check all five pages, relog and `/reload`, server actions, appearance/set state,
fast card switching, the no-SoloCam fallback, and asset mismatch failure.
Record race, sex, slot, resolution, UI scale, and screenshots for camera claims.

For rollback, stop both processes, restore the exact previous worldserver,
configuration, AddOn, and client-file backups. Schema v1 is append-only; do not
drop collection tables without a database backup and an explicit migration
plan. Confirm restored hashes, backend mode, and `.solocollections status`.
