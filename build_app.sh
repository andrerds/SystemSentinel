#!/bin/bash
set -e

echo "🔨 Building SystemSentinel (Release)..."
swift build -c release

APP_DIR="/Applications/SystemSentinel.app"
echo "📦 Packaging to $APP_DIR..."

rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS"
mkdir -p "$APP_DIR/Contents/Resources"

cp .build/release/SystemSentinel "$APP_DIR/Contents/MacOS/SystemSentinel"
chmod +x "$APP_DIR/Contents/MacOS/SystemSentinel"

if [ -f "AppIcon.icns" ]; then
    cp AppIcon.icns "$APP_DIR/Contents/Resources/AppIcon.icns"
fi

cat << 'EOF' > "$APP_DIR/Contents/Info.plist"
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleIdentifier</key>
    <string>com.andrerds.SystemSentinel</string>
    <key>CFBundleName</key>
    <string>SystemSentinel</string>
    <key>CFBundleDisplayName</key>
    <string>System Sentinel</string>
    <key>CFBundleExecutable</key>
    <string>SystemSentinel</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundleIconName</key>
    <string>AppIcon</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSSupportsAutomaticGraphicsSwitching</key>
    <true/>
</dict>
</plist>
EOF

codesign --force --deep --sign - "$APP_DIR"

echo "✅ SystemSentinel.app instalado em /Applications com sucesso!"
