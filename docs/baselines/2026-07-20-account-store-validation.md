# AccountCollectionStore validation

Date: 2026-07-20  
Core: `4cc67a316d2b`  
Configuration: Visual Studio 18 2026, x64, RelWithDebInfo

## Automated and build checks

- Python module contracts: 42 passed.
- Native domain/state-machine CTest: 1 passed.
- AzerothCore `worldserver` configured and linked with
  `SoloCollectionsAccountStore.cpp` successfully.
- The store uses module-owned query and transaction callback processors that
  are pumped from the world thread.

## Isolated MySQL integration

The exact optimistic revision-guard transaction shape was exercised against
MySQL 8.4.10 in `sc_store_v1_integration_test`:

```text
ASYNC_TX_SHAPE_GRANT revision_unlock_audit=1:1:1
DUPLICATE_AND_STALE_REVISION_ROLLBACK=1:1:1
RESTART_RECOVERY sentinel_revision=2 owned_rows=2
```

The first grant advanced one revision and wrote one unlock plus one audit row.
Repeating the stale/duplicate transaction failed and rolled the revision back.
A retry for another collection advanced revision 2, and the login snapshot
query reconstructed both owned rows from durable data. The temporary database
was removed after validation.

## Runtime boundary

The store never captures `Player*` or `WorldSession*`. Load callbacks capture
only account ID, character GUID and login generation. A confirmed transaction
updates the world-thread cache before publishing its committed delta event;
failed transactions leave the cache unchanged.
