package main

import (
	"embed"
	"log"
	"os"
	"path/filepath"

	"github.com/wailsapp/wails/v3/pkg/application"
	"github.com/wailsapp/wails/v3/pkg/events"

	"github.com/mebn/reader/desktop/internal/files"
	"github.com/mebn/reader/desktop/internal/session"
	"github.com/mebn/reader/desktop/internal/windows"
)

//go:embed all:frontend/dist
var assets embed.FS

const appName = "Reader"

func init() {
	application.RegisterEvent[[]files.DroppedFile]("files:dropped")
}

func main() {
	sessions := session.NewService(appDir(os.UserConfigDir))
	fileServer := files.NewServer(appDir(os.UserCacheDir), sessions)

	app := application.New(application.Options{
		Name:        appName,
		Description: "A calm place to read",
		Services: []application.Service{
			application.NewService(sessions),
			application.NewService(windows.NewService()),
		},
		Assets: application.AssetOptions{
			Handler:    application.AssetFileServerFS(assets),
			Middleware: fileServer.Middleware,
		},
		Mac: application.MacOptions{
			ApplicationShouldTerminateAfterLastWindowClosed: true,
		},
	})

	opts := windows.Options(windows.MainName, appName, "/")
	opts.EnableFileDrop = true
	mainWindow := app.Window.NewWithOptions(opts)

	mainWindow.OnWindowEvent(events.Common.WindowFilesDropped, func(e *application.WindowEvent) {
		if dropped := fileServer.Register(e.Context().DroppedFiles()); len(dropped) > 0 {
			app.Event.Emit("files:dropped", dropped)
		}
	})

	if err := app.Run(); err != nil {
		log.Fatal(err)
	}
}

func appDir(base func() (string, error)) string {
	dir, err := base()
	if err != nil {
		dir = os.TempDir()
	}
	return filepath.Join(dir, appName)
}
