#!/bin/bash
# Opens a history store written by an earlier build and checks that today's model can
# still read every record and every field.
#
# The fixture is cut from the schema as it was BEFORE the take-back work, so this is a
# genuine old-to-new upgrade rather than a store written by the same code that reads it.
# See Tools/StoreMigrationChecks/main.swift.
#
#   ./Tools/verify-store.sh
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT="$(mktemp -d)"
trap 'rm -rf "$OUT"' EXIT

swiftc -Onone -o "$OUT/store-checks" \
  "$ROOT/Shared/TaxonomyID.swift" \
  "$ROOT/BinMate/Model/MaterialTaxonomy.swift" \
  "$ROOT/BinMate/Model/PackagingComponent.swift" \
  "$ROOT/Shared/CityRuleset.swift" \
  "$ROOT/BinMate/Engine/RulesEngine.swift" \
  "$ROOT/BinMate/Engine/Uncertainty.swift" \
  "$ROOT/Shared/RulesLibrary.swift" \
  "$ROOT/BinMate/Engine/DecisionRecord.swift" \
  "$ROOT/BinMate/Model/ScanRecord.swift" \
  "$ROOT/Tools/StoreMigrationChecks/main.swift"

BINMATE_FIXTURE="$ROOT/Tools/Fixtures/history-legacy.store" "$OUT/store-checks"
