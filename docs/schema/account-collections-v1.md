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
contents are read only by explicit migration/reconciliation tools; the module
must never silently reinterpret or delete that legacy table during startup.

## Wardrobe projections

Append-only update `data/sql/updates/char/2026_08_16_00_wardrobe_projections.sql`
adds:

- `character_sc_transmog`: one row per character, 14 slot columns in Lab.SLOTS
  order, plus `revision`. `0` is empty, `2` is HideVisual, otherwise an
  appearance collectionId. This is SC2 type 18 and is not account progress.
- `account_sc_outfit`: up to 10 rows per account (`account_id`, `uid`),
  `name_hex` (UTF-8 hex, max 96), `slot_blob` (same 14-segment grammar), and
  `revision`. This is SC2 type 19.

These tables do not advance `sc_account_state.revision`. Existing character
NPC outfits stay on their own table and are not the type 19 authority.
