#!/bin/bash
# Loads the real built .app bundle on the host machine and verifies that every bundled
# ruleset and sample product is discoverable and valid.
#
# Xcode flattens resource directories into the bundle root, so the layout the loaders
# see at runtime is not the layout in the repo. This checks the actual result.
#
#   ./Tools/build.sh && ./Tools/verify-bundle.sh
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP="${1:-$ROOT/build/Debug-iphonesimulator/BinMate.app}"

if [ ! -d "$APP" ]; then
  echo "No app bundle at $APP — run ./Tools/build.sh first." >&2
  exit 1
fi

OUT="$(mktemp -d)"
trap 'rm -rf "$OUT"' EXIT

swiftc -Onone -o "$OUT/bundle-checks" \
  "$ROOT/BinMate/Model/TaxonomyID.swift" \
  "$ROOT/BinMate/Model/MaterialTaxonomy.swift" \
  "$ROOT/BinMate/Model/PackagingComponent.swift" \
  "$ROOT/BinMate/Model/CityRuleset.swift" \
  "$ROOT/BinMate/Model/CurrencyFormatting.swift" \
  "$ROOT/BinMate/Model/StreamContrast.swift" \
  "$ROOT/BinMate/Engine/RulesEngine.swift" \
  "$ROOT/BinMate/Engine/RulesLibrary.swift" \
  "$ROOT/BinMate/Engine/CityGuide.swift" \
  "$ROOT/BinMate/Engine/NearestCity.swift" \
  "$ROOT/BinMate/Services/SampleProducts.swift" \
  "$ROOT/BinMate/Services/QuickItem.swift" \
  "$ROOT/Tools/BundleLoadChecks/main.swift"

BINMATE_APP="$APP" \
BINMATE_INTENT_SOURCE="$ROOT/BinMate/Services/WhichBinIntent.swift" \
  "$OUT/bundle-checks"
