# Getting started with chitra

**chitra** (चित्र — Sanskrit: *image / picture*) is a pure-Cyrius CPU
raster image decoder. It turns encoded image bytes into canonical
RGBA8 pixels — no GPU, no C shim, no external binaries. As of v0.3.0 it
decodes **PNG** (every spec-legal bit depth 1/2/4/8/16 across color types
0/2/3/4/6, Adam7 interlace, PLTE/tRNS) and **baseline JPEG** (JFIF SOF0,
grayscale + YCbCr, 4:4:4 / 4:2:2 / 4:2:0 chroma subsampling, restart
markers) — both to the same canonical RGBA8.

chitra is a **library**, not a CLI. There is no binary to run, no
stdout emit, no terminal surface. You link `dist/chitra.cyr` into your
own program, hand it the encoded bytes you already hold in memory, and
get back an owned RGBA8 buffer. The consumer owns all file / network /
syscall I/O — chitra never opens a file.

The name is deliberately format-agnostic: JPEG joined in 0.3.0, and
GIF / BMP can land later without a rename.

## Build & verify locally

You need the Cyrius toolchain pinned in
[`cyrius.cyml`](../../cyrius.cyml) (`cyrius = "6.2.44"`). If `cyrius`
isn't on your PATH yet, see the agnosticos bootstrap.

```bash
cyrius deps        # resolve stdlib + sankoch + thread into lib/
make build         # link-check: builds build/chitra_smoke from programs/smoke.cyr
make test          # 728 assertions across tests/tcyr/
make dist          # = cyrius distlib → dist/chitra.cyr
```

A few notes on what each step proves:

- **`cyrius deps`** populates `lib/` from the stdlib + sankoch + thread
  pins. `lib/` must be a real directory (never a symlink) — see
  [architecture note 001](../architecture/001-lib-must-not-be-symlink.md).
- **`make build`** compiles [`programs/smoke.cyr`](../../programs/smoke.cyr)
  into `build/chitra_smoke`. chitra has no CLI, so this binary exists
  only to prove the full include chain (stdlib + sankoch + thread +
  domain modules) parses and links clean; it writes a one-line banner
  and exits 0.
- **`make test`** runs the five suites under `tests/tcyr/` — each is a
  standalone `main()`: `error.tcyr` (20), `interlace.tcyr` (35),
  `png.tcyr` (327), `subbyte.tcyr` (143).
- **`make dist`** concatenates the flat source modules into the single
  distributable `dist/chitra.cyr` — see
  [architecture note 002](../architecture/002-flat-modules-distlib-concatenation.md).
  This is the only file consumers link.

## Consuming chitra

chitra ships as a single concatenated library file, `dist/chitra.cyr`.
Add a `[deps.chitra]` block to your own `cyrius.cyml` pointing at a
released tag and pulling that one module:

```toml
[deps.chitra]
git     = "https://github.com/MacCracken/chitra"
tag     = "0.3.0"
modules = ["dist/chitra.cyr"]
```

chitra's own stdlib needs — notably **`sankoch`** (the RFC 1950/1951
`zlib_decompress` + `crc32` + `adler32` that does the IDAT inflate;
DEFLATE is sankoch's job, not chitra's) and **`thread`** (the mutex
pair sankoch's public-API lock wraps) — resolve from *your* stdlib
list. Make sure your manifest's stdlib includes them, then run
`cyrius deps`.

## The decode call

The format-agnostic entry point takes **bytes** (a pointer + length you
already hold) and an error-out slot, sniffs the signature (PNG magic vs
JPEG SOI), routes to the right decoder, and returns an owned `ChitraImage`:

```
fn chitra_image_decode(src, len, err_out): i64
```

If you already know the format, the format-specific decoders have the
identical shape: `chitra_png_decode(src, len, err_out)` and
`chitra_jpeg_decode(src, len, err_out)`.

Each returns the `ChitraImage` pointer on success, or `0` on failure with
`*err_out` set to a `ChitraErr` pointer (and left `0` on success).
`err_out` is a `>=8`-byte slot you own.

Read the result through the accessors — never poke at struct offsets
directly:

- `chitra_image_width(img)` — width in pixels
- `chitra_image_height(img)` — height in pixels
- `chitra_image_pixels(img)` — pointer to the owned RGBA8 buffer
  (`width * height * 4` bytes)
- `chitra_image_channels(img)` — always `4`
- `chitra_image_seen_iend(img)` — `1` if an IEND chunk closed the
  stream, `0` if it ended cleanly without one (tolerated)
- `chitra_image_source_color_type(img)` — the pre-normalization source
  type, so you can report the original format even though the pixels are
  canonical RGBA8. For PNG it is the PNG color_type (0/2/3/4/6); for JPEG
  it is `0x100 | num_components` (`0x101` grayscale, `0x103` YCbCr)

A minimal usage sketch (you supply `bytes`/`n` from however you read
the file or socket):

```
fn load(bytes, n): i64 {
    var err = 0;
    var img = chitra_image_decode(bytes, n, &err);
    if (img == 0) {
        # decode failed — inspect err (see Error handling below)
        return 0;
    }
    var w   = chitra_image_width(img);
    var h   = chitra_image_height(img);
    var px  = chitra_image_pixels(img);    # w*h*4 RGBA8 bytes, owned
    # ... upload px to a texture, blit, etc. ...
    return img;
}
```

If all you want is the pixel pointer plus dimensions, use the
convenience wrappers (one per format):

```
fn chitra_png_decode_rgba8(src, len, w_out, h_out): i64
fn chitra_jpeg_decode_rgba8(src, len, w_out, h_out): i64
```

Each decodes and returns the RGBA8 pixel pointer directly, writing
width/height through `w_out`/`h_out` (`>=8`-byte slots), or `0` on any
failure. The detailed `ChitraErr` is not surfaced on this path — reach
for `chitra_image_decode` / `chitra_png_decode` / `chitra_jpeg_decode`
when you need the error.

`chitra_image_free(img)` exists for API symmetry but is a documented
no-op: the stdlib `alloc` is a bump allocator with no per-block free —
see [architecture note 003](../architecture/003-bump-allocator-no-free.md).

You can probe the linked version at runtime with `chitra_version()`,
which returns `300` for 0.3.0 (`major*10000 + minor*100 + patch`).

## Error handling

On any decoder's failure path, `*err_out` holds a `ChitraErr`
— a 16-byte record: a code at `+0` and a detail pointer at `+8`. (That
layout is deliberately compatible with mabda's `GpuErr`, so a decode
failure maps cleanly onto `GPU_ERR_IMAGE_DECODE` — see
[ADR 0003](../adr/0003-mabda-abi-compatibility.md).) Read it through the
error API:

- `chitra_err_code(err)` — the `ChitraErrCode` enum value
- `chitra_err_detail(err)` — the detail string pointer
- `chitra_err_name(code)` — a human-readable name for a code
- `chitra_err_print_name(code)` — emit that name

### A note on IEND tolerance

A stream that ends cleanly without an IEND chunk still decodes (PNG
§ 5.3 tolerance). The image is returned normally with
`chitra_image_seen_iend(img) == 0`; a consumer can warn yet still use
the pixels. A *malformed* IEND (e.g. non-zero length) is a hard error.

### Error codes

| Code | Value | Triggers when |
|---|---|---|
| `CHITRA_ERR_OK` | 0 | No error (success path) |
| `CHITRA_ERR_SIGNATURE` | 1 | First 8 bytes are not the PNG signature |
| `CHITRA_ERR_TRUNCATED` | 2 | Stream ends mid-chunk / mid-field |
| `CHITRA_ERR_BAD_CHUNK` | 3 | Chunk framing is malformed |
| `CHITRA_ERR_UNSUPPORTED` | 4 | A construct chitra does not handle |
| `CHITRA_ERR_INFLATE` | 5 | sankoch IDAT inflate failed / wrong byte count |
| `CHITRA_ERR_OOM` | 6 | Allocation failed |
| `CHITRA_ERR_CRC` | 7 | Per-chunk CRC32 mismatch (corruption / tampering) |
| `CHITRA_ERR_INTERLACE` | 8 | Illegal interlace method (Adam7 itself is supported) |
| `CHITRA_ERR_BIT_DEPTH` | 9 | Bit depth illegal for the color type (e.g. ct3 + depth16) |
| `CHITRA_ERR_DIMENSIONS` | 10 | IHDR dimensions exceed policy / are invalid |
| `CHITRA_ERR_FILTER` | 11 | Filter byte ∉ {0,1,2,3,4} (spec § 9) |
| `CHITRA_ERR_NO_IDAT` | 12 | Structurally valid PNG with zero pixel data |
| `CHITRA_ERR_OTHER` | 99 | Anything else |

Heads-up on stale comments: the enum comments in
[`src/error.cyr`](../../src/error.cyr) for `CHITRA_ERR_INTERLACE`
("single-pass only") and `CHITRA_ERR_BIT_DEPTH` ("bit_depth != 8") date
from 0.2 and are now out of date — 0.2.1 decodes Adam7 *and* all bit
depths, so those two codes only fire for genuinely illegal combinations
(e.g. color type 3 at bit depth 16).

## What's supported

**PNG** is feature-complete (since 0.2.1):

- Signature + chunk parse (IHDR / concatenated IDAT / IEND / PLTE /
  tRNS)
- Color types 0/2/3/4/6 at every spec-legal bit depth 1/2/4/8/16
  (validated per color type — § 11.2.2 Table 11.1; ct3 + depth16
  rejected)
- Adam7 interlace (all 7 passes deinterlaced into the dense buffer, so
  the color pass is interlace-agnostic)
- IDAT inflate via sankoch (RFC 1950/1951)
- The five § 9 unfilter predictors (None / Sub / Up / Average / Paeth)
- Canonical RGBA8 output (16-bit → high byte; sub-byte grayscale scales
  ×255/85/17; palette indexes PLTE; tRNS resolved)
- The inherited kii security guards (decompression-bomb caps,
  lying-IHDR rejection, ratio caps) — see [SECURITY.md](../../SECURITY.md)

**Baseline JPEG** is feature-complete as of 0.3.0:

- JFIF baseline (SOF0) sequential Huffman, 8-bit precision
- Grayscale (1 component) and YCbCr (3 components) → RGBA8
- Chroma subsampling 4:4:4 / 4:2:2 / 4:2:0 and general per-component
  Hi/Vi (box upsampling)
- DRI / RST0–7 restart markers
- Huffman entropy decode, the integer `jpeg_idct_islow` IDCT, and
  full-range BT.601 YCbCr→RGB — verified byte-identical to ImageMagick on
  a real baseline JPEG
- Non-baseline modes (progressive, arithmetic, 12-bit, hierarchical /
  lossless, CMYK) are rejected with distinct error codes

### Not yet — and never

- **GIF / BMP** — not yet (tracked, not dropped); JPEG baseline shipped in
  0.3.0. The package name is format-agnostic precisely so these can land
  without a rename.
- **Encoding** — chitra is a decoder. Writing PNG (or any format) is
  out of scope, permanently.

## Where to go from here

- **Architecture & non-obvious constraints**: [`docs/architecture/README.md`](../architecture/README.md)
- **Roadmap (JPEG and beyond)**: [`docs/development/roadmap.md`](../development/roadmap.md)
- **Per-release / in-flight state**: [`docs/development/state.md`](../development/state.md)
- **Security model + threat analysis**: [`SECURITY.md`](../../SECURITY.md), [ADR 0002](../adr/0002-security-model.md), [PNG audit](../audit/2026-06-26-audit.md), [JPEG audit](../audit/2026-06-27-audit.md)
- **Why chitra forked kii's decoder**: [ADR 0001](../adr/0001-fork-kii-png-decoder.md)
- **All design decisions**: [`docs/adr/`](../adr/README.md)
- **CHANGELOG**: [`CHANGELOG.md`](../../CHANGELOG.md)

## Contributing

See [`CONTRIBUTING.md`](../../CONTRIBUTING.md). Short version: read
[`CLAUDE.md`](../../CLAUDE.md), follow smallest-first bite discipline,
test after every change, never bundle unrelated changes, and don't
commit (the user owns git).
