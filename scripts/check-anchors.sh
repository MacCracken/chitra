#!/usr/bin/env bash
# check-anchors.sh — report every `src/<file>.cyr:N` citation in the docs
# alongside the line it currently points at.
#
# WHY THIS EXISTS: the docs cite code by line number, and line numbers move
# whenever a guard is added above them. That rot has already had to be repaired
# twice by hand (png_chunks.cyr anchors in 0.3.3, png_filter.cyr anchors in
# 0.5.1) — both times only because someone happened to look. A citation that
# silently points at a closing brace is worse than no citation: it reads as
# precision and delivers noise.
#
# This does NOT gate CI, because it cannot know what a line was MEANT to say —
# it prints the evidence and a human decides. It flags the cases that are
# unambiguously wrong: past end-of-file, or landing on a blank/brace-only line.
#
# Dated audit reports under docs/audit/ are EXCLUDED: their anchors were correct
# at their date and are a historical record, not a live claim.
#
#   ./scripts/check-anchors.sh            # full listing
#   ./scripts/check-anchors.sh --suspect  # only the suspicious ones

set -uo pipefail
cd "$(dirname "$0")/.."

ONLY_SUSPECT=0
[ "${1:-}" = "--suspect" ] && ONLY_SUSPECT=1

suspect=0
total=0

while IFS= read -r hit; do
    doc="${hit%%:*}"
    rest="${hit#*:}"
    file="src/${rest%%:*}"
    line="${rest##*:}"
    [ -f "$file" ] || continue
    total=$((total + 1))
    nlines=$(wc -l < "$file")
    if [ "$line" -gt "$nlines" ]; then
        echo "PAST-EOF  $doc -> $file:$line (file has $nlines lines)"
        suspect=$((suspect + 1))
        continue
    fi
    content=$(sed -n "${line}p" "$file")
    trimmed=$(echo "$content" | tr -d '[:space:]')
    if [ -z "$trimmed" ] || [ "$trimmed" = "}" ] || [ "$trimmed" = "{" ]; then
        echo "SUSPECT   $doc -> $file:$line | $content"
        suspect=$((suspect + 1))
        continue
    fi
    [ "$ONLY_SUSPECT" -eq 1 ] || printf 'ok        %s -> %s:%s | %.70s\n' "$doc" "$file" "$line" "$content"
done < <(grep -rnoE "[a-z_]+\.cyr:[0-9]+" --include="*.md" . \
           | grep -v "^./lib/" | grep -v "^./docs/audit/" \
           | sed -E 's/^\.\///' | awk -F: '{print $1":"$3":"$4}' | sort -u)

echo
echo "anchors checked: $total   suspicious: $suspect"
[ "$suspect" -eq 0 ] || echo "(review the SUSPECT/PAST-EOF lines above — a citation that lands on a brace reads as precision and delivers noise)"
