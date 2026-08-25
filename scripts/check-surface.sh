#!/usr/bin/env bash
# check-surface.sh — the public surface is a list, and this checks the bundle
# against it.
#
# dist/chitra.cyr is a strip-concatenated bundle, so EVERY chitra_-prefixed
# function in it is callable by a consumer whether or not it was meant to be.
# docs/development/public-surface.md splits those names into FROZEN (covered by
# the v1.0 compatibility promise) and INTERNAL_NAMES (visible but not promised).
#
# This script fails when the bundle and the manifest disagree in either
# direction:
#   * a name in the bundle that the manifest does not list — a new export
#     nobody classified, which at v1.0 is a promise made by accident;
#   * a name in the manifest that the bundle no longer has — a removal that
#     slipped through, or a manifest gone stale.
#
# It deliberately does NOT parse @public markers. Those are carried two
# different ways (a file-level banner and a per-function marker), which is
# exactly the ambiguity a freeze should not codify.
#
# Exit 0 = agree. Exit 1 = disagree, with the difference printed.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUNDLE="$ROOT/dist/chitra.cyr"
MANIFEST="$ROOT/docs/development/public-surface.md"

[ -f "$BUNDLE" ]   || { echo "check-surface: missing $BUNDLE (run 'make dist')"; exit 1; }
[ -f "$MANIFEST" ] || { echo "check-surface: missing $MANIFEST"; exit 1; }

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

# Exported names, as the bundle actually defines them.
grep -oE '^fn chitra_[a-z0-9_]+' "$BUNDLE" | sed 's/^fn //' | sort -u > "$tmp/bundle"

# Manifest names: every chitra_* token inside a fenced code block. The prose
# mentions names too (consumers, records), so only the fences count.
awk '/^```/ { infence = !infence; next } infence { print }' "$MANIFEST" \
    | grep -oE 'chitra_[a-z0-9_]+' | sort -u > "$tmp/manifest"

comm -23 "$tmp/bundle" "$tmp/manifest" > "$tmp/unlisted"
comm -13 "$tmp/bundle" "$tmp/manifest" > "$tmp/missing"

rc=0
if [ -s "$tmp/unlisted" ]; then
    echo "check-surface: exported but NOT in the manifest —"
    echo "  a new chitra_* export nobody classified. Add it to FROZEN (and mean"
    echo "  it) or to INTERNAL_NAMES in docs/development/public-surface.md."
    sed 's/^/    /' "$tmp/unlisted"
    rc=1
fi
if [ -s "$tmp/missing" ]; then
    echo "check-surface: in the manifest but NOT exported —"
    echo "  a removal. If it was FROZEN this is a breaking change and needs a"
    echo "  major bump plus an ADR; if INTERNAL, just drop it from the list."
    sed 's/^/    /' "$tmp/missing"
    rc=1
fi

if [ $rc -eq 0 ]; then
    frozen=$(awk '/^## FROZEN/,/^## INTERNAL_NAMES/' "$MANIFEST" \
        | awk '/^```/ { infence = !infence; next } infence { print }' \
        | grep -oE 'chitra_[a-z0-9_]+' | sort -u | wc -l)
    total=$(wc -l < "$tmp/bundle")
    echo "check-surface: bundle and manifest agree — ${total} exports, ${frozen} frozen"
fi
exit $rc
