package main

/*
#cgo darwin CFLAGS: -x objective-c
#cgo darwin LDFLAGS: -framework ApplicationServices -framework Foundation
#include <stdlib.h>
#include "accessibility_darwin.h"
*/
import "C"
import "unsafe"

// captureContextText uses macOS Accessibility APIs via CGO to read up to 200
// characters of text immediately preceding the text cursor in the currently
// active application window. Returns an empty string if permission is missing
// or no text field is focused.
func captureContextText() string {
	cstr := C.get_active_context_text(200)
	if cstr != nil {
		defer C.free(unsafe.Pointer(cstr))
		return C.GoString(cstr)
	}
	return ""
}
