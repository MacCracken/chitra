# chitra — Current State

> **Last refresh**: 2026-08-23 (0.3.3) | **Refresh cadence**: every release.
> [`CLAUDE.md`](../../CLAUDE.md) is preferences / process / architecture
> (durable); this file is **state** (volatile) — it is the home for the
> version, sizes, and counts `CLAUDE.md` must not inline.

## Version

**0.3.3** — cut 2026-08-23. **P-1 audit, hardening and repair cut.** A
ten-lens adversarial sweep of both decode paths, each finding put to two
independent skeptics, plus the repair of everything confirmed and chitra's
**first in-tree fuzz harnesses**. **No memory-safety defect was found** — the
entropy bounds, Adam7 geometry, plane-write indices, signed-shift discipline
and palette/span validation all verified correct. The repairs are correctness,
conformance, resource and defence-in-depth: full-width depth-16 tRNS keying,
rejection of single-component non-interleaved JPEG scans, a JPEG
decompression-bomb cap, a non-null `chitra_err_new`, T.81 fill-byte handling,
ZRL overrun rejection, non-segment marker rejection, and the PNG § 5.4 /
§ 5.6 chunk-ordering guards. Every repair carries a regression test verified
to fail against the pre-repair code. `chitra_version()` → **303**.
**784 assertions** across 5 suites plus **3,464,838 fuzz assertions** over
~10⁶ decode cases, 0 failures. Adds the **benchmark harness** as well, so
**both** remaining v1.0 hardening gates close in this cut. See [`CHANGELOG.md`](../../CHANGELOG.md) and
[`docs/audit/2026-08-23-audit.md`](../audit/2026-08-23-audit.md).

Released tags: 0.1.0, 0.2.0, 0.2.1, 0.3.0, 0.3.1, 0.3.2 (SemVer; pre-1.0, the
public surface is still moving — no API freeze until v1.0). **0.3.3 is being
cut now and is not yet tagged.**

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

Format-agnostic:

- `chitra_image_decode(src, len, err_out)` → `ChitraImage*` — the
  **signature-sniffing router** ([`jpeg.cyr:424`](../../src/jpeg.cyr)): the
  8-byte PNG magic → `chitra_png_decode`; else the JPEG SOI marker →
  `chitra_jpeg_decode`; else **`0` with `*err_out` = `CHITRA_ERR_SIGNATURE`**.
  It does *not* fall through to the PNG decoder for unrecognized bytes — an
  unknown format is rejected at the router. The single entry a consumer
  should reach for when it does not know the format up front.

Shared:

- `ChitraImage` accessors: `chitra_image_{width,height,pixels,channels,
  seen_iend,source_color_type}`; `chitra_image_free` (a documented no-op
  under the bump allocator).
- `chitra_version()` → **`303`** (`major*10000 + minor*100 + patch`).
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

- `error.cyr` (126 L) — the `ChitraErr` model: the `ChitraErrCode` enum
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
- `png_filter.cyr` (610 L) — the five § 9 unfilter predictors
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
- `jpeg_markers.cyr` (532 L) — `chitra_jpeg_check_signature`,
  `chitra_jpeg_scan_markers` (SOI → segment walk → SOS, parsing SOF0 frame
  header / DQT / DHT / DRI and **rejecting** non-baseline modes), the
  `ChitraJpegFrame` storage, and the JPEG security guards: sampling factors
  clamped 1..4 (rejecting 0 — the CVE-2018-11212 divide-by-zero), duplicate
  component ids rejected, ΣHi·Vi ≤ `MAX_BLOCKS_PER_MCU` (10) enforced before
  MCU geometry, `MAX_DIM`/`MAX_PIXELS` re-checked, plus `MAX_COMPONENTS`=4,
  `MAX_SAMP_FACTOR`=4, `MAX_QUANT_TABLES`=4, `MAX_HUFF_TABLES`=4.
- `jpeg.cyr` (470 L) — the public JPEG decode API (`chitra_jpeg_decode` /
  `chitra_jpeg_decode_rgba8`) and the format-sniffing `chitra_image_decode`
  router; `_jpeg_parse_sos` (scan header — Td/Ta selectors, baseline
  Ss=0/Se=63/Ah=Al=0), the subsampling-aware `_jpeg_decode_scan` MCU loop
  (max_h×max_v data units, per-component subsampled planes, box upsample),
  and the BT.601 YCbCr→RGB color pass → `ChitraImage`.

Include chain: `lib.cyr` (64 L) pulls the stdlib set then
`error.cyr` → `png_chunks.cyr` → `png_filter.cyr` → `png_color.cyr` →
`png.cyr` → `jpeg_huffman.cyr` → `jpeg_idct.cyr` → `jpeg_markers.cyr` →
`jpeg.cyr` (the order in `[lib].modules`). Domain-module total: **3,044 L**
across 9 files, plus `lib.cyr`.

## Sizes

- `dist/chitra.cyr` — **~130 KB** (133,286 bytes / 3,075 lines; `cyrius
  distlib` reports 3,044 code lines), regenerated by `cyrius distlib`
  (= `make dist`). This is the artifact consumers link. The 0.3.2 diff
  against 0.3.1 is the version stamp, the `cyrfmt` reflow, the
  `chitra_version()` literal, and two enum comments — **no signature,
  struct offset, or symbol changed**, so mabda and kii are ABI-unaffected.
  0.3.3 adds no public symbol either: every repair is internal, so the
  0.3.2 → 0.3.3 bump is likewise ABI-neutral.
- `dist/chitra.deps` — the 13-leaf stdlib sidecar consumers resolve against.
- `build/chitra_smoke` — **~547 KB** (559,656 bytes), built from
  `programs/smoke.cyr` (19 L) via `make build`. It only proves the include chain compiles + links clean — chitra is
  a library, there is no real CLI behind it.

## Tests + bench

- `make test` (globs `tests/tcyr/*.tcyr`; each is a standalone `main()`) →
  **784 assertions, all pass** across 5 suites:
  - `error.tcyr` — **20** (error codes, `chitra_err_*` accessors, name
    round-trips, `chitra_version` → 302).
  - `interlace.tcyr` — **35** (Adam7 cross-checked against the trusted
    non-interlaced decode for 7 color/depth/odd-dimension cases).
  - `jpeg.tcyr` — **226** (marker scan + non-baseline rejection, SOF0
    components + DQT, Huffman table build vs Annex K.3.3, entropy block
    decode, zig-zag + IDCT + dequant known-answers, end-to-end grayscale /
    YCbCr 4:4:4 / 4:2:0 / restart-interval decodes, and a real
    ImageMagick-encoded 16×16 baseline gradient decoded **byte-identical**,
    plus the 0.3.3 non-interleaved / bomb-cap / non-segment-marker
    regressions).
  - `png.tcyr` — **360** (cursor bounds, all five unfilter predictors, one
    embedded fixture per color type at depth 8/16, palette+tRNS / keyed-color
    fixtures, `_rgba8` wrapper, adversarial rejections, and the 0.3.3
    chunk-ordering / § 5.4 regressions incl. the unknown-ancillary control).
  - `subbyte.tcyr` — **143** (gray/palette at 1/2/4, multi-row padding,
    sub-byte ct2/4/6 reject).
- Reference verification is **embedded in the suite**, not a side script:
  the ImageMagick-encoded fixtures live inside `jpeg.tcyr` / `png.tcyr`, so
  a green `make test` *is* the reference cross-check.
- `make fuzz` (= `cyrius fuzz`, globbing `fuzz/*.fcyr`) → **3,464,838
  assertions, 0 failures** over **~1,000,237 decode cases** (500,082 PNG +
  500,155 JPEG) in **~10 s**, across 2 harnesses (860 lines), new in 0.3.3.
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
- `make bench` (= `cyrius bench tests/bcyr/chitra.bcyr`) → **12 benchmarks**,
  ~2 s, new in 0.3.3. The harness **generates its fixtures at realistic sizes**
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

All green at 0.3.3 on cyrius 6.5.35:

| gate | command | result |
|---|---|---|
| link check | `make build` | OK, 559,656 bytes, no warnings |
| tests | `make test` | 784/784, 0 failures |
| fuzz | `make fuzz` | 3,464,838/3,464,838, 0 failures (~10⁶ cases, ~10 s) |
| bench | `make bench` | 12 benchmarks, fixtures self-verified, ~2 s |
| lint | `make lint` | 0 warnings, 0 untracked deferrals (now incl. `fuzz/*.fcyr`) |
| fmt | `make fmt-check` | clean |
| vet | `make vet` | 1 dep, 0 untrusted, 0 missing |
| version | `make version-check` | consistent across VERSION, cyrius.cyml, CHANGELOG.md, README.md, `chitra_version()` |
| dist | `make dist` + `cyrius check --with-deps dist/chitra.cyr` | compiles clean |

`make version-check` gained a fifth check at 0.3.2: it now packs `VERSION`
as `major*10000 + minor*100 + patch` and diffs it against the literal parsed
out of `chitra_version()` in `src/png.cyr`. That literal is hand-maintained,
and it is exactly what drifted in 0.3.1.

## Dependencies

- **stdlib**: `string`, `fmt`, `alloc`, `io`, `vec`, `str`, `syscalls`,
  `assert`, `bench`, `args`, `flags`, `sankoch`, `thread` (unchanged across
  0.3.0–0.3.2). `sankoch` = RFC 1950/1951 `zlib_decompress` + `crc32` +
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
- **Downstream pins are behind** and must be bumped *after* the 0.3.2 tag
  lands (chitra does not push, and neither pin auto-follows):
  - mabda `[deps.chitra] tag = "0.3.1"` → 0.3.3
  - kii `[deps.chitra] tag = "0.3.0"` → 0.3.3 (kii also carries
    `path = "../chitra"`, so a local kii build already resolves against this
    working tree)

  The 0.3.3 dist is ABI-identical to 0.3.1's, so both bumps are mechanical
  — but both consumers gain the 0.3.3 decode repairs, so the bump is worth
  making rather than deferring.

## Next

Per [`docs/development/roadmap.md`](roadmap.md):

- Three audits have landed —
  [2026-06-26 (PNG)](../audit/2026-06-26-audit.md),
  [2026-06-27 (JPEG)](../audit/2026-06-27-audit.md) and
  [2026-08-23 (P-1 sweep, both paths)](../audit/2026-08-23-audit.md).
- **Both v1.0 hardening gates closed in 0.3.3** — the fuzz harness at 10⁶
  iterations clean, and the benchmark harness with committed CSV history.
  What stands between chitra and a v1.0 freeze is now the **API/ABI freeze
  itself** and the next format, not hardening infrastructure.
- **Non-interleaved JPEG scans** — 0.3.3 *rejects* single-component scans
  with non-unit sampling factors rather than mis-rendering them
  (`CHITRA_ERR_UNSUPPORTED`). Implementing the T.81 § A.2 layout so they
  decode is tracked future work.
- **GIF / BMP** — the format-agnostic name and the `chitra_image_decode`
  router already leave room for them to join without a rename.
- **API freeze** toward **v1.0** (the surface is still moving pre-1.0). Two
  items to settle at the freeze: the missing `@public` markers on the two
  signature predicates, and the misleading `INTERLACE` / `BIT_DEPTH` error
  name strings (both described under *Surface* above).
- ~~Stale `src/error.cyr` enum comments~~ — **resolved in 0.3.2.**
- ~~Fuzz harness~~ — **resolved in 0.3.3.**
- ~~Benchmark harness~~ — **resolved in 0.3.3.**
