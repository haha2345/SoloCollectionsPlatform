# Phase 3 runtime validation

Date: 2026-07-20

Core: `4cc67a316d2b`

Configuration: Visual Studio 18 2026, x64, RelWithDebInfo

## Deployment

- All 46 Python contract tests passed.
- The native domain/state-machine CTest passed (`1/1`).
- The production AzerothCore `worldserver` target built successfully after the
  command and diagnostics sources were linked.
- The Phase 3 `worldserver.exe` was deployed to the local NPCBots runtime.
- SHA-256:
  `C41633180C27B67DEBF99EEA58584D3279F1BF4DD8BEEC374E9F280FB617DD62`.
- The pre-deployment binary is preserved at
  `D:\AzerothCore_NPCBots_Clean\_codex_backups\solocollections_phase3_20260720\worldserver.before-phase3.exe`.
- Startup registered one provider and reported
  `event=schema_check result=ready schema_version=1`.
- The authentication database contains all five Phase 3 RBAC permissions and
  all five Administrator role links (`5:5`).

## Real-client command checks

The administrator account was exercised through the 3.3.5 client, not through
the server console:

- `status` reported `schema=ready`, one provider, one ready cache entry, and no
  pending work.
- `account` reported a ready account with one active session.
- An unknown type grant failed closed with reason `768`
  (`SC_REASON_UNKNOWN_TYPE`).
- Granting type `1`, collection `500` queued revision 1 and committed.
- Repeating the grant failed with reason `1028`
  (`SC_REASON_ALREADY_OWNED`) and did not advance the revision.
- Revoking collection `500` queued revision 2 and committed.
- `import --dry-run` and `reconcile --dry-run` both reported `writes=0`; the
  observed legacy/unified counts were `65/0`.
- `reload` advanced the cache generation from 1 to 2 and reloaded revision 2.
- `resync` failed safely because no SC2 event sink is registered yet.

## Audit, restart recovery, and cleanup

Database inspection after the grant/revoke sequence showed revision 2, no
remaining collection `500`, and four matching audit rows: two successful
mutations and two rejected requests.

Collection `501` was then granted as a restart sentinel at revision 3. After a
full `worldserver` process restart and client reconnect, `account` loaded as
ready at revision 3, proving that the cache was reconstructed from durable
state. The sentinel was revoked through the audited command path at revision 4.

Final production-database checks:

```text
FINAL_STATE=4
FINAL_TEST_UNLOCKS=0
FINAL_AUDITS=6:SUCCESS=4:REJECTED=2
RBAC=5:5
```

No synthetic unlock remains. The audit history is intentionally retained as
the immutable record of the runtime acceptance test.
