# JPEG baseline decoder — the 0.3.0 arc

**Status**: Proposal
**Date**: 2026-06-26

> The implementation plan for adding JFIF baseline sequential JPEG decode
> to chitra, normalizing to the same canonical RGBA8 surface PNG already
> emits. This proposal is the durable record of *what* 0.3.0 builds and
> *why each rejection is a security control*; the decision itself is
> ratified in [`../adr/0004-jpeg-decode-model.md`](../adr/0004-jpeg-decode-model.md),
> and the perimeter discipline it inherits is
> [`../adr/0002-security-model.md`](../adr/0002-security-model.md). The
> roadmap slots this as the "JPEG via 0.3+" item in
> [`../development/roadmap.md`](../development/roadmap.md).

JPEG is the format-agnostic name in `chitra_image_decode` paying off: it
joins without a rename, exactly as the full PNG matrix landed across
0.2.x. kii picks it up on a `[deps.chitra]` re-pin. The arc is
**smallest-first** per AGNOS bite-discipline — each bite decodes (or
hardens) demonstrably more than the last, and every bite carries a test
gate and a security gate.

## Review resolutions (2026-06-26)

This plan was adversarially reviewed before any code landed. The findings
and their resolutions:

- **Initialized-global budget (raised as CRITICAL, now CLOSED).** The
  review estimated the 256-initialized-global cap (from the generic Cyrius
  template) was nearly exhausted (~11 free) and would block bite 1. This
  was **measured empirically** against toolchain `6.2.44`: a probe adding
  400 *used* initialized globals to the smoke unit compiles, links, and
  runs correctly. The 256 figure does **not** bind at this toolchain — the
  JPEG arc's globals have ample headroom. JPEG error codes are `enum`
  members regardless (exempt). Not a constraint.
- **`printf` is unusable** — it faults (SIGILL) in this toolchain; chitra
  code and tests emit via `syscall(1, fd, buf, len)` (the existing idiom),
  never `printf`.
- **Bite 6 split** into 6a (single-component grayscale e2e) and 6b
  (3-component 4:4:4 + YCbCr→RGB) so a first-integration failure has one
  root cause.
- **Sampling-factor guards** (Hi/Vi ∈ 1..4, reject 0 — CVE-2018-11212
  divide-by-zero — reject duplicate component ids, enforce ΣHi·Vi ≤ 10)
  are wired explicitly into **bite 2**'s security gate.
- **Bite 3 test gate** asserts the built `mincode`/`maxcode`/`valptr`
  tables directly (deterministic from Annex K) rather than depending on
  the bite-4 decoder.
- **IDCT factorization committed**: libjpeg `jpeg_idct_islow` (integer,
  13-bit constants) — pinned in [ADR 0004](../adr/0004-jpeg-decode-model.md)
  so the byte-exact RGBA8 contract is reproducible. Worst-case dequantized
  coefficient magnitude is ~2^11 (not 255); i64 intermediates hold with
  margin.
- **`Y == 0`** (DNL-deferred height) is cleanly **rejected**
  (`CHITRA_ERR_DIMENSIONS`); no DNL handling and no 0-height buffer.
- **`src_ctype` sentinel** for JPEG uses an out-of-PNG-range value
  (`0x100 | ncomp`) so a consumer's `0/2/3/4/6` PNG switch never aliases a
  JPEG component count (wired at bite 8).

## Progress

- **Bite 1 — DONE (2026-06-26).** `src/jpeg_markers.cyr`: the byte-cursor
  `_cur_u16_be` helper (in `png_chunks.cyr`), `ChitraJpegFrame` skeleton +
  accessors, `chitra_jpeg_check_signature` (SOI 0xFFD8), and
  `chitra_jpeg_scan_markers` walking SOI → segments → SOS while parsing the
  SOF0 header (precision / dimensions / component count) and rejecting
  progressive / arithmetic / 12-bit / hierarchical-lossless / 4-component
  modes with distinct error codes. 11 JPEG error codes (13–23) appended to
  `error.cyr`. Wired into `lib.cyr` + `cyrius.cyml`. `tests/tcyr/jpeg.tcyr`
  +28 assertions (suite 525 → 553); lint/fmt/vet clean; dist regenerated.
- **Bite 2 — DONE (2026-06-26).** SOF0 per-component parse (id / Hi / Vi /
  quant-selector, max H/V) and DQT quant-table parse into `ChitraJpegFrame`,
  with the sampling-factor security guards (1..4, no zero, no duplicate id,
  ΣHi·Vi ≤ 10). `jpeg.tcyr` +27 assertions (suite 553 → 580). lint/fmt/vet clean.
- **Bite 3 — DONE (2026-06-26).** New `src/jpeg_huffman.cyr` (frame-independent
  table machinery, included before `jpeg_markers.cyr`): canonical Huffman
  decode-table build (`mincode`/`maxcode`/`valptr`, T.81 Annex C + F) with
  over-subscription rejection. DHT parser in `jpeg_markers.cyr` validates
  `Tc/Th`/counts and builds 4 DC + 4 AC tables into the frame. `jpeg.tcyr` +24
  assertions checked against the Annex K.3.3 standard table (suite 580 → 604).
  lint/fmt/vet clean.
- **Bite 4 — DONE (2026-06-26).** Entropy bit-reader (MSB-first, `0xFF00`
  unstuffing, marker detection), Annex F `DECODE` + `RECEIVE`/`EXTEND`, and
  `_jpeg_decode_block` (one 8×8 block → 64 zig-zag coefficients; DC differential,
  AC run/size with ZRL/EOB) in `jpeg_huffman.cyr`. `jpeg.tcyr` +27 assertions,
  incl. a full block decoded from a hand-encoded stream (suite 604 → 631).
  lint/fmt/vet clean.
- **Bite 5 — DONE (2026-06-26).** New `src/jpeg_idct.cyr`: zig-zag→natural map,
  dequantization, the committed libjpeg `jpeg_idct_islow` integer 8×8 IDCT
  (ADR 0004), `+128` level-shift + clamp. DESCALE uses signed round-to-nearest
  division (Cyrius `>>` is logical); `sources.md` IDCT citation promoted from
  provisional to committed. `jpeg.tcyr` +18 assertions — zig-zag table, DC-only
  known-answers with clamps, dequant scaling (suite 631 → 649). lint/fmt/vet clean.
- **Bite 6a — DONE (2026-06-26).** New `src/jpeg.cyr`: public
  `chitra_jpeg_decode -> ChitraImage`. SOS scan-header parse + single-component
  grayscale MCU loop + plane assembly + crop + RGBA8 emit (R=G=B, A=255);
  `source_color_type` = `0x100 | ncomp`. Frame extended with per-component Td/Ta
  + SOS offset. `jpeg.tcyr` +17 assertions decoding a full hand-built 8×8 and
  5×5 grayscale JPEG to pixels (suite 649 → 666). lint/fmt/vet clean. (3-component
  YCbCr returns CHITRA_ERR_UNSUPPORTED until bite 6b.)
- Bites 6b–9: pending.

## Scope

### In scope (what 0.3.0 decodes)

Baseline **JFIF/EXIF** JPEG, the overwhelmingly common subset:

- **SOF0 only** — baseline sequential DCT, Huffman entropy coding,
  **8-bit** sample precision.
- **1 component** (grayscale) or **3 components** (YCbCr). Color converts
  via full-range ITU-R BT.601, the JFIF transform; grayscale replicates Y
  to R=G=B.
- **Chroma subsampling** 4:4:4, 4:2:2, 4:2:0, and the general Hi/Vi case,
  with box/nearest replication upsampling (the conformant-simple choice).
- **Restart markers** (DRI + RST0..RST7) — byte-align, reset DC
  predictors per interval.
- **Marker tolerance** — APP0/JFIF, APP1/EXIF, APP2..APP15, COM are
  parsed for framing (length) then **skipped, never interpreted**. EXIF
  is tolerate-and-skip; orientation is **not** applied to pixels in
  0.3.0 (output stays raw decoded RGBA8 — could surface on `ChitraImage`
  later, marked uncertain).
- **APP14 (Adobe) transform flag** — *if cheaply tracked*, a 3-component
  image with `transform == 0` is treated as direct RGB (no YCbCr math).
  This is a may, not a must; a 3-comp image absent APP14 assumes YCbCr
  per the JFIF default.
- **DNL (Define Number of Lines)** — consulted only when SOF `Y == 0`
  (height arrives after the first scan). Rare; handled or rejected
  explicitly, never allocating a 0-height buffer.
- **Framing tolerance** — leading 0xFF fill bytes skipped; truncated
  streams missing EOI tolerated if all MCUs decoded (analogous to
  chitra's IEND-less `seen_iend` tolerance).

### Out of scope — cleanly rejected with distinct error codes

Each deferred mode is rejected **loud** at the SOF/marker dispatch,
before any of its code paths exist. This is *defer-don't-half-implement*
(the same discipline that governed chitra's pre-0.2.1 Adam7 posture) and
it is simultaneously the **single most effective security control** in
the arc — the most severe recent JPEG CVEs live precisely in these modes
(see [Security hardening](#security-hardening-checklist)).

| Mode | Marker | Rejection |
|---|---|---|
| Extended sequential DCT, Huffman | SOF1 (0xFFC1) | `CHITRA_ERR_JPEG_MODE` — decodable identically to baseline for 8-bit Huffman, but deferred to honor the discipline; trivially upgradeable later (upgrade candidate) |
| Progressive DCT | SOF2 (0xFFC2) | `CHITRA_ERR_JPEG_PROGRESSIVE` (distinct) |
| Lossless (Huffman) | SOF3 (0xFFC3) | `CHITRA_ERR_JPEG_MODE` |
| Differential seq/prog/lossless | SOF5/6/7 | `CHITRA_ERR_JPEG_MODE` |
| Arithmetic (ext-seq/prog/lossless) | SOF9/10/11 | `CHITRA_ERR_JPEG_ARITHMETIC` (distinct) |
| Differential arithmetic | SOF13/14/15 | `CHITRA_ERR_JPEG_ARITHMETIC` |
| Define Arithmetic Conditioning | DAC (0xFFCC) | `CHITRA_ERR_JPEG_ARITHMETIC` |
| Sample precision != 8 (12-bit) | SOF0 P field | `CHITRA_ERR_JPEG_PRECISION` |
| 4-component CMYK/YCCK | SOF Nf==4 / APP14 | `CHITRA_ERR_JPEG_COMPONENTS` |

`SOF1` note: the committed 0.3.0 scope is SOF0 only; SOF1 shares the
exact field layout and is an upgrade candidate, but is rejected cleanly
now rather than silently aliased to the baseline path.

## Decode pipeline

The decode is a marker-driven front half (framing) and a sample-driven
back half (entropy → IDCT → color), mirroring `chitra_png_parse_raw` →
color-pass split.

| Stage | What it does |
|---|---|
| **0. Framing / signature** | Confirm SOI (0xFFD8) at bytes 0..1 via a new `_cur_u16_be` over the existing `png_chunks` cursor. Else `CHITRA_ERR_SIGNATURE` (reused). |
| **1. Marker-segment loop** | Skip 0xFF fill, read the code byte. For length-bearing markers read `Lp` (2 BE, includes its own 2 bytes → payload = `Lp-2`) and slice. Dispatch: APPn/COM → skip; DQT → quant tables; DHT → Huffman tables; DRI → store `Ri`; SOFx → validate mode (only SOF0 accepted) + parse frame header; SOS → stop the loop, entropy stage takes over. RSTn/SOI/EOI/TEM are standalone (no length). |
| **2. Frame setup (SOF0)** | Validate `P==8`; validate/store `Y,X` (apply caps **before any allocation**); read `Nf` (accept 1 or 3, else `CHITRA_ERR_JPEG_COMPONENTS`). Per component store `Ci, Hi, Vi, Tqi`. Compute `Hmax=max(Hi)`, `Vmax=max(Vi)`. |
| **3. Geometry** | MCU pixel size = `8*Hmax` × `8*Vmax`. `mcus_per_row = ceil(X/(8*Hmax))`, `mcus_per_col = ceil(Y/(8*Vmax))`. Per-component sample dims `ceil(X*Hi/Hmax) × ceil(Y*Vi/Vmax)`; per-component block grid padded to whole MCUs (`comp_blocks_w = mcus_per_row*Hi`). Allocate per-component sample planes (block-padded, 1 byte/sample). |
| **4. Scan setup (SOS)** | Read `Ns` and per-component `Td/Ta`; map each `Cs` to the SOF component **by `Ci`, not array position**. Validate `Ss=0, Se=63, Ah=0, Al=0` (else PROGRESSIVE/MODE). Init the entropy bit reader over the post-SOS bytes; reset `DC_pred[comp]=0`; restart counter = 0. |
| **5. Entropy decode loop** | Per MCU in raster order: for each scan component, for `v` in `0..Vi`, for `h` in `0..Hi`, decode one 8×8 block (DC diff via DC Huffman + AC run/size via AC Huffman → 64 zig-zag coefficients). Place into the component plane at `(block-row, block-col)`. After `Ri` MCUs (if `Ri>0`) consume the next RSTn: byte-align + reset DC predictors. |
| **6. Per-block dequant + de-zigzag + IDCT** | Multiply each zig-zag coefficient by the component's quant table, scatter to natural 8×8 via the zig-zag table, run the integer 8×8 inverse DCT, level-shift +128, clamp 0..255, write 64 samples. (Fusable into stage 5 per block.) |
| **7. Chroma upsampling** | Replicate each chroma plane from its subsampled resolution to full `X×Y` by the per-component `Hi/Vi` vs `Hmax/Vmax` ratio. Box/nearest replication. |
| **8. Color conversion → RGBA8** | Grayscale → R=G=B=Y, A=255. YCbCr → RGB via JFIF BT.601 full-range fixed-point, A=255. Honor APP14 `transform==0` (direct RGB) if tracked. Crop block-padded planes to real `X,Y` at the pixel write. |
| **9. Wrap** | Allocate `ChitraImage` (reuse the 48-byte struct), `width=X`, `height=Y`, `pixels=RGBA8 (X*Y*4)`, `channels=4`. Surface end-state (saw EOI / truncated) analogous to `seen_iend`. Return img, or 0 + `*err_out`. |

## Module layout

Six new `src/jpeg_*.cyr` modules. The split is **organizational only** —
all modules concatenate into one compilation unit (`dist/chitra.cyr`),
so the global function/var/global budgets are shared, not relieved (see
[Risks](#risks) and [`../architecture/002-flat-modules-distlib-concatenation.md`](../architecture/002-flat-modules-distlib-concatenation.md)).

| File | Owns | Deps |
|---|---|---|
| `src/jpeg_markers.cyr` | Marker/segment framing. Adds `_cur_u16_be` to the shared cursor (placed in `png_chunks.cyr`). `ChitraJpegFrame` byte-offset struct + accessors. `chitra_jpeg_check_signature` (FFD8). `chitra_jpeg_scan_markers`: walk SOI..SOS, dispatch DQT/DHT/SOF0/SOS/DRI, skip APPn/COM/JFIF/EXIF, reject deferred modes loud. Parses DQT + SOF0 into the frame struct. | `error.cyr`, `png_chunks.cyr` |
| `src/jpeg_huffman.cyr` | Huffman tables + entropy substrate (chitra's own — no sankoch analog). Parse DHT → canonical `mincode/maxcode/valptr` per T.81 Annex C/F; store up to 4 DC + 4 AC. The **new bit-reader struct** over the entropy span: MSB-first pull, 0xFF00 unstuffing, RSTn detection. `_jpeg_decode_huff`, `_jpeg_receive(n)`, `_jpeg_extend`. | `error.cyr`, `png_chunks.cyr` |
| `src/jpeg_idct.cyr` | Per-block reconstruction: the 64-entry zig-zag de-order table (built at init into a buffer, **not** 64 literal globals), dequant, integer fixed-point separable 8×8 inverse DCT (i64 with right-shift rounding), level-shift +128, clamp. | `error.cyr` |
| `src/jpeg_scan.cyr` | Parse-driver analog (mirrors `chitra_png_parse_raw`). `chitra_jpeg_decode_planes`: allocate padded-MCU planes (caps validated first), run the MCU loop honoring H/V factors + table selectors, maintain per-component DC predictors, reset + realign on each restart, call huffman + idct per data unit. | `error.cyr`, `jpeg_markers.cyr`, `jpeg_huffman.cyr`, `jpeg_idct.cyr` |
| `src/jpeg_color.cyr` | Chroma upsample + colorspace → RGBA8. Box/replicate upsample (4:4:4 passthrough, 4:2:2, 4:2:0, general), integer fixed-point YCbCr→RGB (BT.601 full-range) with clamp, grayscale replicate, alpha forced 255. Writes `width*height*4`, cropped from padded planes. | `error.cyr`, `jpeg_scan.cyr` |
| `src/jpeg.cyr` | Public JPEG API + top-level dispatch + version bump. `chitra_jpeg_decode` → `ChitraImage` (reuses the 48-byte struct; `channels=4`, `src_ctype` a JPEG sentinel reflecting component count). `chitra_jpeg_decode_rgba8`. `chitra_image_decode` signature router. `chitra_version() → 300`. | `error.cyr`, `png.cyr` (ChitraImage), `jpeg_markers.cyr`, `jpeg_scan.cyr`, `jpeg_color.cyr` |

### `cyrius.cyml` `[lib].modules` order

Module order matters under the flat-concatenation invariant (declared
before use). The new modules append after the PNG chain:

```
src/error.cyr
src/png_chunks.cyr
src/png_filter.cyr
src/png_color.cyr
src/png.cyr
src/jpeg_markers.cyr
src/jpeg_huffman.cyr
src/jpeg_idct.cyr
src/jpeg_scan.cyr
src/jpeg_color.cyr
src/jpeg.cyr
```

Don't reorder without re-running `cyrius distlib` and verifying the
bundle still compiles clean.

## New error codes

Eleven codes appended to `src/error.cyr` (values 13–23), each with a
name string in `chitra_err_name`. Distinct codes per deferred mode so a
diagnostic names the rejected mode precisely.

| Name | Value | Meaning |
|---|---|---|
| `CHITRA_ERR_JPEG_MARKER` | 13 | malformed/misplaced marker or bad 16-bit segment length (framing) |
| `CHITRA_ERR_JPEG_SOF` | 14 | invalid SOF0 frame header: bad precision/component count/sampling/dims-vs-data |
| `CHITRA_ERR_JPEG_DQT` | 15 | malformed DQT: bad Pq/Tq id or truncated table |
| `CHITRA_ERR_JPEG_DHT` | 16 | malformed DHT or Huffman build failure (counts overflow / bad Tc/Th) |
| `CHITRA_ERR_JPEG_SOS` | 17 | malformed SOS scan header: bad component selector / table refs / Ss-Se-Ah-Al |
| `CHITRA_ERR_JPEG_ENTROPY` | 18 | corrupt entropy stream: undecodable Huffman code, bit overrun, or bad RSTn |
| `CHITRA_ERR_JPEG_PROGRESSIVE` | 19 | deferred: progressive DCT (SOF2) — baseline-only in 0.3.0 |
| `CHITRA_ERR_JPEG_ARITHMETIC` | 20 | deferred: arithmetic coding (SOF9/10/11 or DAC) — Huffman-only in 0.3.0 |
| `CHITRA_ERR_JPEG_PRECISION` | 21 | deferred: sample precision != 8 (12-bit) — 8-bit-only in 0.3.0 |
| `CHITRA_ERR_JPEG_MODE` | 22 | deferred: hierarchical/lossless/differential SOF (SOF3/5/6/7/13/14/15) |
| `CHITRA_ERR_JPEG_COMPONENTS` | 23 | deferred: unsupported component count (4-comp CMYK/YCCK / Adobe APP14) |

`CHITRA_ERR_SIGNATURE` (1) and `CHITRA_ERR_TRUNCATED` (2) are reused for
the SOI check and short segments respectively. `CHITRA_ERR_DIMENSIONS`
(10) and `CHITRA_ERR_OOM` (6) are reused for the size caps.

## Public API + format dispatch

| Signature | Purpose |
|---|---|
| `fn chitra_jpeg_decode(src, len, err_out): i64` | Decode baseline JFIF/EXIF bytes → owned RGBA8 `ChitraImage` ptr; 0 on failure with `*err_out` set (mirrors `chitra_png_decode`'s (ptr, err_out) Ok/Err split). Reuses the 48-byte `ChitraImage` (channels=4, alpha 255); `src_ctype` carries a JPEG sentinel (component count). |
| `fn chitra_jpeg_decode_rgba8(src, len, w_out, h_out): i64` | Convenience wrapper: returns the RGBA8 pixel ptr, writes width/height; 0 with w/h zeroed on failure. Mirrors `chitra_png_decode_rgba8`. |
| `fn chitra_image_decode(src, len, err_out): i64` | Top-level format-dispatching decode: sniff the signature and route. Returns `ChitraImage` ptr or 0 with `*err_out=CHITRA_ERR_SIGNATURE` when neither matches. Recommended entry for format-agnostic consumers (mabda). |
| `fn chitra_version(): i64` | Bump 201 → 300 (0.3.0) to signal JPEG support. |

**Dispatch placement.** `chitra_image_decode` lives in `src/jpeg.cyr` —
the last module — because it is the only place that can see *both*
`chitra_png_decode` (png.cyr) and `chitra_jpeg_decode` (jpeg.cyr)
declared-before-use under the flat-concatenation invariant
([`../architecture/002-flat-modules-distlib-concatenation.md`](../architecture/002-flat-modules-distlib-concatenation.md)).
It length-guards then sniffs: if `len>=2 && src[0]==0xFF && src[1]==0xD8`
route to JPEG; else if `chitra_png_check_signature(src,len)==1` route to
PNG; else store `CHITRA_ERR_SIGNATURE` and return 0. The 0xFF/0xD8 test
is written as nested ifs (or the single-`&&` form the cursor already
uses) to respect the no-mixed-`&&`/`||` rule.
`chitra_jpeg_check_signature` mirrors `chitra_png_check_signature`
(returns 0/1) as the reusable predicate. The existing public
`chitra_png_decode` and the new `chitra_jpeg_decode` stay directly
callable for callers that already know the format.

## The bite sequence

Numbered, smallest-first. Each bite has a test gate and a security gate;
none lands without both green.

| Bite | Deliverable | Test gate | Security gate |
|---|---|---|---|
| **1** | Error codes + markers skeleton + signature/segment scan + defer-rejects | Append the 11 codes (13–23) + names in `error.cyr`; add `_cur_u16_be` to `png_chunks.cyr`; create `jpeg_markers.cyr` (`ChitraJpegFrame`, `chitra_jpeg_check_signature`, `chitra_jpeg_scan_markers` skipping APPn/COM and rejecting SOF2/SOF9-11/DAC/SOF3-7/precision!=8/ncomp-not-1-or-3 with distinct codes). Wire all six `jpeg_*.cyr` into `lib.cyr` + `cyrius.cyml`. | `jpeg.tcyr`: `_cur_u16_be` reads a known BE u16; valid SOI accepted; non-FFD8 → SIGNATURE; truncated segment → TRUNCATED; hand-built SOF2/SOF9/12-bit/4-comp → PROGRESSIVE/ARITHMETIC/PRECISION/COMPONENTS. Smoke build links clean. | Every segment-length read bounds-checked via `_cur_can_read` before access; deferred modes rejected before any allocation. |
| **2** | DQT + SOF0 parse into frame struct | Parse DQT (8-bit Pq only; Tq<4; 64 bytes) + SOF0 (precision=8, ncomp, per-comp id/h/v/quant-sel, max_h/max_v); validate dims vs caps. | Parse a baseline SOF0+DQT fixture: assert width/height/ncomp/sampling/quant entries; 70000×70000 → DIMENSIONS; bad Tq/Pq → JPEG_DQT; malformed SOF0 → JPEG_SOF. | Dimension + pixel caps enforced before any plane alloc; quant/component indices range-checked. |
| **3** | DHT parse + canonical Huffman table build | `jpeg_huffman.cyr`: parse DHT (Tc/Th<4, bits[16], value list, total≤256) → canonical mincode/maxcode/valptr; store up to 4 DC + 4 AC. | Feed the standard Annex K tables; assert known code→symbol decodes; oversized/inconsistent counts → JPEG_DHT. | Sum of bit counts validated ≤256 and against segment length before building; no value-list overrun. |
| **4** | Entropy bit-reader + one-block DC/AC decode | Bit-reader struct (MSB-first, 0xFF00 unstuffing, RSTn detection) + `_jpeg_decode_huff` + `_jpeg_receive`/`_jpeg_extend`; decode one 8×8 block's 64 zig-zag coefficients. | Decode a hand-crafted single-block stream (with an embedded 0xFF00 stuff byte) to a known 64-coefficient vector; truncated → JPEG_ENTROPY. | Bit reads clamped to the entropy span; undecodable code (pos past maxcode) returns JPEG_ENTROPY, never loops/OOB. |
| **5** | Dequant + zigzag + integer IDCT + level-shift | `jpeg_idct.cyr`: init the zig-zag de-order table, dequant, fixed-point separable 8×8 IDCT, level-shift +128, clamp. | Known-answer: a DC-only block → uniform mid-gray; a published 8×8 coefficient block → expected samples within ±1 of a reference integer IDCT. | i64 accumulators sized so worst-case `coeff*quant*basis` stays within i64; output clamped to [0,255]. |
| **6** | Full MCU loop: 4:4:4 grayscale + YCbCr | `jpeg_scan.cyr` MCU driver for the no-subsampling case (all h=v=1) → component planes; `jpeg_color.cyr` grayscale-replicate + YCbCr→RGB → RGBA8; `chitra_jpeg_decode` assembling a `ChitraImage`. | End-to-end decode of tiny 8×8 (and 16×16) grayscale + 4:4:4 YCbCr; assert RGBA8 vs a reference decoder (alpha 255). | Plane allocs sized from validated padded MCU grid; output buffer = `width*height*4` with overflow-checked multiply. |
| **7** | Chroma subsampling (4:2:2 / 4:2:0 / general) + restart markers | Generalize the MCU loop to H/V factors with per-component data-unit ordering; box/replicate upsample; honor DRI + RST0-7 (reset predictors, realign bit-reader). | Decode 4:2:0 + 4:2:2 fixtures + a small-restart-interval fixture; assert pixels vs reference; corrupt/missing RSTn → JPEG_ENTROPY. | Subsampled plane sizes + upsample indexing bounds-checked; restart realignment cannot read past the entropy span. |
| **8** | Format dispatch + version bump + real-image e2e | `chitra_jpeg_decode_rgba8`, `chitra_image_decode` sniffer (FFD8 vs PNG magic), `chitra_version() → 300`, VERSION → 0.3.0, cyml description update. | `chitra_image_decode` routes a JPEG fixture and a PNG fixture correctly; garbage → SIGNATURE; decode a real small photographic baseline JPEG e2e + spot-check pixels; `chitra_version() == 300`. | Dispatcher length-guards both signatures before reading; non-matching input rejected with no allocation. |
| **9** | Hardening pass + audit doc + docs | Adversarial fixtures (truncated scan, junk between segments, oversized DHT, zero dims, missing SOF/SOS), confirm distinct codes; add an architecture note + an audit doc mirroring the kii 2026-05-22 findings; update README scope to 0.3.0. | Full adversarial suite green; each malformed input yields its specific code, no crash/hang/OOB. | Fuzz-style truncation at every byte offset of a valid JPEG never crashes; all caps (pixels/dim/raw-bytes) verified for JPEG inputs. |

## Security hardening checklist

JPEG reopens decode surface that the PNG-only model (
[`../adr/0002-security-model.md`](../adr/0002-security-model.md)) did not
cover. The defense-at-perimeter posture is unchanged — *every byte is
validated before any allocation or loop bound depends on it* — but JPEG
adds an attacker-controlled coefficient/MCU sizing surface and an
entirely new entropy bit-reader substrate (the most fuzzer-reachable
code chitra has). The CVE corpus this checklist defends against is JPEG-
specific (stb_image, libjpeg-turbo, Go image/jpeg, jpeg-decoder/jpeg-js)
and is **referenced, not duplicated** — see [`../sources.md`](../sources.md)
and the per-item refs below.

### New caps (atop the existing PNG caps)

The existing `CHITRA_MAX_PIXELS` (16777216), `CHITRA_MAX_DIM` (65535),
and `CHITRA_MAX_RAW_BYTES` (256 MB) apply **unchanged** to JPEG
width/height and the RGBA output + MCU buffers. `CHITRA_MAX_INFLATE_RATIO`
is PNG/DEFLATE-only and does **not** apply to JPEG.

| Cap | Value | Role |
|---|---|---|
| `CHITRA_MAX_COMPONENTS` | 4 | parse/storage ceiling; decode accepts only Nf==1 (gray) or Nf==3 (YCbCr); Nf==4 rejected as CMYK/YCCK-deferred |
| `CHITRA_MAX_SAMP_FACTOR` | 4 | Hi and Vi each in 1..4 (JPEG spec); rejects 0 (div-by-zero) and >4 (sampling-factor OOM) |
| `CHITRA_MAX_BLOCKS_PER_MCU` | 10 | JPEG spec ceiling on `sum(Hi*Vi)`; bounds `blocks_per_mcu` + the MCU coefficient buffer |
| `CHITRA_MAX_HUFF_TABLES` | 4 | Huffman slots per class (DC, AC); baseline uses 0..1, storage allows 0..3 |
| `CHITRA_MAX_QUANT_TABLES` | 4 | DQT destination slots (Tq 0..3) |
| `CHITRA_MAX_HUFF_CODE_LEN` | 16 | maximum Huffman code length; bounds the decode walk (no unbounded loop) + the BITS array |
| `CHITRA_MAX_HUFFVAL` | 256 | maximum `sum(BITS)` / HUFFVAL symbol count per table |
| `CHITRA_MAX_MCUS` | derived (e.g. `CHITRA_MAX_PIXELS/64`) | checked against `mcu_cols*mcu_rows` before allocating coefficient/component buffers |

### Guard inventory

The mode-rejection dispatch is itself the headline control: accepting
**only SOF0** removes the most severe JPEG CVE classes (progressive DC
accumulation, 12-bit/lossless sample-range overflows, arithmetic state
machines, CMYK color-transform overruns) before any of their code paths
exist.

| # | Guard | Where | Severity |
|---|---|---|---|
| 1 | Dispatch on SOF; accept **only SOF0** (baseline, 8-bit, Huffman); reject SOF2/SOF3/SOF5-7/SOF9-15/DAC, precision!=8, Nf==4/APP14 CMYK — each a distinct code | marker state machine | critical |
| 2 | Validate dims before any alloc, reusing caps: `0<w<=CHITRA_MAX_DIM`, `0<h<=CHITRA_MAX_DIM`, `w*h<=CHITRA_MAX_PIXELS`, in i64 → DIMENSIONS | SOF0 parse | critical |
| 3 | Bound Hi, Vi each in 1..`CHITRA_MAX_SAMP_FACTOR`; reject 0 (div-by-zero) + >4 (OOM); reject duplicate component ids | SOF0 component loop | critical |
| 4 | `sum(Hi*Vi) <= CHITRA_MAX_BLOCKS_PER_MCU` (=10) so `blocks_per_mcu` + the MCU buffer are provably bounded | SOF0 post-parse | high |
| 5 | Derive maxH/maxV, mcu_cols, mcu_rows, blocks_per_mcu in i64; check `mcu_cols*mcu_rows*blocks_per_mcu*64` and `w*h*4` against `CHITRA_MAX_RAW_BYTES` before alloc; no power-of-two buffer growth | MCU/coefficient + output sizing | critical |
| 6 | DHT: Tc/Th in {0,1}; read 16 BITS; require `sum(BITS)<=256` AND `== HUFFVAL bytes implied by segment length`; enforce Kraft inequality during canonical-code gen (reject over-subscribed/over-long codes); zero each table slot on alloc | DHT handler / Huffman builder | critical |
| 7 | DQT: `Pq==0` (8-bit) for baseline; `Tq` in {0..3}; read exactly 64 entries per table, cursor-bounds-checked; iterate tables only while segment bytes remain; track defined Tq slots | DQT handler | high |
| 8 | SOS: each `Cs` matches an SOF component; `Td/Ta` in {0,1} and referenced DC/AC tables **and** the component's Tq flagged 'defined'; `Ns` in 1..Nf; `Ss==0,Se==63,Ah==0,Al==0`; reject SOS-before-SOF | SOS handler | critical |
| 9 | Entropy bit-reader returns a hard EOF/error sentinel when scan data is exhausted; every caller checks it and aborts (TRUNCATED/ENTROPY) — no spin past end-of-data; 0xFF00 unstuffing; 0xFF + non-00 non-RSTn byte = end-of-entropy | entropy bit-reader | critical |
| 10 | Huffman decode walks at most 16 bits then declares 'invalid code' and errors — no unbounded loop (flag+continue idiom, not break) | Huffman inner loop | critical |
| 11 | AC index bound: after each (run,size), advance `k` by `run+1` and require `k<=63` **before** writing into the 64-entry block; `receive_and_extend` size 0..15 (DC 0..11); block is exactly 64 zero-init cells; de-zigzag via fixed 64-entry table indexed only by bounds-checked `k` | block decode | critical |
| 12 | Restart: byte-align, expect `RST(n mod 8)`, reset all DC predictors to 0; if expected RSTn absent, end the scan (don't loop searching); tolerate `Ri==0`; no alloc keyed off `Ri` | DRI handler + scan loop | high |
| 13 | Checked/guarded integer arithmetic for the DC predictor accumulator and coefficient math (i64, unsigned where possible; no negative literals — write `(0 - N)`; guard before any subtract) | DC prediction | high |
| 14 | Chroma upsample + color convert: allocate planes at padded MCU dims but clamp every source read to plane size + every output write to true w/h (nested ifs, not mixed `&&`) | upsample / color pass | high |
| 15 | YCbCr→RGB integer fixed-point, clamp each channel to [0,255] before store8; alpha hard-set 255; no floats | color pass | medium |
| 16 | Add bounds-checked `_cur_u16_be`; for every length-bearing marker require `length>=2` and `_cur_can_read(length-2)` before skipping; reject length past EOF (TRUNCATED) | `png_chunks.cyr` cursor + marker loop | high |
| 17 | Marker state machine: require leading SOI; skip 0xFF fill; enforce SOI → tables/APPn → SOF (exactly one) → tables → SOS → entropy → EOI; reject duplicate SOF, data-before-SOI, SOS-before-SOF | top-level walker | high |
| 18 | APPn / APP1(EXIF) / APP14(Adobe) / COM **skipped by length, never parsed** — no EXIF/IFD interpretation (kills the self-referential-IFD recursion surface) | APPn/COM handling | medium |
| 19 | Reject zero-scan / missing SOS / missing SOF / no entropy data with a clean distinct error (analog of `CHITRA_ERR_NO_IDAT`), never partial/garbage output | completion check | medium |
| 20 | Per-segment sanity cap: reject any single marker segment length above a fixed ceiling (tied to `CHITRA_MAX_RAW_BYTES`) to bound APPn/COM skip work | marker length read | low |
| 21 | Add a fuzz surface (mirroring kii M7b): crafted SOF dims/sampling, malformed DHT BITS/HUFFVAL, DQT precision, SOS selectors, truncated entropy, restart desync, AC-run>63 — assert clean error or clean decode, zero crashes/hangs | `tests/tcyr/jpeg.tcyr` | medium |

**CVE classes defended** (referenced, not duplicated — full citations in
[`../sources.md`](../sources.md)): dimension/MCU-geometry memory bomb (Go
image/jpeg #10532, libjpeg sampling-factor OOM); integer-overflow →
undersized alloc → heap-overflow (stb #1928, OSS-Fuzz #32803,
CVE-2022-28041); DHT construction (CVE-2022-28042, CVE-2013-6630, stb
#1291); DQT precision/index (libjpeg-turbo #668/#677, CVE-2013-6629/6630);
SOF component bounds (CVE-2013-6629 duplicate component, CVE-2018-11212
div-by-zero); SOS selector validation (golang #10447/#10387); entropy DoS
/ infinite loop (jpeg-decoder #132, jpeg-js CVE-2022-25851, golang #10387);
AC index OOB (CVE-2022-28041/28042); restart desync (golang #10387);
chroma upsample OOB (CVE-2023-2804); YCbCr UB-shift (OSS-Fuzz #36193);
marker framing (lodepng #221 EXIF-IFD recursion, stb CVE-2023-45663).

## Math summary

All math is **integer fixed-point** for determinism — chitra is
all-integer, and a float IDCT or float color transform risks
cross-platform output drift against the RGBA8 contract (this is a hard
constraint; see [`../adr/0004-jpeg-decode-model.md`](../adr/0004-jpeg-decode-model.md)).

- **Inverse DCT** — separable two-pass (rows then columns) 8×8 integer
  IDCT with documented right-shift rounding and a fixed scaling, so
  output is bit-reproducible. Worst-case intermediate range (`dequantized
  coeff` up to ~`255*255`, accumulated across a separable pass) must stay
  within i64; pick the scale shifts (e.g. an integer AAN or a libjpeg
  `jpeg_idct_islow`-style Loeffler factorization) with documented
  intermediate ranges. Source: ITU-T T.81 Annex A.3.3 (8×8 inverse DCT
  definition); Loeffler/Ligtenberg/Moschytz factorization; libjpeg
  `jidctint.c` (`islow`) as the integer reference. (Cited in
  [`../sources.md`](../sources.md).)
- **Dequantization + zig-zag** — each zig-zag coefficient is multiplied
  by the component's quant-table entry, then scattered to natural 8×8
  order via the 64-entry zig-zag table *before* the IDCT. Both the DQT
  values (stored zig-zag) and the AC coefficients (produced zig-zag) ride
  the same table — mixing natural/zig-zag indices is the classic silent
  corruption. Source: ITU-T T.81 Annex A.3.6 + Figure A.6 (zig-zag
  sequence), § B.2.4.1 (quantization-table spec).
- **Level shift** — samples were shifted by −128 before the forward DCT,
  so after the inverse DCT add 128 and clamp to [0,255]
  (`clamp(IDCT + 128, 0, 255)`). Under the no-negative-literal rule write
  `(0 - 128)` style. Source: ITU-T T.81 § A.3.1.
- **Receive-and-extend (sign reconstruction)** — after reading `S` bits
  as unsigned `V`, if `V < (1 << (S-1))` then `V -= (1<<S) - 1`. `S==0`
  short-circuits to 0 (do not read 0 bits and extend). Source: ITU-T T.81
  § F.2.2.1 + Figure F.12 (EXTEND procedure).
- **YCbCr → RGB** — full-range ITU-R BT.601 (the JFIF transform), integer
  fixed-point (standard 16-bit-shift coefficients), each channel clamped
  to [0,255] before store8. Clamp happens at **two** places: after IDCT +
  level-shift (per sample) and again after the color convert (it can
  overshoot). Both saturate, never wrap. Source: ITU-R BT.601; JFIF v1.02
  (color-conversion equations); libjpeg `jdcolor.c` fixed-point
  coefficients. The BT.601 coefficients are full of negatives (e.g.
  −0.344, −0.714) — every constant written as `(0 - N)`.
- **Chroma upsampling** — box/nearest replication from the subsampled
  plane (`ceil(X*Hi/Hmax) × ceil(Y*Vi/Vmax)`) to full `X×Y`. The
  conformant-simple choice; bilinear interpolation is *not* in 0.3.0
  scope. Source: ITU-T T.81 § A.2.1 (sampling) + JFIF chroma-positioning
  convention.

## Test plan

Fixtures follow the existing `png.tcyr` pattern exactly: a standalone
`tests/tcyr/jpeg.tcyr` that includes `src/lib.cyr` + `lib/assert.cyr`,
owns `main` + `assert_summary`, with `fx_*` builders that alloc a buffer,
store the exact bytes, and set `*len_out` (no file I/O).

- **Generation** — a throwaway Python script using Pillow
  (`PIL.Image.save` quality/subsampling args) emits the smallest possible
  baseline JPEGs (8×8 and 16×16) for grayscale, 4:4:4, 4:2:2, 4:2:0, and
  a DRI/restart variant; a hexdump-to-`store8` emitter turns each into an
  `fx_` builder, and the same script re-decodes each fixture to produce
  the ground-truth RGBA8 asserted with the `_assert_px` helper (copied
  from `png.tcyr`).
- **Layered known-answer tests** so failures localize: (1) a hand-built
  8×8 entropy stream → known 64 coefficients (bit-reader/Huffman bite);
  (2) a published 8×8 DCT coefficient block (the classic JPEG-spec worked
  example) → expected spatial samples within ±1 (IDCT bite), plus a
  DC-only block → uniform gray; (3) the JPEG Annex K standard
  luminance/chrominance Huffman tables (table-build bite).
- **Adversarial fixtures** hand-built by mutating valid bytes: non-FFD8
  signature, truncated-at-offset-N, SOF2/SOF9/12-bit/4-component headers,
  oversized DHT counts, zero dimensions, missing SOF/SOS, corrupt restart
  marker — each asserting its specific `CHITRA_ERR_*` code.
- **Real-image e2e** — a real small photographic baseline JPEG (a few
  hundred bytes) embedded for bite 8, pixels spot-checked against the
  reference re-decode (±1 for IDCT rounding).
- Wire `tests/tcyr/jpeg.tcyr` into the existing test runner alongside
  `png.tcyr`.

## Risks

- **Compilation-unit limits are global, not per-module.** Per-unit
  limits (1024 functions / 4096 vars / 256 globals) apply to the *whole*
  concatenated `dist/chitra.cyr`. stdlib + sankoch + the 5 png_* modules
  already consume budget; splitting JPEG into 6 modules is organizational
  only — it does **not** relieve the limits. The MCU loop + Huffman +
  IDCT add many functions; budget must be tracked, helpers kept lean
  (target well under 1024 total fns). See
  [`../architecture/002-flat-modules-distlib-concatenation.md`](../architecture/002-flat-modules-distlib-concatenation.md).
- **256 initialized-globals cap.** The 64-entry zig-zag table (and any
  IDCT cos/scale tables) must **not** be 64+ `var` globals. Build them
  once at init into a heap/alloc buffer or fill a fixed array at runtime
  (an init fn), as PNG already does for computed tables.
- **Fixed-point overflow in the i64 IDCT.** Dequantized coeff (up to
  ~`255*255`) times accumulated basis sums across a separable pass can
  grow large; choose scale shifts with documented intermediate ranges so
  worst-case intermediates stay within i64 and rounding is deterministic.
  No f64.
- **No negative literals.** IDCT/YCbCr math is full of negatives
  (level-shift, BT.601 coefficients). Every constant written as `(0 - N)`;
  `_jpeg_extend` (sign extension of Huffman magnitudes) is especially
  error-prone under this rule.
- **No mixed `&&`/`||` and unreliable `break` in while-with-var.** The
  MCU loop, bit-reader inner loops, and marker scanner all want compound
  conditions and early exits — written as nested ifs + flag/continue,
  bug-prone in the tight entropy path (off-by-one bit reads).
- **The entropy bit-reader is the highest-risk new substrate** (no
  sankoch analog): 0xFF00 unstuffing, RSTn alignment, and end-of-data
  handling must be bounded against the entropy span on **every** bit
  pull, or an attacker-crafted stream causes OOB/hang. Undecodable codes
  must terminate with JPEG_ENTROPY, never spin.
- **Plane/MCU sizing arithmetic.** Padded MCU-grid dimensions (ceil to
  `8*max_h`, `8*max_v`) times components can overflow before the pixel cap
  check — validate dims and multiply with overflow guards **before**
  allocation, reusing the existing caps.
- **Subsampling generality.** The general H/V case (beyond
  4:4:4/4:2:0/4:2:2) and component data-unit interleave order is easy to
  get subtly wrong; mitigated by the smallest-first bite order (4:4:4
  first, then subsampling) and per-case fixtures.
- **`ChitraImage.src_ctype` reuse.** The field is PNG-color-type-shaped;
  storing a JPEG sentinel (component count) risks confusing consumers
  that switch on PNG color_type values 0/2/3/4/6 — document the JPEG
  encoding distinctly (an out-of-PNG-range sentinel).

## References

- [`../adr/0004-jpeg-decode-model.md`](../adr/0004-jpeg-decode-model.md) — the ratified decode-model decision this plan implements
- [`../adr/0002-security-model.md`](../adr/0002-security-model.md) — the defense-at-perimeter posture JPEG inherits
- [`../audit/2026-06-26-audit.md`](../audit/2026-06-26-audit.md) — the PNG audit whose shape the bite-9 JPEG audit mirrors
- [`../sources.md`](../sources.md) — citation index (T.81, IDCT, BT.601, zig-zag, plus the JPEG CVE corpus)
- [`../development/roadmap.md`](../development/roadmap.md) — the "JPEG via 0.3+" roadmap slot
- [`../architecture/002-flat-modules-distlib-concatenation.md`](../architecture/002-flat-modules-distlib-concatenation.md) — the flat-concatenation invariant governing module order + global budgets
- [`../../CLAUDE.md`](../../CLAUDE.md) — spec-only-feature-set / defer-don't-half-implement discipline
- [ITU-T T.81 (JPEG)](https://www.w3.org/Graphics/JPEG/itu-t81.pdf) — Annex A (DCT/sampling), Annex B (marker/segment syntax), Annex C/F (Huffman + entropy decode), Annex K (example tables)
