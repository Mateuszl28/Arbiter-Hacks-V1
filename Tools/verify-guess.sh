#!/bin/bash
# Checks the Vision-label-to-packaging-part mapping, and that every suggestion it can
# produce resolves to a real stream in every bundled city.
#
# The mapping is kept free of the Vision framework precisely so this can run on the host
# without a device, a photo, or a model.
#
#   ./Tools/verify-guess.sh
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT="$(mktemp -d)"
trap 'rm -rf "$OUT"' EXIT

swiftc -Onone -o "$OUT/guess-checks" \
  "$ROOT/BinMate/Model/TaxonomyID.swift" \
  "$ROOT/BinMate/Model/MaterialTaxonomy.swift" \
  "$ROOT/BinMate/Model/PackagingComponent.swift" \
  "$ROOT/BinMate/Model/CityRuleset.swift" \
  "$ROOT/BinMate/Engine/RulesEngine.swift" \
  "$ROOT/BinMate/Services/PackagingGuess.swift" \
  "$ROOT/Tools/GuessChecks/main.swift"

BINMATE_RULES="$ROOT/BinMate/Resources/Rules" "$OUT/guess-checks"
