package config

import (
	"os"
	"path/filepath"
)

type Config struct {
	Addr      string
	DataDir   string
	JWTSecret string

	// Google sign-in is offered when both the client id and secret are set.
	GoogleClientID     string
	GoogleClientSecret string
	// PublicURL is where Google sends people back to, as the browser reaches this server.
	PublicURL string
}

func (c Config) DatabasePath() string { return filepath.Join(c.DataDir, "reader.db") }
func (c Config) FilesDir() string     { return filepath.Join(c.DataDir, "files") }

// Load reads configuration from the environment, falling back to sensible defaults.
func Load() Config {
	addr := env("READER_ADDR", ":8080")
	return Config{
		Addr:      addr,
		DataDir:   env("READER_DATA_DIR", "./data"),
		JWTSecret: env("READER_JWT_SECRET", "dev-secret-change-me"),

		GoogleClientID:     env("READER_GOOGLE_CLIENT_ID", ""),
		GoogleClientSecret: env("READER_GOOGLE_CLIENT_SECRET", ""),
		PublicURL:          env("READER_PUBLIC_URL", "http://localhost"+addr),
	}
}

func env(key, fallback string) string {
	if v, ok := os.LookupEnv(key); ok && v != "" {
		return v
	}
	return fallback
}
