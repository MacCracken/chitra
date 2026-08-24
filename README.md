# chitra

Version: 0.7.1

**chitra** (चित्र — Sanskrit: *image / picture*) is a pure-Cyrius CPU
raster image decoder, a sibling AGNOS package in the mould of `sakshi` /
`patra` / `samvada`. It turns encoded image bytes into canonical RGBA8
pixels with no GPU, no C shim, and no external binaries.

The name is deliberately format-agnostic, and all four common raster formats
now share it — PNG, JPEG, BMP and GIF — with room for more without a rename.

## What it decodes

Four formats, one output contract: encoded bytes in, canonical **RGBA8** out —
always 4 channels, always at the source dimensions, whatever went in.

| Format | Coverage |
|---|---|
| **PNG** | Every spec-legal bit depth × color type: 1/2/4/8/16 across types 0/2/3/4/6 (§ 11.2.2 Table 11.1), plus **Adam7 interlace** for every cell. PLTE palettes, tRNS transparency (keyed and per-entry). IDAT inflate via `sankoch`. |
| **JPEG** | JFIF **baseline** (SOF0 sequential Huffman, 8-bit): grayscale + YCbCr, chroma subsampling 4:4:4 / 4:2:2 / 4:2:0 and general `Hi,Vi` box upsampling, DRI / RST0–7 restart markers, and — since 0.6.0 — the T.81 § A.2 **non-interleaved** layout for a one-component frame (any `H`,`V` in 1..4). Verified **byte-identical to `djpeg -nosmooth`** across the sampling matrix. |
| **BMP** | `BI_RGB` at 1 / 4 / 8 bpp (palette), 16 / 24 / 32 bpp, plus **`BI_RLE8` / `BI_RLE4`** run-length and **`BI_BITFIELDS`** channel masks; CORE / INFO / V2 / V3 / **V4** / **V5** headers; bottom-up **and** top-down. Verified **identical to ImageMagick**. |
| **GIF** | GIF87a/89a, LZW, global **and** local color tables, 4-pass row interlace, transparency from a Graphic Control Extension. **First frame only** — see [ADR 0005](docs/adr/0005-gif-first-frame-only.md). Verified against two independent decoders. |

```
fn chitra_image_decode(src, len, err_out): i64
fn chitra_image_decode_budget(src, len, max_bytes, err_out): i64
```

One entry point sniffs the signature — PNG magic, then JPEG SOI, then BMP
`BM`, then GIF `GIF8?a` — and routes. Bytes matching none of the four are
rejected with `CHITRA_ERR_SIGNATURE`; it does not fall through to a default
decoder. If you already know the format, `chitra_{png,jpeg,bmp,gif}_decode`
have the identical shape, each with a `_rgba8` convenience wrapper.

The budgeted variant (0.6.1) refuses **before beginning** any decode whose
RGBA8 output would exceed `max_bytes` — a refusal allocates 16 bytes. It bounds
the output, not the peak, and the function's own comment says exactly what it
does not cover, because a memory guarantee that is not exact is not a
guarantee. It matters more than it sounds: the bump allocator never frees, so
without it a caller decoding untrusted input has no ceiling at all.

The one place that uniformity costs something: an **animated** GIF returns its
first frame, with no indication that more existed. If frame 1 is a background
plate — common in optimised animations — that is what you get. The reasoning
and the shape a future multi-frame surface would take are in ADR 0005.

## What it refuses, and why that is the point

chitra **rejects loud rather than half-decoding**. A decoder that mis-renders
one cell of its matrix is worse than one that declines it cleanly, so every
unsupported mode gets its own `CHITRA_ERR_*` code instead of a guess:
progressive / arithmetic / 12-bit / hierarchical / CMYK JPEG; an unrecognised
BMP DIB header size; and any illegal PNG depth × color-type pair. BMP's
deferral list is now empty — everything it once postponed decodes.

One refusal is worth naming because the file is **valid**: a baseline JPEG whose
scans do not each carry every frame component (what `cjpeg -scans` emits) is
deferred, not malformed, and says so with `CHITRA_ERR_UNSUPPORTED`. 0.6.0
implements the one-component half of that layout and schedules the rest —
[ADR 0006](docs/adr/0006-defer-jpeg-multiscan-resumption.md) records what a
correct implementation owes, and why relaxing the check without it would make
those files decode to a *wrong image with no error raised*.

Two refusals are permanent rather than deferred: **encoding** (chitra is
decode-only, in both directions of that sentence) and **`BI_JPEG` / `BI_PNG`
inside a BMP**, which would have a decoder re-enter itself through
attacker-controlled data.

## Hardening

Untrusted bytes are the whole input surface, so the guards are the product:

- **Bounds on every read**, a per-chunk CRC-32 on PNG, and
  decompression-bomb caps on **every** compressed path — PNG's inflate ratio,
  JPEG's output:input amplification cap (which JPEG needs *more*, because its
  bit-reader zero-pads past end-of-data and so needs no payload at all to
  drive a full-size decode), and, since 0.5.3, the same for BMP-RLE and GIF,
  where a 1,082-byte file and a 797-byte file respectively decoded into
  ~64 MB. PNG's remaining amplification case is documented as **accepted
  risk** rather than capped, because there the bomb and a legitimate solid
  image are the same file shape.
- **`make fuzz`** — one harness per format, **~2.3 M adversarial decode cases,
  8,072,804 assertions, 0 failures**. They assert *both* that the decoder
  survives and that it honours the documented `(0, *err_out set)` contract —
  the invariant a crash-only fuzzer misses.
- **`make bench`** — 17 decode benchmarks with committed
  [CSV history](bench-history.csv). BMP **6 ns/px** (RLE8 **18**, where
  per-opcode branching costs more than the bytes it saves), JPEG grayscale and
  GIF **43 ns/px**, PNG RGBA8 **83 ns/px** at 256×256.
- A 0.6.1 sweep for deferred and half-done work catalogued **84 findings** and
  turned up three defects on files standard tools produce: a `cjpeg -rgb` JPEG
  decoded hue-rotated with no error, an 81-byte GIF was wrongly refused, and a
  16 KB JPEG padded with skipped segments allocated **117 MB**. All fixed; the
  rest are scheduled in the roadmap's 0.7.x arc or named as scope guards.
- **Four security audits** in [`docs/audit/`](docs/audit/) — one per decode
  path, the last (0.5.3) covering BMP and GIF. None found a memory-safety
  defect. What they did find is the reason the reference cross-checks are not
  optional: **seven of nine findings in the 0.5.3 sweep were silent wrong
  output** — a real 32-bpp file decoding with red and blue swapped, a V4 file
  decoding fully transparent — that millions of fuzz cases had passed over,
  because none of them crash. Every one was caught by decoding the same bytes
  with ImageMagick.

Per-release detail — including the four input classes 0.3.3 began rejecting
deliberately — is in [`CHANGELOG.md`](CHANGELOG.md). Sequencing is in
[`docs/development/roadmap.md`](docs/development/roadmap.md): **0.6.0**
deferred JPEG geometry plus a streaming API, then the v1.0 API/ABI freeze.
All four formats are now feature-complete for their scope.

## Relationships

- **mabda** deps chitra (a plain dist dep — `[deps.chitra]`, no C shim)
  and uses it for `gpu_texture_load_png`. A decode failure maps onto
  `GPU_ERR_IMAGE_DECODE`; `ChitraErr` is a 16-byte record
  layout-compatible with mabda's `GpuErr` for that mapping.
- **kii** (the terminal image → ANSI/ASCII viewer) is both chitra's
  **origin and a consumer**. chitra's PNG core is a one-time fork of kii's
  proven, fuzz-hardened, W3C-compliant `src/png.cyr`, plus real new code:
  a byte-buffer I/O boundary (mabda hands over in-memory bytes, not a path)
  and a canonical-RGBA8 normalization pass (+ tRNS). kii then **adopted
  chitra back** — its v1.2.0 PNG re-fold deleted its own decoder in favour
  of `dist/chitra.cyr`, and v1.4.0 wired the JPEG path through
  `chitra_image_decode`. The fork carries **no live dependency**, so a
  decode bugfix is a manual backport in whichever direction it is found.

## Dependencies

- **Cyrius stdlib** — `string`, `fmt`, `alloc`, `io`, `vec`, `str`,
  `syscalls`, `assert`, `bench`, `args`, `flags`, plus **`sankoch`**
  (zlib inflate + CRC32) and **`thread`** (sankoch's mutex pair).
  Resolved by `cyrius deps` into `lib/`.

All deps are pinned in `cyrius.cyml`; the toolchain pin is
`cyrius = "6.5.35"`.

## Quick Start

```bash
cyrius deps          # resolve stdlib + sankoch + thread into lib/
make build           # link-check the include chain (→ build/chitra_smoke)
make test            # 2833 assertions across tests/tcyr/
make fuzz            # ~2.2 M adversarial decode cases (fuzz/*.fcyr)
make bench           # 17 decode benchmarks (tests/bcyr/chitra.bcyr)
make dist            # regenerate dist/chitra.cyr — the artifact consumers link
make test-all        # version-check + dist + test + fuzz (the pre-release gate)
```

`make bench` is deliberately **not** part of `test-all`: benchmark numbers are
host- and load-dependent, so gating a correctness run on them would only
manufacture flakes. Record a series with `make bench-record`.

## Design

Start with [`docs/development/state.md`](docs/development/state.md) for the
current surface, sizes and decode matrix, then:

- [`docs/architecture/`](docs/architecture/) — the non-obvious constraints
  (why `lib/` must not be a symlink, why domain modules stay flat for
  `distlib`, why the bump allocator never frees, how the JPEG pipeline fits
  together). Note the bump allocator is not a footnote: `chitra_image_free`
  is a documented no-op, so decode cost is cumulative for the process — which
  is why the amplification caps exist.
- [`docs/adr/`](docs/adr/) — the decisions and their alternatives (forking
  kii's decoder, the security model, mabda ABI compatibility, the JPEG decode
  model, GIF first-frame-only).
- [`docs/guides/getting-started.md`](docs/guides/getting-started.md) —
  consuming chitra from another package.
- [`docs/audit/`](docs/audit/) — the security audit reports.
- [`docs/sources.md`](docs/sources.md) — every spec section chitra implements,
  mapped to the file that implements it, including the three places the
  formats leave something undefined and chitra had to choose.

The original package proposal lives in the mabda repo
(`docs/proposals/v3.3-chitra-png-decoder-package.md`, the v3.3 "Asset
Loading" arc, Phase AL.P0); chitra's own JPEG design note is
[`docs/proposals/jpeg-baseline-decoder.md`](docs/proposals/jpeg-baseline-decoder.md).

## License

GPL-3.0-only.
