# chitra — Roadmap

> **Last Updated**: 2026-08-24 (0.6.1)
>
> Sequencing — what ships, in what order, against what gates. Volatile state
> (current version, sizes, assertion counts, in-flight work) lives in
> [`state.md`](state.md), not here. **chitra is pre-v1** (current: 0.6.1) and
> all four decode paths are **feature-complete for their scope** — every spec-legal
> PNG depth × color-type × interlace combination, and JFIF **baseline** JPEG
> (grayscale + YCbCr, 4:4:4 / 4:2:2 / 4:2:0, restart markers), decode to
> canonical RGBA8. Hardening infrastructure is **done** — both harnesses landed
> in 0.3.3 — so what remains before a v1.0 freeze is the **API/ABI freeze
> itself**, and getting the downstream consumers onto it. The next formats are
> additive and do not gate the freeze.

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
| [0.1.0](../../CHANGELOG.md#010--2026-06-19) | **PNG → canonical RGBA8**, depth-8, non-interlaced — pure-Cyrius CPU decode (no GPU, no C shim, no external binaries). One-time fork of kii's `png.cyr` core, re-shaped onto a byte-buffer cursor + a canonical-RGBA8 normalization pass; the kii security guards (bounds-checked cursor, per-chunk CRC-32, lying-IHDR / dimension / decompression-bomb caps) come across with it. Color types 0/2/3/4/6, tRNS alpha synthesis. Consumed by mabda for `gpu_texture_load_png`. |
| [0.2.0](../../CHANGELOG.md#020--2026-06-26) | **Bit depth 16 + kii guard-parity backport** — makes chitra a strict superset of kii's native decoder. Big-endian 16-bit samples truncate to the high byte (unchanged rendered output). Backports the IEND-must-be-zero-length guard and adds `CHITRA_ERR_NO_IDAT` (12); adds `chitra_image_seen_iend` and `chitra_image_source_color_type` accessors. `ChitraImage` widened 32→48B, **ABI-additive** (0.1.x offsets preserved → mabda-safe). |
| [0.2.1](../../CHANGELOG.md#021--2026-06-26) | **Sub-byte depths 1/2/4 + Adam7 interlace = full PNG matrix.** Sub-byte grayscale (ct0) / palette (ct3) MSB-first unpack (gray scales ×255/85/17, palette indexes PLTE); the 7 Adam7 passes deinterlace into the same dense byte-padded buffer so the color pass stays interlace-agnostic. Also hardens the IHDR compression/filter-method allow-lists and re-asserts the dimension caps in the color pass. |
| [0.3.0](../../CHANGELOG.md#030--2026-06-27) | **JFIF baseline JPEG → the same canonical RGBA8.** A full baseline (SOF0) sequential-Huffman 8-bit decoder: grayscale (1 comp) + YCbCr (3 comp), chroma subsampling 4:4:4 / 4:2:2 / 4:2:0 (and general Hi,Vi box upsampling), and DRI / RST0–7 restart markers. Pipeline = marker walk (DQT/DHT/SOF0/DRI) → per-component MCU loop (bit-reader + `DECODE`/`RECEIVE`/`EXTEND`, libjpeg islow integer IDCT, level-shift+clamp) → box upsample → BT.601 YCbCr→RGB. New public `chitra_jpeg_decode` / `chitra_jpeg_decode_rgba8` / `chitra_jpeg_check_signature` plus a signature-sniffing `chitra_image_decode` PNG-vs-JPEG router. Output verified **byte-identical to ImageMagick** on a real 16×16 baseline gradient (real Annex K Huffman tables + AC entropy). Non-baseline modes (progressive / arithmetic / 12-bit / hierarchical/lossless / CMYK) reject loud with distinct codes (ADR [0004](../adr/0004-jpeg-decode-model.md)). |
| [0.3.1](../../CHANGELOG.md#031---2026-08-17) | **Toolchain bump** — cyrius pin 6.2.44 → 6.5.27, matching the rest of the AGNOS desktop stack. No decode change. |
| [0.3.2](../../CHANGELOG.md#032---2026-08-23) | **Toolchain catch-up + version-probe fix** — cyrius pin 6.5.27 → 6.5.35 with `lib/` re-vendored, clearing the shadow-lib and pin-drift build warnings. Fixes `chitra_version()`, which 0.3.1 left at its 0.3.0 value while bumping every other version source; `make version-check` now gates that literal so it cannot drift silently again. No decode change. |
| [0.6.1](../../CHANGELOG.md#061---2026-08-24) | **A repair cut, and the byte-budget surface.** A tree-wide sweep for deferred and half-done work turned up four shipped defects that outranked the release's planned content. Three were files standard tools produce: a **`cjpeg -rgb`** file decoded hue-rotated with no error (**1,149 of 1,536 bytes wrong**, a blue pixel returned dark red) because APP14 was never read; an **81-byte GIF** with a 1920×1080 canvas was **refused** because 0.5.3's amplification cap bounded the canvas against the first frame's bytes; and a **16,556-byte JPEG** padded with skipped APPn segments **decoded, spending 117,463,728 bytes**, because the cap divided by whole-file length — the 0.5.3 wrong-denominator defect, live in the JPEG path. Fourth: a refused JPEG cost 22,160 bytes on **every** call, so lazy table allocation drops it to **400**, guarded `== 0` because a DHT may carry 3,854 definitions and per-definition allocation would scale with file size. On top of that, [ADR 0007](../adr/0007-byte-budget-surface-deferred.md)'s deferred surface ships at **two names** rather than eight — `chitra_image_decode_budget` and `CHITRA_ERR_BUDGET` — with a refusal costing 16 bytes and a contract that names what it does not cover ([ADR 0008](../adr/0008-byte-budget-as-shipped.md), [ADR 0009](../adr/0009-jpeg-colour-transform.md)). +83 assertions, a 9th suite. |
| [0.6.0](../../CHANGELOG.md#060---2026-08-24) | **T.81 § A.2 non-interleaved JPEG scans decode — for a one-component frame.** A grayscale JPEG declaring `H > 1` or `V > 1` was rejected through 0.5.3, deliberately (0.3.3 chose refusal over mis-rendering); 0.6.0 implements the layout, so that rejection is **reversed**. Not a second decoder but an **effective-geometry collapse**: for `Nf = 1` the sampling factors are *inert* — § A.1.1's `x_i = ceil(X·H_i/H_max)` collapses to `x_1 = X` because the lone component IS the maximum — so forcing `H = V = 1` makes the existing interleaved loop walk the non-interleaved layout exactly, with `cpw = ceil(w/8)·8` covering the plane with **no unwritten margin** (hence no zero-fill and no tripwire: neither could fire). Also conditions **ΣHj·Vj ≤ 10 on `Ns > 1`** per § B.2.3 — it bounds an interleaved MCU and a one-component frame has none — with the cap's reachability proven in both directions. The oracle is external in both directions: four libjpeg files differing in **exactly one byte** (the SOF0 sampling nibble) decode identically under djpeg, and chitra now matches `djpeg -nosmooth` over all 1536 bytes for every one. **Multi-scan and partially-interleaved files stay deferred** ([ADR 0006](../adr/0006-defer-jpeg-multiscan-resumption.md)) and their code moves from `JPEG_SOS` (17, "malformed") to `UNSUPPORTED` (4, "chitra declines") — measured reason: a naive relaxation makes them *decode*, wrongly, with no error. The **byte-budget surface is deferred to 0.6.1** with [ADR 0007](../adr/0007-byte-budget-surface-deferred.md), on a measurement: a 15-byte JPEG that is refused spends **22,096 bytes**, so a probe-based ceiling would itself be an exhaustion vector. +241 test assertions (a new 8th suite), +590 k fuzz assertions. |
| [0.5.3](../../CHANGELOG.md#053---2026-08-24) | **P-1 audit and repair — the first line-by-line review of BMP and GIF.** Both shipped across 0.4.0–0.5.2 with known-answer suites, reference cross-checks and heavy fuzzing, but no guard review. **No memory-safety defect was found** — no reachable OOB, no overflow into an allocation, no unterminated loop — so the sweep weighted **wrong-output** defects as heavily as memory safety, and seven of nine confirmed findings are exactly that. **Every one was confirmed by decoding the same bytes with ImageMagick**, after millions of fuzz cases had passed over them. Repairs: 32-bpp `BI_BITFIELDS` masks were parsed, validated, then **ignored** unless an alpha mask was also declared (red/blue swapped on a real file); mask fields were honoured under `BI_RGB`, where Microsoft says they are meaningless, decoding a V4 file **fully transparent**; `BI_RGB` defaults were injected into bitfields files, making the "at least one colour channel" guard **unreachable dead code**; the GIF transparent index was a stale function-scoped `var` that survived a later GCE revoking it; the GCE block size was never validated though every field after it is addressed by fixed offset; the LZW chain guard was one looser than the buffer it protected; and two gaps left by 0.3.3's own tRNS repairs (sub-byte keying compared at the wrong width, tRNS-before-PLTE accepted). Adds **amplification caps for BMP-RLE and GIF** — a 1,082-byte RLE8 file and a 797-byte GIF each decoded into ~64 MB — with PNG's equivalent documented as **accepted risk**, since there the bomb and a legitimate solid image are the same file shape. +62 test assertions, every repair carrying a regression test verified to fail against the pre-repair code. Audit: [`2026-08-24`](../audit/2026-08-24-audit.md). |
| [0.5.2](../../CHANGELOG.md#052---2026-08-24) | **BMP channel masks, 16 bpp, and the V4/V5 headers** — the last of the 0.4.0 deferrals, landed as one cut because they are the same feature from three angles. `BI_BITFIELDS` / `BI_ALPHABITFIELDS` masks at 16 and 32 bpp, read from inside the header for V2+ or from the DWORDs after a 40-byte one; 16 bpp (`BI_RGB` defaulting to the **documented** X1R5G5B5, not a convention); and the V2/V3/V4/V5 headers, whose color-space, gamma and ICC fields are **skipped rather than guessed at** — chitra does no color management, so honouring a color space would claim a transform it does not perform. **Retires the 32-bpp alpha heuristic for files that declare a mask** (plain `BI_RGB` still has no mask to read, so the heuristic still governs there). Masks are validated as attacker input: contiguous, non-overlapping, inside the pixel word, at least one color channel. Two real bugs found by reference cross-check and fixed: channel widening is **bit replication**, not `v*255/max` (which was a whole-image color shift), and 16 bpp was falling into the palette path because `bpp < 24` had silently stopped meaning "indexed". New `CHITRA_ERR_BMP_MASK` (33). +155 test assertions, +100 k fuzz cases. **The BMP deferral list is now empty.** |
| [0.5.1](../../CHANGELOG.md#051---2026-08-24) | **BMP run-length compression.** `BI_RLE8` and `BI_RLE4`, deferred in 0.4.0, now decode: encoded runs, absolute mode with word-boundary padding, end-of-line, end-of-bitmap and delta. As predicted, the **guards outweigh the codec** — termination is structural (every opcode consumes ≥ 2 bytes and the cursor only advances), every write is bounds-checked individually rather than per-run (a run past the row end is **rejected, not clipped**), and delta is checked against both dimensions **at the jump**, since a delta past the end followed by no writes is still malformed. Top-down RLE rejected (MS: top-down DIBs cannot be compressed — the end-of-line escape counts from the bottom); depth mismatch rejected (`BI_RLE8`⇒8 bpp, `BI_RLE4`⇒4 bpp). New `CHITRA_ERR_BMP_RLE` (32) separates "your file is broken" from "chitra won't". +561 test assertions, +200 k fuzz cases incl. a delta-splice mode, +1 benchmark (18 ns/px — slower than uncompressed BMP's 6, since per-opcode branching costs more than the bytes it saves). |
| [0.5.0](../../CHANGELOG.md#050---2026-08-24) | **GIF → the same canonical RGBA8, first frame only.** The fourth and last common raster format. `src/gif_lzw.cyr` is the **only decompressor chitra implements itself** — `sankoch` has no LZW to delegate to — with the three LZW attack shapes defended at the point each arises: expansion capped at the frame's pixel count, prefix chains that cannot cycle (entries added only with `prefix < index`, plus a size bound), and out-of-range codes rejected with the one legal KwKwK exception handled explicitly. `src/gif.cyr` carries GIF87a/89a headers, global **and** local color tables, the 4-pass row interlace, GCE transparency, and sub-block chains bounded by the input length. First-frame-only is [ADR 0005](../adr/0005-gif-first-frame-only.md): `ChitraImage` keeps its shape, so consumers gain GIF on a re-pin. Fixtures are real ImageMagick GIFs, expectations corroborated by a second independent decoder. A KwKwK ordering bug was found by that cross-check and fixed pre-release. +622 test assertions, +1,259,514 fuzz assertions, +1 benchmark (43 ns/px). |
| [0.4.0](../../CHANGELOG.md#040---2026-08-24) | **BMP → the same canonical RGBA8.** The third format, and the simplest decode path in the library: no entropy coding, no DEFLATE, no DCT — **6 ns/px** at 24/32 bpp against PNG's 83 and JPEG's 43. `BI_RGB` uncompressed at 1/4/8 bpp (palette, MSB-first), 24 bpp and 32 bpp; `BITMAPINFOHEADER` (40-byte) and `BITMAPCOREHEADER` (12-byte) DIB headers; bottom-up **and** top-down row order; the BGRA palette. New public `chitra_bmp_decode` / `chitra_bmp_decode_rgba8` / `chitra_bmp_check_signature`; `chitra_image_decode` now sniffs three formats. Output verified **identical to ImageMagick** on all eight valid fixtures, including the bottom-up/top-down pair that must agree from opposite storage orders. RLE4/RLE8, BITFIELDS, 16 bpp, V4/V5 headers reject with distinct codes; `BI_JPEG`/`BI_PNG` are refused outright as a decoder-recursion surface. +294 test assertions, +1,819,490 fuzz assertions, +3 benchmarks. |
| [0.3.3](../../CHANGELOG.md#033---2026-08-23) | **P-1 audit, hardening and repair — and both v1.0 hardening gates.** A ten-lens adversarial sweep of both decode paths, every finding put to two independent skeptics. **No memory-safety defect was found**; the repairs are correctness, conformance and resource hardening: full-width depth-16 tRNS keying, rejection of single-component non-interleaved JPEG scans, a JPEG decompression-bomb cap (`CHITRA_MAX_JPEG_RATIO`, the analogue of the PNG inflate-ratio cap), a `chitra_err_new` that can no longer return 0, T.81 fill-byte handling, ZRL overrun rejection, non-segment marker rejection, and the PNG § 5.4 / § 5.6 chunk-ordering guards. Every repair carries a regression test verified to fail against the pre-repair code. **Four input classes that previously decoded now reject**, deliberately. Adds the first fuzz harnesses (`make fuzz`, ~10⁶ cases) and the first benchmark harness (`make bench` + `bench-history.csv`), closing both remaining v1.0 hardening gates. Audit: [`2026-08-23`](../audit/2026-08-23-audit.md). |

## v1.0 criteria

The contract for tagging v1.0. Decode coverage now spans the full PNG matrix
and JFIF baseline JPEG; the open items are hardening infrastructure and the
surface freeze.

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
  into `make test-all`. As of 0.4.0 there is one harness per format (PNG,
  JPEG, BMP, GIF): **~2.2 M decode cases / 7,482,610 assertions, 0 failures**.
  0.3.3 alone cleared the 10⁶ bar with the first two. Both public decode entries are driven over random,
  signature-prefixed, bit-flipped, truncated and degenerate-length input, plus
  **entropy-segment-only mutation** for JPEG — the surface that was previously
  unfuzzed, since its hardening was forked from the kii/PNG lineage rather
  than re-exercised. The harnesses assert the documented `(0, *err_out set)`
  contract as well as survival. See
  [`docs/audit/2026-08-23-audit.md`](../audit/2026-08-23-audit.md) § 5.
- [x] **Benchmark harness + CSV history** — **DONE in 0.3.3.**
  `tests/bcyr/chitra.bcyr` (`make bench`) measures decode latency for both
  formats across 17 benchmarks, and `scripts/bench-csv.sh`
  (`make bench-record`) appends stamped results to
  [`bench-history.csv`](../../bench-history.csv). The harness **generates its
  own fixtures at 256×256** — the in-tree test fixtures are 2×2..16×16 and
  would measure fixed overhead, not throughput — and decode-verifies each one
  before timing it. First baseline: PNG rgba8 83 ns/px, Adam7 128 ns/px;
  JPEG grayscale 43 ns/px, 4:2:0 91 ns/px. Numbers are host- and
  load-dependent, so the CSV is a within-host series, not a cross-host
  comparison.
- [ ] **Public API + ABI freeze** — freeze the PNG surface
  (`chitra_png_decode` / `chitra_png_decode_rgba8`), the JPEG surface
  (`chitra_jpeg_decode` / `chitra_jpeg_decode_rgba8` /
  `chitra_jpeg_check_signature`), the format-router `chitra_image_decode`, the
  `ChitraImage` record (append-only fields), and the 16-byte `ChitraErr`
  (GpuErr-layout-compatible). Pending — the surface is still moving pre-1.0.
  Three concrete prerequisites, all surfaced by the
  [0.3.3 audit](../audit/2026-08-23-audit.md) and deliberately deferred out of
  a patch release because each changes the public surface:
  - Add `@public` markers to `chitra_png_check_signature` and
    `chitra_jpeg_check_signature`. Both are public by documentation and by
    consumer use, but live in modules carrying neither the file-level banner
    nor the per-function marker — so the marker set and the documented surface
    disagree, and a freeze should not codify that disagreement.
  - Reword the `chitra_err_name` strings for `CHITRA_ERR_INTERLACE` and
    `CHITRA_ERR_BIT_DEPTH`. Both read as capability limits ("interlace
    unsupported" / "bit depth unsupported") when both are in fact validity
    rejections — chitra decodes Adam7 and every spec-legal depth. Changing
    them changes public `chitra_err_name` output, which is precisely what a
    freeze makes expensive to do later.
  - ~~Settle whether the four input classes 0.3.3 began rejecting are the
    frozen behaviour~~ — **answered in 0.6.0.** One is **reversed**: the § A.2
    one-component geometry now decodes. The other three are **affirmed as
    frozen behaviour** — the JPEG amplification cap, PNG's § 5.4
    unknown-critical-chunk abort, and the § 5.6 / § 11.3.2 tRNS/PLTE ordering
    rules. The freeze need not re-open them.
  - **`CHITRA_ERR_UNSUPPORTED` (4) now carries three unrelated meanings**
    across two formats — a non-baseline JPEG mode, the § A.2 multi-scan
    deferral (0.6.0), and an undefined Adobe colour transform (0.6.1) — while
    its enum comment describes only the first. Either split it or document all
    three before freezing it.
  - **`chitra_image_seen_iend` is a PNG concept exposed on four formats**, and
    hardcoded on three of them. 0.7.0 makes it honest; the freeze has to decide
    whether the *name* survives, since nothing outside PNG has an IEND.
  - **`ChitraImage` carries no bit depth**, so a consumer cannot detect that
    16-bit precision was discarded. Adding one is append-only and cheap; not
    adding it is defensible; leaving it undecided at the freeze is not.
  - **Not a prerequisite, but the freeze should not ship without it**: a
    machine-checked manifest of the public surface. ~40 `chitra_`-prefixed
    functions are visible in `dist/chitra.cyr` and deliberately outside the
    freeze (`chitra_raw_*`, `chitra_jpeg_frame_*`, `chitra_bmp_hdr_*`,
    `chitra_png_parse_raw`, `chitra_png_color_to_rgba8`,
    `chitra_jpeg_scan_markers`), and "the surface is frozen" is an assertion
    until something checks it.
- [ ] **Downstream consumers green** — mabda's `gpu_texture_load_png` and
  kii's PNG re-fold (its v1.2.0 deleted its own decoder and adopted
  `dist/chitra.cyr`; ADR 0006 on kii's side) both build and pass against the
  frozen surface. Track until the freeze lands. **Both pins are currently
  behind**: mabda at `0.3.1`, kii at `0.3.0`, against a released `0.6.0`. Every cut since 0.3.1 has been
  ABI-additive — nothing removed, no offset moved — so both bumps are
  mechanical, but until they land neither consumer has BMP, GIF, the 0.3.3
  decode repairs, the nine 0.5.3 ones, or 0.6.0's § A.2 support — and kii is
  seven cuts behind on a path it uses in anger.
- [x] **Root docs + doc tree complete** — CLAUDE.md, README, CHANGELOG,
  CONTRIBUTING, SECURITY, ADRs ([`../adr/README.md`](../adr/README.md)),
  architecture notes ([`../architecture/README.md`](../architecture/README.md)),
  the getting-started guide
  ([`../guides/getting-started.md`](../guides/getting-started.md)), and
  examples ([`../examples/README.md`](../examples/README.md)) all current.

## Planned releases

Committed sequencing. Each is a single coherent cycle, smallest-first, and each
lands decode coverage (or surface stability) the previous one did not.

### ~~0.4.0 — BMP~~ — SHIPPED

See the *Shipped* index above. What it deliberately left undone is now
sequenced into the 0.5.x arc below rather than parked here.

One scope note worth carrying forward, because it is a **judgment call, not a
spec reading**: 32-bpp `BI_RGB` alpha. The fourth byte is formally undefined
for `BI_RGB` — alpha only becomes official under `BI_BITFIELDS` / the V4 masks.
chitra treats an all-zero alpha plane as padding (opaque) and otherwise honours
it, because trusting it blindly renders padding-zero files invisible while
ignoring it discards real alpha. ImageMagick makes the same call, which is what
settled it. **0.5.2 supersedes this**: once the declared masks are read, the
heuristic is replaced by the header's own answer and stops being a guess.

**The 0.5.x arc** — 0.5.0 added the last of the four common raster formats;
0.5.1 and 0.5.2 pay off the BMP deferrals from 0.4.0; 0.5.3 pays off the
**review** debt all three incurred. Splitting the BMP work into two cuts
follows the bite discipline: RLE is a decode loop, masks are a header feature,
and they share nothing. Ending the arc with an audit was not planned at 0.4.0
— it became obviously right once 0.5.2 found two silent mis-decodes in code
that had already passed half a million fuzz cases.

### ~~0.5.0 — GIF~~ — SHIPPED

See the *Shipped* index above. The scope question this cut was gated on —
first frame versus a multi-frame surface — was settled in
[ADR 0005](../adr/0005-gif-first-frame-only.md) in favour of **first frame
only**, preserving the one-image-in / one-image-out contract every other format
honours.

What that leaves open, and the ADR says so explicitly: an *optimised* animation
whose first frame is a background plate decodes to that plate. If a consumer
ever needs the sequence, the shape is a **separate** multi-frame entry point
returning a frame list, leaving `chitra_gif_decode` untouched — additive, not a
reversal.

### ~~0.5.1 — BMP run-length compression~~ — SHIPPED

See the *Shipped* index above. The prediction held: the guards were the bulk
of the work, and delta was the sharp opcode. One thing the plan did not
anticipate — **ImageMagick will not write `BI_RLE4` at all**, so those fixtures
are hand-built. They remain reference-*verified*, because ImageMagick reads
them back correctly; an encoder gap does not compromise the check.

### ~~0.5.2 — BMP channel masks, 16 bpp, and the V4/V5 headers~~ — SHIPPED

See the *Shipped* index above. All three landed together as planned, and the
grouping was right — they are the same feature from three angles:

- **`BI_BITFIELDS`** — explicit per-channel bit masks, deferred in 0.4.0 with
  `CHITRA_ERR_BMP_COMPRESSION`.
- **16 bpp** — deferred with `CHITRA_ERR_BMP_DEPTH` precisely *because* of the
  above: absent `BI_BITFIELDS`, 16-bpp channel layout is 5-5-5 by convention
  only, and honouring a convention while refusing the header that declares it
  would be the kind of guess this project rejects elsewhere. Reading the masks
  is what makes 16 bpp decodable rather than assumed.
- **`BITMAPV4HEADER` / `BITMAPV5HEADER`** (108 / 124 bytes) — deferred with
  `CHITRA_ERR_BMP_HEADER`. These are where the masks and an explicit alpha
  mask actually live, so they arrive with the same cut.

It retired the 32-bpp alpha heuristic **for files that declare a mask** — the
precision matters, since plain `BI_RGB` 32 bpp still has no mask to read and
the heuristic still governs there.

Two bugs worth carrying forward as lessons, both caught only by cross-checking
against a reference decoder: channel widening is **bit replication**, not
`v * 255 / max` (the arithmetic version is a whole-image color shift, not an
edge case), and a depth predicate written as `bpp < 24` silently stopped
meaning "indexed" the moment 16 bpp was added.

**The BMP deferral list is now empty.** `BI_JPEG` / `BI_PNG` are not in this
arc, or any arc — see *Out of scope*.

### ~~0.5.3 — P-1 audit and repair (BMP + GIF)~~ — SHIPPED

See the *Shipped* index above, and the report at
[`../audit/2026-08-24-audit.md`](../audit/2026-08-24-audit.md).

Three things from this cut are worth carrying forward as durable lessons
rather than release notes:

- **Fuzzing does not find wrong output.** Four harnesses and ~2.2 M cases had
  run over this code; seven of the nine confirmed findings were silent
  mis-decodes none of them could flag, because none of them crash. The check
  that found every one was decoding the same bytes with ImageMagick. The
  practical consequence: **a reference cross-check is not optional coverage**,
  it is the only instrument that sees this class of defect.
- **A guard that cannot fire is worse than no guard**, because it also
  documents a protection you do not have. The BMP "at least one colour
  channel" check was unreachable dead code from the day it shipped — the
  defaults injected upstream erased exactly the condition it tested — and the
  0.5.2 CHANGELOG advertised it anyway. Reachability is now part of what
  "verified to fail against the pre-repair code" has to mean.
- **A cap must be measured on what the attacker spent, not what they
  supplied.** The first BMP amplification cap was defeated by appending
  padding: junk bytes raised the attacker's own allowance. Measuring bytes
  actually *consumed* fixes it, and the same question — *what exactly is the
  denominator?* — should be asked of any future ratio guard.

### ~~0.6.0 — deferred JPEG geometry + surface work~~ — SHIPPED

See the *Shipped* index above for what landed. Both items were addressed; one
shipped code, the other shipped the decision the roadmap asked for.

The § A.2 item's original framing said *"the urgency is low"* because every real
grayscale encoder emits `H = V = 1`. That premise held only for the file shapes
chitra had fixtures for: `cjpeg -grayscale -sample 2x1` is one flag away, and
`-sample 4x4` was rejected two steps earlier still, by a frame-wide ΣHj·Vj cap
the spec conditions on `Ns > 1`. Implementing the layout also turned out to be
**smaller** than the deferral implied — the factors are inert for `Nf = 1`, so
it is a geometry collapse rather than a second decoder.

The streaming item shipped as [ADR 0007](../adr/0007-byte-budget-surface-deferred.md),
which is what *"this is additive surface, so it wants an ADR"* asked for. The
implementation moved to 0.6.1 on a measurement rather than a preference — see
that entry below.

### ~~0.6.1 — the byte-budget decode surface~~ — SHIPPED

See the *Shipped* index above. It shipped the surface **and** four repairs the
sweep turned up, which is the more important half: three of them were wrong
output or wrongly-refused input on files standard tools produce.

The surface landed at **two names**, not the eight ADR 0007 reserved, and
[ADR 0008](../adr/0008-byte-budget-as-shipped.md) records why. The short
version: a published byte *count* gets consumed as a number — someone sizes a
pool with it — and this very release moved the JPEG figure by ~21 KB.

The prerequisite ADR 0007 named (lazy table allocation) was necessary but not
sufficient. A *well-formed* JPEG refused on budget would still have cost 22 KB,
because it legitimately defines tables before the check — so the budget also
needed a structural dimension read that allocates nothing. Both halves were
required to make "a refusal is cheap" true rather than nominal.

## The 0.7.x arc

Built from the 0.6.1 deferment sweep — **84 findings** catalogued across the
four decoders, the harnesses, CI and the doc tree. Every one is scheduled
below, named as a permanent scope guard in *Out of scope*, or fixed in place as
doc drift. Nothing was left in a document that no release reads.

Ordered smallest-first, each cut a single theme.

### 0.7.0 — Stream-end honesty

**The decoder must say when it fabricated pixels.** Today it does not, and the
one field that exists to say so is a constant.

- A **JPEG truncated inside its entropy stream** decodes to zero-padded MCUs,
  returns success, and reports `seen_iend = 1`. Measured on a 689-byte file:
  truncating 8–60 bytes yields byte sums of 215,484 / 229,896 / 143,178 against
  a correct 223,824 — silently wrong, no signal. (Truncating further *does*
  reject, so the dangerous window is precisely "past the header, inside the
  scan".)
- A **GIF truncated mid-frame** decodes to a partial image, tail filled with
  palette entry 0 at alpha 255, with no error.
- `chitra_image_seen_iend` is **hardcoded to 1** on the JPEG, BMP and GIF paths
  — a PNG-specific "the stream closed properly" signal repurposed as a
  constant on three formats of four.

Scope: make the field mean "the stream ended the way this format says it
should", per format, and keep decoding rather than start rejecting — matching
libjpeg's partial-image behaviour and chitra's own tolerance of an IEND-less
PNG and an EOI-less JPEG. This is a **public behaviour change**, which is why
it is a minor bump and not a patch.

### 0.7.1 — PNG spec conformance: chunks that are forbidden, not merely odd

Three § 5.6 / § 11.3.2 rules chitra does not enforce, all found by reading the
code rather than by any marker in it:

- **tRNS on colour types 4 and 6** is spec-*forbidden* and is silently accepted
  and ignored. chitra's posture is inverted here: it **rejects** tRNS-before-PLTE
  (an ordering ImageMagick tolerates) while **accepting** a tRNS § 11.3.2
  forbids outright.
- **PLTE on colour types 0 and 4** is likewise forbidden and accepted. The
  asymmetry is visible in one function: the tRNS branch consults `color_type`
  eleven lines below a PLTE branch that does not.
- **IDAT contiguity** — "there shall not be any other chunks between the IDAT
  chunks" — is never checked, so an interleaved ancillary chunk still fuses the
  payloads. The flag machinery to enforce it already exists.

Also here: **depth-16 output is self-certified.** The 16→8 reduction is
truncation, and the depth-16 matrix cells assert chitra's own truncation rule
rather than a reference decode. Cross-check against ImageMagick and either
confirm the rule or record the divergence — the project's own lesson is that
this is the only instrument that sees wrong output.

### 0.7.2 — BMP and GIF loose ends

Small, independent, each a reachable wrong answer:

- **`BI_ALPHABITFIELDS` with a 52-byte V2 header** silently drops the alpha
  mask and decodes fully opaque — the mask fields are looked for in the wrong
  place for that header size.
- **A GIF Plain Text Extension is skipped as inert**, but it is a
  graphic-rendering block: a GCE that governs one is silently re-attributed to
  the following image descriptor, keying transparency the file never asked for.
  This is the same class as the 0.5.3 GCE finding, one block type over.
- **The GIF transparent index is never range-checked** against the table in
  force.
- **BMP RLE end-of-line** moves the write cursor past the last row without the
  at-the-jump check delta gets, so the two overshoot paths disagree.
- **OS/2 `BITMAPCOREHEADER2`** (any DIB size 16..64, canonically 64) is
  rejected; the accepted set is an allow-list of six sizes.

### 0.7.3 — Harness and CI gaps

The sweep's least glamorous findings and the ones most likely to hide the next
defect:

- **`fuzz/fuzz_png.fcyr` has no self-check**, alone among the four harnesses.
  A broken fixture would report hundreds of thousands of cases "survived" while
  exercising nothing — the exact no-op failure the other three assert against.
- **No PNG IDAT-stream-only fuzz mode.** PNG's per-chunk CRC means a random
  byte flip inside IDAT rejects at `CHITRA_ERR_CRC` before inflate or the
  unfilter predictors ever run, so the five predictors, the Adam7 deinterlace
  and the tRNS/palette colour pass are effectively unfuzzed. JPEG got exactly
  this treatment in 0.3.3 and it is why its entropy path is well covered.
- **Zero fuzz coverage for the four `_rgba8` wrappers**, which are public and
  about to be frozen.
- **`make fuzz` runs in no GitHub workflow**, so `make test-all` — CLAUDE.md's
  named pre-release gate — is never enforced by automation. CI's lint and fmt
  loops also omit `fuzz/*.fcyr` and `tests/bcyr/*.bcyr`, which the Makefile
  covers, so those files can pass CI and fail `make lint`.

### 0.8.0 — JPEG multi-scan resumption

As scheduled by [ADR 0006](../adr/0006-defer-jpeg-multiscan-resumption.md) —
moved out one cut because 0.7.x is repair work that should not wait behind it.

**Amend ADR 0006 first.** The sweep found its enumeration of what a correct
implementation owes to be incomplete; the ADR is the input to this cut, so it
has to be right before the cut starts.

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
  is out of scope; *surfacing* it would need a `ChitraImage` field and belongs
  to the v1.0 freeze discussion, not here.
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
  only if a consumer demonstrably needs progressive/CMYK decode.
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
