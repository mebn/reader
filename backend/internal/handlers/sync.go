package handlers

import (
	"fmt"
	"io"
	"net/http"
	"strconv"
	"time"

	"github.com/gin-gonic/gin"
	"gorm.io/gorm"

	"github.com/mebn/reader/backend/internal/auth"
	"github.com/mebn/reader/backend/internal/models"
)

type changes struct {
	Version     int64               `json:"version"`
	Folders     []models.Folder     `json:"folders"`
	Books       []models.Book       `json:"books"`
	Progress    []models.Progress   `json:"progress"`
	Annotations []models.Annotation `json:"annotations"`
	Settings    []models.Setting    `json:"settings"`
}

// Sync returns every record changed after `since`. A full sync (since=0) skips tombstones.
func (h *Handler) Sync(c *gin.Context) {
	since, _ := strconv.ParseInt(c.Query("since"), 10, 64)
	userID := auth.UserID(c)

	// Read the cursor first so writes racing this request are picked up next time.
	out := changes{Version: h.cursor()}
	scope := func(db *gorm.DB) *gorm.DB {
		db = db.Where("user_id = ? AND version > ? AND version <= ?", userID, since, out.Version)
		if since == 0 {
			db = db.Where("deleted = ?", false)
		}
		return db
	}

	for _, dst := range []any{&out.Folders, &out.Books, &out.Progress, &out.Annotations, &out.Settings} {
		if err := h.db.Scopes(scope).Find(dst).Error; err != nil {
			serverError(c, err)
			return
		}
	}
	c.JSON(http.StatusOK, out)
}

// Events streams the latest version whenever this user's data changes.
func (h *Handler) Events(c *gin.Context) {
	updates, closed, unsubscribe := h.hub.Subscribe(auth.UserID(c), auth.DeviceID(c))
	defer unsubscribe()

	c.Header("Content-Type", "text/event-stream")
	c.Header("Cache-Control", "no-cache")
	c.Header("Connection", "keep-alive")
	c.Header("X-Accel-Buffering", "no")

	heartbeat := time.NewTicker(25 * time.Second)
	defer heartbeat.Stop()

	c.SSEvent("version", h.clock.Current())
	c.Writer.Flush()

	c.Stream(func(w io.Writer) bool {
		select {
		case <-c.Request.Context().Done():
			return false
		case <-closed:
			return false
		case v := <-updates:
			c.SSEvent("version", v)
		case <-heartbeat.C:
			_, _ = fmt.Fprint(w, ": ping\n\n")
		}
		return true
	})
}
