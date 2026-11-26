#!/bin/bash
# Compile Rangeur et assemble Rangeur.app dans le dossier build/.
set -euo pipefail
cd "$(dirname "$0")"

SDK="$(xcrun --sdk macosx --show-sdk-version 2>/dev/null || echo "?")"
OS="$(sw_vers -productVersion)"
echo "▸ macOS $OS · SDK $SDK · $(swift --version 2>/dev/null | head -1 | sed 's/^.*Swift version /Swift /;s/ (.*//')"
if [[ "${SDK%%.*}" =~ ^[0-9]+$ ]] && (( ${SDK%%.*} < 26 )); then
  echo "  ⚠️  SDK antérieur à macOS 26 : pas de Liquid Glass."
  echo "     Installe Xcode 26 depuis l'App Store, puis : sudo xcode-select -s /Applications/Xcode.app"
fi
echo "▸ Compilation (release)…"
swift build -c release
BIN_DIR="$(swift build -c release --show-bin-path)"

APP="build/Rangeur.app"
echo "▸ Assemblage de ${APP}…"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/Rangeur" "$APP/Contents/MacOS/Rangeur"
cp Resources/Info.plist "$APP/Contents/Info.plist"
# Numéro de build unique : macOS considère chaque installation comme une nouvelle version (et recharge l'icône).
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $(date +%Y%m%d%H%M%S)" "$APP/Contents/Info.plist"

echo "▸ Icône…"
ICONSET="build/AppIcon.iconset"
rm -rf "$ICONSET" && mkdir -p "$ICONSET"
for size in 16 32 128 256 512; do
  sips -z $size $size Resources/AppIcon.png --out "$ICONSET/icon_${size}x${size}.png" >/dev/null
  double=$((size * 2))
  sips -z $double $double Resources/AppIcon.png --out "$ICONSET/icon_${size}x${size}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/Rangeur.icns"
rm -rf "$ICONSET"

echo "▸ Signature locale…"
codesign --force --deep --sign - "$APP"

echo ""
echo "✅ Terminé : $(pwd)/$APP"
echo "   Glisse-la dans /Applications, puis ouvre-la."
if [[ "${1:-}" == "--install" ]]; then
  rm -rf /Applications/Rangeur.app
  cp -R "$APP" /Applications/
  touch /Applications/Rangeur.app
  echo "   Installée dans /Applications."
  echo "▸ Rafraîchissement de l'icône…"
  pkill -x Rangeur 2>/dev/null || true
  /System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f /Applications/Rangeur.app || true
  killall Dock 2>/dev/null || true
  sleep 1
  open /Applications/Rangeur.app
fi
