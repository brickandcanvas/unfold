#!/bin/zsh
set -e
cd "$(dirname "$0")"

swift build -c release

APP="Unfold.app"
BUNDLE_ID="com.bricksandcanvas.unfold"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/release/Unfold "$APP/Contents/MacOS/Unfold"

if [ -f app_icon.png ]; then
    ICONSET=$(mktemp -d)/AppIcon.iconset
    mkdir -p "$ICONSET"
    sizes=(16 32 32 64 128 256 256 512 512 1024)
    names=(icon_16x16 icon_16x16@2x icon_32x32 icon_32x32@2x \
           icon_128x128 icon_128x128@2x icon_256x256 icon_256x256@2x \
           icon_512x512 icon_512x512@2x)
    for i in {1..10}; do
        sips -z "${sizes[$i]}" "${sizes[$i]}" app_icon.png \
            --out "$ICONSET/${names[$i]}.png" >/dev/null
    done
    iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"
    rm -rf "$(dirname "$ICONSET")"
    ICON_KEY="    <key>CFBundleIconFile</key>
    <string>AppIcon</string>"
else
    ICON_KEY=""
fi

cat > "$APP/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>Unfold</string>
    <key>CFBundleIdentifier</key>
    <string>$BUNDLE_ID</string>
    <key>CFBundleName</key>
    <string>Unfold</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSHighResolutionCapable</key>
    <true/>
$ICON_KEY
</dict>
</plist>
EOF

# Prefer Developer ID (distribution) if present, else Apple Development (dev-only),
# else ad-hoc. Developer ID builds get hardened runtime so they're notarizable.
IDENTITY="${UNFOLD_SIGNING_IDENTITY:-}"
if [ -z "$IDENTITY" ]; then
    IDENTITY=$(security find-identity -v -p codesigning 2>/dev/null \
        | grep "Developer ID Application" | head -1 \
        | sed -E 's/.*"(.*)"/\1/')
fi
if [ -z "$IDENTITY" ]; then
    IDENTITY=$(security find-identity -v -p codesigning 2>/dev/null \
        | grep "Apple Development" | head -1 \
        | sed -E 's/.*"(.*)"/\1/')
fi
if [ -n "$IDENTITY" ]; then
    if [[ "$IDENTITY" == Developer\ ID\ Application* ]]; then
        codesign --force --sign "$IDENTITY" --identifier "$BUNDLE_ID" \
            --options runtime --timestamp "$APP"
    else
        codesign --force --sign "$IDENTITY" --identifier "$BUNDLE_ID" "$APP"
    fi
    echo "Built $APP (signed: $IDENTITY)"
else
    codesign --force --sign - --identifier "$BUNDLE_ID" "$APP"
    echo "Built $APP (ad-hoc; permissions may not persist across rebuilds)"
fi
codesign -dv "$APP" 2>&1 | grep -E "Authority|Identifier"
