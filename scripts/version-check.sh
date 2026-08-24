#!/usr/bin/env bash
# Verify version consistency across VERSION, cyrius.cyml, CHANGELOG.md, README.md.
# `version = "${file:VERSION}"` in the manifest means VERSION is the single
# source of truth — the check below enforces that downstream references
# (CHANGELOG header, README badge) agree.
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
if grep -qE '^version = "[0-9]' cyrius.cyml; then
    MANIFEST_VERSION=$(grep -E '^version = "' cyrius.cyml | head -1 | sed -E 's/version = "([^"]*)"/\1/')
    if [ "$FILE_VERSION" != "$MANIFEST_VERSION" ]; then
        echo "  FAIL: VERSION ($FILE_VERSION) != cyrius.cyml ($MANIFEST_VERSION)"
        fail=1
    fi
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
if [ -f src/png.cyr ]; then
    if ! printf '%s' "$FILE_VERSION" | grep -qE '^[0-9]+\.[0-9]+\.[0-9]+(-[0-9A-Za-z.-]+)?$'; then
        echo "  FAIL: VERSION ($FILE_VERSION) is not MAJOR.MINOR.PATCH[-prerelease]"
        fail=1
    else
        IFS=. read -r V_MAJ V_MIN V_PAT <<< "${FILE_VERSION%%-*}"
        EXPECT_PACKED=$(( V_MAJ * 10000 + V_MIN * 100 + V_PAT ))
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
fi

if [ -f README.md ] && grep -q "^Version:" README.md; then
    README_VERSION=$(grep '^Version:' README.md | head -1 | awk '{print $2}')
    if [ "$README_VERSION" != "$FILE_VERSION" ]; then
        echo "  FAIL: README.md Version ($README_VERSION) != VERSION ($FILE_VERSION)"
        fail=1
    fi
fi

if [ $fail -eq 0 ]; then
    echo "  OK: version $FILE_VERSION consistent across VERSION, cyrius.cyml, CHANGELOG.md, README.md, chitra_version()"
fi

exit $fail
