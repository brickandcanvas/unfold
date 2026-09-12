#!/bin/zsh
set -e
cd "$(dirname "$0")"

./make-app.sh

APP="Unfold.app"
VOLNAME="Unfold"
DMG="Unfold.dmg"
NOTARY_PROFILE="${UNFOLD_NOTARY_PROFILE:-unfold-notary}"

rm -f "$DMG"

STAGE=$(mktemp -d)
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"

hdiutil create \
    -volname "$VOLNAME" \
    -srcfolder "$STAGE" \
    -ov -format UDZO \
    "$DMG" >/dev/null

rm -rf "$STAGE"

IDENTITY=$(security find-identity -v -p codesigning 2>/dev/null \
    | grep "Developer ID Application" | head -1 \
    | sed -E 's/.*"(.*)"/\1/')

if [ -n "$IDENTITY" ]; then
    codesign --force --sign "$IDENTITY" --timestamp "$DMG"
    echo "Signed $DMG with: $IDENTITY"

    if xcrun notarytool history --keychain-profile "$NOTARY_PROFILE" >/dev/null 2>&1; then
        echo "Submitting to Apple for notarization..."
        xcrun notarytool submit "$DMG" \
            --keychain-profile "$NOTARY_PROFILE" \
            --wait
        xcrun stapler staple "$DMG"
        echo "Notarized and stapled."
    else
        echo "Skipped notarization: no stored credentials under profile '$NOTARY_PROFILE'."
        echo "To enable: xcrun notarytool store-credentials \"$NOTARY_PROFILE\" \\"
        echo "    --apple-id you@example.com --team-id ABCD123456 --password xxxx-xxxx-xxxx-xxxx"
    fi
else
    echo "Built $DMG (unsigned — Gatekeeper will warn on other machines)."
fi

ls -lh "$DMG"
