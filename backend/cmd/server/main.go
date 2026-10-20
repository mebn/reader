package main

import (
	"log"

	"github.com/mebn/reader/backend/internal/auth"
	"github.com/mebn/reader/backend/internal/config"
	"github.com/mebn/reader/backend/internal/database"
	"github.com/mebn/reader/backend/internal/events"
	"github.com/mebn/reader/backend/internal/handlers"
	"github.com/mebn/reader/backend/internal/server"
	"github.com/mebn/reader/backend/internal/storage"
)

func main() {
	cfg := config.Load()

	db, err := database.Open(cfg.DatabasePath())
	if err != nil {
		log.Fatalf("open database: %v", err)
	}
	store, err := storage.New(cfg.FilesDir())
	if err != nil {
		log.Fatalf("open storage: %v", err)
	}

	tokens := auth.NewTokens(cfg.JWTSecret)
	h, err := handlers.New(db, store, events.NewHub(), tokens)
	if err != nil {
		log.Fatalf("init handlers: %v", err)
	}

	log.Printf("listening on %s", cfg.Addr)
	if err := server.NewRouter(h, tokens).Run(cfg.Addr); err != nil {
		log.Fatal(err)
	}
}
