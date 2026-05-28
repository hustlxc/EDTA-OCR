#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR"

echo "========================================="
echo " Building EDTA OCR (SwiftUI native)..."
echo "========================================="

swift build -c release --arch arm64

APP_DIR="$SCRIPT_DIR/.build/EDTAOCR.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"
PLIST="$CONTENTS_DIR/Info.plist"
BINARY="$SCRIPT_DIR/.build/arm64-apple-macosx/release/EDTAOCR"

rm -rf "$APP_DIR"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR"
cp "$BINARY" "$MACOS_DIR/EDTAOCR"
chmod +x "$MACOS_DIR/EDTAOCR"

cat > "$PLIST" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>zh_CN</string>
    <key>CFBundleExecutable</key>
    <string>EDTAOCR</string>
    <key>CFBundleIdentifier</key>
    <string>com.local.edtaocr</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>EDTA OCR</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>NSCameraUsageDescription</key>
    <string>用于拍摄 EDTA 采血管标签并进行 OCR 识别。</string>
    <key>NSPrincipalClass</key>
    <string>NSApplication</string>
</dict>
</plist>
PLIST

echo ""
echo "Build complete!"
echo "App: .build/EDTAOCR.app"
echo ""

# Optional: set DeepSeek API key for AI-powered extraction
launchctl setenv EDTA_OCR_HOME "$SCRIPT_DIR" >/dev/null 2>&1 || true

if [ -n "${DEEPSEEK_API_KEY:-}" ]; then
    echo "DeepSeek API key detected (env var) -- AI extraction enabled"
    launchctl setenv DEEPSEEK_API_KEY "$DEEPSEEK_API_KEY" >/dev/null 2>&1 || true
fi

# Check if running in GUI session
if [ -z "${SSH_CONNECTION:-}" ] || [ -n "${DISPLAY:-}" ]; then
    echo "========================================="
    echo " Starting EDTA OCR Application..."
    echo "========================================="
    echo ""
    open -n "$APP_DIR"
else
    echo "NOTE: Skipping GUI launch (SSH session detected)"
fi
