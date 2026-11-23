#!/bin/bash
# Builds build/MouseBattery.app for Apple Silicon and Intel Macs.
#   ./build.sh         build the app
#   ./build.sh --zip   also create build/MouseBattery.zip for a GitHub release
set -euo pipefail
cd "$(dirname "$0")"

APP="build/MouseBattery.app"
BINARY="$APP/Contents/MacOS/MouseBattery"
MIN_MACOS="13.0"

rm -rf "$APP" build/MouseBattery.zip
mkdir -p "$APP/Contents/MacOS"

for arch in arm64 x86_64; do
    swiftc -O -swift-version 5 -target "$arch-apple-macos$MIN_MACOS" Sources/*.swift -o "build/MouseBattery-$arch"
done
lipo -create build/MouseBattery-arm64 build/MouseBattery-x86_64 -output "$BINARY"
rm build/MouseBattery-arm64 build/MouseBattery-x86_64

cat > "$APP/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleIdentifier</key><string>com.jstel.mouse-battery</string>
    <key>CFBundleName</key><string>MouseBattery</string>
    <key>CFBundleExecutable</key><string>MouseBattery</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>1.0</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>LSMinimumSystemVersion</key><string>$MIN_MACOS</string>
    <key>LSUIElement</key><true/>
</dict>
</plist>
EOF

# Ad-hoc signature: enough to run, but macOS still asks for confirmation on first launch.
codesign --force --sign - "$APP"
echo "Built $APP"

if [[ "${1:-}" == "--zip" ]]; then
    ditto -c -k --keepParent "$APP" build/MouseBattery.zip
    echo "Packaged build/MouseBattery.zip"
fi
