# The fixed 16.7-megapixel cap refuses screenshots the caller has budgeted for — fixed in 1.4.0

**Status:** 🟢 **FIXED in 1.4.0** — under a budget the budget governs size
([ADR 0015](../../adr/0015-the-decode-context.md)).
**Filed:** 2026-11-14, by **selah** (Rust → Cyrius port, M3: ledger L17).
**Affects:** PNG, JPEG, BMP and GIF images over 16,777,216 pixels: an 8K screenshot (7680 × 4320 = 33.2 MP), three 4K
monitors side by side (11520 × 2160 = 24.9 MP), a tall full-page web capture (1920 × 9000 = 17.3 MP).
**Severity:** Medium for selah: screenshots are its input, and its Rust version opens all of these.

## Summary

`chitra_image_decode_budget` lets the caller say how much it will spend. selah passes 512 MiB, its Rust limit
(`MAX_DECODE_ALLOC`, with `MAX_IMAGE_DIMENSION` 32768 per side), sized "for multi-monitor 8K captures". But the
fixed caps fire first. A 4097 × 4096 PNG is refused with `CHITRA_ERR_DIMENSIONS` although its RGBA8 output (67 MB) is
far inside the budget. The caps came from kii's texture-loader use case (security ceilings, audit 2026-05-22 finding
1), and that use case's sizes are not a screenshot library's.

## Reproduction

`selah/tests/golden/fixtures/png-gray1-4100x4100.png` (2 KB, a 1-bit grayscale PNG, 16.8 MP): Rust's `image`
0.25.10 decodes it within selah's limits; chitra 1.3.1 refuses it. selah's harness lists the row as a known defect
under this issue's file name.

## Proposed fix

Under the budgeted entry point, the caller's `max_bytes` governs: refuse when `w × h × 4 > max_bytes` (as now) or a
side exceeds `CHITRA_MAX_DIM`. Do not also apply `CHITRA_MAX_PIXELS`. Raise `CHITRA_MAX_RAW_BYTES` to cover a working
buffer for the largest budget allowed, or derive it from the budget. The amplification ratios (`CHITRA_MAX_INFLATE_RATIO`
and the others) still bound the work per input byte, so the bomb protection does not depend on the pixel cap.
`chitra_image_decode` without a budget can keep the fixed caps as its defaults.

## Consumer-side workaround

None: the caps are chitra's globals. selah does not write to them. Until this lands, selah refuses images over 16.7 MP,
which its Rust version decodes.

## Resolution (1.4.0)

As proposed: a budgeted decode (`chitra_image_decode_budget`, `_via`, and the CMYK entry) is held to
`max_bytes / 4` pixels and single working buffers up to ~`2 × max_bytes` (PNG's inflated stream is up
to 2 bytes per output byte at depth 16), never below the fixed caps. `CHITRA_MAX_DIM` per side and every
amplification ratio still apply. `chitra_image_decode` and the per-format entries keep the fixed caps.

- `tests/tcyr/budget_via.tcyr` decodes a generated 4100 × 4100 PNG, BMP, JPEG and GIF under a 512 MiB
  budget, refuses each without one, and refuses each over a 64 MiB budget as `CHITRA_ERR_BUDGET` at the
  documented cost. Every cell checked to fail against 1.3.1.
- A side effect fixed with it: a BMP over budget was `CHITRA_ERR_DIMENSIONS`, because the budget probe
  parsed the header with the fixed cap and read the file as unreadable.
- The trade, stated in SECURITY.md: the working set now scales with the budget (~4× the output for an
  Adam7 16-bit PNG), so a budget is a real bound only if it is set to what the caller can spend.
