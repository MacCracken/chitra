# chitra

Version: 1.4.0

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
| **JPEG** | JFIF **baseline** (SOF0) and **progressive** (SOF2, 1.4.0 — spectral selection, successive approximation, 16-bit quant tables), 8-bit Huffman: grayscale + YCbCr, chroma subsampling 4:4:4 / 4:2:2 / 4:2:0 / 4:4:0 and general `Hi,Vi`, upsampled with libjpeg-turbo's **interpolated ("fancy") filters** (1.4.0), DRI / RST0–7 restart markers, RGB components via the Adobe APP14 transform, and the full T.81 § A.2 scan model — interleaved, **non-interleaved and partially interleaved**, single- or multi-scan. **CMYK / YCCK** through its own entry, as CMYK samples (1.4.0). Verified **byte-identical to `djpeg`** (and to libjpeg's own CMYK output) on a 397-file corpus. |
| **BMP** | `BI_RGB` at 1 / 4 / 8 bpp (palette), 16 / 24 / 32 bpp, plus **`BI_RLE8` / `BI_RLE4`** run-length and **`BI_BITFIELDS`** channel masks; CORE / **OS/2 2.x CORE2** / INFO / V2 / V3 / **V4** / **V5** headers (accepted DIB sizes 12/40/52/56/64/108/124); bottom-up **and** top-down. Verified against ImageMagick, and deliberately different in two places since 1.4.0 ([ADR 0011](docs/adr/0011-bmp-samples-mean-what-the-format-says.md)): a channel narrower than 8 bits rounds to the nearest level where ImageMagick bit-replicates (1 level, on 14 of the 96 five- and six-bit levels), and a 32-bpp `BI_RGB` image is opaque, its unused fourth byte not read as alpha. |
| **GIF** | GIF87a/89a, LZW, global **and** local color tables, 4-pass row interlace, transparency from a Graphic Control Extension. **First frame only** — see [ADR 0005](docs/adr/0005-gif-first-frame-only.md). Verified against two independent decoders. |

```
fn chitra_image_decode(src, len, err_out): i64
fn chitra_image_decode_budget(src, len, max_bytes, err_out): i64
fn chitra_image_decode_budget_via(a, src, len, max_bytes, err_out): i64     # 1.4.0
fn chitra_jpeg_decode_cmyk(a, src, len, max_bytes, err_out): i64            # 1.4.0
```

One entry point sniffs the signature — PNG magic, then JPEG SOI, then BMP
`BM`, then GIF `GIF8?a` — and routes. Bytes matching none of the four are
rejected with `CHITRA_ERR_SIGNATURE`; it does not fall through to a default
decoder. If you already know the format, `chitra_{png,jpeg,bmp,gif}_decode`
have the identical shape, each with a `_rgba8` convenience wrapper.

The budgeted variant (0.6.1) refuses **before beginning** any decode whose
RGBA8 output would exceed `max_bytes` — a refusal allocates 16 bytes, the `ChitraErr` itself, for PNG, JPEG and GIF, and 128 for BMP. It bounds
the output, not the peak, and the function's own comment says exactly what it
does not cover, because a memory guarantee that is not exact is not a
guarantee. Since 1.4.0 **the budget governs size**: under it, an image past the
fixed 4096 × 4096 cap — an 8K screenshot, three 4K monitors side by side —
decodes if its output fits the budget, while `chitra_image_decode` keeps the
fixed caps.

`chitra_image_decode_budget_via` (1.4.0) is the same decode with every
allocation taken from a caller's stdlib `Allocator` (a free-list, a
per-request arena): every working buffer goes back before it returns, and
`chitra_image_free` returns the image and its pixels. Through 1.3.x every
decode's memory was lost for the life of the process — the bump allocator
never frees — which a long-running service cannot live with.
`chitra_jpeg_decode_cmyk` returns a CMYK or YCCK JPEG's **C, M, Y, K
samples** (YCCK converted exactly as libjpeg converts it), with the same
allocator-and-budget shape; turning them into RGB is a colour-management
decision chitra leaves to the caller ([ADR 0014](docs/adr/0014-cmyk-samples-not-colours.md)).

The one place that uniformity costs something: an **animated** GIF returns its
first frame, with no indication that more existed. If frame 1 is a background
plate — common in optimised animations — that is what you get. The reasoning
and the shape a future multi-frame surface would take are in ADR 0005.

## What it refuses, and why that is the point

chitra **rejects loud rather than half-decoding**. A decoder that mis-renders
one cell of its matrix is worse than one that declines it cleanly, so every
unsupported mode gets its own `CHITRA_ERR_*` code instead of a guess:
arithmetic / 12-bit / hierarchical / lossless JPEG; CMYK JPEG through the RGBA
entries (it has its own); an unrecognised BMP DIB header size; and any illegal
PNG depth × color-type pair. BMP's deferral list is empty — everything it once
postponed decodes.

That list used to include a **valid** file: a baseline JPEG whose scans do not
each carry every frame component (what `cjpeg -scans` emits). It was deferred
rather than malformed, and said so with `CHITRA_ERR_UNSUPPORTED`. **0.8.0
decodes it** — held to the exact bytes of the same image encoded interleaved,
all nine sampling combinations byte-identical under `djpeg -nosmooth`. The
deferral is over; [ADR 0006](docs/adr/0006-defer-jpeg-multiscan-resumption.md)
is amended with what the implementation actually cost, including a claim in its
original text that turned out to be false.

Several refusals are permanent rather than deferred: **encoding** (chitra is
decode-only, in both directions of that sentence); **`BI_JPEG` / `BI_PNG`
inside a BMP**, which would have a decoder re-enter itself through
attacker-controlled data; and — reclassified from "deferred" by the 0.6.1
sweep — arithmetic-coded, hierarchical/lossless/differential, 12-bit and
DNL-deferred-height JPEG. **Progressive JPEG**, the one genuine deferral left,
decodes since 1.4.0, when a consumer (selah) demonstrated the need the roadmap
asked for ([ADR 0013](docs/adr/0013-progressive-jpeg.md)).

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
- **`make fuzz`** — one harness per format, **11,185,700 assertions, 0
  failures** at 1.1.1. CI runs exactly `make fuzz`, under
  `--poison`: allocator redzones catch the small overflow into the next bump
  allocation that a plain run cannot see. The harnesses assert *both* that the
  decoder survives and that it honours the documented `(0, *err_out set)`
  contract — the invariant a crash-only fuzzer misses.
- **`make bench`** — 17 decode benchmarks with committed
  [CSV history](bench-history.csv). BMP **6 ns/px** (RLE8 **18**, where
  per-opcode branching costs more than the bytes it saves), JPEG grayscale and
  GIF **43 ns/px**, PNG RGBA8 **83 ns/px** at 256×256.
- A 0.6.1 sweep for deferred and half-done work catalogued **84 findings** and
  turned up three defects on files standard tools produce: a `cjpeg -rgb` JPEG
  decoded hue-rotated with no error, an 81-byte GIF was wrongly refused, and a
  16 KB JPEG padded with skipped segments allocated **117 MB**. **All of it is
  closed**: the 0.7.x arc, 0.8.0's multi-scan JPEG and 0.9.0's surface work
  spent every item, and two were deliberately **declined** after a reference
  check contradicted the spec reading rather than fixed — which is the more
  useful outcome and is recorded as such.
- **Six security audits** in [`docs/audit/`](docs/audit/) — PNG and JPEG
  individually, then four P(-1) sweeps (PNG + JPEG, BMP + GIF, and two of the
  whole tree including its gates, the last on 2026-10-15 gating 1.1.1). None found a memory-safety
  defect. What they did find is the reason the reference cross-checks are not
  optional: **seven of nine findings in the 0.5.3 sweep were silent wrong
  output** — a real 32-bpp file decoding with red and blue swapped, a V4 file
  decoding fully transparent — that millions of fuzz cases had passed over,
  because none of them crash. Every one was caught by decoding the same bytes
  with ImageMagick.

Per-release detail — including the four input classes 0.3.3 began rejecting
deliberately — is in [`CHANGELOG.md`](CHANGELOG.md).

## Stability

**The public API and ABI are frozen as of 1.0.0.** The
[31 names](docs/development/public-surface.md) — twelve decode entry points
(two added in 1.4.0, which is what made it a minor), four signature
predicates, eight `ChitraImage` accessors, six error-API functions and
`chitra_version` — plus the `ChitraImage` record (append-only: 64 bytes since
1.4.0) and 16-byte `ChitraErr` layouts and the `ChitraErrCode` numeric values,
cannot change without a major bump and an ADR. Since 1.2.0 the public prefix
*is* the promise: the bundle's `chitra_*` functions are exactly those, everything internal is `_chitra_*`,
and `scripts/check-surface.sh` fails the build if a non-frozen `chitra_*` name
appears, a frozen one disappears, any top-level function or global lacks a
chitra prefix, or a `ChitraErrCode` member lacks a name or a literal value pin.

Four things are deliberately outside the promise: the internal names, the
human-readable `chitra_err_name` strings (the *codes* are frozen — match on
those), bit-exact output across releases, and memory behaviour — the global
bump allocator never frees, and `chitra_image_free` is a no-op except for an
image from a `_via` / CMYK decode. The output contract is *correct*
RGBA8 held to external oracles, so a repair that moves bytes toward the oracle
is a bug fix — the § 13.13 depth-16 rescaling change in 0.7.x changed every
16-bit PNG's output and was one. Full edges in
[ADR 0010](docs/adr/0010-the-v1-surface.md).

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

- **sankoch, `zlib` profile** — `[deps.sankoch]` tag `2.8.9`,
  `dist/sankoch-zlib.cyr`: zlib inflate + CRC-32, and none of sankoch's other
  codecs.
- **Cyrius stdlib** (8 leaves to build chitra itself) — `string`, `fmt`,
  `alloc`, `io`, `str`, `syscalls`, `assert`, `bench`. Resolved with sankoch
  by `cyrius deps` into `lib/`.
- **What a consumer links**: `dist/chitra.deps` names one stdlib leaf
  (`string`), and sankoch arrives through chitra's `[deps.sankoch]` — unless
  the consumer already links a sankoch bundle of its own, which then wins
  (one sankoch bundle per program).

All deps are pinned in `cyrius.cyml`, the toolchain pin with them.

## Quick Start

```bash
cyrius deps          # resolve stdlib + sankoch (zlib profile) into lib/
make build           # link-check the include chain (→ build/chitra_smoke)
make test            # 3949 assertions across tests/tcyr/ (at 1.1.1)
make fuzz            # ~2.6 M adversarial decode cases (fuzz/*.fcyr, under --poison — what CI runs)
make bench           # 17 decode benchmarks (tests/bcyr/chitra.bcyr)
make dist            # regenerate dist/chitra.cyr — the artifact consumers link
make test-all        # version-check + dist + test + fuzz + bench-build (the pre-release gate)
```

`make bench` is deliberately **not** run by `test-all`: benchmark numbers are
host- and load-dependent, so gating a correctness run on them would only
manufacture flakes. `test-all` and CI do *compile* the harness
(`make bench-build`), because nothing else would notice it stop building.
Record a series with `make bench-record`.

## Design

Start with [`docs/development/state.md`](docs/development/state.md) for the
current surface, sizes and decode matrix, then:

- [`docs/architecture/`](docs/architecture/) — the non-obvious constraints
  (why `lib/` must not be a symlink, why domain modules stay flat for
  `distlib`, why the bump allocator never frees, how the JPEG pipeline fits
  together). Note the bump allocator is not a footnote: on every entry point
  but the `_via` / CMYK ones `chitra_image_free` is a no-op, so decode cost is
  cumulative for the process — which is why the amplification caps exist.
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
(`docs/archive/proposals/v3.3-chitra-png-decoder-package.md`, the v3.3 "Asset
Loading" arc, Phase AL.P0); chitra's own JPEG design note is
[`docs/proposals/jpeg-baseline-decoder.md`](docs/proposals/jpeg-baseline-decoder.md).

## License

GPL-3.0-only.
