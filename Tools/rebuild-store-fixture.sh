#!/bin/bash
# Re-cuts the history fixture that verify-store.sh checks against.
#
# Only run this when the schema has deliberately changed AND you have confirmed the new
# schema can carry real history forward. The fixture is meant to be a snapshot of an
# older build's data; regenerating it to make a failing check pass would hide exactly
# the bug it exists to catch.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT="$(mktemp -d)"
trap 'rm -rf "$OUT"' EXIT

swiftc -Onone -o "$OUT/fixture-builder" \
  "$ROOT/Tools/LegacyFixtureBuilder/LegacyScanRecord.swift" \
  "$ROOT/Tools/LegacyFixtureBuilder/main.swift"

BINMATE_FIXTURE="$ROOT/Tools/Fixtures/history-legacy.store" "$OUT/fixture-builder"
