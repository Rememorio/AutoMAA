#!/bin/zsh
set -euo pipefail

PROJECT_DIR="${0:A:h:h}"
INFO_PLIST="$PROJECT_DIR/scripts/Info.plist"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$INFO_PLIST")"
DMG_PATH="$PROJECT_DIR/dist/AutoMAA-$VERSION-macOS-arm64.dmg"
CHECKSUM_PATH="$DMG_PATH.sha256"
MOUNT_DIR="$(/usr/bin/mktemp -d "${TMPDIR:-/tmp}/automaa-release-mount.XXXXXX")"
MOUNTED=false

cleanup() {
    if [[ "$MOUNTED" == true ]]; then
        /usr/bin/hdiutil detach "$MOUNT_DIR" >/dev/null || true
    fi
    /bin/rm -rf -- "$MOUNT_DIR"
}
trap cleanup EXIT INT TERM

cd "$PROJECT_DIR"

swift test --parallel
./scripts/build-app.sh >/dev/null
./scripts/test-updater.sh
npm ci
npm run docs:build
./scripts/package-dmg.sh "$VERSION"

/usr/bin/codesign --verify --deep --strict --verbose=2 "$PROJECT_DIR/.build/AutoMAA.app"
/usr/bin/hdiutil verify "$DMG_PATH"
(cd "$PROJECT_DIR/dist" && /usr/bin/shasum -a 256 -c "${CHECKSUM_PATH:t}")

/usr/bin/hdiutil attach -readonly -nobrowse -mountpoint "$MOUNT_DIR" "$DMG_PATH" >/dev/null
MOUNTED=true

APP_PATH="$MOUNT_DIR/AutoMAA.app"
/bin/test -d "$APP_PATH"
/bin/test -L "$MOUNT_DIR/Applications"
/bin/test "$(/usr/bin/readlink "$MOUNT_DIR/Applications")" = "/Applications"
/bin/test "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP_PATH/Contents/Info.plist")" = "$VERSION"
/bin/test "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$APP_PATH/Contents/Info.plist")" = "com.rememorio.AutoMAA"
/usr/bin/codesign --verify --deep --strict --verbose=2 "$APP_PATH"
/usr/bin/file "$APP_PATH/Contents/MacOS/AutoMAA" | /usr/bin/grep -q arm64
/usr/bin/file "$APP_PATH/Contents/MacOS/AutoMAARunner" | /usr/bin/grep -q arm64
/usr/bin/file "$APP_PATH/Contents/MacOS/AutoMAAUpdater" | /usr/bin/grep -q arm64

/usr/bin/hdiutil detach "$MOUNT_DIR" >/dev/null
MOUNTED=false

print "AutoMAA v$VERSION release verification passed"
