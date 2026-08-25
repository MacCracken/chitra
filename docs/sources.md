# chitra — Sources

> Last Updated: 2026-08-24 (1.0.0)

The citation index for chitra's algorithmic and domain content. AGNOS
math/domain crates carry a sources file so every nontrivial algorithm is
traceable to a spec or primary reference, and so a future maintainer can
re-derive (or audit) any decode step. Entries are grouped by format and,
within each, by the module/function that consumes them.

> Provenance note: the JPEG entries below are drawn from the ITU-T T.81
> spec walk and the integration research behind
> [`proposals/jpeg-baseline-decoder.md`](proposals/jpeg-baseline-decoder.md).
> As of bite 5 (2026-06-26) the IDCT factorization is **committed**: the
> libjpeg `jpeg_idct_islow` integer separable IDCT (Loeffler-Ligtenberg-
> Moschytz), ratified in
> [`adr/0004-jpeg-decode-model.md`](adr/0004-jpeg-decode-model.md) and
> implemented in `src/jpeg_idct.cyr`. Where a citation is the spec
> definition (T.81) it is authoritative; where it is an implementation
> reference (libjpeg source) it is a guide, marked as such. The JPEG
> decode path shipped in the 0.3.0 cut.
>
> Cyrius note: `>>` is a logical shift, so `src/jpeg_idct.cyr` rounds via
> signed division (`_jpeg_descale`, round-to-nearest, symmetric about 0)
> rather than the arithmetic-shift `DESCALE` of the libjpeg reference. This
> is a valid rounding of the same value and keeps chitra's output
> deterministic; it can differ from libjpeg by ≤1 LSB on negative
> intermediates.

## JPEG (shipped, 0.3.0–0.8.0)

### Format syntax and entropy decode

- **ITU-T Recommendation T.81 (1992) — "Digital compression and coding of
  continuous-tone still images"** (the JPEG standard).
  <https://www.w3.org/Graphics/JPEG/itu-t81.pdf>
  - Annex B (B.1–B.2) — marker codes and marker-segment syntax (SOI, SOFn,
    DQT, DHT, DRI, SOS, RSTn, APPn, COM, EOI), big-endian segment lengths.
    Used by: `src/jpeg_markers.cyr` — `chitra_jpeg_scan_markers`,
    `chitra_jpeg_check_signature`, and `_cur_u16_be` (segment-length read).
  - Annex C + Annex F (F.2.2.3, Figure F.16 + Annex C code-assignment) —
    canonical Huffman code construction (`mincode`/`maxcode`/`valptr` from
    the 16 BITS counts + HUFFVAL list) and the DECODE procedure. Used by:
    `src/jpeg_huffman.cyr` — DHT parse (`_jpeg_huff_build`) + the DECODE
    procedure `_jpeg_decode`.
  - § F.2.2.1 + Figure F.12 — the RECEIVE and EXTEND procedures
    (read S bits, sign-reconstruct the DC/AC magnitude). Used by:
    `src/jpeg_huffman.cyr` — `_jpeg_br_bits` (RECEIVE), `_jpeg_extend` (EXTEND).
  - § F.1.2.1 / F.2.2 — baseline DC difference (predictor) + AC run/size
    (RRRR/SSSS, EOB, ZRL) decode. Used by: `src/jpeg.cyr` MCU/block
    decode loop.
  - § A.1.1 — each component's own sample dimensions,
    `x_i = ceil(X·H_i/H_max)` and `y_i = ceil(Y·V_i/V_max)`. This is the
    derivation, NOT § A.2.1 as this entry said through 0.5.3. Used by:
    `src/jpeg.cyr` — and it is what makes the factors **inert** for a
    one-component frame, since there `H_1 ≡ H_max` and `x_1 = X`.
  - § A.2.3 — INTERLEAVED data-unit ordering: one MCU carries `H_i × V_i` units
    from each component in the scan. Used by: `src/jpeg.cyr` MCU geometry and
    upsampling layout.
  - § A.2.2 — NON-INTERLEAVED ordering: a scan carrying a single component
    walks its data units in raster order, one per MCU, "regardless of the
    values of H1 and V1". Diverges from the interleaved layout as soon as the
    factors exceed 1. chitra rejected this through 0.5.3; **0.6.0 decodes it**
    for a one-component frame, and **0.8.0 decodes the rest** — both the
    partially-interleaved case (`Ns < Nf` within one scan) and multi-scan
    (several SOS segments), driven by `_jpeg_decode_scans` and bounded by the
    per-component coverage bitmask. 0.6.0's effective-geometry collapse was
    **deleted** rather than extended: one general § A.1.1 rule now covers both
    layouts, keyed on `Ns == 1` rather than `Nf == 1`. No JPEG scan geometry
    rejects any more. Used by: `src/jpeg.cyr` decode-scan geometry. See
    [`adr/0006-defer-jpeg-multiscan-resumption.md`](adr/0006-defer-jpeg-multiscan-resumption.md).
  - § B.2.3 — scan header: `1 ≤ Ns ≤ 4`, each `Csj` names a distinct frame
    component, and — **conditioned on `Ns > 1`** — `Σ H_j·V_j ≤ 10`. Used by:
    `src/jpeg.cyr` `_jpeg_parse_sos` and `src/jpeg_markers.cyr`
    `CHITRA_MAX_BLOCKS_PER_MCU` (whose comment cited § A.2.2 through 0.5.3).
  - § B.1.1.2 — a marker may be preceded by any number of `0xFF` **fill
    bytes**. Used by: `src/jpeg_huffman.cyr` entropy reader and
    `src/jpeg_markers.cyr` header walk (0.3.3 — the entropy side previously
    read the second `0xFF` as a marker code and rejected valid restart
    streams).
  - § B.1.1.3 + Table B.1 — which markers are **standalone** (SOI, EOI,
    RSTn, TEM) versus length-bearing, and the reserved `0x02`–`0xBF` range.
    Used by: `src/jpeg_markers.cyr` `_jpeg_marker_action` (0.3.3 — these
    previously fell through to "skip by length", letting attacker bytes
    steer the cursor).
  - § B.1.1.5 — `0xFF` data bytes in an entropy-coded segment are stuffed as
    `FF 00`. Used by: `src/jpeg_huffman.cyr` byte-unstuffing, and by
    `tests/bcyr/chitra.bcyr`'s bit writer when it synthesises a scan.
  - Annex K — example luminance/chrominance quantization + Huffman tables
    (the standard reference tables). Used by: `tests/tcyr/jpeg.tcyr`
    known-answer table-build tests.

### Quantization and zig-zag

- **ITU-T T.81 § B.2.4.1 + Annex A.3.6 + Figure A.6** — quantization-table
  spec (DQT, Pq/Tq) and the 8×8 zig-zag scan sequence. Both DQT values and
  AC coefficients are stored/produced in zig-zag order and must be
  scattered to natural order via the 64-entry table before the IDCT. Used
  by: `src/jpeg_markers.cyr` (DQT parse), `src/jpeg_idct.cyr` (zig-zag
  de-order table + dequantization).

### Inverse DCT

- **ITU-T T.81 Annex A.3.3** — definition of the 8×8 inverse DCT (the
  mathematical reference the integer approximation must match within
  tolerance). Used by: `src/jpeg_idct.cyr`.
- **C. Loeffler, A. Ligtenberg, G. S. Moschytz, "Practical Fast 1-D DCT
  Algorithms with 11 Multiplications," ICASSP 1989** — the factorization
  underlying most integer separable IDCT implementations.
  *(Committed factorization — ADR 0004.)* Used by: `src/jpeg_idct.cyr` —
  fixed-point separable 8×8 inverse DCT.
- **libjpeg `jidctint.c` (`jpeg_idct_islow`)** — the canonical integer
  "slow/accurate" IDCT with documented fixed-point scaling and right-shift
  rounding; the practical reference for choosing scale shifts that keep
  i64 intermediates bounded and output bit-reproducible.
  <https://github.com/libjpeg-turbo/libjpeg-turbo/blob/main/jidctint.c>
  *(Implementation guide, not a spec.)* Used by: `src/jpeg_idct.cyr`.
- **ITU-T T.81 § A.3.1** — level shift (+128 after the inverse DCT, then
  clamp to [0,255]). Used by: `src/jpeg_idct.cyr`.

### Color conversion and chroma upsampling

- **ITU-R BT.601 (full-range, as used by JFIF)** and **JFIF v1.02 (ISO/IEC
  10918-5)** — the YCbCr ↔ RGB transform equations chitra applies
  (full-range BT.601, the JFIF default). Used by: `src/jpeg.cyr` —
  integer fixed-point YCbCr→RGB with per-channel clamp.
- **libjpeg `jdcolor.c`** — the standard 16-bit-shift fixed-point YCbCr→RGB
  coefficient set (the integer realization of the BT.601 equations).
  <https://github.com/libjpeg-turbo/libjpeg-turbo/blob/main/jdcolor.c>
  *(Implementation guide.)* Used by: `src/jpeg.cyr`.
- **ITU-T T.81 § A.2.3 + JFIF chroma-positioning convention** — chroma
  subsampling layout; chitra uses box/nearest replication upsampling (the
  conformant-simple choice; interpolation is out of scope). Used by:
  `src/jpeg.cyr` — chroma upsample pass. Two consequences worth carrying: a
  4:2:0 decode differs from **ImageMagick**, which upsamples with a fancy
  (triangle) filter — 937 of 1536 bytes at up to 40/byte on a 24x16 fixture —
  so `djpeg -nosmooth` is the oracle for subsampled JPEG; and the box filter is
  what makes the 0.6.0 exact-fit plane property safe, since it never reads
  `x+1`.

### JPEG decoder CVE corpus (security hardening)

The JPEG-specific vulnerability classes the 0.3.0 hardening checklist
defends against. Referenced, not duplicated — the full mapping of each
class to its chitra guard lives in
[`proposals/jpeg-baseline-decoder.md`](proposals/jpeg-baseline-decoder.md)
(Security hardening checklist) and was verified in the 2026-06-27 JPEG
audit ([`audit/2026-06-27-audit.md`](audit/2026-06-27-audit.md)).

- **CVE-2022-28041** — stb_image baseline DC-coefficient integer overflow
  (also the progressive DC-accumulation class). <https://nvd.nist.gov/vuln/detail/CVE-2022-28041>
- **CVE-2022-28042** — stb_image invalid DHT → out-of-bounds write /
  `huff_decode` UAF. <https://nvd.nist.gov/vuln/detail/CVE-2022-28042>
- **CVE-2013-6629 / CVE-2013-6630** — libjpeg `get_dht` / component handling:
  duplicate component, undefined table, `huffval[]` uninitialized info leak.
  <https://nvd.nist.gov/vuln/detail/CVE-2013-6630>
- **CVE-2023-2804** — libjpeg-turbo `h2v2_merged_upsample` heap overflow
  (12-bit/lossless sample-range + merged-upsample class).
  <https://nvd.nist.gov/vuln/detail/CVE-2023-2804>
- **CVE-2022-25851** — jpeg-js infinite loop on malformed input (entropy DoS).
  <https://nvd.nist.gov/vuln/detail/CVE-2022-25851>
- **CVE-2018-11212** — libjpeg `alloc_sarray` divide-by-zero (zero
  sampling-factor class). <https://nvd.nist.gov/vuln/detail/CVE-2018-11212>
- **Go `image/jpeg`** — excessive-memory-usage (#10532) and
  `unreadByteStuffedByte` mis-sync / scan-component assumptions
  (#10387 / #10447). <https://github.com/golang/go/issues/10387>
- **Rust `jpeg-decoder`** — "subtract with overflow" panic on malformed
  input (#132, image-rs). <https://github.com/image-rs/jpeg-decoder/issues/132>
- **stb_image** — int-overflow → heap-overflow chain (#1928) and DHT
  table-size OOB (#1291). <https://github.com/nothings/stb/issues/1928>
- **lodepng** — self-referential EXIF IFD recursion (#221), the cautionary
  analog for chitra's tolerate-and-skip (never-parse) EXIF handling.
  <https://github.com/lvandeve/lodepng/issues/221>

## PNG (shipped, 0.1.0–0.7.1)

The PNG decode path's algorithmic sources, included so this file covers the
whole crate. The full guard-to-source mapping is in
[`adr/0002-security-model.md`](adr/0002-security-model.md) and
[`audit/2026-06-26-audit.md`](audit/2026-06-26-audit.md).

- **W3C PNG Specification, 2nd ed.** <https://www.w3.org/TR/PNG/>
  - § 5.3 — chunk layout + CRC-32. Used by: `src/png_filter.cyr` (per-chunk
    CRC verification, via sankoch's crc32).
  - § 5.4 — the ancillary bit: a decoder MUST abort on an unrecognised
    **critical** chunk. Used by: `src/png_filter.cyr` chunk walk (0.3.3 —
    previously such chunks were skipped; unknown *ancillary* chunks remain
    skippable).
  - § 5.5–5.6 — chunk ordering constraints. Used by: `src/png_filter.cyr`
    (IHDR-first, PLTE-before-IDAT, at-most-one-PLTE, IEND; 0.3.3 added the
    same discipline for tRNS and switched the ordering test from
    `idat_total > 0` to an explicit `seen_idat` flag, which a spec-legal
    zero-length IDAT had defeated).
  - § 8 — Adam7 interlace (7-pass). Used by: `src/png_filter.cyr`
    deinterlace.
  - § 9 — filter types 0..4 (None/Sub/Up/Average/Paeth). Used by:
    `src/png_filter.cyr` — `_chitra_unfilter_row`.
  - § 11.2.2 + Table 11.1 — IHDR field validity (color-type × bit-depth
    allow-list). Used by: `src/png_filter.cyr` IHDR validation,
    `src/png_chunks.cyr` `chitra_png_color_channels`.
  - § 11.3.2 — tRNS semantics: the chunk names ONE exact sample value to
    treat as transparent. Used by: `src/png_color.cyr` (0.3.3 — the key is
    now compared at full sample width, so a depth-16 key no longer aliases
    onto the 256 values sharing its high byte). 0.7.1 also made tRNS on
    colour types 4 and 6 a rejection, which § 11.3.2 forbids outright.
  - § 13.13 — sample-depth rescaling: `floor(input × MAXOUT / MAXIN + 0.5)`.
    Used by: `src/png_color.cyr` `_png_scale16`, as `(v*255 + 32767) / 65535`
    (0.7.1 — a high-byte **truncation** through 0.7.0, which was off by up to
    one level on every depth-16 sample and changed decoded output for every
    16-bit image when it was fixed).
## BMP (shipped, 0.4.0–0.7.2)

- **Microsoft BMP / DIB format** — `BITMAPFILEHEADER`,
  `BITMAPCOREHEADER` (12-byte, OS/2 1.x), `BITMAPINFOHEADER` (40-byte), the
  `BI_*` compression enumeration, bottom-up-by-default row order with a
  negative height selecting top-down, 4-byte row padding, and the B,G,R
  channel order with a B,G,R,reserved palette.
  <https://learn.microsoft.com/en-us/windows/win32/gdi/bitmap-storage>
  Used by: `src/bmp.cyr` throughout. Three notes on what the format does
  **not** pin down, each of which drove a decision:
  - The fourth byte of a 32-bpp `BI_RGB` pixel is **undefined** — alpha is
    only official under `BI_BITFIELDS` / the V4 masks. Where a mask is
    declared, 0.5.2 reads it; where none is (plain `BI_RGB`), chitra treats an
    all-zero alpha plane as padding and otherwise honours it. ImageMagick
    agrees, which is what settled the heuristic.
    Two corollaries 0.5.3 had to repair, both of which read the *"valid only
    if the compression member is set to `BI_BITFIELDS`"* clause too loosely:
    the V4/V5 mask fields must be **ignored** under `BI_RGB` — real writers
    populate them anyway, and honouring a stale alpha mask over padding bytes
    decoded a file fully transparent — and, conversely, `BI_RGB` defaults must
    not be injected into a bitfields file, which invents a layout the file
    never declared.
  - 16-bpp layout is X1R5G5B5 for `BI_RGB` — **documented**, not merely
    conventional — and declared outright under `BI_BITFIELDS`. Supported since
    0.5.2; the 0.4.0 deferral was on the grounds that the mask machinery did
    not yet exist to read the declaration.
  - Widening a sub-8-bit channel to 8 bits is **bit replication**, not
    `v * 255 / max`. Both arithmetic forms disagree with every reference
    decoder (a 6-bit 48 is 195, not 194), and the error is a whole-image color
    shift rather than an edge case. Used by: `src/bmp.cyr` `_bmp_scale_to_8`.
  - `BI_JPEG` / `BI_PNG` embed a whole other format inside the DIB. Refused
    outright: honouring them re-enters the decoder.
- **CompuServe GIF89a specification** —
  <https://www.w3.org/Graphics/GIF/spec-gif89a.txt>
  - § 18 Logical Screen Descriptor, § 19 Global Color Table, § 20 Image
    Descriptor, § 21 Local Color Table — the two-geometry / two-palette model
    (a frame rect inside a canvas; a local table overriding the global one).
    Used by: `src/gif.cyr`.
  - § 22 + Appendix F — LZW image data: the minimum code size (2..8),
    variable-width LSB-first codes, Clear/End, and the dictionary. Used by:
    `src/gif_lzw.cyr`. Note the KwKwK case (a code equal to the next
    unassigned one, referring to the entry it is itself defining) is the
    subtle part and the one chitra got wrong first — see the 0.5.0 CHANGELOG.
  - § 20 packed field bit 6 — the 4-pass **row** interlace (starts 0/4/2/1,
    steps 8/8/4/2). Distinct from PNG Adam7, which subsamples both axes.
    Used by: `src/gif.cyr`.
  - § 23 Graphic Control Extension — the transparent color index, which is why
    transparency is read from a block *preceding* the image rather than from
    the image itself. Used by: `src/gif.cyr`. Two details 0.5.3 had to
    honour: the block size is **fixed at 4** and must be validated, since
    every field after it is addressed by a fixed offset; and a GCE governs the
    graphic that *follows* it, so the last one before the image descriptor
    wins — **including one that turns transparency off**, which means the
    index has to be cleared rather than merely overwritten when present.
  - § 15-16 sub-block chains — how every unbounded payload is framed. Used by:
    `src/gif.cyr` `_gif_walk_blocks`, which is both the skip path for unknown
    extensions and the gather path for LZW data.
  What the spec leaves to the decoder, and chitra's choice: the canvas area a
  frame does not paint. chitra emits it **transparent** rather than filling
  with the background color index — it decoded nothing there, and alpha 0 says
  so, where a fill would assert a color the frame never specified.
- **RFC 1950 (zlib) + RFC 1951 (DEFLATE)** — IDAT decompression contract;
  § 3.2.5 sets the ~1032:1 ratio backstop behind
  `CHITRA_MAX_INFLATE_RATIO`. **chitra does not implement inflate** — it
  calls sankoch's `zlib_decompress` (+ crc32/adler32). Used by:
  `src/png_filter.cyr` (IDAT inflate call + ratio cap).
  <https://www.rfc-editor.org/rfc/rfc1951>

## See also

- [`proposals/jpeg-baseline-decoder.md`](proposals/jpeg-baseline-decoder.md) — JPEG implementation plan (math summary with inline refs)
- [`adr/0004-jpeg-decode-model.md`](adr/0004-jpeg-decode-model.md) — JPEG decode-model decision
- [`adr/0002-security-model.md`](adr/0002-security-model.md) — security model + PNG guard inventory
- [`audit/2026-06-26-audit.md`](audit/2026-06-26-audit.md) — PNG security audit
- [`audit/2026-06-27-audit.md`](audit/2026-06-27-audit.md) — JPEG security audit
- [`audit/2026-08-23-audit.md`](audit/2026-08-23-audit.md) — P-1 sweep, PNG + JPEG
- [`audit/2026-08-24-audit.md`](audit/2026-08-24-audit.md) — P-1 sweep, BMP + GIF
- Upstream JPEG CVE corpus (referenced, not duplicated): [kii's 2026-05-22 audit](https://github.com/MacCracken/kii/blob/main/docs/audit/2026-05-22-audit.md)
