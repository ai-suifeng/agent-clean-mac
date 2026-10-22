#!/usr/bin/env bash
# Builds build/AgentSweep.app, ad-hoc signed.
#   scripts/build-app.sh               release build for this Mac
#   scripts/build-app.sh --universal   Apple silicon + Intel
#   scripts/build-app.sh --dist        also write build/AgentSweep-<version>.zip and .dmg
#   scripts/build-app.sh --debug       debug build (enables development flags such as --demo-clean)
#   scripts/build-app.sh --open        open the app afterwards
# VERSION=1.2.3 overrides the version written into Info.plist.
set -euo pipefail
cd "$(dirname "$0")/.."

CONFIG=release; ARCHS=(); DIST=0; OPEN=0
for a in "$@"; do
  case "$a" in
    --universal) ARCHS=(--arch arm64 --arch x86_64) ;;
    --dist) DIST=1 ;;
    --debug) CONFIG=debug ;;
    --open) OPEN=1 ;;
    *) echo "unknown option $a" >&2; exit 2 ;;
  esac
done
VERSION="${VERSION:-0.1.0}"

swift build -c "$CONFIG" ${ARCHS[@]+"${ARCHS[@]}"}
BIN="$(swift build -c "$CONFIG" ${ARCHS[@]+"${ARCHS[@]}"} --show-bin-path)"
APP=build/AgentSweep.app

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN/AgentSweep" "$APP/Contents/MacOS/AgentSweep"
cp -R "$BIN/AgentSweep_AgentSweepCore.bundle" "$APP/Contents/Resources/"

if [ ! -f build/AppIcon.icns ] || [ scripts/make-icon.swift -nt build/AppIcon.icns ]; then
  rm -rf build/AppIcon.iconset
  swift scripts/make-icon.swift build/AppIcon.iconset
  iconutil -c icns build/AppIcon.iconset -o build/AppIcon.icns
fi
cp build/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>AgentSweep</string>
  <key>CFBundleDisplayName</key><string>AgentSweep</string>
  <key>CFBundleIdentifier</key><string>app.agentsweep.mac</string>
  <key>CFBundleExecutable</key><string>AgentSweep</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>$VERSION</string>
  <key>CFBundleVersion</key><string>$VERSION</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>LSApplicationCategoryType</key><string>public.app-category.utilities</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSHumanReadableCopyright</key><string>MIT License</string>
</dict>
</plist>
PLIST

codesign --force --deep --sign - "$APP" >/dev/null
echo "Built $APP ($(lipo -archs "$APP/Contents/MacOS/AgentSweep"), $CONFIG, v$VERSION)"

if [ "$DIST" = 1 ]; then
  ZIP="build/AgentSweep-$VERSION.zip"; DMG="build/AgentSweep-$VERSION.dmg"
  rm -f "$ZIP" "$DMG"
  ditto -c -k --keepParent "$APP" "$ZIP"
  STAGE="$(mktemp -d)"
  cp -R "$APP" "$STAGE/"
  ln -s /Applications "$STAGE/Applications"
  hdiutil create -quiet -volname "AgentSweep" -srcfolder "$STAGE" -ov -format UDZO "$DMG"
  rm -rf "$STAGE"
  echo "Packed $ZIP and $DMG"
fi

[ "$OPEN" = 1 ] && open "$APP"
exit 0
