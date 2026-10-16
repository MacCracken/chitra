#!/usr/bin/env bash
# consumer-shape.sh — run chitra's suites the way most of its consumers link it.
#
# chitra's own build links sankoch's `zlib` profile through `[deps.sankoch]`.
# Three of its five consumers (kii, mabda, aethersafha) link the stdlib
# `"sankoch"` leaf instead — the FULL bundle from their toolchain's snapshot —
# and closest-wins means theirs replaces chitra's. That shape was tested
# nowhere: below sankoch 2.8.6 its inflate accepts stream classes zlib refuses
# (audit 2026-10-15, C-26), so chitra's PNG path accepted them too, and no
# chitra gate could see it.
#
# This builds a temporary copy of the tree in exactly that shape — `"sankoch"`
# in `[deps].stdlib`, no `[deps.sankoch]`, `src/lib.cyr` including
# `lib/sankoch.cyr` — on chitra's OWN pinned toolchain, and runs every suite.
# The verdict is behavioural, not a version compare: png.tcyr's png-3 cells
# feed streams only sankoch >= 2.8.6 refuses, and alloc_reset.tcyr exercises the
# full bundle's arena canary. So this fails if chitra ever pins a toolchain whose
# stdlib sankoch is below the floor its docs promise consumers.
#
# It never touches the working tree. Every rewrite is verified, and fails
# closed if it did not apply.
#
#   ./scripts/consumer-shape.sh        # make consumer-shape; also run by CI
set -euo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

cp -r "$REPO/src" "$REPO/tests" "$REPO/cyrius.cyml" "$REPO/VERSION" "$work/"
cd "$work"

fail() { echo "consumer-shape: $*"; exit 1; }

# 1. The manifest: the stdlib leaf in, chitra's [deps.sankoch] out.
awk '
    /^\[deps\.sankoch\]/ { skip = 1; next }
    skip && /^\[/        { skip = 0 }
    skip                 { next }
    /^stdlib = \[/       { print; print "    \"sankoch\","; next }
    { print }
' cyrius.cyml > cyrius.cyml.new
mv cyrius.cyml.new cyrius.cyml
grep -q '^    "sankoch",$' cyrius.cyml   || fail "could not add the stdlib \"sankoch\" leaf"
if grep -q 'deps\.sankoch' cyrius.cyml; then fail "could not remove [deps.sankoch]"; fi

# 2. The include chain: the full stdlib bundle in place of the zlib profile.
sed -i 's#^include "lib/sankoch-zlib.cyr"$#include "lib/sankoch.cyr"#' src/lib.cyr
grep -q '^include "lib/sankoch.cyr"$' src/lib.cyr || fail "could not switch src/lib.cyr to lib/sankoch.cyr"
if grep -q 'sankoch-zlib' src/lib.cyr; then fail "src/lib.cyr still names the zlib profile"; fi

# 3. Resolve, and prove the shape is the one intended: one sankoch, the full one.
mkdir lib
cyrius deps > deps.log 2>&1 || { cat deps.log; fail "cyrius deps failed"; }
[ -f lib/sankoch.cyr ]      || fail "lib/sankoch.cyr was not vendored"
[ ! -e lib/sankoch-zlib.cyr ] || fail "the zlib profile was vendored as well — two sankoch bundles"
ver="$(sed -n 's/^# Version: //p' lib/sankoch.cyr | head -1)"
pin="$(sed -n 's/^cyrius = "\(.*\)"$/\1/p' cyrius.cyml | head -1)"
echo "consumer-shape: cyrius $pin, stdlib sankoch ${ver:-unknown} (full bundle)"

# 4. Every suite, in that shape — and count what ran, so a loop that ran
#    nothing cannot read as a pass.
rc=0
suites=0
passed=0
for f in tests/tcyr/*.tcyr; do
    suites=$((suites + 1))
    cyrius test "$f" > test.log 2>&1 || { cat test.log; echo "consumer-shape: $f FAILED"; rc=1; }
    n="$(sed -n 's/^\([0-9][0-9]*\) passed, 0 failed.*/\1/p' test.log | tail -1)"
    passed=$((passed + ${n:-0}))
done
[ $rc -eq 0 ] || fail "suites failed in the stdlib-sankoch consumer shape"
[ "$suites" -gt 0 ] && [ "$passed" -gt 0 ] || fail "no suite ran ($suites files, $passed assertions)"
echo "consumer-shape: $suites suites, $passed assertions, all pass with the stdlib \"sankoch\" leaf"
