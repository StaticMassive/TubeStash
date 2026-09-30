#!/bin/zsh
# Build Tube Stash.app as a native Mac app: its own window (WebKit), Dock icon
# and menus. It starts the bundled engine privately on 127.0.0.1 and stops it
# on quit. No browser window. Universal (Apple Silicon + Intel).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="$ROOT/Tube Stash.app"
RES="$APP/Contents/Resources"
MACOS="$APP/Contents/MacOS"
SRC="$ROOT/scripts/native/TubeStashApp.swift"
ICON_SRC="$ROOT/assets/app-icon-1024.png"
OUT="$(mktemp -d /tmp/tubestash-build.XXXXXX)"
trap 'rm -rf "$OUT"' EXIT

# Oldest macOS the app supports. Always pass an explicit target: building
# without one defaults to the build Mac's own macOS, and the app then refuses
# to open on anything older.
MINOS=11.3
VERSION="$(sed -n 's/.*"version": *"\([^"]*\)".*/\1/p' "$ROOT/package.json" | head -n 1)"

echo "Building $APP $VERSION (macOS $MINOS+)"
mkdir -p "$MACOS" "$RES"

if xcrun swiftc -O -target "arm64-apple-macos$MINOS" -o "$OUT/arm64" "$SRC" \
   && xcrun swiftc -O -target "x86_64-apple-macos$MINOS" -o "$OUT/x86_64" "$SRC"; then
  lipo -create -output "$OUT/Stash" "$OUT/arm64" "$OUT/x86_64"
  echo "Universal app."
else
  echo "Universal build unavailable. Building for this Mac."
  ARCH=x86_64; [[ "$(sysctl -n hw.optional.arm64 2>/dev/null || true)" == "1" ]] && ARCH=arm64
  xcrun swiftc -O -target "$ARCH-apple-macos$MINOS" -o "$OUT/Stash" "$SRC"
fi
rm -f "$MACOS/Stash"
cp "$OUT/Stash" "$MACOS/Stash"
chmod +x "$MACOS/Stash"

cat > "$APP/Contents/Info.plist" << PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDevelopmentRegion</key>
  <string>en</string>
  <key>CFBundleDisplayName</key>
  <string>Tube Stash</string>
  <key>CFBundleExecutable</key>
  <string>Stash</string>
  <key>CFBundleIconFile</key>
  <string>AppIcon</string>
  <key>CFBundleIdentifier</key>
  <string>com.staticmassive.tubestash</string>
  <key>CFBundleInfoDictionaryVersion</key>
  <string>6.0</string>
  <key>CFBundleName</key>
  <string>Tube Stash</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>$VERSION</string>
  <key>CFBundleVersion</key>
  <string>$VERSION</string>
  <key>LSMinimumSystemVersion</key>
  <string>$MINOS</string>
  <key>NSHighResolutionCapable</key>
  <true/>
  <key>NSPrincipalClass</key>
  <string>NSApplication</string>
  <key>NSAppTransportSecurity</key>
  <dict>
    <key>NSAllowsLocalNetworking</key>
    <true/>
  </dict>
  <key>NSHumanReadableCopyright</key>
  <string>Static Massive. Local YouTube downloader.</string>
</dict>
</plist>
PLIST

echo -n "APPL????" > "$APP/Contents/PkgInfo"

if [[ -f "$ICON_SRC" ]]; then
  ICONSET="$OUT/AppIcon.iconset"
  mkdir -p "$ICONSET"
  sips -s format png -z 1024 1024 "$ICON_SRC" --out "$OUT/icon-1024.png" >/dev/null
  for size in 16 32 128 256 512; do
    sips -z $size $size "$OUT/icon-1024.png" --out "$ICONSET/icon_${size}x${size}.png" >/dev/null
    sips -z $((size*2)) $((size*2)) "$OUT/icon-1024.png" --out "$ICONSET/icon_${size}x${size}@2x.png" >/dev/null
  done
  iconutil -c icns "$ICONSET" -o "$RES/AppIcon.icns"
  echo "Icon installed."
fi

chmod +x "$ROOT/Open Tube Stash.command" "$ROOT/Open Stash.command" "$ROOT/scripts/start.sh"
codesign --force --deep -s - "$APP" 2>/dev/null || true
xattr -cr "$APP" 2>/dev/null || true
touch "$APP"
echo "Done: $APP"
