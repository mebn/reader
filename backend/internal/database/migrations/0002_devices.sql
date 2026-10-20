-- Signed-in devices; a token names its device, and deleting the row signs it out.

CREATE TABLE IF NOT EXISTS `devices` (
  `id` text,
  `user_id` text NOT NULL,
  `name` text,
  `platform` text,
  `created_at` datetime,
  `last_seen_at` datetime,
  PRIMARY KEY (`id`)
);
CREATE INDEX IF NOT EXISTS `idx_devices_user_id` ON `devices`(`user_id`);
