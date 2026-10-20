package handlers

import (
	"errors"
	"net/http"
	"net/mail"
	"strings"
	"time"

	"github.com/gin-gonic/gin"
	"github.com/google/uuid"
	"gorm.io/gorm"

	"github.com/mebn/reader/server/internal/auth"
	"github.com/mebn/reader/server/internal/models"
)

type credentials struct {
	Email    string     `json:"email" binding:"required"`
	Password string     `json:"password" binding:"required"`
	Device   deviceInfo `json:"device"`
}

// deviceInfo is how a client describes itself when signing in.
type deviceInfo struct {
	Name     string `json:"name"`
	Platform string `json:"platform"`
}

func (cr *credentials) normalize() error {
	cr.Email = strings.ToLower(strings.TrimSpace(cr.Email))
	if _, err := mail.ParseAddress(cr.Email); err != nil {
		return errors.New("invalid email")
	}
	return nil
}

type session struct {
	Token string      `json:"token"`
	User  models.User `json:"user"`
}

func (h *Handler) Register(c *gin.Context) {
	var cr credentials
	if err := c.ShouldBindJSON(&cr); err != nil {
		badRequest(c, err)
		return
	}
	if err := cr.normalize(); err != nil {
		badRequest(c, err)
		return
	}
	if len(cr.Password) < 8 {
		badRequest(c, errors.New("password must be at least 8 characters"))
		return
	}

	hash, err := auth.HashPassword(cr.Password)
	if err != nil {
		serverError(c, err)
		return
	}
	user := models.User{ID: uuid.NewString(), Email: cr.Email, PasswordHash: hash}
	if err := h.db.Create(&user).Error; err != nil {
		if errors.Is(err, gorm.ErrDuplicatedKey) || strings.Contains(err.Error(), "UNIQUE") {
			c.AbortWithStatusJSON(http.StatusConflict, gin.H{"error": "email already registered"})
			return
		}
		serverError(c, err)
		return
	}
	h.respondSession(c, http.StatusCreated, user, cr.Device)
}

func (h *Handler) Login(c *gin.Context) {
	var cr credentials
	if err := c.ShouldBindJSON(&cr); err != nil {
		badRequest(c, err)
		return
	}
	_ = cr.normalize()

	var user models.User
	if err := h.db.Where("email = ?", cr.Email).Take(&user).Error; err != nil || !auth.CheckPassword(user.PasswordHash, cr.Password) {
		c.AbortWithStatusJSON(http.StatusUnauthorized, gin.H{"error": "wrong email or password"})
		return
	}
	h.respondSession(c, http.StatusOK, user, cr.Device)
}

func (h *Handler) Me(c *gin.Context) {
	var user models.User
	if err := h.db.Take(&user, "id = ?", auth.UserID(c)).Error; err != nil {
		c.AbortWithStatusJSON(http.StatusUnauthorized, gin.H{"error": "unauthorized"})
		return
	}
	c.JSON(http.StatusOK, user)
}

// respondSession registers the signing-in device and answers with a token bound to it.
func (h *Handler) respondSession(c *gin.Context, status int, user models.User, info deviceInfo) {
	device := models.Device{
		ID:         uuid.NewString(),
		UserID:     user.ID,
		Name:       clip(strings.TrimSpace(info.Name), 80),
		Platform:   clip(strings.TrimSpace(info.Platform), 40),
		LastSeenAt: time.Now(),
	}
	if device.Name == "" {
		device.Name = "Unknown device"
	}
	if err := h.db.Create(&device).Error; err != nil {
		serverError(c, err)
		return
	}
	token, err := h.tokens.Issue(user.ID, device.ID)
	if err != nil {
		serverError(c, err)
		return
	}
	c.JSON(status, session{Token: token, User: user})
}

// RegisterDevice gives a token from before devices were tracked a device of its own,
// answering with a new token bound to it.
func (h *Handler) RegisterDevice(c *gin.Context) {
	var info deviceInfo
	if err := c.ShouldBindJSON(&info); err != nil {
		badRequest(c, err)
		return
	}
	var user models.User
	if err := h.db.Take(&user, "id = ?", auth.UserID(c)).Error; err != nil {
		c.AbortWithStatusJSON(http.StatusUnauthorized, gin.H{"error": "unauthorized"})
		return
	}
	h.respondSession(c, http.StatusCreated, user, info)
}

func clip(s string, n int) string {
	if r := []rune(s); len(r) > n {
		return string(r[:n])
	}
	return s
}
