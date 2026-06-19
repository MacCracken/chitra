# Changelog

All notable changes to chitra are documented here.

The format is based on [Keep a Changelog](https://keepachangelog.com/),
and this project adheres to [Semantic Versioning](https://semver.org/).

## [0.1.0] — 2026-06-19

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

### Planned
- **PNG → canonical RGBA8** (color types 0/2/3/4/6 @ bit depth 8, sankoch
  IDAT inflate, the five unfilter predictors, tRNS, kii security guards;
  no Adam7) — forked from kii's proven `png.cyr`.
- **Staged (tracked):** bit depths 1/2/4/16 + Adam7 interlace → 0.2;
  **JPEG** → 0.3+.
