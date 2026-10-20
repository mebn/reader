package session

import (
	"encoding/json"
	"errors"
	"os"
	"path/filepath"
	"sync"
)

type Session struct {
	ServerURL string `json:"serverUrl"`
	Token     string `json:"token"`
	Email     string `json:"email"`
}

// Service persists the signed-in session so every window and restart shares it.
type Service struct {
	mu      sync.RWMutex
	path    string
	current Session
}

func NewService(dir string) *Service {
	s := &Service{path: filepath.Join(dir, "session.json")}
	if data, err := os.ReadFile(s.path); err == nil {
		_ = json.Unmarshal(data, &s.current)
	}
	return s
}

func (s *Service) Get() Session {
	s.mu.RLock()
	defer s.mu.RUnlock()
	return s.current
}

func (s *Service) Set(session Session) error {
	if session.ServerURL == "" {
		return errors.New("server url is required")
	}
	s.mu.Lock()
	defer s.mu.Unlock()
	s.current = session
	return s.save()
}

func (s *Service) Clear() error {
	s.mu.Lock()
	defer s.mu.Unlock()
	s.current = Session{ServerURL: s.current.ServerURL}
	return s.save()
}

func (s *Service) save() error {
	if err := os.MkdirAll(filepath.Dir(s.path), 0o700); err != nil {
		return err
	}
	data, err := json.Marshal(s.current)
	if err != nil {
		return err
	}
	return os.WriteFile(s.path, data, 0o600)
}
