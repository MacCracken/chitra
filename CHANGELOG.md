# Changelog

All notable changes to chitra are documented here.

The format is based on [Keep a Changelog](https://keepachangelog.com/),
and this project adheres to [Semantic Versioning](https://semver.org/).

## [0.3.2] - 2026-08-23

Toolchain catch-up release. No decode-path behaviour changes — the PNG and
JPEG matrices are byte-for-byte what 0.3.1 shipped; **728 assertions across
5 suites, 0 failures**.

### Changed

- cyrius pin 6.5.27 -> **6.5.35**. `lib/` re-vendored from the 6.5.35 stdlib
  snapshot (108 `.cyr` files), which clears the two drift warnings the 0.3.1
  build emitted: the shadow-lib mismatch (`patra` 1.13.0 vendored vs 1.13.8
  pinned) and the `pins 6.5.27 but cycc is 6.5.35` toolchain-drift note.
  `build/chitra_smoke` unchanged at 551,320 bytes — verified byte-identical
  when compiled by both the 6.5.27 and the 6.5.35 `cycc` against this tree.
  (The 555,416 figure the 0.3.1 entry records does not reproduce here; it
  was measured against that cut's `lib/` vendoring, not this one.)
  `dist/chitra.cyr` 124,630 -> 124,651 bytes (2,925 lines).
- Formatter reflow for 6.5.35's `cyrfmt`, which indents wrapped continuation
  lines +2 relative to the statement: `src/png_chunks.cyr`,
  `src/png_filter.cyr`, `tests/tcyr/error.tcyr`. **Whitespace only** — no
  token changed, and the suite is green before and after.

### Fixed

- `chitra_version()` returned **300** on 0.3.1 — the release bumped
  `VERSION`, `cyrius.cyml`, `CHANGELOG.md`, and `README.md` but left the
  hand-maintained packed literal in [`src/png.cyr`](src/png.cyr) at its
  0.3.0 value, so every consumer probing the version saw a release-behind
  number. Now returns **302**, and `tests/tcyr/error.tcyr` asserts it.

### Added

- `scripts/version-check.sh` (= `make version-check`) now gates
  `chitra_version()` against `VERSION`, packing `major*10000 + minor*100 +
  patch` and diffing it against the literal parsed out of `src/png.cyr`.
  This is the check that would have caught the 0.3.1 drift above; the OK
  line now names all five sources of truth. The check is pre-release-safe:
  it strips a `-rc.N` / `-beta.N` / `-alpha.N` suffix before packing (the
  release workflow's tag filter accepts those and requires `VERSION == tag`),
  and a malformed `VERSION` yields a clean `FAIL:` line rather than aborting
  the script under `set -euo pipefail`.

### Documentation

- Doc-drift sweep against the current tree. `docs/development/state.md`
  refreshed from measured numbers (it had been stuck at 0.3.0 / pin 6.2.44).
  Corrected: the `chitra_image_decode` router description, which claimed
  unrecognized bytes fall through to `chitra_png_decode` — the router
  actually tries PNG magic, then JPEG SOI, then rejects with
  `CHITRA_ERR_SIGNATURE` ([`jpeg.cyr:424`](src/jpeg.cyr)); the
  `getting-started` error-code table, which stopped at 12 and omitted every
  JPEG code 13-23, and named the success constant `CHITRA_ERR_OK` rather
  than `CHITRA_OK`; the `make test` suite list, which omitted `jpeg.tcyr`
  (203) so its counts summed to 525 rather than 728; the `[deps.chitra]`
  example, pinned at 0.3.0; two stale `src/png_chunks.cyr` line anchors in
  [`docs/adr/0002`](docs/adr/0002-security-model.md) and `SECURITY.md`
  (`:184` -> `:196`, `:210` -> `:222`); the architecture module-map include
  order, which predated the four JPEG modules; and CLAUDE.md's
  decompression-bomb checklist item, which conflated the IDAT *input*
  accumulator cap (-> `CHITRA_ERR_OOM`) with the IHDR-derived *output* size
  caps (-> `CHITRA_ERR_DIMENSIONS`).
- Stale `src/error.cyr` enum comments corrected — a drift item tracked open
  since 0.2.1. `CHITRA_ERR_INTERLACE` said "single-pass only" and
  `CHITRA_ERR_BIT_DEPTH` said "bit_depth != 8"; both are validity
  rejections, not capability limits (Adam7 and every spec-legal depth
  decode). Their `chitra_err_name` strings still read as capability limits;
  rewording them changes public output, so that is deferred to the v1.0 API
  freeze.

## [0.3.1] - 2026-08-17

### Changed

- cyrius pin 6.2.44 -> **6.5.27**, matching the rest of the AGNOS desktop stack. Build 370,776 -> 555,416 bytes; 5/5 green.

## [0.3.0] — 2026-06-27

**JFIF baseline JPEG decode.** chitra gains a full baseline JPEG decoder —
grayscale + YCbCr, 4:4:4 / 4:2:2 / 4:2:0 chroma subsampling, and restart
markers — normalizing to the same canonical RGBA8 surface PNG produces, plus a
format-sniffing `chitra_image_decode` entry. Decoder output is verified
**byte-identical to ImageMagick** on a real baseline JPEG with AC content.
Non-baseline modes (progressive, arithmetic, 12-bit, hierarchical/lossless,
CMYK) are cleanly rejected with distinct error codes. See
[`docs/proposals/jpeg-baseline-decoder.md`](docs/proposals/jpeg-baseline-decoder.md)
and [`docs/adr/0004-jpeg-decode-model.md`](docs/adr/0004-jpeg-decode-model.md).

### Added
- **JPEG marker framing (bite 1)** — `src/jpeg_markers.cyr`:
  `chitra_jpeg_check_signature` (SOI), `chitra_jpeg_scan_markers` (SOI →
  segment walk → SOS, parsing the SOF0 frame header), and a `_cur_u16_be`
  cursor helper. Non-baseline modes (progressive, arithmetic, 12-bit,
  hierarchical/lossless, 4-component CMYK) are rejected with distinct error
  codes — the defer-don't-half-implement posture. 11 new `CHITRA_ERR_JPEG_*`
  codes (13–23). `tests/tcyr/jpeg.tcyr`: +28 assertions (suite total 553).
- **JPEG SOF0 components + DQT (bite 2)** — the marker scan now parses the SOF0
  per-component sampling factors (Hi/Vi, quant-table selector, max H/V) and DQT
  quantization tables into `ChitraJpegFrame`, with the baseline security guards:
  sampling factors clamped to 1..4 (rejecting 0 — the CVE-2018-11212
  divide-by-zero), duplicate component ids rejected, and ΣHi·Vi ≤ 10 enforced
  before any MCU geometry is derived. `jpeg.tcyr`: +27 assertions (suite total 580).
- **JPEG Huffman tables (bite 3)** — new `src/jpeg_huffman.cyr`: the canonical
  Huffman decode-table representation (`mincode`/`maxcode`/`valptr`/`huffval`)
  and its construction from a DHT's BITS + HUFFVAL (ITU-T T.81 Annex C + F),
  with over-subscription rejection. `jpeg_markers.cyr` parses DHT segments
  (`Tc ∈ {0,1}`, `Th < 4`, Σcounts ≤ 256, in-bounds) and builds up to 4 DC + 4
  AC tables into frame storage. `jpeg.tcyr`: +24 assertions verifying the built
  table against the standard Annex K.3.3 DC-luminance codes (suite total 604).
- **JPEG entropy decode (bite 4)** — `jpeg_huffman.cyr` gains the entropy
  bit-reader (MSB-first, `0xFF00` byte-unstuffing, marker detection with
  zero-padding past a marker), the Annex F `DECODE` procedure, `RECEIVE`/`EXTEND`
  sign recovery, and `_jpeg_decode_block` decoding one 8×8 block's 64 zig-zag
  coefficients (DC differential + AC run/size with ZRL and EOB). `jpeg.tcyr`:
  +27 assertions including a full block decoded from a hand-encoded stream
  (suite total 631).
- **JPEG dequant + IDCT (bite 5)** — new `src/jpeg_idct.cyr`: the zig-zag→
  natural index map, dequantization, the committed libjpeg `jpeg_idct_islow`
  integer fixed-point 8×8 inverse DCT (ADR 0004), and the `+128` level-shift
  with `[0,255]` clamp. DESCALE uses signed round-to-nearest division (Cyrius
  `>>` is logical, not arithmetic). `jpeg.tcyr`: +18 assertions — zig-zag table,
  DC-only known-answers (`round(D/8)+128` with high/low clamps), and dequant
  scaling (suite total 649).
- **JPEG grayscale decode, end-to-end (bite 6a)** — new `src/jpeg.cyr` with the
  public `chitra_jpeg_decode(src, len, err_out) -> ChitraImage`. Parses the SOS
  scan header (component Td/Ta selectors; baseline Ss=0/Se=63/Ah=Al=0), runs the
  MCU loop for a single-component grayscale image (1 data unit per MCU), places
  IDCT'd 8×8 blocks into the component plane, crops to the image dimensions, and
  emits canonical RGBA8 (R=G=B=gray, A=255). `source_color_type` carries the
  JPEG sentinel `0x100 | num_components`. `jpeg.tcyr`: +17 assertions decoding a
  complete hand-built 8×8 (and cropped 5×5) grayscale JPEG to pixels (suite 666).
- **JPEG YCbCr 4:4:4 decode (bite 6b)** — `chitra_jpeg_decode` now handles
  3-component baseline JPEG with no chroma subsampling (all Hi=Vi=1): the MCU
  loop decodes Y/Cb/Cr planes (one data unit each per MCU, independent DC
  predictors), then a fixed-point full-range BT.601 YCbCr→RGB color pass
  (libjpeg jdcolor constants) emits RGBA8. `source_color_type` = `0x103`.
  `jpeg.tcyr`: +18 assertions — direct YCbCr→RGB known-answers (incl. clamp) and
  a complete hand-built 8×8 4:4:4 JPEG decoded to pixels (suite total 684).
- **JPEG chroma subsampling + restart markers (bite 7)** — the grayscale and
  4:4:4 paths are unified into one subsampling-aware `_jpeg_decode_scan` handling
  arbitrary per-component Hi/Vi: the MCU is max_h×max_v data units, each
  component decodes Hi×Vi blocks into its own subsampled plane, then box-upsamples
  to full resolution (so 4:2:2 / 4:2:0 / general sampling all work). DRI is parsed
  and RST0–7 restart intervals reset the DC predictors and byte-align the entropy
  stream (`_jpeg_br_restart`). `jpeg.tcyr`: +16 assertions — a 4:2:0 8×8 decode
  and a 16×8 restart-interval decode across two MCUs (suite total 700).
- **JPEG public API + format dispatch + real-image e2e (bite 8)** — public
  `chitra_jpeg_decode_rgba8` convenience wrapper and `chitra_image_decode`
  (signature-sniffing PNG-vs-JPEG router). `chitra_version()` → 300, `VERSION` →
  0.3.0, manifest description updated, and the JPEG `src_ctype` sentinel
  documented in `png.cyr`. `jpeg.tcyr`: +24 assertions including a real
  ImageMagick-encoded 16×16 baseline gradient decoded **byte-identical** to the
  reference (validates the real Annex K Huffman tables + AC entropy), the rgba8
  wrapper, and dispatch routing (suite total 724).
- **Hardening (bite 9)** — DC magnitude category bounded to 0..11 and AC size
  to 0..10 (8-bit baseline maxima); duplicate SOS component selector (`Cs`)
  rejected; source doc-drift comments corrected. `jpeg.tcyr`: +4 assertions
  (suite total 728).

### Security
- **First JPEG-decoder security audit**
  ([`docs/audit/2026-06-27-audit.md`](docs/audit/2026-06-27-audit.md)) —
  finder → adversarial-verify per module against the libjpeg / stb_image /
  jpeg-decoder CVE corpus. Verdict: the baseline decoder is **memory-safe**
  (no reachable out-of-bounds read/write, integer overflow, or
  divide-by-zero); all 81 guards confirmed present; the CVE-class checklist is
  fully covered (10 PRESENT, 2 N/A via baseline rejection). Two LOW
  spec-laxity items were fixed in this cut (see Hardening above); truncation
  detection and in-tree fuzz / benchmark harnesses are documented and deferred
  to v1.0.

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
  depth-16 ct4/ct6/ct0-tRNS fixtures from 0.2.0. Suite: **525 assertions**.

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
