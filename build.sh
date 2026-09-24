#!/bin/bash

# Build script for Mouse Toucher app (Production)
set -euo pipefail

# Universal by default. Use ARCHS=arm64 with toolchains lacking Intel runtimes.
read -r -a ARCHITECTURES <<< "${ARCHS:-arm64 x86_64}"
for architecture in "${ARCHITECTURES[@]}"; do
    case "$architecture" in
        arm64|x86_64) ;;
        *) echo "Unsupported architecture: $architecture"; exit 1 ;;
    esac
done

APP_NAME="MouseToucher 2.2"
BUILD_DIR="build"
APP_PATH="$BUILD_DIR/$APP_NAME.app"
ICON_SOURCE="Assets/AppIcon.png"
ICONSET_PATH="$BUILD_DIR/AppIcon.iconset"

echo "=========================================="
echo "Building Mouse Toucher (${ARCHITECTURES[*]})"
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

# Compile each requested architecture. Both use the same sources and minimum OS.
BINARIES=()
for architecture in "${ARCHITECTURES[@]}"; do
    echo "📦 Compiling for $architecture..."
    BINARY_PATH="$BUILD_DIR/${APP_NAME}_$architecture"
    swiftc -o "$BINARY_PATH" \
        -target "$architecture-apple-macos11.0" \
        -import-objc-header MultitouchBridge.h \
        -framework Cocoa \
        -framework ApplicationServices \
        -framework ServiceManagement \
        -F /System/Library/PrivateFrameworks \
        -framework MultitouchSupport \
        -Xlinker -rpath -Xlinker /System/Library/PrivateFrameworks \
        Sources/MouseToucherLib/CompoundTapDetector.swift \
        MouseToucherSettings.swift \
        DragEventMonitor.swift \
        WindowDragController.swift \
        NativeMagnificationEmitter.swift \
        MultitouchManager.swift \
        SettingsWindowController.swift \
        AppDelegate.swift \
        main.swift
    BINARIES+=("$BINARY_PATH")
done

# lipo also accepts a single architecture for a native-only build.
echo "🔗 Creating application executable..."
lipo -create "${BINARIES[@]}" -output "$APP_PATH/Contents/MacOS/$APP_NAME"
rm "${BINARIES[@]}"

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
echo "✅ BUILD COMPLETE!"
echo "=========================================="
echo ""
echo "App location: $APP_PATH"
lipo -info "$APP_PATH/Contents/MacOS/$APP_NAME"
echo ""
echo "To run the app:"
echo "  open \"$APP_PATH\""
echo ""
echo "To install the app (copy to Applications):"
echo "  cp -r \"$APP_PATH\" /Applications/"
echo ""
