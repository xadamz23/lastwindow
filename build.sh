#!/bin/bash
# Builds LastWindow.app, signs it ad-hoc, and installs it to ~/Applications.
set -euo pipefail
cd "$(dirname "$0")"

swift build -c release
BIN="$(swift build -c release --show-bin-path)/LastWindow"

APP=build/LastWindow.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp "$BIN" "$APP/Contents/MacOS/"
cp Resources/Info.plist "$APP/Contents/"
codesign --force --sign - "$APP"

pkill -x LastWindow || true
rm -rf ~/Applications/LastWindow.app
mkdir -p ~/Applications
cp -R "$APP" ~/Applications/

# An ad-hoc signature changes every build, which silently invalidates the old
# Accessibility grant. Clear it so macOS prompts again instead.
tccutil reset Accessibility com.adamstahl.LastWindow >/dev/null 2>&1 || true

echo "Installed ~/Applications/LastWindow.app — run: open ~/Applications/LastWindow.app"
