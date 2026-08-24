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
- **Version**: `VERSION` at the project root is the source of truth — do not inline the number here. SemVer (pre-1.0: surface still moving).
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
- **Validate against a real reference** — every decode-matrix claim is checked against ImageMagick output, plus an interlaced-vs-non-interlaced cross-check. Numbers/images or it didn't happen.
- **Spec-cite the hard cells** — bit-depth × color-type legality follows PNG § 11.2.2 Table 11.1; the five unfilter predictors follow § 9. Cite the section in the code.
- Every buffer declaration is a contract: `var buf[N]` = N **bytes**, not N entries.
- **Trust no input byte** — an encoded image (PNG, JPEG, BMP or GIF) is untrusted external data. Bounds-check every length, reject lying headers, cap decompression bombs, bound every entropy/Huffman loop.

## Rules (Hard Constraints)

- **Read the genesis repo's CLAUDE.md first** — [agnosticos/CLAUDE.md](https://github.com/MacCracken/agnosticos/blob/main/CLAUDE.md)
- **Do not commit or push** — the user handles all git operations
- **NEVER use `gh` CLI** — use `curl` to the GitHub API if needed
- **`lib/` must be a real directory populated by `cyrius deps`** — never a symlink to a cyrius checkout (an agent editing `lib/*.cyr` would corrupt the toolchain repo). `make` targets guard this via `check-lib-wiring`; if it trips: `rm lib && mkdir lib && cyrius deps`.
- **Stdlib includes live ONLY in `src/lib.cyr`** — domain modules (`src/*.cyr`) are flat (no stdlib includes). This is what lets `cyrius distlib` strip-concatenate into a compile-clean `dist/chitra.cyr`. Adding a stdlib include to a domain module breaks the dist bundle.
- **`[lib].modules` order in `cyrius.cyml` is dependency order** — `error.cyr` (dep-free) → `png_chunks.cyr` → `png_filter.cyr` → `png_color.cyr` → `png.cyr` → `jpeg_huffman.cyr` → `jpeg_idct.cyr` → `jpeg_markers.cyr` → `jpeg.cyr` → `bmp.cyr` → `gif_lzw.cyr` → `gif.cyr` (the frame-independent JPEG leaves precede the frame-builder — see [architecture/004](docs/architecture/004-jpeg-decode-pipeline.md); `bmp.cyr` needs only `ChitraImage`, the ceilings and the error codes; `gif_lzw.cyr` is likewise a frame-independent leaf and must precede `gif.cyr`, which drives it). Don't reorder without re-running `cyrius distlib` and verifying the bundle still compiles.
- **`ChitraErr` stays a 16-byte record** (`+0` code, `+8` detail ptr) — layout-compatible with mabda's `GpuErr` so a decode failure maps cleanly onto `GPU_ERR_IMAGE_DECODE`. Don't widen it.
- **`ChitraImage` field additions are append-only** — `width`/`height`/`pixels`/`channels` keep their 0.1.x offsets (mabda's accessors depend on them). New fields go at the end (`seen_iend` @ +32, `src_ctype` @ +40), and any widen bumps `CHITRA_IMAGE_SIZE`.
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
- `chitra_image_decode(src, len, err_out)` → the **format-sniffing router** (PNG magic, then JPEG SOI, then BMP `BM`, then GIF `GIF8?a`, else `CHITRA_ERR_SIGNATURE`); the entry to reach for when the format isn't known up front
- `chitra_png_check_signature` / `chitra_jpeg_check_signature` / `chitra_bmp_check_signature` / `chitra_gif_check_signature` — signature predicates
- `chitra_image_{width,height,pixels,channels,seen_iend,source_color_type}` accessors (`source_color_type`: PNG color_type 0/2/3/4/6; `0x100 | ncomp` for JPEG — 0x101 grayscale, 0x103 YCbCr; `0x200 | bpp` for BMP — 0x208 palette-8, 0x218 24bpp, 0x220 32bpp; `0x300 | min_code_size` for GIF)
- `chitra_image_free` (no-op under the bump allocator; kept for symmetry)
- `chitra_version()` (packed `major*10000 + minor*100 + patch`)
- error API: `chitra_err_new` / `chitra_err` / `chitra_err_code` / `chitra_err_detail` / `chitra_err_name` / `chitra_err_print_name` + the `ChitraErrCode` enum

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

1. **Decompression-bomb caps** — two distinct gates: the fused IDAT *input* accumulator is capped at `CHITRA_MAX_RAW_BYTES` → `CHITRA_ERR_OOM` (`png_filter.cyr:438`), and the IHDR-derived inflated/pixel *output* sizes are capped → `CHITRA_ERR_DIMENSIONS` (`png_filter.cyr:500`-`507`)
2. **Lying-IHDR rejection** — declared dimensions cross-checked against actual data → `CHITRA_ERR_DIMENSIONS`
3. **Ratio caps** — output:input expansion bounded by `CHITRA_MAX_INFLATE_RATIO` → `CHITRA_ERR_DIMENSIONS` (`png_filter.cyr:519`)
4. **Chunk-CRC validation** — every chunk's CRC-32 checked → `CHITRA_ERR_CRC`
5. **Bounds on every read** — truncated input → `CHITRA_ERR_TRUNCATED`, never an OOB read
6. **Filter-byte validation** — per-row filter ∈ {0,1,2,3,4} → else `CHITRA_ERR_FILTER`
7. **Spec-legal matrix only** — illegal bit-depth × color-type combos rejected, not guessed
8. **Unknown critical chunks abort** — § 5.4's ancillary bit is honoured: an unrecognised *critical* chunk changes how the image is to be interpreted, so it is rejected → `CHITRA_ERR_UNSUPPORTED`. Unknown *ancillary* chunks stay skippable — do not let this become blanket rejection
9. **Chunk ordering + uniqueness** — PLTE and tRNS are each at-most-once and must precede IDAT (§ 5.6 / § 11.3.2). Track "have we seen IDAT" with an explicit flag, never by testing an accumulated byte count: a spec-legal **zero-length IDAT** leaves the count at 0 and defeats the guard
10. **tRNS keys one exact value** — the § 11.3.2 color key is compared at FULL sample width. Comparing at the truncated 8-bit output width makes every value sharing a high byte transparent

**JPEG** (baseline; see [docs/audit/2026-06-27-audit.md](docs/audit/2026-06-27-audit.md) and [docs/audit/2026-08-23-audit.md](docs/audit/2026-08-23-audit.md)):

1. **Non-baseline rejection** — progressive / arithmetic / 12-bit / hierarchical-lossless / CMYK rejected at the marker classifier with distinct codes (attack-surface reduction)
2. **Marker/segment bounds** — every 16-bit segment length validated against the input span
3. **Sampling-factor guards** — `Hi/Vi ∈ 1..4` (reject 0 → div-by-zero), no duplicate component ids, `ΣHi·Vi ≤ 10`
4. **Table bounds** — DQT/DHT precision/id checked; Huffman build rejects over-subscription; DECODE rejects out-of-range symbol indices
5. **Entropy bounds** — DC category ≤ 11, AC size ≤ 10, coefficient index ≤ 63; restart markers resync deterministically
6. **Plane/dimension caps** — every allocation bounded by `CHITRA_MAX_RAW_BYTES`; upsample indices stay within plane bounds
7. **Amplification cap** — output:input bounded by `CHITRA_MAX_JPEG_RATIO` → `CHITRA_ERR_DIMENSIONS`. JPEG needs this *more* than PNG does: the entropy bit-reader zero-pads past end-of-data, so a hostile file needs **no scan payload at all** — the declared SOF0 geometry alone drives the work, and the bump allocator never reclaims it
8. **Only length-bearing markers are skipped by length** — standalone markers (SOI, EOI, RSTn, TEM) and the T.81 Table B.1 reserved range are rejected, not treated as segments. Otherwise the walk reads two attacker bytes as a length and the cursor is steered by the input
9. **Fill bytes tolerated, both sides** — § B.1.1.2 allows any number of `0xFF` bytes before a marker. The header walk *and* the entropy reader must both collapse the run, or valid files are rejected
10. **Geometry chitra does not implement is rejected, not approximated** — a single-component scan is non-interleaved per § A.2; since only the interleaved layout is implemented, `H > 1 || V > 1` on a lone component rejects. Mis-rendering a spec-legal file is worse than refusing it

**BMP** (0.4.0; `BI_RGB` uncompressed only):

1. **Header fields validated before use** — every field is checked before it derives another, and every derived size is capped before allocation: dimensions vs `CHITRA_MAX_DIM` / `CHITRA_MAX_PIXELS`, `stride * height` vs `CHITRA_MAX_RAW_BYTES`
2. **The pixel-data offset is attacker-controlled** — it is a header field, not "after the palette", and it can point anywhere. The whole `data_off + stride*height` span is validated against `len` → `CHITRA_ERR_TRUNCATED`
3. **Palette span + index bounds** — the palette span is validated against `len`, and every index is hard-rejected against the declared entry count → `CHITRA_ERR_BMP_PALETTE`. Never clamp an index; reject it
4. **Deferred modes reject with distinct codes** — RLE4/RLE8, BITFIELDS, 16 bpp, V4/V5 headers. `BI_JPEG` / `BI_PNG` are refused outright: honouring them re-enters the decoder, which is a recursion surface, not a feature
5. **No checksum exists** — BMP has nothing like PNG's per-chunk CRC, so every byte of a BMP reaching the parser is attacker-chosen with nothing to turn it away but chitra's own bounds. Treat the header parser as the entire perimeter

**GIF** (0.5.0; first frame only — [ADR 0005](docs/adr/0005-gif-first-frame-only.md)):

1. **LZW is chitra's own decompressor** — `sankoch` has no LZW to delegate to, unlike PNG's DEFLATE. Treat it as the newest attack surface in the tree
2. **Expansion capped at the frame's pixel count** — LZW is a compressor; a few hundred bytes expand without limit unless bounded → `CHITRA_ERR_GIF_LZW`
3. **Prefix chains cannot cycle** — entries are only added with `prefix < the index being written`, so chains strictly decrease. The walk is *additionally* bounded by the dictionary size: a guard you can reason about is worth less than one you cannot get past
4. **Codes above `next_code` are rejected**; the one legal exception (`code == next_code`, KwKwK) is handled explicitly. A truncated LZW stream rejects rather than zero-padding — padding would fabricate dictionary entries
5. **Sub-block chains** — every length byte bounds-checked, gathered payload capped at the input length, so a chain cannot make chitra hold more than the file
6. **Frame rect must lie inside the logical screen** — reject, never clamp; clamping decodes a different image than the file describes
7. **Palette indices hard-rejected** against the table in force (local wins over global)

File findings in `docs/audit/YYYY-MM-DD-audit.md`. Severity: CRITICAL / HIGH / MEDIUM / LOW.

### Closeout Pass (before every minor/major bump)

1. Full test suite — every `.tcyr` passes, zero failures (`make test`)
2. Fuzz clean — `make fuzz` green; both harnesses assert survival **and** the documented `(0, *err_out set)` contract
3. Reference re-verify — the full decode matrix against ImageMagick
3. Dead-code / cleanup sweep — stale comments, unused includes, orphaned files
4. Code-review pass — missed guards, off-by-ones, silently-ignored errors, ABI leaks
5. Security re-scan — the hardening checklist above
6. Downstream check — mabda still builds and `gpu_texture_load_png` works against the new `dist/chitra.cyr`; bump the `[deps.chitra]` pins in mabda and kii *after* the tag lands
7. Benchmark record — `make bench-record`, so `bench-history.csv` has a row per release. Benchmarks are a performance signal, not a correctness gate; they stay out of `test-all` because the numbers are host-dependent
8. Doc sync — CHANGELOG, roadmap, `docs/development/state.md`, CLAUDE.md (if durable content changed)
9. Version verify — `make version-check`; intended git tag matches
10. Clean dist regen — `cyrius distlib` produces a compile-clean bundle

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
- [`docs/development/roadmap.md`](docs/development/roadmap.md) — completed (PNG, baseline JPEG), backlog (GIF, BMP), v1.0 criteria
- [`docs/development/state.md`](docs/development/state.md) — live state snapshot, refreshed every release
- [`docs/audit/`](docs/audit/) — security audit reports (`YYYY-MM-DD-audit.md`)
- [`docs/proposals/`](docs/proposals/) — design notes written *before* a large feature lands (e.g. the baseline-JPEG plan)
- `fuzz/*.fcyr` (`make fuzz`) and `tests/bcyr/chitra.bcyr` (`make bench`) — the two hardening harnesses; both **generate** their inputs, and both self-verify before asserting anything
- [`CHANGELOG.md`](CHANGELOG.md) — source of truth for all changes (Keep a Changelog; perf claims carry numbers; breaking changes get a Breaking section)

New quirks land in `docs/architecture/` as numbered items (`NNN-kebab-case.md`).
New decisions land in `docs/adr/` (`NNNN-kebab-case.md`). **Never renumber either series.**
