#!/bin/bash
# Builds a universal, Developer ID-signed, notarized and stapled SpaceGuard.dmg.
# Usage: VERSION=0.1.0 ./release.sh [--publish]    (--publish also creates the GitHub release)
#
# One-time setup on the release machine:
#   1. A "Developer ID Application" certificate in the login keychain. Only the team's Account Holder
#      can create one: Xcode › Settings › Accounts › (team) › Manage Certificates… › + › Developer ID Application.
#   2. Notarization credentials saved in the keychain as a profile, either with an app-specific password
#      from appleid.apple.com:
#        xcrun notarytool store-credentials spaceguard-notary --apple-id you@example.com --team-id TEAMID
#      or with an App Store Connect API key (Users and Access › Integrations › Team Keys):
#        xcrun notarytool store-credentials spaceguard-notary --key AuthKey_XXXX.p8 --key-id XXXX --issuer <issuer-uuid>
set -euo pipefail
cd "$(dirname "$0")"

APP=SpaceGuard
VERSION="${VERSION:-$(sed -n 's/^VERSION="${VERSION:-\(.*\)}"$/\1/p' build.sh)}"
PROFILE="${NOTARY_PROFILE:-spaceguard-notary}"
IDENTITY="${DEVELOPER_ID:-$(security find-identity -v -p codesigning | awk -F'"' '/Developer ID Application/ {print $2; exit}')}"
DMG="build/$APP.dmg"   # unversioned, so releases/latest/download/SpaceGuard.dmg always works

fail() { echo "error: $*" >&2; exit 1; }
[ -n "$VERSION" ] || fail "could not determine the version"
[ -n "$IDENTITY" ] || fail "no 'Developer ID Application' certificate in the keychain (see setup notes at the top of this script)"
xcrun notarytool history --keychain-profile "$PROFILE" >/dev/null 2>&1 \
    || fail "no notarytool credentials saved as '$PROFILE' (see setup notes at the top of this script)"
if [[ "${1:-}" == "--publish" ]] && gh release view "v$VERSION" >/dev/null 2>&1; then
    fail "release v$VERSION already exists on GitHub; bump VERSION"
fi

notarize() {
    echo "==> Notarizing $(basename "$1") (usually a few minutes)"
    local result status id
    result="$(xcrun notarytool submit "$1" --keychain-profile "$PROFILE" --wait --output-format json)"
    status="$(python3 -c 'import json,sys; print(json.load(sys.stdin).get("status", ""))' <<<"$result")"
    id="$(python3 -c 'import json,sys; print(json.load(sys.stdin).get("id", ""))' <<<"$result")"
    if [ "$status" != "Accepted" ]; then
        xcrun notarytool log "$id" --keychain-profile "$PROFILE" || true
        fail "notarization of $1 finished with status '$status'"
    fi
}

echo "==> Building $APP $VERSION (universal), signing as: $IDENTITY"
ARCHS="arm64 x86_64" HARDENED=1 SIGN_IDENTITY="$IDENTITY" VERSION="$VERSION" ./build.sh
codesign --verify --strict --deep "build/$APP.app"

ditto -c -k --keepParent "build/$APP.app" "build/$APP.zip"
notarize "build/$APP.zip"
rm -f "build/$APP.zip"
xcrun stapler staple "build/$APP.app"

echo "==> Creating $DMG"
STAGE="$(mktemp -d)"
cp -R "build/$APP.app" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
rm -f "$DMG"
hdiutil create -volname "$APP" -srcfolder "$STAGE" -ov -format UDZO "$DMG" >/dev/null
rm -rf "$STAGE"
codesign --force --timestamp --sign "$IDENTITY" "$DMG"
notarize "$DMG"
xcrun stapler staple "$DMG"

echo "==> Checking with Gatekeeper"
spctl --assess --type execute -vv "build/$APP.app"
spctl --assess --type open --context context:primary-signature -vv "$DMG"
SHA="$(shasum -a 256 "$DMG" | cut -d' ' -f1)"
echo "$DMG  sha256 $SHA"

if [[ "${1:-}" == "--publish" ]]; then
    gh release create "v$VERSION" "$DMG" --title "$APP $VERSION" --generate-notes \
        --notes "Universal (Apple silicon + Intel), signed and notarized. Open the DMG and drag SpaceGuard to Applications. SHA-256: \`$SHA\`"
fi
