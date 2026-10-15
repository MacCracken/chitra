#!/usr/bin/env bash
# Verify version consistency across VERSION, cyrius.cyml, CHANGELOG.md, README.md,
# chitra_version() and the packed-version claims in docs/development/state.md.
# `version = "${file:VERSION}"` in the manifest means VERSION is the single
# source of truth — the check below enforces that downstream references
# (CHANGELOG header, README line, the packed literal) agree.
#
# Every leg FAILS CLOSED: a source this script cannot find or cannot parse is a
# FAIL, never a silent skip. A skipped leg that is still named in the OK line is
# the B-14 / gate-11 shape — the gate reports agreement it never checked.
#
# Wired into `make test-all` so drift cannot escape CI.

set -euo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO"

FILE_VERSION=$(tr -d '[:space:]' < VERSION)
fail=0

# Allow the manifest to either inline the version or template it from VERSION.
# The manifest's `version = "${file:VERSION}"` form is valid — so we only
# diff when the manifest has a literal version string.
# B-14 (1.0.3): this arm could not fire, AND its guard passed a manifest with
# no version key at all. The manifest uses the template form
# `version = "${file:VERSION}"`, which the `^version = "[0-9]` test never
# matches — so the "VERSION == cyrius.cyml version" leg of the gate the release
# workflow documents was a no-op, and a manifest that had LOST or reformatted
# its version line was indistinguishable from a correct one. Both halves are
# now decided explicitly, and an unrecognised form is a FAIL rather than a pass.
MANIFEST_LINE=$(grep -E '^version = "' cyrius.cyml | head -1 || true)
if [ -z "$MANIFEST_LINE" ]; then
    echo "  FAIL: cyrius.cyml has no 'version = ' line"
    fail=1
elif echo "$MANIFEST_LINE" | grep -qE '^version = "\$\{file:VERSION\}"$'; then
    : # the template form — VERSION *is* the manifest version; nothing to diff.
elif echo "$MANIFEST_LINE" | grep -qE '^version = "[0-9]'; then
    MANIFEST_VERSION=$(echo "$MANIFEST_LINE" | sed -E 's/version = "([^"]*)"/\1/')
    if [ "$FILE_VERSION" != "$MANIFEST_VERSION" ]; then
        echo "  FAIL: VERSION ($FILE_VERSION) != cyrius.cyml ($MANIFEST_VERSION)"
        fail=1
    fi
else
    echo "  FAIL: cyrius.cyml version is neither a literal nor \${file:VERSION}: $MANIFEST_LINE"
    fail=1
fi

if ! grep -q "^## \[$FILE_VERSION\]" CHANGELOG.md; then
    echo "  FAIL: version $FILE_VERSION missing from CHANGELOG.md"
    fail=1
fi

# chitra_version() packs the release as major*10000 + minor*100 + patch.
# It is a hand-maintained literal in src/png.cyr, so it drifted silently in
# 0.3.1 (VERSION said 0.3.1, the function still returned 300). Gate it here.
#
# VERSION may carry a pre-release suffix: release.yml's tag filter accepts
# x.y.z-{rc,beta,alpha}.N and requires VERSION == tag. chitra_version() packs
# only the x.y.z core, so the suffix is stripped BEFORE the arithmetic --
# feeding "2-rc.1" to $(( )) aborts the whole script under `set -euo pipefail`
# with a raw bash error instead of a clean FAIL line.
EXPECT_PACKED=""
if ! printf '%s' "$FILE_VERSION" | grep -qE '^[0-9]+\.[0-9]+\.[0-9]+(-[0-9A-Za-z.-]+)?$'; then
    echo "  FAIL: VERSION ($FILE_VERSION) is not MAJOR.MINOR.PATCH[-prerelease]"
    fail=1
else
    IFS=. read -r V_MAJ V_MIN V_PAT <<< "${FILE_VERSION%%-*}"
    EXPECT_PACKED=$(( V_MAJ * 10000 + V_MIN * 100 + V_PAT ))
fi
if [ ! -f src/png.cyr ]; then
    echo "  FAIL: src/png.cyr is missing, so chitra_version() cannot be checked"
    fail=1
elif [ -n "$EXPECT_PACKED" ]; then
    ACTUAL_PACKED=$(sed -n '/^fn chitra_version()/,/^}/p' src/png.cyr \
        | grep -oE 'return [0-9]+;' | head -1 | grep -oE '[0-9]+' || echo "")
    if [ -z "$ACTUAL_PACKED" ]; then
        echo "  FAIL: could not read chitra_version() literal from src/png.cyr"
        fail=1
    elif [ "$ACTUAL_PACKED" != "$EXPECT_PACKED" ]; then
        echo "  FAIL: chitra_version() returns $ACTUAL_PACKED, VERSION $FILE_VERSION packs to $EXPECT_PACKED"
        fail=1
    fi
fi

# gate-11 (1.1.1): this leg used to run only `if grep -q "^Version:"`, so a
# README whose line had been restyled (say to `**Version:** 9.9.9`) skipped the
# comparison silently — and the OK line below still listed README.md among the
# sources that agree. No recognisable line is now a FAIL.
if [ ! -f README.md ]; then
    echo "  FAIL: README.md is missing"
    fail=1
elif ! grep -q '^Version: ' README.md; then
    echo "  FAIL: README.md has no '^Version: X.Y.Z' line to check against VERSION"
    fail=1
else
    README_VERSION=$(grep '^Version: ' README.md | head -1 | awk '{print $2}')
    if [ "$README_VERSION" != "$FILE_VERSION" ]; then
        echo "  FAIL: README.md Version ($README_VERSION) != VERSION ($FILE_VERSION)"
        fail=1
    fi
fi

# cc-9 (1.1.1): docs/development/state.md is the live-state snapshot, and it
# quotes the packed version as `chitra_version()` → **N** (and the shorter
# `chitra_version` → N). Those are hand-typed, so they rot exactly the way the
# literal in src/png.cyr did in 0.3.1: at the 1.1.0 cut two of them still said
# 10003. Every such claim must equal what VERSION packs to. A quote of an older
# release has to say so in a form this does not read as a claim — not → N.
STATE_DOC=docs/development/state.md
if [ ! -f "$STATE_DOC" ]; then
    echo "  FAIL: $STATE_DOC is missing"
    fail=1
elif [ -n "$EXPECT_PACKED" ]; then
    # One line per claim (grep -o), each prefixed with its line number (-n).
    STATE_CLAIMS=$(grep -noE \
        'chitra_version(\(\))?`?[[:space:]]*(→|->)[[:space:]]*[*`]*[0-9]+' \
        "$STATE_DOC" || true)
    while IFS= read -r claim; do
        [ -n "$claim" ] || continue
        claim_val=${claim##*[!0-9]}
        if [ "$claim_val" != "$EXPECT_PACKED" ]; then
            echo "  FAIL: $STATE_DOC:${claim%%:*} says chitra_version() → $claim_val," \
                "VERSION $FILE_VERSION packs to $EXPECT_PACKED"
            fail=1
        fi
    done <<< "$STATE_CLAIMS"
fi

if [ $fail -eq 0 ]; then
    echo "  OK: version $FILE_VERSION consistent across VERSION, cyrius.cyml, CHANGELOG.md," \
        "README.md, chitra_version(), $STATE_DOC"
fi

exit $fail
