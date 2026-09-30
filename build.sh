#!/bin/bash
# Builds SpaceGuard.app. Usage: ./build.sh [--install]   (--install copies it to /Applications and relaunches it)
set -euo pipefail
cd "$(dirname "$0")"

APP=SpaceGuard
BUNDLE_ID=io.github.mkrn.spaceguard
VERSION=0.1.0
OUT=build/$APP.app

swift build -c release
BIN="$(swift build -c release --show-bin-path)/$APP"

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
</dict>
</plist>
PLIST

# macOS only grants notifications to properly signed apps, so prefer an Apple Development identity
# from the keychain (override with SIGN_IDENTITY=...). Falls back to an ad-hoc signature.
IDENTITY="${SIGN_IDENTITY:-$(security find-identity -v -p codesigning 2>/dev/null | awk '/Apple Development/ {print $2; exit}')}"
if [ -z "$IDENTITY" ] || ! codesign --force --sign "$IDENTITY" "$OUT" 2>/dev/null; then
    echo "note: signing ad-hoc (notifications may be refused by macOS)"
    codesign --force --sign - "$OUT" >/dev/null
fi
echo "Built $OUT ($(du -sh "$OUT" | cut -f1))"

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
