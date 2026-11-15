# BMP channels narrower than 8 bits are widened by bit replication, which is not the nearest 8-bit value — fixed in 1.4.0

**Status:** 🟢 **FIXED in 1.4.0** — sub-8-bit channels round to the nearest level
([ADR 0011](../../adr/0011-bmp-samples-mean-what-the-format-says.md)).
**Filed:** 2026-11-14, by **selah** (Rust → Cyrius port, M0 decode baseline: `selah/docs/development/port-parity.md`
§2 F3).
**Affects:** 16-bpp BMPs (5-5-5, 5-6-5 bitfields) and any bitfield mask narrower than 8 bits.
**Severity:** Low. Off by at most one level, on some levels — but systematically, and in the less accurate direction.

## Summary

A `w`-bit channel value `v` stands for the fraction `v / (2^w − 1)` of full scale, so its exact 8-bit value is
`v · 255 / (2^w − 1)`, and the nearest 8-bit sample is that rounded. chitra widens by bit replication instead (its
comment: "replication is what the hardware mapping actually is … replication matches [ImageMagick], division does
not"). Replication is an *approximation* of the exact value, and a worse one than rounding:

| Width | replication: largest distance from the exact value | rounding: largest distance | levels where they differ |
|---|---|---|---|
| 5 bits | **0.677** | 0.484 | 4 of 32 |
| 6 bits | **0.714** | 0.476 | 10 of 64 |

chitra's own example makes the point: a 6-bit 48 is exactly 194.29; rounding gives 194 (0.29 away), replication 195
(0.71 away). The PNG specification chitra already cites for its wide-field path (§ 13.13) says the same of narrow
ones: the "most accurate" rescale is `floor(v · MAXOUT / MAXIN + 0.5)`, and left-bit-replication is a close
approximation.

That ImageMagick and GPU texture units replicate is a compatibility fact, not an accuracy one: it tells you what
another decoder outputs, not what the file means.

## Reproduction

`selah/tests/golden/fixtures/bmp-16-555-33x17.bmp` and `bmp-16-565-33x17.bmp` (hand-written BI_RGB 5-5-5 and
BI_BITFIELDS 5-6-5, noise). chitra's RGBA differs from the correctly rounded values on 204 and 235 bytes, by 1 each
(`selah/tests/parity.tcyr`'s decode rows; the reference there, Rust's `image` 0.25.10, rounds).

## Proposed fix

`_chitra_bmp_scale_to_8` for `width < 8`: `(v * 510 + max) / (2 * max)` with `max = 2^width − 1` (round half up of
`v · 255 / max`; no exact ties occur for these widths). Widths above 8 are unaffected.

## Consumer-side workaround

Correcting the output in a consumer means re-parsing the header's bitfield masks to invert the replication, which
duplicates chitra. selah doesn't; its 16-bpp BMP rows sit on its known-defect list (ledger L13) until this lands.

## Resolution (1.4.0)

`_chitra_bmp_scale_to_8` for widths 1–7 is now `(v · 510 + max) / (2 · max)`, `max = 2^w − 1`, as
proposed. Widths above 8 keep 1.1.1's rule.

- It differs from replication on exactly the 14 levels this report predicts: 5-bit 3, 7, 24, 28
  (25 / 58 / 197 / 230, replication 24 / 57 / 198 / 231) and 6-bit 11–15 and 48–52; for 1–4 and 7
  bits the two agree on every level.
- `tests/tcyr/bmp.tcyr`: a new cell pins all 14 levels in a 5-6-5 row, and the existing 5-6-5 cell's
  6-bit 48 moves 195 → 194. Checked to fail against 1.3.1 on every level.
- chitra now differs from ImageMagick (which replicates) by 1 on those levels — recorded in ADR 0011
  and CLAUDE.md BMP rule 9, which used to say the opposite. selah's 16-bpp rows (L13) should now match
  Rust's `image` exactly.
