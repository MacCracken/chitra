# chitra — Current State

> **Last refresh**: 2026-08-24 (0.6.0) | **Refresh cadence**: every release.
> [`CLAUDE.md`](../../CLAUDE.md) is preferences / process / architecture
> (durable); this file is **state** (volatile) — it is the home for the
> version, sizes, and counts `CLAUDE.md` must not inline.

## Version

**0.6.0** — cut 2026-08-24. **T.81 § A.2 non-interleaved JPEG scans decode —
for a one-component frame.** A grayscale JPEG declaring `H > 1` or `V > 1` was
rejected through 0.5.3, deliberately (0.3.3 chose refusal over mis-rendering);
0.6.0 implements the layout, so that rejection is **reversed** — the first time
this project has un-rejected an input class.

The implementation is an **effective-geometry collapse**, not a second decoder.
For `Nf = 1` the sampling factors are *inert*: § A.1.1's
`x_i = ceil(X·H_i/H_max)` collapses to `x_1 = X` because the lone component IS
the maximum, so forcing `H = V = max_h = max_v = 1` makes the existing
interleaved loop walk the non-interleaved layout exactly. `cpw = ceil(w/8)·8`
covers the plane with **no unwritten margin**, which is why the cut adds no
zero-fill and no containment tripwire — neither could ever fire.

It also conditions **ΣHj·Vj ≤ 10 on `Ns > 1`** per § B.2.3 (it bounds an
interleaved MCU; a one-component frame has none), with the cap's reachability
proven in both directions, and moves the multi-scan rejection from
`CHITRA_ERR_JPEG_SOS` to `CHITRA_ERR_UNSUPPORTED` — the file is valid and
chitra declines it.

**Multi-scan and partially-interleaved files stay deferred**
([ADR 0006](../adr/0006-defer-jpeg-multiscan-resumption.md)), and the
**byte-budget surface is deferred to 0.6.1**
([ADR 0007](../adr/0007-byte-budget-surface-deferred.md)) on a measurement: a
15-byte JPEG that is refused spends **22,096 bytes**, so a probe-based memory
ceiling would itself be an exhaustion vector on its own refusal path.

`chitra_version()` → **600**. **2,719 test assertions** across **8 suites**,
**8,072,804 fuzz assertions** across 4 harnesses, and 17 benchmarks — 0 failures
throughout. See [`CHANGELOG.md`](../../CHANGELOG.md).

Released tags: 0.1.0, 0.2.0, 0.2.1, 0.3.0, 0.3.1, 0.3.2, 0.3.3, 0.4.0, 0.5.0,
0.5.1, 0.5.2, 0.5.3 (SemVer;
pre-1.0, the public surface is still moving — no API freeze until v1.0).

## Toolchain

- **Cyrius pin**: `6.5.35` (in [`cyrius.cyml`](../../cyrius.cyml)
  `[package].cyrius`). This pin is the **only** source of truth — CI and the
  release workflow both read it; no toolchain version is hardcoded in YAML.
- **`lib/`**: vendored by `cyrius lib sync --full` / `cyrius deps` from the
  6.5.35 stdlib snapshot — **108 `.cyr` files** (101 top-level + 7 under
  `lib/unicode`). It is a **real directory, never a symlink** — distlib
  concatenation depends on it (see
  [architecture/001](../architecture/001-lib-must-not-be-symlink.md)).
  `lib/` is gitignored: it is a build artifact, not source.
- **6.5.35 notes**:
  - `cyrfmt` now indents wrapped continuation lines **+2** relative to the
    statement. This reflowed `src/png_chunks.cyr`, `src/png_filter.cyr`, and
    `tests/tcyr/error.tcyr` at the 0.3.2 cut — whitespace only
    (`git diff --ignore-all-space` over those files is empty).
  - Since 6.5.28 `cyrius fmt` **rewrites in place** (it was stdout-only
    before). The `make fmt-check` target relies on the exit code with the
    file argument *before* `--check`, and redirects stdout — verify that
    contract holds on any future pin bump.
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
- `chitra_png_check_signature(src, len)` → 1 if the bytes open with the
  8-byte PNG signature.

JPEG (0.3.0):

- `chitra_jpeg_decode(src, len, err_out)` → `ChitraImage*` (0 on fail,
  `*err_out` set).
- `chitra_jpeg_decode_rgba8(src, len, w_out, h_out)` → RGBA8 ptr (0 on fail).
- `chitra_jpeg_check_signature(src, len)` → 1 if the bytes open with the
  JPEG SOI marker.

GIF (0.5.0, first frame only — [ADR 0005](../adr/0005-gif-first-frame-only.md)):

- `chitra_gif_decode(src, len, err_out)` → `ChitraImage*` (0 on fail,
  `*err_out` set). Sized to the **logical screen**; canvas the first frame does
  not paint is emitted transparent (alpha 0) rather than background-filled —
  chitra did not decode those pixels, and alpha 0 says exactly that.
- `chitra_gif_decode_rgba8(src, len, w_out, h_out)` → RGBA8 ptr (0 on fail).
- `chitra_gif_check_signature(src, len)` → 1 for `GIF87a` / `GIF89a`.

BMP (0.4.0):

- `chitra_bmp_decode(src, len, err_out)` → `ChitraImage*` (0 on fail,
  `*err_out` set).
- `chitra_bmp_decode_rgba8(src, len, w_out, h_out)` → RGBA8 ptr (0 on fail).
- `chitra_bmp_check_signature(src, len)` → 1 if the bytes open with `BM`.

Format-agnostic:

- `chitra_image_decode(src, len, err_out)` → `ChitraImage*` — the
  **signature-sniffing router** ([`jpeg.cyr:460`](../../src/jpeg.cyr)): the
  8-byte PNG magic → `chitra_png_decode`; else the JPEG SOI marker →
  `chitra_jpeg_decode`; else the BMP `BM` magic → `chitra_bmp_decode`; else
  the `GIF87a`/`GIF89a` magic → `chitra_gif_decode`; else
  **`0` with `*err_out` = `CHITRA_ERR_SIGNATURE`**.
  It does *not* fall through to the PNG decoder for unrecognized bytes — an
  unknown format is rejected at the router. The single entry a consumer
  should reach for when it does not know the format up front.

Shared:

- `ChitraImage` accessors: `chitra_image_{width,height,pixels,channels,
  seen_iend,source_color_type}`; `chitra_image_free` (a documented no-op
  under the bump allocator).
- `chitra_version()` → **`600`** (`major*10000 + minor*100 + patch`).
- Error API: `chitra_err_new` / `chitra_err` / `chitra_err_code` /
  `chitra_err_detail` / `chitra_err_name` / `chitra_err_print_name` + enum
  `ChitraErrCode`.

> **Marker note**: `@public` is used two ways — a **file-level banner** on
> line 1 of `png.cyr` and `error.cyr` (covering that module's whole stable
> surface, which is how the `ChitraImage` accessors and the `chitra_err_*`
> family are marked) and a **per-function** marker elsewhere. The two
> signature predicates live in `png_chunks.cyr` / `jpeg_markers.cyr`, which
> carry **neither** form — they are public by documentation and by consumer
> use, but not by marker. Worth reconciling at the v1.0 API freeze.

`ChitraImage` is a **48-byte** record — `width`@0, `height`@8, `pixels`@16
(owned RGBA8, `w*h*4` bytes), `channels`@24 (=4), `seen_iend`@32 (1 = IEND
closed the stream, 0 = tolerated IEND-less clean end), `src_ctype`@40. For a
PNG, `src_ctype` is the pre-normalization PNG color_type (0/2/3/4/6); for a
JPEG it carries the sentinel `0x100 | num_components` (so `0x101` grayscale,
`0x103` YCbCr); for a BMP, `0x200 | bpp` (so `0x201`/`0x204`/`0x208` indexed,
`0x218` at 24 bpp, `0x220` at 32 bpp); for a GIF, `0x300 | min_code_size`. The +32/+40 fields are **append-only** — 0.1.x offsets
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
- **T.81 § A.2 non-interleaved layout for a ONE-component frame** (0.6.0): any
  `H`,`V` in 1..4, including `H·V > 10`. The factors are inert there — § A.1.1
  collapses to `x_1 = X` — so the decoder forces the effective geometry to
  `H = V = 1` rather than carrying a second layout. Multi-scan and partially
  interleaved files (`Ns < Nf`) are **deferred** with `CHITRA_ERR_UNSUPPORTED`
  ([ADR 0006](../adr/0006-defer-jpeg-multiscan-resumption.md)).
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
`SIGNATURE`=1, `TRUNCATED`=2, `OOM`=6, `DIMENSIONS`=10, `UNSUPPORTED`=4 —
the last of which 0.6.0 widened to cover the multi-scan deferral (it was
`JPEG_SOS`=17 through 0.5.3, which said "malformed" about a valid file).

BMP: `BMP_HEADER`=24, `BMP_DEPTH`=25, `BMP_COMPRESSION`=26 (now **only**
`BI_JPEG` / `BI_PNG`, refused permanently), `BMP_PALETTE`=27, `BMP_RLE`=32
(0.5.1), `BMP_MASK`=33 (0.5.2). GIF: `GIF_HEADER`=28, `GIF_LZW`=29,
`GIF_PALETTE`=30, `GIF_NO_IMAGE`=31. Both paths reuse `TRUNCATED`=2, `OOM`=6
and `DIMENSIONS`=10 — the latter is what the 0.5.3 amplification caps raise.

For PNG every byte access is bounds-checked against the input span, CRC-32 is
verified per chunk, and the kii decompression-bomb / lying-IHDR /
dimension-ratio caps reject hostile inputs loud (see
[adr/0002](../adr/0002-security-model.md)).

Two codes are narrower than their names suggest, and the 0.3.2 cut corrected
their stale enum comments in [`src/error.cyr`](../../src/error.cyr):

- **`INTERLACE`=8** fires only when the IHDR interlace **method** is neither
  0 (none) nor 1 (Adam7) — [`png_filter.cyr:171`](../../src/png_filter.cyr).
  Both spec-legal methods decode, so this is an illegal-value rejection, not
  an unsupported-feature one.
- **`BIT_DEPTH`=9** fires only on a bit-depth × color-type combination that
  is not spec-legal per § 11.2.2 Table 11.1 (e.g. ct3+depth16, or ct2/4/6 at
  a sub-byte depth) — [`png_filter.cyr:185`](../../src/png_filter.cyr).

Their `chitra_err_name` strings ("interlace unsupported" / "bit depth
unsupported") still read as capability limits rather than validity failures.
Rewording them changes public `chitra_err_name` output, so it is deferred to
the v1.0 API freeze rather than slipped into a patch release.

## Module map

Source under `src/` — flat domain modules in `[lib].modules` dependency
order. Stdlib includes live **only** in `lib.cyr`.

PNG + shared:

- `error.cyr` (149 L) — the `ChitraErr` model: the `ChitraErrCode` enum
  (now incl. the 13–23 JPEG codes), the 16-byte `GpuErr`-compatible record,
  `chitra_err_*` constructors / accessors / `print_name`, and the
  error-name table. Dep-free.
- `png_chunks.cyr` (282 L) — the bounds-checked `(src, len)` cursor (every
  u8 / u32-BE / skip validated against `len` before access), the 8-byte
  signature check, chunk-type predicates (IHDR / IDAT / IEND / PLTE / tRNS),
  color-type→channels, the security ceilings (`MAX_PIXELS`=16777216,
  `MAX_RAW_BYTES`=268435456, `MAX_DIM`=65535, and the four amplification
  ratios — `MAX_INFLATE_RATIO`=1100 PNG, `MAX_JPEG_RATIO`=4096,
  `MAX_BMP_RLE_RATIO`=4096 and `MAX_GIF_RATIO`=16384, the last two added in
  0.5.3), and the
  internal `ChitraPngRaw` handoff struct + accessors. The JPEG modules reuse
  this byte cursor.
- `png_filter.cyr` (621 L) — the five § 9 unfilter predictors
  (None / Sub / Up / Average / Paeth), the Adam7 7-pass deinterlace, and
  `chitra_png_parse_raw`: the two-pass chunk walk (CRC-32 each chunk via
  sankoch, parse IHDR, capture PLTE/tRNS spans, concat IDAT, inflate with
  the bomb caps, unfilter into the scanline buffer). Every failure returns
  a `ChitraErr`, never an OOB read.
- `png_color.cyr` (352 L) — `chitra_png_color_to_rgba8`: the canonical-RGBA8
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

- `jpeg_huffman.cyr` (329 L) — frame-independent Huffman machinery: the
  canonical decode-table representation (`mincode`/`maxcode`/`valptr`/
  `huffval`) built from DHT BITS + HUFFVAL (T.81 Annex C + F) with
  over-subscription rejection; the entropy bit-reader (MSB-first, `0xFF00`
  byte-unstuffing, marker detection + zero-pad past a marker,
  `_jpeg_br_restart`); the `DECODE` / `RECEIVE` / `EXTEND` procedures; and
  `_jpeg_decode_block` (one 8×8 block — DC differential + AC run/size with
  ZRL and EOB → 64 zig-zag coefficients).
- `jpeg_idct.cyr` (226 L) — the zig-zag→natural index map, dequantization,
  the libjpeg `jpeg_idct_islow` integer fixed-point 8×8 inverse DCT, the
  `+128` level-shift with `[0,255]` clamp, and `_jpeg_descale` (signed
  round-to-nearest division, since Cyrius `>>` is logical).
- `jpeg_markers.cyr` (553 L) — `chitra_jpeg_check_signature`,
  `chitra_jpeg_scan_markers` (SOI → segment walk → SOS, parsing SOF0 frame
  header / DQT / DHT / DRI and **rejecting** non-baseline modes), the
  `ChitraJpegFrame` storage, and the JPEG security guards: sampling factors
  clamped 1..4 (rejecting 0 — the CVE-2018-11212 divide-by-zero), duplicate
  component ids rejected, ΣHi·Vi ≤ `MAX_BLOCKS_PER_MCU` (10) enforced before
  MCU geometry (0.6.0: **conditioned on `ncomp > 1`**, per T.81 § B.2.3 — the
  rule bounds an interleaved MCU and a one-component frame has none),
  `MAX_DIM`/`MAX_PIXELS` re-checked, plus `MAX_COMPONENTS`=4,
  `MAX_SAMP_FACTOR`=4, `MAX_QUANT_TABLES`=4, `MAX_HUFF_TABLES`=4.
- `jpeg.cyr` (533 L) — the public JPEG decode API (`chitra_jpeg_decode` /
  `chitra_jpeg_decode_rgba8`) and the format-sniffing `chitra_image_decode`
  router; `_jpeg_parse_sos` (scan header — Td/Ta selectors, baseline
  Ss=0/Se=63/Ah=Al=0), the subsampling-aware `_jpeg_decode_scan` MCU loop
  (max_h×max_v data units, per-component subsampled planes, box upsample),
  and the BT.601 YCbCr→RGB color pass → `ChitraImage`. 0.6.0 added the § A.2
  effective-geometry collapse for a one-component frame and split the single
  `ns != ncomp` scan test into three branches with honest codes (`Ns < 1` and
  `Ns > Nf` are validity failures; `Ns < Nf` is the deferral).

BMP (0.4.0):

- `bmp.cyr` (1,014 L) — the whole BMP path in one module: `chitra_bmp_check_signature`,
  little-endian readers (BMP is LE where PNG and JPEG are BE), the
  `BITMAPFILEHEADER` + DIB header parse into `ChitraBmpHdr`, the deferred-mode
  rejections, the MSB-first index extractor, the `BI_RLE8`/`BI_RLE4` run-length
  decoder (0.5.1 — opcode loop, per-write bounds checks, delta validated at the
  jump), the `BI_BITFIELDS` channel-mask machinery (0.5.2 — shift/width
  extraction, contiguity and overlap validation, and bit-replication widening),
  and `chitra_bmp_decode` / `chitra_bmp_decode_rgba8`. 0.5.3 made the masks
  govern **both** packed depths unconditionally rather than only when an alpha
  mask was declared, gated mask reads on `BI_BITFIELDS` (Microsoft: the V4/V5
  masks are *"valid only if compression is BI_BITFIELDS"*), and added the
  RLE amplification cap — measured on bytes actually **consumed**, since
  padding defeated the first version of it. Depends on `error.cyr` for codes,
  `png_chunks.cyr` for the shared ceilings, and `png.cyr` for `ChitraImage`
  — which is why it comes last in the include order.

GIF (0.5.0):

- `gif_lzw.cyr` (285 L) — the LZW decompressor: LSB-first variable-width bit
  reader, dictionary build, chain expansion, Clear/End handling and the KwKwK
  case. Frame-independent, so it precedes `gif.cyr` in the include order for
  the same reason `jpeg_huffman.cyr` precedes `jpeg_markers.cyr`.
- `gif.cyr` (461 L) — `chitra_gif_check_signature`, the block walk (extensions
  skipped by their sub-block chain, GCE read for transparency), the image
  descriptor and frame geometry, global/local color tables, the 4-pass row
  interlace, and `chitra_gif_decode` / `_rgba8`. 0.5.3 validated the GCE block
  size (fixed at 4, and every field after it addressed by a fixed offset),
  made the transparent index **clear** when a later GCE revokes it, and put
  the amplification cap **before** the allocation it exists to prevent.

Include chain: `lib.cyr` (74 L) pulls the stdlib set then
`error.cyr` → `png_chunks.cyr` → `png_filter.cyr` → `png_color.cyr` →
`png.cyr` → `jpeg_huffman.cyr` → `jpeg_idct.cyr` → `jpeg_markers.cyr` →
`jpeg.cyr` → `bmp.cyr` → `gif_lzw.cyr` → `gif.cyr` (the order in
`[lib].modules`). Domain-module total: **4,930 L** across 12 files, plus
`lib.cyr` (74 L).

## Sizes

- `dist/chitra.cyr` — **~212 KB** (217,452 bytes / 4,970 lines; `cyrius
  distlib` reports 4,930 code lines), regenerated by `cyrius distlib`
  (= `make dist`). This is the artifact consumers link. **0.6.0 adds no public
  function and no error code** — verified by diffing the exported `fn chitra_*`
  signatures against the 0.5.3 bundle: **68 functions, identical**. The surface
  change is in behaviour only: one input class that previously rejected now
  decodes, one that previously rejected now rejects with a different (and
  honest) code.
- `dist/chitra.deps` — the 13-leaf stdlib sidecar consumers resolve against.
- `build/chitra_smoke` — **~575 KB** (588,976 bytes), built from
  `programs/smoke.cyr` (19 L) via `make build`. It only proves the include
  chain compiles and links clean — chitra is a library, there is no real CLI
  behind it.

## Tests + bench

- `make test` (globs `tests/tcyr/*.tcyr`; each is a standalone `main()`) →
  **2,719 assertions, all pass** across 8 suites:
  - `gif.tcyr` — **632** (signature, plain / interlaced 4×4 and 8×8 /
    transparent / animated-first-frame fixtures with **every pixel asserted**,
    the no-image and bad-min-code-size rejections, a truncation sweep, the
    four-format router, and the 0.5.3 amplification bomb — plain, padded, and
    a real GIF proving the cap does not reject valid input). Fixtures are real ImageMagick GIFs; expectations were
    corroborated by a second independent decoder, which is what caught the
    KwKwK bug.
  - `bmp.tcyr` — **1,042** (signature, 24/32 bpp, 1/4/8 bpp palette,
    `BITMAPCOREHEADER`, bottom-up **and** top-down producing identical output,
    the 32-bpp undefined-alpha heuristic, deferred-mode + malformed-header
    rejections, an out-of-range palette index, a full truncation sweep, the
    three-format router, and the `_rgba8` wrapper; plus the 0.5.1 run-length
    coverage — an ImageMagick-encoded RLE8 file, hand-built RLE4-encoded,
    RLE8-absolute, RLE4-absolute and delta fixtures all cross-checked against
    ImageMagick's decode, and the guard rejections for an out-of-bounds delta,
    an over-long run, a truncated absolute run, an unterminated stream, a
    depth mismatch and a top-down RLE DIB. The RLE4-encoded, RLE8-absolute and
    RLE4-absolute fixtures encode the **same image by three different opcode
    paths**, so they must decode identically. Plus the 0.5.2 mask coverage —
    16 bpp 5-5-5 and 5-6-5, V4 and V5 headers carrying an alpha mask, and the
    three mask rejections: non-contiguous, overlapping, and wider than the
    pixel word; and the 0.5.3 audit regressions — a 32-bpp bitfields file with
    **no** alpha mask whose channels must still be permuted by its masks, a V4
    `BI_RGB` file whose stale masks must be ignored, a bitfields file declaring
    no colour channel, and the RLE amplification bomb both plain and **padded**,
    with a real 1,082-byte RLE8 file proving the cap does not reject valid
    input). Fixture pixel values are
    distinct per position — a decoder with the row order *or* channel order
    wrong returns the right *set* of pixels in the wrong places, and only
    position-sensitive expectations catch that.
  - `error.tcyr` — **20** (error codes, `chitra_err_*` accessors, name
    round-trips, `chitra_version` → 600).
  - `interlace.tcyr` — **35** (Adam7 cross-checked against the trusted
    non-interlaced decode for 7 color/depth/odd-dimension cases).
  - `jpeg.tcyr` — **230** (marker scan + non-baseline rejection, SOF0
    components + DQT, Huffman table build vs Annex K.3.3, entropy block
    decode, zig-zag + IDCT + dequant known-answers, end-to-end grayscale /
    YCbCr 4:4:4 / 4:2:0 / restart-interval decodes, and a real
    ImageMagick-encoded 16×16 baseline gradient decoded **byte-identical**,
    plus the 0.3.3 bomb-cap / non-segment-marker regressions, and the 0.3.3
    non-interleaved cell **converted in 0.6.0** from a rejection to a bounds /
    no-crash cell — its 2-byte entropy stream encodes one block where the
    corrected grid asks for three, so the reader zero-pads and it proves the
    guard is gone rather than proving conformance; the conformance weight lives
    in `jpeg_noninterleaved.tcyr` on real encoder output).
  - `png.tcyr` — **380** (cursor bounds, all five unfilter predictors, one
    embedded fixture per color type at depth 8/16, palette+tRNS / keyed-color
    fixtures, `_rgba8` wrapper, adversarial rejections, and the 0.3.3
    chunk-ordering / § 5.4 regressions incl. the unknown-ancillary control;
    plus the 0.5.3 tRNS repairs — a sub-byte grayscale key outside the sample
    range, and a palette tRNS placed **before** PLTE).
  - `subbyte.tcyr` — **143** (gray/palette at 1/2/4, multi-row padding,
    sub-byte ct2/4/6 reject).
  - `jpeg_noninterleaved.tcyr` — **237** (0.6.0; T.81 § A.2). Built on real
    libjpeg-turbo 3.2.0 files, with the regeneration recipe in the suite header
    so the corpus is reproducible. Its source pattern varies in **both** axes
    and gives each 8×8 block a distinct DC level, so a block placed in the wrong
    grid cell moves an asserted pixel instead of hiding in an equal sum. Cells:
    the 1x1 control anchored to `djpeg -nosmooth`; 2x1 / 2x2 / 4x4 each asserted
    **byte-for-byte** against that control; an **exhaustive sweep of all 16
    legal (H,V) pairs**; a 2x1 file with `DRI = 1` (the collapse redefines what
    an MCU is, and Ri counts MCUs); the interleaved 4:2:0 control that must not
    move; the ΣHj·Vj = 24 interleaved rejection that proves the conditioned cap
    is still live; the multi-scan and partially-interleaved deferrals; and the
    `Ns = 0` / `Ns > Nf` validity rejections.
- Reference verification is **embedded in the suite**, not a side script:
  the ImageMagick-encoded fixtures live inside `jpeg.tcyr` / `png.tcyr`, so
  a green `make test` *is* the reference cross-check.
- `make fuzz` (= `cyrius fuzz`, globbing `fuzz/*.fcyr`) → **8,072,804
  assertions, 0 failures** over **~2.3 M decode cases**, across 4 harnesses —
  one per format (4,467 lines). 0.6.0 added a **256-value sweep of the SOF0
  sampling byte** (every value of it is now a live input, including the illegal
  ones that must still reject) and 100,000 entropy-mutation cases behind a
  non-interleaved header — a shape whose entropy bytes never reached the
  bit-reader before 0.6.0, because that header rejected.
  `fuzz_gif.fcyr` carries an **LZW-stream-only**
  mutation mode that leaves the header intact so hostile bits reach the
  decompressor directly.
  This clears the roadmap's *10⁶ iterations clean* bar, not just the
  "a harness exists" bar.
  Each asserts **two** invariants: *survival* (the decoder returns on any
  byte sequence) and *contract* (failure returns 0 **and** sets `*err_out`;
  success leaves it 0) — the second being what a crash-only fuzzer misses,
  and what matters because mabda maps `ChitraErr` onto `GpuErr`.
  - `fuzz_png.fcyr` (294 L) — random bytes, **valid signature + random chunk
    stream**, bit-flipped fixture, full truncation sweep, degenerate lengths.
  - `fuzz_jpeg.fcyr` (566 L) — the same shapes plus **entropy-segment-only
    mutation** against the 8×8 and the real 16×16 gradient, so hostile bits
    reach the bit-reader / `DECODE` behind a valid header. Opens with a
    self-check asserting its fixtures decode and its entropy span is wide
    enough to mutate — the first draft silently exercised a 4-byte span, and
    a harness that no-ops is worse than none.
- `make bench` (= `cyrius bench tests/bcyr/chitra.bcyr`) → **17 benchmarks**,
  ~2 s (12 in 0.3.3, +3 BMP in 0.4.0, +1 GIF in 0.5.0 — the GIF case carries a
  small greedy **LZW encoder**, because a benchmark built from literal codes
  alone would never make the decoder walk a dictionary chain). The harness **generates its
  fixtures at realistic sizes**
  (256×256) rather than timing the 2×2..16×16 test fixtures, which would
  measure fixed overhead rather than throughput: PNG scanlines go through
  sankoch's `zlib_compress` so the real inflate + unfilter path runs, Adam7
  fixtures are interleaved with chitra's own pass-geometry helpers, and JPEG
  scans are bit-written over the Annex K DC table plus a compact AC table
  with real DC **and** AC coefficients per block. **Every fixture is
  decode-verified before it is timed**, and a failed verification aborts the
  run rather than reporting the cost of the error path.
  `scripts/bench-csv.sh` (= `make bench-record`) stamps results with
  timestamp/commit/branch into [`bench-history.csv`](../../bench-history.csv).
  Deliberately **not** in `make test-all` — benchmark numbers are host- and
  load-dependent, so gating CI on them would be a flake source.
- **Both v1.0 hardening gates are CLOSED as of 0.3.3** — the fuzz harness at
  10⁶ iterations clean, and the benchmark harness with committed CSV history.

### Decode baseline (this host, 256×256 = 65,536 px, minimum of 20 rounds)

| benchmark | ns/px | total |
|---|---|---|
| `jpeg_gray_256` | 43 | 2.93 ms |
| `png_rgba8_256` | 83 | 5.41 ms |
| `jpeg_ycbcr420_256` | 91 | 5.95 ms |
| `png_rgb8_256` | 99 | 6.52 ms |
| `jpeg_ycbcr422_256` | 108 | 7.09 ms |
| `png_rgba16_256` | 126 | 8.24 ms |
| `png_rgba8_adam7_256` | 128 | 8.38 ms |
| `jpeg_ycbcr444_256` | 145 | 9.49 ms |
| `png_gray8_256` | 153 | 10.03 ms |
| `png_palette8_256` | 154 | 10.10 ms |

Fixed cost at 16×16 (throughput-irrelevant — the icon case):
`png_rgba8` **60 µs**, `jpeg_gray` **16 µs**.

These are **host- and load-dependent**, and the per-pixel figure includes
inflate, whose cost depends on how the generated fixture compresses — compare
rows from the same host, not across hosts. Adam7 costs ~54 % over the
equivalent non-interlaced rgba8 decode, and JPEG grayscale is the cheapest
path in the library (no chroma planes, no upsample, no color convert).

## Quality gates

All green at 0.6.0 on cyrius 6.5.35:

| gate | command | result |
|---|---|---|
| link check | `make build` | OK, 588,976 bytes, no warnings |
| tests | `make test` | 2,719/2,719, 0 failures |
| fuzz | `make fuzz` | 8,072,804/8,072,804, 0 failures (~2.3 M cases) |
| bench | `make bench` | 17 benchmarks, fixtures self-verified, ~2 s |
| lint | `make lint` | 0 warnings (incl. `fuzz/*.fcyr` + `tests/bcyr/*.bcyr`) |
| fmt | `make fmt-check` | clean |
| vet | `make vet` | 1 dep, 0 untrusted, 0 missing |
| version | `make version-check` | consistent across VERSION, cyrius.cyml, CHANGELOG.md, README.md, `chitra_version()` |
| dist | `make dist` + `cyrius check --with-deps dist/chitra.cyr` | compiles clean |
| anchors | `./scripts/check-anchors.sh --suspect` | 58 anchors, 0 suspicious |

`make version-check` gained a fifth check at 0.3.2: it now packs `VERSION`
as `major*10000 + minor*100 + patch` and diffs it against the literal parsed
out of `chitra_version()` in `src/png.cyr`. That literal is hand-maintained,
and it is exactly what drifted in 0.3.1.

## Dependencies

- **stdlib**: `string`, `fmt`, `alloc`, `io`, `vec`, `str`, `syscalls`,
  `assert`, `bench`, `args`, `flags`, `sankoch`, `thread` (unchanged across
  0.3.0–0.4.0). `sankoch` = RFC 1950/1951 `zlib_decompress` + `crc32` +
  `adler32` (DEFLATE is sankoch's, not chitra's — it backs PNG IDAT inflate
  + chunk CRC); `thread` is the mutex pair sankoch's public-API lock wraps.
  The JPEG path takes **no** sankoch — its entropy (Huffman) decode is
  chitra's own. Resolved by `cyrius deps` into `lib/`.
- **Consumers** (external): **mabda** (`gpu_texture_load_png` — a plain dist
  dep `[deps.chitra]`, no C shim; `ChitraErr` ⇒ `GpuErr`), and **kii** —
  which consumes chitra back: its v1.2.0 PNG re-fold deleted its own
  decoder and adopted `dist/chitra.cyr` (see kii's ADR 0006). Lineage is a
  one-time fork of kii's `src/png.cyr` with **no live dependency** —
  bugfixes are manual backports in both directions.
- **Downstream pins are behind, and further behind than at 0.5.2** — the
  0.4.0–0.5.3 arc landed two formats and nine decode repairs while both pins
  stood still (chitra does not push, and neither pin auto-follows):
  - mabda `[deps.chitra] tag = "0.3.1"` → 0.5.3
  - kii `[deps.chitra] tag = "0.3.0"` → 0.5.3 (kii also carries
    `path = "../chitra"`, so a local kii build already resolves against this
    working tree)

  Every cut since 0.3.1 has been ABI-additive — nothing removed, no offset
  moved — so both bumps are mechanical. 0.5.3 raises the value of making them:
  the consumers gain BMP, GIF, the 0.3.3 decode repairs **and** the nine 0.5.3
  ones with no code change.

## Next

Per [`docs/development/roadmap.md`](roadmap.md):

- **0.6.1 — the byte-budget decode surface**
  ([ADR 0007](../adr/0007-byte-budget-surface-deferred.md)). Its named
  prerequisite is **lazy table allocation** in `chitra_jpeg_scan_markers`:
  today a 15-byte JPEG that is refused spends **22,096 bytes** (frame 320 +
  quant 2,048 + eight Huffman records 19,712, all before the SOF0 check that
  refuses it, and none of it memoized), so a probe routed through that function
  would make a 1-byte budget cost 22 KB before reporting "over budget". Fixing
  it drops the refusal cost to ~336 B for every caller, budgeted or not.
- **0.7.0 — JPEG multi-scan resumption**
  ([ADR 0006](../adr/0006-defer-jpeg-multiscan-resumption.md)): `Ns < Nf`,
  non-interleaved or partially interleaved. Measured reason it was not folded
  into 0.6.0: with the gate simply removed those files **decode**, to a wrong
  image, with no error raised.
- **API/ABI freeze** toward **v1.0** — the one real blocker. Two prerequisites
  remain of the original three: the missing `@public` markers on the (now four)
  signature predicates, and the misleading `INTERLACE` / `BIT_DEPTH` error-name
  strings. The third — whether 0.3.3's four newly-rejected input classes are
  the frozen behaviour — is **answered**: 0.6.0 reversed the § A.2 one, and the
  other three (the JPEG amplification cap, PNG's § 5.4 unknown-critical-chunk
  abort, and the § 5.6 / § 11.3.2 tRNS/PLTE ordering rules) are affirmed as
  frozen.
- **Known upstream issue**: calling the stdlib's `alloc_reset()` between decodes
  corrupts memory and breaks the next **PNG** decode, because sankoch memoizes
  its CRC-32 table as a raw pointer into the arena and cannot see the reset —
  chitra's per-decode `crc32_init_table()` then writes 16 KB through a dangling
  pointer. BMP and JPEG are unaffected. Reproduced and characterised in
  [architecture/005](../architecture/005-alloc-reset-sankoch-hazard.md); not
  fixable chitra-side (`lib/` is a vendored build artifact), so it is reported
  upstream. It matters because the arena boundary is currently chitra's *only*
  memory-reclamation story.
- `BI_JPEG` / `BI_PNG` inside a BMP is **out of scope permanently**, not
  deferred — it would have a decoder re-enter itself through
  attacker-controlled data.
- Four audits have landed —
  [2026-06-26 (PNG)](../audit/2026-06-26-audit.md),
  [2026-06-27 (JPEG)](../audit/2026-06-27-audit.md),
  [2026-08-23 (P-1 sweep, PNG + JPEG)](../audit/2026-08-23-audit.md) and
  [2026-08-24 (P-1 sweep, BMP + GIF)](../audit/2026-08-24-audit.md).
  **Every format has now had a line-by-line guard review**, which closes the
  gap this section carried through 0.5.2.
- **Accepted risk (PNG amplification), stated rather than quietly fixed**: a
  2,116-byte 1-bit PNG declaring 4096×4096 decodes to 64 MB, and
  `CHITRA_MAX_INFLATE_RATIO` does not catch it — that ratio bounds
  *inflated:IDAT*, while the final RGBA is 32× the inflated scanlines. It is
  **not** repaired, because that file is a complete, valid encoding of a solid
  image: the bomb and the legitimate image are the same file shape, and a ratio
  cap would reject valid PNGs. What distinguished the BMP/GIF cases is that
  those bombs supplied *nothing* — 2 and 4 bytes for 16.7 M pixels. The
  operative bound for PNG is `CHITRA_MAX_PIXELS`, and a caller decoding
  untrusted PNGs should treat 64 MB as the worst case rather than the file
  size.
- ~~Stale `src/error.cyr` enum comments~~ — **resolved in 0.3.2.**
- ~~Fuzz harness~~ / ~~Benchmark harness~~ — **both resolved in 0.3.3.**
- ~~BMP~~ — **shipped in 0.4.0.**
- ~~GIF~~ — **shipped in 0.5.0** (first frame only, ADR 0005).
- ~~BMP RLE8/RLE4~~ — **shipped in 0.5.1.**
- ~~BMP BITFIELDS / 16 bpp / V4-V5 headers~~ — **shipped in 0.5.2.** The BMP
  deferral list is now empty.
- ~~BMP + GIF audit~~ — **landed in 0.5.3**
  ([report](../audit/2026-08-24-audit.md)), with nine confirmed findings
  repaired and two amplification caps added.
