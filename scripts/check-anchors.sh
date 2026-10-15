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
# detectably wrong:
#   PAST-EOF  the cited line does not exist;
#   SUSPECT   the cited line is blank or a lone brace;
#   COMMENT   the cited line is comment-only (1.1.1, cc-10) — a citation of a
#             guard should land on the guard, and a comment line is where a
#             drifted anchor most often lands, because the doc block above a
#             function grows. A comment that itself names the identifier the
#             citation names is accepted: that citation is about the comment;
#   IDENT     the citation names a backticked identifier right next to its
#             anchor — "`fn_name` at `:N`", "`fn_name` (`src/f.cyr:N`)" — and that
#             identifier is nowhere within +/-3 lines of N (of N..M for a range),
#             nor the function whose body N lies in (1.1.1, jpeg-13). Of all the
#             checks this is the one that knows what the line was meant to say.
# It exits 1 when anything is flagged, so a closeout can see the count.
#
# Dated audit reports under docs/audit/ are EXCLUDED: their anchors were correct
# at their date and are a historical record, not a live claim. CHANGELOG.md is
# excluded for the same reason (1.1.1): a released entry is never edited, so an
# anchor in it can only ever be re-flagged, never repaired.
#
#   ./scripts/check-anchors.sh            # full listing
#   ./scripts/check-anchors.sh --suspect  # only the flagged ones

set -uo pipefail
cd "$(dirname "$0")/.."

ONLY_SUSPECT=0
[ "${1:-}" = "--suspect" ] && ONLY_SUSPECT=1

suspect=0
total=0
TAB=$'\t'

while IFS="$TAB" read -r doc rest line last_line ident; do
    file="src/$rest"
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
    if [ -n "$ident" ]; then
        # A range citation (`f.cyr:N`-`M`) may name something anywhere in N..M.
        hi=$line
        [ "$last_line" -le "$line" ] || hi=$last_line
        lo=$((line - 3))
        [ "$lo" -ge 1 ] || lo=1
        # "refused in `fn_name`, `f.cyr:N`" cites a line INSIDE fn_name: the last
        # top-level `fn`/`}` at or above N is that function's own header.
        encl=$(sed -n "1,${line}p" "$file" | grep -E '^(fn [A-Za-z_]|})' | tail -1 \
            | sed -nE 's/^fn ([A-Za-z_][A-Za-z0-9_]*).*/\1/p')
        if [ "$encl" != "$ident" ] \
            && ! sed -n "${lo},$((hi + 3))p" "$file" | grep -qwF -- "$ident"; then
            printf 'IDENT     %s -> %s:%s names `%s`, not within 3 lines | %.50s\n' \
                "$doc" "$file" "$line" "$ident" "$content"
            suspect=$((suspect + 1))
            continue
        fi
    fi
    if printf '%s\n' "$content" | grep -qE '^[[:space:]]*#'; then
        if [ -z "$ident" ] || ! printf '%s\n' "$content" | grep -qwF -- "$ident"; then
            printf 'COMMENT   %s -> %s:%s | %.70s\n' "$doc" "$file" "$line" "$content"
            suspect=$((suspect + 1))
            continue
        fi
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
    # A bare anchor is attributed to the LAST .cyr filename named before it in
    # the same document, which is what the shorthand means. A document that
    # writes a bare anchor before ever naming a file is skipped rather than
    # guessed at. 1.1.1: that is now what the code does — it used to count only
    # filenames that carried a line number, so "two stale `src/png_chunks.cyr`
    # anchors (`:184` -> `:196`)" was checked against png_filter.cyr — and every
    # token is taken in ONE left-to-right pass, so a bare anchor written before a
    # later filename on the same line keeps the earlier file. Each record also
    # carries the identifier the citation names (or nothing), for IDENT above.
    find . -name '*.md' -not -path './lib/*' -not -path './docs/audit/*' -not -path './CHANGELOG.md' -print0 \
    | while IFS= read -r -d '' md; do
        awk -v doc="${md#./}" '
          # The backticked identifier the anchor is written next to, or "".
          # Only separators may sit between them: "`x` at `:N`", "`x`, `src/f.cyr:N`",
          # "`x` (`src/f.cyr:N`)", "`x` ([`src/f.cyr:N`](...))", "**`x`** — `src/f.cyr:N`".
          function ident_before(prefix,    id) {
            if (match(prefix, /`(fn )?[A-Za-z_][A-Za-z0-9_]*(\([^`]*\))?`[*]*[[:space:]]*(,|;|—|–|-)?[[:space:]]*((at|in)[[:space:]]+)?[(\[]*`?(src\/)?$/)) {
              id = substr(prefix, RSTART, RLENGTH)
              sub(/^`(fn )?/, "", id)
              if (match(id, /^[A-Za-z_][A-Za-z0-9_]*/)) { return substr(id, RSTART, RLENGTH) }
            }
            return ""
          }
          # The M of a range written N-M right after an anchor, or N itself.
          function range_end(after, n) {
            if (match(after, /^`?(-|–)`?[0-9]+/)) {
              after = substr(after, RSTART, RLENGTH)
              gsub(/[^0-9]/, "", after)
              return after
            }
            return n
          }
          {
            rest = $0
            off = 0
            # One token at a time, leftmost first: a `file.cyr:N` anchor, a bare
            # `:N` anchor, or a plain `file.cyr` mention (which only moves `last`).
            while (match(rest, /[a-z_]+\.cyr(:[0-9]+)?|`:[0-9]+`/)) {
              ts = RSTART; tl = RLENGTH
              t = substr(rest, ts, tl)
              after = substr(rest, ts + tl)
              before = substr($0, 1, off + ts - 1)
              if (substr(t, 1, 1) == "`") {
                n = substr(t, 3, tl - 3)
                if (last != "") {
                  print doc "\t" last "\t" n "\t" range_end(after, n) "\t" ident_before(before)
                }
              } else if (index(t, ":") > 0) {
                split(t, parts, ":")
                last = parts[1]
                print doc "\t" parts[1] "\t" parts[2] "\t" range_end(after, parts[2]) \
                  "\t" ident_before(before)
              } else {
                last = t
              }
              off = off + ts + tl - 1
              rest = after
            }
          }' "$md"
      done | sort -u)

echo
echo "anchors checked: $total   suspicious: $suspect"
if [ "$suspect" -ne 0 ]; then
    echo "(review the flagged lines above — a citation that lands on a brace, a comment, or"
    echo " away from the identifier it names reads as precision and delivers noise)"
    exit 1
fi
