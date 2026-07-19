import pathlib
import re
import unittest


ROOT = pathlib.Path(__file__).resolve().parents[1]
SNAPSHOT = ROOT / "data" / "sql" / "db-characters" / "solo_collections_schema_v1.sql"
MIGRATION = ROOT / "data" / "sql" / "updates" / "char" / "2026_07_20_00_solo_collections_schema_v1.sql"
DOC = (ROOT / "docs" / "schema" / "account-collections-v1.md").read_text(encoding="utf-8")


def normalized_schema(path):
    text = path.read_text(encoding="utf-8")
    text = re.sub(r"^--.*$", "", text, flags=re.MULTILINE)
    return re.sub(r"\s+", " ", text).strip()


class VersionedSchemaContractTests(unittest.TestCase):
    def test_snapshot_and_append_only_migration_define_the_same_schema(self):
        self.assertEqual(normalized_schema(SNAPSHOT), normalized_schema(MIGRATION))

    def test_all_required_tables_and_keys_exist(self):
        sql = normalized_schema(MIGRATION)
        for table in (
            "sc_account_state",
            "sc_collection_unlock",
            "sc_collection_audit",
            "sc_migration_marker",
        ):
            self.assertIn(f"CREATE TABLE IF NOT EXISTS `{table}`", sql)
        self.assertIn("PRIMARY KEY (`account_id`, `type_id`, `collection_id`)", sql)
        self.assertIn("PRIMARY KEY (`account_id`, `migration_id`)", sql)

    def test_ids_revisions_and_audit_are_explicit_unsigned_numbers(self):
        sql = normalized_schema(MIGRATION)
        for declaration in (
            "`account_id` INT UNSIGNED",
            "`type_id` SMALLINT UNSIGNED",
            "`collection_id` INT UNSIGNED",
            "`revision` BIGINT UNSIGNED",
            "`actor_account_id` INT UNSIGNED",
            "`result_code` SMALLINT UNSIGNED",
        ):
            self.assertIn(declaration, sql)
        self.assertNotRegex(sql, r"\b(?:ENUM|TEXT|VARCHAR)\b")

    def test_transaction_and_legacy_migration_boundaries_are_documented(self):
        self.assertIn("advance `revision` exactly once", DOC)
        self.assertIn("commit before the world-thread cache", DOC)
        self.assertIn("legacy `custom_unlocked_appearances` table is intentionally untouched", DOC)


if __name__ == "__main__":
    unittest.main()
