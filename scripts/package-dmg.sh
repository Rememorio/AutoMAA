#!/bin/zsh
set -euo pipefail

PROJECT_DIR="${0:A:h:h}"
INFO_PLIST="$PROJECT_DIR/scripts/Info.plist"
APP_CORE_VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$INFO_PLIST")"
APP_VERSION="$(/usr/libexec/PlistBuddy -c 'Print :AutoMAAReleaseVersion' "$INFO_PLIST" 2>/dev/null || print -r -- "$APP_CORE_VERSION")"
VERSION="${1:-$APP_VERSION}"
ARCH="$(/usr/bin/uname -m)"
CORE_VERSION_PATTERN='(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)'
PRERELEASE_IDENTIFIER_PATTERN='(0|[1-9][0-9]*|[0-9]*[A-Za-z-][0-9A-Za-z-]*)'
RELEASE_VERSION_PATTERN="^${CORE_VERSION_PATTERN}(-${PRERELEASE_IDENTIFIER_PATTERN}(\.${PRERELEASE_IDENTIFIER_PATTERN})*)?(\+[0-9A-Za-z-]+(\.[0-9A-Za-z-]+)*)?$"

if [[ ! "$VERSION" =~ "$RELEASE_VERSION_PATTERN" ]]; then
    print -u2 "Invalid version: $VERSION"
    exit 2
fi

if [[ "${VERSION%%[-+]*}" != "$APP_CORE_VERSION" ]]; then
    print -u2 "Release version $VERSION does not match bundle core version $APP_CORE_VERSION"
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
