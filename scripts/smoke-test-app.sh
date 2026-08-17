#!/bin/zsh
set -euo pipefail

if (( $# != 1 )); then
    print -u2 "Usage: $0 /path/to/AutoMAA.app"
    exit 2
fi

APP_PATH="${1:A}"
EXECUTABLE="$APP_PATH/Contents/MacOS/AutoMAA"
QA_HOME="$(/usr/bin/mktemp -d "${TMPDIR:-/tmp}/automaa-app-smoke.XXXXXX")"
QA_DATA="$QA_HOME/AutoMAAData"
CONFIG_PATH="$QA_DATA/config.json"
APP_PID=""

cleanup() {
    if [[ -n "$APP_PID" ]] && /bin/kill -0 "$APP_PID" 2>/dev/null; then
        /bin/kill -TERM "$APP_PID" 2>/dev/null || true
        /bin/sleep 0.2
        /bin/kill -KILL "$APP_PID" 2>/dev/null || true
    fi
    /bin/rm -rf -- "$QA_HOME"
}
trap cleanup EXIT INT TERM

/bin/test -d "$APP_PATH"
/bin/test -x "$EXECUTABLE"

CFFIXED_USER_HOME="$QA_HOME" "$EXECUTABLE" --data-directory "$QA_DATA" >/dev/null 2>&1 &
APP_PID=$!
READY=false

for _ in {1..100}; do
    if [[ -f "$CONFIG_PATH" ]]; then
        READY=true
        break
    fi
    if ! /bin/kill -0 "$APP_PID" 2>/dev/null; then
        wait "$APP_PID" || true
        print -u2 "AutoMAA exited before creating its isolated configuration"
        exit 1
    fi
    /bin/sleep 0.1
done

if [[ "$READY" != true ]]; then
    print -u2 "AutoMAA did not finish isolated startup within 10 seconds"
    exit 1
fi

/bin/sleep 1
if ! /bin/kill -0 "$APP_PID" 2>/dev/null; then
    wait "$APP_PID" || true
    print -u2 "AutoMAA exited immediately after isolated startup"
    exit 1
fi

/bin/kill -TERM "$APP_PID" 2>/dev/null || true
for _ in {1..50}; do
    if ! /bin/kill -0 "$APP_PID" 2>/dev/null; then
        break
    fi
    /bin/sleep 0.1
done
if /bin/kill -0 "$APP_PID" 2>/dev/null; then
    /bin/kill -KILL "$APP_PID" 2>/dev/null || true
fi
wait "$APP_PID" || true
APP_PID=""

print "AutoMAA isolated app smoke test passed"
