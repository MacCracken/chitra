# 0001 — Fork kii's PNG decoder into the standalone chitra package

**Status**: Accepted
**Date**: 2026-06-19

## Context

kii — the AGNOS image-to-ANSI viewer — carried a proven, fuzz-hardened,
W3C-compliant PNG decoder in-repo (`src/png.cyr`). kii's own
ADR 0001 deliberately kept that decoder
module-local "until a second first-party consumer surfaces," at which
point the AGNOS *extract-on-2nd-consumer* pattern says to lift the shared
surface out into a Sanskrit-named substrate library.

That second consumer surfaced: **mabda** (the AGNOS GPU layer) needed
`gpu_texture_load_png` — encoded PNG bytes turned into a GPU texture, on
the CPU, with no C shim and no external binary. mabda is not a terminal
tool: it does not want kii's file-path I/O, its `STRUCT_*_OFFSET` pstruct
layout, or its ANSI/stdout emit path. It wants exactly one thing kii's
decoder did well — bytes in, canonical pixels out.

The AGNOS first-party rule is *build for two consumers, not one*. With a
second consumer in hand, leaving the decoder embedded in a CLI viewer
would force mabda to either depend on a terminal app for its parser or
reimplement a second copy of the hardest-to-audit untrusted-parser
surface in the ecosystem. Both are the divergence the pattern exists to
prevent.

## Decision

**Fork kii's `src/png.cyr` one time into a new standalone package,
`chitra` (चित्र, *image / picture*), that publishes a stable byte-buffer
→ canonical-RGBA8 decode API and is consumed via `dist/chitra.cyr`.**

- **Scope of chitra**: own CPU-side raster decode for AGNOS — encoded
  image bytes to canonical RGBA8, zero GPU, no C shim, no external
  binaries, pure Cyrius. The format-agnostic name leaves room for JPEG /
  GIF / BMP to join later without a rename; PNG is the 0.x surface.
- **Public surface**: `chitra_png_decode(src, len, err_out)` →
  `ChitraImage*` (see [`src/png.cyr`](../../src/png.cyr)), plus the
  `chitra_png_decode_rgba8` convenience wrapper and the `ChitraImage` /
  `ChitraErr` accessors. The result is an owned RGBA8 buffer regardless
  of the source color type or bit depth.
- **New code beyond the fork** — two seams kii never needed:
  1. the **byte-buffer I/O boundary** (consumers hand in-memory bytes,
     not a file path; chitra deliberately owns no file I/O), and
  2. the **canonical-RGBA8 normalization pass** plus **tRNS
     resolution** (16-bit → high byte, sub-byte grayscale scaled
     ×255/85/17, palette indexed through PLTE), so every supported PNG
     lands as one uniform 4-channel layout for the GPU upload path.
- **No live dependency** between kii and chitra. The Cyrius dist model is
  strip-include concatenation, not live linking, so chitra is a
  one-time fork, not a submodule. kii ↔ chitra bug-fixes are **manual
  backports**.
- **ABI**: `ChitraErr` is a 16-byte record (`+0` code, `+8` detail ptr)
  laid out to be compatible with mabda's `GpuErr`, so a chitra decode
  failure maps directly onto `GPU_ERR_IMAGE_DECODE` with no translation
  struct. `ChitraImage` fields are append-only.

In scope: PNG. Out of scope at fork time: JPEG/GIF/BMP (deferred to
0.3+), and any GPU/terminal/stdout surface (chitra is a library — it
emits no pixels to a screen, only returns buffers).

## Consequences

- **Positive** — one decoder for the AGNOS ecosystem instead of a copy
  per tool. mabda gets PNG decode with no C shim and a `GpuErr`-shaped
  error type it can adopt verbatim. The decoder's fuzz-hardening and
  W3C-compliance carry over from kii's lineage on day one rather than
  being re-earned. And the fork closes the loop kii opened: once chitra
  reaches parity, kii itself deletes its in-repo decoder and re-folds
  onto `dist/chitra.cyr` — which it did at chitra 0.2.0 (see
  kii ADR 0006, "Adopt the chitra distlib"),
  retiring ~800 lines of untrusted-parser surface from the viewer.
- **Negative** — a one-time fork creates **two copies** of the decoder
  until kii re-folds, with a manual-backport window in between: a fix
  landed in one repo has to be hand-carried to the other until they
  reconverge on the shared dist. chitra now owns API-versioning
  discipline (SemVer, tag pinning) that the in-repo module never had.
- **Neutral** — chitra had to reach **parity** with kii's decoder before
  kii could safely consume it back: kii already handled 16-bit depth and
  carried security guards (IEND-length check, distinct no-IDAT error,
  the source-color-type / IEND accessors) the initial fork hadn't all
  inherited. Adopting a decoder weaker than the one it replaces would be
  a regression, so the re-fold was gated on chitra catching up — which
  it did at 0.2.0. The follow-on parity work is tracked in
  [docs/development/state.md](../development/state.md).

## Alternatives considered

- **Reimplement PNG from scratch in chitra.** Rejected — it discards
  kii's accumulated fuzz-hardening and W3C-compliance and re-opens every
  malformed-input bug class on the single highest-risk surface in the
  codebase. A one-time fork inherits all of that for free.
- **Share the decoder via a git submodule / live dependency.** Rejected
  — the Cyrius dist model is strip-include **concatenation**
  (`cyrius distlib` flattens the module chain into one `dist/chitra.cyr`),
  not live linking. There is no live-link path to share, so a submodule
  would buy coupling without the mechanism that makes it work. A
  published dist consumed by `[deps]` is the native idiom.
- **C-FFI to libpng / lodepng / stb_image.** Rejected — it violates the
  AGNOS all-Cyrius-native arc and drags a C build toolchain into the CI
  of chitra and every consumer. The point of owning the decoder is to
  *not* depend on a C binary; DEFLATE itself is already handled natively
  by the `sankoch` stdlib module, so there is no C dependency left to
  justify.

See kii ADR 0006 for the consumer-side completion
of this plan (kii deleting its in-repo decoder and re-folding onto
chitra). Related chitra decisions:
[ADR 0002](0002-security-model.md) (security model inherited from the
kii lineage) and [ADR 0003](0003-mabda-abi-compatibility.md) (the
`ChitraErr` / `ChitraImage` ABI mabda consumes).
