#!/bin/bash
# Checks the bundled material tree against the published taxonomy it is derived from.
#
#   ./Tools/verify-taxonomy.sh
#
# Runs offline against the vendored snapshot in Tools/Fixtures, so it gives the same
# answer twice. Run ./Tools/refresh-taxonomy.sh to pull a newer one.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT="$(mktemp -d)"
trap 'rm -rf "$OUT"' EXIT

swiftc -Onone -o "$OUT/taxonomy-checks" \
  "$ROOT/Shared/TaxonomyID.swift" \
  "$ROOT/BinMate/Model/MaterialTaxonomy.swift" \
  "$ROOT/BinMate/Model/OFFTaxonomy+Generated.swift" \
  "$ROOT/BinMate/Model/OFFSynonyms.swift" \
  "$ROOT/Shared/CityRuleset.swift" \
  "$ROOT/Tools/TaxonomyChecks/main.swift"

BINMATE_RULES="$ROOT/Shared/Rules" \
  BINMATE_MATERIALS_SNAPSHOT="$ROOT/Tools/Fixtures/off-packaging-materials.json" \
  BINMATE_SHAPES_SNAPSHOT="$ROOT/Tools/Fixtures/off-packaging-shapes.json" \
  BINMATE_SYNONYMS="$ROOT/BinMate/Resources/off-synonyms.json" "$OUT/taxonomy-checks"
