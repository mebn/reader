-- Accounts and the synced collections, as first released.
-- IF NOT EXISTS: databases from before migrations already have these tables.

CREATE TABLE IF NOT EXISTS `users` (
  `id` text,
  `email` text NOT NULL,
  `password_hash` text NOT NULL,
  `created_at` datetime,
  PRIMARY KEY (`id`)
);
CREATE UNIQUE INDEX IF NOT EXISTS `idx_users_email` ON `users`(`email`);

CREATE TABLE IF NOT EXISTS `folders` (
  `user_id` text,
  `id` text,
  `modified_at` integer,
  `version` integer,
  `deleted` numeric,
  `name` text,
  `parent_id` text,
  PRIMARY KEY (`user_id`, `id`)
);
CREATE INDEX IF NOT EXISTS `idx_folders_version` ON `folders`(`version`);

CREATE TABLE IF NOT EXISTS `books` (
  `user_id` text,
  `id` text,
  `modified_at` integer,
  `version` integer,
  `deleted` numeric,
  `folder_id` text,
  `title` text,
  `author` text,
  `format` text,
  `file_name` text,
  `size` integer,
  `hash` text,
  `has_cover` numeric,
  `added_at` integer,
  PRIMARY KEY (`user_id`, `id`)
);
CREATE INDEX IF NOT EXISTS `idx_books_version` ON `books`(`version`);

CREATE TABLE IF NOT EXISTS `progresses` (
  `user_id` text,
  `id` text,
  `modified_at` integer,
  `version` integer,
  `deleted` numeric,
  `locator` text,
  `percent` real,
  PRIMARY KEY (`user_id`, `id`)
);
CREATE INDEX IF NOT EXISTS `idx_progresses_version` ON `progresses`(`version`);

CREATE TABLE IF NOT EXISTS `annotations` (
  `user_id` text,
  `id` text,
  `modified_at` integer,
  `version` integer,
  `deleted` numeric,
  `book_id` text,
  `kind` text,
  `locator` text,
  `text` text,
  `note` text,
  `color` text,
  `label` text,
  PRIMARY KEY (`user_id`, `id`)
);
CREATE INDEX IF NOT EXISTS `idx_annotations_book_id` ON `annotations`(`book_id`);
CREATE INDEX IF NOT EXISTS `idx_annotations_version` ON `annotations`(`version`);

CREATE TABLE IF NOT EXISTS `settings` (
  `user_id` text,
  `id` text,
  `modified_at` integer,
  `version` integer,
  `deleted` numeric,
  `data` text,
  PRIMARY KEY (`user_id`, `id`)
);
CREATE INDEX IF NOT EXISTS `idx_settings_version` ON `settings`(`version`);
