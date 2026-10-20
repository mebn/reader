package handlers

import (
	"errors"
	"net/http"
	"time"

	"github.com/gin-gonic/gin"
	"gorm.io/gorm"

	"github.com/mebn/reader/backend/internal/auth"
	"github.com/mebn/reader/backend/internal/models"
)

// DeleteFolder tombstones a folder and moves its contents to the parent folder.
func (h *Handler) DeleteFolder(c *gin.Context) {
	userID, id := auth.UserID(c), c.Param("id")
	now := time.Now().UnixMilli()

	err := h.write(userID, func(tx *gorm.DB) error {
		var folder models.Folder
		if err := tx.Take(&folder, "user_id = ? AND id = ?", userID, id).Error; err != nil {
			return err
		}

		var books []models.Book
		if err := tx.Find(&books, "user_id = ? AND folder_id = ? AND deleted = ?", userID, id, false).Error; err != nil {
			return err
		}
		for i := range books {
			books[i].FolderID, books[i].ModifiedAt = folder.ParentID, now
			if _, err := saveLWW(tx, h.clock, &books[i]); err != nil {
				return err
			}
		}

		var children []models.Folder
		if err := tx.Find(&children, "user_id = ? AND parent_id = ? AND deleted = ?", userID, id, false).Error; err != nil {
			return err
		}
		for i := range children {
			children[i].ParentID, children[i].ModifiedAt = folder.ParentID, now
			if _, err := saveLWW(tx, h.clock, &children[i]); err != nil {
				return err
			}
		}

		folder.Deleted, folder.ModifiedAt = true, now
		_, err := saveLWW(tx, h.clock, &folder)
		return err
	})
	if errors.Is(err, gorm.ErrRecordNotFound) {
		notFound(c)
		return
	}
	if err != nil {
		serverError(c, err)
		return
	}
	c.Status(http.StatusNoContent)
}
