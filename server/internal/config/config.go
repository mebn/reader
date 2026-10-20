package config

import (
	"os"
	"path/filepath"
)

type Config struct {
	Addr      string
	DataDir   string
	JWTSecret string
}

func (c Config) DatabasePath() string { return filepath.Join(c.DataDir, "reader.db") }
func (c Config) FilesDir() string     { return filepath.Join(c.DataDir, "files") }

// Load reads configuration from the environment, falling back to sensible defaults.
func Load() Config {
	return Config{
		Addr:      env("READER_ADDR", ":8080"),
		DataDir:   env("READER_DATA_DIR", "./data"),
		JWTSecret: env("READER_JWT_SECRET", "dev-secret-change-me"),
	}
}

func env(key, fallback string) string {
	if v, ok := os.LookupEnv(key); ok && v != "" {
		return v
	}
	return fallback
}
