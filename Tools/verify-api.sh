#!/bin/bash
# Hits the LIVE Open Food Facts API and checks that real responses parse and resolve.
#
# Needs a network, and depends on data other people can edit, so it is deliberately not
# part of the build. Run it when touching OpenFoodFactsClient.
#
#   ./Tools/verify-api.sh                    # default barcodes
#   ./Tools/verify-api.sh 5449000000996      # a specific one
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT="$(mktemp -d)"
trap 'rm -rf "$OUT"' EXIT

swiftc -Onone -o "$OUT/api-checks" \
  "$ROOT/BinMate/Model/TaxonomyID.swift" \
  "$ROOT/BinMate/Model/MaterialTaxonomy.swift" \
  "$ROOT/BinMate/Model/PackagingComponent.swift" \
  "$ROOT/BinMate/Model/CityRuleset.swift" \
  "$ROOT/BinMate/Engine/RulesEngine.swift" \
  "$ROOT/BinMate/Services/OpenFoodFactsClient.swift" \
  "$ROOT/Tools/APIChecks/main.swift"

BINMATE_RULES="$ROOT/BinMate/Resources/Rules" "$OUT/api-checks" "$@"
