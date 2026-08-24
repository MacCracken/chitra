# chitra — Roadmap

> **Last Updated**: 2026-08-23 (0.3.3)
>
> Sequencing — what ships, in what order, against what gates. Volatile state
> (current version, sizes, assertion counts, in-flight work) lives in
> [`state.md`](state.md), not here. **chitra is pre-v1** (current: 0.3.3) and
> both decode paths are **feature-complete for their scope** — every spec-legal
> PNG depth × color-type × interlace combination, and JFIF **baseline** JPEG
> (grayscale + YCbCr, 4:4:4 / 4:2:2 / 4:2:0, restart markers), decode to
> canonical RGBA8. What remains before a v1.0 freeze is hardening
> infrastructure (both harnesses landed in 0.3.3), an API/ABI freeze, and the next
> formats.

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
  Format coverage is **progressing**, not closed — GIF/BMP remain (see below).
- [x] **First security audit** — line-by-line guard verification across the
  src modules, captured in
  [`../audit/2026-06-26-audit.md`](../audit/2026-06-26-audit.md). Confirmed
  full guard parity with the kii lineage and no real OOB / overflow gap;
  open items are cosmetic doc-drift only (see audit + the stale enum comments
  in `src/error.cyr`).
- [x] **In-tree fuzz harness at 10⁶ iterations clean** — **DONE in 0.3.3.**
  `fuzz/fuzz_png.fcyr` + `fuzz/fuzz_jpeg.fcyr`, run by `make fuzz` and wired
  into `make test-all`: **~1,000,237 decode cases / 3,464,838 assertions, 0
  failures**, in ~10 s. Both public decode entries are driven over random,
  signature-prefixed, bit-flipped, truncated and degenerate-length input, plus
  **entropy-segment-only mutation** for JPEG — the surface that was previously
  unfuzzed, since its hardening was forked from the kii/PNG lineage rather
  than re-exercised. The harnesses assert the documented `(0, *err_out set)`
  contract as well as survival. See
  [`docs/audit/2026-08-23-audit.md`](../audit/2026-08-23-audit.md) § 5.
- [x] **Benchmark harness + CSV history** — **DONE in 0.3.3.**
  `tests/bcyr/chitra.bcyr` (`make bench`) measures decode latency for both
  formats across 12 benchmarks, and `scripts/bench-csv.sh`
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
- [ ] **Downstream consumers green** — mabda's `gpu_texture_load_png` and
  kii's PNG re-fold (its v1.2.0 deleted its own decoder and adopted
  `dist/chitra.cyr`; ADR 0006 on kii's side) both build and pass against the
  frozen surface. Track until the freeze lands.
- [x] **Root docs + doc tree complete** — CLAUDE.md, README, CHANGELOG,
  CONTRIBUTING, SECURITY, ADRs ([`../adr/README.md`](../adr/README.md)),
  architecture notes ([`../architecture/README.md`](../architecture/README.md)),
  the getting-started guide
  ([`../guides/getting-started.md`](../guides/getting-started.md)), and
  examples ([`../examples/README.md`](../examples/README.md)) all current.

## Roadmap ahead (not yet committed)

Ordered roughly by readiness. The PNG and JFIF-baseline-JPEG decode
substrates are done; what remains is the next formats and the hardening
infrastructure that gates v1.0.

- **GIF / BMP via chitra** — the next common raster formats decode into the
  same canonical RGBA8 surface PNG and JPEG already produce. This is the
  **format-agnostic name paying off**: chitra (चित्र = "image") gains GIF and
  BMP without a rename, exactly as it gained the full PNG matrix and then
  baseline JPEG. Consumers (mabda, kii) pick each up on a plain
  `[deps.chitra]` re-pin. GIF raises animation / multi-frame questions to
  settle in scope (see Out of scope) before committing; BMP is the simpler
  of the two and likely lands first.
- ~~Fuzz + benchmark harnesses~~ — **both closed in 0.3.3.** The remaining
  work before a v1.0 freeze is the **API/ABI freeze itself** and the next
  format, not hardening infrastructure.
- **Possible streaming / byte-budget API** — a chunked-input or
  bounded-allocation decode entry point for consumers that cannot hand the
  whole encoded buffer at once, or that need a hard memory ceiling. Speculative
  — only if a consumer needs it; the current API takes one in-memory `(src, len)`.

## Out of scope (durable scope guards)

Durable boundaries on what chitra is — not v1.0-only gates:

- **Encoding** — chitra is **decode-only**. Encoded bytes → RGBA8, never the
  reverse. No PNG/JPEG/GIF/BMP writer.
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
