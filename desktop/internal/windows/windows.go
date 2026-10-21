package windows

import (
	"context"
	"net/url"
	"runtime"
	"sync"

	"github.com/wailsapp/wails/v3/pkg/application"
	"github.com/wailsapp/wails/v3/pkg/events"
)

const MainName = "main"

// Options returns the shared look of every window in the app.
func Options(name, title, route string) application.WebviewWindowOptions {
	return application.WebviewWindowOptions{
		Name:             name,
		Title:            title,
		Width:            1180,
		Height:           800,
		MinWidth:         420,
		MinHeight:        480,
		URL:              "/#" + route,
		BackgroundColour: application.NewRGB(250, 250, 249),
		// On Windows the header is the title bar, with the window buttons drawn by the page.
		Frameless: runtime.GOOS == "windows",
		Mac: application.MacWindow{
			TitleBar:                application.MacTitleBarHiddenInset,
			InvisibleTitleBarHeight: 54,
			Backdrop:                application.MacBackdropNormal,
		},
	}
}

// Service exposes window management to the frontend.
type Service struct {
	mu     sync.Mutex
	pinned map[string]bool
}

func NewService() *Service {
	return &Service{pinned: map[string]bool{}}
}

// OpenReader opens a book in its own window, or focuses the window already showing it.
func (s *Service) OpenReader(bookID, title string) {
	app := application.Get()
	name := "reader-" + bookID
	if w, ok := app.Window.GetByName(name); ok {
		w.Show()
		w.Focus()
		return
	}
	TrackFullscreen(app.Window.NewWithOptions(Options(name, title, "/window/read/"+url.PathEscape(bookID))))
}

// FullscreenEvent tells a window's page when it enters or leaves full screen.
const FullscreenEvent = "window:fullscreen"

// TrackFullscreen hides the toolbar while the window is full screen, and tells the page
// so its header can drop the space kept for the traffic lights.
func TrackFullscreen(w *application.WebviewWindow) {
	set := func(full bool) {
		setToolbarVisible(w.NativeWindow(), !full)
		w.EmitEvent(FullscreenEvent, full)
	}
	w.OnWindowEvent(events.Common.WindowFullscreen, func(*application.WindowEvent) { set(true) })
	w.OnWindowEvent(events.Common.WindowUnFullscreen, func(*application.WindowEvent) { set(false) })
}

// SetPinned keeps the calling window above all other windows.
func (s *Service) SetPinned(ctx context.Context, pinned bool) bool {
	w := caller(ctx)
	if w == nil {
		return false
	}
	w.SetAlwaysOnTop(pinned)
	s.mu.Lock()
	s.pinned[w.Name()] = pinned
	s.mu.Unlock()
	return pinned
}

func (s *Service) IsPinned(ctx context.Context) bool {
	if w := caller(ctx); w != nil {
		s.mu.Lock()
		defer s.mu.Unlock()
		return s.pinned[w.Name()]
	}
	return false
}

// SetWindowButtonsVisible shows or hides the calling window's traffic lights, so they
// can disappear along with the reader's toolbar.
func (s *Service) SetWindowButtonsVisible(ctx context.Context, visible bool) {
	w := caller(ctx)
	if w == nil {
		return
	}
	state := application.ButtonHidden
	if visible {
		state = application.ButtonEnabled
	}
	w.SetCloseButtonState(state)
	w.SetMinimiseButtonState(state)
	w.SetMaximiseButtonState(state)
}

func (s *Service) SetTitle(ctx context.Context, title string) {
	if w := caller(ctx); w != nil {
		w.SetTitle(title)
	}
}

func (s *Service) Close(ctx context.Context) {
	if w := caller(ctx); w != nil {
		w.Close()
	}
}

func (s *Service) Platform() string { return runtime.GOOS }

func caller(ctx context.Context) application.Window {
	w, _ := ctx.Value(application.WindowKey).(application.Window)
	return w
}
