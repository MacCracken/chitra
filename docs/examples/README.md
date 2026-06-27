# chitra — Examples

chitra is a decode **library**: consumers link `dist/chitra.cyr`, hand
it encoded image bytes, and get back canonical RGBA8. There is no CLI,
no stdout emit, no terminal surface to capture — so this directory does
not yet carry the `run.sh`/`expected.txt` example dirs you may know from
sibling AGNOS tools. chitra is early (0.2.1, pre-1.0); examples grow as
the API stabilizes.

## What exists today

| Reference | Shows |
|---|---|
| [`../../programs/smoke.cyr`](../../programs/smoke.cyr) | The minimal "it compiles + links" proof — `include "src/lib.cyr"`, `alloc_init()`, exit 0. Built as `build/chitra_smoke` via `make build`. Proves the full include chain (stdlib + sankoch + thread + domain modules) parses and links clean; it does **not** decode anything. |
| [`../guides/getting-started.md`](../guides/getting-started.md) | The decode-call sketch — how to call `chitra_png_decode` / `chitra_png_decode_rgba8`, read `ChitraImage` fields, and check `ChitraErr`. |

## The decode shape

For orientation, the public entry points (see
[`../../CLAUDE.md`](../../CLAUDE.md) for the full API):

- `chitra_png_decode(src, len, err_out) -> ChitraImage*` — `0` on
  failure with `*err_out` set; on success a `ChitraImage` whose
  `chitra_image_pixels` is owned RGBA8 (`width * height * 4` bytes).
- `chitra_png_decode_rgba8(src, len, w_out, h_out) -> RGBA8*` — the
  thin convenience wrapper when you only want the pixel buffer.

DEFLATE is sankoch's job, not chitra's; chitra owns the byte-buffer I/O
boundary and the canonical-RGBA8 normalization pass.

## Wanted contribution

A runnable decode example — read encoded bytes from memory, call
`chitra_png_decode`, and inspect a few pixels / the `ChitraImage`
header fields (`width`, `height`, `channels`, `seen_iend`,
`source_color_type`) — is a wanted contribution. It would slot in here
once the API surface settles. See
[`../development/roadmap.md`](../development/roadmap.md) for what is
still in flight and [`../../CONTRIBUTING.md`](../../CONTRIBUTING.md)
for how to land it.
