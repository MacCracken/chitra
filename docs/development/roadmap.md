# chitra — Roadmap

> **Last Updated**: 2026-08-24 (0.5.1)
>
> Sequencing — what ships, in what order, against what gates. Volatile state
> (current version, sizes, assertion counts, in-flight work) lives in
> [`state.md`](state.md), not here. **chitra is pre-v1** (current: 0.5.1) and
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
- [x] **In-tree fuzz harness at 10⁶ iterations clean** — **DONE in 0.3.3.**
  `fuzz/fuzz_png.fcyr` + `fuzz/fuzz_jpeg.fcyr`, run by `make fuzz` and wired
  into `make test-all`. As of 0.4.0 there is one harness per format (PNG,
  JPEG, BMP, GIF): **~2.1 M decode cases / 7,182,567 assertions, 0 failures**.
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
  - Settle whether the four input classes 0.3.3 began rejecting are the frozen
    behaviour, or whether any should decode instead (see the § A.2 item
    below).
- [ ] **Downstream consumers green** — mabda's `gpu_texture_load_png` and
  kii's PNG re-fold (its v1.2.0 deleted its own decoder and adopted
  `dist/chitra.cyr`; ADR 0006 on kii's side) both build and pass against the
  frozen surface. Track until the freeze lands. **Both pins are currently
  behind**: mabda at `0.3.1`, kii at `0.3.0`, against a released `0.3.3`. The
  0.3.3 dist is ABI-identical — no public signature, struct offset or symbol
  changed — so both bumps are mechanical, but until they land neither consumer
  has the 0.3.3 decode repairs, and kii is two cuts behind on a path it uses
  in anger.
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
0.5.1 and 0.5.2 pay off the BMP deferrals from 0.4.0. Splitting the BMP work
into two cuts follows the bite discipline: RLE is a decode loop, masks are a
header feature, and they share nothing.

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

### 0.5.2 — BMP channel masks, 16 bpp, and the V4/V5 headers

The remaining 0.4.0 deferrals, which are one coherent piece of work because
they are all the same feature seen from different angles:

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

Landing this also **retires the 32-bpp alpha heuristic** described under 0.4.0
above: with a declared alpha mask, chitra stops inferring and reads.

`BI_JPEG` / `BI_PNG` are **not** in this arc, or any arc — see *Out of scope*.

### 0.6.0 — deferred JPEG geometry + surface work

The two items previously parked as uncommitted, now sequenced:

- **T.81 § A.2 non-interleaved JPEG scans** — implement the non-interleaved
  layout so a single-component scan with `H > 1` or `V > 1` **decodes** instead
  of being rejected. 0.3.3 chose rejection over mis-rendering for a patch cut
  (`CHITRA_ERR_UNSUPPORTED`); this is the follow-through. Every real grayscale
  encoder emits `H = V = 1`, where the interleaved and non-interleaved layouts
  coincide, so the urgency is low — but it is a spec-legal input class chitra
  currently refuses.
- **Streaming / byte-budget decode API** — a chunked-input or
  bounded-allocation entry point for consumers that cannot hand over the whole
  encoded buffer at once, or that need a hard memory ceiling. This is additive
  surface, so it wants an ADR and it wants to land before the v1.0 freeze
  rather than after.

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
- **Non-baseline JPEG** — **progressive**, **arithmetic-coded**, 12-bit,
  hierarchical/lossless, and **CMYK** JPEG are **deferred**, not supported.
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
