#!/usr/bin/env bash
# Builds build/AgentSweep.app, ad-hoc signed.
#   scripts/build-app.sh               release build for this Mac
#   scripts/build-app.sh --universal   Apple silicon + Intel
#   scripts/build-app.sh --dist        also write build/AgentSweep-<version>.zip and .dmg
#   scripts/build-app.sh --debug       debug build (enables development flags such as --demo-clean)
#   scripts/build-app.sh --open        open the app afterwards
# VERSION=1.2.3 overrides the version written into Info.plist.
# FEED_URL overrides the Sparkle appcast (default: appcast.xml on the latest GitHub release).
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
VERSION="${VERSION:-0.2.0}"
FEED_URL="${FEED_URL:-https://github.com/ai-suifeng/agent-clean-mac/releases/latest/download/appcast.xml}"
# Public half of the EdDSA key that signs update archives (private half lives only in the release secret).
SPARKLE_PUBLIC_KEY="Y6eBMUTQuyxGw42oEB01+vaQY+uGKXzBJZbfArNaft4="

swift build -c "$CONFIG" ${ARCHS[@]+"${ARCHS[@]}"}
BIN="$(swift build -c "$CONFIG" ${ARCHS[@]+"${ARCHS[@]}"} --show-bin-path)"
APP=build/AgentSweep.app

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$APP/Contents/Frameworks"
cp "$BIN/AgentSweep" "$APP/Contents/MacOS/AgentSweep"
cp -R "$BIN/AgentSweep_AgentSweepCore.bundle" "$APP/Contents/Resources/"
ditto "$BIN/Sparkle.framework" "$APP/Contents/Frameworks/Sparkle.framework"

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
  <key>SUFeedURL</key><string>$FEED_URL</string>
  <key>SUPublicEDKey</key><string>$SPARKLE_PUBLIC_KEY</string>
  <key>SUEnableAutomaticChecks</key><true/>
  <key>SUScheduledCheckInterval</key><integer>86400</integer>
</dict>
</plist>
PLIST

# Ad-hoc signing. The app's designated requirement is pinned to its bundle id so every release
# satisfies the previous one's requirement, which Sparkle checks before installing an update.
codesign --force --deep --sign - "$APP/Contents/Frameworks/Sparkle.framework" >/dev/null
codesign --force --sign - -r='designated => identifier "app.agentsweep.mac"' "$APP" >/dev/null
codesign --verify --deep --strict "$APP"
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
  cp "$ZIP" build/AgentSweep.zip   # stable names for releases/latest/download/…
  cp "$DMG" build/AgentSweep.dmg
  echo "Packed $ZIP and $DMG"
fi

[ "$OPEN" = 1 ] && open "$APP"
exit 0
