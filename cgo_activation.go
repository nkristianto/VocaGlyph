package main

/*
#cgo CFLAGS: -x objective-c
#cgo LDFLAGS: -framework AppKit
#import <AppKit/AppKit.h>

// hideFromDock sets the process activation policy to Accessory,
// which removes the Dock icon and Task Switcher entry.
// Safe to call only after the Cocoa run loop is running (i.e., from startup()).
void hideFromDock() {
    if ([NSApp isRunning]) {
        [NSApp setActivationPolicy:NSApplicationActivationPolicyAccessory];
    }
}
*/
import "C"

import "log"

// HideFromDock removes the app's Dock icon at runtime.
// No-op if called before the Cocoa run loop (e.g. in tests).
func HideFromDock() {
	defer func() {
		if r := recover(); r != nil {
			log.Printf("cgo_activation: HideFromDock skipped (no run loop): %v", r)
		}
	}()
	C.hideFromDock()
}
