# chitra

Version: 0.2.1

**chitra** (चित्र — Sanskrit: *image / picture*) is a pure-Cyrius CPU
raster image decoder, a sibling AGNOS package in the mould of `sakshi` /
`patra` / `samvada`. It turns encoded image bytes into canonical RGBA8
pixels with no GPU, no C shim, and no external binaries.

The name is deliberately format-agnostic so JPEG / GIF / BMP can join
later without a rename.

## Scope

- **v0.1.0 — PNG → canonical RGBA8.** Signature + chunk parse (IHDR /
  IDAT-concat / IEND / PLTE / tRNS), color types 0/2/3/4/6 at bit depth
  8, IDAT inflate via the stdlib `sankoch` (RFC 1950/1951
  `zlib_decompress`), the five unfilter predictors, canonical-RGBA8
  output, and the kii security guards (decompression-bomb caps,
  lying-IHDR rejection, ratio caps). No Adam7 interlace (single-pass
  only). The decoder is complete and inherits kii's fuzz-hardening (a
  chitra-native fuzz harness is a tracked v1.0 gap) — the public
  entry points are `chitra_png_decode` (→ an owned RGBA8 `ChitraImage`)
  and the `chitra_png_decode_rgba8` convenience wrapper.
- **v0.2.0 — bit depth 16 + hardening parity.** Adds 16-bit decode for
  color types 0/2/4/6 (each big-endian sample truncates to its high byte;
  color_type 3 + depth 16 stays rejected per spec § 11.2.2). Plus the kii
  guard-parity backport: an IEND-must-be-zero-length check, a distinct
  `CHITRA_ERR_NO_IDAT` code (split out of `_DIMENSIONS`), and two additive
  `ChitraImage` fields — `chitra_image_seen_iend` (1 = IEND closed the
  stream, 0 = tolerated IEND-less end) and `chitra_image_source_color_type`
  (the pre-normalization color_type). The struct widen is ABI-additive
  (width/height/pixels/channels keep their offsets — mabda-safe).
- **v0.2.1 — sub-byte depths 1/2/4 + Adam7 interlace.** Completes the PNG
  depth × color-type × interlace matrix. Sub-byte (MSB-first, byte-padded)
  for grayscale + palette (the only types the spec allows below depth 8);
  Adam7's 7 passes are deinterlaced into the same dense buffer the
  non-interlaced path yields, so the color pass is interlace-agnostic.
  Verified against ImageMagick + an interlaced-vs-non-interlaced
  cross-check (525-assertion suite).
- **Staged (tracked, not silently dropped):** **JPEG** (Huffman + IDCT +
  chroma upsample) → 0.3+. PNG is now feature-complete.

## Relationships

- **mabda** deps chitra (a plain dist dep — `[deps.chitra]`, no C shim)
  and uses it for `gpu_texture_load_png`. A decode failure maps onto
  `GPU_ERR_IMAGE_DECODE`; `ChitraErr` is a 16-byte record
  layout-compatible with mabda's `GpuErr` for that mapping.
- **kii** (the terminal image → ANSI/ASCII viewer) is where chitra's
  PNG core is **forked from** — kii's `src/png.cyr` is a proven,
  fuzz-hardened, W3C-compliant decoder. chitra is a one-time fork plus
  real new code: a byte-buffer I/O boundary (mabda hands over in-memory
  bytes, not a path) and a canonical-RGBA8 normalization pass (+ tRNS).
  No live dependency between the two; kii-bugfix backport is manual.

## Dependencies

- **Cyrius stdlib** — `string`, `fmt`, `alloc`, `io`, `vec`, `str`,
  `syscalls`, `assert`, `bench`, `args`, `flags`, plus **`sankoch`**
  (zlib inflate + CRC32) and **`thread`** (sankoch's mutex pair).
  Resolved by `cyrius deps` into `lib/`.

All deps are pinned in `cyrius.cyml`; the toolchain pin is
`cyrius = "6.2.44"`.

## Quick Start

```bash
cyrius deps                                   # resolve stdlib + sankoch into lib/
cyrius build programs/smoke.cyr build/chitra_smoke   # link-check
make test                                     # CPU assertions across tests/tcyr/
cyrius distlib                                # → dist/chitra.cyr
```

## Design

See the proposal in the mabda repo:
`docs/proposals/v3.3-chitra-png-decoder-package.md` (the v3.3 "Asset
Loading" arc, Phase AL.P0).

## License

GPL-3.0-only.
