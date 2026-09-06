#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
env DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild \
  -project "$ROOT_DIR/BuildSweep.xcodeproj" \
  -scheme BuildSweep \
  -configuration Debug \
  -derivedDataPath "$ROOT_DIR/DerivedData" \
  -destination "platform=macOS" \
  CODE_SIGNING_ALLOWED=NO \
  test

