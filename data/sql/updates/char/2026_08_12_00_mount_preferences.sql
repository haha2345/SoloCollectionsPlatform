-- SoloCollections account-scoped mount favorites (SC2 internal projection type 16).
-- The referenced collection identity remains the authoritative mount type 10 ID.
CREATE TABLE IF NOT EXISTS `solo_collection_preference` (
  `account_id` INT UNSIGNED NOT NULL,
  `type_id` SMALLINT UNSIGNED NOT NULL,
  `collection_id` INT UNSIGNED NOT NULL,
  `favorite` TINYINT UNSIGNED NOT NULL DEFAULT 0,
  `updated_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`account_id`, `type_id`, `collection_id`),
  KEY `idx_solo_collection_preference_type` (`account_id`, `type_id`, `favorite`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='SoloCollections account preferences for collection types 10 and 11';
