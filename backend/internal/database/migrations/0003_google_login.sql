-- Accounts that sign in with Google are matched by Google's stable account id.

ALTER TABLE `users` ADD COLUMN `google_id` text;
CREATE UNIQUE INDEX IF NOT EXISTS `idx_users_google_id` ON `users`(`google_id`);
