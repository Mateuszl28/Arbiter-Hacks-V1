#!/bin/bash
# Builds and launches BinMate as a Mac Catalyst app.
#
# Useful because it needs no iOS simulator runtime: on a machine where the runtime is
# missing or still downloading, this is the fastest way to actually see the app run.
# Camera scanning is unavailable on Catalyst, so the scanner sheet offers barcode entry
# and the manual packaging picker instead — every other flow is identical.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

xcodebuild \
  -project BinMate.xcodeproj \
  -scheme BinMate \
  -destination 'platform=macOS,variant=Mac Catalyst' \
  -configuration Debug \
  CODE_SIGNING_ALLOWED=NO \
  build \
  | grep -E "error:|BUILD (SUCCEEDED|FAILED)" || true

APP="$(find "$HOME/Library/Developer/Xcode/DerivedData"/BinMate-*/Build/Products/Debug-maccatalyst \
  -maxdepth 1 -name 'BinMate.app' 2>/dev/null | head -1)"

if [ -z "$APP" ]; then
  echo "Could not find the built app." >&2
  exit 1
fi

echo "Launching $APP"
open "$APP"
