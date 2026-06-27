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
no external binaries. The name is format-agnostic so JPEG / GIF / BMP can join
without a rename.

- **Type**: Shared library (no CLI binary — consumers link `dist/chitra.cyr`)
- **License**: GPL-3.0-only
- **Language**: Cyrius (toolchain pinned in `cyrius.cyml [package].cyrius`, currently `6.2.44`)
- **Version**: `VERSION` at the project root is the source of truth — do not inline the number here. SemVer (pre-1.0: surface still moving).
- **Genesis repo**: [agnosticos](https://github.com/MacCracken/agnosticos)
- **Standards**: [First-Party Standards](https://github.com/MacCracken/agnosticos/blob/main/docs/development/first-party/first-party-standards.md) · [First-Party Documentation](https://github.com/MacCracken/agnosticos/blob/main/docs/development/first-party/first-party-documentation.md)

## Goal

Own **CPU-side raster image decode** for AGNOS. Turn encoded image bytes into
canonical RGBA8 with zero GPU dependency and no C shim — the pure-Cyrius answer
to "load this PNG into a texture." PNG is feature-complete; JPEG and other
formats land later without breaking the byte-buffer → RGBA8 contract.

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
make dist                                            # regenerate dist/chitra.cyr via `cyrius distlib`
make lint fmt-check vet                              # quality gates
make version-check                                   # VERSION / cyrius.cyml / CHANGELOG / README agree
make test-all                                        # version-check + dist regen + full test suite
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
- **Trust no input byte** — a PNG is untrusted external data. Bounds-check every chunk length, reject lying IHDR, cap decompression bombs.

## Rules (Hard Constraints)

- **Read the genesis repo's CLAUDE.md first** — [agnosticos/CLAUDE.md](https://github.com/MacCracken/agnosticos/blob/main/CLAUDE.md)
- **Do not commit or push** — the user handles all git operations
- **NEVER use `gh` CLI** — use `curl` to the GitHub API if needed
- **`lib/` must be a real directory populated by `cyrius deps`** — never a symlink to a cyrius checkout (an agent editing `lib/*.cyr` would corrupt the toolchain repo). `make` targets guard this via `check-lib-wiring`; if it trips: `rm lib && mkdir lib && cyrius deps`.
- **Stdlib includes live ONLY in `src/lib.cyr`** — domain modules (`src/*.cyr`) are flat (no stdlib includes). This is what lets `cyrius distlib` strip-concatenate into a compile-clean `dist/chitra.cyr`. Adding a stdlib include to a domain module breaks the dist bundle.
- **`[lib].modules` order in `cyrius.cyml` is dependency order** — `error.cyr` (dep-free) → `png_chunks.cyr` → `png_filter.cyr` → `png_color.cyr` → `png.cyr`. Don't reorder without re-running `cyrius distlib` and verifying the bundle still compiles.
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
- `chitra_image_{width,height,pixels,channels,seen_iend,source_color_type}` accessors
- `chitra_image_free` (no-op under the bump allocator; kept for symmetry)
- `chitra_version()` (packed `major*10000 + minor*100 + patch`)
- error API: `chitra_err_new` / `chitra_err` / `chitra_err_code` / `chitra_err_detail` / `chitra_err_name` / `chitra_err_print_name` + the `ChitraErrCode` enum

## Process

### Work Loop (continuous)

1. **Work phase** — new format support, decode-matrix cells, bug fixes
2. **Build check** — `make build` (link-check the include chain)
3. **Test additions** — a `.tcyr` suite cell for every new decode path (happy + reject)
4. **Reference verification** — diff decode output against ImageMagick / a known-good corpus
5. **Internal review** — bounds, memory, correctness, edge cases
6. **Security check** — any new chunk-length/buffer/inflate-cap handling
7. **Documentation** — CHANGELOG, `docs/development/state.md`, any ADR the change earned
8. **Version check** — `make version-check` (VERSION / cyrius.cyml / CHANGELOG / README in sync)
9. **Dist regen** — `make dist`, confirm `dist/chitra.cyr` still compiles clean
10. **Return to step 1**

### Security Hardening (before every release)

A PNG is untrusted external data. The kii-inherited guards are non-negotiable —
re-verify each before tagging:

1. **Decompression-bomb caps** — IDAT inflate output is capped; over-cap → `CHITRA_ERR_OOM`
2. **Lying-IHDR rejection** — declared dimensions cross-checked against actual data → `CHITRA_ERR_DIMENSIONS`
3. **Ratio caps** — output:input expansion bounded
4. **Chunk-CRC validation** — every chunk's CRC-32 checked → `CHITRA_ERR_CRC`
5. **Bounds on every read** — truncated input → `CHITRA_ERR_TRUNCATED`, never an OOB read
6. **Filter-byte validation** — per-row filter ∈ {0,1,2,3,4} → else `CHITRA_ERR_FILTER`
7. **Spec-legal matrix only** — illegal bit-depth × color-type combos rejected, not guessed

File findings in `docs/audit/YYYY-MM-DD-audit.md`. Severity: CRITICAL / HIGH / MEDIUM / LOW.

### Closeout Pass (before every minor/major bump)

1. Full test suite — every `.tcyr` passes, zero failures (`make test`)
2. Reference re-verify — the full decode matrix against ImageMagick
3. Dead-code / cleanup sweep — stale comments, unused includes, orphaned files
4. Code-review pass — missed guards, off-by-ones, silently-ignored errors, ABI leaks
5. Security re-scan — the hardening checklist above
6. Downstream check — mabda still builds and `gpu_texture_load_png` works against the new `dist/chitra.cyr`
7. Doc sync — CHANGELOG, roadmap, `docs/development/state.md`, CLAUDE.md (if durable content changed)
8. Version verify — `make version-check`; intended git tag matches
9. Clean dist regen — `cyrius distlib` produces a compile-clean bundle

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

> chitra does not yet carry a `docs/` tree. Per first-party standards it should
> grow one as it matures — at minimum `docs/development/roadmap.md` and
> `docs/development/state.md`, plus `docs/audit/` for the pre-release security
> passes. Create entries when earned; don't scaffold empty directories.

- [`docs/adr/`](docs/adr/) — architecture decision records. *Why X over Y?* (e.g. "fork kii's png.cyr vs. shared dep")
- [`docs/architecture/`](docs/architecture/) — non-obvious constraints. *What can't I derive from the code alone?* (e.g. the `lib/`-must-not-be-a-symlink quirk, the flat-domain-module + distlib invariant)
- [`docs/guides/`](docs/guides/) — task-oriented how-tos (e.g. "consuming chitra from mabda")
- [`docs/development/roadmap.md`](docs/development/roadmap.md) — completed, backlog (JPEG → 0.3+), v1.0 criteria
- [`docs/development/state.md`](docs/development/state.md) — live state snapshot, refreshed every release
- [`docs/audit/`](docs/audit/) — security audit reports (`YYYY-MM-DD-audit.md`)
- [`CHANGELOG.md`](CHANGELOG.md) — source of truth for all changes (Keep a Changelog; perf claims carry numbers; breaking changes get a Breaking section)

New quirks land in `docs/architecture/` as numbered items (`NNN-kebab-case.md`).
New decisions land in `docs/adr/` (`NNNN-kebab-case.md`). **Never renumber either series.**
