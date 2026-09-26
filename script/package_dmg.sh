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

LOCAL_ONLY="${ALLOW_UNSIGNED:-}"
IDENTITY="${CODESIGN_IDENTITY:-}"
if [[ "$LOCAL_ONLY" != "1" && -z "$IDENTITY" ]]; then
  IDENTITY="$(security find-identity -v -p codesigning | awk -F '"' '/Developer ID Application/ { print $2; exit }')"
fi

if [[ "$LOCAL_ONLY" == "1" ]]; then
  echo "Writing an unsigned local disk image. This is not a public release and will not be notarized."
elif [[ -z "$IDENTITY" || -z "${NOTARY_KEYCHAIN_PROFILE:-}" ]]; then
  echo "A public release requires a Developer ID Application certificate and NOTARY_KEYCHAIN_PROFILE." >&2
  echo "Set ALLOW_UNSIGNED=1 only for a local test image. That image must not be published." >&2
  exit 1
fi

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

if [[ "$LOCAL_ONLY" != "1" ]]; then
  echo "Signing with $IDENTITY"
  codesign --force --options runtime --timestamp --sign "$IDENTITY" --entitlements "$ENTITLEMENTS" "$APP"
  codesign --verify --deep --strict --verbose=2 "$APP"
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

if [[ "$LOCAL_ONLY" == "1" ]]; then
  echo "Created local test image $DMG"
  echo "It is not notarized and must not be published."
  lipo -archs "$APP/Contents/MacOS/$APP_NAME"
  exit 0
fi

codesign --force --timestamp --sign "$IDENTITY" "$DMG"
echo "Submitting $DMG for notarization"
xcrun notarytool submit "$DMG" --keychain-profile "$NOTARY_KEYCHAIN_PROFILE" --wait
xcrun stapler staple "$APP"
xcrun stapler staple "$DMG"
xcrun stapler validate "$APP"
xcrun stapler validate "$DMG"
spctl --assess --type execute --verbose=2 "$APP"
spctl --assess --type open --context context:primary-signature --verbose=2 "$DMG"

echo "Created notarized $DMG"
lipo -archs "$APP/Contents/MacOS/$APP_NAME"
