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
done < <(
    # B-13 (1.0.3) — ALSO RESOLVE THE BARE `:NNN` CONTINUATION ANCHORS.
    # The original extractor matched only citations that REPEAT the filename,
    # so the shorthand the ADRs use most — "`src/png_filter.cyr:39`) -> `:665`"
    # — was invisible to it. Measured at the 1.0.3 sweep: it inspected 66 of
    # ~126 live line-number claims and still printed "suspicious: 0", while
    # anchors it could not see were landing on a bare brace — exactly the case
    # this script advertises catching. A checker that reports clean over half
    # the corpus is worse than one that reports its own coverage.
    #
    # A bare anchor is attributed to the LAST .cyr filename named at or before
    # it in the same document, which is what the shorthand means. A document
    # that writes a bare anchor before ever naming a file is skipped rather
    # than guessed at.
    find . -name '*.md' -not -path './lib/*' -not -path './docs/audit/*' -print0 \
    | while IFS= read -r -d '' md; do
        awk -v doc="${md#./}" '{
            line = $0
            while (match(line, /[a-z_]+\.cyr:[0-9]+/)) {
              a = substr(line, RSTART, RLENGTH)
              split(a, parts, ":")
              last = parts[1]
              print doc ":" parts[1] ":" parts[2]
              line = substr(line, RSTART + RLENGTH)
            }
            rest = $0
            while (match(rest, /`:[0-9]+`/)) {
              b = substr(rest, RSTART + 2, RLENGTH - 3)
              if (last != "") { print doc ":" last ":" b }
              rest = substr(rest, RSTART + RLENGTH)
            }
          }' "$md"
      done | sort -u)

echo
echo "anchors checked: $total   suspicious: $suspect"
[ "$suspect" -eq 0 ] || echo "(review the SUSPECT/PAST-EOF lines above — a citation that lands on a brace reads as precision and delivers noise)"
