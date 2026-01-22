#!/usr/bin/env bash
set -e

BASE_DIR="$(cd "$(dirname "$0")" && pwd)"
source "${BASE_DIR}/venv/bin/activate"

echo "🚀 Starting Docling Serve..."
echo "🌐 http://localhost:5001/ui"

# Docling Serve settings (match Curatore defaults)
export DOCLING_SERVE_ENABLE_REMOTE_SERVICES=1
export DOCLING_SERVE_ENABLE_UI=1
export DOCLING_SERVE_MAX_SYNC_WAIT="${DOCLING_SERVE_MAX_SYNC_WAIT:-300}"
export DOCLING_SERVE_ARTIFACTS_PATH="${DOCLING_SERVE_ARTIFACTS_PATH:-${BASE_DIR}/artifacts}"

# Apple Silicon optimizations
export DOCLING_APPLE_OPTIMIZED=1
export DOCLING_DEVICE=auto
export DOCLING_NUM_THREADS="${DOCLING_NUM_THREADS:-8}"
export DOCLING_PERF_PAGE_BATCH_SIZE="${DOCLING_PERF_PAGE_BATCH_SIZE:-4}"
export PYTORCH_ENABLE_MPS_FALLBACK=1
export TOKENIZERS_PARALLELISM=false

# Paths
export DOCLING_ARTIFACTS_PATH="${DOCLING_ARTIFACTS_PATH:-${BASE_DIR}/artifacts}"
export DOCLING_SCRATCH_PATH="${DOCLING_SCRATCH_PATH:-${BASE_DIR}/scratch}"

# Menu bar patch: capture task IDs from UI async requests.
PATCH_DIR="${BASE_DIR}/macos/DoclingMenuBar/patches"
if [[ -d "${PATCH_DIR}" ]]; then
  export PYTHONPATH="${PATCH_DIR}:${PYTHONPATH:-}"
fi

# Server binding
export UVICORN_HOST="${UVICORN_HOST:-127.0.0.1}"
export UVICORN_PORT="${UVICORN_PORT:-5001}"

if command -v docling-serve >/dev/null 2>&1; then
  exec docling-serve run
else
  echo "❌ docling-serve is not installed in this virtual environment."
  echo "👉 Activate the venv and run: pip install -r requirements.txt"
  exit 1
fi
