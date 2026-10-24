#!/bin/bash
# Builds the Mac release as a Developer ID signed, notarised and stapled .dmg.
#
#   ./release-dmg.sh
#
# What it needs, once:
#   - a "Developer ID Application" certificate in the login keychain;
#   - notarytool credentials stored under a keychain profile:
#       xcrun notarytool store-credentials chotki-notary --key AuthKey_XXXX.p8 \
#           --key-id XXXX --issuer <issuer-uuid>
#
# The order matters, and each step is checked before the next:
#   1. build the universal release (build-app.sh), signed ad hoc;
#   2. re-sign the app with Developer ID, the hardened runtime and a secure
#      timestamp — Apple will not notarise anything else;
#   3. notarise the app, then staple the ticket to it, so it still opens with no
#      network once it has been dragged out of the disk image;
#   4. build the .dmg around that stapled app, sign it, notarise it, staple it;
#   5. ask Gatekeeper about the result. Assessing is not running: the Intel
#      slice of this bundle has never been executed and must not be here.
#
# Nothing is masked. A step that fails stops the script with Apple's own words.
set -euo pipefail

cd "$(dirname "$0")"

source ./version.env
PROFILE="${CHOTKI_NOTARY_PROFILE:-chotki-notary}"
IDENTITY="${CHOTKI_SIGN_IDENTITY:-}"
if [ -z "$IDENTITY" ]; then
    IDENTITY="$(security find-identity -v -p codesigning \
        | sed -n 's/.*"\(Developer ID Application:[^"]*\)".*/\1/p' | head -1)"
fi
if [ -z "$IDENTITY" ]; then
    echo "No \"Developer ID Application\" identity in the keychain." >&2
    exit 1
fi

OUT="dist/release"
APP="$OUT/Chotki.app"
SLUG="$(echo "$CHOTKI_VERSION" | tr ' ,' '--' | tr -s '-')"      # 1.0-beta-build-34
DMG="$OUT/Chotki-$SLUG.dmg"

echo "==> signing as: $IDENTITY"
echo "==> notary profile: $PROFILE"

echo "==> building the universal release"
./build-app.sh release

rm -rf "$OUT"
mkdir -p "$OUT"
cp -R dist/Chotki.app "$APP"
xattr -cr "$APP"

echo "==> signing the app (Developer ID, hardened runtime, secure timestamp)"
codesign --force --options runtime --timestamp --sign "$IDENTITY" "$APP"
codesign --verify --deep --strict --verbose=2 "$APP" 2>&1 | sed 's/^/    /'

# A debuggable build cannot be notarised, and a release one should never carry
# the entitlement; say so here rather than let Apple say it ten minutes later.
if codesign -d --entitlements - "$APP" 2>&1 | grep -q "get-task-allow"; then
    echo "The app carries com.apple.security.get-task-allow and cannot be notarised." >&2
    exit 1
fi
codesign -dv "$APP" 2>&1 | grep -E "Identifier|Authority=Developer|TeamIdentifier|flags|Timestamp" | sed 's/^/    /'

notarise() {
    # $1 = the file to submit. Fails with Apple's log if it is not accepted.
    local file="$1" result id status
    result="$(xcrun notarytool submit "$file" --keychain-profile "$PROFILE" --wait 2>&1)" || true
    echo "$result" | sed 's/^/    /'
    id="$(echo "$result" | sed -n 's/^ *id: *//p' | head -1)"
    status="$(echo "$result" | sed -n 's/^ *status: *//p' | tail -1)"
    if [ "$status" != "Accepted" ]; then
        echo "Notarisation of $file ended as: ${status:-unknown}" >&2
        if [ -n "$id" ]; then xcrun notarytool log "$id" --keychain-profile "$PROFILE" >&2 || true; fi
        exit 1
    fi
}

echo "==> notarising the app"
ZIP="$OUT/Chotki-notarise.zip"
ditto -c -k --keepParent --noextattr --norsrc "$APP" "$ZIP"
notarise "$ZIP"
rm -f "$ZIP"

echo "==> stapling the app"
xcrun stapler staple "$APP" 2>&1 | sed 's/^/    /'
xcrun stapler validate "$APP" 2>&1 | sed 's/^/    /'

echo "==> building the disk image"
STAGE="$OUT/stage"
rm -rf "$STAGE"
mkdir -p "$STAGE"
ditto "$APP" "$STAGE/Chotki.app"
ln -s /Applications "$STAGE/Applications"
hdiutil create -volname "Chotki" -srcfolder "$STAGE" -ov -format UDZO -fs HFS+ "$DMG" 2>&1 | sed 's/^/    /'
rm -rf "$STAGE"

echo "==> signing the disk image"
codesign --force --timestamp --sign "$IDENTITY" "$DMG"
codesign --verify --verbose=2 "$DMG" 2>&1 | sed 's/^/    /'

echo "==> notarising the disk image"
notarise "$DMG"

echo "==> stapling the disk image"
xcrun stapler staple "$DMG" 2>&1 | sed 's/^/    /'
xcrun stapler validate "$DMG" 2>&1 | sed 's/^/    /'

echo "==> asking Gatekeeper (assessing, not running)"
spctl --assess --type open --context context:primary-signature --verbose=4 "$DMG" 2>&1 | sed 's/^/    /'
MOUNT="$(mktemp -d /tmp/chotki-dmg.XXXXXX)"
hdiutil attach "$DMG" -nobrowse -readonly -mountpoint "$MOUNT" >/dev/null
spctl --assess --type execute --verbose=4 "$MOUNT/Chotki.app" 2>&1 | sed 's/^/    /'
xcrun stapler validate "$MOUNT/Chotki.app" 2>&1 | sed 's/^/    /'
hdiutil detach "$MOUNT" >/dev/null
rmdir "$MOUNT"

echo "==> done"
ls -la "$DMG" | sed 's/^/    /'
shasum -a 256 "$DMG" | sed 's/^/    /'
