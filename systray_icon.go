package main

/*
#include <stdlib.h>

// Only extern declarations here — implementation is in systray_darwin.m
// to avoid CGo preamble duplicate-symbol linker errors.
extern void dispatchSysTray(const unsigned char *pngData, int pngLen);
extern void dispatchHideFromDock(void);
extern void dispatchSetSysTrayState(int state);
*/
import "C"

import (
	_ "embed"
	"log"
	"unsafe"
)

//go:embed assets/icon-template.png
var iconBytes []byte

// goApp is set by StartSystray so the C callback can invoke Go.
var goApp *App

//export goToggleWindowCallback
func goToggleWindowCallback() {
	if goApp != nil {
		goApp.ToggleWindow()
	}
}

//export goQuitCallback
func goQuitCallback() {
	if goApp != nil {
		goApp.Quit()
	}
}

// StartSystray installs an NSStatusItem (mic icon) in the macOS right menu bar.
// All AppKit calls are dispatched to the Cocoa main thread via dispatch_async.
// ObjC implementation lives in systray_darwin.m (not in a CGo preamble)
// to avoid duplicate-symbol linker errors with Wails' AppDelegate.
func StartSystray(app *App) {
	goApp = app
	defer func() {
		if r := recover(); r != nil {
			log.Printf("systray: skipped (no Cocoa run loop): %v", r)
		}
	}()
	cBytes := C.CBytes(iconBytes)
	defer C.free(unsafe.Pointer(cBytes))
	C.dispatchSysTray((*C.uchar)(cBytes), C.int(len(iconBytes)))
	C.dispatchHideFromDock()
}

// HideFromDock is now handled inside StartSystray. No-op kept for compatibility.
func HideFromDock() {}

// SetSysTrayState updates the menu bar icon based on the current app state.
// 0 = Idle, 1 = Recording, 2 = Processing.
func SetSysTrayState(state int) {
	C.dispatchSetSysTrayState(C.int(state))
}
