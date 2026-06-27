# Contributing to chitra

Contributions are welcome. All contributions must be licensed under
**GPL-3.0-only**.

chitra is a **library** — a pure-Cyrius CPU raster image decoder. There is no
CLI, no stdout/ANSI surface, no binary to ship; consumers link `dist/chitra.cyr`
and call the decode API. Keep that framing in mind when proposing changes.

## Development

Follow the conventions in [`CLAUDE.md`](CLAUDE.md) and the AGNOS
[first-party standards](https://github.com/MacCracken/agnosticos/blob/main/docs/development/first-party/first-party-standards.md).
`CLAUDE.md` is the durable rulebook; volatile state (current version, dist size,
assertion count, in-flight format work) lives in
[`docs/development/state.md`](docs/development/state.md) — do not duplicate it
into a PR description.

Build and test before submitting:

```sh
cyrius deps      # resolve stdlib + sankoch + thread into lib/
make build       # link-check the include chain (programs/smoke.cyr → build/chitra_smoke)
make test        # run every tests/tcyr/*.tcyr CPU suite
make dist        # regenerate dist/chitra.cyr via `cyrius distlib`
```

`make build` only proves the include chain compiles clean — `programs/smoke.cyr`
is a smoke link-check, not a real CLI. The deliverable is the library, exercised
through the test suites.

> **`lib/` must be a real directory** populated by `cyrius deps` — never a
> symlink to a cyrius checkout (editing `lib/*.cyr` would corrupt the toolchain
> repo). Every `make` target guards this via `check-lib-wiring`. If it trips:
> `rm lib && mkdir lib && cyrius deps`.

## Adding a new image format

PNG is **feature-complete** as of the current release: signature + chunk parse
(IHDR / IDAT / IEND / PLTE / tRNS), color types 0/2/3/4/6 at every spec-legal
bit depth (1/2/4/8/16 per PNG § 11.2.2 Table 11.1), Adam7 interlace, the five
§ 9 unfilter predictors, canonical-RGBA8 normalization, and the kii-inherited
security guards.

GIF / BMP and friends are post-0.3 work; JPEG baseline shipped in 0.3.0. The
format-agnostic name exists precisely so they can join without a rename. Before writing a new
decoder, **open an issue to confirm sequencing** — a large format lands as small
bites (e.g. JPEG: Huffman, then IDCT, then chroma upsample), each verified
against a real reference (ImageMagick output) before the next.

The contract a new format must honor is unchanged: encoded bytes in →
canonical RGBA8 out. No GPU, no C shim, no file paths.

## ABI discipline

chitra's records are consumed by **mabda** (`gpu_texture_load_png`) with no C
shim and by **kii** (which re-folded onto `dist/chitra.cyr`). Two layout rules
are non-negotiable — see
[`docs/adr/0003-mabda-abi-compatibility.md`](docs/adr/0003-mabda-abi-compatibility.md):

- **`ChitraErr` stays a 16-byte record** (`+0` code, `+8` detail ptr) —
  layout-compatible with mabda's `GpuErr`, so a decode failure maps onto
  `GPU_ERR_IMAGE_DECODE`. Do not widen or reorder it.
- **`ChitraImage` field additions are append-only.** `width` @ +0, `height` @ +8,
  `pixels` @ +16, `channels` @ +24 keep their 0.1.x offsets (mabda's accessors
  depend on them). New fields go at the end (`seen_iend` @ +32, `src_ctype` @ +40),
  and any widen bumps `CHITRA_IMAGE_SIZE`. Never insert a field in the middle.

Any change to the `@public` surface
(`chitra_png_decode`, `chitra_png_decode_rgba8`, `chitra_jpeg_decode`,
`chitra_jpeg_decode_rgba8`, `chitra_image_decode`, the `chitra_image_*`
accessors, the error API, the `ChitraErrCode` enum) requires a `Breaking`
CHANGELOG entry and an ADR.

## Dependencies

The full non-stdlib dependency set is **`sankoch` + `thread`** — and that is
deliberate:

- **`sankoch` owns DEFLATE.** IDAT inflate (RFC 1950/1951) and chunk-CRC route
  through `sankoch` (`zlib_decompress` / `crc32` / `adler32`). Do **not**
  reimplement zlib inline — that is sankoch's job, not chitra's.
- **`thread`** supplies the mutex pair sankoch's public-API lock wraps.

A new dependency needs a written rationale in the PR: what does it own that we
can't do in-tree, does an AGNOS-family substrate already exist, and has the
substrate-extraction trigger fired? See
[`first-party-standards.md § Own the Stack`](https://github.com/MacCracken/agnosticos/blob/main/docs/development/first-party/first-party-standards.md#own-the-stack).

## Tests

Every behavior change needs at least:

- One **happy-path** test (a decode that succeeds and matches the reference)
- One **error-path** test (malformed input, truncated chunk, illegal
  bit-depth × color-type cell, etc.) asserting the right `ChitraErrCode`

Place each in the matching `tests/tcyr/` suite — `error.tcyr` (error paths),
`interlace.tcyr` (Adam7), `jpeg.tcyr` (baseline JPEG decode + reject paths),
`png.tcyr` (the core PNG decode matrix), or `subbyte.tcyr` (1/2/4-bit
grayscale/palette). The suites are globbed by `make test`; each is a standalone
`main()`. The current baseline is **728 assertions across 5 suites** — PRs that
lower coverage will be asked to add it.
Confirm the count with `make count-assertions`.

> **Wanted contribution:** there is no fuzz harness and no benchmark harness
> in-tree yet (both are v1.0 gates). The PNG decoder is "fuzz-corpus-tested" by
> lineage (its kii origin); the JPEG entropy decoder is from-scratch chitra code
> and has never been fuzzed in-tree. A `.fcyr` fuzz harness over the byte-buffer
> entry points (`chitra_image_decode` / the PNG + JPEG decoders) and a `.bcyr`
> bench over the decode hot paths are both welcome — open an issue first to agree
> on shape.

## Modules and the dist bundle

- **Stdlib includes live ONLY in `src/lib.cyr`.** Domain modules (`src/*.cyr`)
  are flat — no stdlib includes. This is what lets `cyrius distlib`
  strip-concatenate them into a compile-clean `dist/chitra.cyr`. Adding a stdlib
  include to a domain module breaks the bundle.
- **`[lib].modules` order in `cyrius.cyml` is dependency order:** `error.cyr` →
  `png_chunks.cyr` → `png_filter.cyr` → `png_color.cyr` → `png.cyr` →
  `jpeg_huffman.cyr` → `jpeg_idct.cyr` → `jpeg_markers.cyr` → `jpeg.cyr`. Don't
  reorder casually.
- **Re-run `make dist` after touching module order or any domain module**, and
  confirm `dist/chitra.cyr` still compiles. The rationale lives in
  [`docs/architecture/002-flat-modules-distlib-concatenation.md`](docs/architecture/002-flat-modules-distlib-concatenation.md).

## Commits and PRs

- **Conventional Commits** preferred: `feat: …`, `fix: …`, `docs: …`,
  `test: …`, `refactor: …`, `chore: …`.
- **One concern per commit** (mirror of CLAUDE.md's "ONE change at a time").
- **The maintainer owns all releases and tagging.** Do not include `VERSION`
  bumps, `cyrius.cyml` version bumps, or CHANGELOG release headers in a feature
  PR unless explicitly asked — release sync is a separate, maintainer-driven
  step.

## Code of Conduct

Participation in this project is governed by the
[Code of Conduct](CODE_OF_CONDUCT.md). By contributing you agree to abide by its
terms.
