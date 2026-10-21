// Package files serves book data to the webview: dropped local files and a
// disk cache of books and covers downloaded from the sync server.
package files

import (
	"crypto/rand"
	"encoding/hex"
	"fmt"
	"io"
	"net/http"
	"os"
	"path/filepath"
	"regexp"
	"strings"
	"sync"

	"github.com/mebn/reader/desktop/internal/session"
)

const (
	localPrefix = "/local/"
	bookPrefix  = "/cache/books/"
	coverPrefix = "/cache/covers/"
)

var safeID = regexp.MustCompile(`^[A-Za-z0-9-]{1,64}$`)

type DroppedFile struct {
	Name string `json:"name"`
	URL  string `json:"url"`
}

type Server struct {
	dir      string
	sessions *session.Service
	client   *http.Client

	mu    sync.RWMutex
	local map[string]string

	// One download per file at a time: a book opened twice at once (or its window and
	// the library) would otherwise race to rename onto the same path, which Windows refuses.
	dlMu sync.Mutex
	dl   map[string]*sync.Mutex
}

func NewServer(cacheDir string, sessions *session.Service) *Server {
	return &Server{dir: cacheDir, sessions: sessions, client: &http.Client{}, local: map[string]string{}, dl: map[string]*sync.Mutex{}}
}

// Register makes local paths readable by the webview and returns their URLs.
// Only explicitly registered paths are ever served.
func (s *Server) Register(paths []string) []DroppedFile {
	s.mu.Lock()
	defer s.mu.Unlock()
	out := make([]DroppedFile, 0, len(paths))
	for _, p := range paths {
		if info, err := os.Stat(p); err != nil || info.IsDir() {
			continue
		}
		key := randomKey()
		s.local[key] = p
		out = append(out, DroppedFile{Name: filepath.Base(p), URL: localPrefix + key})
	}
	return out
}

// Middleware intercepts file routes before the frontend asset handler.
func (s *Server) Middleware(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		switch path := r.URL.Path; {
		case strings.HasPrefix(path, localPrefix):
			s.serveLocal(w, r, strings.TrimPrefix(path, localPrefix))
		case strings.HasPrefix(path, bookPrefix):
			s.serveCached(w, r, "books", strings.TrimPrefix(path, bookPrefix), "file")
		case strings.HasPrefix(path, coverPrefix):
			s.serveCached(w, r, "covers", strings.TrimPrefix(path, coverPrefix), "cover")
		default:
			next.ServeHTTP(w, r)
		}
	})
}

func (s *Server) serveLocal(w http.ResponseWriter, r *http.Request, key string) {
	s.mu.RLock()
	path, ok := s.local[key]
	s.mu.RUnlock()
	if !ok {
		http.NotFound(w, r)
		return
	}
	http.ServeFile(w, r, path)
}

// serveCached serves a book or cover from disk, downloading it on first use.
// Covers carry a version query so a replaced cover is fetched again.
func (s *Server) serveCached(w http.ResponseWriter, r *http.Request, kind, id, remote string) {
	if !safeID.MatchString(id) {
		http.NotFound(w, r)
		return
	}
	name := id
	if v := r.URL.Query().Get("v"); safeID.MatchString(v) {
		name += "-" + v
	}
	path := filepath.Join(s.dir, kind, name)

	if err := s.ensure(path, fmt.Sprintf("/api/books/%s/%s", id, remote)); err != nil {
		http.Error(w, err.Error(), http.StatusBadGateway)
		return
	}
	w.Header().Set("Cache-Control", "no-cache")
	http.ServeFile(w, r, path)
}

// ensure downloads endpoint to path unless it is already there.
func (s *Server) ensure(path, endpoint string) error {
	s.dlMu.Lock()
	lock, ok := s.dl[path]
	if !ok {
		lock = &sync.Mutex{}
		s.dl[path] = lock
	}
	s.dlMu.Unlock()

	lock.Lock()
	defer lock.Unlock()
	if _, err := os.Stat(path); err == nil {
		return nil
	}
	return s.download(endpoint, path)
}

func (s *Server) download(endpoint, dst string) error {
	sess := s.sessions.Get()
	req, err := http.NewRequest(http.MethodGet, strings.TrimRight(sess.ServerURL, "/")+endpoint, nil)
	if err != nil {
		return err
	}
	req.Header.Set("Authorization", "Bearer "+sess.Token)

	res, err := s.client.Do(req)
	if err != nil {
		return err
	}
	defer res.Body.Close()
	if res.StatusCode != http.StatusOK {
		return fmt.Errorf("server returned %s", res.Status)
	}

	if err := os.MkdirAll(filepath.Dir(dst), 0o755); err != nil {
		return err
	}
	tmp, err := os.CreateTemp(filepath.Dir(dst), ".dl-*")
	if err != nil {
		return err
	}
	defer os.Remove(tmp.Name())
	_, err = io.Copy(tmp, res.Body)
	if cerr := tmp.Close(); err == nil {
		err = cerr
	}
	if err != nil {
		return err
	}
	return os.Rename(tmp.Name(), dst)
}

func randomKey() string {
	b := make([]byte, 16)
	_, _ = rand.Read(b)
	return hex.EncodeToString(b)
}
