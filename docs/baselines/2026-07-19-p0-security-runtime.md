# 2026-07-19 P0 Security Runtime Deployment

## Deployed revisions

| Component | Revision |
|---|---|
| AzerothCore production checkout | `4cc67a316d2bec9faf27c3392634282e70cacbe0` |
| `mod-solo-collections` P0 code | `bd7aa3e` |
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
Size:    41,565,184 bytes
SHA-256: 54898B85F699E2CB6F4F3134DC9F0587E995830EE575E88F3D4727BE4902C9C6
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

The immediate pre-fix P0 binary is also preserved at:

```text
D:\AzerothCore_NPCBots_Clean\backups\solocollections-gossip-precharge-20260720-001010
SHA-256: DE2C4AC5C866B9D29CDAEB71CB11896C5380F7A6F0CE9E6AA9BF46749E2ED4B2
```

The pre-config-reload-fix binary is preserved at:

```text
D:\AzerothCore_NPCBots_Clean\backups\solocollections-config-reload-20260720-001939
SHA-256: 3DABC0E0DC9EC78DF0EBFC412323D40C56EFA9302E2A7514A41D96E8BF940AA4
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
- The collection cache loaded successfully with zero appearances at startup.
- NPCBots remained enabled and loaded normally.
- The server reached the `worldserver-daemon ready` state.

Before fault injection, `Errors.log` contained only three pre-existing orphan
references for quest `990101`. The deliberate collection-reload failures and
their recovery evidence are recorded below.

## Live acceptance setup

- Account ID `1` is GM level 3 and character GUID `14` (`啊啊水电费`) was
  confirmed online for the acceptance run.
- Character login populated 65 collected appearances without manual database
  injection.
- A compatible collected test pair is available: target item `900047`
  (`边境守备护腿`) and source item `6084` (`暴风城卫兵护腿`).
- `.transmog check 啊啊水电费 900047 6084` passed every item-pair,
  target-item, source-item, and collection check, ending with
  `结果：可以幻化`.
- Remote administration executed `.transmog reload` successfully and returned
  both `Transmog configs reloaded.` and `Transmog collections reloaded.`. No
  worldserver restart was required.
- No spawn for creature templates `190010` or `190011` existed before the
  client-side acceptance run.
- The GM client created creature spawn GUID `6000008` from template `190010`.
- Applying source `6084` to equipped target `900047` succeeded. Characters DB
  item GUID `1410` now has `FakeEntry = 6084` and `Owner = 14`. Character money
  remained at the pre-test value of `1000268` copper, as expected for this
  zero-price target.

### Rejected-request runtime regression and fix

The first stale-menu test correctly rejected revoked source `6971` and left
head item GUID `1403` without a fake entry, but AzerothCore's gossip handler
pre-deducted the option's `BoxMoney` before the module callback. Character
money fell from `1000268` to `990268` copper despite the rejection.

Commit `c455d68` changed gossip options to use `BoxMoney = 0`, retained a
read-only icon-based cost display, and left all real deductions exclusively in
`CommitApplyPlan` after a successful database commit. The security contract
suite now includes a regression test for this Core/module boundary and passes
21 of 21 tests.

After deploying the fix, the character's `10000` copper was restored while the
character was offline. The same stale-menu test was repeated: source `6971`
was removed and the collection cache reloaded while the confirmation dialog
remained open. The client reported `源元素不存在`; character money remained
`1000268`, item GUID `1403` retained no fake entry, and the temporary
collection row remained absent.

### Resource preflight and disk-config reload

The first insufficient-money setup exposed that `.transmog reload` called
`LoadConfig(true)` against ConfigMgr's existing memory snapshot without first
reloading module files from disk. The command reported success, but the test
appearance was applied using the old zero-extra-cost values. That controlled
apply cost `10000` copper at the normal base price; the appearance was removed
and the test cost was restored while the character was offline.

Commit `bd7aa3e` now calls `LoadModulesConfigs(true, false)` before loading the
transmog runtime values. A contract test enforces this order. After deployment,
the command reported `Transmog module config files and runtime values
reloaded.` and both resource-failure paths passed:

- With `CopperCost = 2000000`, the client reported `你没有足够的钱`.
  Live `.pinfo` remained `100g2s68c`; item GUID `1403` retained no fake entry.
- With `RequireToken = 1`, `TokenEntry = 49426`, and `TokenAmount = 1` while
  the character owned zero tokens, the client reported `你的筹码不够`.
  Money, token count, and item GUID `1403` remained unchanged.

The production config was restored to `CopperCost = 0` and
`RequireToken = 0`; temporary collection item `6971` was deleted and the
runtime cache reloaded.

### Mixed-validity preset atomicity

A temporary preset named `P0-Atomic-Mixed` contained a valid head request
(`slot 0 -> item 6971`) followed by an incompatible shoulder request
(`slot 2 -> item 6971`). Before the test, head item GUID `1403` and shoulder
item GUID `1404` both had no fake entry.

The client reported `所选项目无效`. Database verification found no
`custom_transmogrification` row for either item, and live money remained
`100g2s68c`. The valid first slot was therefore not partially committed. The
temporary preset and collection row were then deleted and runtime state
reloaded.

### Cache failure retention and successful revoke

The first failure-injection attempt temporarily renamed the collection table.
AzerothCore classified MySQL error `1146` as an out-of-date database structure
and protectively terminated worldserver. A `finally` block restored the table
name; verification found all 66 rows intact, and worldserver restarted
normally. This unsafe injection method was discarded and is not counted as a
passing reload test.

The replacement test left the schema unchanged. A dedicated connection held a
short write lock while `.transmog reload` issued its collection SELECT; only
that SELECT was interrupted with `KILL QUERY`, producing MySQL error `1317`.
The command returned `Transmog collection reload failed; previous cache
retained.` Worldserver remained running, `.transmog check` still passed for
controlled item `6971`, and the real client still listed `淬火罩帽`.

After deleting item `6971` from the collection table, a normal reload succeeded.
The diagnostic then reported that the appearance was not collected, and after
closing and reopening the NPC menu the client confirmed `淬火罩帽` had
disappeared. The temporary collection row, query lock, and test connection were
all removed.

## Client acceptance status

The local `security-baseline` tag must not be created until a real 3.3.5 client
confirms all of the following against this deployed server:

1. [x] Open NPC `190010` and apply a collected appearance successfully.
2. [x] Submit an uncollected appearance and confirm no money, token, database, or
   visible-item side effect.
3. [x] Test insufficient money and insufficient token paths.
4. [x] Apply a preset containing one valid and one invalid slot and confirm that
   neither slot changes.
5. [x] Run `.transmog reload` after a controlled revoke and confirm the revoked
   appearance disappears while a deliberately failed reload retains the old
   cache.
