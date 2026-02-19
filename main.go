package main

import (
	"embed"
	"log"
	"os"

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
	app.SetHotkeyService(NewHotkeyService()) // inject real hotkey service
	app.SetAudioService(NewAudioService())   // inject real audio service

	// Inject whisper transcription service.
	// Model must be downloaded first: see README or Makefile.
	home, _ := os.UserHomeDir()
	modelPath := home + "/.voice-to-text/models/ggml-base.en.bin"
	app.SetWhisperService(NewWhisperService(modelPath))
	app.SetOutputService(NewOutputService()) // osascript paste + pbcopy fallback

	// Application menu (File / Edit style top-bar entries).
	// NOTE: A true clickable NSStatusItem (right-side menu bar icon) requires
	// a CGo Objective-C bridge — tracked as Story 1.2.
	// This menu provides keyboard-shortcut access to Settings and Quit
	// while the window is focused.
	appMenu := menu.NewMenu()
	fileMenu := appMenu.AddSubmenu("voice-to-text")
	fileMenu.AddText("Settings", keys.CmdOrCtrl(","), func(_ *menu.CallbackData) {
		app.ShowWindow()
	})
	fileMenu.AddSeparator()
	fileMenu.AddText("Quit", keys.CmdOrCtrl("q"), func(_ *menu.CallbackData) {
		app.Quit()
	})

	err := wails.Run(&options.App{
		Title:  "voice-to-text",
		Width:  320,
		Height: 290,
		AssetServer: &assetserver.Options{
			Assets: assets,
		},
		BackgroundColour: &options.RGBA{R: 18, G: 18, B: 18, A: 0},
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
		// Window is visible on launch during dev/Story 1.1.
		// Story 1.2 will add the native NSStatusItem via CGo so the window
		// starts hidden and is shown only via the menu bar icon.
		StartHidden:       false,
		HideWindowOnClose: true,
		Menu:              appMenu,
	})

	if err != nil {
		log.Fatalf("fatal: wails.Run failed: %v", err)
	}
}
