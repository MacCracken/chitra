# chitra — Examples

chitra is a decode **library**: consumers link `dist/chitra.cyr`, hand
it encoded image bytes, and get back canonical RGBA8. There is no CLI,
no stdout emit, no terminal surface to capture — so this directory does
not yet carry the `run.sh`/`expected.txt` example dirs you may know from
sibling AGNOS tools. chitra is at 1.0.0 with a frozen public surface; examples grow as
the API stabilizes.

## What exists today

| Reference | Shows |
|---|---|
| [`../../programs/smoke.cyr`](../../programs/smoke.cyr) | The minimal "it compiles + links" proof — `include "src/lib.cyr"`, `alloc_init()`, exit 0. Built as `build/chitra_smoke` via `make build`. Proves the full include chain (stdlib + sankoch + thread + domain modules) parses and links clean; it does **not** decode anything. |
| [`../guides/getting-started.md`](../guides/getting-started.md) | The decode-call sketch — how to call `chitra_image_decode` (the four-format router) or the format-specific `chitra_png_decode` / `chitra_jpeg_decode` (+ their `_rgba8` wrappers), read `ChitraImage` fields, and check `ChitraErr`. |

## The decode shape

For orientation, the public entry points (see
[`../development/public-surface.md`](../development/public-surface.md) for the
authoritative frozen list — 29 names as of 1.0.0):

- `chitra_image_decode(src, len, err_out) -> ChitraImage*` — the
  format-sniffing router: PNG magic → PNG, JPEG SOI → JPEG, BMP `BM` → BMP,
  GIF `GIF8?a` → GIF, else `0` with `CHITRA_ERR_SIGNATURE`. Reach for this
  when you don't know the format up front.
- `chitra_image_decode_budget(src, len, max_bytes, err_out)` — the same, but
  refuses **before decoding** if the RGBA8 output would exceed `max_bytes`
  (`CHITRA_ERR_BUDGET`). Worth reaching for on untrusted input, because the
  bump allocator never frees.
- `chitra_{png,jpeg,bmp,gif}_decode(src, len, err_out) -> ChitraImage*` — the
  format-specific decoders; `0` on failure with `*err_out` set, else a
  `ChitraImage` whose `chitra_image_pixels` is owned RGBA8
  (`width * height * 4` bytes).
- `chitra_{png,jpeg,bmp,gif}_decode_rgba8(src, len, w_out, h_out) -> RGBA8*` —
  the thin convenience wrappers when you only want the pixel buffer.

For PNG, DEFLATE is sankoch's job; for JPEG, GIF and BMP the decompression is
chitra's own. Either way chitra owns the byte-buffer I/O boundary and the
canonical-RGBA8 normalization pass.

## Wanted contribution

A runnable decode example — read encoded bytes from memory, call
`chitra_image_decode`, and inspect a few pixels / the `ChitraImage`
header fields (`width`, `height`, `channels`, `seen_iend`,
`source_color_type`, `source_depth`) — is a wanted contribution. The surface is
frozen as of 1.0.0, so it can slot in here now. See
[`../development/roadmap.md`](../development/roadmap.md) for what is left and [`../../CONTRIBUTING.md`](../../CONTRIBUTING.md)
for how to land it.
