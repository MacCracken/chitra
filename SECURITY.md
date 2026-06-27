# Security Policy

## Threat surface

chitra is a CPU-side raster-decode **library**: it takes attacker-controllable
image bytes handed in by a consumer (mabda's `gpu_texture_load_png`, kii) and
returns an owned, canonical RGBA8 buffer. It has no CLI, no stdout/ANSI emit,
no terminal surface, and no file or network I/O — the caller passes in-memory
bytes, never a path.

**Image decoders are a known-malicious-input surface.** libpng, lodepng,
libjpeg-turbo, and stb_image all carry a long CVE history of out-of-bounds
reads, integer overflows, and decompression bombs reached through crafted
files. chitra's PNG decoder is forked from kii's fuzz-hardened, W3C-compliant
decoder (see [`docs/adr/0001-fork-kii-png-decoder.md`](docs/adr/0001-fork-kii-png-decoder.md))
and is held to that same defensive standard.

Because chitra returns an in-memory buffer rather than emitting to a terminal,
the **ANSI-escape-injection** threat class that a stdout viewer must worry
about is **not applicable** here. chitra's threat surface is exactly two
things: the untrusted image bytes, and the size of the buffer it allocates on
the caller's behalf.

The realistic threats:

- **Malformed PNG** — a crafted file that tries to trigger decoder bugs:
  - Out-of-bounds reads on truncated chunks or short fields.
  - Integer overflow on declared dimensions (`width × height × bytes_per_pixel`
    overflowing `i64`).
  - Decompression-bomb amplification: a tiny IDAT payload that inflates to an
    enormous scanline buffer through `sankoch`'s DEFLATE.
  - CRC mismatches accepted as valid (a validation-gate bypass).
  - Palette-index out-of-bounds reads (a color-type-3 index pointing past the
    PLTE table).
- **Pathologically large output** — a small input declaring extreme dimensions,
  producing an output frame that exhausts the consumer's memory.

DEFLATE decompression itself is **not** chitra's code — it is `sankoch`'s job
(RFC 1950 / 1951 `zlib_decompress`). chitra owns the framing, the bounds
discipline around the inflate call, and the post-inflate exact-size check.

## Mitigations in code (✅ shipped)

The guards below are present in chitra's source today and enforced on every
decode. Each maps to a `ChitraErrCode`
([`src/error.cyr`](src/error.cyr)) the consumer can act on.

- ✅ **PNG signature check** — the 8-byte magic is length-validated and matched
  before any chunk is read (`chitra_png_check_signature`,
  [`src/png_chunks.cyr:184`](src/png_chunks.cyr)). Failure →
  `CHITRA_ERR_SIGNATURE`.
- ✅ **Self-validating bounds-checked cursor** — every read goes through a
  cursor that rejects negative lengths and reads past the end of the input
  buffer, so a truncated chunk or short field can never drive an OOB load.
  Failure → `CHITRA_ERR_TRUNCATED`.
- ✅ **Per-chunk CRC-32 validation** — every chunk (IHDR included) is verified
  with `sankoch`'s `crc32` against its trailing CRC (e.g. the IHDR check at
  [`src/png_filter.cyr:140`](src/png_filter.cyr)); a mismatch aborts the decode
  rather than accepting corrupt or tampered data. Failure → `CHITRA_ERR_CRC`.
- ✅ **Dimension caps before any multiply** — IHDR `width`/`height` are rejected
  if zero/negative or over the per-side cap `CHITRA_MAX_DIM = 65535`, *before*
  the `width × height` product is ever computed, and the pixel count is capped
  at `CHITRA_MAX_PIXELS = 16777216`
  ([`src/png_chunks.cyr:37-39`](src/png_chunks.cyr)). This closes the
  integer-overflow chain at its source. Failure → `CHITRA_ERR_DIMENSIONS`.
- ✅ **Decompression-bomb ratio cap** — the ratio of inflated output to
  compressed IDAT input is bounded by `CHITRA_MAX_INFLATE_RATIO = 1100`
  (constant in [`src/png_chunks.cyr:43`](src/png_chunks.cyr); checked at
  [`src/png_filter.cyr:519`](src/png_filter.cyr)), just above DEFLATE's
  theoretical 1032:1 maximum (RFC 1951 § 3.2.5), so a zip-bomb-style input is
  rejected instead of expanded. Failure → `CHITRA_ERR_DIMENSIONS`.
- ✅ **Raw-buffer ceiling** — every derived buffer size is bounded by
  `CHITRA_MAX_RAW_BYTES = 268435456` (256 MB)
  ([`src/png_chunks.cyr:38`](src/png_chunks.cyr)), and every allocation is
  null-checked. The IHDR-derived inflated/pixel buffer sizes over the ceiling
  fail as `CHITRA_ERR_DIMENSIONS` ([`src/png_filter.cyr:500-505`](src/png_filter.cyr));
  the IDAT-accumulator over the ceiling and any allocation that returns null
  fail as `CHITRA_ERR_OOM` ([`src/png_filter.cyr:438`](src/png_filter.cyr)).
- ✅ **Inflate exact-size second line of defense** — the inflated stream size
  must match exactly the size derived from IHDR (`height × (1 + row_bytes)`);
  any mismatch from `sankoch` aborts the decode. Failure →
  `CHITRA_ERR_INFLATE` / `CHITRA_ERR_DIMENSIONS`.
- ✅ **§ 11.2.2 Table 11.1 allow-list** — color-type, bit-depth, the
  color-type × bit-depth cross-product, compression method, filter method, and
  interlace value are each checked against the spec allow-list (only method 0,
  interlace ∈ {0,1}, and spec-legal depth/type combos such as the rejection of
  color-type-3 at depth 16). Failure → `CHITRA_ERR_UNSUPPORTED` (unknown color
  type or non-zero compression/filter method), `CHITRA_ERR_INTERLACE`
  (interlace value ∉ {0,1}), or `CHITRA_ERR_BIT_DEPTH` (illegal depth × color-type
  combination) — see [`src/png_filter.cyr:165-185`](src/png_filter.cyr).
- ✅ **Per-row filter-byte validation** — every scanline's filter type is
  checked against `{0,1,2,3,4}` (spec § 9) on both the non-interlaced and the
  Adam7 paths ([`src/png_filter.cyr:37`](src/png_filter.cyr)); an out-of-range
  byte aborts before unfilter. Failure → `CHITRA_ERR_FILTER`.
- ✅ **Palette-index bounds checks** — every palette pixel index, on both the
  sub-byte and the depth-8 path, is rejected if it points past the PLTE entry
  count, and per-entry tRNS reads are bounded by the tRNS array length
  ([`src/png_color.cyr:173`](src/png_color.cyr),
  [`src/png_color.cyr:292`](src/png_color.cyr)). Palette images with a
  missing/short PLTE are rejected. Failure → `CHITRA_ERR_BAD_CHUNK`.
- ✅ **PLTE / tRNS structural guards** — PLTE is rejected if duplicated, if it
  appears after IDAT, if its length exceeds 768 bytes, or if it is not a
  multiple of 3; tRNS spans are re-validated within `(src, len)` in the color
  pass and must have the correct length for the color type
  ([`src/png_color.cyr:110`](src/png_color.cyr)). Failure →
  `CHITRA_ERR_BAD_CHUNK`.
- ✅ **Structural completeness checks** — IEND must be zero-length; a
  structurally valid PNG with zero IDAT is rejected before any divide on the
  scanline geometry. Failures → `CHITRA_ERR_BAD_CHUNK` / `CHITRA_ERR_NO_IDAT`.
- ✅ **Fail-fast short reads** — chunk headers, chunk data, and CRC spans are
  all bounds-checked against the remaining input before they are scanned, so a
  truncated stream is detected during the walk rather than read past.

> Note on stale enum comments: the inline comments on `CHITRA_ERR_INTERLACE`
> and `CHITRA_ERR_BIT_DEPTH` ([`src/error.cyr:26-27`](src/error.cyr)) still say
> "single-pass only" / "bit_depth != 8". This is cosmetic doc drift — as of
> 0.2.1 chitra decodes Adam7 and every spec-legal bit depth, so those two codes
> now fire only for genuinely illegal combinations (e.g. color-type-3 at depth
> 16), not for legal interlace or sub-byte input. See
> [`docs/audit/2026-06-26-audit.md`](docs/audit/2026-06-26-audit.md).

## What chitra does NOT do

For threat-modeling clarity, chitra has no:

- **Network access** — no sockets, no fetch of any kind.
- **Filesystem access** — the consumer hands in bytes; chitra never opens,
  reads, or writes a file.
- **Process spawning** — no `exec`, no `system`, no subprocess.
- **stdout / ANSI / terminal emit** — chitra returns an RGBA8 buffer; it has no
  CLI and produces no escape sequences. (The one exception is
  `chitra_err_print_name`, which writes a fixed, decoder-controlled error name
  to stderr — never attacker-derived text.)
- **Persistent state** — no config files, no cache, no global mutable state
  across calls.
- **Crypto / TLS / hashing** — beyond the CRC-32 / Adler-32 integrity checks
  that `sankoch` performs as part of PNG/zlib validation.

This minimal-surface posture is durable; expanding it (e.g. adding a file or
network entry point) requires explicit justification and a re-audit. The
allocator is intentionally a bump allocator with no per-block free
(`chitra_image_free` is a documented no-op — see
[`docs/architecture/003-bump-allocator-no-free.md`](docs/architecture/003-bump-allocator-no-free.md)),
which keeps lifetime reasoning simple but means a caller decoding many images in
one process should arena-scope its decodes.

## Reporting vulnerabilities

Report vulnerabilities privately to **security@agnos.dev**. Do not open public
GitHub issues for security bugs.

We will:

- Acknowledge receipt within **48 hours**.
- Provide a fix timeline within one week.
- Coordinate disclosure — default **90 days** from acknowledgment, or whenever a
  fix lands and propagates to consumers (mabda, kii), whichever is sooner.

For format-specific issues (e.g. a known libpng/lodepng/stb_image
vulnerability), please cite the CVE ID. If chitra inherits an issue by faithfully
implementing the PNG spec, the fix may involve hardening chitra's parser beyond
spec.

## Audit history

- [`docs/audit/2026-06-26-audit.md`](docs/audit/2026-06-26-audit.md) — first
  full security audit of the chitra decode path
  ([`src/png_chunks.cyr`](src/png_chunks.cyr),
  [`src/png_filter.cyr`](src/png_filter.cyr),
  [`src/png_color.cyr`](src/png_color.cyr),
  [`src/png.cyr`](src/png.cyr), [`src/error.cyr`](src/error.cyr)).

> Coverage gap to be transparent about: chitra ships **no in-tree fuzz harness
> and no benchmark harness** yet. The defensive guards above are exercised by
> the test suites under `tests/tcyr/`, and the decoder's lineage is
> fuzz-hardened in kii, but chitra itself has not re-run a fuzz corpus against
> its own byte-buffer I/O boundary. Standing up a fuzz harness is tracked in
> [`docs/development/roadmap.md`](docs/development/roadmap.md).
