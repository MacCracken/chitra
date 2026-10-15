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
baseline JPEG, BMP and GIF — decode to that one surface. **As of 1.0.0 the
public surface is frozen**, so what remains is maintenance inside that promise
(see [`docs/development/public-surface.md`](docs/development/public-surface.md)),
not format coverage. Adding a format is still additive; changing a frozen name
is a major bump plus an ADR.

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
cyrius deps                                          # resolve stdlib + sankoch into lib/ (CI: `cyrius deps --locked`)
make build                                           # link-check the lib (programs/smoke.cyr → build/chitra_smoke)
make test                                            # run every tests/tcyr/*.tcyr CPU suite
make fuzz                                            # every fuzz/*.fcyr under `--poison` (allocator redzones) — exactly what CI runs
make bench                                           # decode benchmarks (tests/bcyr/chitra.bcyr)
make bench-build                                     # compile the bench harness without running it (CI + test-all)
make dist                                            # regenerate dist/chitra.cyr via `cyrius distlib`
make lint fmt-check vet                              # quality gates (lint also runs scripts/check-surface.sh)
make version-check                                   # VERSION / cyrius.cyml / CHANGELOG / README / chitra_version() / state.md's chitra_version claims agree
make test-all                                        # version-check + dist regen + tests + fuzz + bench-build (the pre-release gate)
make bench-record                                    # bench + append to bench-history.csv
make count-assertions                                # NUL-safe assertion total across suites
```

## Key Principles

- **Correctness is the optimum sovereignty** — a decoder that mis-renders one bit-depth × color-type cell is worse than one that rejects it cleanly.
- Test after EVERY change, not after the feature is "done" — `make test` is cheap.
- ONE change at a time — never bundle unrelated changes.
- **DEFLATE is sankoch's job, not chitra's** — IDAT inflate + chunk-CRC route through `sankoch` (`zlib_decompress` / `crc32` / `adler32`), exactly as kii does. Don't reimplement zlib inline.
- **Validate against a real reference** — every decode-matrix claim is checked against ImageMagick output, plus an interlaced-vs-non-interlaced cross-check. Numbers/images or it didn't happen. **JPEG narrowing**: the primary oracle is `djpeg -nosmooth`. chitra matches it exactly on most files and can differ by at most **1 LSB per IDCT output** on any file — `_jpeg_descale` (`src/jpeg_idct.cyr:119`) rounds half AWAY FROM ZERO where libjpeg's arithmetic-shift DESCALE rounds half UP. That is a rounding choice inside IEEE 1180 tolerance, not a decode bug; don't chase it either. ImageMagick is a valid *second* oracle only for grayscale and 4:4:4 — it upsamples chroma with a fancy (triangle) filter where chitra uses box, so on a 4:2:0 file it differs in 937 of 1536 bytes at up to 40/byte. That is a filter difference, not a bug; don't chase it.
- **Spec-cite the hard cells** — bit-depth × color-type legality follows PNG § 11.2.2 Table 11.1; the five unfilter predictors follow § 9. Cite the section in the code.
- Every buffer declaration is a contract: `var buf[N]` = N **bytes**, not N entries.
- **Trust no input byte** — an encoded image (PNG, JPEG, BMP or GIF) is untrusted external data. Bounds-check every length, reject lying headers, cap decompression bombs, bound every entropy/Huffman loop.
- **Bound the index, not a proxy for it** — a guard on a loop counter is not a guard on the buffer the loop writes. `gif_lzw.cyr` permitted 4097 stores into a 4096-byte buffer because the counter and the write index were different variables. A guard one looser than its buffer is a latent overflow, not a margin.
- **A guard that cannot fire is worse than no guard** — it documents a protection you do not have. Prove reachability: neuter the guard and confirm a test fails. BMP's "at least one colour channel" check was unreachable dead code from the day it shipped, and the CHANGELOG advertised it anyway.
- **A cap belongs BEFORE the allocation it exists to prevent** — and when its honest denominator is only knowable afterwards, it needs a second, *strictly weaker* bound in front. The 1.0.3 sweep found this shape four times in three formats: JPEG spent **50,354,832 B** to refuse a 4,250-byte file, BMP spent **16,777,344 B** to refuse a 60-byte one, and GIF allocated a flat **69,632 B** dictionary before reading a code. A cap that fires afterwards is decoration on an allocator that never frees, and the spend is *cumulative across decodes*. ⚠ The weaker pre-gate must not REPLACE the exact check: padding a file raises the pre-gate's own bound, which is the attack the exact denominator exists to see. ⛔ And "only knowable afterwards" is a claim to test, not assume: 1.1.1 found JPEG's exact denominator was byte-structural all along, so 4,200 bytes of padding walked straight past the weaker gate and back into B-3's 50,354,832 B — the exact check now runs first too.
- **A gate that cannot fire is a guard that cannot fire, one level up** — audit the machinery, not just the code. 1.0.3 found `check-surface.sh` running in **no CI workflow at all**, an unvalidated pin grep whose empty result makes the installer take *latest*, two script failure-branches unreachable under `set -euo pipefail`, an anchor checker blind to half the citations it reports clean, and a test stack in which **transposing width and height on mabda's primary entry point passed all 13 suites and all 10.7 M fuzz assertions**. Every wrapper fixture was square.
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
- Do not add unnecessary dependencies (current set: stdlib + `sankoch`'s **`zlib` profile** via `[deps.sankoch]`). Link the narrowest sankoch bundle that carries what chitra calls, and never a second one — sankoch allows one bundle per program, and a consumer's own `[deps.sankoch]` overrides chitra's (closest-wins).
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
- `chitra_image_decode_budget(src, len, max_bytes, err_out)` → decode unless the RGBA8 output would exceed `max_bytes` (0.6.1). A refusal costs 16 bytes (128 for BMP — measured; it was misquoted as 144 until 1.1.1) and sets `CHITRA_ERR_BUDGET`; it is **never a validity opinion** — an unreadable header goes to the router so the real error is reported. See [ADR 0008](docs/adr/0008-byte-budget-as-shipped.md)
- `chitra_image_decode(src, len, err_out)` → the **format-sniffing router** (PNG magic, then JPEG SOI, then BMP `BM`, then GIF `GIF8?a`, else `CHITRA_ERR_SIGNATURE`); the entry to reach for when the format isn't known up front
- `chitra_png_check_signature` / `chitra_jpeg_check_signature` / `chitra_bmp_check_signature` / `chitra_gif_check_signature` — signature predicates
- `chitra_image_{width,height,pixels,channels,seen_iend,source_color_type,source_depth}` accessors (`source_depth`: bits per channel in the SOURCE — PNG IHDR depth, 8 for JPEG/GIF, the widest declared channel for BMP) (`source_color_type`: PNG color_type 0/2/3/4/6; `0x100 | ncomp` for JPEG — 0x101 grayscale, 0x103 YCbCr, **0x113 RGB** (0.6.1); `0x200 | bpp` for BMP — 0x208 palette-8, 0x218 24bpp, 0x220 32bpp; `0x300 | min_code_size` for GIF)
- `chitra_image_free` (no-op under the bump allocator; kept for symmetry)
- `chitra_version()` (packed `major*10000 + minor*100 + patch`)
- error API: `chitra_err_new` / `chitra_err` / `chitra_err_code` / `chitra_err_detail` / `chitra_err_name` / `chitra_err_print_name` + the `ChitraErrCode` enum

**The frozen list is [`docs/development/public-surface.md`](docs/development/public-surface.md)**, checked against `dist/chitra.cyr` by `scripts/check-surface.sh` on every `make lint` and in CI. The same script fails when a `ChitraErrCode` member has no `chitra_err_name` arm or no literal value pin in `tests/tcyr/surface.tcyr` (1.1.1) — the freeze covers the enum's numeric values, and the old name check stopped at 34. The bundle is a strip-concatenation, so it exports 75 `chitra_*` names and **46 of them are internal** — the manifest is what says which is which, and the gate fails both when the bundle gains an unclassified name and when the manifest names one the bundle lost.

## Process

### Work Loop (continuous)

1. **Work phase** — new format support, decode-matrix cells, bug fixes
2. **Build check** — `make build` (link-check the include chain)
3. **Test additions** — a `.tcyr` suite cell for every new decode path (happy + reject), and a `fuzz/*.fcyr` case for any new byte-level surface. A repair without a regression test that was **checked to fail against the pre-repair code** is not finished — a test that passes both ways proves nothing
4. **Reference verification** — diff decode output against ImageMagick / a known-good corpus
5. **Internal review** — bounds, memory, correctness, edge cases
6. **Security check** — any new chunk-length/buffer/inflate-cap handling; `make fuzz` green
7. **Documentation** — CHANGELOG, `docs/development/state.md`, any ADR the change earned
8. **Version check** — `make version-check` (VERSION, `cyrius.cyml`, CHANGELOG, README, `chitra_version()` and every `chitra_version() → N` claim in `docs/development/state.md` in sync)
9. **Dist regen** — `make dist`, confirm `dist/chitra.cyr` still compiles clean
10. **Return to step 1**

### Security Hardening (before every release)

An encoded image is untrusted external data. The guards below are
non-negotiable — re-verify each before tagging.

**PNG** (the kii-inherited guards):

1. **Decompression-bomb caps** — two distinct gates: the fused IDAT *input* accumulator is capped at `CHITRA_MAX_RAW_BYTES` → `CHITRA_ERR_OOM` (`png_filter.cyr:483`), and the IHDR-derived inflated/pixel *output* sizes are capped → `CHITRA_ERR_DIMENSIONS` (`png_filter.cyr:617`-`624`)
2. **Lying-IHDR rejection** — declared dimensions cross-checked against actual data → `CHITRA_ERR_DIMENSIONS`
3. **Ratio caps** — output:input expansion bounded by `CHITRA_MAX_INFLATE_RATIO` → `CHITRA_ERR_DIMENSIONS` (`png_filter.cyr:636`)
4. **Chunk-CRC validation** — every chunk's CRC-32 checked → `CHITRA_ERR_CRC`
5. **Bounds on every read** — truncated input → `CHITRA_ERR_TRUNCATED`, never an OOB read
6. **Filter-byte validation** — per-row filter ∈ {0,1,2,3,4} → else `CHITRA_ERR_FILTER`
7. **Spec-legal matrix only** — illegal bit-depth × color-type combos rejected, not guessed
8. **Unknown critical chunks abort** — § 5.4's ancillary bit is honoured: an unrecognised *critical* chunk changes how the image is to be interpreted, so it is rejected → `CHITRA_ERR_UNSUPPORTED`. Unknown *ancillary* chunks stay skippable — do not let this become blanket rejection
9. **Chunk ordering + uniqueness** — PLTE and tRNS are each at-most-once and must precede IDAT (§ 5.6 / § 11.3.2). Track "have we seen IDAT" with an explicit flag, never by testing an accumulated byte count: a spec-legal **zero-length IDAT** leaves the count at 0 and defeats the guard. ⚠ **A second IHDR is `CHITRA_ERR_BAD_CHUNK` (1.1.1)** (`png_filter.cyr:462`) — § 5.6 allows exactly one. Through 1.1.0 it fell to rule 8's unknown-critical branch and reported `CHITRA_ERR_UNSUPPORTED`, "valid but declined", for a file the spec makes invalid; it is checked after the CRC, so a corrupt chunk still reports as one
10. **tRNS keys one exact value** — the § 11.3.2 color key is compared at FULL sample width. Comparing at the truncated 8-bit output width makes every value sharing a high byte transparent
11. **Refuse what the chunk list has already decided BEFORE the first allocation (1.1.1)** — colour type 3 without a (non-empty) PLTE, a palette tRNS longer than PLTE, and a colour-type-0/2 tRNS that is not 2/6 bytes are refused at the end of the chunk walk (`png_filter.cyr:682`-`711`): after the bomb caps, so a bomb keeps `CHITRA_ERR_DIMENSIONS`, and before `alloc(idat_total)`. Through 1.1.0 the colour pass refused them only after the IDAT concatenation, the inflate buffer, the scanlines and the RGBA buffer existed — a 2,116-byte 4096×4096 depth-1 palette PNG with no PLTE spent **71,335,368 B** to return `CHITRA_ERR_BAD_CHUNK`. The early checks mirror the colour pass's conditions exactly, so no accept/reject outcome moved; the colour-pass checks stay as defence in depth for its `@internal` entry
12. **An allocation failure is not a corrupt stream (1.1.1)** — `zlib_decompress` returns `-ERR_OOM` when sankoch's own allocations fail (its lazily built decode tables; the 32-byte bit-reader on every call), and that now maps to `CHITRA_ERR_OOM` (`png_filter.cyr:751`); every other negative return stays `CHITRA_ERR_INFLATE`. Reporting it as `INFLATE` told a caller a valid PNG decoded under memory pressure was damaged, and invited it to cache that verdict. B-1 (1.0.3) restored the same contract for `crc32_init_table`; this is the other half

**JPEG** (baseline; see [docs/audit/2026-06-27-audit.md](docs/audit/2026-06-27-audit.md) and [docs/audit/2026-08-23-audit.md](docs/audit/2026-08-23-audit.md); § A.2 geometry per [ADR 0006](docs/adr/0006-defer-jpeg-multiscan-resumption.md)):

1. **Non-baseline rejection** — progressive / arithmetic / 12-bit / hierarchical-lossless / CMYK rejected at the marker classifier with distinct codes (attack-surface reduction). ⚠ **The code must name the mode, not a symptom of it (1.1.1)**: libjpeg writes DQT *before* SOF, and cjpeg switches to SOF1 exactly when a quant value exceeds 255 (every cjpeg file at quality ≤ 23), so refusing a 16-bit table (`Pq = 1`) on sight reported all of them — and their progressive / arithmetic siblings — as `CHITRA_ERR_JPEG_DQT`. A 16-bit DQT ahead of the frame header is now accepted syntactically, consumed unstored, and judged by the SOF that follows: SOF1 → `JPEG_MODE` (22), SOF2 → `JPEG_PROGRESSIVE` (19), SOF9 → `JPEG_ARITHMETIC` (20); with SOF0 it is still `JPEG_DQT`, and after SOF0 it is refused on sight. `0xC8` (JPG), `0xDE` (DHP), `0xDF` (EXP) and `0xF0`–`0xFD` (JPGn, incl. JPEG-LS) refuse as `JPEG_MODE` instead of being length-skipped — DHP and EXP *are* the hierarchical mode. SOS before any SOF is `JPEG_MARKER` (a misplaced marker), not `JPEG_SOF`
2. **Marker/segment bounds** — every 16-bit segment length validated against the input span
3. **Sampling-factor guards** — `Hi/Vi ∈ 1..4` (reject 0 → div-by-zero), no duplicate component ids, `ΣHj·Vj ≤ 10` per *interleaved scan* (rule 12)
4. **Table bounds** — DQT/DHT precision/id checked; Huffman build rejects over-subscription; DECODE rejects out-of-range symbol indices
5. **Entropy bounds** — DC category ≤ 11, AC size ≤ 10, coefficient index ≤ 63; restart markers resync deterministically. ⚠ **`BR_EOD` is set at the FABRICATION point, not at the marker latch (1.0.3)** — an RSTn the decoder never asked for (no DRI, DRI=0, wrong interval) sits *inside* the entropy span, latches, and every later bit is invented; through 1.0.2 that left `seen_iend` = 1 over a half-fabricated image. A *legitimate* restart also latches and is then consumed with nothing fabricated, so flagging the latch would mis-report every restart-interval JPEG. ⚠ **Two more ways a scan does not close cleanly, neither of them an error (1.1.1)**: a restart marker out of its modulo-8 sequence (an interval lost or repeated — resynced on, but flagged in its own `BR_DAMAGED`, because no bit was fabricated and `BR_EOD` means fabrication and nothing else), and entropy bytes no MCU consumed (anything but a trailing RSTn — libjpeg's "extraneous bytes"). Both return the image with `seen_iend` = 0. And a restart-interval file **truncated** mid-scan now decodes partially with `seen_iend` = 0, exactly like a non-DRI one: the span running out at a restart point is truncation, not corruption. Through 1.1.0 it refused as `CHITRA_ERR_JPEG_ENTROPY`; something other than an RSTn sitting where one is due still does
6. **Plane/dimension caps** — every allocation bounded by `CHITRA_MAX_RAW_BYTES`; upsample indices stay within plane bounds
7. **Amplification cap** — output:input bounded by `CHITRA_MAX_JPEG_RATIO` → `CHITRA_ERR_DIMENSIONS`. JPEG needs this *more* than PNG does: the entropy bit-reader zero-pads past end-of-data, so a hostile file needs **no scan payload at all** — the declared SOF0 geometry alone drives the work, and the bump allocator never reclaims it. Since 1.1.1 every gate that bounds the planes runs before them — see 16
8. **Only length-bearing markers are skipped by length** — standalone markers (SOI, EOI, RSTn, TEM) and the T.81 Table B.1 reserved range are rejected, not treated as segments. Otherwise the walk reads two attacker bytes as a length and the cursor is steered by the input
9. **Fill bytes tolerated, both sides** — § B.1.1.2 allows any number of `0xFF` bytes before a marker. The header walk *and* the entropy reader must both collapse the run, or valid files are rejected
10. **No baseline scan geometry is deferred any more (0.8.0)** — the § A.2 class is complete: interleaved, non-interleaved, partially interleaved (`Ns < Nf`), single- and multi-scan all decode. The `Ns < Nf` gate was deleted, and what replaces it as the bound is the **per-component coverage bitmask** — a component may be decoded exactly once, so a file gets at most `Nf` scans and every scan must name something new (refused in `_jpeg_parse_sos`, `src/jpeg.cyr:180`, set at `:186`; the driver `_jpeg_decode_scans` at `:963` reads the mask at `:1055`). ⚠ **Within one scan the components must appear in frame order (1.1.1)** — T.81 § B.2.3, which libjpeg enforces ("Invalid component ID 1 in SOS") and cjpeg will not write; chitra accepted all five permutations of a 4:4:4 scan (`_jpeg_parse_sos`, `src/jpeg.cyr:170`). Strictly increasing also means distinct, so it replaced the duplicate-`Cs` loop. The order of *scans* is still free: `cjpeg -scans` writes Cb's scan before Y's on request, and that decodes. `CHITRA_ERR_UNSUPPORTED` no longer covers any scan geometry; on the JPEG path it now means only an Adobe APP14 transform above 1 on a 3-component non-JFIF frame (rule 13; the non-baseline modes carry codes 19..23). See [ADR 0006](docs/adr/0006-defer-jpeg-multiscan-resumption.md), amended
11. **ONE § A.2 rule covers both layouts (0.8.0)** — a scan is non-interleaved when **`Ns == 1`**, whatever `Nf` is. `_jpeg_decode_one_scan` then walks a scan grid `s_cols × s_rows = ceil(x_i/8) × ceil(y_i/8)` over that component's own § A.1.1 sample dimensions, one data unit per MCU, leaving `max_h`/`max_v` **alone**. 0.6.0's *effective-geometry collapse* (forcing `H = V = max_h = max_v = 1`) was **deleted, not extended**: it was valid only because with `Nf = 1` the lone component IS the maximum, and a one-component *scan* of a three-component *frame* has a maximum that is not itself. `Nf = 1` now falls out of the same general formula. Keep ONE grid variable; a second (`grid_w` for the count while `mcu_cols` sizes the plane) lets placement diverge from count
12. **ΣHj·Vj ≤ 10 is § B.2.3 and applies only when Ns > 1** — it bounds an INTERLEAVED MCU, and a one-component scan has none. Conditioned, not removed — and as of 0.8.0 it lives at the **scan** header (`_jpeg_parse_sos`, `src/jpeg.cyr:213`), summed over the *scan's* components, not the frame's. That is still ahead of every allocation, because planes are allocated per scan by `_jpeg_decode_one_scan` after the scan header parses. Applying it frame-wide rejected files libjpeg writes: `cjpeg -sample 4x4,1x1,1x1 -scans` is legal, sums to 18, and decodes
13. **A JFIF APP0 outranks everything below it (1.0.3)** — JFIF § 4.1 *defines* three components as Y/Cb/Cr, so a file that declares itself JFIF has already answered the colour question and neither the Adobe transform nor the component ids may overturn it. The order is **JFIF → APP14 transform → component ids → YCbCr**, which is libjpeg's (`default_decompress_parms` tests `saw_JFIF_marker` first). Through 1.0.2 chitra never parsed APP0 at all, so rule 14's `'R','G','B'` ids also applied to JFIF files: six edited bytes produced a whole-image colour error with no error code while `source_color_type` returned 0x113 and told the consumer the samples were RGB. ⚠ `cjpeg -rgb` emits **no** JFIF APP0, so rule 14 still fires for real RGB files — pinned by its own cell so this cannot silently revert 0.6.1. ⛔ **What counts as JFIF, and when the question is settled (1.1.1)**: an APP0 is JFIF only with a payload of **≥ 14 bytes** (libjpeg's `APP0_DATA_LEN`) — through 1.1.0 the bare 5-byte `"JFIF\0"` counted, so nine spliced bytes outranked an Adobe `transform=0` and pushed a `cjpeg -rgb` file's RGB samples through BT.601 (1,149 of 1,536 colour bytes wrong, no error). APP0 and APP14 **after the first SOS are skipped**, so the colour space is fixed by the evidence in front of the first SOS, as libjpeg fixes it; through 1.1.0 a segment spliced between scans re-decided the colour of samples earlier scans had already produced. The APP14 transform is judged once, at the first SOS, and refuses (`CHITRA_ERR_UNSUPPORTED`) only where it decides something — a 3-component frame with no JFIF; a grey or JFIF frame ignores it, and a 4-component YCCK frame now reports `CHITRA_ERR_JPEG_COMPONENTS` (23) from SOF0 rather than 4 from the segment
14. **A 3-component JPEG is not necessarily YCbCr (0.6.1)** — `cjpeg -rgb` writes RGB components with an Adobe APP14 `transform=0` and ids `'R','G','B'`. Applying BT.601 to them hue-rotates the image with NO error: 1,149 of 1,536 bytes wrong, a blue pixel returned dark red. Order of authority (below a JFIF APP0, rule 13): the APP14 transform, else the component ids, else YCbCr. An undefined transform is DECLINED where it decides the colour space — assuming YCbCr for it is the same guess in a smaller form
15. **Allocation timing is part of the attack surface (0.6.1)** — `chitra_jpeg_scan_markers` allocated 22,160 bytes BEFORE any check could refuse the file, on every call, unmemoized. Tables are now allocated when a DQT/DHT first defines something, guarded `== 0` — per FRAME, never per DEFINITION: a single DHT may carry 3,854 definitions, so per-definition allocation trades a flat cost for one that SCALES with file size. ⚠ **"First defines something" became true only in 1.1.1** — the allocation sat at segment ENTRY, ahead of every table header, so an empty (`Lq`/`Lh` = 2) or malformed segment still paid the whole store: the 12-byte `FF D8 FF DB 00 02 FF C4 00 02 FF D9` spent all 22,160 bytes. It now happens immediately before the first store, once that table's header has validated (DQT: `Pq`, `Tq` and the 64-byte body; DHT: `Tc`, `Th`, the BITS sum and the symbol span), so an empty DQT/DHT costs nothing. Still at most once per frame
16. **An amplification denominator must exclude bytes the decoder never decodes (0.6.1)** — `CHITRA_MAX_JPEG_RATIO` divided by whole-file length, so 16,404 bytes of skipped APPn padding bought a 4096×4096 decode and 117 MB. The denominator is now a real entropy-span walk. This is the 0.5.3 BMP-RLE lesson: ask what the attacker actually SPENT. ⛔ **And the honest denominator has to be known before the planes (1.1.1)** — GATE 2 (the RGBA output against the *summed* entropy spans) ran only after every scan had decoded, on the premise that the sum "can only" be known then; GATE 0 (B-3, 1.0.3 — against `len`) was all that stood in front of the planes, and `len` counts padding: 4,200 bytes of APP1 bought a 16,658-byte three-scan file B-3's exact **50,354,832 B** back. The sum is byte-structural, so `_jpeg_structural_espan` — an allocation-free pre-pass that reads only `Ls`/`Ns`/`Cs` and skips everything else by length — computes it first and GATE 2 refuses ahead of the planes (`src/jpeg.cyr:1010`-`1016`). It is never stricter than the decode: where it stops short of full coverage the decode refuses at that point or earlier, and with no readable scan header it does not gate at all. The post-decode GATE 2 stays as the exact backstop (an equivalent mutant while the two walks agree, kept as the bound of record); GATE 1 still bounds each scan's planes against that scan's own span; GATE 0 still runs and only decides the code for a frame none of whose scan headers can be read
17. **The exact-fit property depends on the BOX upsampler** — box reads exactly `(y·Vi/max_v)*comppw + (x·Hi/max_h)`. A fancy/triangle upsampler reads `x+1` and would make an edge margin live again, reopening a read-of-uninitialized class

**BMP** (0.4.0 `BI_RGB`; + RLE 0.5.1; + BITFIELDS/16 bpp/V4-V5 0.5.2; audited 0.5.3 — see [docs/audit/2026-08-24-audit.md](docs/audit/2026-08-24-audit.md)):

1. **Header fields validated before use** — every field is checked before it derives another, and every derived size is capped before allocation: dimensions vs `CHITRA_MAX_DIM` / `CHITRA_MAX_PIXELS`, `stride * height` vs `CHITRA_MAX_RAW_BYTES`
2. **The pixel-data offset is attacker-controlled** — it is a header field, not "after the palette", and it can point anywhere. The whole `data_off + stride*height` span is validated against `len` → `CHITRA_ERR_TRUNCATED`. ⚠ **`bfOffBits = 0` means "by layout", and the layout includes the optional colour table (1.1.1)** — a 16/24/32-bpp file with a non-zero `biClrUsed` declares a table between the headers and the bits; with no palette at those depths, the inferred start landed ON it and decoded its entries as pixels with no error. It is skipped, not refused
3. **Palette span + index bounds** — the palette span is validated against `len`, and every index is hard-rejected against the declared entry count → `CHITRA_ERR_BMP_PALETTE`. Never clamp an index; reject it
4. **The deferral list is empty as of 0.5.2** — RLE8/RLE4 (0.5.1), BITFIELDS/16 bpp/V4/V5 (0.5.2). `BI_JPEG` / `BI_PNG` are refused **permanently**: honouring them re-enters the decoder, which is a recursion surface, not a feature. Accepted DIB header sizes are an **allow-list** (12/40/52/56/**64**/108/124), not a lower bound — 64 is the OS/2 2.x `BITMAPCOREHEADER2` (0.7.2), whose +40 onward is units/recording/rendering, so its mask fields must NOT be read. ⚠ **Nor do its compression numbers mean what Windows' do from 3 up (1.1.1)** — 3 is Huffman 1D and 4 is RLE24 there, not `BI_BITFIELDS` / `BI_JPEG`, so any compression ≥ 3 on a 64-byte header → `CHITRA_ERR_BMP_COMPRESSION`. Mapping 3 to bitfields decoded a 32-bpp file by masks read from a header that has none
5. **No checksum exists** — BMP has nothing like PNG's per-chunk CRC, so every byte of a BMP reaching the parser is attacker-chosen with nothing to turn it away but chitra's own bounds. Treat the header parser as the entire perimeter
6. **An RLE row is `w` pixels of image inside a DWORD-ALIGNED row (1.0.3)** — real encoders fill the padding, so a 9-pixel RLE8 row arrives as nine 1-pixel runs plus a 3-pixel run. Bounding writes at `x >= w` refused **30 of 30** files from `magick -compress RLE`, every one of which ffmpeg and ImageMagick read fine. Samples in `[w, row_cap)` are consumed and **discarded**; past `row_cap` is still refused. ⚠ The padding is not image data, so discarding it is not clipping — and the tree's own "ImageMagick-encoded RLE8" fixture was 8×4, a width where the padding does not exist, which is why nothing caught it
7. **RLE (0.5.1)** — termination is structural (every opcode consumes ≥ 2 bytes; the cursor only advances). Bounds-check every write **individually**, not per-run: reject a run past the row end, never clip it, or you decode a different image than the file encodes. Check **delta at the jump** against both dimensions — a delta past the end followed by no writes is still malformed. Top-down + RLE is rejected (the end-of-line escape counts rows from the bottom), and RLE8/RLE4 must match 8/4 bpp
8. **Channel masks are attacker input (0.5.2)** — validate every one: contiguous (a split mask names no real channel), non-overlapping (two channels claiming a bit is a contradiction), inside the pixel word (a 24-bit mask on 16 bpp reads bits that are not there), and at least one color channel present. An unvalidated width feeds a shift, and an unvalidated shift reads outside the pixel
9. **Widening a sub-8-bit channel is BIT REPLICATION**, not `v * 255 / max` — shift left and refill the low bits from the field's own high bits. The arithmetic forms disagree with every reference decoder (a 6-bit 48 is 195, not 194), and the error is a whole-image color shift rather than an edge case. ⚠ **A channel WIDER than 8 bits is a different rule (1.1.1)** — replication degenerated there to `v >> (w-8)`, truncation. chitra now uses ImageMagick's mapping (ffmpeg refuses these layouts): place the field at the top of a 16-bit sample, `x16 = v << (16-w)` (or `v >> (w-16)` above 16 bits), then `round(x16 / 257)`. For a 16-bit field that is exactly § 13.13; for 9..15 bits it is not, and the § 13.13 rescale disagrees with ImageMagick in both directions (measured over every value of 9/10/11/12/16/24-bit fields). Bit replication still governs every sub-8-bit field
10. **A validated mask must then be USED (0.5.3)** — validating the masks and then decoding by a fixed BGRA layout is the worst of both: the file is checked against a contract the decoder does not honour. And **whether the file declares alpha is a separate question from whether it declares a channel order** — gating the mask path on `mask_a != 0` swapped red and blue on real files
11. **Masks are `BI_BITFIELDS`-only (0.5.3)** — MS: the V4/V5 mask fields are *"valid only if compression is `BI_BITFIELDS`"*, and real writers populate them under `BI_RGB` anyway. Reading them there decoded a V4 file **fully transparent**. Equally, do not inject `BI_RGB` defaults into a bitfields file: it invents a layout the file never declared, and it made the "at least one colour channel" guard **unreachable dead code**
12. **RLE amplification cap (0.5.3)** — `CHITRA_MAX_BMP_RLE_RATIO` bounds output against bytes **CONSUMED**, not file size → `CHITRA_ERR_DIMENSIONS`. Measuring the file lets an attacker raise their own allowance by appending padding, which is exactly what defeated the first version

**GIF** (0.5.0; first frame only — [ADR 0005](docs/adr/0005-gif-first-frame-only.md); audited 0.5.3):

1. **LZW is chitra's own decompressor** — `sankoch` has no LZW to delegate to, unlike PNG's DEFLATE. Treat it as the newest attack surface in the tree
2. **Expansion capped at the frame's pixel count** — LZW is a compressor; a few hundred bytes expand without limit unless bounded → `CHITRA_ERR_GIF_LZW`. ⚠ **A full frame followed only by the last byte's padding is the END, not one pixel too many (1.1.1)** — with fewer than 8 bits left after the frame is full, the decoder stops, as ImageMagick and ffmpeg do. Through 1.1.0 that padding read as root code 0 whenever it was at least one code wide, and an End-less file was refused as a bomb or decoded depending on bit alignment (34 of 150 such files refused). A whole byte or more past a full frame is still refused
3. **Prefix chains cannot cycle** — entries are only added with `prefix < the index being written`, so chains strictly decrease. The walk is *additionally* bounded by the dictionary size: a guard you can reason about is worth less than one you cannot get past
4. **Codes above `next_code` are rejected**; the one legal exception (`code == next_code`, KwKwK) is handled explicitly. The bit reader never zero-pads — padded bits would fabricate dictionary entries. Running out of codes is tolerated as a clean end: the unwritten tail of the frame is zero-filled and `seen_iend` reports 0. A sub-block chain that runs off the input rejects with `CHITRA_ERR_TRUNCATED`
5. **Sub-block chains** — every length byte bounds-checked, gathered payload capped at the input length, so a chain cannot make chitra hold more than the file
6. **Frame rect must lie inside the logical screen** — reject, never clamp; clamping decodes a different image than the file describes
7. **Palette indices hard-rejected** against the table in force (local wins over global) — over the whole decoded index plane, **before the canvas is allocated (1.1.1)**. In the paint loops, which run after the logical-screen canvas exists, a 35-byte file naming a 4096×4096 screen and one bad index spent 67,109,120 bytes to be refused
8. **Amplification cap (0.5.3)** — `CHITRA_MAX_GIF_RATIO` bounds output against the compressed stream, checked **before** the allocation it exists to prevent → `CHITRA_ERR_DIMENSIONS`. It is deliberately looser than PNG's 1100:1: LZW's legitimate compression of degenerate content is close to the bomb ratio, so the cap bounds the extreme case, not the merely aggressive one. ⚠ **Its units are FRAME PIXELS per gathered LZW byte, not RGBA bytes (corrected 1.1.1)**: a frame is admitted iff `fw * fh <= comp_len * 16384`, `comp_len` being the LZW payload bytes the sub-block walk gathered. That is a **1,024-byte** floor for a 4096×4096 frame, ~11× headroom over ImageMagick's own solid 4096² GIF (11,513 LZW bytes). Through 1.1.0 the docs did this arithmetic in RGBA bytes and said 4 KB / ~3×; the cap itself did not change
9. **Fixed-size blocks need their size checked (0.5.3)** — a GCE's block size is fixed at 4 and every field after it is addressed by a fixed offset. Validate it, or a GCE declaring another size has chitra read the packed byte and transparent index from bytes that are not those fields → `CHITRA_ERR_GIF_HEADER`
10. **A GCE governs the graphic that FOLLOWS it (0.5.3)** — including one that turns transparency **off**. State from a previous GCE must be cleared, not merely overwritten when present. Cyrius `var`s are function-scoped, so "the last value that happened to be stored" is the default failure mode in a long block walk

File findings in `docs/audit/YYYY-MM-DD-audit.md`. Severity: CRITICAL / HIGH / MEDIUM / LOW.

### Closeout Pass (before every minor/major bump)

1. Full test suite — every `.tcyr` passes, zero failures (`make test`)
2. Fuzz clean — `make fuzz` green: every `fuzz/*.fcyr` under `--poison` (allocator redzones, exit 86 on an overwrite — a small overflow into the next bump allocation does not crash, so a plain run cannot see it), and exactly the step CI runs. Every harness asserts survival **and** the documented `(0, *err_out set)` contract
3. Reference re-verify — the full decode matrix against ImageMagick. Not a formality: it is the only check that sees a **silent mis-decode**, and the 0.5.3 audit found seven
4. Dead-code / cleanup sweep — stale comments, unused includes, orphaned files
5. Code-anchor sweep — `./scripts/check-anchors.sh --suspect`. The docs cite code by line number, and those move whenever a guard is added above them; this rot has needed hand-repair repeatedly. The script prints every citation (bare `` `:N` `` continuations included) with the line it now points at and flags four kinds: **PAST-EOF**; **SUSPECT** (a blank line or a lone brace); **COMMENT** (a comment-only line, unless the comment names the identifier the citation names — a drifted anchor most often lands in a doc block that grew); and **IDENT** (the citation names a backticked identifier next to its anchor, and that identifier is neither within ±3 lines nor the function the line sits in). It **exits 1 when anything is flagged**. It still does not gate CI — it cannot know what a line was meant to say — but the closeout does not finish with a non-zero count. Dated `docs/audit/` reports and `CHANGELOG.md` are excluded: their anchors are a historical record, never edited, not a live claim
6. Code-review pass — missed guards, off-by-ones, silently-ignored errors, ABI leaks
7. Security re-scan — the hardening checklist above
8. Downstream check — mabda still builds and `gpu_texture_load_png` works against the new `dist/chitra.cyr`; bump the `[deps.chitra]` pins in mabda and kii *after* the tag lands
9. Benchmark record — `make bench-record`, so `bench-history.csv` has a row per release. Benchmarks are a performance signal, not a correctness gate; they are not *run* by `test-all` because the numbers are host-dependent — but `test-all` and CI both *compile* the harness (`make bench-build`, 1.1.1), since nothing else does and `lint` passes a file it cannot compile
10. Doc sync — CHANGELOG, roadmap, `docs/development/state.md`, CLAUDE.md (if durable content changed)
11. Version verify — `make version-check` (it also fails on any `chitra_version() → N` claim in `state.md` that is not the current packed version); intended git tag matches
12. Clean dist regen — `cyrius distlib` produces a compile-clean bundle

### Task Sizing

- **Low/Medium effort**: batch freely.
- **Large effort** (a new format like JPEG): small bites — Huffman, then IDCT, then chroma upsample, verifying each.
- **If unsure**: treat it as large.

## CI / Release

- **Toolchain pin**: `cyrius = "X.Y.Z"` in `cyrius.cyml [package]`. CI and release both read it; no hardcoded version strings in YAML.
- **Workflows**: `.github/workflows/ci.yml` (locked deps + lint + fmt + vet + dist-sync + `check-surface.sh` + build + `make bench-build` + test + `make fuzz` + version-check) and `.github/workflows/release.yml` (version gate → CI gate → dist + artifacts).
- **Lock gate (1.1.1)**: CI requires `cyrius.lock` to be committed, runs `cyrius deps --locked` (resolves the tags against the COMMITTED lock and writes nothing), then resolves `lib/` and fails if that rewrote `cyrius.lock` — commit the lock the tags resolve to. A plain `cyrius deps` rewrites the lock to whatever it resolves, so before this a stale hash, a re-pointed sankoch tag or a deleted lock all went green.
- **Tag filter**: release triggers on semver-only tags. Non-numeric tags do not ship.
- **Version-verify gate**: release asserts `VERSION == cyrius.cyml version == git tag` before building.
- **State sync**: bump `docs/development/state.md` at release. If a release hook can do it, fix the hook rather than hand-maintaining state.

## Docs

- [`docs/adr/`](docs/adr/) — architecture decision records. *Why X over Y?* (e.g. "fork kii's png.cyr vs. shared dep")
- [`docs/architecture/`](docs/architecture/) — non-obvious constraints. *What can't I derive from the code alone?* (e.g. the `lib/`-must-not-be-a-symlink quirk, the flat-domain-module + distlib invariant)
- [`docs/guides/`](docs/guides/) — task-oriented how-tos (e.g. "consuming chitra from mabda")
- [`docs/development/roadmap.md`](docs/development/roadmap.md) — **forward-only**: 1.1.x maintenance, 1.2.0 and the unscheduled 1.x candidates, what would need a major, lessons carried forward, and the durable out-of-scope guards. Shipped work is the CHANGELOG's, not the roadmap's
- [`docs/development/state.md`](docs/development/state.md) — live state snapshot, refreshed every release
- [`docs/development/public-surface.md`](docs/development/public-surface.md) — the frozen 29-name surface + both record layouts, and what the promise deliberately excludes; gated by `scripts/check-surface.sh` on every `make lint`
- [`docs/sources.md`](docs/sources.md) — the specs each guard cites, section by section
- [`docs/examples/`](docs/examples/) — runnable consumer sketches
- [`docs/audit/`](docs/audit/) — security audit reports (`YYYY-MM-DD-audit.md`)
- [`docs/proposals/`](docs/proposals/) — design notes written *before* a large feature lands (e.g. the baseline-JPEG plan)
- `fuzz/*.fcyr` (`make fuzz`) and `tests/bcyr/chitra.bcyr` (`make bench`) — the two hardening harnesses; both **generate** their inputs, and both self-verify before asserting anything
- [`CHANGELOG.md`](CHANGELOG.md) — source of truth for all changes (Keep a Changelog; perf claims carry numbers; breaking changes get a Breaking section)

New quirks land in `docs/architecture/` as numbered items (`NNN-kebab-case.md`).
New decisions land in `docs/adr/` (`NNNN-kebab-case.md`). **Never renumber either series.**
