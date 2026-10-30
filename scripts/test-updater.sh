#!/bin/zsh
set -euo pipefail

PROJECT_DIR="${0:A:h:h}"
APP_PATH="$PROJECT_DIR/.build/AutoMAA.app"
TEST_ROOT="$(/usr/bin/mktemp -d "${TMPDIR:-/tmp}/automaa-updater-test.XXXXXX")"
CURRENT_APP="$TEST_ROOT/Installed/AutoMAA.app"
STAGED_APP="$TEST_ROOT/Staged/AutoMAA.app"
RESULT_PATH="$TEST_ROOT/update-result.json"
LOCK_PATH="$TEST_ROOT/runner.lock"

cleanup() {
    /bin/rm -rf -- "$TEST_ROOT"
}
trap cleanup EXIT INT TERM

"$PROJECT_DIR/scripts/build-app.sh" >/dev/null
/bin/mkdir -p "${CURRENT_APP:h}" "${STAGED_APP:h}"
/usr/bin/ditto "$APP_PATH" "$CURRENT_APP"
/usr/bin/ditto "$APP_PATH" "$STAGED_APP"
/usr/bin/touch "$STAGED_APP/Contents/Resources/updater-test-marker"
/usr/bin/codesign --force --deep --sign - "$STAGED_APP"
CORE_VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$STAGED_APP/Contents/Info.plist")"
RELEASE_VERSION="$(/usr/libexec/PlistBuddy -c 'Print :AutoMAAReleaseVersion' "$STAGED_APP/Contents/Info.plist" 2>/dev/null || print -r -- "$CORE_VERSION")"
if [[ "${RELEASE_VERSION%%[-+]*}" != "$CORE_VERSION" ]]; then
    print -u2 "Release version $RELEASE_VERSION does not match bundle core version $CORE_VERSION"
    exit 2
fi

"$CURRENT_APP/Contents/MacOS/AutoMAAUpdater" \
    --pid 0 \
    --current-app "$CURRENT_APP" \
    --new-app "$STAGED_APP" \
    --expected-version "$RELEASE_VERSION" \
    --result "$RESULT_PATH" \
    --lock "$LOCK_PATH" \
    --no-relaunch

/bin/test -f "$CURRENT_APP/Contents/Resources/updater-test-marker"
/bin/test "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$CURRENT_APP/Contents/Info.plist")" = "$CORE_VERSION"
INSTALLED_VERSION="$(/usr/libexec/PlistBuddy -c 'Print :AutoMAAReleaseVersion' "$CURRENT_APP/Contents/Info.plist" 2>/dev/null || /usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$CURRENT_APP/Contents/Info.plist")"
/bin/test "$INSTALLED_VERSION" = "$RELEASE_VERSION"
/usr/bin/codesign --verify --deep --strict --verbose=2 "$CURRENT_APP"
/usr/bin/plutil -extract status raw "$RESULT_PATH" | /usr/bin/grep -qx success

print "AutoMAA updater smoke test passed"
