#!/usr/bin/env bash
set -euo pipefail

# Paths
ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
APP_NAME="DoclingMenuBar"
APP_ID="com.docling.menubar"
APP_DIR="$ROOT_DIR/build/${APP_NAME}.app"
SRC="$ROOT_DIR/macos/DoclingMenuBar/main.swift"

# Icon source - use logo.png from repo root, allow override
ICON_SOURCE="${ICON_SOURCE:-$ROOT_DIR/logo.png}"
ICONSET_DIR="${ICONSET_DIR:-$ROOT_DIR/build/AppIcon.iconset}"

echo "Building $APP_NAME..."

# Clean previous build
mkdir -p "$ROOT_DIR/build"
rm -rf "$APP_DIR" "$ICONSET_DIR"

# Create app bundle structure
mkdir -p "$APP_DIR/Contents/MacOS"
mkdir -p "$APP_DIR/Contents/Resources"

# Compile Swift code
echo "Compiling Swift..."
swiftc -O -o "$APP_DIR/Contents/MacOS/$APP_NAME" "$SRC"

# Generate app icon from logo.png
echo "Generating app icon..."
if [[ ! -f "$ICON_SOURCE" ]]; then
    echo "Warning: Icon source not found at $ICON_SOURCE"
    echo "App will be built without a custom icon."
else
    mkdir -p "$ICONSET_DIR"

    # Generate all required icon sizes using sips
    for size in 16 32 64 128 256 512; do
        /usr/bin/sips -z $size $size "$ICON_SOURCE" \
            --out "$ICONSET_DIR/icon_${size}x${size}.png" >/dev/null 2>&1

        # Generate @2x retina versions
        double=$((size * 2))
        /usr/bin/sips -z $double $double "$ICON_SOURCE" \
            --out "$ICONSET_DIR/icon_${size}x${size}@2x.png" >/dev/null 2>&1
    done

    # Convert iconset to icns
    /usr/bin/iconutil -c icns "$ICONSET_DIR" -o "$APP_DIR/Contents/Resources/AppIcon.icns"
    echo "Icon generated."
fi

# Create Info.plist
cat > "$APP_DIR/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>
    <string>${APP_NAME}</string>
    <key>CFBundleDisplayName</key>
    <string>Docling Menu Bar</string>
    <key>CFBundleIdentifier</key>
    <string>${APP_ID}</string>
    <key>CFBundleExecutable</key>
    <string>${APP_NAME}</string>
    <key>CFBundleVersion</key>
    <string>1.0.0</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0.0</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>LSMinimumSystemVersion</key>
    <string>12.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSHighResolutionCapable</key>
    <true/>
</dict>
</plist>
PLIST

echo ""
echo "Built: $APP_DIR"
echo ""
echo "To run: open $APP_DIR"
