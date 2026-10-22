# Runs the apps for development. Every target starts the sync server first (or uses one
# already listening on SERVER_PORT) and stops it again when you quit with Ctrl-C.
#
#   make server          just the server
#   make desktop         server + desktop app (wails3 dev, hot reload)
#   make ios             server + iOS app in the simulator
#   make android         server + Android app in the emulator
#   make desktop-ios     server + desktop + iOS; likewise desktop-android, ios-android
#   make all             server + every app
#
# Options: SIM="iPhone 17 Pro" picks the simulator, AVD=… the Android emulator,
# SERVER_PORT=8081 the server's port.

DEV := scripts/dev.sh

.PHONY: server desktop ios android desktop-ios desktop-android ios-android all

server:
	@$(DEV)

desktop ios android:
	@$(DEV) $@

desktop-ios desktop-android ios-android:
	@$(DEV) $(subst -, ,$@)

all:
	@$(DEV) desktop ios android
