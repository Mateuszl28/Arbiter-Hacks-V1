#!/bin/bash
# Compiles the pure-Swift model and engine for the host machine and runs the rules
# checks against the real bundled city JSON. No simulator, no Xcode UI, a few seconds.
#
#   ./Tools/verify-rules.sh
#
# Run it after editing anything in Shared/Rules.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT="$(mktemp -d)"
trap 'rm -rf "$OUT"' EXIT

swiftc -Onone -o "$OUT/rules-checks" \
  "$ROOT/Shared/TaxonomyID.swift" \
  "$ROOT/BinMate/Model/MaterialTaxonomy.swift" \
  "$ROOT/BinMate/Model/PackagingComponent.swift" \
  "$ROOT/Shared/CityRuleset.swift" \
  "$ROOT/BinMate/Engine/RulesEngine.swift" \
  "$ROOT/Tools/RulesEngineChecks/main.swift"

BINMATE_RULES="$ROOT/Shared/Rules" "$OUT/rules-checks"
