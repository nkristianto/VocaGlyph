package main

import (
	_ "embed"

	"github.com/getlantern/systray"
)

//go:embed assets/icon-template.png
var iconBytes []byte

// StartSystray launches the system-tray icon in a background goroutine.
// It must be called AFTER Wails startup() fires so the Cocoa run loop is
// already running — calling it earlier causes a deadlock.
func StartSystray(app *App) {
	go systray.Run(
		func() { onSystrayReady(app) },
		func() { /* onExit — nothing to clean up */ },
	)
}

func onSystrayReady(app *App) {
	HideFromDock() // runs on Cocoa thread — safe to call NSApp here
	systray.SetTemplateIcon(iconBytes, iconBytes)
	systray.SetTooltip("voice-to-text — click to show")

	mToggle := systray.AddMenuItem("Show / Hide", "Toggle the voice-to-text window")
	systray.AddSeparator()
	mQuit := systray.AddMenuItem("Quit voice-to-text", "Exit the application")

	go func() {
		for {
			select {
			case <-mToggle.ClickedCh:
				app.ToggleWindow()
			case <-mQuit.ClickedCh:
				systray.Quit()
				app.Quit()
				return
			}
		}
	}()
}
