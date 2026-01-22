# Repository Guidelines

## Project Structure & Module Organization
- `macos/DoclingMenuBar/`: Swift menu bar app source (`main.swift`) and build scripts.
- `build/`: Generated app bundle and icon artifacts.
- `artifacts/` and `scratch/`: Docling Serve output and temporary working data.
- `run-docling-local-apple-silicon.sh`: Local runner for Docling Serve with environment defaults.
- `logo.png`: App icon source used by build script.

## Build, Test, and Development Commands
- `./macos/DoclingMenuBar/build-app.sh`: Builds `build/DoclingMenuBar.app` from `main.swift` and `logo.png`.
- `open build/DoclingMenuBar.app`: Launches the menu bar app bundle.
- `./macos/DoclingMenuBar/install-launchagent.sh`: Installs a LaunchAgent to start the app at login.
- `./run-docling-local-apple-silicon.sh`: Starts Docling Serve using the local virtual environment.

## Coding Style & Naming Conventions
- Swift: follow existing style in `macos/DoclingMenuBar/main.swift` (4-space indentation, `camelCase` for vars, `UpperCamelCase` for types).
- Bash: keep `set -euo pipefail`, quote variables, and use uppercase for exported env vars.
- Filenames are `kebab-case` for scripts and `UpperCamelCase` for app bundles/binaries.

## Testing Guidelines
- No automated tests are present; focus on manual validation.
- Suggested checks: build the app, launch it, and verify it starts Docling Serve automatically.

## Commit & Pull Request Guidelines
- Commit messages in history are short, imperative, and capitalized (e.g., "Add macOS menu bar app...").
- PRs should include a clear summary, steps to validate, and screenshots for UI changes.

## Configuration & Runtime Notes
- Menu bar config: `~/Library/Application Support/DoclingMenuBar/config.json`.
- The app auto-detects the Docling installation path on startup.
- Config options: `baseURL`, `pollIntervalSeconds`, `doclingInstallPath`, `autoStartOnLaunch`.
