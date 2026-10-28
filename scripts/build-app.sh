#!/bin/bash
# Builds Tendedero.app into ./build without needing Xcode.
# Usage: scripts/build-app.sh [debug|release]
set -euo pipefail
cd "$(dirname "$0")/.."

CONFIG="${1:-release}"
APP="build/SunMemo.app"
VERSION="${VERSION:-$(cat VERSION 2>/dev/null | tr -d '[:space:]' || echo '1.0.0')}"
BUILD_NUMBER="${BUILD_NUMBER:-$(git rev-list --count HEAD 2>/dev/null || echo '1')}"
SPARKLE_PUBLIC_KEY="$(tr -d '[:space:]' < config/sparkle-public-key.txt)"

# Builds one architecture and prints the binary's path.
# The Command Line Tools for macOS 27 ship an SDK whose SwiftUI needs a macro
# plugin they do not include. If the default SDK fails, fall back to the
# newest macOS 26 SDK installed alongside it.
build_arch() {
  local triple="$1-apple-macosx13.0"
  if [ -z "${SDKROOT:-}" ] && ! swift build -c "$CONFIG" --triple "$triple" >&2; then
    FALLBACK="$(ls -d /Library/Developer/CommandLineTools/SDKs/MacOSX26*.sdk 2>/dev/null | sort -V | tail -1)"
    if [ -z "$FALLBACK" ]; then exit 1; fi
    echo "Retrying with $FALLBACK" >&2
    export SDKROOT="$FALLBACK"
  fi
  if [ -n "${SDKROOT:-}" ]; then swift build -c "$CONFIG" --triple "$triple" >&2; fi
  cp "$(swift build -c "$CONFIG" --triple "$triple" --show-bin-path)/SunMemo" "$OUT/SunMemo-$1"
}

# A universal binary, so it runs on Apple silicon and on Intel Macs, from
# macOS 13 Ventura onwards.
OUT="$(mktemp -d)"
build_arch arm64
build_arch x86_64
lipo -create "$OUT/SunMemo-arm64" "$OUT/SunMemo-x86_64" -output "$OUT/SunMemo"
BIN="$OUT/SunMemo"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/SunMemo"
mkdir -p "$APP/Contents/Frameworks"
ditto .build/artifacts/sparkle/Sparkle/Sparkle.xcframework/macos-arm64_x86_64/Sparkle.framework \
  "$APP/Contents/Frameworks/Sparkle.framework"

# Icon
WORK="$(mktemp -d)"
swift scripts/make-icon.swift "$WORK/icon.png"
ICONSET="$WORK/SunMemo.iconset"
mkdir -p "$ICONSET"
for s in 16 32 128 256 512; do
  sips -z $s $s "$WORK/icon.png" --out "$ICONSET/icon_${s}x${s}.png" >/dev/null
  sips -z $((s*2)) $((s*2)) "$WORK/icon.png" --out "$ICONSET/icon_${s}x${s}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/SunMemo.icns"
rm -rf "$WORK"

# Translations: one folder per language, listed in Info.plist so macOS knows
# which languages the app speaks.
LANGUAGES=""
for dir in Sources/SunMemo/Resources/*.lproj; do
  cp -R "$dir" "$APP/Contents/Resources/"
  LANGUAGES="$LANGUAGES<string>$(basename "$dir" .lproj)</string>"
done

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>SunMemo</string>
  <key>CFBundleDisplayName</key><string>SunMemo</string>
  <key>CFBundleIdentifier</key><string>com.zhangkaiming.SunMemo</string>
  <key>CFBundleExecutable</key><string>SunMemo</string>
  <key>CFBundleIconFile</key><string>SunMemo</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>${VERSION}</string>
  <key>CFBundleVersion</key><string>${BUILD_NUMBER}</string>
  <key>CFBundleDevelopmentRegion</key><string>en</string>
  <key>CFBundleLocalizations</key><array>${LANGUAGES}</array>
  <key>LSMinimumSystemVersion</key><string>13.0</string>
  <key>LSUIElement</key><true/>
  <key>NSHighResolutionCapable</key><true/>
  <key>SUFeedURL</key><string>https://github.com/km-open-lab/SunMemo/releases/latest/download/appcast.xml</string>
  <key>SUPublicEDKey</key><string>${SPARKLE_PUBLIC_KEY}</string>
  <key>SUEnableAutomaticChecks</key><true/>
  <key>SUScheduledCheckInterval</key><integer>86400</integer>
  <key>SUAutomaticallyUpdate</key><false/>
  <key>SUAllowsAutomaticUpdates</key><false/>
  <key>SUVerifyUpdateBeforeExtraction</key><true/>
  <key>SURequireSignedFeed</key><true/>
  <key>NSDesktopFolderUsageDescription</key>
  <string>SunMemo watches the folder where macOS saves your screenshots so it can hang them on the line.</string>
</dict>
</plist>
PLIST

# Sign with a Developer ID when one is in the keychain (or SIGN_IDENTITY is
# set), with the hardened runtime and a secure timestamp that notarization
# requires. Without one, sign ad hoc so the app still runs locally.
IDENTITY="${SIGN_IDENTITY:-$(security find-identity -v -p codesigning 2>/dev/null | awk -F'"' '/Developer ID Application/{print $2; exit}')}"
sign_code() {
  if [ -n "$IDENTITY" ]; then
    codesign --force --options runtime --timestamp --sign "$IDENTITY" "$@"
  else
    codesign --force --sign - "$@"
  fi
}
SPARKLE="$APP/Contents/Frameworks/Sparkle.framework/Versions/B"
# Sign from the inside out; Downloader keeps its shipped sandbox entitlements.
sign_code "$SPARKLE/XPCServices/Installer.xpc"
sign_code --preserve-metadata=entitlements "$SPARKLE/XPCServices/Downloader.xpc"
sign_code "$SPARKLE/Autoupdate"
sign_code "$SPARKLE/Updater.app"
sign_code "$APP/Contents/Frameworks/Sparkle.framework"
sign_code "$APP"
if [ -n "$IDENTITY" ]; then
  echo "Signed with $IDENTITY"
else
  echo "Signed ad hoc (no Developer ID found)"
fi
codesign --verify --deep --strict "$APP"
echo "Built $APP"
