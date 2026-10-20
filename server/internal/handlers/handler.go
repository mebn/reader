package handlers

import (
	"net/http"
	"sync"
	"time"

	"github.com/gin-gonic/gin"
	"gorm.io/gorm"

	"github.com/mebn/reader/server/internal/auth"
	"github.com/mebn/reader/server/internal/events"
	"github.com/mebn/reader/server/internal/models"
	"github.com/mebn/reader/server/internal/storage"
)

type Handler struct {
	db     *gorm.DB
	store  *storage.Store
	hub    *events.Hub
	tokens *auth.Tokens
	clock  *clock

	// writeMu serialises writes so a sync cursor never skips an uncommitted version.
	writeMu sync.Mutex
}

// write runs fn in a transaction and notifies the user's other devices on success.
func (h *Handler) write(userID string, fn func(tx *gorm.DB) error) error {
	h.writeMu.Lock()
	err := h.db.Transaction(fn)
	h.writeMu.Unlock()
	if err == nil {
		h.hub.Publish(userID, h.clock.Current())
	}
	return err
}

// cursor returns the newest version whose writes are all committed.
func (h *Handler) cursor() int64 {
	h.writeMu.Lock()
	defer h.writeMu.Unlock()
	return h.clock.Current()
}

func New(db *gorm.DB, store *storage.Store, hub *events.Hub, tokens *auth.Tokens) (*Handler, error) {
	c, err := newClock(db)
	if err != nil {
		return nil, err
	}
	return &Handler{db: db, store: store, hub: hub, tokens: tokens, clock: c}, nil
}

// clock hands out strictly increasing versions used as the sync cursor.
type clock struct {
	mu   sync.Mutex
	last int64
}

func newClock(db *gorm.DB) (*clock, error) {
	c := &clock{}
	for _, m := range []any{&models.Folder{}, &models.Book{}, &models.Progress{}, &models.Annotation{}, &models.Setting{}} {
		var max int64
		if err := db.Model(m).Select("COALESCE(MAX(version), 0)").Scan(&max).Error; err != nil {
			return nil, err
		}
		c.last = maxInt(c.last, max)
	}
	return c, nil
}

func (c *clock) Next() int64 {
	c.mu.Lock()
	defer c.mu.Unlock()
	c.last = maxInt(c.last+1, time.Now().UnixMicro())
	return c.last
}

func (c *clock) Current() int64 {
	c.mu.Lock()
	defer c.mu.Unlock()
	return c.last
}

func maxInt(a, b int64) int64 {
	if a > b {
		return a
	}
	return b
}

// saveLWW stores rec unless the stored copy was modified later, and returns
// the record that is current afterwards.
func saveLWW[T any, P interface {
	*T
	models.Syncable
}](tx *gorm.DB, c *clock, rec P) (P, error) {
	meta := rec.Meta()
	if meta.ModifiedAt == 0 {
		meta.ModifiedAt = time.Now().UnixMilli()
	}

	existing := P(new(T))
	res := tx.Where("user_id = ? AND id = ?", meta.UserID, meta.ID).Limit(1).Find(existing)
	if res.Error != nil {
		return nil, res.Error
	}
	if res.RowsAffected > 0 && existing.Meta().ModifiedAt > meta.ModifiedAt {
		return existing, nil
	}

	meta.Version = c.Next()
	return rec, tx.Save(rec).Error
}

// PutRecord is the generic upsert endpoint for simple synced records.
func PutRecord[T any, P interface {
	*T
	models.Syncable
}](h *Handler) gin.HandlerFunc {
	return func(c *gin.Context) {
		rec := P(new(T))
		if err := c.ShouldBindJSON(rec); err != nil {
			badRequest(c, err)
			return
		}
		meta := rec.Meta()
		meta.UserID = auth.UserID(c)
		meta.ID = c.Param("id")

		var saved P
		err := h.write(meta.UserID, func(tx *gorm.DB) (err error) {
			saved, err = saveLWW[T, P](tx, h.clock, rec)
			return err
		})
		if err != nil {
			serverError(c, err)
			return
		}
		c.JSON(http.StatusOK, saved)
	}
}

func badRequest(c *gin.Context, err error) {
	c.AbortWithStatusJSON(http.StatusBadRequest, gin.H{"error": err.Error()})
}

func serverError(c *gin.Context, err error) {
	_ = c.Error(err)
	c.AbortWithStatusJSON(http.StatusInternalServerError, gin.H{"error": "internal error"})
}

func notFound(c *gin.Context) {
	c.AbortWithStatusJSON(http.StatusNotFound, gin.H{"error": "not found"})
}
