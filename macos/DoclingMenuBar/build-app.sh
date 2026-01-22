#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
APP_NAME="DoclingMenuBar"
APP_ID="com.docling.menubar"
APP_DIR="$ROOT_DIR/build/${APP_NAME}.app"
BIN_NAME="DoclingMenuBar"
SRC="$ROOT_DIR/macos/DoclingMenuBar/main.swift"
ASSETS_DIR="$ROOT_DIR/macos/DoclingMenuBar/assets"
ICON_PPM="$ASSETS_DIR/icon.ppm"
ICONSET_DIR="$ROOT_DIR/build/AppIcon.iconset"

mkdir -p "$ROOT_DIR/build"
rm -rf "$APP_DIR" "$ICONSET_DIR"

mkdir -p "$APP_DIR/Contents/MacOS"
mkdir -p "$APP_DIR/Contents/Resources"

swiftc -o "$APP_DIR/Contents/MacOS/$BIN_NAME" "$SRC"

# Build app icon from a tiny PPM to avoid external dependencies.
if [[ ! -f "$ICON_PPM" ]]; then
  echo "Missing icon source at $ICON_PPM" >&2
  exit 1
fi

BASE_PNG="$ROOT_DIR/build/icon-base.png"
/usr/bin/sips -s format png "$ICON_PPM" --out "$BASE_PNG" >/dev/null

mkdir -p "$ICONSET_DIR"
for size in 16 32 64 128 256 512 1024; do
  /usr/bin/sips -z $size $size "$BASE_PNG" --out "$ICONSET_DIR/icon_${size}x${size}.png" >/dev/null
  if [[ $size -lt 1024 ]]; then
    double=$((size * 2))
    /usr/bin/sips -z $double $double "$BASE_PNG" --out "$ICONSET_DIR/icon_${size}x${size}@2x.png" >/dev/null
  fi
done

/usr/bin/iconutil -c icns "$ICONSET_DIR" -o "$APP_DIR/Contents/Resources/AppIcon.icns"

cat > "$APP_DIR/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key>
  <string>${APP_NAME}</string>
  <key>CFBundleIdentifier</key>
  <string>${APP_ID}</string>
  <key>CFBundleExecutable</key>
  <string>${BIN_NAME}</string>
  <key>CFBundleVersion</key>
  <string>1.0</string>
  <key>CFBundleShortVersionString</key>
  <string>1.0</string>
  <key>CFBundleIconFile</key>
  <string>AppIcon</string>
  <key>LSUIElement</key>
  <true/>
</dict>
</plist>
PLIST

echo "Built $APP_DIR"
