#!/bin/zsh
set -euo pipefail

PROJECT_DIR="${0:A:h:h}"
cd "$PROJECT_DIR"

swift build -c release --product AutoMAA
swift build -c release --product AutoMAARunner
swift build -c release --product AutoMAAUpdater
BIN_DIR="$(swift build -c release --show-bin-path)"
APP_DIR="$PROJECT_DIR/.build/AutoMAA.app"
BUILD_VERSION="$(/bin/date -u +%Y%m%d%H%M%S)"
LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"

/bin/mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"
/bin/cp "$BIN_DIR/AutoMAA" "$APP_DIR/Contents/MacOS/AutoMAA"
/bin/cp "$BIN_DIR/AutoMAARunner" "$APP_DIR/Contents/MacOS/AutoMAARunner"
/bin/cp "$BIN_DIR/AutoMAAUpdater" "$APP_DIR/Contents/MacOS/AutoMAAUpdater"
/bin/cp "$PROJECT_DIR/scripts/Info.plist" "$APP_DIR/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $BUILD_VERSION" "$APP_DIR/Contents/Info.plist"
/bin/cp "$PROJECT_DIR/Assets/AutoMAA.icns" "$APP_DIR/Contents/Resources/AutoMAA.icns"
/usr/bin/codesign --force --deep --sign - "$APP_DIR"
/usr/bin/touch "$APP_DIR"
"$LSREGISTER" -f "$APP_DIR"

echo "$APP_DIR"
