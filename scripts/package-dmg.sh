#!/bin/zsh
set -euo pipefail

PROJECT_DIR="${0:A:h:h}"
INFO_PLIST="$PROJECT_DIR/scripts/Info.plist"
APP_VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$INFO_PLIST")"
VERSION="${1:-$APP_VERSION}"
ARCH="$(/usr/bin/uname -m)"

if [[ ! "$VERSION" =~ '^[0-9]+\.[0-9]+\.[0-9]+([.-][A-Za-z0-9.-]+)?$' ]]; then
    print -u2 "Invalid version: $VERSION"
    exit 2
fi

if [[ "$ARCH" != "arm64" ]]; then
    print -u2 "AutoMAA DMG currently supports arm64 builds only (current: $ARCH)"
    exit 2
fi

if [[ "$VERSION" != "$APP_VERSION" ]]; then
    print -u2 "Requested DMG version $VERSION does not match App version $APP_VERSION"
    exit 2
fi

APP_PATH="$PROJECT_DIR/.build/AutoMAA.app"
DIST_DIR="$PROJECT_DIR/dist"
DMG_PATH="$DIST_DIR/AutoMAA-$VERSION-macOS-arm64.dmg"
CHECKSUM_PATH="$DMG_PATH.sha256"
STAGING_DIR="$(/usr/bin/mktemp -d "${TMPDIR:-/tmp}/automaa-dmg.XXXXXX")"

cleanup() {
    /bin/rm -rf -- "$STAGING_DIR"
}
trap cleanup EXIT INT TERM

"$PROJECT_DIR/scripts/build-app.sh"
/bin/mkdir -p "$DIST_DIR"
/bin/rm -f -- "$DMG_PATH" "$CHECKSUM_PATH"
/usr/bin/ditto "$APP_PATH" "$STAGING_DIR/AutoMAA.app"
/bin/ln -s /Applications "$STAGING_DIR/Applications"

/usr/bin/hdiutil create \
    -volname "AutoMAA" \
    -srcfolder "$STAGING_DIR" \
    -format UDZO \
    -ov \
    "$DMG_PATH"

(cd "$DIST_DIR" && /usr/bin/shasum -a 256 "${DMG_PATH:t}" > "${CHECKSUM_PATH:t}")

print "$DMG_PATH"
print "$CHECKSUM_PATH"
