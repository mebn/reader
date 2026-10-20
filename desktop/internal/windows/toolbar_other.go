//go:build !darwin

package windows

import "unsafe"

func setToolbarVisible(unsafe.Pointer, bool) {}
