#!/bin/bash
# Builds Tidy and wraps the binary in a signed .app bundle at build/Tidy.app.
# Usage: scripts/bundle.sh [debug|release]   (default: release)
set -euo pipefail
cd "$(dirname "$0")/.."

CONFIG="${1:-release}"
swift build -c "$CONFIG"
BIN_DIR="$(swift build -c "$CONFIG" --show-bin-path)"

APP="build/Tidy.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/Tidy" "$APP/Contents/MacOS/Tidy"
cp Resources/Info.plist "$APP/Contents/Info.plist"

# Ad-hoc signature so macOS remembers the Photos / folder permissions you grant.
codesign --force --sign - "$APP"
echo "Built $APP"
