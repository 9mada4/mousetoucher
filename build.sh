#!/bin/bash

# Build script for Mouse Toucher app (Production)

APP_NAME="MouseToucher 1.7"
BUILD_DIR="build"
APP_PATH="$BUILD_DIR/$APP_NAME.app"
ICON_SOURCE="Assets/AppIcon.png"
ICONSET_PATH="$BUILD_DIR/AppIcon.iconset"

echo "=========================================="
echo "Building Mouse Toucher (Universal Binary)"
echo "=========================================="

# Clean previous build
rm -rf "$APP_PATH"
mkdir -p "$BUILD_DIR"

# Create app bundle structure
mkdir -p "$APP_PATH/Contents/MacOS"
mkdir -p "$APP_PATH/Contents/Resources"

# Generate the full macOS icon set from the checked-in 1024px+ source image.
if [ ! -f "$ICON_SOURCE" ]; then
    echo "❌ App icon source is missing: $ICON_SOURCE"
    exit 1
fi

rm -rf "$ICONSET_PATH"
mkdir -p "$ICONSET_PATH"
sips -z 16 16 "$ICON_SOURCE" --out "$ICONSET_PATH/icon_16x16.png" >/dev/null
sips -z 32 32 "$ICON_SOURCE" --out "$ICONSET_PATH/icon_16x16@2x.png" >/dev/null
sips -z 32 32 "$ICON_SOURCE" --out "$ICONSET_PATH/icon_32x32.png" >/dev/null
sips -z 64 64 "$ICON_SOURCE" --out "$ICONSET_PATH/icon_32x32@2x.png" >/dev/null
sips -z 128 128 "$ICON_SOURCE" --out "$ICONSET_PATH/icon_128x128.png" >/dev/null
sips -z 256 256 "$ICON_SOURCE" --out "$ICONSET_PATH/icon_128x128@2x.png" >/dev/null
sips -z 256 256 "$ICON_SOURCE" --out "$ICONSET_PATH/icon_256x256.png" >/dev/null
sips -z 512 512 "$ICON_SOURCE" --out "$ICONSET_PATH/icon_256x256@2x.png" >/dev/null
sips -z 512 512 "$ICON_SOURCE" --out "$ICONSET_PATH/icon_512x512.png" >/dev/null
sips -z 1024 1024 "$ICON_SOURCE" --out "$ICONSET_PATH/icon_512x512@2x.png" >/dev/null
iconutil -c icns "$ICONSET_PATH" -o "$APP_PATH/Contents/Resources/AppIcon.icns"
rm -rf "$ICONSET_PATH"

# Compile for Apple Silicon (arm64)
echo "📦 Compiling for Apple Silicon (arm64)..."
swiftc -o "$BUILD_DIR/${APP_NAME}_arm64" \
    -target arm64-apple-macos11.0 \
    -import-objc-header MultitouchBridge.h \
    -framework Cocoa \
    -framework ApplicationServices \
    -framework ServiceManagement \
    -F /System/Library/PrivateFrameworks \
    -framework MultitouchSupport \
    -Xlinker -rpath -Xlinker /System/Library/PrivateFrameworks \
    Sources/MouseToucherLib/CompoundTapDetector.swift \
    MouseToucherSettings.swift \
    MultitouchManager.swift \
    SettingsWindowController.swift \
    AppDelegate.swift \
    main.swift

if [ $? -ne 0 ]; then
    echo "❌ arm64 compilation failed!"
    exit 1
fi

# Compile for Intel (x86_64)
echo "📦 Compiling for Intel (x86_64)..."
swiftc -o "$BUILD_DIR/${APP_NAME}_x86_64" \
    -target x86_64-apple-macos11.0 \
    -import-objc-header MultitouchBridge.h \
    -framework Cocoa \
    -framework ApplicationServices \
    -framework ServiceManagement \
    -F /System/Library/PrivateFrameworks \
    -framework MultitouchSupport \
    -Xlinker -rpath -Xlinker /System/Library/PrivateFrameworks \
    Sources/MouseToucherLib/CompoundTapDetector.swift \
    MouseToucherSettings.swift \
    MultitouchManager.swift \
    SettingsWindowController.swift \
    AppDelegate.swift \
    main.swift

if [ $? -ne 0 ]; then
    echo "❌ x86_64 compilation failed!"
    exit 1
fi

# Create universal binary
echo "🔗 Creating universal binary..."
lipo -create \
    "$BUILD_DIR/${APP_NAME}_arm64" \
    "$BUILD_DIR/${APP_NAME}_x86_64" \
    -output "$APP_PATH/Contents/MacOS/$APP_NAME"

if [ $? -ne 0 ]; then
    echo "❌ Failed to create universal binary!"
    exit 1
fi

# Clean up temporary files
rm "$BUILD_DIR/${APP_NAME}_arm64" "$BUILD_DIR/${APP_NAME}_x86_64"

# Copy Info.plist
cp Info.plist "$APP_PATH/Contents/"

# Ad-hoc sign the app bundle so macOS Accessibility permissions persist
echo "[34m[1m[0m"
echo "[34m[1m[0m"
echo "[34m[1mCodesigning app bundle...[0m"
codesign --force --deep --sign - "$APP_PATH"

if [ $? -ne 0 ]; then
    echo "❌ Codesigning failed!"
    exit 1
fi

echo ""
echo "=========================================="
echo "✅ UNIVERSAL BINARY BUILD COMPLETE!"
echo "=========================================="
echo ""
echo "App location: $APP_PATH"
echo "Architectures: arm64 (Apple Silicon) + x86_64 (Intel)"
echo ""
echo "To run the app:"
echo "  open \"$APP_PATH\""
echo ""
echo "To install the app (copy to Applications):"
echo "  cp -r \"$APP_PATH\" /Applications/"
echo ""
