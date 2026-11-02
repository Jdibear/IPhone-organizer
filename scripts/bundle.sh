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

# macOS ties Photos / folder permissions to the signature. A real certificate keeps them across rebuilds;
# an ad-hoc signature changes every build, so macOS would ask again each time.
IDENTITY="$(security find-identity -v -p codesigning | awk -F'"' '/Apple Development/ { print $2; exit }')"
codesign --force --sign "${IDENTITY:--}" "$APP"
echo "Built $APP"
