# 004 — JPEG decode pipeline (markers → huffman → idct → public)

Architecture notes describe *how the world is* — non-obvious invariants a reader
cannot derive from the code alone. Not decisions (those live in
[`../adr/`](../adr/)) and not guides (those live in
[`../guides/`](../guides/)). Numbered chronologically — never renumber.

The JPEG decoder landed in 0.3.0 alongside the existing PNG path. It is the same
shape as the PNG pipeline — untrusted bytes in, canonical RGBA8 `ChitraImage`
out, every read bounds-checked before access, the `(ptr, err_out)` Ok/Err split —
but the decode topology and the Cyrius-specific arithmetic are different enough to
deserve their own note. Scope is JFIF **baseline** (SOF0) sequential Huffman
8-bit: grayscale (1 component), YCbCr (3 components) and — since 0.6.1 —
**RGB** 3-component frames written with an Adobe APP14 `transform=0`
([ADR 0009](../adr/0009-jpeg-colour-transform.md)); chroma subsampling
4:4:4 / 4:2:2 / 4:2:0 / general `Hi,Vi` via box upsampling; DRI/RST0–7 restart
markers; and, since 0.8.0, the **complete T.81 § A.2 scan model** —
interleaved, non-interleaved, partially interleaved, single- and multi-scan.
As of 0.8.0 `CHITRA_ERR_UNSUPPORTED` no longer covers any JPEG scan geometry. The decision and scope rationale live in
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
| [`../../src/jpeg_huffman.cyr`](../../src/jpeg_huffman.cyr) | 344 | `HuffTable` record (MINCODE/MAXCODE/VALPTR/COUNT/HUFFVAL); `_jpeg_huff_build` (Annex C/F table derivation + over-subscription reject); the entropy bit-reader (`_jpeg_br_*`) with byte-stuffing + marker/restart handling; `_jpeg_decode` (DECODE), `_jpeg_br_bits` (RECEIVE), `_jpeg_extend` (EXTEND); `_jpeg_decode_block` (one 8×8 block: DC diff + AC run/size) |
| [`../../src/jpeg_idct.cyr`](../../src/jpeg_idct.cyr) | 226 | The zig-zag→natural index map; `_jpeg_descale` (signed round-to-nearest); the libjpeg `jpeg_idct_islow` integer IDCT; `_jpeg_idct_block` (dequant + de-zig-zag + 2-D IDCT + level-shift+clamp) |
| [`../../src/jpeg_markers.cyr`](../../src/jpeg_markers.cyr) | 814 | `ChitraJpegFrame` record + accessors; the baseline ceilings; `chitra_jpeg_check_signature`; the SOI→SOS marker walk `chitra_jpeg_scan_markers`; `_jpeg_parse_{sof0,dqt,dht,dri}`; `_jpeg_marker_action` (the non-baseline reject table) |
| [`../../src/jpeg.cyr`](../../src/jpeg.cyr) | 1056 | Public API: `chitra_jpeg_decode`, `chitra_jpeg_decode_rgba8`, `chitra_image_decode` (the **four-format** signature router — PNG, JPEG, BMP, GIF), `chitra_image_decode_budget`; `_jpeg_parse_sos`; and the three functions 0.8.0 split `_jpeg_decode_scan` into — `_jpeg_decode_scans` (multi-scan driver), `_jpeg_decode_one_scan` (MCU loop + plane placement), `_jpeg_build_image` (box upsample + colour pass + `ChitraImage`) — plus `_jpeg_resume_to_next_scan` and `_jpeg_entropy_span` |

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
(`CHITRA_JPEG_FRAME_SIZE = 384` bytes, deliberately over-reserved so the alloc
size stays stable as fields are added). It grew from 320 for `JF_ADOBE_TRANSFORM`
@232 (0.6.1) and the per-scan block 0.8.0 added — `JF_SCAN_NS` @240, `JF_SCAN`
@248 (4 × 24-byte entries) and the coverage bitmask `JF_COVERED` @344 — while
`JF_COMP_STRIDE` *shrank* 48 → 32 in the same cut, when the Huffman selectors
moved off the component record, so the net allocation cost of 0.8.0 was zero. It is the JPEG
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
  component back to a frame component by `Cs == id`, and writes the **per-scan**
  entries `JF_SCAN_COMP` / `JF_SCAN_TD` / `JF_SCAN_TA` (`JF_SCAN_STRIDE` = 24
  bytes, up to 4 entries) plus `JF_SCAN_NS`. It also applies the § B.2.3
  `ΣHj·Vj ≤ 10` cap, conditioned on `Ns > 1` and summed over the *scan's* own
  components. It enforces the baseline spectral selection (`Ss=0`, `Se=63`,
  `Ah=Al=0`) and returns the byte offset where entropy-coded data begins.

  **The Huffman selectors deliberately do not live on the component record.**
  They are a property of the *scan*, not the component: in a multi-scan file a
  component absent from a later scan would otherwise retain the earlier scan's
  tables. 0.8.0 deleted `JF_COMP_TD` / `JF_COMP_TA` for exactly that reason.
- `_jpeg_decode_scans` drives the scans and `_jpeg_decode_one_scan` reads it all
  back through accessors, never touching raw offsets.

## The MCU / sampling-factor / plane / box-upsample model

`_jpeg_decode_one_scan` is the heart. For an **interleaved** scan the MCU is
`max_h × max_v` data units wide/tall
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
`source_color_type` — `0x100 | ncomp`, with **bit 4 set when the components are
RGB** rather than YCbCr: `0x101` gray, `0x103` YCbCr, `0x113` RGB (0.6.1). A
consumer's PNG 0/2/3/4/6 switch can never alias any of them. The order of
authority for that decision — the APP14 transform, else the component ids, else
YCbCr, with an *undefined* transform declined rather than guessed — is
[ADR 0009](../adr/0009-jpeg-colour-transform.md).

### One § A.2 rule for both layouts (0.8.0)

The model above is the **interleaved** one (T.81 § A.2.3). A scan carrying a
single component is **non-interleaved** (§ A.2.2) and its MCU is exactly one 8×8
data unit — a different layout, which chitra rejected outright through 0.5.3
rather than mis-render.

0.6.0 decoded the one-component *frame* case with an **effective-geometry
collapse**, forcing `H = V = max_h = max_v = 1`. **0.8.0 deleted that collapse
rather than extending it**, and the reason is the load-bearing fact in this
section: the collapse was valid only because with `Nf = 1` the lone component
*is* the maximum, so § A.1.1's `x_i = ceil(X·H_i/H_max)` reduces to `x_1 = X`.
A one-component **scan** of a three-component **frame** has a maximum that is
not itself, and forcing the factors there would have been right for grayscale
and wrong for every subsampled colour file.

The rule that replaced it keys on the **scan**, not the frame:

- A scan is non-interleaved when **`Ns == 1`**, whatever `Nf` is.
- `_jpeg_decode_one_scan` then walks a scan grid
  `s_cols × s_rows = ceil(x_i/8) × ceil(y_i/8)` over that component's own
  § A.1.1 sample dimensions, one data unit per MCU, with `H_i = V_i = 1` blocks
  per MCU — and `max_h` / `max_v` are left **alone**.
- `Nf = 1` now falls out of that same formula. There is no special case.

**The exact-fit property, and what it depends on.** The plane is sized
`cpw = s_cols · H · 8` and `cph = s_rows · V · 8` from the same grid the blocks
are placed on, so the block grid covers the plane with **no unwritten margin** —
the last block's last write lands at `cpw·cph − 1` precisely (for 24×16: a
384-byte plane, last write at 383). That is why this path needs no plane
zero-fill and no containment tripwire: with an exact fit, neither could ever
fire.

That property is **conditional on the upsampler being a box filter**. Box reads
exactly `(y·Vi/max_v)·comppw + (x·Hi/max_h)`, never past it. A fancy or triangle
upsampler reads `x+1`, which would make an edge margin live and reopen a
read-of-uninitialized class. Anyone changing the upsampler must revisit this
paragraph, not just the colour pass.

Note also that only **one** grid variable exists per scan. An implementation
carrying a second (a `grid_w` for the block count while `mcu_cols` still sizes
the plane) has two names for one quantity and lets placement diverge from count
— see [`../adr/0006-defer-jpeg-multiscan-resumption.md`](../adr/0006-defer-jpeg-multiscan-resumption.md)
(amended: its claim that the multi-scan cut could *build on* the 0.6.0 collapse
was false, and the amendment records why).

**Termination is the coverage bitmask, not a counter.** A component may be
decoded exactly once, so a file gets at most `Nf` scans and every scan must name
something new; `_jpeg_decode_scans` terminates on `JF_COVERED` rather than on a
scan limit standing in for it. No scan cap and no resume tripwire were added,
because neither could fire before coverage does.

Restart intervals need no change: `Ri` counts MCUs (§ B.2.4.4), an MCU in a
non-interleaved scan is one data unit, and `mi % ri` is already expressed in
MCUs.

## The entropy bit-reader's marker / restart handling

The bit-reader (`BR_SIZE = 56` bytes: base/pos/end/buf/cnt/marker/**eod**) pulls bits
MSB-first over the entropy-coded segment after SOS, and it is where the byte
stream's framing intrudes on the bit stream — a thing a reader cannot derive from
the DECODE algorithm alone:

- **Byte stuffing.** A `0xFF 0x00` pair in the stream is a literal `0xFF` data
  byte (`_jpeg_br_load_byte` loads the `0xFF` and discards the `0x00`).
- **Fill bytes are collapsed first (0.3.3).** T.81 § B.1.1.2 permits a marker to
  be preceded by *any number* of `0xFF` fill bytes, so a run of them is consumed
  before the next byte is classified. Before 0.3.3 the entropy reader took the
  second `0xFF` of such a run as the marker code, which made a well-formed
  `FF FF D0` restart stream fail resync — a **valid file rejected**. The header
  marker walk had always handled this; only the entropy side was missing it, and
  the asymmetry is the thing worth remembering here.
- **Embedded markers stop the reader.** A `0xFF xx` with `xx` neither `0x00` nor
  `0xFF` (an RSTn, EOI, or any marker) is *not* consumed as data: the marker code
  is recorded in `BR_MARKER`, `pos` is left pointing **at the last `0xFF`** (so a
  later resync can re-read it), and `BR_CNT` is left 0 so all subsequent bit reads
  **pad with zeros**. A trailing lone `0xFF` at end-of-data synthesizes an EOI
  (`0xD9`). This zero-padding-past-marker behavior is what lets a truncated or
  marker-terminated scan finish the current block deterministically instead of
  reading out of bounds — but note the same property is what makes the JPEG
  amplification cap necessary (see *Error codes and security ceilings*): a scan
  needs no payload at all to drive a full-size decode.
- **`BR_EOD` — "ran out of scan" (0.7.0/0.8.0).** Zero-padding past a marker is
  indistinguishable from zero-padding past a real EOI, so the marker alone
  cannot say whether the scan actually delivered its data. A separate `BR_EOD`
  flag is set when the reader exhausts its span, read back through
  `_jpeg_br_eod` and folded into the `ChitraImage`'s `seen_iend`. **The reader
  is bounded to the scan's own entropy span**, not to the end of the file —
  which 0.8.0 made necessary, since the bytes after a scan are now the next
  scan's header, and which is also what finally made `seen_iend` honest for a
  file truncated mid-entropy with a real `FF D9` appended.
- **Restart resync.** `_jpeg_decode_one_scan` counts decoded MCUs; when
  `restart_interval > 0` and `mi % ri == 0` (and `mi > 0`), it calls
  `_jpeg_br_restart`, which discards the partial byte (byte-aligns), requires the
  next two bytes to be `0xFF` followed by `0xD0..0xD7` (RSTn), advances past them,
  clears `BR_MARKER`, and the caller resets all DC predictors to 0. A
  missing/malformed restart marker returns −1, surfaced as
  `CHITRA_ERR_JPEG_ENTROPY`.

`_jpeg_decode` and `_jpeg_decode_block` defend the table edges: an undecodable
code (no length ≤ 16 matched, or a symbol index outside the table's `COUNT`)
returns −1 → `CHITRA_ERR_JPEG_ENTROPY`. The magnitude categories are bounded to
their 8-bit baseline ranges — **DC `t > 11`** and **AC `s > 10`** are rejected
(T.81 Tables F.1 / F.2), which is what keeps the subsequent RECEIVE shift and
EXTEND in range — and an AC run that pushes `k > 63` is rejected rather than
overrunning the 64-coefficient block. 0.3.3 closed the one asymmetry here: a
**ZRL** run ending past coefficient 63 used to fall out of the loop as a
*successful* decode while the equivalent run overrun beside it was rejected; it
now raises `CHITRA_ERR_JPEG_ENTROPY` too.

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
   struct-of-arrays sugar, so the scan decoder keeps stack arrays (`preds`,
   `dctabs`, `actabs`, `quants`, `comph`, `compv`) indexed by `comp * 8` (i64
   stride). Two of them — `planes` and `comppw` — live one level up in
   `_jpeg_decode_scans` and are indexed by **frame** component rather than scan
   component, because a plane outlives the scan that fills it (0.8.0: a
   multi-scan file fills each plane in a different scan). Likewise
   `ChitraJpegFrame`'s per-component specs are a flat block of
   4 × `JF_COMP_STRIDE` (32-byte since 0.8.0, when the Huffman selectors moved
   to the scan) records addressed by `JF_COMP + i*JF_COMP_STRIDE + field`. The
   accessor functions (`chitra_jpeg_frame_comp_*`) exist precisely so the rest
   of the code never open-codes that arithmetic.

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
`CHITRA_MAX_DIM` 65535) and gate `_jpeg_parse_sof0` (width/height),
`_jpeg_decode_one_scan` (per-plane byte counts) and `_jpeg_build_image` (the
final RGBA byte count). JPEG adds its own in
`jpeg_markers.cyr`: `CHITRA_MAX_COMPONENTS` 4, `CHITRA_MAX_SAMP_FACTOR` 4,
`CHITRA_MAX_BLOCKS_PER_MCU` 10, `CHITRA_MAX_QUANT_TABLES` 4,
`CHITRA_MAX_HUFF_TABLES` 4, and — since 0.3.3 — `CHITRA_MAX_JPEG_RATIO` 4096,
the output:input amplification ceiling.

That last one is the ceiling a reader is least likely to expect, so it is worth
stating why it exists separately from the byte caps above. The byte caps bound
*one* allocation; the ratio cap bounds the allocation against the **entropy
span** — the bytes the decoder actually decodes, computed by
`_jpeg_entropy_span`, and explicitly **not** whole-file length. 0.6.1 fixed it
after measuring the difference: a 16,556-byte file padded with 16,404 bytes of
*skipped* APPn segments bought a 4096×4096 decode and 117,463,728 bytes, because
padding it never read was inflating its own allowance. The general form of that
lesson — ask what the attacker actually **spent** — is the one BMP-RLE taught in
0.5.3.
JPEG needs that where PNG's equivalent (`CHITRA_MAX_INFLATE_RATIO`) is merely
prudent, because the entropy bit-reader zero-pads past end-of-data: a hostile
file supplies a SOF0 declaring 4096×4096 and then *nothing*, and the decoder
still allocates every plane and runs every IDCT. Combined with the bump
allocator's never-free property (see
[`003-bump-allocator-no-free.md`](003-bump-allocator-no-free.md)) the cost is
cumulative across decodes, so the attack is a handful of ~150-byte files rather
than a stream of large ones.

0.8.0 split the check into **two gates**, because a multi-scan file allocates per
scan: GATE 1 in `_jpeg_decode_one_scan` bounds that scan's planes against that
scan's span, before the planes are allocated; GATE 2 in `_jpeg_decode_scans`
bounds the whole image against the summed spans. Neither alone suffices — the
first misses a file spreading its amplification across many cheap scans, the
second runs too late to stop any single one.

Two further hardening checks are worth naming:
`_jpeg_parse_sof0` rejects `Hi` or `Vi` of 0 (the CVE-2018-11212 div-by-zero
class) and rejects duplicate component ids — but
**not** `ΣHi·Vi > 10`, which 0.8.0 moved to `_jpeg_parse_sos` conditioned on
`Ns > 1`, because § B.2.3 scopes it to an interleaved MCU and applying it
frame-wide rejected files libjpeg writes (the live check is
[`../../src/jpeg.cyr:183`](../../src/jpeg.cyr)); and
`_jpeg_huff_build` rejects an over-subscribed table (`code >= 1<<L`) — the check
that stops a malformed DHT from producing out-of-range code values
([`../../src/jpeg_huffman.cyr`](../../src/jpeg_huffman.cyr) line 72). The marker
walk itself cannot loop forever: every iteration advances ≥ 2 bytes or terminates
on the `can_read(2)` gate ([`../../src/jpeg_markers.cyr`](../../src/jpeg_markers.cyr)
lines 398–443).

**Gap closed in 0.3.3.** The JPEG decoder's hardening lineage is the kii/PNG
fork's, and its byte-buffer / entropy surface was for a long time the one piece
of new attack surface never fuzzed in-tree. `fuzz/fuzz_jpeg.fcyr` now covers it
directly, including **entropy-segment-only mutation** — the header is left valid
so hostile bits reach the bit-reader and `DECODE` rather than being turned away
at the signature gate. `tests/bcyr/chitra.bcyr` measures the path's cost.
The 284 assertions in `jpeg.tcyr`, the 238 in `jpeg_noninterleaved.tcyr` and the
75 in `jpeg_multiscan.tcyr` remain hand-authored known-answer tests
— the byte-identical reference cross-check is correctness evidence, and the fuzz
harness is the generated coverage that complements it.

**Which reference decoder, and when.** `djpeg -nosmooth` is the primary oracle
for every JPEG cell and matches chitra byte-for-byte across the sampling matrix.
ImageMagick is a valid *independent second* oracle only for grayscale and 4:4:4:
it upsamples chroma with a fancy (triangle) filter where chitra and
`djpeg -nosmooth` use box, so on a 4:2:0 file it differs in 937 of 1536 bytes at
up to 40 per byte. That is a filter difference, not a decode bug — do not chase
it. CLAUDE.md's blanket "validate against ImageMagick" rule holds for PNG, BMP
and GIF unqualified, and for JPEG with this narrowing.

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
