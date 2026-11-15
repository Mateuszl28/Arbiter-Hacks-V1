#!/bin/bash
# Pulls fresh Open Food Facts packaging taxonomies, vendors a trimmed snapshot and
# regenerates the Swift tree.
#
# The snapshot is vendored on purpose. ./Tools/verify-taxonomy.sh has to run offline and
# give the same answer twice, and a suite that silently depends on a remote file is a
# suite that fails for reasons that have nothing to do with the code. Refreshing is
# therefore a deliberate act with a visible diff, not something a test does behind your
# back.
#
# Ids, parents and names in every language are kept. The descriptions are not: they run
# to a paragraph per language and make the upstream files over 200 kB each. The names
# matter because contributed data is not in English — a measured 7% of packaging
# identifiers in a real category sample carried another language's prefix, including
# "es:Plástico" and "fr:PP 5 - Polypropylène", none of which BinMate could place.
set -euo pipefail
cd "$(dirname "$0")/.."

BASE="https://static.openfoodfacts.org/data/taxonomies"
AGENT="BinMate/1.0 (hackathon project; taxonomy snapshot)"

for pair in "packaging_materials:off-packaging-materials" "packaging_shapes:off-packaging-shapes"; do
    upstream="${pair%%:*}"
    vendored="${pair##*:}"
    echo "fetching $upstream.json"
    curl -sfL -A "$AGENT" "$BASE/$upstream.json" -o "/tmp/$upstream.json"

    python3 - "$upstream" "$vendored" <<'PY'
import json, sys
upstream, vendored = sys.argv[1], sys.argv[2]
with open("/tmp/%s.json" % upstream, encoding="utf-8") as handle:
    full = json.load(handle)

trimmed = {}
for key, entry in full.items():
    kept = {}
    if entry.get("parents"):
        kept["parents"] = entry["parents"]
    names = {
        lang: value.strip()
        for lang, value in (entry.get("name") or {}).items()
        if isinstance(value, str) and value.strip()
    }
    if names:
        kept["name"] = names
    trimmed[key] = kept

path = "Tools/Fixtures/%s.json" % vendored
with open(path, "w", encoding="utf-8") as handle:
    json.dump(trimmed, handle, ensure_ascii=False, indent=1, sort_keys=True)
    handle.write("\n")
print("  %d entries -> %s" % (len(trimmed), path))
PY
done

echo
python3 Tools/generate-taxonomy.py
echo
echo "Review the diff, then run ./Tools/verify-taxonomy.sh and ./Tools/verify-regression.sh."
echo "A refreshed taxonomy can move verdicts; that is what the regression lab is for."
