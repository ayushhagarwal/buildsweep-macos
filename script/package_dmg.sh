#!/usr/bin/env bash
# Build a versioned BuildSweep disk image.
# A public download needs Developer ID signing and notarization.
# ALLOW_UNSIGNED=1 writes a local image that Gatekeeper will reject.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="BuildSweep"
INFO_PLIST="$ROOT_DIR/BuildSweep/Info.plist"
ENTITLEMENTS="$ROOT_DIR/BuildSweep/BuildSweep.entitlements"
DERIVED_DATA="$ROOT_DIR/DerivedDataRelease"
DIST="$ROOT_DIR/dist"

VERSION="$(plutil -extract CFBundleShortVersionString raw "$INFO_PLIST")"
BUILD="$(plutil -extract CFBundleVersion raw "$INFO_PLIST")"
APP="$DIST/$APP_NAME.app"
DMG="$DIST/${APP_NAME}-${VERSION}.dmg"
STAGE="$(mktemp -d)"

cleanup() {
  rm -rf "$STAGE"
}
trap cleanup EXIT

echo "Building $APP_NAME $VERSION ($BUILD) for arm64 and x86_64"
env DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}" xcodebuild \
  -project "$ROOT_DIR/BuildSweep.xcodeproj" \
  -scheme "$APP_NAME" \
  -configuration Release \
  -derivedDataPath "$DERIVED_DATA" \
  -destination "generic/platform=macOS" \
  ARCHS="arm64 x86_64" \
  ONLY_ACTIVE_ARCH=NO \
  CODE_SIGNING_ALLOWED=NO \
  build

rm -rf "$APP"
mkdir -p "$DIST"
ditto "$DERIVED_DATA/Build/Products/Release/$APP_NAME.app" "$APP"

IDENTITY="${CODESIGN_IDENTITY:-}"
if [[ -z "$IDENTITY" ]]; then
  IDENTITY="$(security find-identity -v -p codesigning | awk -F '"' '/Developer ID Application/ { print $2; exit }')"
fi

if [[ -n "$IDENTITY" ]]; then
  echo "Signing with $IDENTITY"
  codesign --force --options runtime --timestamp --sign "$IDENTITY" --entitlements "$ENTITLEMENTS" "$APP"
  codesign --verify --deep --strict --verbose=2 "$APP"
else
  if [[ "${ALLOW_UNSIGNED:-}" != "1" ]]; then
    echo "No Developer ID Application identity found." >&2
    echo "Install one, set CODESIGN_IDENTITY, or set ALLOW_UNSIGNED=1 for a local test image." >&2
    exit 1
  fi
  echo "Writing an unsigned local disk image. Gatekeeper will not accept it as a public download."
fi

cp -R "$APP" "$STAGE/$APP_NAME.app"
ln -s /Applications "$STAGE/Applications"

rm -f "$DMG"
hdiutil create \
  -volname "$APP_NAME $VERSION" \
  -srcfolder "$STAGE" \
  -ov \
  -format UDZO \
  "$DMG"

if [[ -n "$IDENTITY" ]]; then
  codesign --force --timestamp --sign "$IDENTITY" "$DMG"
fi

if [[ -n "${NOTARY_KEYCHAIN_PROFILE:-}" ]]; then
  echo "Submitting $DMG for notarization"
  xcrun notarytool submit "$DMG" --keychain-profile "$NOTARY_KEYCHAIN_PROFILE" --wait
  xcrun stapler staple "$DMG"
  spctl --assess --type open --context context:primary-signature --verbose=2 "$DMG" || true
  spctl --assess --type execute --verbose=2 "$APP"
fi

echo "Created $DMG"
lipo -archs "$APP/Contents/MacOS/$APP_NAME"
