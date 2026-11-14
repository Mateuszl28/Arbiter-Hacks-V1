#!/bin/bash
# Builds BinMate for the iOS Simulator SDK.
#
# Uses -target rather than -scheme on purpose: -scheme requires a bootable simulator
# destination, and this compiles fine on a machine with no simulator runtimes installed.
#
#   ./Tools/build.sh            # debug
#   ./Tools/build.sh Release
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONFIG="${1:-Debug}"

cd "$ROOT"
xcodebuild \
  -project BinMate.xcodeproj \
  -target BinMate \
  -sdk iphonesimulator \
  -arch arm64 \
  -configuration "$CONFIG" \
  CODE_SIGNING_ALLOWED=NO \
  build \
  | grep -E "error:|BUILD (SUCCEEDED|FAILED)" || true

echo "Built: $ROOT/build/$CONFIG-iphonesimulator/BinMate.app"
