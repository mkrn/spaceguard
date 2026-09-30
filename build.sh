#!/bin/bash
# Builds SpaceGuard.app. Usage: ./build.sh [--install]   (--install copies it to /Applications and relaunches it)
#
# Environment:
#   SIGN_IDENTITY  codesign identity (default: first "Apple Development" identity, else ad-hoc)
#   ARCHS          e.g. "arm64 x86_64" for a universal binary (default: this Mac's architecture)
#   HARDENED=1     hardened runtime + secure timestamp (required for notarization; see release.sh)
#   VERSION        marketing version (default below)
set -euo pipefail
cd "$(dirname "$0")"

APP=SpaceGuard
BUNDLE_ID=io.github.mkrn.spaceguard
VERSION="${VERSION:-0.1.0}"
OUT=build/$APP.app

ARCH_FLAGS=()
for arch in ${ARCHS:-}; do ARCH_FLAGS+=(--arch "$arch"); done
swift build -c release ${ARCH_FLAGS[@]+"${ARCH_FLAGS[@]}"}
BIN="$(swift build -c release ${ARCH_FLAGS[@]+"${ARCH_FLAGS[@]}"} --show-bin-path)/$APP"

rm -rf "$OUT"
mkdir -p "$OUT/Contents/MacOS" "$OUT/Contents/Resources"
cp "$BIN" "$OUT/Contents/MacOS/$APP"
[ -f Resources/AppIcon.icns ] && cp Resources/AppIcon.icns "$OUT/Contents/Resources/"

cat > "$OUT/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key><string>$APP</string>
    <key>CFBundleIdentifier</key><string>$BUNDLE_ID</string>
    <key>CFBundleName</key><string>$APP</string>
    <key>CFBundleDisplayName</key><string>$APP</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>$VERSION</string>
    <key>CFBundleVersion</key><string>$(date +%Y%m%d%H%M)</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>LSUIElement</key><true/>
    <key>NSHighResolutionCapable</key><true/>
    <key>NSHumanReadableCopyright</key><string>© 2026 Mark Sergienko. MIT License.</string>
</dict>
</plist>
PLIST

SIGN_FLAGS=(--force)
[ "${HARDENED:-}" = 1 ] && SIGN_FLAGS+=(--options runtime --timestamp)
if [ -n "${SIGN_IDENTITY:-}" ]; then
    # An explicitly requested identity must work; never fall back silently.
    codesign "${SIGN_FLAGS[@]}" --sign "$SIGN_IDENTITY" "$OUT"
else
    # macOS only grants notifications to properly signed apps, so prefer an Apple Development identity.
    IDENTITY="$(security find-identity -v -p codesigning 2>/dev/null | awk '/Apple Development/ {print $2; exit}')"
    if [ -z "$IDENTITY" ] || ! codesign "${SIGN_FLAGS[@]}" --sign "$IDENTITY" "$OUT" 2>/dev/null; then
        echo "note: signing ad-hoc (notifications may be refused by macOS)"
        codesign --force --sign - "$OUT" >/dev/null
    fi
fi
echo "Built $OUT ($(du -sh "$OUT" | cut -f1), $(lipo -archs "$OUT/Contents/MacOS/$APP"))"

if [[ "${1:-}" == "--install" ]]; then
    # /Applications when writable (notifications are more reliable there), else ~/Applications.
    DEST=/Applications
    [ -w "$DEST" ] || DEST="$HOME/Applications"
    pkill -x "$APP" 2>/dev/null || true
    for _ in $(seq 1 25); do pgrep -x "$APP" >/dev/null || break; sleep 0.2; done
    mkdir -p "$DEST"
    rm -rf "$DEST/$APP.app"
    [ "$DEST" = /Applications ] && rm -rf "$HOME/Applications/$APP.app"
    cp -R "$OUT" "$DEST/"
    open "$DEST/$APP.app" 2>/dev/null || { sleep 1; open "$DEST/$APP.app"; }
    echo "Installed to $DEST/$APP.app and launched"
fi
