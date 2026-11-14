#!/bin/zsh
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
RELEASE_CONFIG_PATH="$ROOT_DIR/Config/app_release.env"
if [[ ! -f "$RELEASE_CONFIG_PATH" ]]; then
  echo "Missing release config: $RELEASE_CONFIG_PATH" >&2
  exit 1
fi
source "$RELEASE_CONFIG_PATH"
# A release can override the version and build number (scripts/make_release.sh does).
APP_VERSION="${LORRE_VERSION:-$APP_VERSION}"
BUILD_NUMBER="${LORRE_BUILD:-$BUILD_NUMBER}"

CONFIGURATION="debug" # debug | release
SKIP_BUILD="0"
FINAL_DIST_DIR="$ROOT_DIR/dist"
# The bundle is put together and signed in a temporary folder: a cloud-synced project folder
# (Dropbox, iCloud) adds file attributes that make codesign reject the bundle.
DIST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/lorre-package.XXXXXX")"
trap 'rm -rf "$DIST_DIR"' EXIT
APP_BUNDLE="$DIST_DIR/${APP_NAME}.app"
CONTENTS_DIR="$APP_BUNDLE/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"
FRAMEWORKS_DIR="$CONTENTS_DIR/Frameworks"
ICON_PATH="$ROOT_DIR/$ICON_RELATIVE_PATH"
TEXT_NORMALIZATION_LIBRARY="$ROOT_DIR/$TEXT_NORMALIZATION_LIBRARY_RELATIVE_PATH"

while [[ $# -gt 0 ]]; do
  case "$1" in
    debug|release)
      CONFIGURATION="$1"
      ;;
    --skip-build)
      SKIP_BUILD="1"
      ;;
    *)
      echo "Usage: $0 [debug|release] [--skip-build]" >&2
      exit 1
      ;;
  esac
  shift
done

if [[ ! -f "$ICON_PATH" ]]; then
  echo "Missing icon file: $ICON_PATH" >&2
  exit 1
fi

cd "$ROOT_DIR"
if [[ "$SKIP_BUILD" == "0" ]]; then
  echo "Building $APP_NAME ($CONFIGURATION)..."
  swift build -c "$CONFIGURATION"
else
  echo "Skipping build; using existing binary for $CONFIGURATION if present..."
fi

BIN_PATH="$ROOT_DIR/.build/${CONFIGURATION}/$APP_NAME"
if [[ ! -x "$BIN_PATH" ]]; then
  ALT_BIN_PATH="$ROOT_DIR/.build/arm64-apple-macosx/${CONFIGURATION}/$APP_NAME"
  if [[ -x "$ALT_BIN_PATH" ]]; then
    BIN_PATH="$ALT_BIN_PATH"
  fi
fi
if [[ ! -x "$BIN_PATH" ]]; then
  echo "Could not find built binary at $BIN_PATH" >&2
  exit 1
fi

echo "Packaging app bundle..."
rm -rf "$APP_BUNDLE"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR"
mkdir -p "$FRAMEWORKS_DIR"

cp "$BIN_PATH" "$MACOS_DIR/$APP_NAME"

# Sparkle (automatic updates) comes as a prebuilt framework in the SwiftPM artifacts.
SPARKLE_FRAMEWORK="$(find "$ROOT_DIR/.build/artifacts" -type d -name Sparkle.framework -path '*macos-arm64_x86_64*' 2>/dev/null | head -n 1)"
if [[ -z "$SPARKLE_FRAMEWORK" ]]; then
  echo "Could not find Sparkle.framework under .build/artifacts; run swift build first" >&2
  exit 1
fi
ditto "$SPARKLE_FRAMEWORK" "$FRAMEWORKS_DIR/Sparkle.framework"
if ! otool -l "$MACOS_DIR/$APP_NAME" | grep -q "@executable_path/../Frameworks"; then
  install_name_tool -add_rpath "@executable_path/../Frameworks" "$MACOS_DIR/$APP_NAME"
fi
cp "$ICON_PATH" "$RESOURCES_DIR/$APP_NAME.icns"
if [[ -f "$TEXT_NORMALIZATION_LIBRARY" ]]; then
  cp "$TEXT_NORMALIZATION_LIBRARY" "$FRAMEWORKS_DIR/libnemo_text_processing.dylib"
fi

# Update feed and public key, only when both are given. Without them the app has no update feature.
UPDATE_PLIST_KEYS=""
if [[ -n "${LORRE_UPDATE_FEED_URL:-}" && -n "${LORRE_UPDATE_PUBLIC_KEY:-}" ]]; then
  UPDATE_PLIST_KEYS="  <key>SUFeedURL</key>
  <string>$LORRE_UPDATE_FEED_URL</string>
  <key>SUPublicEDKey</key>
  <string>$LORRE_UPDATE_PUBLIC_KEY</string>
  <key>SUEnableAutomaticChecks</key>
  <true/>"
  echo "Updates: configured (feed $LORRE_UPDATE_FEED_URL)"
else
  echo "Updates: not configured (set LORRE_UPDATE_FEED_URL and LORRE_UPDATE_PUBLIC_KEY to enable)"
fi

cat > "$CONTENTS_DIR/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDevelopmentRegion</key>
  <string>en</string>
  <key>CFBundleExecutable</key>
  <string>$APP_NAME</string>
  <key>CFBundleIdentifier</key>
  <string>$APP_BUNDLE_IDENTIFIER</string>
  <key>CFBundleInfoDictionaryVersion</key>
  <string>6.0</string>
  <key>CFBundleName</key>
  <string>$APP_NAME</string>
  <key>CFBundleDisplayName</key>
  <string>$APP_NAME</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>$APP_VERSION</string>
  <key>CFBundleVersion</key>
  <string>$BUILD_NUMBER</string>
  <key>CFBundleIconFile</key>
  <string>$APP_NAME</string>
  <key>LSMinimumSystemVersion</key>
  <string>$MINIMUM_MACOS_VERSION</string>
  <key>NSMicrophoneUsageDescription</key>
  <string>Lorre transcribes audio locally — your microphone, system audio from other apps, or both.</string>
  <key>NSAudioCaptureUsageDescription</key>
  <string>Lorre captures audio from other apps so meetings and system audio can be transcribed locally.</string>
  <key>NSCalendarsFullAccessUsageDescription</key>
  <string>Lorre reads the calendar on this Mac to show upcoming conversations and to name recordings. Nothing leaves your Mac.</string>
  <key>NSHighResolutionCapable</key>
  <true/>
$UPDATE_PLIST_KEYS
</dict>
</plist>
PLIST

ENTITLEMENTS_PATH="$DIST_DIR/${APP_NAME}.entitlements"
cat > "$ENTITLEMENTS_PATH" <<ENTITLEMENTS
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>com.apple.security.device.audio-input</key>
  <true/>
</dict>
</plist>
ENTITLEMENTS

chmod +x "$MACOS_DIR/$APP_NAME"
# Ad-hoc signing ("-") ties the app's identity to the binary hash, so macOS forgets the
# microphone and audio-capture permissions after every build. A fixed certificate keeps them.
# See docs/signing.md.
SIGN_IDENTITY="${LORRE_SIGN_IDENTITY:--}"
if [[ "$SIGN_IDENTITY" == "-" ]]; then
  echo "Signing: ad-hoc (permissions reset on every build; set LORRE_SIGN_IDENTITY to keep them)"
else
  echo "Signing with identity: $SIGN_IDENTITY"
fi
# Nested code is signed first, inside out, with the same identity; the app is signed last and
# without --deep so the nested code keeps its own signature (and does not get the app's entitlements).
xattr -cr "$APP_BUNDLE" 2>/dev/null || true # cloud-synced folders add attributes codesign rejects
SPARKLE_B="$FRAMEWORKS_DIR/Sparkle.framework/Versions/B"
for nested in "$SPARKLE_B/XPCServices/Installer.xpc" "$SPARKLE_B/XPCServices/Downloader.xpc" \
              "$SPARKLE_B/Autoupdate" "$SPARKLE_B/Updater.app" "$FRAMEWORKS_DIR/Sparkle.framework"; do
  codesign --force --sign "$SIGN_IDENTITY" "$nested"
done
if [[ -f "$FRAMEWORKS_DIR/libnemo_text_processing.dylib" ]]; then
  codesign --force --sign "$SIGN_IDENTITY" "$FRAMEWORKS_DIR/libnemo_text_processing.dylib"
fi
codesign --force --sign "$SIGN_IDENTITY" --entitlements "$ENTITLEMENTS_PATH" "$APP_BUNDLE"
codesign --verify --deep --strict "$APP_BUNDLE"
codesign -d -r- "$APP_BUNDLE" 2>&1 | grep 'designated' || true

mkdir -p "$FINAL_DIST_DIR"
rm -rf "$FINAL_DIST_DIR/${APP_NAME}.app"
ditto --noextattr --norsrc "$APP_BUNDLE" "$FINAL_DIST_DIR/${APP_NAME}.app"
cp "$ENTITLEMENTS_PATH" "$FINAL_DIST_DIR/"

echo "Created: $FINAL_DIST_DIR/${APP_NAME}.app"
echo "Binary:  $FINAL_DIST_DIR/${APP_NAME}.app/Contents/MacOS/$APP_NAME"
echo "Install: ditto --noextattr --norsrc \"$FINAL_DIST_DIR/${APP_NAME}.app\" /Applications/${APP_NAME}.app"
