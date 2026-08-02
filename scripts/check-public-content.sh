#!/bin/zsh
set -euo pipefail

PROJECT_DIR="${0:A:h:h}"
if (( $# > 0 )); then
    PATHS=("$@")
else
    PATHS=("$PROJECT_DIR/README.md" "$PROJECT_DIR/CHANGELOG.md" "$PROJECT_DIR/docs")
fi

PATTERNS=(
    '按要求'
    '根据(用户|协作)?要求'
    '应用户要求'
    '本次(对话|协作|任务)'
    '我们的对话'
    '未进行真实游戏测试'
    '未启动[^。]*真实游戏'
    '不会连接[^。]*真实游戏'
    '/Users/[A-Za-z0-9._-]+/'
    '(^|[^0-9])1[3-9][0-9]{9}([^0-9]|$)'
)

FAILED=false
for path in "${PATHS[@]}"; do
    if [[ ! -e "$path" ]]; then
        print -u2 "Public content path does not exist: $path"
        exit 2
    fi
    for pattern in "${PATTERNS[@]}"; do
        if /usr/bin/grep -ERnI \
            --exclude='*.webp' \
            --exclude='*.png' \
            --exclude='*.icns' \
            -- "$pattern" "$path"; then
            FAILED=true
        fi
    done
done

if [[ "$FAILED" == true ]]; then
    print -u2 "Public content contains collaboration context or private identifiers"
    exit 1
fi

print "Public content check passed"
