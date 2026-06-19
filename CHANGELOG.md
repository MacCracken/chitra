# Changelog

All notable changes to chitra are documented here.

The format is based on [Keep a Changelog](https://keepachangelog.com/),
and this project adheres to [Semantic Versioning](https://semver.org/).

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
