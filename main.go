package main

import (
	"embed"
	"log"

	"github.com/wailsapp/wails/v2"
	"github.com/wailsapp/wails/v2/pkg/menu"
	"github.com/wailsapp/wails/v2/pkg/menu/keys"
	"github.com/wailsapp/wails/v2/pkg/options"
	"github.com/wailsapp/wails/v2/pkg/options/assetserver"
	"github.com/wailsapp/wails/v2/pkg/options/mac"
)

//go:embed all:frontend/dist
var assets embed.FS

func main() {
	app := NewApp()

	// Build system tray menu.
	// Callbacks use app.ShowWindow() and app.Quit() — safe accessor methods
	// that guard against nil context if called before startup() completes.
	appMenu := menu.NewMenu()
	appMenu.Append(menu.Text("🎙 voice-to-text", nil, nil))
	appMenu.Append(menu.Separator())
	appMenu.Append(menu.Text("Ready to dictate", nil, nil))
	appMenu.Append(menu.Separator())
	appMenu.Append(menu.Text("Settings", keys.CmdOrCtrl(","), func(_ *menu.CallbackData) {
		app.ShowWindow()
	}))
	appMenu.Append(menu.Separator())
	appMenu.Append(menu.Text("Quit", keys.CmdOrCtrl("q"), func(_ *menu.CallbackData) {
		app.Quit()
	}))

	err := wails.Run(&options.App{
		Title:  "voice-to-text",
		Width:  480,
		Height: 600,
		AssetServer: &assetserver.Options{
			Assets: assets,
		},
		BackgroundColour: &options.RGBA{R: 18, G: 18, B: 18, A: 0}, // A:0 — let macOS blur be the background (L1 fix)
		OnStartup:        app.startup,
		Bind: []interface{}{
			app,
		},
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
		StartHidden:       true,
		HideWindowOnClose: true,
		Menu:              appMenu,
	})

	if err != nil {
		log.Fatalf("fatal: wails.Run failed: %v", err) // M1 fix: structured fatal log with exit code
	}
}
