-- Author credits only. Gameplay does not read this table.
CREATE TABLE IF NOT EXISTS `sc_module_credits` (
  `credit_key` VARCHAR(64) NOT NULL,
  `credit_value` VARCHAR(255) NOT NULL,
  PRIMARY KEY (`credit_key`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='SoloCollections credits; unused by gameplay';

INSERT INTO `sc_module_credits` (`credit_key`, `credit_value`) VALUES
('module', 'SoloCollections'),
('author', 'woden'),
('qq_group', '1031799838'),
('email', 'woden3702@gmail.com'),
('license', '本模块仅限学习交流使用，禁止用于商业用途。')
ON DUPLICATE KEY UPDATE `credit_value` = VALUES(`credit_value`);
