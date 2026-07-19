# 2026-07-19 P0 Security Runtime Deployment

## Deployed revisions

| Component | Revision |
|---|---|
| AzerothCore production checkout | `4cc67a316d2bec9faf27c3392634282e70cacbe0` |
| `mod-solo-collections` P0 code | `3bbb4f7` |
| Production build | `RelWithDebInfo`, static modules |

The production build retained ALE, AOE Loot, AutoBalance, Junk-to-Gold,
Learn Spells, Solo LFG, and the NPCBots Core integration while adding
`mod-solo-collections`.

## Deployment evidence

Runtime root:

```text
D:\AzerothCore_NPCBots_Clean
```

Deployed `worldserver.exe`:

```text
Size:    41,563,648 bytes
SHA-256: DE2C4AC5C866B9D29CDAEB71CB11896C5380F7A6F0CE9E6AA9BF46749E2ED4B2
```

Rollback backup:

```text
D:\AzerothCore_NPCBots_Clean\backups\solocollections-security-baseline-20260719-232904
```

The backup contains the previous `worldserver.exe`, `worldserver.pdb`, and a
targeted `rollback.sql`. The previous executable SHA-256 was:

```text
B335010D2ADCB28FC1E96528C9DBFFB607A51B79B4C8C44EC5258737011E2955
```

## Database and startup checks

- Module schema installed in auth, characters, and world databases.
- World rows installed: two transmog creature templates, one portable spell,
  two fake-vendor items, and eight transmog commands.
- `mod-transmog` strings: IDs 1 through 81, 81 rows total.
- `mod-transmog` localized strings: 626 rows.
- The ordered repair migration was re-applied by AzerothCore's updater with
  hash `9C39F046C67BE5433539F8B6A7DD3580E2FDB127`.
- The atomic-apply error migration is registered with hash
  `AAE2B9756ABE2E73D0F62966D9868C3705B82449`.
- Startup loaded 89 total module strings and 658 total localized module
  strings.
- The collection cache loaded successfully with zero current appearances.
- NPCBots remained enabled and loaded normally.
- The server reached the `worldserver-daemon ready` state.

`Errors.log` contains only three pre-existing orphan references for quest
`990101`; no new transmog or module error was recorded.

## Remaining in-client acceptance

The local `security-baseline` tag must not be created until a real 3.3.5 client
confirms all of the following against this deployed server:

1. Open NPC `190010` and apply a collected appearance successfully.
2. Submit an uncollected appearance and confirm no money, token, database, or
   visible-item side effect.
3. Test insufficient money and insufficient token paths.
4. Apply a preset containing one valid and one invalid slot and confirm that
   neither slot changes.
5. Run `.transmog reload` after a controlled revoke and confirm the revoked
   appearance disappears while a deliberately failed reload retains the old
   cache.

