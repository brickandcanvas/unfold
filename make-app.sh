#!/bin/zsh
set -e
cd "$(dirname "$0")"

swift build -c release

APP="CloseFadeIn.app"
BUNDLE_ID="com.bricksandcanvas.closefadein"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp .build/release/CloseFadeIn "$APP/Contents/MacOS/CloseFadeIn"

cat > "$APP/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>CloseFadeIn</string>
    <key>CFBundleIdentifier</key>
    <string>$BUNDLE_ID</string>
    <key>CFBundleName</key>
    <string>CloseFadeIn</string>
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
</dict>
</plist>
EOF

# Prefer a stable signing identity so TCC (Screen Recording / Input Monitoring)
# permissions persist across rebuilds. Falls back to ad-hoc.
IDENTITY="${CFI_SIGNING_IDENTITY:-}"
if [ -z "$IDENTITY" ]; then
    IDENTITY=$(security find-identity -v -p codesigning 2>/dev/null \
        | grep "Apple Development" | head -1 \
        | sed -E 's/.*"(.*)"/\1/')
fi
if [ -n "$IDENTITY" ]; then
    codesign --force --sign "$IDENTITY" --identifier "$BUNDLE_ID" "$APP"
    echo "Built $APP (signed: $IDENTITY)"
else
    codesign --force --sign - --identifier "$BUNDLE_ID" "$APP"
    echo "Built $APP (ad-hoc; permissions may not persist across rebuilds)"
fi
codesign -dv "$APP" 2>&1 | grep -E "Authority|Identifier"
