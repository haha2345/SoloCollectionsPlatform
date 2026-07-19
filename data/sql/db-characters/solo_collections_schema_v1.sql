-- SoloCollections account collection schema, version 1.
-- This snapshot is for new installations. Published update files are append-only.

CREATE TABLE IF NOT EXISTS `sc_account_state` (
  `account_id` INT UNSIGNED NOT NULL,
  `revision` BIGINT UNSIGNED NOT NULL DEFAULT 0,
  `schema_version` SMALLINT UNSIGNED NOT NULL DEFAULT 1,
  `created_at` DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
  `updated_at` DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3) ON UPDATE CURRENT_TIMESTAMP(3),
  PRIMARY KEY (`account_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='SoloCollections account revision state v1';

CREATE TABLE IF NOT EXISTS `sc_collection_unlock` (
  `account_id` INT UNSIGNED NOT NULL,
  `type_id` SMALLINT UNSIGNED NOT NULL,
  `collection_id` INT UNSIGNED NOT NULL,
  `revision` BIGINT UNSIGNED NOT NULL,
  `source_kind` SMALLINT UNSIGNED NOT NULL,
  `source_id` BIGINT UNSIGNED NOT NULL DEFAULT 0,
  `character_guid` INT UNSIGNED NOT NULL DEFAULT 0,
  `unlocked_at` DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
  PRIMARY KEY (`account_id`, `type_id`, `collection_id`),
  KEY `idx_sc_unlock_account_revision` (`account_id`, `revision`),
  KEY `idx_sc_unlock_type_collection` (`type_id`, `collection_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='SoloCollections authoritative account unlocks v1';

CREATE TABLE IF NOT EXISTS `sc_collection_audit` (
  `audit_id` BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  `account_id` INT UNSIGNED NOT NULL,
  `type_id` SMALLINT UNSIGNED NOT NULL,
  `collection_id` INT UNSIGNED NOT NULL,
  `action_kind` SMALLINT UNSIGNED NOT NULL,
  `source_kind` SMALLINT UNSIGNED NOT NULL,
  `source_id` BIGINT UNSIGNED NOT NULL DEFAULT 0,
  `character_guid` INT UNSIGNED NOT NULL DEFAULT 0,
  `actor_account_id` INT UNSIGNED NOT NULL DEFAULT 0,
  `actor_guid` INT UNSIGNED NOT NULL DEFAULT 0,
  `revision` BIGINT UNSIGNED NOT NULL DEFAULT 0,
  `result_code` SMALLINT UNSIGNED NOT NULL,
  `created_at` DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
  PRIMARY KEY (`audit_id`),
  KEY `idx_sc_audit_account_time` (`account_id`, `created_at`),
  KEY `idx_sc_audit_actor_time` (`actor_account_id`, `created_at`),
  KEY `idx_sc_audit_collection` (`type_id`, `collection_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='SoloCollections immutable numeric audit trail v1';

CREATE TABLE IF NOT EXISTS `sc_migration_marker` (
  `account_id` INT UNSIGNED NOT NULL,
  `migration_id` INT UNSIGNED NOT NULL,
  `migration_version` SMALLINT UNSIGNED NOT NULL,
  `completed_revision` BIGINT UNSIGNED NOT NULL DEFAULT 0,
  `imported_count` INT UNSIGNED NOT NULL DEFAULT 0,
  `rejected_count` INT UNSIGNED NOT NULL DEFAULT 0,
  `completed_at` DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
  PRIMARY KEY (`account_id`, `migration_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='SoloCollections per-account migration markers v1';
