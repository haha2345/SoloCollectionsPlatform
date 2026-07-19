-- Stable module-owned permissions. IDs 71050-71054 were verified unused at creation.
INSERT INTO `rbac_permissions` (`id`, `name`) VALUES
  (71050, 'Command: solocollections status'),
  (71051, 'Command: solocollections account'),
  (71052, 'Command: solocollections grant/revoke'),
  (71053, 'Command: solocollections reload/resync'),
  (71054, 'Command: solocollections import/reconcile dry-run')
ON DUPLICATE KEY UPDATE `name` = VALUES(`name`);

-- Administrator Commands role. Account-specific deny/grant rules remain intact.
INSERT IGNORE INTO `rbac_linked_permissions` (`id`, `linkedId`) VALUES
  (196, 71050),
  (196, 71051),
  (196, 71052),
  (196, 71053),
  (196, 71054);
