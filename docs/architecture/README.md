# Architecture notes

Non-obvious constraints, quirks, and invariants that a reader cannot derive from the code alone. Numbered chronologically — never renumber.

These are not decisions (those live in [`../adr/`](../adr/)) and not how-tos (those live in [`../guides/`](../guides/)). An item here describes *how the world is*, not *what we chose* or *how to do something*. Volatile state — version, sizes, counts, in-flight work — does not belong here; it lives in [`../development/state.md`](../development/state.md).

chitra is a **library** — there is no CLI, no stdout emit, no terminal/ANSI surface. Consumers ([mabda](../adr/0003-mabda-abi-compatibility.md), and now kii's v1.2.0 re-fold) link `dist/chitra.cyr` and call `chitra_png_decode`. Everything below is about the in-memory decode pipeline: untrusted bytes in, canonical RGBA8 out.

## Module map

The pipeline runs left-to-right; each module owns one stage. Data flows by value through two records — `ChitraPngRaw` (parse output) and `ChitraImage` (public result) — not a shared scratch buffer. The include order is fixed by `[lib].modules` in [`../../cyrius.cyml`](../../cyrius.cyml): `error → png_chunks → png_filter → png_color → png`.

```
  (src, len)                                                    ChitraImage
  untrusted bytes                                               (owned RGBA8)
       │                                                              ▲
       ▼                                                              │
 ┌──────────────────┐   ┌──────────────────┐   ┌──────────────────┐  │
 │ png_chunks.cyr   │   │ png_filter.cyr   │   │ png_color.cyr    │  │
 │ cursor + sig +   │──►│ IDAT concat +    │──►│ canonical RGBA8  │──┘
 │ chunk walk +     │   │ sankoch inflate +│   │ + tRNS +         │
 │ IHDR + PLTE/tRNS │   │ 5 unfilter preds │   │ sub-byte/16-bit/ │
 │ span capture     │   │ + security caps  │   │ Adam7 collapse   │
 └──────────────────┘   └──────────────────┘   └──────────────────┘
       │  ChitraPngRaw ───────────────────────────►│
       │                                            │
       └────────────────────────────────────────────────────────┐
                                                                  ▼
                                                          ┌──────────────────┐
                                                          │ png.cyr          │
                                                          │ chitra_png_decode│
                                                          │ (public) wraps   │
                                                          │ raw + rgba in a  │
                                                          │ ChitraImage      │
                                                          └──────────────────┘

   error.cyr — ChitraErr (16B, GpuErr-compatible) underpins every stage;
               each fallible call returns 0 + sets *err_out.
```

| Module | Owns | Notes |
|---|---|---|
| [`../../src/error.cyr`](../../src/error.cyr) | `ChitraErr` record + `ChitraErrCode` enum + Result helpers (`chitra_err_new`/`chitra_err`/`chitra_err_code`/`chitra_err_detail`/`chitra_err_name`) | Dep-free; 16-byte record layout-compatible with mabda's `GpuErr` ([ADR 0003](../adr/0003-mabda-abi-compatibility.md)). Some enum comments are stale — see below. |
| [`../../src/png_chunks.cyr`](../../src/png_chunks.cyr) | Bounds-checked byte-buffer cursor over `(src, len)`; PNG signature; chunk walk (IHDR / IDAT / IEND / PLTE / tRNS); IHDR decode; PLTE/tRNS captured as `(offset, length)` spans (no copy); the security ceilings | Every read validated against `len` *before* access. CRC-32 via sankoch. Caps ported from kii (audit 2026-05-22). |
| [`../../src/png_filter.cyr`](../../src/png_filter.cyr) | The five spec § 9 unfilter predictors (None/Sub/Up/Avg/Paeth) + `chitra_png_parse_raw`: IDAT concat → sankoch inflate → unfilter → `ChitraPngRaw` | The framing driver. Returns a `ChitraErr` ptr on any failure — never an OOB access on untrusted input. |
| [`../../src/png_color.cyr`](../../src/png_color.cyr) | `chitra_png_color_to_rgba8`: canonical-RGBA8 normalization for color types 0/2/3/4/6, tRNS → alpha, sub-byte grayscale (×255/85/17), 16-bit → high byte, Adam7 deinterlace | The genuinely new code over kii: kii emits native channels for its terminal path; chitra normalizes every color type to RGBA8. Resolves PLTE/tRNS spans against the original `(src, len)`. |
| [`../../src/png.cyr`](../../src/png.cyr) | Public API: `chitra_png_decode` / `chitra_png_decode_rgba8`, the `ChitraImage` record + accessors, `chitra_image_free` (no-op), `chitra_version` | Wires parse → color → `ChitraImage`. The Ok/Err split is a `(ptr, err_out)` pair, not a tagged union. |

Stdlib includes (`string`, `fmt`, `alloc`, `io`, `vec`, `str`, `syscalls`, `assert`, `bench`, `args`, `flags`, `thread`, `sankoch`) live **only** in [`../../src/lib.cyr`](../../src/lib.cyr) — the domain modules are flat. That flatness is exactly what makes `cyrius distlib` strip-concatenation produce a compile-clean `dist/chitra.cyr` (item 002). DEFLATE itself is sankoch's job, not chitra's: `thread.cyr` must precede `sankoch.cyr` because sankoch's public-API lock wraps `mutex_lock`/`mutex_unlock`.

A note on doc-drift for future readers: `src/error.cyr`'s enum comments for `CHITRA_ERR_INTERLACE` ("single-pass only (chitra 0.2)") and `CHITRA_ERR_BIT_DEPTH` ("bit_depth != 8 … chitra 0.2 / AL.P0d scope"), and `png_color.cyr`'s header line "Only bit depth 8 is handled here", are **stale**. As of 0.2.1 chitra decodes Adam7 and every spec-legal bit depth (1/2/4/8/16, validated per color type — PNG § 11.2.2 Table 11.1). Those two error codes now fire only for genuinely illegal combinations (e.g. color type 3 at bit depth 16).

## Items

| # | Item | Hook | What it affects |
|---|---|---|---|
| 001 | [`lib/` must not be a symlink](001-lib-must-not-be-symlink.md) | `cyrius deps` resolves stdlib + sankoch into `lib/`, which must be a **real directory** | Dependency resolution, distlib concatenation, CI checkout |
| 002 | [Flat modules + distlib strip-concatenation](002-flat-modules-distlib-concatenation.md) | `cyrius distlib` builds `dist/chitra.cyr` by stripping includes and concatenating the flat `src/*.cyr` in dependency order | Where stdlib includes may live; the single-file dist consumers link |
| 003 | [Bump allocator / no per-block free](003-bump-allocator-no-free.md) | The stdlib `alloc` is a bump allocator with no per-block free, so `chitra_image_free` / `chitra_raw_free` are documented no-ops | Memory lifetime, the no-op free API, decode-loop usage caveats |
