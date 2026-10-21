package handlers

import (
	"context"
	"crypto/rand"
	"crypto/subtle"
	"encoding/base64"
	"errors"
	"html/template"
	"net/http"
	"strings"
	"sync"
	"time"

	"github.com/coreos/go-oidc/v3/oidc"
	"github.com/gin-gonic/gin"
	"github.com/google/uuid"
	"golang.org/x/oauth2"
	"golang.org/x/oauth2/google"
	"gorm.io/gorm"

	"github.com/mebn/reader/backend/internal/models"
)

// GoogleConfig holds the OAuth client from the Google Cloud console. RedirectURL must be
// listed there as an authorised redirect URI.
type GoogleConfig struct {
	ClientID     string
	ClientSecret string
	RedirectURL  string
}

const googleAttemptTTL = 10 * time.Minute

// googleAuth runs Google sign-in for apps that can't receive the redirect themselves.
//
// The app asks the server to start, opens the returned Google URL in the system browser,
// and polls with a secret only it knows. Google sends the browser back to the server's
// callback, which verifies the ID token and parks a session for the poll to collect.
type googleAuth struct {
	oauth *oauth2.Config

	mu       sync.Mutex
	verifier *oidc.IDTokenVerifier // set on first use, so the server starts without internet
	attempts map[string]*googleAttempt
}

type googleAttempt struct {
	secret   string
	pkce     string
	device   deviceInfo
	expires  time.Time
	finished bool
	result   session
	err      string
}

func newGoogleAuth(cfg GoogleConfig) *googleAuth {
	if cfg.ClientID == "" || cfg.ClientSecret == "" {
		return nil
	}
	return &googleAuth{
		oauth: &oauth2.Config{
			ClientID:     cfg.ClientID,
			ClientSecret: cfg.ClientSecret,
			RedirectURL:  cfg.RedirectURL,
			Endpoint:     google.Endpoint,
			Scopes:       []string{oidc.ScopeOpenID, "email", "profile"},
		},
		attempts: map[string]*googleAttempt{},
	}
}

func (g *googleAuth) idVerifier(ctx context.Context) (*oidc.IDTokenVerifier, error) {
	g.mu.Lock()
	defer g.mu.Unlock()
	if g.verifier == nil {
		provider, err := oidc.NewProvider(ctx, "https://accounts.google.com")
		if err != nil {
			return nil, err
		}
		g.verifier = provider.Verifier(&oidc.Config{ClientID: g.oauth.ClientID})
	}
	return g.verifier, nil
}

func (h *Handler) GoogleStart(c *gin.Context) {
	g := h.google
	if g == nil {
		c.AbortWithStatusJSON(http.StatusNotImplemented, gin.H{"error": "Google sign-in isn't set up on this server"})
		return
	}
	var req struct {
		Device deviceInfo `json:"device"`
	}
	_ = c.ShouldBindJSON(&req)

	state, secret, pkce := randomToken(), randomToken(), oauth2.GenerateVerifier()

	g.mu.Lock()
	now := time.Now()
	for k, a := range g.attempts {
		if now.After(a.expires) {
			delete(g.attempts, k)
		}
	}
	g.attempts[state] = &googleAttempt{secret: secret, pkce: pkce, device: req.Device, expires: now.Add(googleAttemptTTL)}
	g.mu.Unlock()

	url := g.oauth.AuthCodeURL(state, oauth2.S256ChallengeOption(pkce), oauth2.SetAuthURLParam("prompt", "select_account"))
	c.JSON(http.StatusOK, gin.H{"url": url, "state": state, "secret": secret})
}

// GoogleCallback is where Google sends the browser back. It answers with a page for
// the person, and leaves the session for the app to collect.
func (h *Handler) GoogleCallback(c *gin.Context) {
	g := h.google
	if g == nil {
		c.Status(http.StatusNotFound)
		return
	}
	state := c.Query("state")

	g.mu.Lock()
	attempt, ok := g.attempts[state]
	if ok && (attempt.finished || time.Now().After(attempt.expires)) {
		ok = false
	}
	g.mu.Unlock()
	if !ok {
		renderGoogleResult(c, http.StatusBadRequest, "This sign-in link has expired. Go back to Reader and try again.")
		return
	}

	user, err := h.googleUser(c, attempt)
	g.mu.Lock()
	attempt.finished = true
	if err == nil {
		attempt.result, err = h.newSession(user, attempt.device)
	}
	if err != nil {
		attempt.err = friendly(err)
	}
	g.mu.Unlock()

	if err != nil {
		_ = c.Error(err)
		renderGoogleResult(c, http.StatusBadRequest, attempt.err)
		return
	}
	renderGoogleResult(c, http.StatusOK, "")
}

// googleUser exchanges the callback's code and finds or creates the account behind it.
func (h *Handler) googleUser(c *gin.Context, attempt *googleAttempt) (models.User, error) {
	g := h.google
	if e := c.Query("error"); e != "" {
		return models.User{}, errSignIn("Google sign-in was cancelled")
	}
	verifier, err := g.idVerifier(c.Request.Context())
	if err != nil {
		return models.User{}, err
	}
	token, err := g.oauth.Exchange(c.Request.Context(), c.Query("code"), oauth2.VerifierOption(attempt.pkce))
	if err != nil {
		return models.User{}, err
	}
	raw, _ := token.Extra("id_token").(string)
	idToken, err := verifier.Verify(c.Request.Context(), raw)
	if err != nil {
		return models.User{}, err
	}
	var claims struct {
		Email         string `json:"email"`
		EmailVerified bool   `json:"email_verified"`
	}
	if err := idToken.Claims(&claims); err != nil {
		return models.User{}, err
	}
	email := strings.ToLower(strings.TrimSpace(claims.Email))
	if email == "" || !claims.EmailVerified {
		return models.User{}, errSignIn("Your Google account has no verified email")
	}
	return h.userForGoogle(idToken.Subject, email)
}

// userForGoogle finds the account for a Google id, links an existing account with the same
// verified email, or creates one. Google accounts have no password.
func (h *Handler) userForGoogle(sub, email string) (models.User, error) {
	var user models.User
	err := h.db.Where("google_id = ?", sub).Take(&user).Error
	if err == nil {
		return user, nil
	}
	if !errors.Is(err, gorm.ErrRecordNotFound) {
		return user, err
	}

	err = h.db.Where("email = ?", email).Take(&user).Error
	switch {
	case err == nil:
		user.GoogleID = &sub
		return user, h.db.Model(&user).Update("google_id", sub).Error
	case errors.Is(err, gorm.ErrRecordNotFound):
		user = models.User{ID: uuid.NewString(), Email: email, GoogleID: &sub}
		return user, h.db.Create(&user).Error
	}
	return user, err
}

// GooglePoll is how the app collects the session once the person has signed in.
func (h *Handler) GooglePoll(c *gin.Context) {
	g := h.google
	if g == nil {
		c.AbortWithStatusJSON(http.StatusNotImplemented, gin.H{"error": "Google sign-in isn't set up on this server"})
		return
	}
	state, secret := c.Query("state"), c.Query("secret")

	g.mu.Lock()
	defer g.mu.Unlock()
	attempt, ok := g.attempts[state]
	if !ok || subtle.ConstantTimeCompare([]byte(attempt.secret), []byte(secret)) != 1 || time.Now().After(attempt.expires) {
		c.AbortWithStatusJSON(http.StatusGone, gin.H{"error": "Sign-in expired. Try again."})
		return
	}
	switch {
	case !attempt.finished:
		c.JSON(http.StatusAccepted, gin.H{"status": "pending"})
	case attempt.err != "":
		delete(g.attempts, state)
		c.AbortWithStatusJSON(http.StatusBadRequest, gin.H{"error": attempt.err})
	default:
		delete(g.attempts, state)
		c.JSON(http.StatusOK, attempt.result)
	}
}

type errSignIn string

func (e errSignIn) Error() string { return string(e) }

// friendly keeps internal errors out of the page and the app.
func friendly(err error) string {
	var e errSignIn
	if errors.As(err, &e) {
		return e.Error()
	}
	return "Couldn't sign in with Google. Try again."
}

func randomToken() string {
	b := make([]byte, 32)
	_, _ = rand.Read(b)
	return base64.RawURLEncoding.EncodeToString(b)
}

var resultPage = template.Must(template.New("result").Parse(`<!doctype html>
<html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>Reader</title>
<style>
  :root { color-scheme: light dark; }
  body { margin: 0; min-height: 100vh; display: grid; place-items: center; font: 16px/1.5 system-ui, sans-serif;
         background: #faf7f0; color: #302b26; }
  main { text-align: center; padding: 24px; max-width: 360px; }
  .book { width: 64px; height: 92px; margin: 0 auto 28px; border-radius: 6px 12px 12px 6px; position: relative;
          background: linear-gradient(135deg, #f7f1e6, #e8decc); box-shadow: 0 18px 30px -12px rgba(48,43,38,.45); }
  .book::before { content: ""; position: absolute; inset: 0 auto 0 0; width: 14px; border-radius: 6px 0 0 6px; background: #d6cab5; }
  .book::after { content: ""; position: absolute; top: 0; right: 14px; width: 12px; height: 34px; background: #d9663f;
                 clip-path: polygon(0 0, 100% 0, 100% 100%, 50% 80%, 0 100%); }
  h1 { font: 600 24px Georgia, serif; margin: 0 0 8px; }
  p { margin: 0; opacity: .7; }
  @media (prefers-color-scheme: dark) { body { background: #1f1b18; color: #f1ece4; } }
</style></head>
<body><main>
  <div class="book"></div>
  {{if .Error}}<h1>Couldn’t sign in</h1><p>{{.Error}}</p>
  {{else}}<h1>You’re signed in</h1><p>You can close this tab and go back to Reader.</p>{{end}}
</main></body></html>`))

func renderGoogleResult(c *gin.Context, status int, message string) {
	c.Header("Cache-Control", "no-store")
	c.Header("Referrer-Policy", "no-referrer")
	c.Status(status)
	_ = resultPage.Execute(c.Writer, gin.H{"Error": message})
}
