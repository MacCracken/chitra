#!/usr/bin/env bash
# check-surface.sh — the public surface is a list, and this checks the bundle
# against it.
#
# dist/chitra.cyr is a strip-concatenated bundle, so EVERY function in it is
# callable by a consumer whether or not it was meant to be. Since 1.2.0 the
# public prefix IS the promise: the bundle's chitra_* functions must be exactly
# the FROZEN names in docs/development/public-surface.md, and everything internal
# is _chitra_* / _CHITRA_*. (Through 1.1.4 the manifest also had an
# INTERNAL_NAMES block of 46 visible-but-unpromised chitra_* names, and which
# block a name sat in was enforced by nothing but review.)
#
# This script fails when the bundle and the manifest disagree in either
# direction:
#   * a chitra_* function the manifest does not list — a new public name nobody
#     decided on: freeze it here (a promise, with an ADR) or name it _chitra_*;
#   * a FROZEN name the bundle no longer has — a removal, which is a breaking
#     change.
#
# It also fails when a member of `enum ChitraErrCode` has no chitra_err_name
# arm, or no literal value pin in tests/tcyr/surface.tcyr (see below), and when
# the bundle declares a top-level `var` (cc-13, 1.1.2) or `fn` (1.1.3) without a
# chitra prefix.
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
    echo "check-surface: chitra_* functions that are NOT frozen —"
    echo "  the public prefix is the promise. Add it to FROZEN in"
    echo "  docs/development/public-surface.md (and mean it — an ADR), or rename it"
    echo "  _chitra_* if it is internal."
    sed 's/^/    /' "$tmp/unlisted"
    rc=1
fi
if [ -s "$tmp/missing" ]; then
    echo "check-surface: FROZEN but no longer in the bundle —"
    echo "  a removal or a rename of a promised name: a breaking change, which"
    echo "  needs a major bump plus an ADR."
    sed 's/^/    /' "$tmp/missing"
    rc=1
fi

# ChitraErrCode coverage (1.1.1, gate-7 / gate-13). The freeze covers the
# NUMERIC VALUES of the enum, and those are pinned literally by the
# _sf_frozen_code table in tests/tcyr/surface.tcyr — which also asserts each
# code has a name of its own. Both that table and chitra_err_name are lists a
# new enum member can silently miss (the old name loop stopped at 34 and never
# saw INFLATE_LIMIT), so every member of the bundle's enum must appear in both.
PINS="$ROOT/tests/tcyr/surface.tcyr"
awk '/^enum ChitraErrCode[[:space:]]*\{/,/^}/' "$BUNDLE" \
    | grep -oE '^[[:space:]]*CHITRA_[A-Z0-9_]+[[:space:]]*=' \
    | grep -oE 'CHITRA_[A-Z0-9_]+' | sort -u > "$tmp/enum" || true
awk '/^fn chitra_err_name\(/,/^}/' "$BUNDLE" \
    | grep -oE 'code == CHITRA_[A-Z0-9_]+' \
    | grep -oE 'CHITRA_[A-Z0-9_]+' | sort -u > "$tmp/named" || true
if [ -f "$PINS" ]; then
    grep -oE '_sf_frozen_code\(CHITRA_[A-Z0-9_]+,' "$PINS" \
        | grep -oE 'CHITRA_[A-Z0-9_]+' | sort -u > "$tmp/pinned" || true
else
    : > "$tmp/pinned"
fi
if [ ! -s "$tmp/enum" ]; then
    # Fail closed: an enum this script cannot read is not an enum it has checked.
    echo "check-surface: could not read 'enum ChitraErrCode' from $BUNDLE"
    rc=1
else
    comm -23 "$tmp/enum" "$tmp/named" > "$tmp/unnamed"
    comm -23 "$tmp/enum" "$tmp/pinned" > "$tmp/unpinned"
    if [ -s "$tmp/unnamed" ]; then
        echo "check-surface: ChitraErrCode members with no chitra_err_name arm —"
        echo "  they print \"unknown error\"."
        sed 's/^/    /' "$tmp/unnamed"
        rc=1
    fi
    if [ -s "$tmp/unpinned" ]; then
        echo "check-surface: ChitraErrCode members with no _sf_frozen_code row in"
        echo "  tests/tcyr/surface.tcyr — their numeric value is frozen by nothing."
        sed 's/^/    /' "$tmp/unpinned"
        rc=1
    fi
fi

# Every top-level `var` in the bundle is a global in the CONSUMER'S program, so
# its name must be chitra's: `_chitra_*`, `_CHITRA_*`, or the public `CHITRA_*`
# constants. Through 1.1.1, 128 were not (RAW_*, CUR_*, IMAGE_*_OFFSET, HT_*,
# BR_*, JF_*, BH_*, LZ_*, FIX_*, ...), and a consumer's own global of one of
# those names — declared after chitra, or just assigned — rewrote the value
# chitra decodes with: `CUR_POS_OFFSET` crashed the JPEG and PNG decoders,
# `LZ_BIT` the GIF one. tests/tcyr/namespace.tcyr is that consumer.
grep -E '^var ' "$BUNDLE" | grep -vE '^var _?(chitra|CHITRA)_' \
    | sed -E 's/^var ([A-Za-z0-9_]+).*/\1/' > "$tmp/unprefixed" || true
if [ -s "$tmp/unprefixed" ]; then
    echo "check-surface: top-level globals without a chitra prefix — a consumer's"
    echo "  global of the same name would silently rewrite them (cc-13):"
    sed 's/^/    /' "$tmp/unprefixed"
    rc=1
fi

# Functions have the same exposure (1.1.3). A consumer `fn` of the same name
# REPLACES chitra's — the compiler says "duplicate fn … last definition wins" and
# links the consumer's. Through 1.1.2, 84 internal helpers (`_jpeg_*`, `_bmp_*`,
# `_cur_*`, ...) had no prefix, and a consumer `_jpeg_descale` changed JPEG
# pixels. Every function is `chitra_*` (the frozen 29 plus the classified
# internals above) or `_chitra_*`.
grep -E '^fn ' "$BUNDLE" | grep -vE '^fn _?chitra_' \
    | sed -E 's/^fn ([A-Za-z0-9_]+).*/\1/' > "$tmp/unprefixed_fn" || true
if [ -s "$tmp/unprefixed_fn" ]; then
    echo "check-surface: functions without a chitra prefix — a consumer function of"
    echo "  the same name would silently replace them:"
    sed 's/^/    /' "$tmp/unprefixed_fn"
    rc=1
fi

if [ $rc -eq 0 ]; then
    frozen=$(awk '/^## FROZEN/,/^## Internal names/' "$MANIFEST" \
        | awk '/^```/ { infence = !infence; next } infence { print }' \
        | grep -oE 'chitra_[a-z0-9_]+' | sort -u | wc -l)
    total=$(wc -l < "$tmp/bundle")
    codes=$(wc -l < "$tmp/enum")
    globals=$(grep -cE '^var ' "$BUNDLE")
    fns=$(grep -cE '^fn ' "$BUNDLE")
    echo "check-surface: bundle and manifest agree — ${total} chitra_* functions, all ${frozen} frozen;" \
        "${codes} ChitraErrCode members, each named and value-pinned;" \
        "${globals} globals and ${fns} functions, all chitra-prefixed"
fi
exit $rc
