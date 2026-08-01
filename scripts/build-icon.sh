#!/bin/zsh
set -euo pipefail

PROJECT_DIR="${0:A:h:h}"
SOURCE="${1:-$PROJECT_DIR/Assets/AutoMAA-icon.png}"
ICONSET="$PROJECT_DIR/Assets/AutoMAA.iconset"
OUTPUT="$PROJECT_DIR/Assets/AutoMAA.icns"

/bin/mkdir -p "$ICONSET"
/usr/bin/sips -z 16 16 "$SOURCE" --out "$ICONSET/icon_16x16.png"
/usr/bin/sips -z 32 32 "$SOURCE" --out "$ICONSET/icon_16x16@2x.png"
/usr/bin/sips -z 32 32 "$SOURCE" --out "$ICONSET/icon_32x32.png"
/usr/bin/sips -z 64 64 "$SOURCE" --out "$ICONSET/icon_32x32@2x.png"
/usr/bin/sips -z 128 128 "$SOURCE" --out "$ICONSET/icon_128x128.png"
/usr/bin/sips -z 256 256 "$SOURCE" --out "$ICONSET/icon_128x128@2x.png"
/usr/bin/sips -z 256 256 "$SOURCE" --out "$ICONSET/icon_256x256.png"
/usr/bin/sips -z 512 512 "$SOURCE" --out "$ICONSET/icon_256x256@2x.png"
/usr/bin/sips -z 512 512 "$SOURCE" --out "$ICONSET/icon_512x512.png"
/usr/bin/sips -z 1024 1024 "$SOURCE" --out "$ICONSET/icon_512x512@2x.png"
/usr/bin/iconutil -c icns "$ICONSET" -o "$OUTPUT"

echo "$OUTPUT"
