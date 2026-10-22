#!/usr/bin/env bash
# Runs the apps for development: `scripts/dev.sh desktop ios` starts the sync server (or
# uses one already listening on SERVER_PORT), launches the iOS app in the simulator, runs
# the desktop app, and stops the server it started when you quit with Ctrl-C.
set -euo pipefail
cd "$(dirname "$0")/.."

SERVER_PORT="${SERVER_PORT:-8080}"
SIM="${SIM:-iPhone 17}"
# xcode-select often points at the Command Line Tools, which have no simulator tools.
if [ -z "${DEVELOPER_DIR:-}" ] && xcode-select -p | grep -q CommandLineTools; then
  export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
fi
DERIVED_DATA="${DERIVED_DATA:-$PWD/ios/build/DerivedData}"

listening() { lsof -ti "tcp:$SERVER_PORT" -sTCP:LISTEN >/dev/null; }

server=""
start_server() {
  if listening; then
    echo "› Using the server already on :$SERVER_PORT"
    return
  fi
  echo "› Starting the server on :$SERVER_PORT"
  (cd backend && READER_ADDR=":$SERVER_PORT" exec go run ./cmd/server) &
  server=$!
  # go run starts the server as a child, so stop whatever listens on the port too.
  trap 'kill $(lsof -ti "tcp:$SERVER_PORT" -sTCP:LISTEN) "$server" 2>/dev/null || true' EXIT
  trap 'exit 130' INT TERM
  until listening; do sleep 0.3; done
}

run_ios() {
  echo "› Building the iOS app for $SIM"
  local udid
  udid=$(xcrun simctl list devices available -j | python3 -c '
import json, sys
name = sys.argv[1]
print(next((d["udid"] for ds in json.load(sys.stdin)["devices"].values() for d in ds if d["name"] == name), ""))' "$SIM")
  if [ -z "$udid" ]; then
    echo "No simulator named \"$SIM\"; pick one with SIM=\"…\" (xcrun simctl list devices available)" >&2
    exit 1
  fi
  xcrun simctl boot "$udid" 2>/dev/null || true
  # Xcode 27 shows simulators in DeviceHub; older versions in Simulator.
  open -a Simulator 2>/dev/null || open "$DEVELOPER_DIR/../Applications/DeviceHub.app" 2>/dev/null || true
  (cd ios && xcodegen generate --quiet && xcodebuild -project Reader.xcodeproj -scheme Reader -destination "id=$udid" -derivedDataPath "$DERIVED_DATA" -quiet build)
  xcrun simctl install "$udid" "$DERIVED_DATA/Build/Products/Debug-iphonesimulator/Reader.app"
  xcrun simctl launch --terminate-running-process "$udid" com.mebn.reader >/dev/null
  echo "› Reader is running in the $SIM simulator"
}

run_android() {
  echo "› There's no Android app yet; skipping it."
}

start_server
desktop=false
for app in "$@"; do
  case "$app" in
    desktop) desktop=true ;;
    ios) run_ios ;;
    android) run_android ;;
    *) echo "Unknown app: $app (desktop, ios, android)" >&2; exit 1 ;;
  esac
done

# The desktop app runs in the foreground; otherwise the server does, until Ctrl-C.
if $desktop; then
  (cd desktop && wails3 dev)
elif [ -n "$server" ]; then
  echo "› Ctrl-C stops the server"
  wait "$server"
fi
