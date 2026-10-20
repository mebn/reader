package handlers

import (
	"encoding/json"
	"errors"
	"mime/multipart"
	"net/http"
	"os"
	"time"

	"github.com/gin-gonic/gin"
	"gorm.io/gorm"

	"github.com/mebn/reader/backend/internal/auth"
	"github.com/mebn/reader/backend/internal/models"
	"github.com/mebn/reader/backend/internal/storage"
)

// bookPatch holds the fields a client may change after upload.
type bookPatch struct {
	Title      *string `json:"title"`
	Author     *string `json:"author"`
	FolderID   *string `json:"folderId"`
	Deleted    *bool   `json:"deleted"`
	ModifiedAt int64   `json:"modifiedAt"`
}

type bookUpload struct {
	bookPatch
	Format   string `json:"format"`
	FileName string `json:"fileName"`
	AddedAt  int64  `json:"addedAt"`
}

// CreateBook accepts a multipart upload with `meta` (JSON), `file` and an optional `cover`.
func (h *Handler) CreateBook(c *gin.Context) {
	userID, id := auth.UserID(c), c.Param("id")
	if !storage.ValidID(id) {
		badRequest(c, errors.New("invalid id"))
		return
	}

	var meta bookUpload
	if err := json.Unmarshal([]byte(c.PostForm("meta")), &meta); err != nil {
		badRequest(c, err)
		return
	}
	file, err := c.FormFile("file")
	if err != nil {
		badRequest(c, err)
		return
	}

	book := models.Book{
		Base:     models.Base{UserID: userID, ID: id, ModifiedAt: meta.ModifiedAt},
		Format:   meta.Format,
		FileName: meta.FileName,
		AddedAt:  meta.AddedAt,
	}
	meta.apply(&book)
	if book.AddedAt == 0 {
		book.AddedAt = time.Now().UnixMilli()
	}

	if book.Size, book.Hash, err = h.saveUpload(file, h.store.BookPath(userID, id)); err != nil {
		serverError(c, err)
		return
	}
	if cover, err := c.FormFile("cover"); err == nil {
		if _, _, err := h.saveUpload(cover, h.store.CoverPath(userID, id)); err != nil {
			serverError(c, err)
			return
		}
		book.HasCover = true
	}

	h.respondBook(c, &book)
}

func (h *Handler) UpdateBook(c *gin.Context) {
	var patch bookPatch
	if err := c.ShouldBindJSON(&patch); err != nil {
		badRequest(c, err)
		return
	}
	book, ok := h.findBook(c)
	if !ok {
		return
	}
	book.ModifiedAt = patch.ModifiedAt
	patch.apply(book)
	h.respondBook(c, book)
}

func (h *Handler) DeleteBook(c *gin.Context) {
	book, ok := h.findBook(c)
	if !ok {
		return
	}
	book.Deleted, book.ModifiedAt = true, time.Now().UnixMilli()
	h.respondBook(c, book)
}

func (h *Handler) UploadCover(c *gin.Context) {
	book, ok := h.findBook(c)
	if !ok {
		return
	}
	cover, err := c.FormFile("cover")
	if err != nil {
		badRequest(c, err)
		return
	}
	if _, _, err := h.saveUpload(cover, h.store.CoverPath(book.UserID, book.ID)); err != nil {
		serverError(c, err)
		return
	}
	book.HasCover, book.ModifiedAt = true, time.Now().UnixMilli()
	h.respondBook(c, book)
}

func (h *Handler) BookFile(c *gin.Context) {
	if book, ok := h.findBook(c); ok {
		serveFile(c, h.store.BookPath(book.UserID, book.ID))
	}
}

func (h *Handler) BookCover(c *gin.Context) {
	if book, ok := h.findBook(c); ok {
		c.Header("Cache-Control", "private, max-age=86400")
		serveFile(c, h.store.CoverPath(book.UserID, book.ID))
	}
}

func (p bookPatch) apply(b *models.Book) {
	if p.Title != nil {
		b.Title = *p.Title
	}
	if p.Author != nil {
		b.Author = *p.Author
	}
	if p.Deleted != nil {
		b.Deleted = *p.Deleted
	}
	// folderId is always sent; null moves the book to the root.
	b.FolderID = p.FolderID
}

func (h *Handler) findBook(c *gin.Context) (*models.Book, bool) {
	var book models.Book
	err := h.db.Take(&book, "user_id = ? AND id = ? AND deleted = ?", auth.UserID(c), c.Param("id"), false).Error
	if errors.Is(err, gorm.ErrRecordNotFound) {
		notFound(c)
		return nil, false
	}
	if err != nil {
		serverError(c, err)
		return nil, false
	}
	return &book, true
}

func (h *Handler) respondBook(c *gin.Context, book *models.Book) {
	var saved *models.Book
	err := h.write(book.UserID, func(tx *gorm.DB) (err error) {
		saved, err = saveLWW(tx, h.clock, book)
		return err
	})
	if err != nil {
		serverError(c, err)
		return
	}
	if saved.Deleted {
		h.store.Remove(saved.UserID, saved.ID)
	}
	c.JSON(http.StatusOK, saved)
}

func (h *Handler) saveUpload(fh *multipart.FileHeader, dst string) (int64, string, error) {
	f, err := fh.Open()
	if err != nil {
		return 0, "", err
	}
	defer f.Close()
	return h.store.Save(dst, f)
}

func serveFile(c *gin.Context, path string) {
	if _, err := os.Stat(path); err != nil {
		notFound(c)
		return
	}
	c.File(path)
}
