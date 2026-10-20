package storage

import (
	"crypto/sha256"
	"encoding/hex"
	"errors"
	"io"
	"os"
	"path/filepath"
	"regexp"
)

var safeID = regexp.MustCompile(`^[A-Za-z0-9-]{1,64}$`)

// Store keeps book files and covers on disk, namespaced per user.
type Store struct {
	root string
}

func New(root string) (*Store, error) {
	return &Store{root: root}, os.MkdirAll(root, 0o755)
}

func (s *Store) BookPath(userID, bookID string) string  { return s.path(userID, bookID, "book") }
func (s *Store) CoverPath(userID, bookID string) string { return s.path(userID, bookID, "cover") }

func (s *Store) path(userID, bookID, kind string) string {
	return filepath.Join(s.root, userID, bookID+"."+kind)
}

// Save writes r to the book or cover slot and returns its size and sha256.
func (s *Store) Save(dst string, r io.Reader) (int64, string, error) {
	if !safeID.MatchString(filepath.Base(filepath.Dir(dst))) {
		return 0, "", errors.New("invalid path")
	}
	if err := os.MkdirAll(filepath.Dir(dst), 0o755); err != nil {
		return 0, "", err
	}
	tmp, err := os.CreateTemp(filepath.Dir(dst), ".upload-*")
	if err != nil {
		return 0, "", err
	}
	defer os.Remove(tmp.Name())

	hash := sha256.New()
	size, err := io.Copy(io.MultiWriter(tmp, hash), r)
	if cerr := tmp.Close(); err == nil {
		err = cerr
	}
	if err != nil {
		return 0, "", err
	}
	return size, hex.EncodeToString(hash.Sum(nil)), os.Rename(tmp.Name(), dst)
}

func (s *Store) Remove(userID, bookID string) {
	_ = os.Remove(s.BookPath(userID, bookID))
	_ = os.Remove(s.CoverPath(userID, bookID))
}

func ValidID(id string) bool { return safeID.MatchString(id) }
