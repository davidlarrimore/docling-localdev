#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
APP_PATH="$ROOT_DIR/build/DoclingMenuBar.app"
PLIST_LABEL="com.docling.menubar"
PLIST_PATH="$HOME/Library/LaunchAgents/${PLIST_LABEL}.plist"

# Verify app exists
if [[ ! -d "$APP_PATH" ]]; then
    echo "Error: App not found at $APP_PATH" >&2
    echo "Run ./macos/DoclingMenuBar/build-app.sh first." >&2
    exit 1
fi

# Unload existing agent if present
launchctl unload "$PLIST_PATH" 2>/dev/null || true

# Create LaunchAgent plist
mkdir -p "$HOME/Library/LaunchAgents"

cat > "$PLIST_PATH" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>${PLIST_LABEL}</string>
    <key>ProgramArguments</key>
    <array>
        <string>/usr/bin/open</string>
        <string>-a</string>
        <string>${APP_PATH}</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <false/>
</dict>
</plist>
PLIST

# Load the agent
launchctl load "$PLIST_PATH"

echo "Installed LaunchAgent: $PLIST_PATH"
echo "The app will start automatically at login."
echo ""
echo "To uninstall:"
echo "  launchctl unload $PLIST_PATH"
echo "  rm $PLIST_PATH"
