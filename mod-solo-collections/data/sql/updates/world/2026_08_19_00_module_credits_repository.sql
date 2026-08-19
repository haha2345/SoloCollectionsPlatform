-- Author credits only. Gameplay does not read this table.
INSERT INTO `sc_module_credits` (`credit_key`, `credit_value`) VALUES
('repository', 'https://github.com/haha2345/SoloCollectionsPlatform')
ON DUPLICATE KEY UPDATE `credit_value` = VALUES(`credit_value`);
