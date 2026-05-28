#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"

echo "========================================="
echo " Building EDTA OCR (SwiftUI native)..."
echo "========================================="

swift build -c release --arch arm64

echo ""
echo "Build complete!"
echo "Binary: .build/arm64-apple-macosx/release/EDTAOCR"
echo ""

# Optional: set DeepSeek API key for AI-powered extraction
if [ -n "${DEEPSEEK_API_KEY:-}" ]; then
    echo "DeepSeek API key detected (env var) -- AI extraction enabled"
fi

# Check if running in GUI session
if [ -z "${SSH_CONNECTION:-}" ] || [ -n "${DISPLAY:-}" ]; then
    echo "========================================="
    echo " Starting EDTA OCR Application..."
    echo "========================================="
    echo ""
    exec .build/arm64-apple-macosx/release/EDTAOCR
else
    echo "NOTE: Skipping GUI launch (SSH session detected)"
fi
