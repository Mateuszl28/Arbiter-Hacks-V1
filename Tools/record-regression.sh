#!/bin/bash
# Re-records the regression baseline.
#
# Run this only after reading the diff from verify-regression.sh and agreeing with every
# change. Recording to make a red check go green is the one way to make this tool
# worthless.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BINMATE_RECORD=1 "$ROOT/Tools/verify-regression.sh"
