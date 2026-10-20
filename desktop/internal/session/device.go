package session

import (
	"os"
	"os/exec"
	"runtime"
	"strings"
)

// DeviceName is how this computer is listed among the account's devices: the name
// set in macOS Sharing settings, or the host name elsewhere.
func (s *Service) DeviceName() string {
	if runtime.GOOS == "darwin" {
		if out, err := exec.Command("scutil", "--get", "ComputerName").Output(); err == nil {
			if name := strings.TrimSpace(string(out)); name != "" {
				return name
			}
		}
	}
	if name, err := os.Hostname(); err == nil {
		return strings.TrimSuffix(name, ".local")
	}
	return ""
}
