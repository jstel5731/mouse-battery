#!/bin/bash
# Builds and packages build/MouseBattery.app
set -euo pipefail
cd "$(dirname "$0")"

APP="build/MouseBattery.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"

swiftc -O -swift-version 5 Sources/*.swift -o "$APP/Contents/MacOS/MouseBattery"

cat > "$APP/Contents/Info.plist" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleIdentifier</key><string>local.mousebattery</string>
    <key>CFBundleName</key><string>MouseBattery</string>
    <key>CFBundleExecutable</key><string>MouseBattery</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>1.0</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>LSMinimumSystemVersion</key><string>13.0</string>
    <key>LSUIElement</key><true/>
</dict>
</plist>
EOF

codesign --force --sign - "$APP"
echo "Built $APP"
