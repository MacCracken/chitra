#!/usr/bin/env bash
# bench-csv.sh — run the benchmark harness and append its results to
# bench-history.csv.
#
# The harness (tests/bcyr/chitra.bcyr) prints a human-readable report AND a
# machine-readable `CSV:<benchmark>,<min_ns>` line per benchmark. This script
# stamps each of those with the timestamp / commit / branch the history file
# wants, so the committed series is reproducible rather than hand-typed.
#
#   ./scripts/bench-csv.sh            # append to bench-history.csv
#   ./scripts/bench-csv.sh --dry-run  # print the rows, write nothing
#
# Numbers are the observed MINIMUM per benchmark, which is the least
# noise-sensitive estimator on a shared machine — but they are still host
# and load dependent. Compare rows from the same host, not across hosts.

set -euo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO"

CSV="bench-history.csv"
DRY=0
[ "${1:-}" = "--dry-run" ] && DRY=1

TS=$(date -u +%Y-%m-%dT%H:%M:%SZ)
COMMIT=$(git rev-parse --short HEAD 2>/dev/null || echo "nogit")
BRANCH=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "nogit")

out=$(cyrius bench tests/bcyr/chitra.bcyr 2>&1)
if ! echo "$out" | grep -q '^CSV:'; then
    echo "bench-csv: harness produced no CSV rows — did it abort?" >&2
    echo "$out" >&2
    exit 1
fi
if echo "$out" | grep -q 'BENCH ABORTED'; then
    echo "bench-csv: harness reported a fixture failure; refusing to record numbers." >&2
    echo "$out" >&2
    exit 1
fi

rows=$(echo "$out" | grep '^CSV:' | sed "s|^CSV:|$TS,$COMMIT,$BRANCH,|")

if [ "$DRY" -eq 1 ]; then
    echo "$rows"
    exit 0
fi

if [ ! -f "$CSV" ]; then
    echo "timestamp,commit,branch,benchmark,estimate_ns" > "$CSV"
fi
echo "$rows" >> "$CSV"
echo "bench-csv: appended $(echo "$rows" | wc -l) rows to $CSV"
