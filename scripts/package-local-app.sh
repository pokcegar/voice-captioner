#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONFIGURATION="${CONFIGURATION:-debug}"
APP_NAME="${APP_NAME:-VoiceCaptioner.app}"
DIST_DIR="$ROOT/dist"
APP_DIR="$DIST_DIR/$APP_NAME"
CONTENTS="$APP_DIR/Contents"
MACOS="$CONTENTS/MacOS"
RESOURCES="$CONTENTS/Resources"
EXECUTABLE="$ROOT/.build/$CONFIGURATION/voice-captioner-app"
WHISPER_CLI="${WHISPER_CLI:-$ROOT/Resources/whisper-cli}"

cd "$ROOT"
swift build ${CONFIGURATION:+--configuration "$CONFIGURATION"}

if [[ ! -x "$EXECUTABLE" ]]; then
  echo "Missing app executable: $EXECUTABLE" >&2
  exit 1
fi
if [[ ! -x "$WHISPER_CLI" ]]; then
  cat >&2 <<MSG
Missing bundled whisper executable: $WHISPER_CLI
Build or copy whisper.cpp's whisper-cli there, or rerun with WHISPER_CLI=/path/to/whisper-cli.
MSG
  exit 1
fi

rm -rf "$APP_DIR"
mkdir -p "$MACOS" "$RESOURCES"
cp "$EXECUTABLE" "$MACOS/VoiceCaptioner"
cp "$WHISPER_CLI" "$RESOURCES/whisper-cli"
chmod +x "$MACOS/VoiceCaptioner" "$RESOURCES/whisper-cli"

cat > "$CONTENTS/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key>
  <string>VoiceCaptioner</string>
  <key>CFBundleIdentifier</key>
  <string>dev.local.voice-captioner</string>
  <key>CFBundleName</key>
  <string>VoiceCaptioner</string>
  <key>CFBundleDisplayName</key>
  <string>VoiceCaptioner</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>0.1.0</string>
  <key>CFBundleVersion</key>
  <string>1</string>
  <key>LSMinimumSystemVersion</key>
  <string>15.0</string>
  <key>NSMicrophoneUsageDescription</key>
  <string>VoiceCaptioner records your microphone locally as a separate meeting track.</string>
  <key>NSScreenCaptureUsageDescription</key>
  <string>VoiceCaptioner captures system audio locally as a separate meeting track.</string>
</dict>
</plist>
PLIST

echo "$APP_DIR"
