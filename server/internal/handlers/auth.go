package handlers

import (
	"errors"
	"net/http"
	"net/mail"
	"strings"

	"github.com/gin-gonic/gin"
	"github.com/google/uuid"
	"gorm.io/gorm"

	"github.com/mebn/reader/server/internal/auth"
	"github.com/mebn/reader/server/internal/models"
)

type credentials struct {
	Email    string `json:"email" binding:"required"`
	Password string `json:"password" binding:"required"`
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
	h.respondSession(c, http.StatusCreated, user)
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
	h.respondSession(c, http.StatusOK, user)
}

func (h *Handler) Me(c *gin.Context) {
	var user models.User
	if err := h.db.Take(&user, "id = ?", auth.UserID(c)).Error; err != nil {
		c.AbortWithStatusJSON(http.StatusUnauthorized, gin.H{"error": "unauthorized"})
		return
	}
	c.JSON(http.StatusOK, user)
}

func (h *Handler) respondSession(c *gin.Context, status int, user models.User) {
	token, err := h.tokens.Issue(user.ID)
	if err != nil {
		serverError(c, err)
		return
	}
	c.JSON(status, session{Token: token, User: user})
}
