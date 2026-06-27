# 0002 — Security model: defense-at-perimeter on untrusted image input

**Status**: Accepted
**Date**: 2026-06-26

## Context

chitra decodes attacker-controllable image bytes. Its public entry,
`chitra_png_decode(src, len, err_out)` ([`../../README.md`](../../README.md)),
takes an in-memory byte buffer that a consumer (mabda's
`gpu_texture_load_png`; kii's re-fold per its ADR 0006) hands in
verbatim — those bytes originate from disk, the network, or an asset
pipeline and must be assumed hostile. PNG decoders are a historically
high-CVE surface: libpng, lodepng, and stb_image have each shipped a
long string of advisories (integer-overflow IHDR multiplies, OOB
palette reads, decompression bombs, malformed-chunk OOB). The audit
([`../audit/2026-06-26-audit.md`](../audit/2026-06-26-audit.md)) walked
that corpus against chitra's source and produced the guard inventory
this ADR formalizes.

The decision space is shaped by three constraints:

1. **chitra is a library with no output surface.** Unlike kii — a
   CLI image-to-ANSI viewer whose threat model has a whole second half
   for ANSI-escape injection into a downstream terminal — chitra emits
   nothing to a terminal. It returns a canonical RGBA8 buffer and exits;
   the sole byte sink is `chitra_err_print_name`
   ([`../../src/error.cyr`](../../src/error.cyr)), which writes a fixed,
   decoder-controlled error name to stderr — never attacker-derived text,
   so there is no path-echo or escape-sequence surface. The
   ANSI-injection half of kii's
   ([`0001-fork-kii-png-decoder.md`](0001-fork-kii-png-decoder.md))
   model is structurally **out of scope**: chitra's model is purely
   inbound validation plus bounded allocation.

2. **The decompression substrate is shared.** DEFLATE/zlib inflate is
   sankoch's job (RFC 1950 / RFC 1951), not chitra's — chitra calls
   `zlib_decompress` and never re-implements it. CRC-32 and adler-32
   likewise come from sankoch. Bugs inside that substrate are upstream;
   chitra's defense sits at its own perimeter.

3. **Every read crosses an untrusted boundary.** The decoder walks a
   bounds-checked cursor over `(src, len)`; the canonical-RGBA8
   normalization pass and the byte-buffer I/O boundary are the genuinely
   new code over the kii fork, so they get equal scrutiny.

## Decision

chitra's security model is **defense-at-perimeter**: every byte parsed
from IHDR / PLTE / IDAT / tRNS is validated before any allocation or
loop bound depends on it.

- **Bounds-checked cursor.** All input is read through a self-validating
  24-byte cursor (`_cur_can_read` rejects `n < 0` and `remaining < n`;
  `_cur_u8` / `_cur_u32_be` defensively return 0 rather than ever issuing
  an OOB load), `src/png_chunks.cyr:138`-`167`. u32 reads are masked to
  32 bits so a high bit cannot sign-extend into a negative i64.
- **Compile-time policy ceilings** cap the largest allocation the
  decoder will ever request, applied to attacker-controlled IHDR fields
  *before* the `width * height * bpp` multiply: `CHITRA_MAX_PIXELS`
  (16777216 = 4096²), `CHITRA_MAX_DIM` (65535 per side), and
  `CHITRA_MAX_RAW_BYTES` (268435456 = 256 MB single-buffer ceiling),
  `src/png_chunks.cyr:37`-`39`. The per-side cap is asserted first so
  the product cannot overflow i64.
- **PNG § 11.2.2 Table 11.1 as an allow-list.** Color type
  (`{0,2,3,4,6}`), compression method (`0` only), filter method (`0`
  only), interlace (`{0,1}`), and the bit-depth × color-type
  cross-product are enforced as positive allow-lists — anything else is
  rejected loud rather than half-decoded (e.g. color_type 3 + depth 16
  is rejected), `src/png_filter.cyr:164`-`185`.
- **Decompression-amplification defense.** An IDAT-accumulator cap
  (`src/png_filter.cyr:436`-`442`), a derived inflated/pixel-size cap
  (`:500`-`507`), and a compression-ratio cap of 1100:1 — above
  DEFLATE's theoretical 1032:1 ceiling per RFC 1951 § 3.2.5 —
  (`:519`-`522`) defend against zip-bomb inputs. sankoch's inflate is
  also bounded to the exact pre-computed output size, and the result is
  checked for an exact byte-count match (`:554`-`556`).
- **CRC-32 on every chunk.** IHDR and every walked chunk have their
  stored CRC-32 verified against a recomputation over `type + data`
  (`src/png_filter.cyr:145`-`147`, `:425`-`434`).

**Threat-model boundary.** Bugs *inside* sankoch (Huffman-table
construction, inflate state machine) are upstream's; chitra catches the
symptom at its boundary — a short or oversized inflate result maps to
`CHITRA_ERR_INFLATE` — but does not attempt to fix substrate causes.
What the consumer does with the returned RGBA8 buffer (upload to a GPU
texture, hash it, re-encode it) is the consumer's responsibility;
chitra's contract ends at returning a validated, correctly-sized buffer
or a typed `ChitraErr`.

### Hardening commitments

Each guard maps to its enforcing code and the `CHITRA_ERR_*` code it
raises (enum in [`../../README.md`](../../README.md) and
`src/error.cyr`). All line references are verified against the source in
the audit ([`../audit/2026-06-26-audit.md`](../audit/2026-06-26-audit.md)).

| Guard | Code | Error |
|---|---|---|
| 8-byte signature length + magic check | `chitra_png_check_signature` (`src/png_chunks.cyr:184`) | `CHITRA_ERR_SIGNATURE` |
| Self-validating bounds-checked cursor | `_cur_can_read` / `_cur_u8` / `_cur_u32_be` (`src/png_chunks.cyr:138`-`167`) | `CHITRA_ERR_TRUNCATED` |
| IHDR length must equal 13 | `src/png_filter.cyr:131` | `CHITRA_ERR_BAD_CHUNK` |
| IHDR is the first chunk + type tag | `src/png_filter.cyr:138` | `CHITRA_ERR_BAD_CHUNK` |
| IHDR CRC-32 verification | `src/png_filter.cyr:145`-`147` | `CHITRA_ERR_CRC` |
| Color-type allow-list `{0,2,3,4,6}` | `chitra_png_color_channels` (`src/png_chunks.cyr:210`) + `src/png_filter.cyr:164` | `CHITRA_ERR_UNSUPPORTED` |
| Compression + filter method must be 0 | `src/png_filter.cyr:168`-`169` | `CHITRA_ERR_UNSUPPORTED` |
| Interlace value gate `{0,1}` | `src/png_filter.cyr:171` | `CHITRA_ERR_INTERLACE` |
| Bit-depth × color-type Table 11.1 allow-list | `src/png_filter.cyr:175`-`185` | `CHITRA_ERR_BIT_DEPTH` |
| Dimension caps before the pixel multiply | `src/png_filter.cyr:191`-`197` | `CHITRA_ERR_DIMENSIONS` |
| Per-chunk length cap | `src/png_filter.cyr:407`-`410` | `CHITRA_ERR_BAD_CHUNK` |
| Per-chunk span fits remaining before CRC scan | `src/png_filter.cyr:412`-`415` | `CHITRA_ERR_TRUNCATED` |
| Per-chunk CRC-32 (every chunk) | `src/png_filter.cyr:425`-`434` | `CHITRA_ERR_CRC` |
| IDAT-fusing accumulator cap | `src/png_filter.cyr:436`-`442` | `CHITRA_ERR_OOM` |
| PLTE: single, pre-IDAT, ≤768, multiple-of-3 | `src/png_filter.cyr:443`-`454` | `CHITRA_ERR_BAD_CHUNK` |
| IEND zero-length enforcement | `src/png_filter.cyr:462`-`471` | `CHITRA_ERR_BAD_CHUNK` |
| Derived inflated/pixel-size caps (Adam7-aware) | `src/png_filter.cyr:500`-`507` | `CHITRA_ERR_DIMENSIONS` |
| Zero-IDAT structural reject | `src/png_filter.cyr:512`-`515` | `CHITRA_ERR_NO_IDAT` |
| Decompression-bomb ratio cap (1100:1) | `src/png_filter.cyr:519`-`522` | `CHITRA_ERR_DIMENSIONS` |
| Inflate failure + exact-size second line | `src/png_filter.cyr:554`-`556` | `CHITRA_ERR_INFLATE` |
| Per-row filter-byte allow-list `{0..4}` | `_chitra_unfilter_row` (`src/png_filter.cyr:94`) → `:572` / deinterlace `:311` | `CHITRA_ERR_FILTER` |
| Color-pass re-assert of dimension caps | `src/png_color.cyr:80`-`88` | `CHITRA_ERR_DIMENSIONS` |
| Scanline-buffer sufficiency check | `src/png_color.cyr:96`-`99` | `CHITRA_ERR_DIMENSIONS` |
| tRNS span re-validated within `(src, len)` | `src/png_color.cyr:110`-`113` | `CHITRA_ERR_BAD_CHUNK` |
| tRNS length per color-type (gray 2 / RGB 6 / palette ≤ entries) | `src/png_color.cyr:128` / `:200` / `:234` / `:163`,`:284` | `CHITRA_ERR_BAD_CHUNK` |
| Palette index OOB hard-reject | `src/png_color.cyr:173`, `:292` | `CHITRA_ERR_BAD_CHUNK` |
| Palette images require non-empty, in-bounds PLTE | `src/png_color.cyr:157`,`:272`-`280` | `CHITRA_ERR_BAD_CHUNK` |
| Allocation-failure check on every alloc | throughout `src/png_filter.cyr`, `src/png_color.cyr`, `src/png.cyr` | `CHITRA_ERR_OOM` |

Test coverage exercises each cap and rejection path; the suite counts
live in [`../development/state.md`](../development/state.md). There is
**no in-tree fuzz or benchmark harness yet** — the README calls the
decoder "fuzz-corpus-tested" from its kii lineage, but chitra itself
ships neither file; both are tracked gaps (see Consequences).

## Consequences

**Positive**:

- **Eliminated CVE classes by not decoding what it does not need.**
  chitra parses only IHDR / IDAT / IEND / PLTE / tRNS. It does not
  decode ancillary or metadata chunks — tEXt / iTXt / zTXt / iCCP /
  eXIf / gAMA / sRGB / cHRM / pHYs — so no bug whose root cause lives in
  EXIF parsing, ICC-profile handling, gamma/chromaticity math, or text
  decompression can ship. That surface is structurally inaccessible.
- **Bounded resource consumption.** A hostile PNG can drive at most a
  256 MB single allocation and a 4096²-pixel decode; the ratio cap
  forecloses zip-bomb amplification before inflate runs. Both are inside
  any reasonable DoS window.
- **No emit surface to inject into.** Because chitra returns bytes
  rather than writing a terminal stream, the entire escape-injection /
  output-sanitization problem that dominates a CLI viewer's model simply
  does not exist here. The output is a fixed-layout RGBA8 buffer.
- **Typed, GpuErr-compatible failures.** Every rejection produces a
  16-byte `ChitraErr` (code @0, detail @8) that is layout-compatible
  with mabda's `GpuErr`, so a decode failure maps cleanly onto
  `GPU_ERR_IMAGE_DECODE`
  ([`0003-mabda-abi-compatibility.md`](0003-mabda-abi-compatibility.md)).

**Negative**:

- **Some legitimate large images are rejected.** A genuine PNG above
  4096² pixels or 256 MB inflated is refused at IHDR with
  `CHITRA_ERR_DIMENSIONS`. For chitra's texture-loader use case this is
  a deliberate, acceptable ceiling; a consumer needing larger inputs
  must pre-downscale upstream.
- **Defense-in-depth adds branches.** The color pass re-asserts the
  dimension caps and re-validates the PLTE/tRNS spans against
  `(src, len)` even though `chitra_png_parse_raw` already checked them
  — so the `@internal` pass stays safe on a hand-built `ChitraPngRaw`.
  The cost is microseconds; the code surface is larger.

**Neutral**:

- **New formats and features reopen the surface.** Adding JPEG / GIF /
  BMP (the format-agnostic name anticipates this), or any currently-
  skipped PNG chunk, reintroduces parsing surface and requires a fresh
  audit pass with the shape of
  [`../audit/2026-06-26-audit.md`](../audit/2026-06-26-audit.md). The
  spec-only-feature-set discipline in [`../../CLAUDE.md`](../../CLAUDE.md)
  enforces this.
- **sankoch upstream items are tracked, not owned.** chitra's pre-inflate
  caps reduce the blast radius of any sankoch-internal inflate bug, but a
  substrate flaw remains an upstream finding; tracked in
  [`../development/state.md`](../development/state.md) /
  [`../development/roadmap.md`](../development/roadmap.md).
- **No in-tree fuzz / bench harness yet.** The cap and rejection paths
  are unit-tested but not yet differentially fuzzed against a reference
  decoder inside this repo, and worst-case decode latency is **not yet
  measured**. Both are open follow-ups, not claims.
- **Two stale enum comments to retire.** `src/error.cyr:26`-`27` still
  describe `CHITRA_ERR_INTERLACE` / `CHITRA_ERR_BIT_DEPTH` as
  "single-pass only" / "bit_depth != 8" — accurate for 0.2, stale as of
  0.2.1, which decodes Adam7 and all spec-legal depths. The codes now
  fire only for genuinely illegal combos (e.g. color_type 3 + depth 16).
  Cosmetic doc-drift, no behavioral impact.

## Alternatives considered

- **Stream IDAT incrementally vs. buffer the whole input.** chitra is
  handed a complete in-memory `(src, len)` by the consumer by design — it
  never owns a file handle or socket — so there is nothing to stream;
  the IDAT payloads are concatenated and inflated as a unit, with the
  accumulator and ratio caps providing the amplification defense a
  streaming decoder would get from incremental backpressure.
- **Reject palette PNGs (color_type 3) outright.** Considered as a way
  to delete the OOB-palette-read CVE class wholesale; rejected because
  every palette index access is hard bounds-checked against the PLTE
  entry count (`src/png_color.cyr:173`, `:292`) and palette images
  require a non-empty, in-bounds PLTE span — so the class is closed
  without dropping a spec-mandatory feature.
- **Relative IDAT cap (e.g. `1.5 × inflated_size`).** Rejected for the
  same reason kii's audit rejected it: zlib/DEFLATE header overhead is
  near-constant, so for tiny payloads the legitimate idat:inflated ratio
  exceeds any small relative bound. chitra uses an absolute
  `CHITRA_MAX_RAW_BYTES` ceiling plus the 1100:1 ratio cap — same
  defense, no small-image edge-case failure.

## References

- [`../audit/2026-06-26-audit.md`](../audit/2026-06-26-audit.md) — full guard-inventory audit grounding every entry in the commitments table
- [`../../SECURITY.md`](../../SECURITY.md) — public-facing security policy and reporting
- [`0001-fork-kii-png-decoder.md`](0001-fork-kii-png-decoder.md) — the one-time kii fork these guards descend from
- [`0003-mabda-abi-compatibility.md`](0003-mabda-abi-compatibility.md) — `ChitraErr` / `GpuErr` layout compatibility
- [`../../CLAUDE.md`](../../CLAUDE.md) — spec-only-feature-set discipline
- [`../development/state.md`](../development/state.md) — volatile state: test counts, tracked gaps
- [W3C PNG spec, 2nd ed.](https://www.w3.org/TR/PNG/) — § 5.3 chunk layout/CRC, § 5.5–5.6 chunk ordering, § 8 Adam7, § 9 filters, § 11.2.2 Table 11.1
- RFC 1950 (zlib), RFC 1951 (DEFLATE) — sankoch's inflate contract; § 3.2.5 sets the 1032:1 ratio backstop
