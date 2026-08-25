# chitra — Roadmap

> **Last Updated**: 2026-08-24 (1.0.0)
>
> Sequencing — what ships, in what order, against what gates. Volatile state
> (current version, sizes, assertion counts, in-flight work) lives in
> [`state.md`](state.md), not here. **chitra is at 1.0.0 and the public surface
> is frozen** — the 29 names in [`public-surface.md`](public-surface.md) plus
> both record layouts, gated by `scripts/check-surface.sh` on every
> `make lint`. All four decode paths are **feature-complete for their scope**:
> every spec-legal PNG depth × colour-type × interlace combination, JFIF
> baseline JPEG including the full T.81 § A.2 scan model, BMP with an empty
> deferral list, and GIF's first frame. Hardening infrastructure landed in
> 0.3.3; four audits have reviewed every format line by line.
>
> **What the roadmap is for now**: the two tracking items below that 1.0.0 did
> not close (the sankoch pin bump and the downstream consumer pins), and the
> post-1.0 possibilities in *Out of scope* — most of which now need a **major**
> bump or a new entry point rather than a minor, which is exactly what the
> freeze was for.

The roadmap is **smallest-first** per AGNOS bite-discipline: each release is a
single coherent cycle that decodes demonstrably more (or hardens demonstrably
more) than the last. chitra is a **library** — there is no CLI, no stdout
emit, no terminal surface; releases are measured in decode coverage and ABI
stability, not user-facing commands.

## Shipped

Per-release detail, per-bite provenance, and deferrals live in
[`../../CHANGELOG.md`](../../CHANGELOG.md); this table is the index.

| Release | Headline |
|---|---|
| [1.0.0](../../CHANGELOG.md#100---2026-08-24) | **The public API and ABI are frozen.** The **29 names** in [`public-surface.md`](public-surface.md) — ten decode entry points, four signature predicates, eight `ChitraImage` accessors, six error-API functions and `chitra_version` — plus the 56-byte `ChitraImage` and 16-byte `ChitraErr` layouts and the `ChitraErrCode` numeric values now require a **major bump and an ADR** to change. The other **45** `chitra_*` names the bundle exports are listed in that same file as internal and are explicitly not covered. **No code changed in this cut except the version literal**, which is the point: 0.9.0 spent every prerequisite, so the release promising stability does not itself churn the thing it promises about. The promise's *edges* are stated as deliberately as its contents — the internal names, `chitra_err_name`'s human-readable strings (the **codes** are frozen; match on those), bit-exact output across releases (the contract is *correct* RGBA8 held to external oracles — 0.7.1's § 13.13 rescaling changed every 16-bit PNG's output and was a fix), and memory behaviour are all outside it. Coverage at the freeze: full PNG matrix + Adam7, JFIF baseline JPEG including the complete T.81 § A.2 scan model, BMP with an empty deferral list, GIF first frame. Four audits, every format line-by-line reviewed. |
| [0.9.0](../../CHANGELOG.md#090---2026-08-24) | **Freeze prep** — every prerequisite the roadmap had listed, spent in one cut so 1.0.0 could be code-churn-free. Two measured facts drove it: **mabda calls two names, kii calls nine**, so a rename is cheap in the abstract and expensive against that list. Adds **`chitra_image_source_depth`** at +48 (`ChitraImage` 48 → 56 bytes, append-only) because the output is always 8 bits per channel and a consumer could not otherwise tell that § 13.13 rescaling had discarded precision — added *now* because adding it after the freeze is an ABI event. Adds **`public-surface.md` + `scripts/check-surface.sh`** to `make lint`: the bundle is a strip-concatenation, so all **74** exported `chitra_*` names are callable and **45 are internal**, and until this gate existed "the surface is frozen" was an assertion with nothing behind it — it fails in both directions and both were proven to fire. **Two `chitra_err_name` strings changed** (`INTERLACE`, `BIT_DEPTH`) because both read as capability limits when both are validity rejections. Two things deliberately *not* done: `seen_iend` keeps its odd name (kii calls it), and the 45 internal names are classified rather than renamed. ABI diff vs 0.8.0: one name added, none removed, no offset moved. +76 assertions, a 12th suite. [ADR 0010](../adr/0010-the-v1-surface.md). |
| [0.8.0](../../CHANGELOG.md#080---2026-08-24) | **T.81 § A.2 multi-scan and partially-interleaved JPEG** — the last deferred decode class. A baseline file whose scans carry fewer components than the frame (what `cjpeg -scans` emits) was refused from 0.6.0 through 0.7.3; it now decodes. **The oracle is external in both directions**: at each sampling ratio the same image encoded interleaved, as three `Ns=1` scans, and as `Ns=1` then `Ns=2` decodes to identical bytes under `djpeg -nosmooth`, and since chitra already got the interleaved one right the others are held to its exact bytes — **all nine byte-identical**. Two design results: **one § A.2 rule covers both layouts** (0.6.0's effective-geometry collapse was *deleted*, not extended — it was valid only because a lone component IS the maximum, and `Nf = 1` now falls out of the general formula, so **ADR 0006's claim that this cut could build on that collapse was false** and is amended along with five other omissions); and **coverage is the loop bound**, since a component decodes exactly once, so the driver terminates on a bitmask rather than a counter standing in for it. Also fixes `seen_iend` still lying for a file truncated mid-entropy with a real `FF D9` appended — bounding the reader to the scan's own span makes "ran out of scan" and "ran out of data" the same event. `ΣHj·Vj ≤ 10` moves to the scan header conditioned on `Ns > 1` per § B.2.3; Huffman selectors move from the component to the scan, shrinking the component stride 48 → 32 so the whole cut costs **zero allocation growth**. +75 assertions, an 11th suite. |
| [0.7.3](../../CHANGELOG.md#073---2026-08-24) | **Harness and CI gaps — the sweep's least glamorous findings, and the ones most likely to hide the next defect.** **9,975,418 fuzz assertions**, up from 8,072,804, and `make fuzz` runs in **CI for the first time**. The one that matters is the **PNG scanline-mutation mode**: PNG's per-chunk CRC-32 meant a random byte flip inside IDAT rejected with `CHITRA_ERR_CRC` *before* inflate ever ran, so the five § 9 unfilter predictors, the Adam7 deinterleave and the colour pass had been receiving **no** mutated input at all — the harness mutates the scanline bytes and repairs the CRC, so the mutations reach the code they were meant to test. |
| [0.7.2](../../CHANGELOG.md#072---2026-08-24) | **BMP and GIF loose ends** — five items from the 0.6.1 deferment sweep, each small and independent. Four landed: **OS/2 2.x `BITMAPCOREHEADER2` (64 bytes)** decodes (its first 40 bytes are laid out exactly like `BITMAPINFOHEADER`); `BI_ALPHABITFIELDS` on a 52-byte V2 header — which decoded silently opaque — is **rejected** rather than relocated, because a 52-byte header has room for three masks while the compression names four, and ImageMagick refuses the combination outright so there is no reference to agree with; the GIF **transparent index** is range-checked against the table in force; and **BMP RLE end-of-line** now checks its landing point at the same threshold delta already used, so the two overshoot paths agree. The fifth was investigated and **deliberately not acted on**, which is the more useful result: GIF Plain Text extensions are examined-and-declined, recorded as such rather than left looking like an oversight. |
| [0.7.1](../../CHANGELOG.md#071---2026-08-24) | **PNG conformance: chunks the spec forbids, and a reduction that was wrong by one.** Four gaps, all found by *reading* the code rather than by any marker in it, three of which left chitra's posture inverted — rejecting tRNS-before-PLTE (which ImageMagick tolerates) while accepting chunks the spec forbids outright. The headline: **depth-16 samples were TRUNCATED to the high byte, not rescaled**. PNG § 13.13 gives `floor(input·MAXOUT/MAXIN + 0.5)`; truncation was off by up to one level on every 16-bit sample and had been the behaviour since 0.2.0. The fix is `(v*255 + 32767) / 65535`, hoisted behind one branch per pixel so depth-8 pays nothing (measured **−0.6%**, against **+13%** for the naive placement). Also: PLTE on colour types 0/4 and tRNS on 4/6 now reject per § 11.2.3 / § 11.3.2, and a chunk interleaved **between** IDAT chunks is rejected via an explicit `idat_closed` flag (§ 5.6 contiguity). +13 assertions. |
| [0.7.0](../../CHANGELOG.md#070---2026-08-24) | **Stream-end honesty.** `chitra_image_seen_iend` exists to answer one question — did the stream end the way its format says it should? PNG had answered honestly since 0.2.0; **JPEG, BMP and GIF hardcoded `1`**, so on three formats of four the single accessor a consumer could use to detect an incomplete stream was a constant. It matters because chitra deliberately **decodes** incomplete streams rather than rejecting them, exactly as libjpeg does: a JPEG truncated inside its entropy data comes back as fabricated zero-padded MCUs, and the accessor was the only thing that could have said so. Now it reports EOI for JPEG, the declared pixel span for BMP, and the LZW terminator for GIF. The accessor keeps its PNG-derived name; the *meaning* generalises. |
| [0.6.1](../../CHANGELOG.md#061---2026-08-24) | **A repair cut, and the byte-budget surface.** A tree-wide sweep for deferred and half-done work turned up four shipped defects that outranked the release's planned content. Three were files standard tools produce: a **`cjpeg -rgb`** file decoded hue-rotated with no error (**1,149 of 1,536 bytes wrong**, a blue pixel returned dark red) because APP14 was never read; an **81-byte GIF** with a 1920×1080 canvas was **refused** because 0.5.3's amplification cap bounded the canvas against the first frame's bytes; and a **16,556-byte JPEG** padded with skipped APPn segments **decoded, spending 117,463,728 bytes**, because the cap divided by whole-file length — the 0.5.3 wrong-denominator defect, live in the JPEG path. Fourth: a refused JPEG cost 22,160 bytes on **every** call, so lazy table allocation drops it to **400**, guarded `== 0` because a DHT may carry 3,854 definitions and per-definition allocation would scale with file size. On top of that, [ADR 0007](../adr/0007-byte-budget-surface-deferred.md)'s deferred surface ships at **two names** rather than eight — `chitra_image_decode_budget` and `CHITRA_ERR_BUDGET` — with a refusal costing 16 bytes and a contract that names what it does not cover ([ADR 0008](../adr/0008-byte-budget-as-shipped.md), [ADR 0009](../adr/0009-jpeg-colour-transform.md)). +83 assertions, a 9th suite. |
| [0.6.0](../../CHANGELOG.md#060---2026-08-24) | **T.81 § A.2 non-interleaved JPEG scans decode — for a one-component frame.** A grayscale JPEG declaring `H > 1` or `V > 1` was rejected through 0.5.3, deliberately (0.3.3 chose refusal over mis-rendering); 0.6.0 implements the layout, so that rejection is **reversed**. Not a second decoder but an **effective-geometry collapse**: for `Nf = 1` the sampling factors are *inert* — § A.1.1's `x_i = ceil(X·H_i/H_max)` collapses to `x_1 = X` because the lone component IS the maximum — so forcing `H = V = 1` makes the existing interleaved loop walk the non-interleaved layout exactly, with `cpw = ceil(w/8)·8` covering the plane with **no unwritten margin** (hence no zero-fill and no tripwire: neither could fire). Also conditions **ΣHj·Vj ≤ 10 on `Ns > 1`** per § B.2.3 — it bounds an interleaved MCU and a one-component frame has none — with the cap's reachability proven in both directions. The oracle is external in both directions: four libjpeg files differing in **exactly one byte** (the SOF0 sampling nibble) decode identically under djpeg, and chitra now matches `djpeg -nosmooth` over all 1536 bytes for every one. **Multi-scan and partially-interleaved files stay deferred** ([ADR 0006](../adr/0006-defer-jpeg-multiscan-resumption.md)) and their code moves from `JPEG_SOS` (17, "malformed") to `UNSUPPORTED` (4, "chitra declines") — measured reason: a naive relaxation makes them *decode*, wrongly, with no error. The **byte-budget surface is deferred to 0.6.1** with [ADR 0007](../adr/0007-byte-budget-surface-deferred.md), on a measurement: a 15-byte JPEG that is refused spends **22,096 bytes**, so a probe-based ceiling would itself be an exhaustion vector. +241 test assertions (a new 8th suite), +590 k fuzz assertions. |
| [0.5.3](../../CHANGELOG.md#053---2026-08-24) | **P-1 audit and repair — the first line-by-line review of BMP and GIF.** Both shipped across 0.4.0–0.5.2 with known-answer suites, reference cross-checks and heavy fuzzing, but no guard review. **No memory-safety defect was found** — no reachable OOB, no overflow into an allocation, no unterminated loop — so the sweep weighted **wrong-output** defects as heavily as memory safety, and seven of nine confirmed findings are exactly that. **Every one was confirmed by decoding the same bytes with ImageMagick**, after millions of fuzz cases had passed over them. Repairs: 32-bpp `BI_BITFIELDS` masks were parsed, validated, then **ignored** unless an alpha mask was also declared (red/blue swapped on a real file); mask fields were honoured under `BI_RGB`, where Microsoft says they are meaningless, decoding a V4 file **fully transparent**; `BI_RGB` defaults were injected into bitfields files, making the "at least one colour channel" guard **unreachable dead code**; the GIF transparent index was a stale function-scoped `var` that survived a later GCE revoking it; the GCE block size was never validated though every field after it is addressed by fixed offset; the LZW chain guard was one looser than the buffer it protected; and two gaps left by 0.3.3's own tRNS repairs (sub-byte keying compared at the wrong width, tRNS-before-PLTE accepted). Adds **amplification caps for BMP-RLE and GIF** — a 1,082-byte RLE8 file and a 797-byte GIF each decoded into ~64 MB — with PNG's equivalent documented as **accepted risk**, since there the bomb and a legitimate solid image are the same file shape. +62 test assertions, every repair carrying a regression test verified to fail against the pre-repair code. Audit: [`2026-08-24`](../audit/2026-08-24-audit.md). |
| [0.5.2](../../CHANGELOG.md#052---2026-08-24) | **BMP channel masks, 16 bpp, and the V4/V5 headers** — the last of the 0.4.0 deferrals, landed as one cut because they are the same feature from three angles. `BI_BITFIELDS` / `BI_ALPHABITFIELDS` masks at 16 and 32 bpp, read from inside the header for V2+ or from the DWORDs after a 40-byte one; 16 bpp (`BI_RGB` defaulting to the **documented** X1R5G5B5, not a convention); and the V2/V3/V4/V5 headers, whose color-space, gamma and ICC fields are **skipped rather than guessed at** — chitra does no color management, so honouring a color space would claim a transform it does not perform. **Retires the 32-bpp alpha heuristic for files that declare a mask** (plain `BI_RGB` still has no mask to read, so the heuristic still governs there). Masks are validated as attacker input: contiguous, non-overlapping, inside the pixel word, at least one color channel. Two real bugs found by reference cross-check and fixed: channel widening is **bit replication**, not `v*255/max` (which was a whole-image color shift), and 16 bpp was falling into the palette path because `bpp < 24` had silently stopped meaning "indexed". New `CHITRA_ERR_BMP_MASK` (33). +155 test assertions, +100 k fuzz cases. **The BMP deferral list is now empty.** |
| [0.5.1](../../CHANGELOG.md#051---2026-08-24) | **BMP run-length compression.** `BI_RLE8` and `BI_RLE4`, deferred in 0.4.0, now decode: encoded runs, absolute mode with word-boundary padding, end-of-line, end-of-bitmap and delta. As predicted, the **guards outweigh the codec** — termination is structural (every opcode consumes ≥ 2 bytes and the cursor only advances), every write is bounds-checked individually rather than per-run (a run past the row end is **rejected, not clipped**), and delta is checked against both dimensions **at the jump**, since a delta past the end followed by no writes is still malformed. Top-down RLE rejected (MS: top-down DIBs cannot be compressed — the end-of-line escape counts from the bottom); depth mismatch rejected (`BI_RLE8`⇒8 bpp, `BI_RLE4`⇒4 bpp). New `CHITRA_ERR_BMP_RLE` (32) separates "your file is broken" from "chitra won't". +561 test assertions, +200 k fuzz cases incl. a delta-splice mode, +1 benchmark (18 ns/px — slower than uncompressed BMP's 6, since per-opcode branching costs more than the bytes it saves). |
| [0.5.0](../../CHANGELOG.md#050---2026-08-24) | **GIF → the same canonical RGBA8, first frame only.** The fourth and last common raster format. `src/gif_lzw.cyr` is the **only decompressor chitra implements itself** — `sankoch` has no LZW to delegate to — with the three LZW attack shapes defended at the point each arises: expansion capped at the frame's pixel count, prefix chains that cannot cycle (entries added only with `prefix < index`, plus a size bound), and out-of-range codes rejected with the one legal KwKwK exception handled explicitly. `src/gif.cyr` carries GIF87a/89a headers, global **and** local color tables, the 4-pass row interlace, GCE transparency, and sub-block chains bounded by the input length. First-frame-only is [ADR 0005](../adr/0005-gif-first-frame-only.md): `ChitraImage` keeps its shape, so consumers gain GIF on a re-pin. Fixtures are real ImageMagick GIFs, expectations corroborated by a second independent decoder. A KwKwK ordering bug was found by that cross-check and fixed pre-release. +622 test assertions, +1,259,514 fuzz assertions, +1 benchmark (43 ns/px). |
| [0.4.0](../../CHANGELOG.md#040---2026-08-24) | **BMP → the same canonical RGBA8.** The third format, and the simplest decode path in the library: no entropy coding, no DEFLATE, no DCT — **6 ns/px** at 24/32 bpp against PNG's 83 and JPEG's 43. `BI_RGB` uncompressed at 1/4/8 bpp (palette, MSB-first), 24 bpp and 32 bpp; `BITMAPINFOHEADER` (40-byte) and `BITMAPCOREHEADER` (12-byte) DIB headers; bottom-up **and** top-down row order; the BGRA palette. New public `chitra_bmp_decode` / `chitra_bmp_decode_rgba8` / `chitra_bmp_check_signature`; `chitra_image_decode` now sniffs three formats. Output verified **identical to ImageMagick** on all eight valid fixtures, including the bottom-up/top-down pair that must agree from opposite storage orders. RLE4/RLE8, BITFIELDS, 16 bpp, V4/V5 headers reject with distinct codes; `BI_JPEG`/`BI_PNG` are refused outright as a decoder-recursion surface. +294 test assertions, +1,819,490 fuzz assertions, +3 benchmarks. |
| [0.3.3](../../CHANGELOG.md#033---2026-08-23) | **P-1 audit, hardening and repair — and both v1.0 hardening gates.** A ten-lens adversarial sweep of both decode paths, every finding put to two independent skeptics. **No memory-safety defect was found**; the repairs are correctness, conformance and resource hardening: full-width depth-16 tRNS keying, rejection of single-component non-interleaved JPEG scans, a JPEG decompression-bomb cap (`CHITRA_MAX_JPEG_RATIO`, the analogue of the PNG inflate-ratio cap), a `chitra_err_new` that can no longer return 0, T.81 fill-byte handling, ZRL overrun rejection, non-segment marker rejection, and the PNG § 5.4 / § 5.6 chunk-ordering guards. Every repair carries a regression test verified to fail against the pre-repair code. **Four input classes that previously decoded now reject**, deliberately. Adds the first fuzz harnesses (`make fuzz`, ~10⁶ cases) and the first benchmark harness (`make bench` + `bench-history.csv`), closing both remaining v1.0 hardening gates. Audit: [`2026-08-23`](../audit/2026-08-23-audit.md). |
| [0.3.2](../../CHANGELOG.md#032---2026-08-23) | **Toolchain catch-up + version-probe fix** — cyrius pin 6.5.27 → 6.5.35 with `lib/` re-vendored, clearing the shadow-lib and pin-drift build warnings. Fixes `chitra_version()`, which 0.3.1 left at its 0.3.0 value while bumping every other version source; `make version-check` now gates that literal so it cannot drift silently again. No decode change. |
| [0.3.1](../../CHANGELOG.md#031---2026-08-17) | **Toolchain bump** — cyrius pin 6.2.44 → 6.5.27, matching the rest of the AGNOS desktop stack. No decode change. |
| [0.3.0](../../CHANGELOG.md#030--2026-06-27) | **JFIF baseline JPEG → the same canonical RGBA8.** A full baseline (SOF0) sequential-Huffman 8-bit decoder: grayscale (1 comp) + YCbCr (3 comp), chroma subsampling 4:4:4 / 4:2:2 / 4:2:0 (and general Hi,Vi box upsampling), and DRI / RST0–7 restart markers. Pipeline = marker walk (DQT/DHT/SOF0/DRI) → per-component MCU loop (bit-reader + `DECODE`/`RECEIVE`/`EXTEND`, libjpeg islow integer IDCT, level-shift+clamp) → box upsample → BT.601 YCbCr→RGB. New public `chitra_jpeg_decode` / `chitra_jpeg_decode_rgba8` / `chitra_jpeg_check_signature` plus a signature-sniffing `chitra_image_decode` PNG-vs-JPEG router. Output verified **byte-identical to ImageMagick** on a real 16×16 baseline gradient (real Annex K Huffman tables + AC entropy). Non-baseline modes (progressive / arithmetic / 12-bit / hierarchical/lossless / CMYK) reject loud with distinct codes (ADR [0004](../adr/0004-jpeg-decode-model.md)). |
| [0.2.1](../../CHANGELOG.md#021--2026-06-26) | **Sub-byte depths 1/2/4 + Adam7 interlace = full PNG matrix.** Sub-byte grayscale (ct0) / palette (ct3) MSB-first unpack (gray scales ×255/85/17, palette indexes PLTE); the 7 Adam7 passes deinterlace into the same dense byte-padded buffer so the color pass stays interlace-agnostic. Also hardens the IHDR compression/filter-method allow-lists and re-asserts the dimension caps in the color pass. |
| [0.2.0](../../CHANGELOG.md#020--2026-06-26) | **Bit depth 16 + kii guard-parity backport** — makes chitra a strict superset of kii's native decoder. Big-endian 16-bit samples truncate to the high byte (unchanged rendered output). Backports the IEND-must-be-zero-length guard and adds `CHITRA_ERR_NO_IDAT` (12); adds `chitra_image_seen_iend` and `chitra_image_source_color_type` accessors. `ChitraImage` widened 32→48B, **ABI-additive** (0.1.x offsets preserved → mabda-safe). |
| [0.1.0](../../CHANGELOG.md#010--2026-06-19) | **PNG → canonical RGBA8**, depth-8, non-interlaced — pure-Cyrius CPU decode (no GPU, no C shim, no external binaries). One-time fork of kii's `png.cyr` core, re-shaped onto a byte-buffer cursor + a canonical-RGBA8 normalization pass; the kii security guards (bounds-checked cursor, per-chunk CRC-32, lying-IHDR / dimension / decompression-bomb caps) come across with it. Color types 0/2/3/4/6, tRNS alpha synthesis. Consumed by mabda for `gpu_texture_load_png`. |

## v1.0 criteria

The contract that gated v1.0, kept as a record of what was promised and met.
Decode coverage spans all four formats and every hardening item is closed.
**The two unchecked boxes below are the only ones still open**, and neither
blocked the freeze: the sankoch pin bump (which waits on a cyrius release) and
the downstream consumer re-pins.

- [x] **Full PNG matrix** — color types 0/2/3/4/6 at every spec-legal bit
  depth (1/2/4/8/16, validated per color type against § 11.2.2 Table 11.1)
  plus Adam7 interlace, all normalizing to canonical RGBA8 (shipped 0.2.1).
- [x] **JFIF baseline JPEG** — SOF0 sequential-Huffman 8-bit: grayscale +
  YCbCr, chroma subsampling 4:4:4 / 4:2:2 / 4:2:0 (general Hi,Vi box
  upsampling), DRI / RST0–7 restart markers, normalizing to the same canonical
  RGBA8 (shipped 0.3.0). Validated **byte-identical to ImageMagick** on a real
  baseline gradient with AC content; non-baseline modes reject with distinct
  `CHITRA_ERR_JPEG_*` codes (13–23). Decode model: ADR
  [`0004-jpeg-decode-model.md`](../adr/0004-jpeg-decode-model.md); design:
  [`../proposals/jpeg-baseline-decoder.md`](../proposals/jpeg-baseline-decoder.md).
  Format coverage: all four common raster formats now decode — BMP shipped in
  0.4.0, GIF in 0.5.0. What remains in the arc is paying off deferrals, not
  adding formats.
- [x] **First security audit** — line-by-line guard verification across the
  src modules, captured in
  [`../audit/2026-06-26-audit.md`](../audit/2026-06-26-audit.md). Confirmed
  full guard parity with the kii lineage and no real OOB / overflow gap;
  open items are cosmetic doc-drift only (see audit + the stale enum comments
  in `src/error.cyr`).
- [x] **Every format audited** — **DONE in 0.5.3.** Four reports now cover the
  four decode paths: [PNG](../audit/2026-06-26-audit.md),
  [JPEG](../audit/2026-06-27-audit.md),
  [the P-1 sweep of both](../audit/2026-08-23-audit.md), and
  [the P-1 sweep of BMP + GIF](../audit/2026-08-24-audit.md). The last closes
  the gap 0.4.0–0.5.2 opened by shipping two formats faster than they could be
  reviewed. Its lesson is worth keeping: **fuzzing does not find wrong output**
  — seven of the nine confirmed findings were silent mis-decodes that millions
  of fuzz cases had passed over, and each was caught by cross-checking against
  ImageMagick.
- [x] **In-tree fuzz harness at 10⁶ iterations clean** — **DONE in 0.3.3.**
  `fuzz/fuzz_png.fcyr` + `fuzz/fuzz_jpeg.fcyr`, run by `make fuzz` and wired
  into `make test-all`. There is one harness per format (PNG,
  JPEG, BMP, GIF); [`state.md`](state.md) carries the running total, which this
  file deliberately does not duplicate.
  0.3.3 alone cleared the 10⁶ bar with the first two. Both public decode entries are driven over random,
  signature-prefixed, bit-flipped, truncated and degenerate-length input, plus
  **entropy-segment-only mutation** for JPEG — the surface that was previously
  unfuzzed, since its hardening was forked from the kii/PNG lineage rather
  than re-exercised. The harnesses assert the documented `(0, *err_out set)`
  contract as well as survival. See
  [`docs/audit/2026-08-23-audit.md`](../audit/2026-08-23-audit.md) § 5.
- [x] **Benchmark harness + CSV history** — **DONE in 0.3.3.**
  `tests/bcyr/chitra.bcyr` (`make bench`) measures decode latency for all four
  formats across 17 benchmarks, and `scripts/bench-csv.sh`
  (`make bench-record`) appends stamped results to
  [`bench-history.csv`](../../bench-history.csv). The harness **generates its
  own fixtures at 256×256** — the in-tree test fixtures are 2×2..16×16 and
  would measure fixed overhead, not throughput — and decode-verifies each one
  before timing it. First baseline: PNG rgba8 83 ns/px, Adam7 128 ns/px;
  JPEG grayscale 43 ns/px, 4:2:0 91 ns/px. Numbers are host- and
  load-dependent, so the CSV is a within-host series, not a cross-host
  comparison.
- [ ] **Waiting on a toolchain pin bump for the sankoch repair.** The
  `alloc_reset()` hazard recorded in
  [architecture/005](../architecture/005-alloc-reset-sankoch-hazard.md) — where
  a reset left sankoch's memoized CRC table dangling and chitra's per-decode
  `crc32_init_table()` wrote 16 KB through it — **is fixed upstream in sankoch
  2.7.10** (released). chitra cannot pick it up on its own: `lib/` is vendored
  by `cyrius deps` from the toolchain, so the fix arrives with the next cyrius
  release and a bump of `[package].cyrius` (currently `6.5.35`).

  **On that bump, and not before**, three things become stale and should be
  cleared in the same cut: architecture/005 moves from a live hazard to a
  historical note, `architecture/003`'s ⚠ block stops warning against the
  arena-reset pattern it currently forbids, and state.md's "Known upstream
  issue" entry goes. Verify rather than assume — re-run the reproduction from
  005 against the new `lib/sankoch.cyr` before deleting anything, because the
  fix ships in the toolchain's bundled copy and a pin bump is not by itself
  evidence that the copy moved.

  **A consumer is exercising it today**: kii's fuzz harness
  (`tests/kii.fcyr`, `fuzz_png_iter`) calls `kii_decode_png` then
  `alloc_reset()` every iteration, 10⁶ times a run — and its contract
  ("never crashes; returns `PNG_OK` or any `PNG_ERR_*` cleanly") is satisfied
  by a *corrupted* decode returning `CHITRA_ERR_CRC`, so the harness passes
  either way. Fuzzing does not find wrong output.

  Not a v1.0 blocker: chitra's own decode path never calls `alloc_reset()`,
  and the freeze does not depend on it. It is listed here so the pin bump is not spent without also spending
  the doc cleanup it enables.
- [x] **Public API + ABI freeze — DONE in 1.0.0.** It froze the PNG surface
  (`chitra_png_decode` / `chitra_png_decode_rgba8`), the JPEG surface
  (`chitra_jpeg_decode` / `chitra_jpeg_decode_rgba8` /
  `chitra_jpeg_check_signature`), the format-router `chitra_image_decode`, the
  `ChitraImage` record (append-only fields), and the 16-byte `ChitraErr`
  (GpuErr-layout-compatible). **Every prerequisite below is now settled** —
  they were surfaced by the [0.3.3 audit](../audit/2026-08-23-audit.md) and
  deferred out of a patch release because each changes the public surface.
  0.9.0 spent them all, so **1.0.0 was the freeze itself with no code change
  beyond the version literal** — the right property for a version that promises
  stability. The decisions are recorded in
  [ADR 0010](../adr/0010-the-v1-surface.md), and the promise's *edges* — what
  is deliberately NOT frozen (the 45 internal names, `chitra_err_name`'s
  strings, bit-exact output across releases, memory behaviour) — are stated in
  [`public-surface.md`](public-surface.md), because a promise with unstated
  edges is not a promise.
  - [x] **`@public` markers on the signature predicates** — done in 0.9.0, and
    evidence-backed: kii calls `chitra_png_check_signature` and
    `chitra_jpeg_check_signature` directly. Both were public by documentation
    and by consumer use while living in modules that carried neither the
    file-level banner nor a per-function marker; the freeze should not codify
    that disagreement.
  - [x] **The two misleading `chitra_err_name` strings** — done in 0.9.0.
    `CHITRA_ERR_INTERLACE` now reads "illegal interlace method" and
    `CHITRA_ERR_BIT_DEPTH` "illegal bit depth for color type". Both formerly
    read as capability limits ("interlace unsupported" / "bit depth
    unsupported") when both are validity rejections — chitra decodes Adam7 and
    every spec-legal depth. This changes public output, which is exactly what
    a freeze makes expensive later.
  - [x] **The four input classes 0.3.3 began rejecting** — answered in 0.6.0.
    One is **reversed**: the § A.2 one-component geometry now decodes. The
    other three are **affirmed as frozen behaviour** — the JPEG amplification
    cap, PNG's § 5.4 unknown-critical-chunk abort, and the § 5.6 / § 11.3.2
    tRNS/PLTE ordering rules. The freeze need not re-open them.
  - [x] **`CHITRA_ERR_UNSUPPORTED`'s several meanings** — settled in 0.9.0:
    **documented, not split.** Minting error codes immediately before a freeze
    is the opposite of settling the surface, each new code is itself a
    permanent name, and the shared meaning is real and precise — *the file is
    valid; chitra declines it*. The set also shrank on its own: 0.8.0 removed
    the multi-scan meaning when multi-scan started decoding. What was wrong
    was the enum comment describing one case as though it were all; it now
    enumerates them.
  - [x] **`chitra_image_seen_iend` — does the name survive?** — settled in
    0.9.0: **it keeps its name.** It is a PNG concept on four formats and
    0.7.0 generalised its meaning, so the name reads oddly; renaming it buys a
    better name and charges kii a real edit at the moment the project promises
    stability, and shipping both names would leave a frozen surface with two
    names for one field.
  - [x] **`ChitraImage` carries no bit depth** — added in 0.9.0 as
    `chitra_image_source_depth` at +48, append-only; the record is now 56
    bytes and every prior offset is unmoved. Added *before* the freeze because
    adding it after is an ABI event.
  - [x] **A machine-checked manifest of the public surface** — shipped in
    0.9.0: [`public-surface.md`](public-surface.md) + `scripts/check-surface.sh`,
    wired into `make lint`. **74** `chitra_`-prefixed functions are visible in
    `dist/chitra.cyr` and **45 of them are internal** (`chitra_raw_*`,
    `chitra_jpeg_frame_*`, `chitra_bmp_hdr_*`, `chitra_png_parse_raw`,
    `chitra_png_color_to_rgba8`, `chitra_jpeg_scan_markers`); **29** are
    frozen. Until the gate existed, "the surface is frozen" was an assertion
    with nothing behind it. It fails in both directions and both were proven
    to fire. The 45 internal names are deliberately **not** renamed to
    `_chitra_*`: that is ~45 renames plus 75 test call sites immediately
    before a freeze, for zero runtime benefit, and it stays available later as
    a non-breaking change.
- [ ] **Downstream consumers green** — mabda's `gpu_texture_load_png` and
  kii's PNG re-fold (its v1.2.0 deleted its own decoder and adopted
  `dist/chitra.cyr`; ADR 0006 on kii's side) both build and pass against the
  frozen surface. Track until both consumers re-pin to 1.0.0. **Both pins are currently
  behind**: mabda at `0.3.1`, kii at `0.3.0`, against a released `1.0.0`.
  Every cut since 0.3.1 has been ABI-additive — nothing removed, no offset
  moved, `ChitraImage` grown only on the end (40 → 48 → 56 bytes) — so both
  bumps are mechanical, but until they land neither consumer has BMP, GIF, the
  0.3.3 decode repairs, the nine 0.5.3 ones, 0.6.0's § A.2 support, 0.7.x's
  depth-16 fidelity and byte budget, or 0.8.0's multi-scan JPEG. kii is the
  one that matters: it is ten cuts behind on a path it uses in anger, and its
  nine-name call set is the evidence base ADR 0010 used to decide what the
  freeze may not rename.
- [x] **Root docs + doc tree complete** — CLAUDE.md, README, CHANGELOG,
  CONTRIBUTING, SECURITY, ADRs ([`../adr/README.md`](../adr/README.md)),
  architecture notes ([`../architecture/README.md`](../architecture/README.md)),
  the getting-started guide
  ([`../guides/getting-started.md`](../guides/getting-started.md)), and
  examples ([`../examples/README.md`](../examples/README.md)) all current.

## Lessons carried forward

The per-release sections that used to live here were retrospectives on shipped
work, which [`../../CHANGELOG.md`](../../CHANGELOG.md) already holds in full.
What survives is the part a *future* cut needs: seven findings that generalise
past the release that produced them, and that are recorded nowhere else in the
tree. Each is here because it changed how the next cut was done.

- **A sweep finding is a hypothesis** (0.7.2). Two of that cut's five items did
  not survive contact with a reference decoder — one was a rejection rather than
  the relocation the sweep read it as, the other was a spec argument ImageMagick
  simply does not follow. The cheapest time to learn that is *before* writing the
  repair. Investigate, then decide; a declined finding is a result, not a gap.
- **Every new fuzz mode needs its own no-op proof** (0.7.3). A harness that
  exercises nothing still reports hundreds of thousands of cases "survived". The
  first cut of the PNG scanline mode was measured by error-code distribution
  before it was believed — ~99% of CRC-repaired IDAT mutations fail inflate and
  only 0.6% reach the predictors, while scanline mutation puts 69% into the
  unfilter path. Neither number was predictable from the code.
- **Ask what the denominator is** (0.5.3). A cap must be measured on what the
  attacker *spent*, not what they supplied. The first BMP amplification cap
  divided by file size, so appending padding raised the attacker's own
  allowance; JPEG repeated the identical mistake in 0.6.1, where 16 KB of
  skipped APPn segments bought a 117 MB decode. Ask it of every future ratio
  guard, before shipping it.
- **Reachability is part of what a regression test has to prove** (0.5.3). "A
  test verified to fail against the pre-repair code" is not enough on its own if
  the guard it covers could never fire: BMP's "at least one colour channel"
  check was unreachable from the day it shipped, because defaults injected
  upstream erased exactly the condition it tested — and the CHANGELOG advertised
  it anyway. Neuter the guard and confirm a test fails.
- **A change to how samples are reduced is never local to the reduction**
  (0.7.1). When depth-16 truncation became the § 13.13 rescale, the ct2 tRNS key
  comparison broke, because it reconstructed full-width samples from the
  *reduced* ones. Anything that reconstructs an input from an output is coupled
  to the reduction, however far away it lives.
- **Where a conformance argument cannot be confirmed, follow the reference**
  (0.7.2). chitra diverges from ImageMagick where the spec is prohibitive *and*
  the result is a wrong image (PNG § 5.6 in 0.7.1). It does not diverge on a
  reading the reference declines to share — the GIF Plain Text / GCE scoping
  question read like a defect on the spec and was declined on measurement.
- **Guards that cannot fire are left out, not written down** (0.8.0). Multi-scan
  needed no scan limit and no resume tripwire: coverage is the loop bound, since
  a component decodes exactly once, so the driver terminates on the bitmask
  itself rather than on a counter standing in for it. Neither proposed guard
  could fire before coverage did, so neither was added.

## After 1.0.0

Nothing here is scheduled. Recorded so the next cut starts from a list rather
than from memory.

- **The two open v1.0-criteria items** — the sankoch pin bump (waiting on
  cyrius; a consumer is exercising the hazard today) and the downstream
  consumer pins (mabda `0.3.1`, kii `0.3.0` — both mechanical, since every cut
  has been ABI-additive).
- **Post-1.0 decode work now costs a major bump or a new name**, which is what
  the freeze was for. Multi-frame GIF is additive by design — a *separate*
  entry point returning a frame list, leaving `chitra_gif_decode` untouched
  ([ADR 0005](../adr/0005-gif-first-frame-only.md)) — and so is APNG, for the
  same reason. Progressive JPEG is a decode-model question
  ([ADR 0004](../adr/0004-jpeg-decode-model.md)), not a surface one.
- **The internal-name rename** (`_chitra_*` on the 45) is available whenever
  someone wants it: non-breaking by construction, because nothing frozen is
  being renamed.
- **A fancy/triangle chroma upsampler** would close the remaining ImageMagick
  gap on subsampled JPEG — but note it is **not** a drop-in: the exact-fit
  plane property depends on box never reading `x+1`
  ([architecture/004](../architecture/004-jpeg-decode-pipeline.md)), and
  `djpeg -nosmooth` would stop being the oracle.

## Out of scope (durable scope guards)

Durable boundaries on what chitra is — not v1.0-only gates:

- **Encoding** — chitra is **decode-only**. Encoded bytes → RGBA8, never the
  reverse. No PNG/JPEG/GIF/BMP writer.
- **`BI_JPEG` / `BI_PNG` inside a BMP** — a BMP whose DIB body is an entire
  embedded JPEG or PNG stream. Refused outright (`CHITRA_ERR_BMP_COMPRESSION`),
  and **not deferred to any release**: honouring it would have `chitra_bmp_decode`
  re-enter `chitra_jpeg_decode` / `chitra_png_decode`, and a decoder that can
  call itself through attacker-controlled data is a recursion surface better
  declined than bounded. A consumer that genuinely holds one of these can
  extract the inner stream and call the inner decoder directly — which keeps
  the recursion decision on the consumer's side, where it belongs.
- **Reclassified from "deferred" to permanent by the 0.6.1 sweep.** These were
  filed as deferrals, which implied a release would eventually take them. On
  inspection they are scope boundaries, and saying so is more honest than
  leaving them on a list nothing will ever pull from:
  - **Arithmetic-coded JPEG** (SOF9/10/11 + DAC) — a second entropy coder for
    a mode almost nothing produces.
  - **Hierarchical / lossless / differential SOF frames** (SOF3/5/6/7/13/14/15)
    — a different codec that happens to share a container.
  - **4-component CMYK / YCCK** — decoding it to RGBA requires a colour-space
    guess chitra's own rules forbid it from making. See
    [ADR 0009](../adr/0009-jpeg-colour-transform.md) on why guessing a colour
    space is the defect, not the feature.
  - **12-bit sample precision** — unreachable by construction under SOF0-only,
    so it is a validity rejection wearing a capability label.
  - **DNL-deferred height** (SOF0 with `Y = 0`, the height supplied after the
    scan). Spec-legal per T.81 § B.2.2, and refused: it would make the geometry
    that drives every allocation depend on a value read *after* the data.
  **Progressive JPEG (SOF2) is the one exception** and stays a genuine
  deferral — it is the only non-baseline mode with a real-world consumer case.
- **Colour management, in every format.** gAMA / sRGB / iCCP / cHRM / sBIT on
  PNG, the V4/V5 colour-space, CIEXYZ endpoints, gamma, rendering intent and
  embedded ICC profile on BMP, and APP2 ICC on JPEG are all **skipped**, and
  samples are emitted as-is. chitra's RGBA8 output is untagged. This was
  written down for BMP and nowhere else; it applies to all four.
- **EXIF orientation** (APP1) is neither applied nor surfaced, so a camera JPEG
  decodes in its stored orientation. Applying it is an image transform, which
  is out of scope; *surfacing* it would need a new `ChitraImage`
  field, which after the 1.0.0 freeze is a major bump plus an ADR — see
  *After 1.0.0*.
- **ICO / CUR containers**, and bare DIBs with no `BITMAPFILEHEADER`.
- **2 bpp (Windows CE) and 64 bpp BMP**, and the `BI_CMYK` compressions.
- **The GIF pixel aspect ratio byte** — non-square-pixel GIFs render unscaled,
  which is a transform question, not a decode one.
- **Interpolated (fancy) chroma upsampling.** chitra uses box. This is why
  ImageMagick differs from chitra on a subsampled JPEG by up to 40 per byte
  while `djpeg -nosmooth` matches exactly — a filter difference, not a bug.
  Note it is **not** a drop-in change: the 0.6.0 exact-fit plane property
  depends on the box filter never reading `x+1`
  ([architecture/004](../architecture/004-jpeg-decode-pipeline.md)).
- **APNG** decodes to its default image. That is the same situation GIF is in,
  and it gets the same answer for the same reason — see
  [ADR 0005](../adr/0005-gif-first-frame-only.md) — but unlike GIF it had no
  written decision until now.
- **Non-baseline JPEG** — **progressive** JPEG is **deferred**, not supported.
  chitra decodes JFIF baseline (SOF0 sequential Huffman, 8-bit) only; every
  other mode rejects loud with a distinct `CHITRA_ERR_JPEG_*` code rather than
  half-decoding. This is a deliberate decision, recorded in ADR
  [`0004-jpeg-decode-model.md`](../adr/0004-jpeg-decode-model.md) — revisit
  only if a consumer demonstrably needs progressive decode. CMYK/YCCK,
  arithmetic, hierarchical/lossless/differential, 12-bit and DNL-deferred
  height were reclassified from *deferred* to **permanent** by the 0.6.1 sweep.
- **Image transforms** — no crop, rotate, resize, or color adjustment. chitra
  emits canonical RGBA8 at the source dimensions; transforms are the
  consumer's job (or a sibling like hisab / ranga).
- **Filesystem / path I/O** — chitra takes in-memory bytes `(src, len)`. It
  never opens a file, walks a directory, or touches a path. The consumer reads
  the bytes and hands them in.
- **GPU work** — no upload, no texture handles, no shaders. chitra is the CPU
  decode boundary; mabda / soorat own everything GPU-side. (`ChitraErr` is
  deliberately layout-compatible with mabda's `GpuErr` so a decode failure
  maps onto `GPU_ERR_IMAGE_DECODE` — that is the seam, not GPU work in chitra.)

Captured deferrals become ADRs when the decision crystallizes (e.g. the JPEG
decode-model ADR [0004](../adr/0004-jpeg-decode-model.md) when 0.3 scoped, or a
streaming-API ADR if that surface lands). See
[`../adr/README.md`](../adr/README.md) for the existing decision record.
