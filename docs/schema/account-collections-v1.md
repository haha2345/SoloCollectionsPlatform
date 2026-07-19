# SoloCollections account collection schema v1

The authoritative characters-database schema version is `1`. New installations
use `data/sql/db-characters/solo_collections_schema_v1.sql`; existing databases
receive the append-only migration
`data/sql/updates/char/2026_07_20_00_solo_collections_schema_v1.sql`.

## Transaction invariant

Every successful unlock or revoke transaction must:

1. ensure `sc_account_state` exists for the numeric account ID;
2. lock/update that account row and advance `revision` exactly once;
3. insert/delete the `(account_id, type_id, collection_id)` row using the new revision;
4. insert the numeric audit row using the same revision; and
5. commit before the world-thread cache or connected sessions are updated.

Failed and duplicate operations must not leave a cache-only unlock. Rejected
requests may write an audit row with revision `0`, but they must not advance the
account revision.

## Stable numeric fields

`type_id`, `collection_id`, `action_kind`, `source_kind`, and `result_code` are
stable numeric identifiers. Their meaning is defined by code/catalog manifests,
not by SQL enum ordering. No arbitrary client text is stored in schema v1.

The legacy `custom_unlocked_appearances` table is intentionally untouched. Its
dry-run and canonical migration are owned by phase 8.
