# chitra — Current State

> Refreshed every release. [`CLAUDE.md`](../../CLAUDE.md) is preferences /
> process / architecture (durable); this file is **state** (volatile) — it
> is the home for the version, sizes, and counts `CLAUDE.md` must not inline.

## Version

**0.2.1** — cut 2026-06-26. **Sub-byte bit depths 1/2/4 + Adam7 interlace.**
Completes the PNG bit-depth/interlace matrix (a direct continuation of the
0.2.0 depth-16 work) — chitra now decodes every depth × color-type ×
interlace combination the PNG spec permits. The depth-8/16 non-interlaced
path is unchanged (byte-for-byte). `chitra_version()` → **201**. **525
assertions** across 4 suites. See [`CHANGELOG.md`](../../CHANGELOG.md).

Released tags: 0.1.0, 0.2.0, 0.2.1 (SemVer; pre-1.0, the public surface is
still moving — no API freeze until v1.0).

## Toolchain

- **Cyrius pin**: `6.2.44` (in [`cyrius.cyml`](../../cyrius.cyml)
  `[package].cyrius`).
- **`lib/`**: vendored by `cyrius deps` from the 6.2.44 stdlib snapshot. It
  is a **real directory, never a symlink** — distlib concatenation depends
  on it (see [architecture/001](../architecture/001-lib-must-not-be-symlink.md)).

## Surface

chitra is a **library** — encoded image bytes → canonical RGBA8, zero GPU,
no C shim, no external binaries, no CLI/stdout/ANSI surface. Consumers link
`dist/chitra.cyr`. DEFLATE is **sankoch's** job, not chitra's.

### Public API (`@public`)

- `chitra_png_decode(src, len, err_out)` → `ChitraImage*` (0 on fail,
  `*err_out` set).
- `chitra_png_decode_rgba8(src, len, w_out, h_out)` → RGBA8 ptr (0 on fail) —
  convenience wrapper.
- `ChitraImage` accessors: `chitra_image_{width,height,pixels,channels,
  seen_iend,source_color_type}`; `chitra_image_free` (a documented no-op
  under the bump allocator).
- `chitra_version()` → `201` (`major*10000 + minor*100 + patch`).
- Error API: `chitra_err_new` / `chitra_err` / `chitra_err_code` /
  `chitra_err_detail` / `chitra_err_name` / `chitra_err_print_name` + enum
  `ChitraErrCode`.

`ChitraImage` is a **48-byte** record — `width`@0, `height`@8, `pixels`@16
(owned RGBA8, `w*h*4` bytes), `channels`@24 (=4), `seen_iend`@32 (1 = IEND
closed the stream, 0 = tolerated IEND-less clean end), `src_ctype`@40
(pre-normalization PNG color_type). The +32/+40 fields are **append-only** —
0.1.x offsets preserved, so mabda's accessors are unaffected.

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

### Decode rejection paths → `CHITRA_ERR_*`

`OK`=0, `SIGNATURE`=1, `TRUNCATED`=2, `BAD_CHUNK`=3, `UNSUPPORTED`=4,
`INFLATE`=5, `OOM`=6, `CRC`=7, `INTERLACE`=8, `BIT_DEPTH`=9, `DIMENSIONS`=10,
`FILTER`=11, `NO_IDAT`=12, `OTHER`=99. Every byte access is bounds-checked
against the input span, CRC-32 is verified per chunk, and the kii
decompression-bomb / lying-IHDR / dimension-ratio caps reject hostile inputs
loud (see [adr/0002](../adr/0002-security-model.md)).

> **Doc-drift note:** `src/error.cyr`'s enum comments for
> `CHITRA_ERR_INTERLACE` ("single-pass only") and `CHITRA_ERR_BIT_DEPTH`
> ("bit_depth != 8") are **stale** — 0.2.1 decodes Adam7 + all bit depths,
> so `INTERLACE` is now effectively unused and `BIT_DEPTH` only fires for a
> genuinely illegal combo (e.g. ct3+depth16, or ct2/4/6 at a sub-byte depth).

## Module map

Source under `src/` — flat domain modules in `[lib].modules` dependency
order. Stdlib includes live **only** in `lib.cyr`.

- `error.cyr` (88 L) — the `ChitraErr` model: the `ChitraErrCode` enum,
  the 16-byte `GpuErr`-compatible record, `chitra_err_*` constructors /
  accessors, and the error-name table. Dep-free.
- `png_chunks.cyr` (270 L) — the bounds-checked `(src, len)` cursor (every
  u8 / u32-BE / skip validated against `len` before access), the 8-byte
  signature check, chunk-type predicates (IHDR / IDAT / IEND / PLTE / tRNS),
  color-type→channels, the security ceilings (`MAX_DIM` / `MAX_PIXELS` /
  bomb ratio), and the internal `ChitraPngRaw` handoff struct + accessors.
- `png_filter.cyr` (578 L) — the five § 9 unfilter predictors
  (None / Sub / Up / Average / Paeth), the Adam7 7-pass deinterlace, and
  `chitra_png_parse_raw`: the two-pass chunk walk (CRC-32 each chunk via
  sankoch, parse IHDR, capture PLTE/tRNS spans, concat IDAT, inflate with
  the bomb caps, unfilter into the scanline buffer). Every failure returns
  a `ChitraErr`, never an OOB read.
- `png_color.cyr` (344 L) — `chitra_png_color_to_rgba8`: the canonical-RGBA8
  normalization pass (the genuinely new code over the kii fork) — grayscale
  → (g,g,g,255), RGB → (r,g,b,255), palette → PLTE RGB + per-entry tRNS
  alpha, gray+alpha → (g,g,g,a), RGBA passthrough, with tRNS keying for
  types 0/2 and sub-byte / 16-bit sample handling. PLTE/tRNS are resolved
  from the original `src` via the captured (offset, length) spans,
  re-validated defensively.
- `png.cyr` (122 L) — the public decode API (`chitra_png_decode` /
  `chitra_png_decode_rgba8`), the 48-byte `ChitraImage` + accessors,
  `chitra_image_free`, and `chitra_version`.

Include chain: `lib.cyr` (52 L) pulls the stdlib set then
`error.cyr` → `png_chunks.cyr` → `png_filter.cyr` → `png_color.cyr` →
`png.cyr` (the order in `[lib].modules`).

## Sizes

- `dist/chitra.cyr` — **~61 KB** (62,010 bytes / 1,421 lines), regenerated by
  `cyrius distlib` (= `make dist`). This is the artifact consumers link.
- `build/chitra_smoke` — **~341 KB**, built from `programs/smoke.cyr` via
  `make build`. It only proves the include chain compiles + links clean —
  chitra is a library, there is no real CLI behind it.

## Tests + bench

- `make test` (globs `tests/tcyr/*.tcyr`; each is a standalone `main()`) →
  **525 assertions, all pass** across 4 suites:
  - `error.tcyr` — **20** (error codes, `chitra_err_*` accessors, name
    round-trips, `chitra_version`).
  - `interlace.tcyr` — **35** (Adam7 cross-checked against the trusted
    non-interlaced decode for 7 color/depth/odd-dimension cases).
  - `png.tcyr` — **327** (cursor bounds, all five unfilter predictors, one
    embedded fixture per color type at depth 8/16, palette+tRNS / keyed-color
    fixtures, `_rgba8` wrapper, adversarial rejections).
  - `subbyte.tcyr` — **143** (gray/palette at 1/2/4, multi-row padding,
    sub-byte ct2/4/6 reject).
- **No in-tree fuzz harness and no benchmark harness yet** — this is a real
  gap. The README calls the decoder "fuzz-corpus-tested" from its kii
  lineage (the core it forks from is fuzz-hardened), but chitra itself ships
  no `.fcyr` / `.bcyr` file. Decode latency and throughput are **not yet
  measured** in-repo.

## Dependencies

- **stdlib**: `string`, `fmt`, `alloc`, `io`, `vec`, `str`, `syscalls`,
  `assert`, `bench`, `args`, `flags`, `sankoch`, `thread`. `sankoch` =
  RFC 1950/1951 `zlib_decompress` + `crc32` + `adler32` (DEFLATE is
  sankoch's, not chitra's); `thread` is the mutex pair sankoch's public-API
  lock wraps. Resolved by `cyrius deps` into `lib/`.
- **Consumers** (external): **mabda** (`gpu_texture_load_png` — a plain dist
  dep `[deps.chitra]`, no C shim; `ChitraErr` ⇒ `GpuErr`), and **kii** —
  which now consumes chitra back: its v1.2.0 PNG re-fold deleted its own
  813-line decoder and adopted `dist/chitra.cyr` (see kii's ADR 0006).
  Lineage is a one-time fork of kii's `src/png.cyr` with **no live
  dependency** — bugfixes are manual backports in both directions.

## Next

Per [`docs/development/roadmap.md`](roadmap.md):

- The 0.2.x audit landed — see
  [`docs/audit/2026-06-26-audit.md`](../audit/2026-06-26-audit.md).
- **Fuzz harness** + **benchmark harness** (close the in-tree gaps above —
  fuzz-corpus the byte-buffer boundary, measure decode latency/throughput).
- **JPEG** (0.3+) — Huffman + IDCT + chroma upsample. The format-agnostic
  name already leaves room for JPEG/GIF/BMP to join without a rename.
- **API freeze** toward **v1.0** (the surface is still moving pre-1.0).
- Stale `src/error.cyr` enum comments (`INTERLACE` / `BIT_DEPTH`) to be
  refreshed to the 0.2.1 reality.
