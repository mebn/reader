package handlers

import (
	"net/http"
	"sort"
	"time"

	"github.com/gin-gonic/gin"

	"github.com/mebn/reader/backend/internal/auth"
	"github.com/mebn/reader/backend/internal/models"
)

// seenEvery limits how often a device's last-seen time is written.
const seenEvery = time.Minute

type deviceView struct {
	models.Device
	Current bool `json:"current"`
	Online  bool `json:"online"`
}

// CheckDevice is the token middleware's check: a device may use its token while it
// still exists. Tokens without a device predate device tracking and are let through.
func (h *Handler) CheckDevice(userID, deviceID string) bool {
	if deviceID == "" {
		return true
	}
	now := time.Now()
	res := h.db.Model(&models.Device{}).
		Where("id = ? AND user_id = ? AND last_seen_at < ?", deviceID, userID, now.Add(-seenEvery)).
		Update("last_seen_at", now)
	if res.Error == nil && res.RowsAffected > 0 {
		return true
	}
	var count int64
	h.db.Model(&models.Device{}).Where("id = ? AND user_id = ?", deviceID, userID).Count(&count)
	return count > 0
}

// Devices lists the user's signed-in devices, this one first, then the most recently active.
func (h *Handler) Devices(c *gin.Context) {
	userID, current := auth.UserID(c), auth.DeviceID(c)
	var devices []models.Device
	if err := h.db.Where("user_id = ?", userID).Find(&devices).Error; err != nil {
		serverError(c, err)
		return
	}
	online := h.hub.Online(userID)
	views := make([]deviceView, len(devices))
	for i, d := range devices {
		views[i] = deviceView{Device: d, Current: d.ID == current, Online: online[d.ID]}
	}
	sort.Slice(views, func(i, j int) bool {
		if views[i].Current != views[j].Current {
			return views[i].Current
		}
		return views[i].LastSeenAt.After(views[j].LastSeenAt)
	})
	c.JSON(http.StatusOK, views)
}

// DeleteDevice signs a device out: its token stops working and its event stream ends.
func (h *Handler) DeleteDevice(c *gin.Context) {
	userID, id := auth.UserID(c), c.Param("id")
	res := h.db.Where("id = ? AND user_id = ?", id, userID).Delete(&models.Device{})
	if res.Error != nil {
		serverError(c, res.Error)
		return
	}
	if res.RowsAffected == 0 {
		notFound(c)
		return
	}
	h.hub.Disconnect(userID, id)
	c.Status(http.StatusNoContent)
}
