package database

import (
	"embed"
	"fmt"
	"io/fs"
	"log"
	"sort"
	"strings"
	"time"

	"gorm.io/gorm"
)

// Schema changes are numbered SQL files in migrations/, applied in order at startup.
// Each runs once, in its own transaction, and is recorded in schema_migrations.
// Add a new file for every change; never edit one that has shipped.
//
//go:embed migrations/*.sql
var migrationFiles embed.FS

func migrate(db *gorm.DB) error {
	if err := db.Exec("CREATE TABLE IF NOT EXISTS `schema_migrations` (`version` text PRIMARY KEY, `applied_at` datetime NOT NULL)").Error; err != nil {
		return err
	}

	var applied []string
	if err := db.Raw("SELECT `version` FROM `schema_migrations`").Scan(&applied).Error; err != nil {
		return err
	}
	done := map[string]bool{}
	for _, v := range applied {
		done[v] = true
	}

	names, err := fs.Glob(migrationFiles, "migrations/*.sql")
	if err != nil {
		return err
	}
	sort.Strings(names)

	for _, name := range names {
		version := strings.TrimSuffix(strings.TrimPrefix(name, "migrations/"), ".sql")
		if done[version] {
			continue
		}
		sql, err := migrationFiles.ReadFile(name)
		if err != nil {
			return err
		}
		err = db.Transaction(func(tx *gorm.DB) error {
			if err := tx.Exec(string(sql)).Error; err != nil {
				return err
			}
			return tx.Exec("INSERT INTO `schema_migrations` (`version`, `applied_at`) VALUES (?, ?)", version, time.Now()).Error
		})
		if err != nil {
			return fmt.Errorf("migration %s: %w", version, err)
		}
		log.Printf("applied migration %s", version)
	}
	return nil
}
