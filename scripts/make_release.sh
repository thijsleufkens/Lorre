#!/bin/zsh
# Builds a signed release zip and extends the Sparkle appcast. Uploads nothing. See docs/updates.md.
set -euo pipefail

if [[ $# -ne 2 ]]; then
  echo "Usage: LORRE_SIGN_IDENTITY=... LORRE_UPDATE_FEED_URL=... LORRE_UPDATE_PUBLIC_KEY=... $0 <version> <build>" >&2
  exit 1
fi
VERSION="$1"
BUILD="$2"

for variable in LORRE_SIGN_IDENTITY LORRE_UPDATE_FEED_URL LORRE_UPDATE_PUBLIC_KEY; do
  if [[ -z "${(P)variable:-}" ]]; then
    echo "Missing environment variable: $variable (see docs/updates.md)" >&2
    exit 1
  fi
done

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
RELEASE_DIR="$ROOT_DIR/dist/release"

export LORRE_VERSION="$VERSION"
export LORRE_BUILD="$BUILD"
"$ROOT_DIR/scripts/package_macos_app.sh" release

GENERATE_APPCAST="$(find "$ROOT_DIR/.build/artifacts" -type f -name generate_appcast -path '*/bin/*' 2>/dev/null | head -n 1)"
if [[ -z "$GENERATE_APPCAST" ]]; then
  echo "Could not find Sparkle's generate_appcast under .build/artifacts; run swift build first" >&2
  exit 1
fi

mkdir -p "$RELEASE_DIR"
ZIP="$RELEASE_DIR/Lorre-$VERSION.zip"
rm -f "$ZIP"
ditto -c -k --keepParent --noextattr --norsrc "$ROOT_DIR/dist/Lorre.app" "$ZIP"

# generate_appcast signs each zip with the private key in the login keychain and creates or extends
# appcast.xml next to the zips. Keep older zips in this folder so the appcast keeps their entries.
APPCAST_ARGS=()
if [[ -n "${LORRE_UPDATE_DOWNLOAD_PREFIX:-}" ]]; then
  APPCAST_ARGS+=(--download-url-prefix "$LORRE_UPDATE_DOWNLOAD_PREFIX")
fi
"$GENERATE_APPCAST" "${APPCAST_ARGS[@]}" "$RELEASE_DIR"

echo
echo "Release $VERSION ($BUILD) is ready. Publish these two files:"
echo "  $ZIP"
echo "  $RELEASE_DIR/appcast.xml"
