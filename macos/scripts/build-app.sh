#!/usr/bin/env bash
# Builds "Alive for Mac.app" into macos/build/ (ad-hoc signed).
#
#   scripts/build-app.sh            universal (arm64 + x86_64) release build
#   scripts/build-app.sh --native   host architecture only (faster)
#   scripts/build-app.sh --zip      also write macos/dist/AliveForMac-<version>.zip
#   scripts/build-app.sh --dmg      also write macos/dist/AliveForMac-<version>.dmg
#                                   (app + Applications link + license files; no GUI needed)
#   --zip and --dmg can be combined.
#
# The app carries two app extensions (Contents/PlugIns): AliveQuickLook (Space on an .als in
# Finder) and AliveWidget (desktop widget). SwiftPM has no extension product type, so they are
# executables linked to start in _NSExtensionMain; this script gives them their Info.plist and
# sandbox entitlements (Resources/Extensions) and signs them before the app. They register on
# first launch of the app but come up switched off: Settings has the button, or
# `pluginkit -e use -i io.github.bassmicrobe.alive-for-mac.quicklook` (and `.widget`).
set -euo pipefail

NATIVE=0
ZIP=0
DMG=0
for arg in "$@"; do
    case "$arg" in
        --native) NATIVE=1 ;;
        --zip) ZIP=1 ;;
        --dmg) DMG=1 ;;
        -h|--help) sed -n '2,16p' "$0"; exit 0 ;;
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
ICON_SRC="$MACOS_DIR/Resources/Branding/AppIcon.icns"
if [[ ! -f "$ICON_SRC" ]]; then
    echo "error: $ICON_SRC not found; run macos/scripts/generate-app-icon.sh" >&2
    exit 1
fi

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
mkdir -p "$CONTENTS/MacOS" "$CONTENTS/Resources" "$CONTENTS/PlugIns"
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
# The complete 1x/2x icon set is generated from the supplied 1024 px logo.
# Keep the generated asset in the repository so builds need no SVG renderer.
cp "$ICON_SRC" "$CONTENTS/Resources/AppIcon.icns"

# ---------------------------------------------------------------- Info.plist
# .als is declared as Viewer / Alternate: Alive can open sets, but Live stays the default app.
# The imported type com.ableton.live-set is what the Quick Look extension is registered for;
# LSItemContentTypes ties the document type to it. alive:// is the URL scheme (Shortcuts).
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
            <key>LSItemContentTypes</key>
            <array><string>com.ableton.live-set</string></array>
        </dict>
    </array>
    <key>UTImportedTypeDeclarations</key>
    <array>
        <dict>
            <key>UTTypeIdentifier</key><string>com.ableton.live-set</string>
            <key>UTTypeDescription</key><string>Ableton Live Set</string>
            <key>UTTypeConformsTo</key>
            <array><string>public.data</string></array>
            <key>UTTypeTagSpecification</key>
            <dict>
                <key>public.filename-extension</key>
                <array><string>als</string></array>
            </dict>
        </dict>
    </array>
    <key>CFBundleURLTypes</key>
    <array>
        <dict>
            <key>CFBundleURLName</key><string>$BUNDLE_ID</string>
            <key>CFBundleURLSchemes</key>
            <array><string>alive</string></array>
        </dict>
    </array>
</dict>
</plist>
PLIST
plutil -lint "$CONTENTS/Info.plist" >/dev/null

# ---------------------------------------------------------------- extensions
EXT_RES="$MACOS_DIR/Resources/Extensions"
make_appex() { # <SwiftPM executable name> <bundle id suffix> <display name> <NSExtension plist fragment> <entitlements>
    local name="$1" bid="$BUNDLE_ID.$2" display="$3" fragment="$4" entitlements="$5"
    local appex="$CONTENTS/PlugIns/$name.appex"
    mkdir -p "$appex/Contents/MacOS"
    cp "$BIN_DIR/$name" "$appex/Contents/MacOS/$name"
    cat > "$appex/Contents/Info.plist" <<EXTPLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>$name</string>
    <key>CFBundleDisplayName</key><string>$display</string>
    <key>CFBundleIdentifier</key><string>$bid</string>
    <key>CFBundleExecutable</key><string>$name</string>
    <key>CFBundlePackageType</key><string>XPC!</string>
    <key>CFBundleInfoDictionaryVersion</key><string>6.0</string>
    <key>CFBundleShortVersionString</key><string>$VERSION</string>
    <key>CFBundleVersion</key><string>$BUILD_NUMBER</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
$(cat "$fragment")
</dict>
</plist>
EXTPLIST
    plutil -lint "$appex/Contents/Info.plist" >/dev/null
    # Each extension is sandboxed with its own entitlements; signed before the app that holds it.
    codesign --force --sign - --entitlements "$entitlements" "$appex"
}
echo "==> assembling extensions"
make_appex AliveQuickLook quicklook "Alive Quick Look" "$EXT_RES/quicklook.plist" "$EXT_RES/quicklook.entitlements"
make_appex AliveWidget widget "Alive" "$EXT_RES/widget.plist" "$EXT_RES/widget.entitlements"

# ---------------------------------------------------------------- sign
# No --deep: it would re-sign the extensions without their entitlements.
echo "==> ad-hoc signing"
codesign --force --sign - "$APP"
codesign --verify --deep --strict "$APP"

# ---------------------------------------------------------------- zip
if [[ $ZIP -eq 1 ]]; then
    mkdir -p "$MACOS_DIR/dist"
    ARCHIVE="$MACOS_DIR/dist/AliveForMac-$VERSION.zip"
    rm -f "$ARCHIVE"
    ditto -c -k --keepParent "$APP" "$ARCHIVE"
    echo "==> $ARCHIVE"
fi

# ---------------------------------------------------------------- dmg
if [[ $DMG -eq 1 ]]; then
    mkdir -p "$MACOS_DIR/dist" "$MACOS_DIR/build"
    DMG_PATH="$MACOS_DIR/dist/AliveForMac-$VERSION.dmg"
    STAGE="$(mktemp -d "$MACOS_DIR/build/dmg-stage.XXXXXX")"
    trap 'rm -rf "$STAGE"' EXIT
    ditto "$APP" "$STAGE/$APP_NAME.app"
    ln -s /Applications "$STAGE/Applications"
    # License texts sit next to the app: upstream's verbatim, the port's, the notice.
    cp "$REPO_ROOT/LICENSE" "$STAGE/LICENSE"
    cp "$MACOS_DIR/LICENSE" "$STAGE/LICENSE-macos"
    cp "$MACOS_DIR/NOTICE.md" "$STAGE/NOTICE.md"
    rm -f "$DMG_PATH"
    hdiutil create -volname "$APP_NAME $VERSION" -srcfolder "$STAGE" \
        -format UDZO -fs HFS+ -ov "$DMG_PATH" >/dev/null
    rm -rf "$STAGE"
    echo "==> $DMG_PATH"
fi

echo "==> built $APP ($VERSION, upstream ${UPSTREAM_COMMIT:0:7})"
