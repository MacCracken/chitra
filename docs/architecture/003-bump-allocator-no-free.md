# 003 — Bump allocator: no per-block free; `*_free` are no-ops

Non-obvious constraint a reader cannot derive from the API shape: chitra's
public `*_free` functions look like deallocators but reclaim nothing. This note
records *how the world is* — not a decision (the allocator choice lives in
[`../adr/`](../adr/)) and not a how-to (see [`../guides/getting-started.md`](../guides/getting-started.md)).

## The fact

chitra allocates every heap object through the stdlib `alloc()` bump allocator
(included once in [`../../src`](../../src) via `lib.cyr`). A bump allocator hands
out memory by advancing a cursor; it has **no per-block reclamation**. There is
no `free()` counterpart in chitra's call graph — grep the source and the only
allocation primitive in use is `alloc()`:

- `src/png_filter.cyr` — the PNG parse path: the concatenated IDAT buffer, the
  inflated scanline buffer, the reconstructed pixel buffer, the Paeth/Up filter
  work rows, and the `ChitraPngRaw` record itself.
- `src/png_color.cyr` — the canonical-RGBA8 output buffer.
- `src/jpeg_markers.cyr` — the `ChitraJpegFrame` record plus its quant-table and
  Huffman-table side allocations.
- `src/jpeg.cyr` — the per-component MCU planes, the zig-zag/IDCT scratch, and the
  RGBA8 output buffer.
- `src/png.cyr` — the 48-byte `ChitraImage` record (shared by both decoders).
- `src/error.cyr` — the 16-byte `ChitraErr` record.

None of these are ever returned to the allocator during a decode.

## The `*_free` no-ops

Three `@public` "free" functions exist purely for API symmetry, and all are
verified no-ops that return `0`:

- `chitra_image_free(img)` — `src/png.cyr`. Body is `return 0;`. The header
  states it plainly: *"The stdlib `alloc` is a bump allocator with no per-block
  free, so this is a documented no-op kept for API symmetry (matches
  `chitra_raw_free`) and a future arena-backed allocator. Safe on a 0 ptr."*
- `chitra_raw_free(raw)` — `src/png_chunks.cyr`. Body is `return 0;`. Same
  rationale.
- `chitra_jpeg_frame_free(f)` — `src/jpeg_markers.cyr`. Body is `return 0;`. The
  `ChitraJpegFrame` and its side allocations (quant / Huffman storage, the MCU
  planes) live in the same bump arena; same no-op rationale, safe on a 0 ptr.

Because the bodies ignore their argument entirely, **both are safe to call on a
`0` pointer** — calling `chitra_image_free(0)` after a failed decode is a no-op,
not a crash. They are kept (rather than deleted) so that:

1. Consumer code that pairs a decode with a free reads naturally and stays
   forward-compatible.
2. If chitra ever swaps the bump allocator for an arena/region allocator that
   *can* reclaim, the call sites already exist — only the bodies change, the ABI
   does not.

## Consequence for consumers

A `ChitraImage`'s `pixels` (and every intermediate buffer the decode touched)
live until **the process exits or the underlying arena is reset** — not until
`chitra_image_free` returns. There is no way, through chitra's API, to release
one image's memory while keeping the process alive.

Therefore a long-running consumer that calls `chitra_png_decode` (or
`chitra_png_decode_rgba8`) in a loop **accumulates memory monotonically** — each
decode bumps the cursor further and nothing walks it back. This affects any
consumer doing repeated decodes (batch conversion, a server decoding many
uploads, a test loop).

### The intended pattern: decode → use → drop the arena

chitra is built for *decode-then-use-then-reclaim-the-whole-region*, not
per-image free:

- **mabda** (`gpu_texture_load_png`) decodes once, uploads the RGBA8 pixels to a
  GPU texture, and then the arena backing that decode is reclaimed wholesale —
  the CPU-side `pixels` were only ever a staging buffer, so a bump allocator with
  a region reset is exactly the right shape.
- A consumer that genuinely needs to decode many images in one long-lived
  process should drive the lifetime at the arena boundary (reset the region
  between batches) rather than expecting `chitra_image_free` to give memory back.

Do **not** treat `chitra_image_free` / `chitra_raw_free` / `chitra_jpeg_frame_free`
as memory-pressure relief. They are markers, not collectors.

## See also

- [`../adr/0003-mabda-abi-compatibility.md`](../adr/0003-mabda-abi-compatibility.md) — why the
  `ChitraImage` / `ChitraErr` layouts (and thus the free no-ops' ABI) are pinned.
- [`002-flat-modules-distlib-concatenation.md`](002-flat-modules-distlib-concatenation.md) — why
  stdlib includes (`alloc.cyr` among them) live only in `lib.cyr`.
- [`../audit/2026-06-26-audit.md`](../audit/2026-06-26-audit.md) — current-state audit.
- [`../development/state.md`](../development/state.md) — volatile state (versions, sizes, counts).
