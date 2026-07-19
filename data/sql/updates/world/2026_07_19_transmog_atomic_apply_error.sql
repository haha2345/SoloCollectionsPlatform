DELETE FROM `module_string` WHERE `module` = 'mod-transmog' AND `id` = 81;
INSERT INTO `module_string` (`module`, `id`, `string`) VALUES
('mod-transmog', 81, 'The appearance could not be saved. No costs were charged.');

DELETE FROM `module_string_locale` WHERE `module` = 'mod-transmog' AND `id` = 81;
INSERT INTO `module_string_locale` (`module`, `id`, `locale`, `string`) VALUES
('mod-transmog', 81, 'zhCN', '外观保存失败，未扣除任何费用。'),
('mod-transmog', 81, 'zhTW', '外觀儲存失敗，未扣除任何費用。');
