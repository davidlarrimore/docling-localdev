Docling Menu Bar Status

This is a small macOS menu bar app that polls Docling Serve and shows active task status.

What it can do
- Shows a menu bar icon with active task count.
- Tooltip displays server online/offline and active task count.
- Add task IDs manually or from clipboard.

Build and run
1) Build a double-clickable app bundle:
   ./macos/DoclingMenuBar/build-app.sh

2) Open the app:
   open build/DoclingMenuBar.app

3) (Optional) Build only the executable:
   swiftc -o DoclingMenuBar macos/DoclingMenuBar/main.swift

4) Run it directly:
   ./DoclingMenuBar

Config
A config file is read from:
~/Library/Application Support/DoclingMenuBar/config.json

Example config:
{
  "baseURL": "http://127.0.0.1:5001",
  "apiKey": "",
  "pollSeconds": 5,
  "serviceScriptPath": "/Users/davidlarrimore/Documents/Github/docling/run-docling.sh",
  "serviceWorkingDirectory": "/Users/davidlarrimore/Documents/Github/docling"
}

Tasks are stored at:
~/Library/Application Support/DoclingMenuBar/tasks.json

Icon
The build script generates an .icns from macos/DoclingMenuBar/assets/icon.ppm.
Change that file and rebuild to customize the app icon.

Task monitoring
The app watches Docling Serve stdout/stderr and will auto-add any task IDs it sees
in log lines (UUID format). When the service is started by the app, a small
`sitecustomize.py` patch logs task IDs emitted by the UI async requests.

Auto-start on login
1) Build the app:
   ./macos/DoclingMenuBar/build-app.sh

2) Install LaunchAgent:
   ./macos/DoclingMenuBar/install-launchagent.sh
