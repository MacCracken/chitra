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
- **Malformed JPEG** — a crafted baseline JFIF that tries to trigger decoder bugs:
  - Out-of-bounds reads on truncated markers/segments or a runaway entropy stream.
  - Integer overflow in MCU / dimension / component-count math.
  - Divide-by-zero from a zero sampling factor (the CVE-2018-11212 class).
  - Malformed Huffman tables (over-subscribed codes) or out-of-range
    DC/AC magnitude categories and run lengths.
  - Chroma-upsample out-of-bounds on mismatched component dimensions.
  - Non-baseline modes (progressive, arithmetic, 12-bit, hierarchical / lossless,
    CMYK) used as an attack surface — chitra rejects all of these outright.
- **Pathologically large output** — a small input declaring extreme dimensions,
  producing an output frame that exhausts the consumer's memory.

For PNG, DEFLATE decompression itself is **not** chitra's code — it is
`sankoch`'s job (RFC 1950 / 1951 `zlib_decompress`); chitra owns the framing, the
bounds discipline around the inflate call, and the post-inflate exact-size check.
For JPEG, the Huffman/entropy decode **is** chitra's own code — its bounds are
the subject of the 2026-06-27 audit.

## Mitigations in code (✅ shipped)

The guards below are present in chitra's source today and enforced on every
decode. Each maps to a `ChitraErrCode`
([`src/error.cyr`](src/error.cyr)) the consumer can act on.

- ✅ **PNG signature check** — the 8-byte magic is length-validated and matched
  before any chunk is read (`chitra_png_check_signature`,
  [`src/png_chunks.cyr:196`](src/png_chunks.cyr)). Failure →
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
  [`src/png_filter.cyr:562`](src/png_filter.cyr)), just above DEFLATE's
  theoretical 1032:1 maximum (RFC 1951 § 3.2.5), so a zip-bomb-style input is
  rejected instead of expanded. Failure → `CHITRA_ERR_DIMENSIONS`.
  ⚠️ **Accepted risk, stated rather than quietly fixed**: this ratio bounds
  *inflated:IDAT*, and the final RGBA8 buffer is up to 32× the inflated
  scanlines, so a **2,116-byte** 1-bit PNG declaring 4096×4096 decodes to
  64 MB and no ratio cap fires. The 0.5.3 audit examined this and chose **not**
  to repair it: that file is a complete, valid encoding of a solid image, so
  the bomb and the legitimate image are the same file shape and an
  output-ratio cap would reject valid PNGs. What distinguished the BMP and GIF
  cases capped in that cut is that those bombs supplied *nothing* — 2 and 4
  bytes for 16.7 M pixels. **The operative bound for PNG is
  `CHITRA_MAX_PIXELS`**: a caller decoding untrusted PNGs should budget 64 MB
  per decode as the worst case, not the file size, and remember that the bump
  allocator makes that cumulative.
- ✅ **Raw-buffer ceiling** — every derived buffer size is bounded by
  `CHITRA_MAX_RAW_BYTES = 268435456` (256 MB)
  ([`src/png_chunks.cyr:38`](src/png_chunks.cyr)), and every allocation is
  null-checked. The IHDR-derived inflated/pixel buffer sizes over the ceiling
  fail as `CHITRA_ERR_DIMENSIONS` ([`src/png_filter.cyr:543-550`](src/png_filter.cyr));
  the IDAT-accumulator over the ceiling and any allocation that returns null
  fail as `CHITRA_ERR_OOM` ([`src/png_filter.cyr:445`](src/png_filter.cyr)).
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
  ([`src/png_color.cyr:103`](src/png_color.cyr)). Failure →
  `CHITRA_ERR_BAD_CHUNK`.
- ✅ **Structural completeness checks** — IEND must be zero-length; a
  structurally valid PNG with zero IDAT is rejected before any divide on the
  scanline geometry. Failures → `CHITRA_ERR_BAD_CHUNK` / `CHITRA_ERR_NO_IDAT`.
- ✅ **Fail-fast short reads** — chunk headers, chunk data, and CRC spans are
  all bounds-checked against the remaining input before they are scanned, so a
  truncated stream is detected during the walk rather than read past.

Added in **0.3.3** by the [P-1 sweep](docs/audit/2026-08-23-audit.md). That
audit found **no memory-safety defect** — no out-of-bounds access and no
integer overflow into an allocation — so the mitigations below are
conformance, resource and defence-in-depth rather than exploit fixes:

- ✅ **Unknown critical chunks abort** — PNG § 5.4's ancillary bit is honoured.
  An unrecognised *critical* chunk by definition changes how the image is to be
  interpreted, so rendering the image anyway means rendering a stream whose
  meaning the decoder does not understand. Failure → `CHITRA_ERR_UNSUPPORTED`.
  Unknown *ancillary* chunks remain skippable, and a dedicated test asserts
  that so this cannot silently become blanket rejection.
- ✅ **tRNS ordering and uniqueness** — tRNS is now at-most-once and must
  precede IDAT, matching the discipline PLTE always had. The PLTE ordering test
  also moved from an accumulated byte count to an explicit `seen_idat` flag: a
  spec-legal **zero-length IDAT** adds nothing to the count and had defeated
  the old guard. Failure → `CHITRA_ERR_BAD_CHUNK`.
- ✅ **JPEG amplification cap** — output:input is bounded by
  `CHITRA_MAX_JPEG_RATIO`, the JPEG analogue of the PNG inflate-ratio cap.
  JPEG needs it *more*: the entropy bit-reader zero-pads past end-of-data, so a
  hostile file needs **no scan payload at all** — the declared SOF0 geometry
  alone drives every allocation and every IDCT. Because the bump allocator
  never reclaims, that made exhaustion **cumulative across decodes**: a handful
  of ~150-byte files rather than a stream of large ones. Demonstrated, not
  argued — with the cap disabled a 150-byte fixture decodes to a full
  4096×4096 image. Failure → `CHITRA_ERR_DIMENSIONS`.
- ✅ **Marker classification is exhaustive** — standalone markers (SOI, EOI,
  RSTn, TEM) and the T.81 Table B.1 reserved range are rejected rather than
  skipped by length. Treating them as segments made the walk read the next two
  stream bytes as a length and skip that far: bounds-checked, so never an
  overread, but a cursor steered by attacker input. Failure →
  `CHITRA_ERR_JPEG_MARKER`.
- ✅ **Entropy-stream conformance** — `0xFF` fill runs are collapsed on both
  the header and entropy sides (§ B.1.1.2), and a ZRL run past coefficient 63
  is rejected like the run overrun beside it instead of exiting as a clean
  decode. The first accepts valid input that was previously refused; the second
  refuses corrupt input that was previously accepted.
- ✅ **The error path cannot fail silently** — `chitra_err_new` no longer
  returns `0` when its 16-byte allocation fails. It previously stored through a
  null pointer *and* returned 0, which every caller reads as "no error" —
  inverting the failure contract at the exact moment a failure must be
  reported. A BSS-resident fallback `ChitraErr` keeps the contract intact once
  the heap is gone.
- ✅ **Geometry chitra does not implement is refused, not approximated** — a
  single-component scan is non-interleaved per T.81 § A.2; only the interleaved
  layout is implemented, so `H > 1 || V > 1` on a lone component rejects
  (`CHITRA_ERR_UNSUPPORTED`) rather than emitting zero-padded, fabricated
  pixels. Note this **rejects input that 0.3.2 decoded** — deliberately; see
  the CHANGELOG's *Behaviour changes* section for the full list of four such
  input classes.

> Note on two narrow codes: `CHITRA_ERR_INTERLACE` and `CHITRA_ERR_BIT_DEPTH`
> ([`src/error.cyr:26-27`](src/error.cyr)) are validity rejections, not
> capability limits — chitra decodes Adam7 and every spec-legal bit depth, so
> they fire only on genuinely illegal values (an interlace method outside
> {0,1}, or a bit-depth × color-type pair outside § 11.2.2 Table 11.1, e.g.
> color-type-3 at depth 16). Their enum comments were corrected in 0.3.2. See
> [`docs/audit/2026-06-26-audit.md`](docs/audit/2026-06-26-audit.md).

### BMP (0.4.0)

BMP has **no checksum of any kind** — no per-chunk CRC like PNG, nothing. Every
byte reaching the parser is attacker-chosen with only chitra's own bounds to
turn it away, so the header parser *is* the entire perimeter:

- ✅ **Every header field validated before it derives another**, and every
  derived size capped before allocation: dimensions against
  `CHITRA_MAX_DIM` / `CHITRA_MAX_PIXELS`, `stride * height` against
  `CHITRA_MAX_RAW_BYTES`. Failures → `CHITRA_ERR_DIMENSIONS`.
- ✅ **The pixel-data offset is attacker-controlled.** It is a header field —
  not "wherever the palette ended" — so it can point anywhere in or past the
  buffer. The full `data_off + stride * height` span is validated against the
  input length before a single pixel is read. Failure →
  `CHITRA_ERR_TRUNCATED`.
- ✅ **Palette span and index bounds.** The palette span is validated against
  the input length, and every index is **hard-rejected** against the declared
  entry count rather than clamped — the same posture as the PNG palette path.
  Failure → `CHITRA_ERR_BMP_PALETTE`.
- ✅ **Run-length streams (0.5.1)** decode with the guards carrying the weight,
  not the codec. Termination is **structural** — every opcode consumes at least
  two bytes and the cursor only advances, so the loop cannot spin. Every write
  is bounds-checked **individually**, so a run past the end of a row is
  rejected rather than clipped (clipping would silently decode a different
  image than the file encodes). **Delta** — which moves the write cursor by
  attacker-chosen `(dx, dy)` unrelated to anything written — is checked against
  both dimensions **at the jump**, because a delta past the end followed by no
  writes is still malformed. Failure → `CHITRA_ERR_BMP_RLE`. A top-down RLE DIB
  is rejected outright, and `BI_RLE8`/`BI_RLE4` must match 8/4 bpp.
- ✅ **Channel masks (0.5.2) are validated as attacker input.** The
  `BI_BITFIELDS` masks are four DWORDs that drive every shift and width the
  pixel loop uses, so each must be a single **contiguous** run of bits (a split
  mask names no channel any format produces), channels must not **overlap**
  (two claiming the same bit is a contradiction, not a blend), every mask must
  fit **inside the pixel word** (a 24-bit mask on a 16-bpp image reads bits
  that are not there), and at least one color channel must be present or the
  pixel names nothing. All reject at parse with `CHITRA_ERR_BMP_MASK` — an
  unvalidated width feeds a shift, and an unvalidated shift is how a decoder
  reads outside its own pixel.
  **0.5.3 corrected three defects in that machinery**, none of which a fuzzer
  could see because none crash: the validated masks were then **ignored** at
  32 bpp unless the file also declared an alpha mask (a real file decoded with
  red and blue swapped); masks were honoured under `BI_RGB`, where Microsoft
  states they are *"valid only if compression is `BI_BITFIELDS`"*, so a V4
  file with a stale alpha mask over padding decoded **fully transparent**; and
  `BI_RGB` defaults were injected into bitfields files, which made the
  "at least one colour channel" guard **unreachable dead code** — the defaults
  erased exactly the condition it tests. A guard that cannot fire is worse
  than no guard, because it also documents a protection you do not have.
- ✅ **RLE amplification cap (0.5.3)** — `CHITRA_MAX_BMP_RLE_RATIO` = 4096
  bounds decoded output against RLE bytes **consumed**. Demonstrated, not
  argued: a **1,082-byte** RLE8 file declaring 4096×4096 decoded into ~64 MB
  the bump allocator never reclaims. Measuring *consumed* rather than *file
  size* is the whole guard — the first version measured the file, and
  appending 512 KB of padding raised the attacker's own allowance. A solid
  4096×4096 image genuinely needs ~137 KB of RLE, so the cap leaves 8.5×
  headroom over the format's own best case. Failure → `CHITRA_ERR_DIMENSIONS`.
- ✅ **Accepted DIB header sizes are an allow-list**, not a lower bound:
  12 / 40 / 52 / 56 / 108 / 124. An unrecognised size rejects rather than being
  treated as "at least an INFO header". **`BI_JPEG` and `BI_PNG` are refused outright** — honouring them
  would have a decoder re-enter itself, and a recursion surface is better
  declined than bounded.
- ✅ **`planes != 1` is a malformed header, not a feature.** There has never
  been a multi-plane BMP in the wild, so accepting one would only widen the
  parser for no input that exists.

### GIF (0.5.0)

GIF, like BMP and JPEG, carries **no checksum**. It also carries the only
decompressor chitra implements itself: `sankoch` supplies DEFLATE, not LZW, so
there was nothing to delegate to. That makes `src/gif_lzw.cyr` the newest
attack surface in the tree, and it is written against the three shapes a
hostile LZW stream takes:

- ✅ **Unbounded expansion.** LZW is a compressor — a few hundred bytes expand
  without limit. Output is capped at the frame's exact pixel count, so
  expansion past one screenful is a rejection, not an allocation. Failure →
  `CHITRA_ERR_GIF_LZW`.
- ✅ **Cyclic prefix chains.** Emitting a code walks its prefix chain
  backwards; a corrupt dictionary pointing forward or at itself turns that into
  an infinite loop. Entries are only ever added with `prefix < the index being
  written`, so chains strictly decrease and cannot cycle — and the walk is
  **additionally** bounded by the dictionary size, because a guard you can
  reason about is worth less than one you cannot get past.
- ✅ **Out-of-range codes.** A code above `next_code` has no entry and is
  rejected; the single legal exception (`code == next_code`, the KwKwK case) is
  handled explicitly rather than by reading past the dictionary.
- ✅ **A truncated LZW stream rejects** rather than zero-padding. JPEG
  zero-pads past end-of-data because a truncated scan still has a well-defined
  block to finish; LZW has no such notion, and padding would fabricate
  dictionary entries.
- ✅ **Sub-block chains** — every length byte is bounds-checked against the
  input, and the gathered payload is capped at the input length, so a chain
  cannot make chitra hold more than the file itself. The same walk skips
  unknown extension blocks, which is what makes an unrecognised extension
  harmless rather than a parse failure.
- ✅ **The frame rect must lie inside the logical screen** it claims to paint.
  A frame hanging off the canvas edge is rejected, not clamped — clamping would
  silently decode a different image than the file describes.
- ✅ **Palette indices hard-rejected** against the table in force (a local
  color table overrides the global one for its image).
- ✅ **Amplification cap (0.5.3)** — `CHITRA_MAX_GIF_RATIO` = 16384 bounds
  decoded output against the compressed stream, checked **before** the
  allocation it exists to prevent (the first version fired after it). A
  **797-byte** GIF declaring 4096×4096 decoded into ~64 MB. The cap is
  deliberately looser than PNG's 1100:1 because **LZW's legitimate compression
  of degenerate content is close to the bomb ratio** — a solid 4096×4096
  really does compress to ~13 KB — so it bounds the extreme case, not the
  merely aggressive one. Failure → `CHITRA_ERR_DIMENSIONS`.
- ✅ **Graphic Control Extension block size validated (0.5.3)** — it is fixed
  at 4, and every field after it was addressed by a fixed offset. A GCE
  declaring another size had chitra read the packed byte and transparent index
  from bytes that are not those fields. Failure → `CHITRA_ERR_GIF_HEADER`.
- ✅ **The transparent index is per-GCE (0.5.3)** — a GCE governs the graphic
  that follows it, including one that turns transparency **off**. The index
  was only ever set, never cleared, so an earlier GCE's value survived a later
  one revoking it and keyed pixels the file said were opaque. Cyrius `var`
  declarations are function-scoped, and this is what that costs in a long
  function.

GIF's line-by-line audit landed in **0.5.3**
([report](docs/audit/2026-08-24-audit.md)). It found no memory-safety defect
in the LZW decompressor; the one memory finding was a prefix-chain guard set
**one looser than the buffer it protected** (4097 possible stores into 4096
bytes) — unreachable in practice, since the longest real chain is ~4092, but a
guard one looser than its buffer is a latent overflow, not a margin.

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

For format-specific issues (e.g. a known libpng / lodepng / stb_image / libjpeg
vulnerability), please cite the CVE ID. If chitra inherits an issue by faithfully
implementing the PNG, JPEG, BMP or GIF spec, the fix may involve hardening
chitra's parser beyond spec.

## Audit history

- [`docs/audit/2026-06-26-audit.md`](docs/audit/2026-06-26-audit.md) — the PNG
  decode-path audit
  ([`src/png_chunks.cyr`](src/png_chunks.cyr),
  [`src/png_filter.cyr`](src/png_filter.cyr),
  [`src/png_color.cyr`](src/png_color.cyr),
  [`src/png.cyr`](src/png.cyr), [`src/error.cyr`](src/error.cyr)).
- [`docs/audit/2026-06-27-audit.md`](docs/audit/2026-06-27-audit.md) — the
  baseline JPEG decode-path audit
  ([`src/jpeg_huffman.cyr`](src/jpeg_huffman.cyr),
  [`src/jpeg_idct.cyr`](src/jpeg_idct.cyr),
  [`src/jpeg_markers.cyr`](src/jpeg_markers.cyr),
  [`src/jpeg.cyr`](src/jpeg.cyr)); verdict: memory-safe — no reachable
  out-of-bounds, overflow, or divide-by-zero.

- [`docs/audit/2026-08-23-audit.md`](docs/audit/2026-08-23-audit.md) — the
  P-1 sweep of **both** decode paths (ten adversarial lenses, every finding
  put to two independent skeptics), gating 0.3.3. Verdict: **no memory-safety
  defect** — the confirmed findings were correctness, conformance, resource
  and defence-in-depth, and all were repaired in that cut. Introduced the
  in-tree fuzz harnesses.
- [`docs/audit/2026-08-24-audit.md`](docs/audit/2026-08-24-audit.md) — the
  P-1 sweep of **BMP and GIF** ([`src/bmp.cyr`](src/bmp.cyr),
  [`src/gif.cyr`](src/gif.cyr), [`src/gif_lzw.cyr`](src/gif_lzw.cyr)), gating
  0.5.3. Verdict: **no memory-safety defect** — no reachable out-of-bounds, no
  overflow into an allocation, no unterminated loop. **Seven of the nine
  confirmed findings were silent wrong output**, which is the finding about
  the *method* rather than the code: four fuzz harnesses and ~2.2 M cases had
  passed over every one of them, because none of them crash. Each was
  confirmed by decoding the same bytes with ImageMagick. Added the BMP-RLE and
  GIF amplification caps.

  **With this report every decode path has been audited.**

> Coverage note: as of 0.5.3 every format has been audited, and both
> hardening gates have been closed since 0.3.3. The fuzz gap
> is closed — `make fuzz` drives both public decode entries
> over ~2.2 M adversarial cases (7,482,610 assertions, 0 failures),
> including JPEG entropy-segment mutation, and asserts the documented
> `(0, *err_out set)` failure contract as well as survival; and `make bench`
> measures decode latency for all four formats with a committed CSV history. Note
> that benchmarks are a performance signal, **not** a security one — they are
> deliberately excluded from `make test-all` so a slow host cannot fail a
> correctness gate. See
> [`docs/development/roadmap.md`](docs/development/roadmap.md).
