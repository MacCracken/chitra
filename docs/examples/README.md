# chitra — Examples

chitra is a decode **library**: consumers link `dist/chitra.cyr`, hand
it encoded image bytes, and get back canonical RGBA8. There is no CLI,
no stdout emit, no terminal surface to capture — so this directory does
not yet carry the `run.sh`/`expected.txt` example dirs you may know from
sibling AGNOS tools. chitra is early (0.3.0, pre-1.0); examples grow as
the API stabilizes.

## What exists today

| Reference | Shows |
|---|---|
| [`../../programs/smoke.cyr`](../../programs/smoke.cyr) | The minimal "it compiles + links" proof — `include "src/lib.cyr"`, `alloc_init()`, exit 0. Built as `build/chitra_smoke` via `make build`. Proves the full include chain (stdlib + sankoch + thread + domain modules) parses and links clean; it does **not** decode anything. |
| [`../guides/getting-started.md`](../guides/getting-started.md) | The decode-call sketch — how to call `chitra_image_decode` (the PNG/JPEG router) or the format-specific `chitra_png_decode` / `chitra_jpeg_decode` (+ their `_rgba8` wrappers), read `ChitraImage` fields, and check `ChitraErr`. |

## The decode shape

For orientation, the public entry points (see
[`../../CLAUDE.md`](../../CLAUDE.md) for the full API):

- `chitra_image_decode(src, len, err_out) -> ChitraImage*` — the
  format-sniffing router: PNG magic → the PNG decoder, JPEG SOI → the
  JPEG decoder. Reach for this when you don't know the format up front.
- `chitra_png_decode(src, len, err_out)` /
  `chitra_jpeg_decode(src, len, err_out) -> ChitraImage*` — the
  format-specific decoders; `0` on failure with `*err_out` set, else a
  `ChitraImage` whose `chitra_image_pixels` is owned RGBA8
  (`width * height * 4` bytes).
- `chitra_png_decode_rgba8` / `chitra_jpeg_decode_rgba8(src, len, w_out,
  h_out) -> RGBA8*` — the thin convenience wrappers when you only want the
  pixel buffer.

For PNG, DEFLATE is sankoch's job; for JPEG, entropy decode is chitra's
own. Either way chitra owns the byte-buffer I/O boundary and the
canonical-RGBA8 normalization pass.

## Wanted contribution

A runnable decode example — read encoded bytes from memory, call
`chitra_image_decode`, and inspect a few pixels / the `ChitraImage`
header fields (`width`, `height`, `channels`, `seen_iend`,
`source_color_type`) — is a wanted contribution. It would slot in here
once the API surface settles. See
[`../development/roadmap.md`](../development/roadmap.md) for what is
still in flight and [`../../CONTRIBUTING.md`](../../CONTRIBUTING.md)
for how to land it.
