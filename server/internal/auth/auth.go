package auth

import (
	"errors"
	"net/http"
	"strings"
	"time"

	"github.com/gin-gonic/gin"
	"github.com/golang-jwt/jwt/v5"
	"golang.org/x/crypto/bcrypt"
)

const (
	userIDKey   = "userID"
	deviceIDKey = "deviceID"
)

// DeviceCheck reports whether a device may still use its token, and records that it
// was seen. Tokens issued before devices were tracked carry no device and pass.
type DeviceCheck func(userID, deviceID string) bool

type Tokens struct {
	secret []byte
	ttl    time.Duration
}

func NewTokens(secret string) *Tokens {
	return &Tokens{secret: []byte(secret), ttl: 90 * 24 * time.Hour}
}

// Issue signs a token for a user on one device; the device ID goes in the token's ID.
func (t *Tokens) Issue(userID, deviceID string) (string, error) {
	claims := jwt.RegisteredClaims{
		Subject:   userID,
		ID:        deviceID,
		IssuedAt:  jwt.NewNumericDate(time.Now()),
		ExpiresAt: jwt.NewNumericDate(time.Now().Add(t.ttl)),
	}
	return jwt.NewWithClaims(jwt.SigningMethodHS256, claims).SignedString(t.secret)
}

// Parse returns the user and device a token was issued to.
func (t *Tokens) Parse(token string) (userID, deviceID string, err error) {
	claims := &jwt.RegisteredClaims{}
	_, err = jwt.ParseWithClaims(token, claims, func(*jwt.Token) (any, error) { return t.secret, nil },
		jwt.WithValidMethods([]string{jwt.SigningMethodHS256.Alg()}))
	if err != nil {
		return "", "", err
	}
	if claims.Subject == "" {
		return "", "", errors.New("missing subject")
	}
	return claims.Subject, claims.ID, nil
}

// Middleware accepts a bearer token, or a `token` query parameter for clients
// that cannot set headers (EventSource, <img>).
func (t *Tokens) Middleware(check DeviceCheck) gin.HandlerFunc {
	return func(c *gin.Context) {
		token := strings.TrimPrefix(c.GetHeader("Authorization"), "Bearer ")
		if token == "" {
			token = c.Query("token")
		}
		userID, deviceID, err := t.Parse(token)
		if err != nil || !check(userID, deviceID) {
			c.AbortWithStatusJSON(http.StatusUnauthorized, gin.H{"error": "unauthorized"})
			return
		}
		c.Set(userIDKey, userID)
		c.Set(deviceIDKey, deviceID)
		c.Next()
	}
}

func UserID(c *gin.Context) string { return c.GetString(userIDKey) }

// DeviceID is the signed-in device, or "" for a token from before devices were tracked.
func DeviceID(c *gin.Context) string { return c.GetString(deviceIDKey) }

func HashPassword(password string) (string, error) {
	hash, err := bcrypt.GenerateFromPassword([]byte(password), bcrypt.DefaultCost)
	return string(hash), err
}

func CheckPassword(hash, password string) bool {
	return bcrypt.CompareHashAndPassword([]byte(hash), []byte(password)) == nil
}
