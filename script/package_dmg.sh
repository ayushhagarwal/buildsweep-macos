#!/usr/bin/env bash
# Build a versioned BuildSweep disk image.
# A public download needs Developer ID signing and notarization.
# ALLOW_UNSIGNED=1 writes a local image that Gatekeeper will reject.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="BuildSweep"
INFO_PLIST="$ROOT_DIR/BuildSweep/Info.plist"
ENTITLEMENTS="$ROOT_DIR/BuildSweep/BuildSweep.entitlements"
HELPER_ENTITLEMENTS="$ROOT_DIR/BuildSweepMCP/BuildSweepMCP.entitlements"
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

APP_SIGNING_ENTITLEMENTS="$ENTITLEMENTS"
HELPER_SIGNING_ENTITLEMENTS="$HELPER_ENTITLEMENTS"
if [[ "$LOCAL_ONLY" != "1" ]]; then
  if [[ -z "${DEVELOPMENT_TEAM:-}" ]]; then
    IDENTITY_LINE="$(security find-identity -v -p codesigning | awk -F '\"' -v identity="$IDENTITY" '$2 == identity || index($0, identity) { print; exit }')"
    DEVELOPMENT_TEAM="$(printf '%s\n' "$IDENTITY_LINE" | sed -nE 's/.*\(([A-Z0-9]{10})\)[[:space:]]*$/\1/p')"
  fi
  if [[ ! "${DEVELOPMENT_TEAM:-}" =~ ^[A-Z0-9]{10}$ ]]; then
    echo "Could not determine the 10-character Apple Developer team ID from the signing identity." >&2
    echo "Set DEVELOPMENT_TEAM to the team that owns the Developer ID certificate." >&2
    exit 1
  fi
  APP_SIGNING_ENTITLEMENTS="$STAGE/BuildSweep.entitlements"
  HELPER_SIGNING_ENTITLEMENTS="$STAGE/BuildSweepMCP.entitlements"
  cp "$ENTITLEMENTS" "$APP_SIGNING_ENTITLEMENTS"
  cp "$HELPER_ENTITLEMENTS" "$HELPER_SIGNING_ENTITLEMENTS"
  /usr/libexec/PlistBuddy -c "Set :com.apple.security.application-groups:0 ${DEVELOPMENT_TEAM}.com.ayush.buildsweep" "$APP_SIGNING_ENTITLEMENTS"
  /usr/libexec/PlistBuddy -c "Set :com.apple.security.application-groups:0 ${DEVELOPMENT_TEAM}.com.ayush.buildsweep" "$HELPER_SIGNING_ENTITLEMENTS"
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

MCP_HELPER="$APP/Contents/Library/HelperTools/BuildSweepMCP"
if [[ ! -x "$MCP_HELPER" ]]; then
  echo "Expected embedded MCP helper was not produced: $MCP_HELPER" >&2
  exit 1
fi

if [[ "$LOCAL_ONLY" != "1" ]]; then
  echo "Signing with $IDENTITY"
  codesign --force --options runtime --timestamp --sign "$IDENTITY" --entitlements "$HELPER_SIGNING_ENTITLEMENTS" "$MCP_HELPER"
  codesign --verify --strict --verbose=2 "$MCP_HELPER"
  codesign --force --options runtime --timestamp --sign "$IDENTITY" --entitlements "$APP_SIGNING_ENTITLEMENTS" "$APP"
  codesign --verify --deep --strict --verbose=2 "$APP"
  codesign -dv --verbose=4 "$MCP_HELPER" 2>&1 | rg -q "TeamIdentifier=${DEVELOPMENT_TEAM}"
  codesign -dv --verbose=4 "$APP" 2>&1 | rg -q "TeamIdentifier=${DEVELOPMENT_TEAM}"
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
