#!/usr/bin/env bash
# Builds "Alive for Mac.app" into macos/build/ (ad-hoc signed).
#
#   scripts/build-app.sh            universal (arm64 + x86_64) release build
#   scripts/build-app.sh --native   host architecture only (faster)
#   scripts/build-app.sh --zip      also write macos/dist/AliveForMac-<version>.zip
set -euo pipefail

NATIVE=0
ZIP=0
for arg in "$@"; do
    case "$arg" in
        --native) NATIVE=1 ;;
        --zip) ZIP=1 ;;
        -h|--help) sed -n '2,7p' "$0"; exit 0 ;;
        *) echo "unknown option: $arg" >&2; exit 2 ;;
    esac
done

MACOS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REPO_ROOT="$(cd "$MACOS_DIR/.." && pwd)"
APP_NAME="Alive for Mac"
EXECUTABLE="AliveForMac"
BUNDLE_ID="io.github.bassmicrobe.alive-for-mac"
VERSION="$(tr -d '[:space:]' < "$MACOS_DIR/VERSION")"
UPSTREAM_COMMIT="$(tr -d '[:space:]' < "$MACOS_DIR/UPSTREAM_SYNC")"
BUILD_NUMBER="$(git -C "$REPO_ROOT" rev-list --count HEAD 2>/dev/null || echo 1)"
YEAR="$(date +%Y)"

APP="$MACOS_DIR/build/$APP_NAME.app"
CONTENTS="$APP/Contents"

cd "$MACOS_DIR"

# ---------------------------------------------------------------- compile
ARCH_FLAGS=()
if [[ $NATIVE -eq 0 ]]; then
    ARCH_FLAGS=(--arch arm64 --arch x86_64)
fi

echo "==> swift build -c release ${ARCH_FLAGS[*]:-(native)}"
if ! swift build -c release ${ARCH_FLAGS[@]+"${ARCH_FLAGS[@]}"}; then
    if [[ $NATIVE -eq 0 ]]; then
        echo "warning: universal build failed, falling back to the host architecture" >&2
        ARCH_FLAGS=()
        swift build -c release
    else
        exit 1
    fi
fi
BIN_DIR="$(swift build -c release ${ARCH_FLAGS[@]+"${ARCH_FLAGS[@]}"} --show-bin-path)"

# ---------------------------------------------------------------- bundle
echo "==> assembling $APP"
rm -rf "$APP"
mkdir -p "$CONTENTS/MacOS" "$CONTENTS/Resources"
cp "$BIN_DIR/$EXECUTABLE" "$CONTENTS/MacOS/$EXECUTABLE"

# SwiftPM resource bundles (none today, but features may add some).
shopt -s nullglob
for bundle in "$BIN_DIR"/*.bundle; do
    cp -R "$bundle" "$CONTENTS/Resources/"
done
shopt -u nullglob

# License texts: upstream's verbatim, the port's, and the notice.
cp "$REPO_ROOT/LICENSE" "$CONTENTS/Resources/LICENSE"
cp "$MACOS_DIR/LICENSE" "$CONTENTS/Resources/LICENSE-macos"
cp "$MACOS_DIR/NOTICE.md" "$CONTENTS/Resources/NOTICE.md"

# ---------------------------------------------------------------- icon
ICON_SRC="$REPO_ROOT/src/icons/icon256.ico"
if [[ -f "$ICON_SRC" ]]; then
    WORK="$(mktemp -d)"
    trap 'rm -rf "$WORK"' EXIT
    ICONSET="$WORK/AppIcon.iconset"
    mkdir -p "$ICONSET"
    sips -s format png "$ICON_SRC" --out "$WORK/icon.png" >/dev/null
    # The source is 256 px: larger sizes would only be upscaled, so the set stops at 256.
    for size in 16 32 64 128 256; do
        sips -z "$size" "$size" "$WORK/icon.png" --out "$WORK/s$size.png" >/dev/null
    done
    cp "$WORK/s16.png"  "$ICONSET/icon_16x16.png"
    cp "$WORK/s32.png"  "$ICONSET/icon_16x16@2x.png"
    cp "$WORK/s32.png"  "$ICONSET/icon_32x32.png"
    cp "$WORK/s64.png"  "$ICONSET/icon_32x32@2x.png"
    cp "$WORK/s128.png" "$ICONSET/icon_128x128.png"
    cp "$WORK/s256.png" "$ICONSET/icon_128x128@2x.png"
    cp "$WORK/s256.png" "$ICONSET/icon_256x256.png"
    iconutil -c icns "$ICONSET" -o "$CONTENTS/Resources/AppIcon.icns"
else
    echo "warning: $ICON_SRC not found, building without an icon" >&2
fi

# ---------------------------------------------------------------- Info.plist
# .als is declared as Viewer / Alternate: Alive can open sets, but Live stays the default app.
cat > "$CONTENTS/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>$APP_NAME</string>
    <key>CFBundleDisplayName</key><string>$APP_NAME</string>
    <key>CFBundleIdentifier</key><string>$BUNDLE_ID</string>
    <key>CFBundleExecutable</key><string>$EXECUTABLE</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleInfoDictionaryVersion</key><string>6.0</string>
    <key>CFBundleShortVersionString</key><string>$VERSION</string>
    <key>CFBundleVersion</key><string>$BUILD_NUMBER</string>
    <key>CFBundleDevelopmentRegion</key><string>en</string>
    <key>CFBundleLocalizations</key>
    <array><string>en</string><string>ja</string></array>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>LSApplicationCategoryType</key><string>public.app-category.music</string>
    <key>NSHighResolutionCapable</key><true/>
    <key>NSPrincipalClass</key><string>NSApplication</string>
    <key>NSHumanReadableCopyright</key>
    <string>Alive © RueBlose (MIT). macOS port © $YEAR bassmicrobe (MIT). Unofficial port.</string>
    <key>AliveUpstreamCommit</key><string>$UPSTREAM_COMMIT</string>
    <key>CFBundleDocumentTypes</key>
    <array>
        <dict>
            <key>CFBundleTypeName</key><string>Ableton Live Set</string>
            <key>CFBundleTypeExtensions</key>
            <array><string>als</string></array>
            <key>CFBundleTypeRole</key><string>Viewer</string>
            <key>LSHandlerRank</key><string>Alternate</string>
        </dict>
    </array>
</dict>
</plist>
PLIST
plutil -lint "$CONTENTS/Info.plist" >/dev/null

# ---------------------------------------------------------------- sign
echo "==> ad-hoc signing"
codesign --force --deep --sign - "$APP"
codesign --verify --deep --strict "$APP"

# ---------------------------------------------------------------- zip
if [[ $ZIP -eq 1 ]]; then
    mkdir -p "$MACOS_DIR/dist"
    ARCHIVE="$MACOS_DIR/dist/AliveForMac-$VERSION.zip"
    rm -f "$ARCHIVE"
    ditto -c -k --keepParent "$APP" "$ARCHIVE"
    echo "==> $ARCHIVE"
fi

echo "==> built $APP ($VERSION, upstream ${UPSTREAM_COMMIT:0:7})"
