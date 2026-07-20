# mod-solo-collections

`mod-solo-collections` is the authoritative AzerothCore C++ backend for the
SoloCollections AddOn. It owns account collection persistence, authorization,
revision ordering, SC2 synchronization, and server-side actions. The fork keeps
the Git history and AGPL-3.0 license of AzerothCore `mod-transmog`.

## Compatibility contract

A release is a matched set. Use `release-manifest.json` from the
SoloCollections unified release to verify:

- AddOn, module, and AzerothCore commits;
- SC2 protocol version and per-category mapping hashes;
- asset pack version; and
- SQL schema and append-only migration versions.

Do not run the legacy ALE Lua as a parallel production writer or action
responder after the C++ backend owns the account.

## Installation boundaries

1. Extract this module below `<AzerothCore source>/modules/mod-solo-collections`.
2. Apply the SQL below `data/sql/` to its named auth, characters, or world
   database. New characters databases use
   `data/sql/db-characters/solo_collections_schema_v1.sql`; existing databases
   use the matching append-only file below `data/sql/updates/char/`.
3. Re-run CMake and build `worldserver` from the AzerothCore commit recorded in
   the release manifest.
4. Copy `conf/transmog.conf.dist` to the runtime configuration directory and
   edit the copy. Never publish the runtime file or database credentials.
5. Install the AddOn separately. Client resources are a third, optional
   distribution and are not part of this module source archive.

After startup, verify `event=startup_versions`, `event=schema_check
result=ready`, and `.solocollections status`.

## Tests

Run the module contracts from a clean checkout:

```powershell
python -m unittest discover -s tests -p "test_*.py"
```

The AzerothCore reusable module workflow performs the integrated Core build.

## License and provenance

This module is distributed under GNU AGPL version 3; see [LICENSE](LICENSE).
Upstream authorship and the fork point are preserved in
[THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md) and the Git history.
