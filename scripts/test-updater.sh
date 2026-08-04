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

"$CURRENT_APP/Contents/MacOS/AutoMAAUpdater" \
    --pid 0 \
    --current-app "$CURRENT_APP" \
    --new-app "$STAGED_APP" \
    --expected-version "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$STAGED_APP/Contents/Info.plist")" \
    --result "$RESULT_PATH" \
    --lock "$LOCK_PATH" \
    --no-relaunch

/bin/test -f "$CURRENT_APP/Contents/Resources/updater-test-marker"
/usr/bin/codesign --verify --deep --strict --verbose=2 "$CURRENT_APP"
/usr/bin/plutil -extract status raw "$RESULT_PATH" | /usr/bin/grep -qx success

print "AutoMAA updater smoke test passed"
