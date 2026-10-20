//go:build darwin

package windows

/*
#cgo CFLAGS: -x objective-c
#cgo LDFLAGS: -framework Cocoa
#import <Cocoa/Cocoa.h>

static void setToolbarVisible(void *window, int visible) {
	NSWindow *w = (__bridge NSWindow *)window;
	dispatch_async(dispatch_get_main_queue(), ^{
		w.toolbar.visible = visible ? YES : NO;
	});
}
*/
import "C"

import "unsafe"

// setToolbarVisible shows or hides the window's (empty) toolbar, which only exists to
// inset the traffic lights. In full screen macOS would slide it down as a grey strip.
func setToolbarVisible(window unsafe.Pointer, visible bool) {
	if window == nil {
		return
	}
	v := C.int(0)
	if visible {
		v = 1
	}
	C.setToolbarVisible(window, v)
}
