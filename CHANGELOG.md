# Changelog

All notable changes to chitra are documented here.

The format is based on [Keep a Changelog](https://keepachangelog.com/),
and this project adheres to [Semantic Versioning](https://semver.org/).

## [0.2.1] — 2026-06-26

**Sub-byte bit depths 1/2/4 + Adam7 interlace** — completes the PNG
bit-depth/interlace matrix (a direct continuation of the 0.2.0 depth-16
work). chitra now decodes every depth × color-type × interlace combination
the PNG spec permits. The depth-8/16 non-interlaced path is unchanged
(byte-for-byte).

### Added
- **Sub-byte depths 1/2/4** for grayscale (ct0) and palette (ct3) — the
  only color types the spec permits below depth 8 (§ 11.2.2 Table 11.1).
  Samples are MSB-first packed with rows padded to a byte; grayscale scales
  to 8-bit (×255/85/17), palette indexes the PLTE. The IHDR gate now
  enforces the full validity table; ct2/4/6 at a sub-byte depth still
  reject as `CHITRA_ERR_BIT_DEPTH`.
- **Adam7 interlace** (§ 8) — the 7-pass reduced images are each filtered
  independently and deinterlaced into the same dense, byte-padded buffer
  the non-interlaced path produces, so the color pass is interlace-agnostic.
  Works for every color type/depth, including the sub-byte bit-scatter case.
- New unfilter stride is `ceil(channels*depth/8)` (≥1), and row size is
  `ceil(width*channels*depth/8)` — correct for sub-byte packing.
- Test suites split out: `tests/tcyr/subbyte.tcyr` (143 assertions —
  gray/palette at 1/2/4, multi-row padding, ct2-depth4 reject) and
  `tests/tcyr/interlace.tcyr` (35 — Adam7 cross-checked against the trusted
  non-interlaced decode for 7 color/depth/odd-dimension cases). Fixtures
  are ImageMagick-generated (independent reference codec) or python-packed
  and cross-checked against ImageMagick. Also folded in the deferred
  depth-16 ct4/ct6/ct0-tRNS fixtures from 0.2.0. Suite: **523 assertions**.

### Changed
- `chitra_version()` → 201. `ChitraPngRaw` widened 96→104B (internal —
  adds an interlace slot; not the public `ChitraImage`).
- `dist/chitra.cyr` regenerated.

### Hardened (adversarial-review follow-ups, all low-severity)
- IHDR **compression-method (byte 10) + filter-method (byte 11)** are now
  validated — anything other than method 0 (the only spec-legal value)
  rejects as `CHITRA_ERR_UNSUPPORTED` instead of silently mis-decoding.
- The color pass re-asserts the dimension caps (`MAX_DIM`/`MAX_PIXELS`)
  before its width×height multiplies — defense-in-depth so it is overflow-
  safe even on a hand-built raw (unreachable via `chitra_png_decode`, which
  caps in `parse_raw`).

### Removed
- The 0.1.0/0.2.0 `interlace`/`depth1` *rejection* tests (those inputs are
  now decoded, not rejected).

## [0.2.0] — 2026-06-26

**Bit depth 16 + kii guard-parity backport.** This is the release that
makes chitra a strict superset of kii's native PNG decoder, so kii can
adopt chitra (the "PNG re-fold") with zero capability loss. No change to
the depth-8 path — every existing decode is byte-for-byte identical.

### Added
- **16-bit decode** for color types 0/2/4/6. Each big-endian 16-bit
  sample truncates to its **high byte** on the way to canonical RGBA8 —
  the same lossy 16→8 reduction kii's terminal path used, so rendered
  output is unchanged. The IHDR gate now accepts `bit_depth ∈ {8,16}`;
  `bps = bit_depth/8` threads through the size math, the five unfilter
  predictors (`bpp = channels*bps`), and the color pass.
- `chitra_image_seen_iend(img)` — 1 if an IEND chunk closed the stream,
  0 for a tolerated clean IEND-less end (spec § 5.3). Lets a consumer
  warn while still using the pixels. Backed by a new `RAW_SEEN_IEND`
  slot on `ChitraPngRaw`.
- `chitra_image_source_color_type(img)` — the pre-normalization PNG
  color_type (0/2/3/4/6), so a consumer can report the original format
  even though pixels are normalized to RGBA8.
- `CHITRA_ERR_NO_IDAT` (12) — a structurally valid PNG with zero IDAT
  now reports this distinct code instead of collapsing into
  `CHITRA_ERR_DIMENSIONS`.
- Test fixtures + assertions for all of the above (depth-16 RGB None and
  Sub/Up-filtered, depth-16 grayscale, ct3+depth16 rejection, depth-1
  rejection, NO_IDAT, non-zero IEND, seen_iend both directions, source
  color_type). Suite: error 17→20, png 232→302.

### Changed / Hardened
- **IEND-must-be-zero-length** guard: an IEND chunk with a non-zero
  length is now rejected as `CHITRA_ERR_BAD_CHUNK` (spec § 11.2.5) —
  backported from kii (its M8 chunk-ordering FSM).
- `ChitraImage` widened 32B → 48B (seen_iend at +32, source color_type
  at +40). **ABI-additive**: width/height/pixels/channels keep their
  0.1.x offsets, so mabda's accessors are unaffected.
- `chitra_version()` re-based to `major*10000 + minor*100 + patch`
  (0.2.0 → 200); the prior comment's arithmetic was self-inconsistent.
- `dist/chitra.cyr` regenerated via `cyrius distlib`.

### Deferred (tracked)
- **0.2.1** — sub-byte depths 1/2/4 and Adam7 interlace (the remainder
  of the bit-depth matrix; a direct continuation of this depth-16 work).
  Both still reject loud today.
- **0.3+** — JPEG.

## [0.1.1] — 2026-06-26

Toolchain + dependency refresh. **No functional change to the decoder** —
the PNG → canonical RGBA8 path, security guards, and public API
(`chitra_png_decode` / `chitra_png_decode_rgba8`) are byte-for-byte the
same as 0.1.0; only the toolchain pin and vendored stdlib snapshot move.

### Changed
- Toolchain pin bumped `cyrius = "6.2.23"` → `"6.2.44"` in `cyrius.cyml`.
- `lib/` re-vendored from the 6.2.44 stdlib snapshot via `cyrius deps`.
  The snapshot is byte-identical to 6.2.23's for chitra's dep set, so
  `sankoch` stays at **2.4.4** (zlib inflate + CRC32) and `thread` is
  unchanged.
- `dist/chitra.cyr` regenerated via `cyrius distlib` (bundle header now
  reads Version 0.1.1).
- `VERSION`, `README.md`, and `CHANGELOG.md` synced to 0.1.1.
- All gates green: smoke link-check, the CPU test suites under
  `tests/tcyr/`, and `version-check`.

## [0.1.0] — 2026-06-19

First release. **chitra decodes PNG to canonical RGBA8** — a pure-Cyrius
CPU decoder with no GPU, no C shim, and no external binaries. PNG color
types 0/2/3/4/6 at bit depth 8 (grayscale, RGB, palette, grayscale+alpha,
RGBA) normalize to canonical RGBA8 via stdlib `sankoch` IDAT inflate
(RFC 1950/1951), the five unfilter predictors (None/Sub/Up/Average/Paeth),
and tRNS-driven alpha synthesis. The decoder is **security-hardened** —
every byte access is bounds-checked against the input span, CRC-32 is
verified per chunk, and the kii decompression-bomb / lying-IHDR /
dimension-ratio caps reject hostile inputs loud — and **fuzz-corpus-tested**
(the kii core it forks from is fuzz-hardened; chitra's adversarial test
fixtures cover bad-signature / truncated / CRC-mismatch / interlaced /
bomb / palette-index-OOB / out-of-bounds-tRNS rejections).

Consumed by **mabda** for `gpu_texture_load_png` (a plain `[deps.chitra]`
dist dep; `ChitraErr` is layout-compatible with mabda's `GpuErr`).

**Deferred to a later release (tracked, not silently dropped):**
- **0.2** — PNG bit depths 1 / 2 / 4 / 16, and Adam7 interlace
  (0.1.0 is single-pass, depth-8 only; all reject loud today).
- **0.3+** — **JPEG** (Huffman + IDCT + chroma upsample).

### Added
- Initial package scaffold (mabda v3.3 arc, bite **AL.P0a**). A minimal,
  green, link-checkable pure-Cyrius skeleton — **not** the PNG decoder
  yet (that lands in AL.P0b–AL.P0e):
  - `cyrius.cyml` — `name = "chitra"`, `cyrius = "6.2.23"`, GPL-3.0-only;
    `[deps].stdlib` carries the base set plus `sankoch` (zlib inflate +
    CRC32) and `thread` (sankoch's mutex pair); `[lib].modules` lists the
    include-order src chain.
  - `src/lib.cyr` — the single stdlib + domain include chain.
  - `src/error.cyr` — `ChitraErr` model: `CHITRA_OK` / `_ERR_SIGNATURE` /
    `_ERR_TRUNCATED` / `_ERR_BAD_CHUNK` / `_ERR_UNSUPPORTED` /
    `_ERR_INFLATE` / `_ERR_OOM` / `_ERR_OTHER` constants, a 16-byte
    `GpuErr`-compatible record (`chitra_err_new` / `chitra_err` /
    `chitra_err_code` / `chitra_err_detail`), and `chitra_err_name`.
  - `src/png.cyr` — stub: the planned PNG → RGBA8 API documented in the
    header, plus a live `chitra_version()` (returns 100 = 0.1.0 packed)
    so the module is non-empty and links.
  - `programs/smoke.cyr` — link-check entry proving the include chain
    (stdlib + sankoch + thread + domain modules) parses and links.
  - `tests/tcyr/error.tcyr` — CPU suite covering the error codes,
    `chitra_err_*` accessors, `chitra_err_name` round-trips, and
    `chitra_version()`.
  - `Makefile`, `scripts/version-check.sh`,
    `scripts/count-test-assertions.sh`, `.gitignore`, `README.md` —
    adapted from mabda's conventions.
- PNG byte-buffer framing + IDAT inflate + unfilter + security layer
  (mabda v3.3 arc, bite **AL.P0b**) — forked from kii's proven
  `png.cyr` core, re-shaped onto a byte-buffer cursor. Turns PNG bytes
  into inflated, unfiltered raw scanlines + the parsed IHDR (the
  AL.P0d color-pass handoff). **Not** the canonical-RGBA8 pass or the
  public `chitra_png_decode` yet (AL.P0d / AL.P0e):
  - `src/png_chunks.cyr` — a bounds-checked `(src, len)` cursor (every
    u8/u32-BE/skip validated against `len` before access), the 8-byte
    signature check, chunk-type predicates (IHDR/IDAT/IEND/PLTE/tRNS),
    color-type→channels, the kii security ceilings, and the
    `ChitraPngRaw` (96-byte) handoff struct + accessors.
  - `src/png_filter.cyr` — the five PNG unfilter predictors
    (None/Sub/Up/Average/Paeth) and `chitra_png_parse_raw`: a two-pass
    chunk walk (CRC-32 every chunk via sankoch, parse IHDR, capture
    PLTE/tRNS spans, concat IDAT, inflate with the bomb caps, unfilter
    into the scanline buffer). Every failure path returns a `ChitraErr`,
    never an OOB read.
  - `src/error.cyr` — new codes `CHITRA_ERR_CRC` / `_INTERLACE` /
    `_BIT_DEPTH` / `_DIMENSIONS` / `_FILTER` + names.
  - Security guards ported from kii: lying-IHDR / dimension caps,
    decompression-bomb ratio cap, CRC-mismatch + truncated-stream
    rejection. Adam7 interlace and bit depths != 8 reject loud
    (tracked: chitra 0.2 / AL.P0d).
  - `tests/tcyr/png.tcyr` — 95 CPU assertions: cursor bounds, signature,
    Paeth + all five unfilter predictors, three embedded-byte-array
    fixtures (rgba8 2x2 None, rgb8 2x2 Sub+Up, rgba8 1x1 Paeth — raw
    bytes asserted exactly), and five adversarial rejections
    (bad-signature, truncated, CRC-mismatch, interlaced, bomb).
- Canonical-RGBA8 color-normalization pass + the public PNG decoder
  (mabda v3.3 arc, bite **AL.P0d**) — completes chitra's PNG → RGBA8
  path for bit depth 8. Consumes a `ChitraPngRaw` and emits an owned
  RGBA8 `ChitraImage`:
  - `src/png_color.cyr` — `chitra_png_color_to_rgba8(raw, src, len,
    err_out)`: the genuinely new code over kii (kii emits native
    channels / palette indices for the terminal path; chitra normalizes
    to canonical RGBA8 + synthesizes alpha from tRNS). Handles all five
    color types at depth 8 — grayscale(0) → (g,g,g,255), RGB(2) →
    (r,g,b,255), palette(3) → PLTE RGB + per-entry tRNS alpha,
    grey+alpha(4) → (g,g,g,a), RGBA(6) passthrough — with tRNS keying
    for types 0/2 (matching gray / RGB → alpha 0). PLTE/tRNS are read
    from the original `src` via the (offset, length) spans the parse
    driver captured (no struct widening; documented in the module
    header), re-validated against `(src, len)` defensively.
  - `src/png.cyr` — replaces the stub with the public API:
    `chitra_png_decode(src, len, err_out)` → `ChitraImage*` (parse_raw +
    the color pass), `chitra_png_decode_rgba8(src, len, w_out, h_out)`
    convenience, `chitra_image_free` (documented bump-allocator no-op),
    plus the 32-byte `ChitraImage` struct (`width` / `height` / `pixels`
    (owned RGBA8 w*h*4) / `channels` = 4) + accessors. `chitra_version`
    retained.
  - `src/lib.cyr` + `cyrius.cyml` `[lib].modules` — wire `png_color.cyr`
    between `png_filter.cyr` and `png.cyr`.
  - New reject paths: palette index ≥ PLTE entry count → `BAD_CHUNK`;
    color_type 3 with no/short PLTE → `BAD_CHUNK`; tRNS span out of
    `(src, len)` bounds or wrong length for the color type → `BAD_CHUNK`.
    The AL.P0b rejects (interlace / bit-depth / bombs / CRC / truncation)
    stay intact.
  - `tests/tcyr/png.tcyr` — grows to 232 CPU assertions: one
    embedded-byte-array fixture per color type 0/2/3/4/6 at depth 8
    decoded end-to-end with pixel-exact RGBA8 (ground truth from a
    reference re-decode of the same bytes), a palette+tRNS fixture
    (per-entry alpha), grayscale+tRNS and RGB+tRNS keyed-color fixtures
    (keyed pixel → alpha 0), the `_rgba8` convenience wrapper, and a
    palette-index-out-of-range adversarial reject.

### Notes
- The four `### Added` blocks above are the per-bite (AL.P0a → AL.P0d)
  build provenance; the summary at the top of this entry is the shipped
  0.1.0 surface. Deferred work (bit depths 1/2/4/16 + Adam7 → 0.2; JPEG
  → 0.3+) is listed under the summary.
