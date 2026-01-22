#!/usr/bin/env bash
set -e

echo "🔧 Setting up Docling for Apple Silicon (M2 Pro)"

# -----------------------------
# Configuration
# -----------------------------
PYTHON_BIN="python3.12"
VENV_DIR="venv"
ARTIFACTS_DIR="$(pwd)/artifacts"
SCRATCH_DIR="$(pwd)/scratch"
LOGS_DIR="$(pwd)/logs"
ROOT_DIR="$(pwd)"

# -----------------------------
# Clean previous setup
# -----------------------------
echo "🧹 Cleaning existing setup..."
rm -rf "${VENV_DIR}" "${ARTIFACTS_DIR}" "${SCRATCH_DIR}" "${LOGS_DIR}"

# -----------------------------
# Verify Python version
# -----------------------------
if ! command -v ${PYTHON_BIN} >/dev/null 2>&1; then
  echo "❌ ${PYTHON_BIN} not found. Please install Python 3.12 first."
  exit 1
fi

echo "✅ Found Python:"
${PYTHON_BIN} --version

# -----------------------------
# Create virtual environment
# -----------------------------
if [ ! -d "${VENV_DIR}" ]; then
  echo "📦 Creating virtual environment..."
  ${PYTHON_BIN} -m venv ${VENV_DIR}
else
  echo "📦 Virtual environment already exists."
fi

source ${VENV_DIR}/bin/activate

# -----------------------------
# Upgrade tooling
# -----------------------------
echo "⬆️  Upgrading pip/setuptools/wheel..."
pip install --upgrade pip setuptools wheel

# -----------------------------
# Install Docling + Serve (pinned)
# -----------------------------
echo "📥 Installing Docling and Docling Serve..."
pip install -r requirements.txt

# -----------------------------
# Download model artifacts
# -----------------------------
echo "⬇️  Downloading Docling model artifacts..."
docling-tools models download -o "${ARTIFACTS_DIR}"
docling-tools models download -o "${ARTIFACTS_DIR}" easyocr

# -----------------------------
# Create directories
# -----------------------------
mkdir -p "${ARTIFACTS_DIR}"
mkdir -p "${SCRATCH_DIR}"
mkdir -p "${LOGS_DIR}"

# -----------------------------
# Environment optimization (Apple Silicon)
# -----------------------------
ENV_FILE="${VENV_DIR}/bin/activate"

if ! grep -q "DOCLING_APPLE_OPTIMIZED" "${ENV_FILE}"; then
  echo "⚙️  Writing Apple Silicon optimizations..."

  cat <<EOF >> "${ENV_FILE}"

# --- Docling Apple Silicon Optimizations ---
export DOCLING_APPLE_OPTIMIZED=1
export DOCLING_DEVICE=auto
export DOCLING_NUM_THREADS=8
export DOCLING_PERF_PAGE_BATCH_SIZE=4

# Cache & paths
export DOCLING_ARTIFACTS_PATH="${ARTIFACTS_DIR}"
export DOCLING_SCRATCH_PATH="${SCRATCH_DIR}"
export DOCLING_SERVE_ARTIFACTS_PATH="${ARTIFACTS_DIR}"

# Torch / Metal stability
export PYTORCH_ENABLE_MPS_FALLBACK=1
export TOKENIZERS_PARALLELISM=false
EOF
fi

# -----------------------------
# Warm model cache (optional but recommended)
# -----------------------------
echo "🔥 Warming model cache (first run may take a few minutes)..."
python - <<'EOF'
from docling.document_converter import DocumentConverter
converter = DocumentConverter()
print("✅ Docling initialized successfully")
EOF

# -----------------------------
# Create run script
# -----------------------------
RUN_SCRIPT="run-docling-local-apple-silicon.sh"

cat <<'EOF' > ${RUN_SCRIPT}
#!/usr/bin/env bash
set -euo pipefail

# Local Docling Serve runner for Apple Silicon only.
# This script is separate from the macOS menu bar app bundle.

BASE_DIR="$(cd "$(dirname "$0")" && pwd)"
source "${BASE_DIR}/venv/bin/activate"

echo "🚀 Starting Docling Serve (local Apple Silicon)..."
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

# Optional menu bar patch: capture task IDs from UI async requests.
# The macOS menu bar app can point at this script via serviceScriptPath.
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
EOF

chmod +x ${RUN_SCRIPT}

# -----------------------------
# Build macOS menu bar app
# -----------------------------
if [[ -x "${ROOT_DIR}/macos/DoclingMenuBar/build-app.sh" ]]; then
  echo "🍎 Building macOS menu bar app..."
  ICON_SOURCE="${ROOT_DIR}/logo.png" \
    ICONSET_DIR="${ROOT_DIR}/build/AppIcon.iconset" \
    "${ROOT_DIR}/macos/DoclingMenuBar/build-app.sh"
else
  echo "⚠️  macOS menu bar build script not found or not executable."
fi

echo ""
echo "🎉 Docling setup complete!"
echo ""
echo "Next steps:"
echo "  ▶ Run Docling: ./run-docling-local-apple-silicon.sh <command>"
echo "  ▶ Example:     ./run-docling-local-apple-silicon.sh --help"
