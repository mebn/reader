package server

import (
	"net/http"

	"github.com/gin-gonic/gin"

	"github.com/mebn/reader/backend/internal/auth"
	"github.com/mebn/reader/backend/internal/handlers"
	"github.com/mebn/reader/backend/internal/models"
)

func NewRouter(h *handlers.Handler, tokens *auth.Tokens) *gin.Engine {
	r := gin.New()
	r.Use(gin.Logger(), gin.Recovery(), cors())
	r.MaxMultipartMemory = 16 << 20

	r.GET("/health", func(c *gin.Context) { c.Status(http.StatusOK) })

	api := r.Group("/api")
	api.POST("/auth/register", h.Register)
	api.POST("/auth/login", h.Login)
	api.POST("/auth/google/start", h.GoogleStart)
	api.GET("/auth/google/callback", h.GoogleCallback)
	api.GET("/auth/google/poll", h.GooglePoll)

	authed := api.Group("", tokens.Middleware(h.CheckDevice))
	authed.GET("/me", h.Me)
	authed.POST("/auth/device", h.RegisterDevice)
	authed.GET("/devices", h.Devices)
	authed.DELETE("/devices/:id", h.DeleteDevice)
	authed.GET("/sync", h.Sync)
	authed.GET("/events", h.Events)

	authed.PUT("/folders/:id", handlers.PutRecord[models.Folder](h))
	authed.DELETE("/folders/:id", h.DeleteFolder)

	authed.POST("/books/:id", h.CreateBook)
	authed.PUT("/books/:id", h.UpdateBook)
	authed.DELETE("/books/:id", h.DeleteBook)
	authed.GET("/books/:id/file", h.BookFile)
	authed.GET("/books/:id/cover", h.BookCover)
	authed.PUT("/books/:id/cover", h.UploadCover)

	authed.PUT("/progress/:id", handlers.PutRecord[models.Progress](h))
	authed.PUT("/annotations/:id", handlers.PutRecord[models.Annotation](h))
	authed.PUT("/settings/:id", handlers.PutRecord[models.Setting](h))

	return r
}

// cors allows any origin: clients authenticate with bearer tokens, not cookies.
func cors() gin.HandlerFunc {
	return func(c *gin.Context) {
		c.Header("Access-Control-Allow-Origin", "*")
		c.Header("Access-Control-Allow-Headers", "Authorization, Content-Type")
		c.Header("Access-Control-Allow-Methods", "GET, POST, PUT, DELETE, OPTIONS")
		if c.Request.Method == http.MethodOptions {
			c.AbortWithStatus(http.StatusNoContent)
			return
		}
		c.Next()
	}
}
