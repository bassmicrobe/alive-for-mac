#!/usr/bin/env bash
# Regenerate the committed macOS icon from Resources/Branding/AppIcon-1024.png.
# Requires only the sips and iconutil tools included with macOS.
set -euo pipefail

MACOS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BRANDING_DIR="$MACOS_DIR/Resources/Branding"
SOURCE="$BRANDING_DIR/AppIcon-1024.png"
if [[ ! -f "$SOURCE" ]]; then
    echo "error: $SOURCE not found" >&2
    exit 1
fi

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
ICONSET="$WORK/AppIcon.iconset"
mkdir -p "$ICONSET"

for size in 16 32 128 256 512; do
    sips -z "$size" "$size" "$SOURCE" --out "$ICONSET/icon_${size}x${size}.png" >/dev/null
    retina=$((size * 2))
    if [[ $retina -eq 1024 ]]; then
        cp "$SOURCE" "$ICONSET/icon_${size}x${size}@2x.png"
    else
        sips -z "$retina" "$retina" "$SOURCE" --out "$ICONSET/icon_${size}x${size}@2x.png" >/dev/null
    fi
done

iconutil -c icns "$ICONSET" -o "$WORK/AppIcon.icns"
mv "$WORK/AppIcon.icns" "$BRANDING_DIR/AppIcon.icns"
echo "Generated $BRANDING_DIR/AppIcon.icns"
