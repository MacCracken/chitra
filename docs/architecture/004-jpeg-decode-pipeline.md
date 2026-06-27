# 004 — JPEG decode pipeline (markers → huffman → idct → public)

> **Last Updated**: 2026-06-27

Architecture notes describe *how the world is* — non-obvious invariants a reader
cannot derive from the code alone. Not decisions (those live in
[`../adr/`](../adr/)) and not guides (those live in
[`../guides/`](../guides/)). Numbered chronologically — never renumber.

The JPEG decoder landed in 0.3.0 alongside the existing PNG path. It is the same
shape as the PNG pipeline — untrusted bytes in, canonical RGBA8 `ChitraImage`
out, every read bounds-checked before access, the `(ptr, err_out)` Ok/Err split —
but the decode topology and the Cyrius-specific arithmetic are different enough to
deserve their own note. Scope is JFIF **baseline** (SOF0) sequential Huffman
8-bit: grayscale (1 component) and YCbCr (3 components), chroma subsampling
4:4:4 / 4:2:2 / 4:2:0 / general `Hi,Vi` via box upsampling, and DRI/RST0–7
restart markers. The decision and scope rationale live in
[`../adr/0004-jpeg-decode-model.md`](../adr/0004-jpeg-decode-model.md); this note
records the invariants that survive the decision.

## Module map

Four source modules, included (per `[lib].modules` in
[`../../cyrius.cyml`](../../cyrius.cyml)) *after* the five PNG modules and in this
order:

```
… png_color → png →  jpeg_huffman → jpeg_idct → jpeg_markers → jpeg
```

```
  (src, len)                                                   ChitraImage
  untrusted JPEG bytes                                          (owned RGBA8)
       │                                                              ▲
       ▼                                                              │
 ┌──────────────────┐   ┌──────────────────┐   ┌──────────────────┐  │
 │ jpeg_markers.cyr │   │ jpeg_huffman.cyr │   │ jpeg_idct.cyr    │  │
 │ SOI..SOS walk +  │   │ bit-reader +     │   │ dequant + de-    │  │
 │ DQT/DHT/SOF0/DRI │──►│ DECODE + RECEIVE │──►│ zig-zag + islow  │──┘
 │ parse + reject   │   │ /EXTEND + per-   │   │ integer IDCT +   │
 │ non-baseline     │   │ block run/size   │   │ level-shift+clamp│
 └──────────────────┘   └──────────────────┘   └──────────────────┘
       │  ChitraJpegFrame ──────────────────────────►│
       │                                              │
       └──────────────────────────────────────────────────────────┐
                                                                    ▼
                                                          ┌──────────────────┐
                                                          │ jpeg.cyr (public)│
                                                          │ scan_markers →   │
                                                          │ parse_sos →      │
                                                          │ decode_scan →    │
                                                          │ box upsample +   │
                                                          │ YCbCr→RGB →      │
                                                          │ ChitraImage      │
                                                          └──────────────────┘

   error.cyr — ChitraErr underpins every stage; each fallible call
               returns 0 + sets *err_out (codes 13..23 are JPEG-specific).
```

| Module | Lines | Owns |
|---|---|---|
| [`../../src/jpeg_huffman.cyr`](../../src/jpeg_huffman.cyr) | 282 | `HuffTable` record (MINCODE/MAXCODE/VALPTR/COUNT/HUFFVAL); `_jpeg_huff_build` (Annex C/F table derivation + over-subscription reject); the entropy bit-reader (`_jpeg_br_*`) with byte-stuffing + marker/restart handling; `_jpeg_decode` (DECODE), `_jpeg_br_bits` (RECEIVE), `_jpeg_extend` (EXTEND); `_jpeg_decode_block` (one 8×8 block: DC diff + AC run/size) |
| [`../../src/jpeg_idct.cyr`](../../src/jpeg_idct.cyr) | 222 | The zig-zag→natural index map; `_jpeg_descale` (signed round-to-nearest); the libjpeg `jpeg_idct_islow` integer IDCT; `_jpeg_idct_block` (dequant + de-zig-zag + 2-D IDCT + level-shift+clamp) |
| [`../../src/jpeg_markers.cyr`](../../src/jpeg_markers.cyr) | 508 | `ChitraJpegFrame` record + accessors; the baseline ceilings; `chitra_jpeg_check_signature`; the SOI→SOS marker walk `chitra_jpeg_scan_markers`; `_jpeg_parse_{sof0,dqt,dht,dri}`; `_jpeg_marker_action` (the non-baseline reject table) |
| [`../../src/jpeg.cyr`](../../src/jpeg.cyr) | 420 | Public API: `chitra_jpeg_decode`, `chitra_jpeg_decode_rgba8`, `chitra_image_decode` (PNG/JPEG signature router); `_jpeg_parse_sos`; `_jpeg_decode_scan` (the MCU loop + plane placement + box upsample + BT.601 YCbCr→RGB) |

## Why huffman + idct precede markers in the include chain

This is the load-bearing, counter-intuitive ordering fact. The natural reading
order of the *pipeline* is markers → huffman → idct → public, but the *include*
order is huffman → idct → markers → public. Two reasons, both required by the
flat-module / strip-concatenation invariant ([item 002](002-flat-modules-distlib-concatenation.md)):

1. **`jpeg_huffman.cyr` is frame-independent table machinery.** Its
   `_jpeg_huff_build` builds a canonical decode table from a DHT's `BITS` +
   `HUFFVAL` into caller-owned storage; it knows nothing about `ChitraJpegFrame`.
   But `jpeg_markers.cyr`'s DHT parser (`_jpeg_parse_dht`) *calls* `_jpeg_huff_build`
   and references `HT_SIZE` / `HT_*` field offsets to allocate and index the
   frame's 8-table storage. Since concatenation puts a use after its declaration
   only if the declaring module is listed first, `jpeg_huffman.cyr` must come
   before `jpeg_markers.cyr`.

2. **`jpeg_idct.cyr` is likewise frame-independent** (it operates on caller
   buffers: a 64-i64 zig-zag block, a 64-i64 quant table, a 64-i64 output). It is
   not called by the marker walk at all — it is called from `jpeg.cyr` — but it
   defines `_jpeg_descale`, which `jpeg.cyr`'s color pass also uses, so it sits
   above `jpeg.cyr`. Placing it before `jpeg_markers.cyr` keeps the two
   frame-independent leaf modules grouped ahead of the frame-aware ones.

So the rule is: **frame-independent leaves (huffman, idct) first; the
frame-builder (markers) next; the public wirer (jpeg) last.** The same dependency
topology that orders the PNG five orders these four.

## The `ChitraJpegFrame` handoff

`chitra_jpeg_scan_markers` walks SOI→SOS once and produces a heap `ChitraJpegFrame`
(`CHITRA_JPEG_FRAME_SIZE = 320` bytes, deliberately over-reserved so the alloc
size stayed stable as fields were added across the 0.3.0 bites). It is the JPEG
analog of `ChitraPngRaw`: a parse-output record passed by pointer between stages,
not a shared scratch buffer. The frame owns two side allocations referenced by
pointer fields — `JF_QUANT` (4×64 i64 quant tables, stored in **zig-zag/spec
order**; de-zig-zag is deferred to dequant time) and `JF_HUFF` (8 `HuffTable`
records: slots 0–3 DC, 4–7 AC, slot = `class*4 + id`). `quant_present` /
`huff_present` are bitmasks of which tables have been seen, checked at scan time
before a component is allowed to reference them.

The handoff crosses three functions in `jpeg.cyr`:

- `chitra_jpeg_scan_markers` fills the SOF fields (width/height/precision/ncomp/
  max_h/max_v, per-component `id`/`H`/`V`/`Tq`), the tables, the restart
  interval, and records `JF_SOS_OFFSET` (the byte offset of the SOS length field).
- `_jpeg_parse_sos` re-opens a cursor at `JF_SOS_OFFSET`, matches each scan
  component back to a frame component by `Cs == id`, and writes the per-component
  `JF_COMP_TD` / `JF_COMP_TA` (DC/AC Huffman selectors). It enforces the baseline
  spectral selection (`Ss=0`, `Se=63`, `Ah=Al=0`) and returns the byte offset
  where entropy-coded data begins.
- `_jpeg_decode_scan` reads it all back through accessors, never touching raw
  offsets except to write `TD`/`TA` (which it does not).

## The MCU / sampling-factor / plane / box-upsample model

`_jpeg_decode_scan` is the heart. The MCU is `max_h × max_v` data units wide/tall
(`mcu_w = 8*max_h`, `mcu_h = 8*max_v`); the image is covered by
`ceil(w/mcu_w) × ceil(h/mcu_h)` MCUs. Each component `i` contributes `Hi × Vi`
8×8 blocks per MCU, laid into its **own component plane** at the component's
subsampled resolution: `comppw = mcu_cols * Hi * 8` wide,
`mcu_rows * Vi * 8` tall (one byte per sample). Allocating a plane per component —
rather than interleaving into one buffer — is what lets arbitrary `Hi,Vi`
combinations and the three named subsampling ratios share one code path.

Per MCU, the loop iterates components in scan order, and within a component the
`Vi × Hi` blocks in raster order; each block goes `_jpeg_decode_block` (entropy)
→ `_jpeg_idct_block` (dequant + IDCT) → scatter the 64 samples into the plane at
`((mcu_y*Vi + by)*8 + r, (mcu_x*Hi + bx)*8 + c)`. DC predictors live in a small
per-component array and persist across MCUs (DC is differential).

After all MCUs decode, the color pass produces RGBA8. Upsampling is **box** (no
interpolation): each output pixel `(x,y)` samples its component plane at
`(y*Vi/max_v)*comppw + (x*Hi/max_h)` — integer division, nearest-lower sample.
For 1 component the gray value fills R=G=B with A=255; for 3 it goes through
`_jpeg_ycc_to_rgb`. The result `ChitraImage` carries a JPEG sentinel in
`source_color_type` (`256 + ncomp`, i.e. `0x101` gray / `0x103` YCbCr) so a
consumer's PNG 0/2/3/4/6 switch can never alias it.

## The entropy bit-reader's marker / restart handling

The bit-reader (`BR_SIZE = 48` bytes: base/pos/end/buf/cnt/marker) pulls bits
MSB-first over the entropy-coded segment after SOS, and it is where the byte
stream's framing intrudes on the bit stream — a thing a reader cannot derive from
the DECODE algorithm alone:

- **Byte stuffing.** A `0xFF 0x00` pair in the stream is a literal `0xFF` data
  byte (`_jpeg_br_load_byte` loads the `0xFF` and discards the `0x00`).
- **Embedded markers stop the reader.** A `0xFF xx` with `xx != 0` (an RSTn, EOI,
  or any marker) is *not* consumed as data: the marker code is recorded in
  `BR_MARKER`, `pos` is left pointing **at the `0xFF`** (so a later resync can
  re-read it), and `BR_CNT` is left 0 so all subsequent bit reads **pad with
  zeros**. A trailing lone `0xFF` at end-of-data synthesizes an EOI (`0xD9`).
  This zero-padding-past-marker behavior is what lets a truncated or
  marker-terminated scan finish the current block deterministically instead of
  reading out of bounds.
- **Restart resync.** `_jpeg_decode_scan` counts decoded MCUs; when
  `restart_interval > 0` and `mi % ri == 0` (and `mi > 0`), it calls
  `_jpeg_br_restart`, which discards the partial byte (byte-aligns), requires the
  next two bytes to be `0xFF` followed by `0xD0..0xD7` (RSTn), advances past them,
  clears `BR_MARKER`, and the caller resets all DC predictors to 0. A
  missing/malformed restart marker returns −1, surfaced as
  `CHITRA_ERR_JPEG_ENTROPY`.

`_jpeg_decode` and `_jpeg_decode_block` defend the table edges: an undecodable
code (no length ≤ 16 matched, or a symbol index outside the table's `COUNT`)
returns −1 → `CHITRA_ERR_JPEG_ENTROPY`; a DC magnitude `t > 16`, or an AC run
that pushes `k > 63`, is likewise rejected rather than overrunning the 64-coeff
block.

## Cyrius-specific facts (cannot be derived from the algorithm)

These three are pure Cyrius/representation quirks — the IDCT and color math are
*textbook libjpeg*, but the language forces non-obvious shapes:

1. **`>>` is a LOGICAL shift in Cyrius.** It is therefore wrong for the negative
   intermediates the IDCT and color conversion produce. Both modules use
   `_jpeg_descale` ([`../../src/jpeg_idct.cyr`](../../src/jpeg_idct.cyr) lines
   115–120) — signed division with round-to-nearest, symmetric about zero —
   instead of `>>` for descaling. Relatedly, the even-part `CONST_BITS` scaling
   multiplies by `* 8192` (= `1<<13`) rather than left-shifting, so negative
   coefficients scale correctly. This is deterministic and a valid rounding;
   output is verified **byte-identical to ImageMagick** on a real 16×16 baseline
   gradient JPEG with real Annex K Huffman tables and AC entropy.

2. **The marker-action integer convention.** `_jpeg_marker_action` returns a
   small positive *action* code (1=SOF0/parse, 2=SOS/stop, 3=standalone,
   4=length-bearing/skip, 5=DQT, 6=DHT, 7=DRI) **or** a `CHITRA_ERR_*` reject
   code for a non-baseline mode. Those two numeric ranges are deliberately
   disjoint: actions are 1..7, JPEG error codes are 13..23, so the caller can
   test `act >= 13` to mean "reject" without a separate flag. A reader who does
   not know the JPEG error enum starts at 13 will misread this dispatch.

3. **Per-component data lives in parallel byte-offset arrays.** Cyrius has no
   struct-of-arrays sugar, so `_jpeg_decode_scan` keeps eight stack arrays
   (`planes`, `preds`, `dctabs`, `actabs`, `quants`, `comph`, `compv`, `comppw`)
   indexed by `comp * 8` (i64 stride). Likewise `ChitraJpegFrame`'s per-component
   specs are a flat block of 4 × `JF_COMP_STRIDE` (48-byte) records addressed by
   `JF_COMP + i*48 + field`. The accessor functions (`chitra_jpeg_frame_comp_*`)
   exist precisely so the rest of the code never open-codes that arithmetic.

## Error codes and security ceilings

JPEG-specific `ChitraErrCode` values occupy 13–23 in
[`../../src/error.cyr`](../../src/error.cyr): `JPEG_MARKER` 13, `_SOF` 14,
`_DQT` 15, `_DHT` 16, `_SOS` 17, `_ENTROPY` 18, `_PROGRESSIVE` 19,
`_ARITHMETIC` 20, `_PRECISION` 21, `_MODE` 22, `_COMPONENTS` 23. Generic codes
are reused where they fit: `SIGNATURE` 1, `TRUNCATED` 2, `OOM` 6,
`DIMENSIONS` 10, `UNSUPPORTED` 4.

Ceilings are validated **before** any allocation depends on them. The shared
pixel/byte/dimension caps come from `png_chunks.cyr`
(`CHITRA_MAX_PIXELS` 16777216, `CHITRA_MAX_RAW_BYTES` 268435456,
`CHITRA_MAX_DIM` 65535) and gate both `_jpeg_parse_sof0` (width/height) and
`_jpeg_decode_scan` (per-plane and final RGBA byte counts). JPEG adds its own in
`jpeg_markers.cyr`: `CHITRA_MAX_COMPONENTS` 4, `CHITRA_MAX_SAMP_FACTOR` 4,
`CHITRA_MAX_BLOCKS_PER_MCU` 10, `CHITRA_MAX_QUANT_TABLES` 4,
`CHITRA_MAX_HUFF_TABLES` 4. Two specific hardening checks are worth naming:
`_jpeg_parse_sof0` rejects `Hi` or `Vi` of 0 (the CVE-2018-11212 div-by-zero
class) and rejects duplicate component ids and `ΣHi·Vi > 10`
([`../../src/jpeg_markers.cyr`](../../src/jpeg_markers.cyr) lines 340–379); and
`_jpeg_huff_build` rejects an over-subscribed table (`code >= 1<<L`) — the check
that stops a malformed DHT from producing out-of-range code values
([`../../src/jpeg_huffman.cyr`](../../src/jpeg_huffman.cyr) line 72). The marker
walk itself cannot loop forever: every iteration advances ≥ 2 bytes or terminates
on the `can_read(2)` gate ([`../../src/jpeg_markers.cyr`](../../src/jpeg_markers.cyr)
lines 398–443).

**Known gap (real).** The JPEG decoder's hardening lineage is the kii/PNG fork's,
but the JPEG byte-buffer / entropy surface has **not been fuzzed in-tree**: there
is no in-tree fuzz harness and no benchmark harness yet. Both are v1.0 gates. The
byte-identical ImageMagick cross-check is correctness evidence, not fuzz
coverage. The 199 assertions in `jpeg.tcyr` (of 724 total across the 5 suites,
`make test`) exercise the marker walk, table builds, entropy decode, IDCT, and
color, but are hand-authored, not generated.

## See also

- [`../adr/0004-jpeg-decode-model.md`](../adr/0004-jpeg-decode-model.md) — the
  decision and scope rationale this note records the invariants of.
- [`002-flat-modules-distlib-concatenation.md`](002-flat-modules-distlib-concatenation.md)
  — the include-order / strip-concatenation invariant that forces the
  huffman → idct → markers → jpeg ordering.
- [`003-bump-allocator-no-free.md`](003-bump-allocator-no-free.md) — the
  allocation model the per-plane / per-frame allocs assume (`chitra_jpeg_frame_free`
  is a no-op).
- [`../development/state.md`](../development/state.md) — current bundle size,
  line counts, version, and the open fuzz/bench gates (volatile; this note stays
  durable).
