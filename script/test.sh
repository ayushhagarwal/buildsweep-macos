#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# Debug test builds use the host slice; the packaging path separately builds universal Release binaries.
HOST_ARCH="$(uname -m)"
env DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild \
  -project "$ROOT_DIR/BuildSweep.xcodeproj" \
  -scheme BuildSweep \
  -configuration Debug \
  -derivedDataPath "$ROOT_DIR/DerivedData" \
  -destination "platform=macOS" \
  ARCHS="$HOST_ARCH" \
  ONLY_ACTIVE_ARCH=YES \
  CODE_SIGNING_ALLOWED=NO \
  test
