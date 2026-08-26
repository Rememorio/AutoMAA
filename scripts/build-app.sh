#!/bin/zsh
set -euo pipefail

PROJECT_DIR="${0:A:h:h}"
cd "$PROJECT_DIR"

swift build -c release --product AutoMAA
swift build -c release --product AutoMAARunner
swift build -c release --product AutoMAAResourceProbe
swift build -c release --product AutoMAAUpdater
BIN_DIR="$(swift build -c release --show-bin-path)"
APP_DIR="$PROJECT_DIR/.build/AutoMAA.app"
BUILD_VERSION="$(/bin/date -u +%Y%m%d%H%M%S)"
BUNDLE_IDENTIFIER="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$PROJECT_DIR/scripts/Info.plist")"
LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"

/bin/rm -rf -- "$APP_DIR"
/bin/mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"
/bin/cp "$BIN_DIR/AutoMAA" "$APP_DIR/Contents/MacOS/AutoMAA"
/bin/cp "$BIN_DIR/AutoMAARunner" "$APP_DIR/Contents/MacOS/AutoMAARunner"
/bin/cp "$BIN_DIR/AutoMAAResourceProbe" "$APP_DIR/Contents/MacOS/AutoMAAResourceProbe"
/bin/cp "$BIN_DIR/AutoMAAUpdater" "$APP_DIR/Contents/MacOS/AutoMAAUpdater"
/bin/cp "$PROJECT_DIR/scripts/Info.plist" "$APP_DIR/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $BUILD_VERSION" "$APP_DIR/Contents/Info.plist"
/bin/cp "$PROJECT_DIR/Assets/AutoMAA.icns" "$APP_DIR/Contents/Resources/AutoMAA.icns"
/bin/cp "$PROJECT_DIR/Assets/AutoMAA-slogan.png" "$APP_DIR/Contents/Resources/AutoMAA-slogan.png"
/usr/bin/codesign --force --sign - --identifier "$BUNDLE_IDENTIFIER" "$APP_DIR/Contents/MacOS/AutoMAARunner"
/usr/bin/codesign --force --sign - --identifier "$BUNDLE_IDENTIFIER.resource-probe" "$APP_DIR/Contents/MacOS/AutoMAAResourceProbe"
/usr/bin/codesign --force --sign - --identifier "$BUNDLE_IDENTIFIER.updater" "$APP_DIR/Contents/MacOS/AutoMAAUpdater"
/usr/bin/codesign --force --sign - "$APP_DIR"
/usr/bin/codesign --verify --deep --strict "$APP_DIR"
RUNNER_IDENTIFIER="$(/usr/bin/codesign -dvv "$APP_DIR/Contents/MacOS/AutoMAARunner" 2>&1 | /usr/bin/sed -n 's/^Identifier=//p')"
if [[ "$RUNNER_IDENTIFIER" != "$BUNDLE_IDENTIFIER" ]]; then
    print -u2 "AutoMAARunner signing identifier mismatch: $RUNNER_IDENTIFIER"
    exit 2
fi
PROBE_IDENTIFIER="$(/usr/bin/codesign -dvv "$APP_DIR/Contents/MacOS/AutoMAAResourceProbe" 2>&1 | /usr/bin/sed -n 's/^Identifier=//p')"
if [[ "$PROBE_IDENTIFIER" != "$BUNDLE_IDENTIFIER.resource-probe" ]]; then
    print -u2 "AutoMAAResourceProbe signing identifier mismatch: $PROBE_IDENTIFIER"
    exit 2
fi
/usr/bin/touch "$APP_DIR"
"$LSREGISTER" -f "$APP_DIR"

echo "$APP_DIR"
