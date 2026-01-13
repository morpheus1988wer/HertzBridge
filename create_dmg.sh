#!/bin/bash

APP_NAME="HertzBridge"
VERSION="v1.3"
DMG_NAME="${APP_NAME}_${VERSION}.dmg"
BUILD_DIR=".build/release"
APP_BUNDLE="${APP_NAME}.app"

echo "🚀 Starting build for ${APP_NAME} ${VERSION}..."

# 1. Clean and Build
echo "📦 Building Release..."
swift build -c release

# 2. Create App Bundle Structure
echo "📂 Creating App Bundle..."
rm -rf "$APP_BUNDLE"
mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Resources"

# 3. Copy Executable
echo "COPY Executable..."
cp "$BUILD_DIR/$APP_NAME" "$APP_BUNDLE/Contents/MacOS/"

# 4. Copy Resources (Icon)
echo "COPY Resources..."
if [ -f "Sources/HertzBridge/Resources/AppIcon.icns" ]; then
    cp "Sources/HertzBridge/Resources/AppIcon.icns" "$APP_BUNDLE/Contents/Resources/"
else 
    echo "⚠️ Warning: AppIcon.icns not found!"
fi

# 5. Create Info.plist
# LSUIElement=1 makes it a menu bar app (no dock icon)
echo "📝 Generating Info.plist..."
cat > "$APP_BUNDLE/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>${APP_NAME}</string>
    <key>CFBundleIdentifier</key>
    <string>com.example.${APP_NAME}</string>
    <key>CFBundleName</key>
    <string>${APP_NAME}</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundleShortVersionString</key>
    <string>1.3</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSAppleEventsUsageDescription</key>
    <string>HertzBridge needs to control Music to detect the current track's sample rate.</string>
</dict>
</plist>
EOF

# 6. Create DMG
echo "💿 Creating DMG..."
rm -f "$DMG_NAME"
hdiutil create -volname "${APP_NAME} ${VERSION}" -srcfolder "$APP_BUNDLE" -ov -format UDZO "$DMG_NAME"

echo "✅ Done! Created $DMG_NAME"
