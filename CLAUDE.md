# chitra — Claude Code Instructions

> This file is **preferences, process, and procedures** — durable rules that
> change rarely. Volatile state (current version, binary/dist sizes, assertion
> counts, in-flight work, consumers) lives in
> [`docs/development/state.md`](docs/development/state.md) and
> [`CHANGELOG.md`](CHANGELOG.md). Do not inline state here — it rots within a minor.

---

## Project Identity

**chitra** (चित्र — Sanskrit: *image / picture*) — a pure-Cyrius CPU raster
image decoder. Encoded image bytes → canonical RGBA8 pixels. No GPU, no C shim,
no external binaries. The name is format-agnostic — PNG, JPEG, BMP and GIF all
share it, and further formats can join without a rename.

- **Type**: Shared library (no CLI binary — consumers link `dist/chitra.cyr`)
- **License**: GPL-3.0-only
- **Language**: Cyrius (toolchain pinned in `cyrius.cyml [package].cyrius` — that pin is the source of truth; do not inline the number here)
- **Version**: `VERSION` at the project root is the source of truth — do not inline the number here. SemVer. **The public surface is frozen as of 1.0.0** — the 29 names in [`docs/development/public-surface.md`](docs/development/public-surface.md) plus both record layouts. Changing a signature, removing a name, or changing documented behaviour there is a **major bump plus an ADR**, not a minor. `scripts/check-surface.sh` gates it on every `make lint`.
- **Genesis repo**: [agnosticos](https://github.com/MacCracken/agnosticos)
- **Standards**: [First-Party Standards](https://github.com/MacCracken/agnosticos/blob/main/docs/development/first-party/first-party-standards.md) · [First-Party Documentation](https://github.com/MacCracken/agnosticos/blob/main/docs/development/first-party/first-party-documentation.md)

## Goal

Own **CPU-side raster image decode** for AGNOS. Turn encoded image bytes into
canonical RGBA8 with zero GPU dependency and no C shim — the pure-Cyrius answer
to "load this image into a texture." All four common raster formats — PNG,
baseline JPEG, BMP and GIF — decode to that one surface. What remains before
v1.0 is the API/ABI freeze, not format coverage.

## Current State

> Volatile state — current version, `dist/chitra.cyr` size, assertion count,
> in-flight format work, consumers — lives in
> [`docs/development/state.md`](docs/development/state.md) (refreshed every release)
> and [`CHANGELOG.md`](CHANGELOG.md) (per-tag chronology).
>
> This file (`CLAUDE.md`) is durable rules only.

## Scaffolding

Project was scaffolded with the Cyrius tooling. **Do not manually create project
structure** — use the tools. If the tools are missing something, fix the tools.

## Quick Start

```bash
cyrius deps                                          # resolve stdlib + sankoch into lib/
make build                                           # link-check the lib (programs/smoke.cyr → build/chitra_smoke)
make test                                            # run every tests/tcyr/*.tcyr CPU suite
make fuzz                                            # adversarial-input harnesses (fuzz/*.fcyr)
make bench                                           # decode benchmarks (tests/bcyr/chitra.bcyr)
make dist                                            # regenerate dist/chitra.cyr via `cyrius distlib`
make lint fmt-check vet                              # quality gates
make version-check                                   # VERSION / cyrius.cyml / CHANGELOG / README / chitra_version() agree
make test-all                                        # version-check + dist regen + tests + fuzz (the pre-release gate)
make bench-record                                    # bench + append to bench-history.csv
make count-assertions                                # NUL-safe assertion total across suites
```

## Key Principles

- **Correctness is the optimum sovereignty** — a decoder that mis-renders one bit-depth × color-type cell is worse than one that rejects it cleanly.
- Test after EVERY change, not after the feature is "done" — `make test` is cheap.
- ONE change at a time — never bundle unrelated changes.
- **DEFLATE is sankoch's job, not chitra's** — IDAT inflate + chunk-CRC route through `sankoch` (`zlib_decompress` / `crc32` / `adler32`), exactly as kii does. Don't reimplement zlib inline.
- **Validate against a real reference** — every decode-matrix claim is checked against ImageMagick output, plus an interlaced-vs-non-interlaced cross-check. Numbers/images or it didn't happen. **JPEG narrowing**: the primary oracle is `djpeg -nosmooth`, which chitra matches byte-for-byte across the sampling matrix. ImageMagick is a valid *second* oracle only for grayscale and 4:4:4 — it upsamples chroma with a fancy (triangle) filter where chitra uses box, so on a 4:2:0 file it differs in 937 of 1536 bytes at up to 40/byte. That is a filter difference, not a bug; don't chase it.
- **Spec-cite the hard cells** — bit-depth × color-type legality follows PNG § 11.2.2 Table 11.1; the five unfilter predictors follow § 9. Cite the section in the code.
- Every buffer declaration is a contract: `var buf[N]` = N **bytes**, not N entries.
- **Trust no input byte** — an encoded image (PNG, JPEG, BMP or GIF) is untrusted external data. Bounds-check every length, reject lying headers, cap decompression bombs, bound every entropy/Huffman loop.
- **Bound the index, not a proxy for it** — a guard on a loop counter is not a guard on the buffer the loop writes. `gif_lzw.cyr` permitted 4097 stores into a 4096-byte buffer because the counter and the write index were different variables. A guard one looser than its buffer is a latent overflow, not a margin.
- **A guard that cannot fire is worse than no guard** — it documents a protection you do not have. Prove reachability: neuter the guard and confirm a test fails. BMP's "at least one colour channel" check was unreachable dead code from the day it shipped, and the CHANGELOG advertised it anyway.
- **Fuzzing does not find wrong output** — it finds crashes. Seven of nine findings in the 0.5.3 audit were silent mis-decodes that ~2.2 M fuzz cases had passed over. The instrument that sees this class is a **reference cross-check** (ImageMagick), and it is not optional coverage.

## Rules (Hard Constraints)

- **Read the genesis repo's CLAUDE.md first** — [agnosticos/CLAUDE.md](https://github.com/MacCracken/agnosticos/blob/main/CLAUDE.md)
- **Do not commit or push** — the user handles all git operations
- **NEVER use `gh` CLI** — use `curl` to the GitHub API if needed
- **`lib/` must be a real directory populated by `cyrius deps`** — never a symlink to a cyrius checkout (an agent editing `lib/*.cyr` would corrupt the toolchain repo). `make` targets guard this via `check-lib-wiring`; if it trips: `rm lib && mkdir lib && cyrius deps`.
- **Stdlib includes live ONLY in `src/lib.cyr`** — domain modules (`src/*.cyr`) are flat (no stdlib includes). This is what lets `cyrius distlib` strip-concatenate into a compile-clean `dist/chitra.cyr`. Adding a stdlib include to a domain module breaks the dist bundle.
- **`[lib].modules` order in `cyrius.cyml` is dependency order** — `error.cyr` (dep-free) → `png_chunks.cyr` → `png_filter.cyr` → `png_color.cyr` → `png.cyr` → `jpeg_huffman.cyr` → `jpeg_idct.cyr` → `jpeg_markers.cyr` → `jpeg.cyr` → `bmp.cyr` → `gif_lzw.cyr` → `gif.cyr` (the frame-independent JPEG leaves precede the frame-builder — see [architecture/004](docs/architecture/004-jpeg-decode-pipeline.md); `bmp.cyr` needs only `ChitraImage`, the ceilings and the error codes; `gif_lzw.cyr` is likewise a frame-independent leaf and must precede `gif.cyr`, which drives it). Don't reorder without re-running `cyrius distlib` and verifying the bundle still compiles.
- **`ChitraErr` stays a 16-byte record** (`+0` code, `+8` detail ptr) — layout-compatible with mabda's `GpuErr` so a decode failure maps cleanly onto `GPU_ERR_IMAGE_DECODE`. Don't widen it.
- **`ChitraImage` field additions are append-only** — `width`/`height`/`pixels`/`channels` keep their 0.1.x offsets (mabda's accessors depend on them). New fields go at the end (`seen_iend` @ +32, `src_ctype` @ +40, `src_depth` @ +48), and any widen bumps `CHITRA_IMAGE_SIZE`.
- Do not add unnecessary dependencies (current set: stdlib + `sankoch` + `thread`).
- Do not skip tests, fuzz-corpus checks, or reference-image verification before claiming a decode path works.
- Do not hardcode the toolchain version in CI YAML — the `cyrius = "X.Y.Z"` pin in `cyrius.cyml` is the only source of truth.

## kii Relationship (read before touching `src/png.cyr`)

chitra's PNG core is a **one-time fork** of kii's proven, fuzz-hardened,
W3C-compliant `src/png.cyr`, plus genuinely new code: the byte-buffer I/O
boundary (mabda hands over in-memory bytes, not a path) and the
canonical-RGBA8 + tRNS normalization pass. **There is no live dependency** — a
kii bugfix is a manual backport, and vice versa. When you fix a decode bug
here, note whether it also exists in kii.

## Cyrius Conventions

- All struct fields are 8 bytes (`i64`), accessed via `load64` / `store64` with offset (see `ChitraErr` / `ChitraImage` layouts).
- Heap-allocate large buffers — a `var buf[256000]` bloats the binary.
- `break` in while loops with `var` declarations is unreliable — use flag + `continue`.
- No negative literals — write `(0 - N)` not `-N`.
- No mixed `&&` / `||` in one expression — nest `if` blocks instead.
- `return;` without value is invalid — always `return 0;`.
- All `var` declarations are function-scoped — no block scoping.
- `enum` for constants (e.g. `ChitraErrCode`) — don't burn initialized-global slots.

## Public API Surface (`@public`)

Stable entry points consumers depend on — change these only with a `Breaking`
CHANGELOG entry and an ADR:

- `chitra_png_decode(src, len, err_out)` → owned RGBA8 `ChitraImage`, or `0` with `*err_out` set
- `chitra_png_decode_rgba8(src, len, w_out, h_out)` → RGBA8 ptr directly (no detailed error)
- `chitra_jpeg_decode(src, len, err_out)` / `chitra_jpeg_decode_rgba8(src, len, w_out, h_out)` — the JPEG pair, mirroring the PNG ones
- `chitra_bmp_decode(src, len, err_out)` / `chitra_bmp_decode_rgba8(src, len, w_out, h_out)` — the BMP pair (0.4.0)
- `chitra_gif_decode(src, len, err_out)` / `chitra_gif_decode_rgba8(src, len, w_out, h_out)` — the GIF pair (0.5.0). **First frame only** — see [ADR 0005](docs/adr/0005-gif-first-frame-only.md)
- `chitra_image_decode_budget(src, len, max_bytes, err_out)` → decode unless the RGBA8 output would exceed `max_bytes` (0.6.1). A refusal costs 16 bytes (144 for BMP) and sets `CHITRA_ERR_BUDGET`; it is **never a validity opinion** — an unreadable header goes to the router so the real error is reported. See [ADR 0008](docs/adr/0008-byte-budget-as-shipped.md)
- `chitra_image_decode(src, len, err_out)` → the **format-sniffing router** (PNG magic, then JPEG SOI, then BMP `BM`, then GIF `GIF8?a`, else `CHITRA_ERR_SIGNATURE`); the entry to reach for when the format isn't known up front
- `chitra_png_check_signature` / `chitra_jpeg_check_signature` / `chitra_bmp_check_signature` / `chitra_gif_check_signature` — signature predicates
- `chitra_image_{width,height,pixels,channels,seen_iend,source_color_type,source_depth}` accessors (`source_depth`: bits per channel in the SOURCE — PNG IHDR depth, 8 for JPEG/GIF, the widest declared channel for BMP) (`source_color_type`: PNG color_type 0/2/3/4/6; `0x100 | ncomp` for JPEG — 0x101 grayscale, 0x103 YCbCr, **0x113 RGB** (0.6.1); `0x200 | bpp` for BMP — 0x208 palette-8, 0x218 24bpp, 0x220 32bpp; `0x300 | min_code_size` for GIF)
- `chitra_image_free` (no-op under the bump allocator; kept for symmetry)
- `chitra_version()` (packed `major*10000 + minor*100 + patch`)
- error API: `chitra_err_new` / `chitra_err` / `chitra_err_code` / `chitra_err_detail` / `chitra_err_name` / `chitra_err_print_name` + the `ChitraErrCode` enum

**The frozen list is [`docs/development/public-surface.md`](docs/development/public-surface.md)**, checked against `dist/chitra.cyr` by `scripts/check-surface.sh` on every `make lint`. The bundle is a strip-concatenation, so it exports 74 `chitra_*` names and **45 of them are internal** — the manifest is what says which is which, and the gate fails both when the bundle gains an unclassified name and when the manifest names one the bundle lost.

## Process

### Work Loop (continuous)

1. **Work phase** — new format support, decode-matrix cells, bug fixes
2. **Build check** — `make build` (link-check the include chain)
3. **Test additions** — a `.tcyr` suite cell for every new decode path (happy + reject), and a `fuzz/*.fcyr` case for any new byte-level surface. A repair without a regression test that was **checked to fail against the pre-repair code** is not finished — a test that passes both ways proves nothing
4. **Reference verification** — diff decode output against ImageMagick / a known-good corpus
5. **Internal review** — bounds, memory, correctness, edge cases
6. **Security check** — any new chunk-length/buffer/inflate-cap handling; `make fuzz` green
7. **Documentation** — CHANGELOG, `docs/development/state.md`, any ADR the change earned
8. **Version check** — `make version-check` (all five sources of truth in sync)
9. **Dist regen** — `make dist`, confirm `dist/chitra.cyr` still compiles clean
10. **Return to step 1**

### Security Hardening (before every release)

An encoded image is untrusted external data. The guards below are
non-negotiable — re-verify each before tagging.

**PNG** (the kii-inherited guards):

1. **Decompression-bomb caps** — two distinct gates: the fused IDAT *input* accumulator is capped at `CHITRA_MAX_RAW_BYTES` → `CHITRA_ERR_OOM` (`png_filter.cyr:445`), and the IHDR-derived inflated/pixel *output* sizes are capped → `CHITRA_ERR_DIMENSIONS` (`png_filter.cyr:543`-`550`)
2. **Lying-IHDR rejection** — declared dimensions cross-checked against actual data → `CHITRA_ERR_DIMENSIONS`
3. **Ratio caps** — output:input expansion bounded by `CHITRA_MAX_INFLATE_RATIO` → `CHITRA_ERR_DIMENSIONS` (`png_filter.cyr:562`)
4. **Chunk-CRC validation** — every chunk's CRC-32 checked → `CHITRA_ERR_CRC`
5. **Bounds on every read** — truncated input → `CHITRA_ERR_TRUNCATED`, never an OOB read
6. **Filter-byte validation** — per-row filter ∈ {0,1,2,3,4} → else `CHITRA_ERR_FILTER`
7. **Spec-legal matrix only** — illegal bit-depth × color-type combos rejected, not guessed
8. **Unknown critical chunks abort** — § 5.4's ancillary bit is honoured: an unrecognised *critical* chunk changes how the image is to be interpreted, so it is rejected → `CHITRA_ERR_UNSUPPORTED`. Unknown *ancillary* chunks stay skippable — do not let this become blanket rejection
9. **Chunk ordering + uniqueness** — PLTE and tRNS are each at-most-once and must precede IDAT (§ 5.6 / § 11.3.2). Track "have we seen IDAT" with an explicit flag, never by testing an accumulated byte count: a spec-legal **zero-length IDAT** leaves the count at 0 and defeats the guard
10. **tRNS keys one exact value** — the § 11.3.2 color key is compared at FULL sample width. Comparing at the truncated 8-bit output width makes every value sharing a high byte transparent

**JPEG** (baseline; see [docs/audit/2026-06-27-audit.md](docs/audit/2026-06-27-audit.md) and [docs/audit/2026-08-23-audit.md](docs/audit/2026-08-23-audit.md); § A.2 geometry per [ADR 0006](docs/adr/0006-defer-jpeg-multiscan-resumption.md)):

1. **Non-baseline rejection** — progressive / arithmetic / 12-bit / hierarchical-lossless / CMYK rejected at the marker classifier with distinct codes (attack-surface reduction)
2. **Marker/segment bounds** — every 16-bit segment length validated against the input span
3. **Sampling-factor guards** — `Hi/Vi ∈ 1..4` (reject 0 → div-by-zero), no duplicate component ids, `ΣHi·Vi ≤ 10`
4. **Table bounds** — DQT/DHT precision/id checked; Huffman build rejects over-subscription; DECODE rejects out-of-range symbol indices
5. **Entropy bounds** — DC category ≤ 11, AC size ≤ 10, coefficient index ≤ 63; restart markers resync deterministically
6. **Plane/dimension caps** — every allocation bounded by `CHITRA_MAX_RAW_BYTES`; upsample indices stay within plane bounds
7. **Amplification cap** — output:input bounded by `CHITRA_MAX_JPEG_RATIO` → `CHITRA_ERR_DIMENSIONS`. JPEG needs this *more* than PNG does: the entropy bit-reader zero-pads past end-of-data, so a hostile file needs **no scan payload at all** — the declared SOF0 geometry alone drives the work, and the bump allocator never reclaims it
8. **Only length-bearing markers are skipped by length** — standalone markers (SOI, EOI, RSTn, TEM) and the T.81 Table B.1 reserved range are rejected, not treated as segments. Otherwise the walk reads two attacker bytes as a length and the cursor is steered by the input
9. **Fill bytes tolerated, both sides** — § B.1.1.2 allows any number of `0xFF` bytes before a marker. The header walk *and* the entropy reader must both collapse the run, or valid files are rejected
10. **Geometry chitra does not implement is rejected, not approximated** — as of 0.6.0 that means MULTI-SCAN and partially-interleaved files (`Ns < Nf`), which reject with `CHITRA_ERR_UNSUPPORTED` (a deferral, not a validity error — the file is valid and chitra declines it; see [ADR 0006](docs/adr/0006-defer-jpeg-multiscan-resumption.md)). It no longer means the one-component case, which now decodes
11. **For a ONE-component frame the sampling factors are INERT (0.6.0)** — not merely ignorable. § A.1.1 gives `x_i = ceil(X·H_i/H_max)`, and with `Nf = 1` the lone component IS the maximum, so `x_1 = X` for every legal `(H,V)`. That is why the non-interleaved layout is an *effective-geometry collapse* (force `H = V = max_h = max_v = 1`) rather than a second decoder — and why it needs no plane zero-fill: `cpw = ceil(w/8)*8` covers the plane with NO unwritten margin. Keep ONE grid variable; a second (`grid_w` for the count while `mcu_cols` sizes the plane) lets placement diverge from count
12. **ΣHj·Vj ≤ 10 is § B.2.3 and applies only when Ns > 1** — it bounds an INTERLEAVED MCU, and a one-component frame has none. Conditioned, not removed, and it stays at the SOF0 parse (moving it to the scan header would put it after the allocations it exists to bound)
13. **A 3-component JPEG is not necessarily YCbCr (0.6.1)** — `cjpeg -rgb` writes RGB components with an Adobe APP14 `transform=0` and ids `'R','G','B'`. Applying BT.601 to them hue-rotates the image with NO error: 1,149 of 1,536 bytes wrong, a blue pixel returned dark red. Order of authority: the APP14 transform, else the component ids, else YCbCr. An undefined transform is DECLINED — assuming YCbCr for it is the same guess in a smaller form
14. **Allocation timing is part of the attack surface (0.6.1)** — `chitra_jpeg_scan_markers` allocated 22,160 bytes BEFORE any check could refuse the file, on every call, unmemoized. Tables are now allocated when a DQT/DHT first defines something, guarded `== 0` — per FRAME, never per DEFINITION: a single DHT may carry 3,854 definitions, so per-definition allocation trades a flat cost for one that SCALES with file size
15. **An amplification denominator must exclude bytes the decoder never decodes (0.6.1)** — `CHITRA_MAX_JPEG_RATIO` divided by whole-file length, so 16,404 bytes of skipped APPn padding bought a 4096×4096 decode and 117 MB. The denominator is now a real entropy-span walk. This is the 0.5.3 BMP-RLE lesson: ask what the attacker actually SPENT
16. **The exact-fit property depends on the BOX upsampler** — box reads exactly `(y·Vi/max_v)*comppw + (x·Hi/max_h)`. A fancy/triangle upsampler reads `x+1` and would make an edge margin live again, reopening a read-of-uninitialized class

**BMP** (0.4.0 `BI_RGB`; + RLE 0.5.1; + BITFIELDS/16 bpp/V4-V5 0.5.2; audited 0.5.3 — see [docs/audit/2026-08-24-audit.md](docs/audit/2026-08-24-audit.md)):

1. **Header fields validated before use** — every field is checked before it derives another, and every derived size is capped before allocation: dimensions vs `CHITRA_MAX_DIM` / `CHITRA_MAX_PIXELS`, `stride * height` vs `CHITRA_MAX_RAW_BYTES`
2. **The pixel-data offset is attacker-controlled** — it is a header field, not "after the palette", and it can point anywhere. The whole `data_off + stride*height` span is validated against `len` → `CHITRA_ERR_TRUNCATED`
3. **Palette span + index bounds** — the palette span is validated against `len`, and every index is hard-rejected against the declared entry count → `CHITRA_ERR_BMP_PALETTE`. Never clamp an index; reject it
4. **The deferral list is empty as of 0.5.2** — RLE8/RLE4 (0.5.1), BITFIELDS/16 bpp/V4/V5 (0.5.2). `BI_JPEG` / `BI_PNG` are refused **permanently**: honouring them re-enters the decoder, which is a recursion surface, not a feature. Accepted DIB header sizes are an **allow-list** (12/40/52/56/108/124), not a lower bound
5. **No checksum exists** — BMP has nothing like PNG's per-chunk CRC, so every byte of a BMP reaching the parser is attacker-chosen with nothing to turn it away but chitra's own bounds. Treat the header parser as the entire perimeter
6. **RLE (0.5.1)** — termination is structural (every opcode consumes ≥ 2 bytes; the cursor only advances). Bounds-check every write **individually**, not per-run: reject a run past the row end, never clip it, or you decode a different image than the file encodes. Check **delta at the jump** against both dimensions — a delta past the end followed by no writes is still malformed. Top-down + RLE is rejected (the end-of-line escape counts rows from the bottom), and RLE8/RLE4 must match 8/4 bpp
7. **Channel masks are attacker input (0.5.2)** — validate every one: contiguous (a split mask names no real channel), non-overlapping (two channels claiming a bit is a contradiction), inside the pixel word (a 24-bit mask on 16 bpp reads bits that are not there), and at least one color channel present. An unvalidated width feeds a shift, and an unvalidated shift reads outside the pixel
8. **Widening a sub-8-bit channel is BIT REPLICATION**, not `v * 255 / max` — shift left and refill the low bits from the field's own high bits. The arithmetic forms disagree with every reference decoder (a 6-bit 48 is 195, not 194), and the error is a whole-image color shift rather than an edge case
9. **A validated mask must then be USED (0.5.3)** — validating the masks and then decoding by a fixed BGRA layout is the worst of both: the file is checked against a contract the decoder does not honour. And **whether the file declares alpha is a separate question from whether it declares a channel order** — gating the mask path on `mask_a != 0` swapped red and blue on real files
10. **Masks are `BI_BITFIELDS`-only (0.5.3)** — MS: the V4/V5 mask fields are *"valid only if compression is `BI_BITFIELDS`"*, and real writers populate them under `BI_RGB` anyway. Reading them there decoded a V4 file **fully transparent**. Equally, do not inject `BI_RGB` defaults into a bitfields file: it invents a layout the file never declared, and it made the "at least one colour channel" guard **unreachable dead code**
11. **RLE amplification cap (0.5.3)** — `CHITRA_MAX_BMP_RLE_RATIO` bounds output against bytes **CONSUMED**, not file size → `CHITRA_ERR_DIMENSIONS`. Measuring the file lets an attacker raise their own allowance by appending padding, which is exactly what defeated the first version

**GIF** (0.5.0; first frame only — [ADR 0005](docs/adr/0005-gif-first-frame-only.md); audited 0.5.3):

1. **LZW is chitra's own decompressor** — `sankoch` has no LZW to delegate to, unlike PNG's DEFLATE. Treat it as the newest attack surface in the tree
2. **Expansion capped at the frame's pixel count** — LZW is a compressor; a few hundred bytes expand without limit unless bounded → `CHITRA_ERR_GIF_LZW`
3. **Prefix chains cannot cycle** — entries are only added with `prefix < the index being written`, so chains strictly decrease. The walk is *additionally* bounded by the dictionary size: a guard you can reason about is worth less than one you cannot get past
4. **Codes above `next_code` are rejected**; the one legal exception (`code == next_code`, KwKwK) is handled explicitly. A truncated LZW stream rejects rather than zero-padding — padding would fabricate dictionary entries
5. **Sub-block chains** — every length byte bounds-checked, gathered payload capped at the input length, so a chain cannot make chitra hold more than the file
6. **Frame rect must lie inside the logical screen** — reject, never clamp; clamping decodes a different image than the file describes
7. **Palette indices hard-rejected** against the table in force (local wins over global)
8. **Amplification cap (0.5.3)** — `CHITRA_MAX_GIF_RATIO` bounds output against the compressed stream, checked **before** the allocation it exists to prevent → `CHITRA_ERR_DIMENSIONS`. It is deliberately looser than PNG's 1100:1: LZW's legitimate compression of degenerate content is close to the bomb ratio, so the cap bounds the extreme case, not the merely aggressive one
9. **Fixed-size blocks need their size checked (0.5.3)** — a GCE's block size is fixed at 4 and every field after it is addressed by a fixed offset. Validate it, or a GCE declaring another size has chitra read the packed byte and transparent index from bytes that are not those fields → `CHITRA_ERR_GIF_HEADER`
10. **A GCE governs the graphic that FOLLOWS it (0.5.3)** — including one that turns transparency **off**. State from a previous GCE must be cleared, not merely overwritten when present. Cyrius `var`s are function-scoped, so "the last value that happened to be stored" is the default failure mode in a long block walk

File findings in `docs/audit/YYYY-MM-DD-audit.md`. Severity: CRITICAL / HIGH / MEDIUM / LOW.

### Closeout Pass (before every minor/major bump)

1. Full test suite — every `.tcyr` passes, zero failures (`make test`)
2. Fuzz clean — `make fuzz` green; both harnesses assert survival **and** the documented `(0, *err_out set)` contract
3. Reference re-verify — the full decode matrix against ImageMagick. Not a formality: it is the only check that sees a **silent mis-decode**, and the 0.5.3 audit found seven
4. Dead-code / cleanup sweep — stale comments, unused includes, orphaned files
5. Code-anchor sweep — `./scripts/check-anchors.sh`. The docs cite code by line number, and those move whenever a guard is added above them; this rot has already needed hand-repair twice. The script prints every citation with the line it now points at and flags the ones landing on a brace or past EOF. It does not gate CI — it cannot know what a line was meant to say — but the closeout should not skip it. Dated `docs/audit/` reports are excluded: their anchors are a historical record, not a live claim
6. Code-review pass — missed guards, off-by-ones, silently-ignored errors, ABI leaks
7. Security re-scan — the hardening checklist above
8. Downstream check — mabda still builds and `gpu_texture_load_png` works against the new `dist/chitra.cyr`; bump the `[deps.chitra]` pins in mabda and kii *after* the tag lands
9. Benchmark record — `make bench-record`, so `bench-history.csv` has a row per release. Benchmarks are a performance signal, not a correctness gate; they stay out of `test-all` because the numbers are host-dependent
10. Doc sync — CHANGELOG, roadmap, `docs/development/state.md`, CLAUDE.md (if durable content changed)
11. Version verify — `make version-check`; intended git tag matches
12. Clean dist regen — `cyrius distlib` produces a compile-clean bundle

### Task Sizing

- **Low/Medium effort**: batch freely.
- **Large effort** (a new format like JPEG): small bites — Huffman, then IDCT, then chroma upsample, verifying each.
- **If unsure**: treat it as large.

## CI / Release

- **Toolchain pin**: `cyrius = "X.Y.Z"` in `cyrius.cyml [package]`. CI and release both read it; no hardcoded version strings in YAML.
- **Workflows**: `.github/workflows/ci.yml` (deps + fmt + lint + vet + build + test) and `.github/workflows/release.yml` (version gate → CI gate → dist + artifacts).
- **Tag filter**: release triggers on semver-only tags. Non-numeric tags do not ship.
- **Version-verify gate**: release asserts `VERSION == cyrius.cyml version == git tag` before building.
- **State sync**: bump `docs/development/state.md` at release. If a release hook can do it, fix the hook rather than hand-maintaining state.

## Docs

- [`docs/adr/`](docs/adr/) — architecture decision records. *Why X over Y?* (e.g. "fork kii's png.cyr vs. shared dep")
- [`docs/architecture/`](docs/architecture/) — non-obvious constraints. *What can't I derive from the code alone?* (e.g. the `lib/`-must-not-be-a-symlink quirk, the flat-domain-module + distlib invariant)
- [`docs/guides/`](docs/guides/) — task-oriented how-tos (e.g. "consuming chitra from mabda")
- [`docs/development/roadmap.md`](docs/development/roadmap.md) — shipped (PNG, baseline JPEG, BMP, GIF + the 0.5.x arc, § A.2 Nf=1 in 0.6.0), backlog (byte-budget surface 0.6.1, JPEG multi-scan 0.7.0), v1.0 criteria
- [`docs/development/state.md`](docs/development/state.md) — live state snapshot, refreshed every release
- [`docs/audit/`](docs/audit/) — security audit reports (`YYYY-MM-DD-audit.md`)
- [`docs/proposals/`](docs/proposals/) — design notes written *before* a large feature lands (e.g. the baseline-JPEG plan)
- `fuzz/*.fcyr` (`make fuzz`) and `tests/bcyr/chitra.bcyr` (`make bench`) — the two hardening harnesses; both **generate** their inputs, and both self-verify before asserting anything
- [`CHANGELOG.md`](CHANGELOG.md) — source of truth for all changes (Keep a Changelog; perf claims carry numbers; breaking changes get a Breaking section)

New quirks land in `docs/architecture/` as numbered items (`NNN-kebab-case.md`).
New decisions land in `docs/adr/` (`NNNN-kebab-case.md`). **Never renumber either series.**
