# SoloCollections schema v1 validation

Date: 2026-07-20  
Database engine: MySQL 8.4.10  
Migration: `data/sql/updates/char/2026_07_20_00_solo_collections_schema_v1.sql`

Validation used two isolated temporary databases on the local development
server. Production characters data was not modified, and both temporary
databases were removed after the checks.

## Results

```text
EMPTY_INSTALL tables=4
UPGRADE_AND_RERUN sc_tables_and_legacy_row=4:1
ATOMIC_COMMIT revision_unlock_audit=1:1:1
DUPLICATE_ROLLBACK revision_unlock_audit=1:1:1
TEMP_DATABASES_REMAINING=0
```

The upgrade fixture contained the legacy `custom_unlocked_appearances` table
and one row. Applying schema migration v1 twice created the four `sc_*` tables
without removing or changing that legacy row.

The transaction fixture advanced one account revision, inserted one unlock and
inserted one audit row in a single transaction. A second transaction attempted
the same unique unlock after incrementing the revision; the unique-key error
rolled back the whole transaction, leaving revision, unlock count and audit
count at `1:1:1`.

Credentials were supplied through the process environment and are not included
in this record.
