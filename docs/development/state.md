# chitra — Current State

> **Last refresh**: 2026-06-27 | **Refresh cadence**: every release.
> [`CLAUDE.md`](../../CLAUDE.md) is preferences / process / architecture
> (durable); this file is **state** (volatile) — it is the home for the
> version, sizes, and counts `CLAUDE.md` must not inline.

## Version

**0.3.0** — cut 2026-06-27. **JFIF baseline JPEG decode.** chitra gains a
full baseline (SOF0) JPEG decoder alongside the feature-complete PNG path —
grayscale + YCbCr, 4:4:4 / 4:2:2 / 4:2:0 / general Hi,Vi chroma subsampling,
DRI/RST restart markers — normalizing to the **same canonical RGBA8**
`ChitraImage` PNG produces, plus a format-sniffing `chitra_image_decode`
entry point. Decoder output is verified **byte-identical to ImageMagick** on
a real 16×16 baseline gradient JPEG (real Annex K Huffman tables + AC
entropy). The PNG decode path is unchanged. `chitra_version()` → **300**.
**728 assertions** across 5 suites. See [`CHANGELOG.md`](../../CHANGELOG.md).

Released tags: 0.1.0, 0.2.0, 0.2.1 (SemVer; pre-1.0, the public surface is
still moving — no API freeze until v1.0). **0.3.0 is being cut now and is
not yet tagged.**

## Toolchain

- **Cyrius pin**: `6.2.44` (in [`cyrius.cyml`](../../cyrius.cyml)
  `[package].cyrius`).
- **`lib/`**: vendored by `cyrius deps` from the 6.2.44 stdlib snapshot. It
  is a **real directory, never a symlink** — distlib concatenation depends
  on it (see [architecture/001](../architecture/001-lib-must-not-be-symlink.md)).
- **Cyrius note**: `>>` is a **logical** shift. The JPEG IDCT and the
  YCbCr→RGB color pass need signed round-to-nearest division, so they use the
  in-tree `_jpeg_descale` helper rather than `>>` (see
  [adr/0004](../adr/0004-jpeg-decode-model.md)).

## Surface

chitra is a **library** — encoded image bytes → canonical RGBA8, zero GPU,
no C shim, no external binaries, no CLI/stdout/ANSI surface (the one stderr
write is `chitra_err_print_name`, a fixed string). Consumers link
`dist/chitra.cyr`. DEFLATE is **sankoch's** job; JPEG entropy decode is
chitra's own (no sankoch on the JPEG path).

### Public API (`@public`)

PNG:

- `chitra_png_decode(src, len, err_out)` → `ChitraImage*` (0 on fail,
  `*err_out` set).
- `chitra_png_decode_rgba8(src, len, w_out, h_out)` → RGBA8 ptr (0 on fail) —
  convenience wrapper.

JPEG (0.3.0):

- `chitra_jpeg_decode(src, len, err_out)` → `ChitraImage*` (0 on fail,
  `*err_out` set).
- `chitra_jpeg_decode_rgba8(src, len, w_out, h_out)` → RGBA8 ptr (0 on fail).
- `chitra_jpeg_check_signature(src, len)` → 1 if the bytes open with the
  JPEG SOI marker.

Format-agnostic:

- `chitra_image_decode(src, len, err_out)` → `ChitraImage*` — the
  **signature-sniffing router**: JPEG SOI → `chitra_jpeg_decode`, otherwise
  → `chitra_png_decode`. The single entry a consumer should reach for when
  it does not know the format up front.

Shared:

- `ChitraImage` accessors: `chitra_image_{width,height,pixels,channels,
  seen_iend,source_color_type}`; `chitra_image_free` (a documented no-op
  under the bump allocator).
- `chitra_version()` → `300` (`major*10000 + minor*100 + patch`).
- Error API: `chitra_err_new` / `chitra_err` / `chitra_err_code` /
  `chitra_err_detail` / `chitra_err_name` / `chitra_err_print_name` + enum
  `ChitraErrCode`.

`ChitraImage` is a **48-byte** record — `width`@0, `height`@8, `pixels`@16
(owned RGBA8, `w*h*4` bytes), `channels`@24 (=4), `seen_iend`@32 (1 = IEND
closed the stream, 0 = tolerated IEND-less clean end), `src_ctype`@40. For a
PNG, `src_ctype` is the pre-normalization PNG color_type (0/2/3/4/6); for a
JPEG it carries the sentinel `0x100 | num_components` (so `0x101` grayscale,
`0x103` YCbCr). The +32/+40 fields are **append-only** — 0.1.x offsets
preserved, so mabda's accessors are unaffected.

`ChitraErr` is a **16-byte** record (+0 code, +8 detail ptr), **layout-
compatible with mabda's `GpuErr`** so a decode failure maps onto
`GPU_ERR_IMAGE_DECODE` (see [adr/0003](../adr/0003-mabda-abi-compatibility.md)).

### PNG decode matrix (feature-complete as of 0.2.1)

Signature + chunk parse (IHDR / IDAT-concat / IEND / PLTE / tRNS), all five
color types across every spec-legal bit depth, both scan orders:

| color type | 1 | 2 | 4 | 8 | 16 |
|---|---|---|---|---|---|
| 0 grayscale       | ✓ | ✓ | ✓ | ✓ | ✓ |
| 2 RGB             | — | — | — | ✓ | ✓ |
| 3 palette         | ✓ | ✓ | ✓ | ✓ | ✗ |
| 4 gray+alpha      | — | — | — | ✓ | ✓ |
| 6 RGBA            | — | — | — | ✓ | ✓ |

(— = not spec-legal per § 11.2.2 Table 11.1, rejected at the IHDR gate;
✗ = ct3+depth16 is the one illegal combo that survives the table and is
rejected.) **Adam7 interlace** is supported for every cell — the 7 reduced
passes are filtered independently and deinterlaced into the same dense,
byte-padded buffer the non-interlaced path produces, so the color pass is
interlace-agnostic. 16-bit samples truncate to the high byte; sub-byte
grayscale scales ×255/85/17; palette indexes PLTE; tRNS synthesizes alpha.

### JPEG decode scope (0.3.0)

JFIF **baseline** (SOF0) sequential Huffman, 8-bit precision only:

- **Grayscale** (1 component) and **YCbCr** (3 components).
- **Chroma subsampling**: 4:4:4 / 4:2:2 / 4:2:0 and **general per-component
  Hi,Vi** (box upsampling to full resolution).
- **DRI / RST0–7** restart markers — restart intervals reset the DC
  predictors and byte-align the entropy stream.

Decode pipeline: `chitra_jpeg_scan_markers` (SOI..SOS marker walk —
DQT / DHT / SOF0 / DRI parse + reject non-baseline) → `_jpeg_parse_sos` →
`_jpeg_decode_scan` (per-component MCU loop: `_jpeg_decode_block`
[bit-reader + Annex F `DECODE` + `RECEIVE`/`EXTEND`, DC diff + AC run/size],
`_jpeg_idct_block` [dequant + zig-zag + libjpeg `islow` integer IDCT +
level-shift `+128` and `[0,255]` clamp], plane placement) → box upsample +
full-range BT.601 YCbCr→RGB → `ChitraImage`. **Non-baseline modes
(progressive, arithmetic, 12-bit precision, hierarchical/lossless/
differential, 4-component CMYK/YCCK) are rejected with distinct error
codes** — the defer-don't-half-implement posture. See
[adr/0004](../adr/0004-jpeg-decode-model.md) and
[proposals/jpeg-baseline-decoder.md](../proposals/jpeg-baseline-decoder.md).

### Decode rejection paths → `CHITRA_ERR_*`

PNG / generic: `OK`=0, `SIGNATURE`=1, `TRUNCATED`=2, `BAD_CHUNK`=3,
`UNSUPPORTED`=4, `INFLATE`=5, `OOM`=6, `CRC`=7, `INTERLACE`=8, `BIT_DEPTH`=9,
`DIMENSIONS`=10, `FILTER`=11, `NO_IDAT`=12, `OTHER`=99.

JPEG (`src/error.cyr` enum, 13–23): `JPEG_MARKER`=13, `JPEG_SOF`=14,
`JPEG_DQT`=15, `JPEG_DHT`=16, `JPEG_SOS`=17, `JPEG_ENTROPY`=18,
`JPEG_PROGRESSIVE`=19, `JPEG_ARITHMETIC`=20, `JPEG_PRECISION`=21,
`JPEG_MODE`=22, `JPEG_COMPONENTS`=23. The JPEG path also reuses the generic
`SIGNATURE`=1, `TRUNCATED`=2, `OOM`=6, `DIMENSIONS`=10, `UNSUPPORTED`=4.

For PNG every byte access is bounds-checked against the input span, CRC-32 is
verified per chunk, and the kii decompression-bomb / lying-IHDR /
dimension-ratio caps reject hostile inputs loud (see
[adr/0002](../adr/0002-security-model.md)).

> **Doc-drift note:** `src/error.cyr`'s enum comments for
> `CHITRA_ERR_INTERLACE` ("single-pass only") and `CHITRA_ERR_BIT_DEPTH`
> ("bit_depth != 8") are **stale** ([`error.cyr:26-27`](../../src/error.cyr)
> still read "chitra 0.2") — 0.2.1 decodes Adam7 + all bit depths, so
> `INTERLACE` is now effectively unused and `BIT_DEPTH` only fires for a
> genuinely illegal combo (e.g. ct3+depth16, or ct2/4/6 at a sub-byte depth).

## Module map

Source under `src/` — flat domain modules in `[lib].modules` dependency
order. Stdlib includes live **only** in `lib.cyr`.

PNG + shared:

- `error.cyr` (111 L) — the `ChitraErr` model: the `ChitraErrCode` enum
  (now incl. the 13–23 JPEG codes), the 16-byte `GpuErr`-compatible record,
  `chitra_err_*` constructors / accessors / `print_name`, and the
  error-name table. Dep-free.
- `png_chunks.cyr` (282 L) — the bounds-checked `(src, len)` cursor (every
  u8 / u32-BE / skip validated against `len` before access), the 8-byte
  signature check, chunk-type predicates (IHDR / IDAT / IEND / PLTE / tRNS),
  color-type→channels, the security ceilings (`MAX_PIXELS`=16777216,
  `MAX_RAW_BYTES`=268435456, `MAX_DIM`=65535, the bomb ratio), and the
  internal `ChitraPngRaw` handoff struct + accessors. The JPEG modules reuse
  this byte cursor.
- `png_filter.cyr` (578 L) — the five § 9 unfilter predictors
  (None / Sub / Up / Average / Paeth), the Adam7 7-pass deinterlace, and
  `chitra_png_parse_raw`: the two-pass chunk walk (CRC-32 each chunk via
  sankoch, parse IHDR, capture PLTE/tRNS spans, concat IDAT, inflate with
  the bomb caps, unfilter into the scanline buffer). Every failure returns
  a `ChitraErr`, never an OOB read.
- `png_color.cyr` (344 L) — `chitra_png_color_to_rgba8`: the canonical-RGBA8
  normalization pass — grayscale → (g,g,g,255), RGB → (r,g,b,255), palette →
  PLTE RGB + per-entry tRNS alpha, gray+alpha → (g,g,g,a), RGBA passthrough,
  with tRNS keying for types 0/2 and sub-byte / 16-bit sample handling.
  PLTE/tRNS are resolved from the original `src` via the captured
  (offset, length) spans, re-validated defensively.
- `png.cyr` (125 L) — the public PNG decode API (`chitra_png_decode` /
  `chitra_png_decode_rgba8`), the 48-byte `ChitraImage` + accessors,
  `chitra_image_free`, the JPEG `src_ctype` sentinel doc, and
  `chitra_version`.

JPEG (0.3.0):

- `jpeg_huffman.cyr` (288 L) — frame-independent Huffman machinery: the
  canonical decode-table representation (`mincode`/`maxcode`/`valptr`/
  `huffval`) built from DHT BITS + HUFFVAL (T.81 Annex C + F) with
  over-subscription rejection; the entropy bit-reader (MSB-first, `0xFF00`
  byte-unstuffing, marker detection + zero-pad past a marker,
  `_jpeg_br_restart`); the `DECODE` / `RECEIVE` / `EXTEND` procedures; and
  `_jpeg_decode_block` (one 8×8 block — DC differential + AC run/size with
  ZRL and EOB → 64 zig-zag coefficients).
- `jpeg_idct.cyr` (222 L) — the zig-zag→natural index map, dequantization,
  the libjpeg `jpeg_idct_islow` integer fixed-point 8×8 inverse DCT, the
  `+128` level-shift with `[0,255]` clamp, and `_jpeg_descale` (signed
  round-to-nearest division, since Cyrius `>>` is logical).
- `jpeg_markers.cyr` (510 L) — `chitra_jpeg_check_signature`,
  `chitra_jpeg_scan_markers` (SOI → segment walk → SOS, parsing SOF0 frame
  header / DQT / DHT / DRI and **rejecting** non-baseline modes), the
  `ChitraJpegFrame` storage, and the JPEG security guards: sampling factors
  clamped 1..4 (rejecting 0 — the CVE-2018-11212 divide-by-zero), duplicate
  component ids rejected, ΣHi·Vi ≤ `MAX_BLOCKS_PER_MCU` (10) enforced before
  MCU geometry, `MAX_DIM`/`MAX_PIXELS` re-checked, plus `MAX_COMPONENTS`=4,
  `MAX_SAMP_FACTOR`=4, `MAX_QUANT_TABLES`=4, `MAX_HUFF_TABLES`=4.
- `jpeg.cyr` (434 L) — the public JPEG decode API (`chitra_jpeg_decode` /
  `chitra_jpeg_decode_rgba8`) and the format-sniffing `chitra_image_decode`
  router; `_jpeg_parse_sos` (scan header — Td/Ta selectors, baseline
  Ss=0/Se=63/Ah=Al=0), the subsampling-aware `_jpeg_decode_scan` MCU loop
  (max_h×max_v data units, per-component subsampled planes, box upsample),
  and the BT.601 YCbCr→RGB color pass → `ChitraImage`.

Include chain: `lib.cyr` (64 L) pulls the stdlib set then
`error.cyr` → `png_chunks.cyr` → `png_filter.cyr` → `png_color.cyr` →
`png.cyr` → `jpeg_huffman.cyr` → `jpeg_idct.cyr` → `jpeg_markers.cyr` →
`jpeg.cyr` (the order in `[lib].modules`).

## Sizes

- `dist/chitra.cyr` — **~122 KB** (124,630 bytes / 2,925 lines), regenerated
  by `cyrius distlib` (= `make dist`). This is the artifact consumers link.
- `build/chitra_smoke` — **~378 KB** (386,480 bytes), built from `programs/smoke.cyr` via
  `make build`. It only proves the include chain compiles + links clean —
  chitra is a library, there is no real CLI behind it.

## Tests + bench

- `make test` (globs `tests/tcyr/*.tcyr`; each is a standalone `main()`) →
  **728 assertions, all pass** across 5 suites:
  - `error.tcyr` — **20** (error codes, `chitra_err_*` accessors, name
    round-trips, `chitra_version`).
  - `interlace.tcyr` — **35** (Adam7 cross-checked against the trusted
    non-interlaced decode for 7 color/depth/odd-dimension cases).
  - `jpeg.tcyr` — **203** (marker scan + non-baseline rejection, SOF0
    components + DQT, Huffman table build vs Annex K.3.3, entropy block
    decode, zig-zag + IDCT + dequant known-answers, end-to-end grayscale /
    YCbCr 4:4:4 / 4:2:0 / restart-interval decodes, and a real
    ImageMagick-encoded 16×16 baseline gradient decoded **byte-identical**).
  - `png.tcyr` — **327** (cursor bounds, all five unfilter predictors, one
    embedded fixture per color type at depth 8/16, palette+tRNS / keyed-color
    fixtures, `_rgba8` wrapper, adversarial rejections).
  - `subbyte.tcyr` — **143** (gray/palette at 1/2/4, multi-row padding,
    sub-byte ct2/4/6 reject).
- **No in-tree fuzz harness and no benchmark harness yet** — this is a real
  gap, and both are **v1.0 gates**. The JPEG decoder's hardening lineage is
  the kii/PNG fork's; the byte-buffer / entropy surface has **not** been
  fuzzed in-tree, and decode latency/throughput are **not yet measured**
  in-repo (no `.fcyr` / `.bcyr` ships).

## Dependencies

- **stdlib**: `string`, `fmt`, `alloc`, `io`, `vec`, `str`, `syscalls`,
  `assert`, `bench`, `args`, `flags`, `sankoch`, `thread` (unchanged across
  0.3.0). `sankoch` = RFC 1950/1951 `zlib_decompress` + `crc32` + `adler32`
  (DEFLATE is sankoch's, not chitra's — it backs PNG IDAT inflate + chunk
  CRC); `thread` is the mutex pair sankoch's public-API lock wraps. The JPEG
  path takes **no** sankoch — its entropy (Huffman) decode is chitra's own.
  Resolved by `cyrius deps` into `lib/`.
- **Consumers** (external): **mabda** (`gpu_texture_load_png` — a plain dist
  dep `[deps.chitra]`, no C shim; `ChitraErr` ⇒ `GpuErr`), and **kii** —
  which consumes chitra back: its v1.2.0 PNG re-fold deleted its own
  decoder and adopted `dist/chitra.cyr` (see kii's ADR 0006). Lineage is a
  one-time fork of kii's `src/png.cyr` with **no live dependency** —
  bugfixes are manual backports in both directions.

## Next

Per [`docs/development/roadmap.md`](roadmap.md):

- The 0.2.x audit landed — see
  [`docs/audit/2026-06-26-audit.md`](../audit/2026-06-26-audit.md).
- **Fuzz harness** + **benchmark harness** — the two **v1.0 gates** still
  open (fuzz-corpus the PNG chunk + JPEG entropy byte boundaries; measure
  decode latency/throughput). The JPEG entropy surface is the priority
  target — it is the newest unfuzzed code.
- **GIF / BMP** — the format-agnostic name and the `chitra_image_decode`
  router already leave room for them to join without a rename.
- **API freeze** toward **v1.0** (the surface is still moving pre-1.0).
- Stale `src/error.cyr` enum comments (`INTERLACE` / `BIT_DEPTH`) to be
  refreshed to the 0.2.1 reality.
