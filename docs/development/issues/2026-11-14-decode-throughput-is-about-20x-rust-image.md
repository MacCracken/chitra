# PNG and JPEG decoding run about 20× slower than Rust's `image`, which puts a 4K screenshot at about 2 s — addressed in 1.4.0

**Status:** 🟢 **ADDRESSED in 1.4.0** — JPEG 2.6–3.4× faster, PNG 1.25×; what remains is recorded on the
roadmap (1.4.x maintenance).
**Filed:** 2026-11-14, by **selah** (Rust → Cyrius port, M3 benches: `selah/docs/benchmarks-rust-v-cyrius.md`).
**Affects:** every decode. selah decodes a whole screenshot on every annotate, redact and convert call.
**Severity:** Medium for selah: its MCP tools answer an agent interactively, and a 4K JPEG now takes seconds.

## Measurement

One 512 × 512 RGBA image (`(x ^ y, 3x + y, 5y ^ x, 255) mod 256`: edges and gradients). The same PNG and JPEG files
are decoded on both sides. The JPEG is baseline 4:4:4 at quality 75, so no chroma upsampling is involved.

| Decode | chitra 1.3.1 (`chitra_image_decode_budget`) | Rust `image` 0.25.10 (png 0.18.1 / zune-jpeg 0.5.15) | Ratio |
|---|---|---|---|
| PNG, 512 × 512 RGBA | 24.9 ms (95 ns/pixel) | 1.31 ms (5.0 ns/pixel) | 19× |
| JPEG, 512 × 512 | 59.5 ms (227 ns/pixel) | 2.54 ms (9.7 ns/pixel) | 23× |

At those rates a 3840 × 2160 screenshot (8.3 MP) takes about 0.8 s as PNG and 1.9 s as JPEG, against 41 ms and 80 ms
in Rust. selah's other ported paths run 2.5–7× slower than Rust (its JPEG encoder, at 2.5×, does the same DCT
arithmetic in the other direction). That puts decode about an order of magnitude outside that range.

## Reproduction

From the selah root: `cyrius bench` (it prints `decode_png_512` and `decode_jpeg_512` and writes the two files to
`build/bench/`), then `cargo run --release --locked --manifest-path scripts/oracle/Cargo.toml -- --bench` for Rust's
times on the same files.

## Where to look (read, not profiled)

- **JPEG, Huffman decoding.** `_chitra_jpeg_decode` follows T.81 F.2.2.3's DECODE procedure literally: one bit per
  step, comparing against `maxcode[L]` through accessor calls (`_chitra_jpeg_huff_maxcode`, `_valptr`, `_val`).
  libjpeg and zune-jpeg resolve most codes with one 8- or 9-bit lookahead-table lookup (libjpeg's `jdhuff.c`
  `HUFF_LOOKAHEAD`), and fall back to the bit-serial walk only for longer codes.
- **JPEG, the IDCT and colour pass.** A function call per sample is expensive in Cyrius, so the accessor-per-sample
  pattern is worth checking here too.
- **PNG.** sankoch's inflate rate, and the per-byte work in unfiltering and the RGBA8 colour pass.

A profile on this pair of files would settle the split.

## Resolution (1.4.0)

Measured on this report's 512×512 pattern (same host, minimum of 10):

| decode | 1.3.1 | 1.4.0 | vs Rust `image` |
|---|---:|---:|---|
| JPEG 4:4:4 q75 | 46.5 ms | **13.8 ms** (3.4×) | ~5.4× (was 18–23×) |
| JPEG 4:2:0 q75 | 29.5 ms | **11.2 ms** (2.6×, now with interpolated chroma) | — |
| PNG RGBA8 | 18.2 ms | **14.6 ms** (1.25×) | ~11× (was 19×) |
| JPEG 3840×2160 4:2:0 | 1,033 ms | **354 ms** | — |

- **JPEG** — the split this report asked for, measured by elimination: the IDCT was ~60 % of a 4:4:4
  decode (two calls and a signed division per output sample, then a byte-at-a-time copy into the
  plane), not Huffman decoding. Now: one inlined IDCT per block writing straight into the plane, with
  libjpeg's all-zero shortcuts; coefficients dequantized into natural order as they decode; a 9-bit
  lookahead table per Huffman table and a 56-bit word bit-reader (the fabrication / restart / tail
  semantics kept by construction and pinned); colour and upsampling without a call per pixel. Output is
  byte-identical to `djpeg`.
- **PNG** — inlined Paeth, the first-pixel test hoisted out of every predictor, 32-bit stores in the
  8-bit colour passes. What remains is mostly sankoch's inflate: 1,258 of 1,350 ms on a 3840×2160
  photo-like PNG. That is outside chitra; the roadmap records it as the next thing to measure.
- Not closed to Rust's numbers: Cyrius has no inlining and keeps every local in memory, so ~1 ns per
  simple operation is the floor here. The remaining JPEG cuts (a DC-only block path, the progressive
  driver) are on the roadmap.
