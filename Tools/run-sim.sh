#!/bin/bash
# Builds, reinstalls and relaunches BinMate on the iPhone simulator.
#
# `simctl install` is not hot reload: without this, the simulator keeps running whatever
# binary was installed last, which silently makes it look like changes had no effect.
# Run this after every change you want to see on the phone.
#
#   ./Tools/run-sim.sh                 # uses the first booted device, or boots one
#   ./Tools/run-sim.sh "iPhone 17 Pro" # a specific device by name
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

BUNDLE_ID="app.binmate.BinMate"
WANTED="${1:-}"

# Prefer a device that is already booted, so an open simulator window is reused.
UDID="$(xcrun simctl list devices booted -j \
  | python3 -c "
import json,sys
d=json.load(sys.stdin)['devices']
want='''$WANTED'''
for runtime, devices in d.items():
    for dev in devices:
        if dev.get('state') == 'Booted' and (not want or dev['name'] == want):
            print(dev['udid']); raise SystemExit
")"

if [ -z "$UDID" ]; then
  NAME="${WANTED:-iPhone 17 Pro}"
  UDID="$(xcrun simctl list devices available -j \
    | python3 -c "
import json,sys
d=json.load(sys.stdin)['devices']
for runtime, devices in d.items():
    for dev in devices:
        if dev['name'] == '''$NAME''':
            print(dev['udid']); raise SystemExit
")"
  [ -n "$UDID" ] || { echo "No simulator called '$NAME'." >&2; exit 1; }
  echo "Booting $NAME…"
  xcrun simctl boot "$UDID"
  open -a Simulator
  sleep 8
fi

echo "Building…"
xcodebuild \
  -project BinMate.xcodeproj \
  -target BinMate \
  -sdk iphonesimulator \
  -arch arm64 \
  -configuration Debug \
  CODE_SIGNING_ALLOWED=NO \
  build \
  | grep -E "error:|BUILD (SUCCEEDED|FAILED)" || true

APP="$ROOT/build/Debug-iphonesimulator/BinMate.app"
[ -d "$APP" ] || { echo "Build produced no app bundle." >&2; exit 1; }

# Terminate first: a running process keeps the old code even after reinstalling.
xcrun simctl terminate "$UDID" "$BUNDLE_ID" 2>/dev/null || true
xcrun simctl install "$UDID" "$APP"
xcrun simctl launch "$UDID" "$BUNDLE_ID" >/dev/null

echo "Running on $UDID — $(/usr/bin/stat -f '%Sm' "$APP/BinMate")"
