#!/bin/bash
# Resolves every known case and compares against the recorded baseline.
#
# Rules are data, and editing data silently changes answers. Adding one broad rule can
# re-route every plastic in a city, and the only symptom is users being told something
# different. A change here is not automatically wrong — most are intended. Not knowing is
# what this prevents.
#
#   ./Tools/verify-regression.sh
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT="$(mktemp -d)"
trap 'rm -rf "$OUT"' EXIT

swiftc -Onone -o "$OUT/regression" \
  "$ROOT/Shared/TaxonomyID.swift" \
  "$ROOT/BinMate/Model/MaterialTaxonomy.swift" \
  "$ROOT/BinMate/Model/OFFTaxonomy+Generated.swift" \
  "$ROOT/BinMate/Model/OFFSynonyms.swift" \
  "$ROOT/BinMate/Model/PackagingComponent.swift" \
  "$ROOT/Shared/CityRuleset.swift" \
  "$ROOT/BinMate/Engine/RulesEngine.swift" \
  "$ROOT/BinMate/Engine/Uncertainty.swift" \
  "$ROOT/Tools/RegressionLab/main.swift"

BINMATE_RULES="$ROOT/Shared/Rules" \
  BINMATE_SYNONYMS="$ROOT/BinMate/Resources/off-synonyms.json" \
BINMATE_BASELINE="$ROOT/Tools/Fixtures/regression-baseline.json" \
  "$OUT/regression"
