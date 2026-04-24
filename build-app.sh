#!/usr/bin/env bash
# Compila Clipo e empacota em Clipo.app (bundle mínimo).
set -euo pipefail

cd "$(dirname "$0")"

CONFIG="${1:-release}"
APP_NAME="Clipo"
BUNDLE_ID="com.clipo.app"

echo "▶︎ Compilando ($CONFIG)…"
swift build -c "$CONFIG"

BIN_PATH="$(swift build -c "$CONFIG" --show-bin-path)/$APP_NAME"
if [[ ! -f "$BIN_PATH" ]]; then
  echo "Binário não encontrado em $BIN_PATH"; exit 1
fi

APP_DIR="./build/$APP_NAME.app"
rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS"
mkdir -p "$APP_DIR/Contents/Resources"

cp "$BIN_PATH" "$APP_DIR/Contents/MacOS/$APP_NAME"
chmod +x "$APP_DIR/Contents/MacOS/$APP_NAME"

# Copy icon assets
[[ -f assets/Clipo.icns ]] && cp assets/Clipo.icns "$APP_DIR/Contents/Resources/Clipo.icns"
[[ -f assets/menubar.png ]] && cp assets/menubar.png "$APP_DIR/Contents/Resources/menubar.png"
[[ -f assets/menubar@2x.png ]] && cp assets/menubar@2x.png "$APP_DIR/Contents/Resources/menubar@2x.png"

cat > "$APP_DIR/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
 "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDisplayName</key><string>$APP_NAME</string>
  <key>CFBundleName</key><string>$APP_NAME</string>
  <key>CFBundleExecutable</key><string>$APP_NAME</string>
  <key>CFBundleIdentifier</key><string>$BUNDLE_ID</string>
  <key>CFBundleInfoDictionaryVersion</key><string>6.0</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>0.1.0</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>LSMinimumSystemVersion</key><string>13.0</string>
  <key>LSUIElement</key><true/>
  <key>CFBundleIconFile</key><string>Clipo</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSAppleEventsUsageDescription</key>
  <string>Clipo envia ⌘V para colar o item selecionado no app ativo.</string>
</dict>
</plist>
PLIST

echo "✓ App criado em: $APP_DIR"

# Install into /Applications
INSTALL_DIR="/Applications/$APP_NAME.app"
pkill -x "$APP_NAME" 2>/dev/null || true
rm -rf "$INSTALL_DIR"
cp -R "$APP_DIR" "$INSTALL_DIR"
echo "✓ Instalado em: $INSTALL_DIR"
echo "Execute com: open \"$INSTALL_DIR\""
