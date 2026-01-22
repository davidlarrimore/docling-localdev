# Docling for macOS (Apple Silicon)

This repository streamlines local deployment of Docling on macOS, with defaults tuned for Apple Silicon GPU acceleration (Metal/MPS). The goal is to make it easy to run Docling Serve locally, manage artifacts, and optionally run a small menu bar status app that monitors task progress.

## What This Project Provides
- A repeatable macOS setup script that creates a Python 3.12 virtual environment and installs Docling + Docling Serve.
- Apple Silicon environment defaults for better performance (e.g., `DOCLING_DEVICE=auto`, `PYTORCH_ENABLE_MPS_FALLBACK=1`).
- A `run-docling-local-apple-silicon.sh` helper to start Docling Serve locally with consistent settings.
- An optional Swift-based menu bar app (kept locally during iteration) to monitor server health and task status.

## Ways To Deploy Docling
Choose the workflow that fits how you want to run Docling Serve locally on Apple Silicon.

### Option A: Local Serve (Script)
Use the Apple Silicon runner to start Docling Serve directly from the terminal.

1) Install dependencies and download models:
   ```bash
   ./setup.sh
   ```

2) Start Docling Serve:
   ```bash
   ./run-docling-local-apple-silicon.sh
   ```

3) Open the UI:
   ```bash
   open http://localhost:5001/ui
   ```

Artifacts are stored in `artifacts/`, and scratch data is stored in `scratch/` by default.

### Option B: Menu Bar App (Optional)
Run the Swift menu bar app to monitor tasks and optionally start/stop the service.
The macOS app sources are ignored in git during iteration, so only use this path if
you have `macos/DoclingMenuBar/` locally.

1) Build and open the app bundle:
   ```bash
   ./macos/DoclingMenuBar/build-app.sh
   open build/DoclingMenuBar.app
   ```

2) Configure the app (separate from the runner script):
   - `~/Library/Application Support/DoclingMenuBar/config.json`
   - Set `serviceScriptPath` to `./run-docling-local-apple-silicon.sh` (absolute path recommended).

### Option C: LaunchAgent (Auto-start)
Auto-start the menu bar app at login after building it once.

```bash
./macos/DoclingMenuBar/install-launchagent.sh
```

## GPU Acceleration on macOS
The setup and run scripts set Apple Silicon-friendly defaults so Docling can leverage MPS (Metal Performance Shaders). Key environment variables include:
- `DOCLING_DEVICE=auto`
- `DOCLING_APPLE_OPTIMIZED=1`
- `PYTORCH_ENABLE_MPS_FALLBACK=1`

You can override any of these variables in your shell or by editing `run-docling-local-apple-silicon.sh`.

## Project Layout
- `setup.sh`: Installs dependencies, downloads models, and configures the environment.
- `run-docling-local-apple-silicon.sh`: Starts Docling Serve locally with macOS-optimized defaults.
- `requirements.txt`: Pinned dependencies for Docling + Serve.
- `build/`: Generated app bundle and icon artifacts (created locally).
- `macos/`: Optional menu bar app sources (ignored during iteration).

## Notes
- This repo assumes macOS with Apple Silicon (M1/M2/M3). Intel Macs may need adjustments.
- If `docling-serve` is missing, re-run `./setup.sh` or `pip install -r requirements.txt` inside `venv/`.
