package main

import (
	"context"
	"embed"
	"io"
	"log"
	"os"
	"path/filepath"

	"github.com/wailsapp/wails/v2"
	"github.com/wailsapp/wails/v2/pkg/logger"
	"github.com/wailsapp/wails/v2/pkg/menu"
	"github.com/wailsapp/wails/v2/pkg/menu/keys"
	"github.com/wailsapp/wails/v2/pkg/options"
	"github.com/wailsapp/wails/v2/pkg/options/assetserver"
	"github.com/wailsapp/wails/v2/pkg/options/mac"
)

//go:embed all:frontend/dist
var assets embed.FS

// initLogging prepares a log file in ~/.voice-to-text/app.log
// It configures the standard 'log' package to write to both stdout and this file.
func initLogging() *os.File {
	home, err := os.UserHomeDir()
	if err != nil {
		log.Printf("logging: failed to get home dir: %v", err)
		return nil
	}
	logDir := filepath.Join(home, ".voice-to-text")
	if err := os.MkdirAll(logDir, 0o755); err != nil {
		log.Printf("logging: failed to create log dir: %v", err)
		return nil
	}

	logPath := filepath.Join(logDir, "app.log")
	f, err := os.OpenFile(logPath, os.O_CREATE|os.O_WRONLY|os.O_APPEND, 0o666)
	if err != nil {
		log.Printf("logging: failed to open log file: %v", err)
		return nil
	}

	log.SetOutput(io.MultiWriter(os.Stdout, f))
	log.SetFlags(log.Ldate | log.Ltime | log.Lmicroseconds | log.Lshortfile)
	log.Println("=== Application Started ===")
	return f
}

func main() {
	logFile := initLogging()
	if logFile != nil {
		defer logFile.Close()
	}

	app := NewApp()
	app.SetHotkeyService(NewHotkeyService())
	app.SetAudioService(NewAudioService())

	// Load config → pick model path from persisted preference.
	cfgSvc := NewConfigService()
	app.SetConfigService(cfgSvc)
	cfg := cfgSvc.Load()

	// Model download/status service.
	modelSvc := NewModelService()
	app.SetModelService(modelSvc)

	// Initialize whisper service with the correct filename for the model
	modelPath := modelSvc.ModelPath(cfg.Model)
	app.SetWhisperService(NewWhisperService(modelPath))
	app.SetOutputService(NewOutputService())

	// Application menu — keyboard shortcuts while window is focused.
	appMenu := menu.NewMenu()
	fileMenu := appMenu.AddSubmenu("voice-to-text")
	fileMenu.AddText("Show / Hide", keys.CmdOrCtrl(","), func(_ *menu.CallbackData) {
		app.ToggleWindow()
	})
	fileMenu.AddSeparator()
	fileMenu.AddText("Quit", keys.CmdOrCtrl("q"), func(_ *menu.CallbackData) {
		app.Quit()
	})

	err := wails.Run(&options.App{
		Title:     "voice-to-text",
		Width:     360,
		Height:    420,
		MinWidth:  300,
		MinHeight: 380,
		AssetServer: &assetserver.Options{
			Assets: assets,
		},
		BackgroundColour: &options.RGBA{R: 18, G: 18, B: 18, A: 0},
		OnStartup:        app.startup,
		Bind:             []interface{}{app},
		Mac: &mac.Options{
			TitleBar:             mac.TitleBarHiddenInset(),
			Appearance:           mac.NSAppearanceNameDarkAqua,
			WebviewIsTransparent: true,
			WindowIsTranslucent:  true,
			About: &mac.AboutInfo{
				Title:   "voice-to-text",
				Message: "A fast, private, offline dictation tool.",
			},
		},
		StartHidden:       true, // window hidden at launch; systray icon reveals it
		HideWindowOnClose: true, // X button hides, doesn't quit
		Menu:              appMenu,
		OnBeforeClose: func(ctx context.Context) (prevent bool) {
			app.SaveWindowPosition()
			return false
		},
		Logger:   logger.NewDefaultLogger(),
		LogLevel: logger.WARNING,
	})

	if err != nil {
		log.Fatalf("fatal: wails.Run failed: %v", err)
	}
}
