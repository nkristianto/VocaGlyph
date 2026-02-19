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
	app.SetHotkeyService(NewHotkeyService())
	app.SetAudioService(NewAudioService())

	// Load config → pick model path from persisted preference.
	cfgSvc := NewConfigService()
	app.SetConfigService(cfgSvc)
	cfg := cfgSvc.Load()
	home, _ := os.UserHomeDir()
	modelPath := home + "/.voice-to-text/models/ggml-" + cfg.Model + ".en.bin"
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
		Title:  "voice-to-text",
		Width:  360,
		Height: 420,
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
	})

	if err != nil {
		log.Fatalf("fatal: wails.Run failed: %v", err)
	}
}
