package models

import "time"

type User struct {
	ID           string    `gorm:"primaryKey;size:36" json:"id"`
	Email        string    `gorm:"uniqueIndex;not null" json:"email"`
	PasswordHash string    `gorm:"not null" json:"-"`
	CreatedAt    time.Time `json:"createdAt"`
}

// Base is shared by every synced record.
//
// ModifiedAt is the client's timestamp (ms) and decides last-write-wins conflicts.
// Version is assigned by the server on every write and is the sync cursor.
type Base struct {
	UserID     string `gorm:"primaryKey;size:36" json:"-"`
	ID         string `gorm:"primaryKey;size:64" json:"id"`
	ModifiedAt int64  `json:"modifiedAt"`
	Version    int64  `gorm:"index" json:"version"`
	Deleted    bool   `json:"deleted"`
}

func (b *Base) Meta() *Base { return b }

// Syncable is implemented by every model embedding Base.
type Syncable interface {
	Meta() *Base
}

type Folder struct {
	Base
	Name     string  `json:"name"`
	ParentID *string `gorm:"size:36" json:"parentId"`
}

type Book struct {
	Base
	FolderID *string `gorm:"size:36" json:"folderId"`
	Title    string  `json:"title"`
	Author   string  `json:"author"`
	Format   string  `json:"format"`
	FileName string  `json:"fileName"`
	Size     int64   `json:"size"`
	Hash     string  `json:"hash"`
	HasCover bool    `json:"hasCover"`
	AddedAt  int64   `json:"addedAt"`
}

// Progress uses the book ID as its ID.
type Progress struct {
	Base
	Locator string  `json:"locator"`
	Percent float64 `json:"percent"`
}

type Annotation struct {
	Base
	BookID  string `gorm:"index;size:36" json:"bookId"`
	Kind    string `json:"kind"` // highlight | bookmark
	Locator string `json:"locator"`
	Text    string `json:"text"`
	Note    string `json:"note"`
	Color   string `json:"color"`
	Label   string `json:"label"`
}

// Setting uses its scope as ID: "app", "reader" (defaults) or "reader:<bookId>".
type Setting struct {
	Base
	Data string `json:"data"`
}

func All() []any {
	return []any{&User{}, &Folder{}, &Book{}, &Progress{}, &Annotation{}, &Setting{}}
}
