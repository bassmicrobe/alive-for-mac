#!/usr/bin/env bash
# Builds "Alive for Mac.app" into macos/build/ (ad-hoc signed unless ALIVE_SIGN_IDENTITY is set).
#
#   scripts/build-app.sh            universal (arm64 + x86_64) release build
#   scripts/build-app.sh --native   host architecture only (faster)
#   scripts/build-app.sh --zip      also write macos/dist/AliveForMac-<version>.zip
#   scripts/build-app.sh --dmg      also write macos/dist/AliveForMac-<version>.dmg
#                                   (app + Applications link + license files; no GUI needed)
#   --zip and --dmg can be combined.
#   scripts/build-app.sh --zip --dmg --notarize
#                                   Developer ID sign, notarize and staple the app, then the dmg
#                                   (needs ALIVE_SIGN_IDENTITY and Apple credentials, see below)
#
# Signing (details: docs/RELEASING.md):
#   ALIVE_SIGN_IDENTITY     e.g. "Developer ID Application: Name (TEAMID)". Set: both app extensions
#                           and the app are signed with it (hardened runtime, secure timestamp,
#                           entitlements kept). Unset: ad-hoc signing, as always.
#   --notarize credentials  ALIVE_NOTARY_KEYCHAIN_PROFILE (a `notarytool store-credentials` profile),
#                           or APPLE_ID + APPLE_APP_PASSWORD + APPLE_TEAM_ID.
#                           ALIVE_NOTARY_TIMEOUT (default 60m) limits each wait for Apple.
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
NOTARIZE=0
for arg in "$@"; do
    case "$arg" in
        --native) NATIVE=1 ;;
        --zip) ZIP=1 ;;
        --dmg) DMG=1 ;;
        --notarize) NOTARIZE=1 ;;
        -h|--help) awk 'NR > 1 { if (/^#/) { sub(/^# ?/, ""); print } else exit }' "$0"; exit 0 ;;
        *) echo "unknown option: $arg" >&2; exit 2 ;;
    esac
done

# ---------------------------------------------------------------- signing setup
# Empty identity = ad-hoc. Checked before the (long) build so a missing credential fails at once.
SIGN_IDENTITY="${ALIVE_SIGN_IDENTITY:-}"
NOTARY_TIMEOUT="${ALIVE_NOTARY_TIMEOUT:-60m}"
NOTARY_AUTH=()
if [[ $NOTARIZE -eq 1 ]]; then
    if [[ -z "$SIGN_IDENTITY" ]]; then
        echo "error: --notarize needs ALIVE_SIGN_IDENTITY (a \"Developer ID Application: Name (TEAMID)\" identity)" >&2
        exit 2
    fi
    if [[ -n "${ALIVE_NOTARY_KEYCHAIN_PROFILE:-}" ]]; then
        NOTARY_AUTH=(--keychain-profile "$ALIVE_NOTARY_KEYCHAIN_PROFILE")
    elif [[ -n "${APPLE_ID:-}" && -n "${APPLE_APP_PASSWORD:-}" && -n "${APPLE_TEAM_ID:-}" ]]; then
        NOTARY_AUTH=(--apple-id "$APPLE_ID" --password "$APPLE_APP_PASSWORD" --team-id "$APPLE_TEAM_ID")
    else
        echo "error: --notarize needs ALIVE_NOTARY_KEYCHAIN_PROFILE, or APPLE_ID + APPLE_APP_PASSWORD + APPLE_TEAM_ID" >&2
        exit 2
    fi
    if ! xcrun --find notarytool >/dev/null 2>&1 || ! xcrun --find stapler >/dev/null 2>&1; then
        echo "error: xcrun notarytool / stapler not found (install Xcode 13 or later)" >&2
        exit 2
    fi
fi

STAGE=""  # dmg staging folder
WORK=""   # scratch folder for the notarization upload and the zip check
cleanup() {
    if [[ -n "$STAGE" ]]; then rm -rf "$STAGE"; fi
    if [[ -n "$WORK" ]]; then rm -rf "$WORK"; fi
}
trap cleanup EXIT

fail() { echo "error: $*" >&2; exit 1; }

# sign_code <path> [entitlements]: ad-hoc by default. With ALIVE_SIGN_IDENTITY: that identity, the
# hardened runtime and a secure timestamp (notarization needs both).
sign_code() {
    local target="$1" entitlements="${2:-}"
    local args=(--force)
    if [[ -n "$SIGN_IDENTITY" ]]; then
        args+=(--sign "$SIGN_IDENTITY" --options runtime --timestamp)
    else
        args+=(--sign -)
    fi
    if [[ -n "$entitlements" ]]; then args+=(--entitlements "$entitlements"); fi
    codesign "${args[@]}" "$target"
}

# notarytool prints the submission's plist; plutil reads a key from stdin.
plist_value() { plutil -extract "$1" raw -o - - 2>/dev/null || true; }

# notarize <file> <label>: uploads, waits for Apple's verdict and stops with the log unless it is Accepted.
# Not trusting notarytool's exit status alone: `set -e` would end the script before the log is printed.
notarize() {
    local file="$1" label="$2" rc=0 out id status
    echo "==> notarizing $label (uploads to Apple and waits, usually a few minutes)"
    out="$(xcrun notarytool submit "$file" "${NOTARY_AUTH[@]}" --wait --timeout "$NOTARY_TIMEOUT" --output-format plist)" || rc=$?
    id="$(plist_value id <<<"$out")"
    status="$(plist_value status <<<"$out")"
    if [[ -z "$status" && -n "$id" ]]; then
        # Output without a final status: ask the service directly.
        status="$(xcrun notarytool info "$id" "${NOTARY_AUTH[@]}" --output-format plist 2>/dev/null | plist_value status || true)"
    fi
    if [[ "$status" != "Accepted" ]]; then
        echo "error: notarization of $label failed (notarytool exit $rc, status: ${status:-unknown}, submission: ${id:-none})" >&2
        if [[ -n "$out" ]]; then printf '%s\n' "$out" >&2; fi
        if [[ -n "$id" ]]; then
            echo "---- notarytool log $id" >&2
            xcrun notarytool log "$id" "${NOTARY_AUTH[@]}" >&2 || true
        fi
        exit 1
    fi
    echo "==> notarization accepted: $label (submission $id)"
}

# staple <path>: the ticket can take a moment to become available right after approval.
staple() {
    local attempt
    for attempt in 1 2 3 4 5; do
        if xcrun stapler staple "$1"; then return 0; fi
        echo "warning: stapler failed for $1 (attempt $attempt of 5), retrying in 15 s" >&2
        sleep 15
    done
    fail "could not staple $1"
}

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
    sign_code "$appex" "$entitlements"
}
echo "==> assembling extensions"
make_appex AliveQuickLook quicklook "Alive Quick Look" "$EXT_RES/quicklook.plist" "$EXT_RES/quicklook.entitlements"
make_appex AliveWidget widget "Alive" "$EXT_RES/widget.plist" "$EXT_RES/widget.entitlements"

# ---------------------------------------------------------------- sign
# No --deep: it would re-sign the extensions without their entitlements.
if [[ -n "$SIGN_IDENTITY" ]]; then
    echo "==> signing with: $SIGN_IDENTITY (hardened runtime)"
else
    echo "==> ad-hoc signing"
fi
sign_code "$APP"
codesign --verify --deep --strict "$APP"

# What must hold after signing, in both modes: the extensions kept their sandbox entitlements (and the
# widget its read exception). With a Developer ID identity also the authority and the hardened runtime.
verify_signing() {
    local bundle info entitlements
    for bundle in "$CONTENTS"/PlugIns/*.appex "$APP"; do
        if [[ "$bundle" == *.appex ]]; then
            entitlements="$(codesign -d --entitlements - "$bundle" 2>/dev/null)"
            grep -q "com.apple.security.app-sandbox" <<<"$entitlements" \
                || fail "$(basename "$bundle") lost its sandbox entitlement while signing"
            if [[ "$bundle" == *AliveWidget.appex ]]; then
                grep -q "com.apple.security.temporary-exception.files.home-relative-path.read-only" <<<"$entitlements" \
                    || fail "AliveWidget.appex lost its widget-folder read exception while signing"
            fi
        fi
        if [[ -n "$SIGN_IDENTITY" ]]; then
            info="$(codesign -dvv "$bundle" 2>&1)"
            grep -q "^Authority=Developer ID Application" <<<"$info" \
                || fail "$(basename "$bundle") is not signed by a Developer ID Application certificate"
            grep -q "flags=.*runtime" <<<"$info" \
                || fail "$(basename "$bundle") is missing the hardened runtime flag"
        fi
    done
}
verify_signing

# ---------------------------------------------------------------- notarize the app
# Submission 1 of 2: the app (zipped as Finder would), stapled before it is zipped/dmg'd for release.
if [[ $NOTARIZE -eq 1 ]]; then
    WORK="$(mktemp -d "${TMPDIR:-/tmp}/alive-notarize.XXXXXX")"
    ditto -c -k --keepParent "$APP" "$WORK/$APP_NAME.zip"
    notarize "$WORK/$APP_NAME.zip" "app"
    staple "$APP"
fi

# ---------------------------------------------------------------- zip
# Written after stapling, so the release zip carries the ticket.
if [[ $ZIP -eq 1 ]]; then
    mkdir -p "$MACOS_DIR/dist"
    ARCHIVE="$MACOS_DIR/dist/AliveForMac-$VERSION.zip"
    rm -f "$ARCHIVE"
    ditto -c -k --keepParent "$APP" "$ARCHIVE"
    echo "==> $ARCHIVE"
fi

# ---------------------------------------------------------------- dmg
# Built from the stapled app. The image is signed too (spctl judges a dmg by its own signature), then
# it is submission 2 of 2.
if [[ $DMG -eq 1 ]]; then
    mkdir -p "$MACOS_DIR/dist" "$MACOS_DIR/build"
    DMG_PATH="$MACOS_DIR/dist/AliveForMac-$VERSION.dmg"
    STAGE="$(mktemp -d "$MACOS_DIR/build/dmg-stage.XXXXXX")"
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
    if [[ -n "$SIGN_IDENTITY" ]]; then
        codesign --force --sign "$SIGN_IDENTITY" --timestamp "$DMG_PATH"
    fi
    if [[ $NOTARIZE -eq 1 ]]; then
        notarize "$DMG_PATH" "dmg"
        staple "$DMG_PATH"
    fi
    echo "==> $DMG_PATH"
fi

# ---------------------------------------------------------------- verify the notarized result
# What Gatekeeper will say on a user's Mac. Any failure stops the build.
verify_notarized() {
    local out check
    echo "==> verifying notarization"
    out="$(spctl -a -vv "$APP" 2>&1)" || { printf '%s\n' "$out" >&2; fail "spctl rejected the app"; }
    printf '%s\n' "$out"
    grep -q "source=Notarized Developer ID" <<<"$out" || fail "the app is not accepted as Notarized Developer ID"
    xcrun stapler validate "$APP"
    codesign -dvv "$APP" 2>&1 | grep -E "^(Authority|TeamIdentifier|Timestamp)=" || true

    if [[ $ZIP -eq 1 ]]; then # the release zip must hold the stapled app
        check="$WORK/zip-check"
        mkdir -p "$check"
        ditto -x -k "$ARCHIVE" "$check"
        xcrun stapler validate "$check/$APP_NAME.app"
    fi
    if [[ $DMG -eq 1 ]]; then
        xcrun stapler validate "$DMG_PATH"
        out="$(spctl -a -t open --context context:primary-signature -vv "$DMG_PATH" 2>&1)" \
            || { printf '%s\n' "$out" >&2; fail "spctl rejected the dmg"; }
        printf '%s\n' "$out"
    fi
}
if [[ $NOTARIZE -eq 1 ]]; then
    verify_notarized
fi

echo "==> built $APP ($VERSION, upstream ${UPSTREAM_COMMIT:0:7})"
