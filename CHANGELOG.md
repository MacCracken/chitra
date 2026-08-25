# Changelog

All notable changes to chitra are documented here.

The format is based on [Keep a Changelog](https://keepachangelog.com/),
and this project adheres to [Semantic Versioning](https://semver.org/).

## [0.7.2] - 2026-08-24

**BMP and GIF loose ends.** Five items from the 0.6.1 deferment sweep, each
small and independent. Four landed; the fifth was investigated and
**deliberately not acted on**, which is the more useful result.

**2,858 test assertions** across 10 suites, 0 failures.

### Added

- **OS/2 2.x `BITMAPCOREHEADER2` (64 bytes) decodes.** Its first 40 bytes are
  laid out exactly like `BITMAPINFOHEADER` — 32-bit width and height, unlike
  the 12-byte OS/2 1.x header — so it needed only admitting to the DIB
  allow-list. Verified against ImageMagick byte-for-byte.

  The OS/2 spec permits any header size from 16 to 64, and chitra accepts
  **only the canonical 64**. Below 40 the compression and `clrused` fields are
  simply absent and would have to be defaulted with no reference to check the
  defaults against — ImageMagick refuses a 16-byte header too ("improper image
  header"). Inventing behaviour for a size nothing writes and nothing else
  reads is the guess this decoder exists to avoid.

### Fixed

- **`BI_ALPHABITFIELDS` on a 52-byte V2 header decoded silently opaque.** That
  compression names four masks; a `BITMAPV2INFOHEADER` ends at the blue mask
  (+40 R, +44 G, +48 B = 52), so the file declares a channel it provides no
  room for. chitra's in-header alpha read is gated on V3-or-later, so `mask_a`
  stayed 0 and **every per-pixel alpha the file declared was discarded with no
  error**.

  It now rejects with `CHITRA_ERR_BMP_MASK` rather than reading the fourth mask
  from just past the header. That would be inventing an undocumented layout:
  ImageMagick refuses `BI_ALPHABITFIELDS` outright ("unrecognized
  compression"), so there is no reference to agree with, and guessing where a
  field probably lives is the same move as injecting `BI_RGB` defaults into a
  bitfields file — the 0.5.3 defect this mask path was rewritten to stop
  making.
- **The GIF transparent index is now range-checked** against the colour table
  in force for that image (a local table changes what "in range" means). Out of
  range it simply never matched a pixel, so this was a validation gap rather
  than a wrong-output one — but chitra's rule for palette indices is to reject
  rather than tolerate, and an index that names nothing is a statement the file
  cannot mean.

### Changed

- **BMP RLE end-of-line now checks its landing point**, at the same threshold
  the delta escape has always used. The delta path's own comment says landing
  outside the bitmap is malformed "even if the stream then writes nothing"; the
  end-of-line path said nothing and checked nothing, so **the two overshoot
  routes in one function disagreed**.

  Stated plainly: no write was ever at risk — every store is bounds-checked
  individually — and **ImageMagick accepts such a file**. This is a consistency
  guard, not a repair for a known defect. `y == h` remains legal, because one
  trailing end-of-line after the last row is ordinary encoder output and a
  guard at `y >= h` would refuse real files; a control cell pins that.

### Investigated and declined

- **A GIF Plain Text Extension does NOT consume a pending Graphic Control
  Extension**, and chitra now says so in the code rather than leaving it
  unexamined.

  The sweep flagged this as a defect, and on the spec alone it reads like one:
  § 23 gives a GCE's scope as "the first Graphic-Rendering Block to follow",
  and § 25 makes Plain Text one — so a `GCE / PlainText / Image` sequence means
  the GCE governs the *text*, and carrying its transparent index forward to the
  image keys pixels the file never asked for.

  **ImageMagick disagrees, measured.** On a hand-built GIF with exactly that
  sequence it renders the image transparent, identically to the same file with
  the Plain Text block removed — so the reference decoder carries the GCE
  forward too. chitra follows the reference here: Plain Text blocks are
  essentially unused in the wild, no real file exists to check the claim
  against, and being the only decoder that renders such a file opaque is a
  visible divergence bought with a conformance argument nothing can confirm.
  This project diverges from ImageMagick where the spec is prohibitive and the
  consequence is a wrong image — PNG § 5.6 in 0.7.1 — and that is not this case.

### Notes

- No public function, struct offset or error code changed.

## [0.7.1] - 2026-08-24

**PNG conformance: chunks the spec forbids, and a reduction that was wrong by
one.** Four gaps, all found by reading the code rather than by any marker in
it. Three left chitra's posture inverted — it has rejected tRNS-before-PLTE
since 0.5.3, an ordering ImageMagick tolerates, while accepting chunks the spec
forbids outright.

**2,833 test assertions** across 10 suites, 0 failures.

### Fixed

- **Depth-16 samples were TRUNCATED to the high byte, not rescaled.** PNG
  § 13.13 gives the conversion between sample depths as
  `floor(input * MAXOUT / MAXIN + 0.5)`; chitra took the top byte, which is
  libpng's `png_set_strip_16` — a function libpng itself documents as the fast,
  *inaccurate* option beside `png_set_scale_16`. It is wrong by up to 1 per
  channel, and wrong precisely where 16-bit precision was the point of the
  file. Measured: samples `0x00FF` and `0x01FF` reduced to **0 and 1** where
  ImageMagick gives **1 and 2**.

  **This changes decoded pixel values for every depth-16 image.** All four
  colour types went through the same path (0, 2, 4, 6), so all four move.

  The tree's own doc called the reduction "unchanged rendered output" — a claim
  about a reference nobody had checked it against. **The depth-16 row of the
  decode matrix was self-certified**: its cells asserted chitra's own
  truncation rule. All seven depth-16 fixtures have now been extracted to real
  `.png` files and diffed against ImageMagick **byte-for-byte, zero
  differences**, and the expectations carry that provenance.

  One subtlety the change surfaced: the ct2 tRNS key compare derived its
  full-width samples from the reduced ones. That was safe only while those were
  untouched high bytes; with rescaling it would have keyed on the wrong number,
  so it now reads the raw samples.
- **PLTE was accepted on greyscale images.** § 11.2.3 makes PLTE required for
  colour type 3, optional for 2 and 6 (a suggested palette), and **forbidden
  for 0 and 4** — a greyscale image has no palette to suggest. chitra captured
  it and ignored it. The asymmetry was visible inside one function: the tRNS
  branch consulted `color_type` eleven lines below a PLTE branch that did not.
- **tRNS was accepted on colour types 4 and 6.** § 11.3.2 forbids it — those
  types already carry a full alpha channel, so a tRNS is a second,
  contradictory statement about the same pixels. Accepted and silently ignored.
- **Chunks between IDATs were ignored.** § 5.6: *"there shall not be any other
  chunks between the IDAT chunks"*. chitra fused every IDAT it met regardless
  of what sat between them, so a stream of IDAT / tEXt / IDAT decoded as though
  the two payloads were adjacent — a different image than the file describes,
  with no error. The ordering family this belongs to was enforced for PLTE
  (0.3.3) and tRNS (0.5.3); the IDAT half of the same sentence never was, while
  CLAUDE.md's hardening checklist claimed chunk ordering as a PNG guard.

  The guard is a `idat_closed` flag, not a count: **multiple IDAT chunks are
  not merely legal, they are the normal shape of any PNG over 8 KB**. A control
  cell pins that consecutive IDATs still decode, and it passes both before and
  after the repair.

### Behaviour changes

- **Depth-16 pixel values change**, as above. A consumer comparing decoded
  bytes against stored expectations from 0.7.0 or earlier will see differences
  of at most 1 per channel — in the direction of every reference decoder.
- **Three input classes now reject with `CHITRA_ERR_BAD_CHUNK`** that
  previously decoded: PLTE on ct0/ct4, tRNS on ct4/ct6, and any chunk between
  IDATs. **ImageMagick accepts all three.** chitra rejects them, which is the
  same call it already made for chunk ordering: a stream whose structure
  contradicts its own header is not something to render a guess from.

### Performance

- **`png_rgba16_256` +10.6%** (8.28 ms → 9.16 ms). That is the rescale itself —
  a multiply, add and divide per sample where there was a byte load — and it is
  the honest price of the correctness fix on the depth-16 path.
- **The depth-8 paths are unchanged** (−0.6% to −0.8%, host noise), and keeping
  them that way took a second pass. The first implementation routed every
  sample through a helper that returned `load8` at depth 8 — correct, and
  **+13.0% on `png_rgba8_256`**, because a per-sample call replaced an inline
  load on the most common decode path in the library. Hoisting the rescale
  behind one branch per pixel put it back. A depth-16 fix has no business
  costing anything on 8-bit images.

### Notes

- Fixture recipe for the three rejection cases:

  ```
  python3 - <<'EOF'
  import zlib, struct
  def chunk(t, d):
      return struct.pack('>I', len(d)) + t + d + struct.pack('>I', zlib.crc32(t+d) & 0xffffffff)
  SIG = b'\x89PNG\r\n\x1a\n'
  # PLTE on greyscale
  open('bad_plte_on_gray.png','wb').write(SIG
      + chunk(b'IHDR', struct.pack('>IIBBBBB', 2, 1, 8, 0, 0, 0, 0))
      + chunk(b'PLTE', bytes([1,2,3, 4,5,6]))
      + chunk(b'IDAT', zlib.compress(b'\x00' + bytes([10, 200])))
      + chunk(b'IEND', b''))
  # tRNS on RGBA
  open('bad_trns_on_rgba.png','wb').write(SIG
      + chunk(b'IHDR', struct.pack('>IIBBBBB', 1, 1, 8, 6, 0, 0, 0))
      + chunk(b'tRNS', bytes([0,5, 0,6, 0,7]))
      + chunk(b'IDAT', zlib.compress(b'\x00' + bytes([10,20,30,255])))
      + chunk(b'IEND', b''))
  # a chunk between IDATs (and the legal control)
  c = zlib.compress(b'\x00' + bytes([10, 200])); h = len(c)//2
  ihdr = chunk(b'IHDR', struct.pack('>IIBBBBB', 2, 1, 8, 0, 0, 0, 0))
  open('bad_idat_split.png','wb').write(SIG + ihdr + chunk(b'IDAT', c[:h])
      + chunk(b'tEXt', b'Comment\x00spliced') + chunk(b'IDAT', c[h:]) + chunk(b'IEND', b''))
  open('ok_idat_split.png','wb').write(SIG + ihdr + chunk(b'IDAT', c[:h])
      + chunk(b'IDAT', c[h:]) + chunk(b'IEND', b''))
  EOF
  ```
- No public function, struct offset or error code changed.

## [0.7.0] - 2026-08-24

**Stream-end honesty.** `chitra_image_seen_iend` exists to answer one question —
did the encoded stream end the way its format says it should? PNG has answered
it honestly since 0.2.0. **JPEG, BMP and GIF hardcoded `1`**, so on three
formats of four the single accessor a consumer could use to detect an
incomplete stream was a constant.

That matters because chitra deliberately **decodes** incomplete streams rather
than rejecting them, exactly as libjpeg does. A JPEG truncated inside its
entropy data comes back as fabricated zero-padded MCUs; a GIF whose LZW stream
stops early comes back with its tail filled by palette entry 0 at full alpha.
Both are defensible decodes. Both were indistinguishable from a complete one.

Measured on a 689-byte JPEG before the repair: chopping 8, 20 and 60 bytes gave
byte sums of **215,484 / 229,896 / 143,178** against a correct 223,824 — every
one reporting a cleanly closed stream.

**2,820 test assertions** across **10 suites**, 0 failures.

### Changed

- **`chitra_image_seen_iend` now means what it says on every format.** It is
  never an error on its own — all of these cases still return a usable
  `ChitraImage`, and the caller decides what a partial decode is worth.
  - **JPEG** — `1` if the scan ended at a real EOI **and** the entropy decoder
    never had to fabricate bits. Both conditions are needed and neither is
    sufficient: the first alone misses a file whose EOI was spliced in early,
    the second alone misses an EOI-stripped file whose pixels are complete.
    Implemented with a new `BR_EOD` flag on the bit reader, set the moment it
    needs a byte the input does not contain — a real EOI and a truncated scan
    both leave the reader zero-padding, and only that flag tells them apart.
  - **GIF** — `1` if the LZW stream filled the frame. Note this asks about the
    **frame**, not the file trailer: chitra decodes the first frame only
    ([ADR 0005](docs/adr/0005-gif-first-frame-only.md)), so on a multi-frame
    GIF it never reads far enough for the trailer to mean anything.
  - **BMP** — still always `1`, now deliberately rather than by omission. The
    format has no terminator, and the entire pixel span is validated against
    the input length before anything is read, so a decode that returns at all
    had complete data.
  - **PNG** — unchanged.

  A consumer treating `seen_iend` as "always 1 except on PNG" will now see `0`
  on truncated JPEG and GIF input. That is the repair.

### Added

- `tests/tcyr/stream_end.tcyr` — a 10th suite (18 assertions) pinning the
  signal for every format **in both directions**. A suite that only checked the
  truncated cases would pass with the field hardcoded the other way.

  Its GIF fixture is worth a note: plain truncation of a GIF mostly *rejects*
  with `CHITRA_ERR_TRUNCATED`, so it does not exercise this path at all. The
  reachable case is a **structurally valid** file whose LZW sub-block chain
  ends early — built by shortening the first sub-block and splicing in the
  end-of-blocks terminator. ImageMagick reads it without complaint.

### Notes

- The bit-reader record grew from 48 to 56 bytes for `BR_EOD`. Every
  `var reader[48]` / `var rdr[48]` declaration moved with it — in `src/` and in
  the seven test call sites. A `var buf[N]` is N **bytes**, and a record that
  outgrows its declaration writes past it: the first build after the reader
  grew failed 8 assertions in exactly that way, which is the cheapest possible
  version of that lesson.
- No public function, struct offset or error code changed. `ChitraImage` keeps
  its 48-byte layout and every accessor keeps its meaning; what changed is that
  one of them now reports a fact instead of a constant.

## [0.6.1] - 2026-08-24

**A repair cut, and the byte-budget surface ADR 0007 deferred.** A tree-wide
sweep for deferred and half-done work turned up four shipped defects that
outranked the release's planned content — three of them **silent wrong output
or wrongly refused input on files standard tools produce**. Those are fixed
first; the budget surface then lands on top, at two names instead of the eight
ADR 0007 reserved.

**2,802 test assertions** across **9 suites** (up from 2,719), 8,072,804 fuzz
assertions, 0 failures. Every repair carries a regression test verified to fail
against the pre-repair code.

### Fixed

- **A `cjpeg -rgb` file decoded to a hue-rotated image with no error raised.**
  libjpeg-turbo writes baseline JPEGs whose three components *are RGB*: ids
  `'R','G','B'`, an Adobe APP14 declaring `transform = 0`, no JFIF APP0.
  chitra skipped every APPn marker and applied the BT.601 inverse anyway —
  **1,149 of 1,536 bytes wrong, max delta 235**, a blue pixel `(20,20,200)`
  returned as dark red `(121,6,0)`. Now byte-identical to `djpeg -nosmooth`,
  with ImageMagick agreeing byte-for-byte. Colour space is taken from the Adobe
  transform, else the component ids, else YCbCr; an undefined transform is
  declined rather than guessed. `source_color_type` gains **`0x113`** so a
  consumer can tell which space was decoded. See
  [ADR 0009](docs/adr/0009-jpeg-colour-transform.md).
- **The GIF amplification cap refused valid files.** 0.5.3 bounded the whole
  logical screen against the *first frame's* compressed bytes — but naming a
  large canvas and painting a small first frame into it is the ordinary shape
  of an optimised animation, not an attack. An **81-byte** GIF with a
  1920×1080 canvas, which `magick identify` reads without complaint, was
  rejected with `CHITRA_ERR_DIMENSIONS`. The ratio now bounds only the frame,
  which is what the LZW stream actually expands into; the canvas is bounded by
  `CHITRA_MAX_DIM` / `CHITRA_MAX_PIXELS` / `CHITRA_MAX_RAW_BYTES`, exactly as
  every other format's declared dimensions are. The 0.5.3 bomb fixtures still
  reject, unchanged.
- **A JPEG refused for good reason still cost 22,160 bytes.**
  `chitra_jpeg_scan_markers` allocated the quantization store and all eight
  Huffman records up front, before any check could refuse the file, and did it
  again on every call. A 15-byte file with a 12-bit SOF0 — rejected correctly
  and permanently — spent 22,160 bytes the bump allocator never reclaims, which
  is ~1,400:1 amplification on the path a consumer under attack takes most.
  The stores are now allocated when a DQT or DHT first defines something:
  **400 bytes**, and a real file pays exactly what it paid before, one segment
  later.

### Security

- **The JPEG amplification cap divided by the whole file length**, so an
  attacker bought allowance with bytes the decoder never decodes — the same
  wrong-denominator defect the 0.5.3 BMP-RLE cap had, live in the JPEG path.
  Demonstrated rather than argued: a **16,556-byte** file, of which 16,404 are
  APPn segments the marker walk skips wholesale, declared 4096×4096 and
  **decoded, spending 117,463,728 bytes**. The denominator is now a real
  entropy-span walk (`_jpeg_entropy_span`) that stops at the first marker which
  is neither stuffing nor RSTn — so padding before *or* after the scan buys
  nothing. Same file, after: rejected, 22,160 bytes. (Now 400, with lazy
  allocation.)
- **The lazy allocation is guarded `== 0`, and that guard is the whole thing.**
  A single DHT segment may carry up to **3,854 table definitions**
  (`_jpeg_huff_build` accepts an all-zero BITS table, so each one counts), so
  allocating per *definition* rather than per *frame* would have traded a flat
  22 KB refusal cost for one that **scales with file size** — 9,496,704 bytes
  from a 64 KB file. Measured with the guard: 20,112. A regression test builds
  that exact file.
- Two reads of `JF_QUANT` / `JF_HUFF` in `tests/tcyr/jpeg.tcyr` were not
  guarded by the presence bitmask. `assert_eq` is print-and-continue, not a
  branch, so a parse regression would have taken the suite down with a SIGSEGV
  instead of printing the FAIL line that names it — and under lazy allocation
  those reads become null dereferences. Both now guarded.

### Added

- **`chitra_image_decode_budget(src, len, max_bytes, err_out)`** and
  **`CHITRA_ERR_BUDGET` (34)** — the surface [ADR 0007](docs/adr/0007-byte-budget-surface-deferred.md)
  deferred, shipped at two names rather than eight. See
  [ADR 0008](docs/adr/0008-byte-budget-as-shipped.md) for why the other six
  were dropped, chiefly that a published byte *count* gets consumed as a
  number and this very release moves the JPEG figure by ~21 KB.

  **The contract:** chitra will not *begin* a decode whose RGBA8 output would
  exceed `max_bytes`. A refusal allocates **16 bytes** — the `ChitraErr` — for
  PNG, JPEG and GIF, and **144** for BMP, whose dimension read goes through the
  real header parser rather than a private copy of the layout. Measured, not
  estimated. It does **not** cover working buffers during a decode that is
  begun, sankoch's allocations (~41 KB one-time on the first PNG decode, plus
  **32 bytes per `zlib_decompress` call** — an exclusion ADR 0007 missed), or
  the cumulative total across calls. `max_bytes <= 0` refuses.

  A budget refusal is **never a validity opinion**: a file whose header cannot
  be read is handed to the router, which reports the real reason. That is what
  keeps the check from becoming a second parser that can disagree with the
  decoder, and a test asserts it.
- `tests/tcyr/budget.tcyr` — a 9th suite. Its cells assert allocation **costs**
  with real numeric bounds, not just return values: a budget test that only
  checked the error code would pass with the exhaustion vector wide open, which
  is the exact failure ADR 0007 held the surface back over.

### Behaviour changes

- An Adobe APP14 declaring `transform >= 2` now rejects with
  `CHITRA_ERR_UNSUPPORTED`. Such a file decoded to garbage before, so this is a
  correction, but it is a change.
- `source_color_type` returns `0x113` for an RGB-component JPEG where it
  previously returned `0x103`. Additive — `0x101` and `0x103` are unchanged —
  but a consumer testing `== 0x103` to mean "3-component JPEG" must test the
  low nibble instead.
- A GIF with a large logical screen and a small first frame now decodes where
  it was rejected. This is the repair, stated as a behaviour change because a
  consumer may have been relying on the rejection.

### Notes

- **The roadmap gains a 0.7.x arc built from the sweep**, not invented: 84
  deferments were catalogued across the decoders, the harnesses, CI and the doc
  tree, and each is now scheduled, marked a permanent scope guard, or marked a
  doc fix. See [`docs/development/roadmap.md`](docs/development/roadmap.md).
- **Not fixed here, and scheduled instead:** a JPEG truncated inside its
  entropy stream still decodes to fabricated MCUs, returns success, and reports
  `seen_iend = 1` — a field hardcoded to `1` on the JPEG, BMP and GIF paths, so
  the one accessor that exists to say "the stream ended cleanly" is a constant
  on three formats of four. Making it honest is a public behaviour change and
  belongs in a cut whose theme is the surface.

## [0.6.0] - 2026-08-24

**T.81 § A.2 non-interleaved JPEG scans decode — for a one-component frame.**
Through 0.5.3 a grayscale JPEG whose SOF0 declared `H > 1` or `V > 1` was
**rejected**, deliberately: chitra computed the interleaved geometry
unconditionally, the two layouts diverge as soon as the factors exceed 1, and
0.3.3 chose rejection over mis-rendering. This cut implements the layout, so
that rejection is reversed. **Multi-scan and partially-interleaved files
(`Ns < Nf`) remain deferred** — see [ADR 0006](docs/adr/0006-defer-jpeg-multiscan-resumption.md),
which records what a correct implementation owes and why a naive relaxation is
worse than the refusal.

This entry deliberately does **not** say "non-interleaved scans now decode".
Only the `Nf = 1` class does.

The implementation is an **effective-geometry collapse**, not a second decoder.
For a one-component frame the sampling factors are *inert*: § A.1.1's
`x_i = ceil(X · H_i / H_max)` collapses to `x_1 = X` because the lone component
**is** the maximum, so forcing the effective geometry to `H = V = 1` makes the
existing interleaved loop walk the non-interleaved layout exactly. It adds no
zero-fill and no containment tripwire, because `cpw = ceil(w/8) · 8` covers the
plane with **no unwritten margin** — the last block write lands at
`cpw·cph − 1` precisely — and a guard that cannot fire is worse than none.

**The oracle is unusually strong here, and it is external in both directions.**
Four libjpeg-turbo 3.2.0 files from one source image, at sampling 1x1 / 2x1 /
2x2 / 4x4, are each 372 bytes and differ in **exactly one byte** — the SOF0
sampling nibble — and `djpeg` decodes all four to the identical image. So the
reference-correct decode of an H>1 grayscale JPEG is provably its H=1 twin's
decode, established by an external encoder *and* an external decoder rather
than by chitra agreeing with itself. chitra now matches `djpeg -nosmooth` over
all 1536 bytes for every one of them.

**2,719 test assertions** (up from 2,478) across **8 suites**, **8,072,804 fuzz
assertions**, 0 failures.

### Added

- `tests/tcyr/jpeg_noninterleaved.tcyr` — a new suite (237 assertions) built on
  real libjpeg-encoded files, with the regeneration recipe in its header so the
  corpus is reproducible rather than mysterious. Its source pattern varies in
  **both** axes and gives each 8×8 block a distinct DC level, so a block placed
  in the wrong grid cell moves an asserted pixel instead of hiding in an equal
  sum. It includes an **exhaustive sweep of all 16 legal (H,V) pairs**, each
  asserted byte-for-byte against the control decode — the factors being inert
  is proved, not spot-checked.
- Two fuzz cases in `fuzz/fuzz_jpeg.fcyr` (+590,194 assertions): a **256-value
  sweep of the SOF0 sampling byte** (every value is now a live input, including
  the illegal ones that must still reject), and 100,000 entropy-mutation cases
  behind a non-interleaved header — a shape whose entropy bytes **never reached
  the bit-reader before**, because that header rejected. Worth stating
  precisely, because the intuitive claim is backwards: the collapsed grid walks
  6 data units for every legal `(H,V)` on the 24×16 fixture, *fewer* than the 8
  or 16 an interleaved reading of the same header would have walked. The new
  surface is a header shape that now decodes at all, not more work per file.

### Behaviour changes

Both directions, which is a first for this project — 0.3.3's entry established
the convention for newly-*rejecting* classes only.

**Newly accepting** (previously rejected, now decodes):

- A one-component JPEG declaring `H > 1` or `V > 1` — was `CHITRA_ERR_UNSUPPORTED`.
- A one-component JPEG whose `H · V` exceeds 10 — was `CHITRA_ERR_JPEG_SOF`,
  from a ΣH·V ≤ 10 cap applied frame-wide. T.81 § B.2.3 conditions that
  restriction on **`Ns > 1`**; it bounds an interleaved MCU, and a
  one-component frame has none. libjpeg agrees in both directions: its encoder
  refuses `-sample 4x4,2x2,2x2` interleaved ("Sampling factors too large for
  interleaved scan") and accepts the same factors non-interleaved. The cap is
  **conditioned, not removed**, and does not move — it stays at the SOF0 parse,
  once per file, before any geometry derives from those factors.

**Newly reclassified** (still rejected, different code):

- A baseline JPEG whose scans do not each carry every frame component now
  rejects with `CHITRA_ERR_UNSUPPORTED` (4) instead of `CHITRA_ERR_JPEG_SOS`
  (17). **The file is valid; chitra defers it.** Seventeen said "your file is
  malformed" about a file `cjpeg -scans` writes on request and `djpeg` reads
  back — and this rejection appeared in **no document in the tree** before now.
  A consumer switching on 17 for this class must move to 4.

### Fixed

- **`Ns = 0` was reported as a deferral rather than a malformed scan.** The old
  single `ns != ncomp` test lumped three different situations together; they
  are now three branches with their own codes. `Ns < 1` and `Ns > Nf` are
  validity failures (`CHITRA_ERR_JPEG_SOS`); `Ns < Nf` is the deferral. Neuter
  the `Ns < 1` branch and an `Ns = 0` file comes back as code 4 — chitra
  claiming it *declines* a file that is simply broken.
- `CHITRA_MAX_BLOCKS_PER_MCU`'s comment cited T.81 § A.2.2 for a rule that is
  § B.2.3. A wrong section number is invisible to `scripts/check-anchors.sh`,
  which can only see line drift.

### Security

- The `Ns > Nf` branch is kept although removing it changes no error code today
  (such a scan is caught downstream by the duplicate-selector guard with the
  same 17). It is what bounds the `seencs` **write index directly** — with it
  the selector loop runs at most `ncomp` times; without it the bound comes from
  the proxy "distinct SOF ids run out". Both are in bounds while `ncomp` is
  restricted to {1,3}; only the direct bound survives that being widened. The
  code comment says all of this, so nobody later "proves" it dead and deletes it.
- **Reachability proof for the conditioned ΣH·V cap, run in both directions**
  because this cut's only cap *loosening* is exactly where a guard silently
  becomes dead code. With the `ncomp > 1` wrapper removed, the 4x4 grayscale
  file rejects again with 14 (so the condition is doing the work). With the
  inner line removed entirely, a 3-component file declaring ΣH·V = 24 **decodes
  to garbage** — byte sum 282,048 against the correct 223,824 (so the cap is
  live, not dead). Both were run; the second is the one the 0.5.3 BMP finding
  says not to skip.
- A widely-repeated claim about this code is **false, and tested**: removing the
  `ns != ncomp` gate does *not* give chitra a reachable stack overflow via
  `seencs`. With the gate fully deleted and no replacement bound, `Ns = 200`
  rejects cleanly under both cycling-valid and ascending-distinct selectors,
  because the write index advances only on a distinct matched SOF id. It is
  recorded in ADR 0006 so a future cut does not hunt a corruption that cannot
  happen — and so the guard that *is* reachable after relaxation (`Ns < 1`,
  a wrong-output guard) is not mistaken for a memory-safety one.

### Deferred, with an ADR

- **The streaming / byte-budget decode entry point.** The roadmap asked for
  "additive surface, so it wants an ADR"; 0.6.0 ships the ADR and the
  measurement that shapes it, and 0.6.1 ships the surface.
  [ADR 0007](docs/adr/0007-byte-budget-surface-deferred.md) leads with what
  disqualified the obvious design: **a 15-byte JPEG that is refused,
  permanently and correctly, spends 22,096 bytes** — `chitra_jpeg_scan_markers`
  allocates the frame record, the quantization store and eight Huffman table
  records *before* the SOF0 check that refuses the file, and none of it comes
  back. Any probe reaching SOF0 through that function makes
  `decode_budget(src, len, 1, &err)` spend 22 KB and then say "over budget" —
  a memory-ceiling API that is itself a memory-exhaustion vector, reachable by
  an attacker who only ever gets refused. That is the 0.5.3 wrong-denominator
  lesson recurring inside the guard built to embody it. The named prerequisite
  is **lazy table allocation** in the existing parser (not a second parser,
  whose divergence from the real one is the failure it would be built to
  avoid), which also drops the refusal cost to ~336 bytes for *every* caller.

### Documentation

- **NEW** [`docs/architecture/005-alloc-reset-sankoch-hazard.md`](docs/architecture/005-alloc-reset-sankoch-hazard.md)
  — a reproduced upstream defect: calling the stdlib's `alloc_reset()` between
  decodes **corrupts memory and breaks the next PNG decode**, because sankoch
  memoizes its CRC-32 table as a raw pointer into the arena and cannot see the
  reset, so chitra's per-decode `crc32_init_table()` writes 16 KB through a
  dangling pointer. BMP and JPEG are unaffected — neither touches sankoch. The
  observed error code varies (7 and 1 both seen from the same bytes) with what
  now occupies the re-issued address, which is itself the diagnosis; the note
  documents the **mechanism**, not a code. Not fixable chitra-side: the guards
  are internal to sankoch and `lib/` is a vendored build artifact.
- **REVISED** [`docs/architecture/003`](docs/architecture/003-bump-allocator-no-free.md)
  — its allocation inventory predated BMP and GIF entirely (the real count is
  **30 sites across 9 modules**), and its recommendation to "reset the region
  between batches" is now flagged unsafe for PNG per 005. Gains the
  refusal-path allocation cost as a numbered fact.
- **REVISED** [`ADR 0004`](docs/adr/0004-jpeg-decode-model.md) gains a dated
  *Revised in 0.6.0* section; the existing 0.3.3 text is left intact so the
  decision history stays legible.
- **REVISED** [`docs/architecture/004`](docs/architecture/004-jpeg-decode-pipeline.md)
  documents the collapse, the exact-fit property, and the fact that exact fit
  **depends on the upsampler being a box filter** — a fancy filter reads `x+1`
  and would make an edge margin live again.
- The reference-verification rule is narrowed for JPEG in CLAUDE.md and
  CONTRIBUTING: `djpeg -nosmooth` is the primary oracle, and ImageMagick is a
  valid second one only for grayscale and 4:4:4. It differs from chitra on a
  4:2:0 file in 937 of 1536 bytes (fancy vs box chroma upsampling) — a filter
  difference that would otherwise send someone chasing a non-bug.

### Notes

- **No public function, struct offset, or error code changed.** `dist/chitra.cyr`
  stays ABI-additive; consumers re-pin mechanically.
- **No new benchmark row.** With the collapse, `H` and `V` do not affect block
  count or plane size for a one-component frame, so a `jpeg_gray_h2v2_256` row
  would measure the identical loop counts under a different name. The four
  existing `jpeg_*` rows are unmoved within host noise (`jpeg_gray_256`
  2.85 ms vs 2.83 ms), which is the expected result: this cut adds two
  branches taken once per decode and no zero-fill.

## [0.5.3] - 2026-08-24

**P-1 audit and repair cut — the first line-by-line audit of BMP and GIF.**
Those two formats shipped across 0.4.0–0.5.2 with known-answer suites,
reference cross-checks and heavy fuzzing, but no guard review. Full report:
[`docs/audit/2026-08-24-audit.md`](docs/audit/2026-08-24-audit.md).

**No memory-safety defect was found** — no OOB access reachable from a public
entry, no integer overflow into an allocation, no unterminated loop. That was
the expected shape: 0.5.2 alone had surfaced two silent BMP bugs that months of
fuzzing missed because neither was a crash, so this sweep weighted
**wrong-output** defects as heavily as memory safety. Seven of the nine
confirmed findings are exactly that.

**Every wrong-output finding was confirmed by decoding the same bytes with
ImageMagick.** The fuzzers had run millions of cases over this code without
flagging any of them.

**2,478 test assertions** (up from 2,416), **7,482,610 fuzz assertions**, 0
failures. Every repair carries a regression test verified to fail against the
pre-repair code.

### Fixed

- **32-bpp `BI_BITFIELDS` masks were parsed, validated, then ignored** unless
  the file also declared an alpha mask. A file whose red mask is the low byte
  decoded **with red and blue swapped** — chitra returned `(50,100,200)` where
  ImageMagick returns `(200,100,50)`. Masks now govern both packed depths
  unconditionally; whether the file also declares alpha is a separate question.
- **Mask fields were honoured under `BI_RGB`, rendering images invisible.**
  Microsoft is explicit that the V4/V5 masks are *"valid only if compression is
  BI_BITFIELDS"*, and real writers populate them anyway. A V4 `BI_RGB` file
  with a stale alpha mask over padding bytes decoded **fully transparent**.
  Masks are now read only under `BI_BITFIELDS` / `BI_ALPHABITFIELDS`. Present
  since 0.5.2.
- **`BI_RGB` default masks were injected into bitfields files**, inventing a
  layout the file never declared — and making the **"at least one colour
  channel" guard unreachable dead code**, because the defaults erased exactly
  the condition it tests. The 0.5.2 CHANGELOG claimed that guard rejects such
  files; it could not fire. Defaults now apply only when the file declared no
  masks, and a bitfields file declaring no colour channel rejects with
  `CHITRA_ERR_BMP_MASK`.
- **GIF transparent index was a stale function-scoped var.** A Graphic Control
  Extension applies to the graphic that follows it, so the last one before the
  image descriptor governs — including one that turns transparency **off**. The
  index was only ever set, never cleared, so an earlier GCE's value survived a
  later GCE that revoked it, keying pixels the file said were opaque. This is
  the `var`-is-function-scoped hazard, and what it costs in a long function.
- **GIF Graphic Control Extension block size was never validated.** It is fixed
  at 4 and every field after it was addressed by a fixed offset; a GCE
  declaring another size had chitra read the packed byte and transparent index
  from bytes that are not those fields.
- **Sub-byte grayscale tRNS compared the key at the wrong width** — a gap in
  0.3.3's H-1 repair, which fixed depth 8/16 but not the sub-byte path. A key
  of `0x0105` names no 4-bit sample, yet its low byte aliased onto a real one
  and keyed those pixels transparent.
- **tRNS ordering enforced two of the three rules its own comment claimed** — a
  gap in 0.3.3's H-8 repair. For a palette image tRNS must **follow PLTE**; its
  entries are per-palette-entry alphas and mean nothing before the palette
  exists (§ 5.6 / § 11.3.2). Note ImageMagick tolerates this ordering; chitra
  rejects it, consistent with its § 5.4 posture.
- **The LZW prefix-chain guard was looser than the buffer it protected**,
  permitting up to 4097 stores into a 4096-byte buffer. Unreachable in practice
  (the maximum real chain is ~4092) but a guard one looser than its buffer is a
  latent overflow, not a margin. The bound is now on the index itself.
- **A wild pointer on the RLE path.** `srow = data + y * stride` was computed
  where `stride` is meaningless, producing a pointer far past the input. Never
  dereferenced — but a pointer that survives only by never being used is
  latent, not safe.

### Security

- **Amplification caps for BMP-RLE and GIF.** PNG bounds inflate output against
  IDAT input and JPEG has had an output:input cap since 0.3.3; neither newer
  format got one. Demonstrated rather than argued: a **1,082-byte** RLE8 file
  and a **797-byte** GIF each declaring 4096×4096 decoded into ~64 MB the bump
  allocator never reclaims. New `CHITRA_MAX_BMP_RLE_RATIO` (4096:1) and
  `CHITRA_MAX_GIF_RATIO` (16384:1), each sized against the format's own best
  case — a solid 4096×4096 needs ~137 KB of RLE or ~13 KB of LZW, leaving 8.5×
  and 3.2× headroom. The GIF cap is deliberately looser than PNG's 1100:1
  because **LZW's legitimate compression of degenerate content is close to the
  bomb ratio**; it bounds the extreme case, not the merely aggressive one.
- Two follow-on defects **in the new caps** were found and fixed before
  release: padding defeated the BMP cap (appending 512 KB of junk raised the
  attacker's own allowance, so it now measures bytes actually **consumed**),
  and the GIF cap fired *after* the allocation it exists to prevent.

### Notes

- **Accepted risk, stated rather than quietly fixed:** a 2,116-byte 1-bit PNG
  declaring 4096×4096 decodes to 64 MB, and `CHITRA_MAX_INFLATE_RATIO` does not
  catch it because it bounds *inflated:IDAT* while the final RGBA is 32× the
  inflated scanlines. This is **not** repaired: that file is a complete, valid
  encoding of a solid image, so the bomb and the legitimate image are the same
  file shape and a ratio cap would reject valid PNGs. What distinguishes the
  BMP/GIF cases is that those bombs supplied *nothing* — 2 and 4 bytes for
  16.7 M pixels. The operative bound for PNG is `CHITRA_MAX_PIXELS`.
- No PNG or JPEG regression: all nine 2026-08-23 repairs are intact, and
  growing the router from two formats to four did not change routing for any
  PNG or JPEG input.
- `scripts/check-anchors.sh` caught three more drifted code citations
  introduced by this cut's own edits, on its second release since being added.

## [0.5.2] - 2026-08-24

**BMP channel masks, 16 bpp, and the V4/V5 headers.** The last of the 0.4.0
deferrals, landed as one cut because they are the same feature seen from three
angles: 16 bpp was deferred *because* of the masks, and the masks live in the
extended headers.

**This retires the 32-bpp alpha heuristic — for the files that declare a mask.**
That precision matters. When a header carries an alpha mask (V3+ or
`BI_ALPHABITFIELDS`), chitra now reads it instead of inferring. For plain 32-bpp
`BI_RGB` the fourth byte remains formally undefined and no mask says otherwise,
so the heuristic still governs there. Claiming the heuristic is simply "gone"
would be wrong.

### Added

- **`BI_BITFIELDS`** (and `BI_ALPHABITFIELDS`) — explicit per-channel bit masks
  at 16 and 32 bpp. Masks are read from inside the header for V2 and later, or
  from the DWORDs following a 40-byte `BITMAPINFOHEADER`.
- **16 bpp.** Deferred in 0.4.0 on the grounds that 5-5-5 was convention rather
  than declaration; with the mask machinery in place, `BI_BITFIELDS` declares
  the layout outright, and the `BI_RGB` default is **documented by Microsoft**
  as X1R5G5B5 — so applying it is reading the spec, not guessing.
- **`BITMAPV4HEADER` (108) and `BITMAPV5HEADER` (124)**, plus the V2 (52) and
  V3 (56) intermediates. All are `BITMAPINFOHEADER` with fields *appended*, so
  the common 40-byte prefix is parsed as before and only the channel masks at
  +40..+55 are additionally read. The color-space, gamma, rendering-intent and
  ICC-profile fields are **skipped, not guessed at**: chitra emits raw
  sRGB-ordered samples and performs no color management, so honouring a color
  space would be claiming a transform it does not do.
- `CHITRA_ERR_BMP_MASK` (33) — a mask that is non-contiguous, overlapping,
  wider than the pixel word, or leaves no color channel at all.
- **+155 test assertions** (`bmp.tcyr` 855 → 1,010), every pixel of every new
  fixture asserted against ImageMagick's decode of the same bytes. The V4 and
  V5 fixtures encode the same image, so they must decode identically.
- **+100,000 fuzz cases** — a channel-mask mutation mode that splices random
  DWORDs into the mask fields, since those four values drive every shift and
  width the pixel loop uses. BMP fuzz now 2,758,258 assertions, 0 failures.

### Fixed

- **Channel scaling used the wrong formula, twice.** Widening a 5- or 6-bit
  channel to 8 bits is **bit replication** — shift left and fill the vacated
  low bits with copies of the field's own high bits — not `v * 255 / max`.
  The first draft truncated (a 5-bit 16 became 131 instead of 132, every
  16-bit pixel one level low); round-to-nearest fixed that case but still
  disagreed at 6 bits (48 → 194, where the answer is 195). Only replication
  matches the reference at every width and value, because replication is what
  the hardware mapping actually is. Caught by cross-checking against
  ImageMagick; a whole-image color shift, not an edge case.
- **16 bpp was routed through the palette path.** `bpp < 24` had been a safe
  shorthand for "indexed" since 0.4.0 and stopped being one the moment 16 bpp
  landed — a packed-pixel depth was falling into the palette-lookup branch and
  failing with `CHITRA_ERR_BMP_PALETTE`. Narrowed to `bpp < 16`, with a test
  asserting a 16-bit image is not treated as indexed.

### Security

- **Masks are attacker-controlled and validated as such.** Each must be a
  single contiguous run of bits (`0xA800` names no channel any format
  produces); channels must not overlap (two claiming the same bit is a
  contradiction, not a blend); every mask must fit inside the pixel word (a
  24-bit mask on a 16-bpp image reads bits that are not there); and at least
  one color channel must be present, or the pixel names nothing. All reject
  with `CHITRA_ERR_BMP_MASK` at parse — an unvalidated width feeds a shift, and
  an unvalidated shift is how a decoder reads outside its own pixel.
- `BI_BITFIELDS` is rejected at depths where it is meaningless (anything other
  than 16 or 32 bpp), and an **unknown DIB header size** still rejects — the
  set of accepted sizes is an allow-list, not a lower bound.
- The mask DWORDs following a 40-byte header are bounds-checked against the
  input before they are read, and they push the implicit pixel-data offset
  along when the file-header offset is 0.

### Notes

- With 0.5.2 the BMP deferral list from 0.4.0 is **empty**. What remains
  refused is refused *permanently*, not deferred: `BI_JPEG` and `BI_PNG`, which
  would have a decoder re-enter itself through attacker-controlled data.

## [0.5.1] - 2026-08-24

**BMP run-length compression.** `BI_RLE8` and `BI_RLE4`, deferred in 0.4.0 with
`CHITRA_ERR_BMP_COMPRESSION`, now decode. This is the first of the two cuts
paying off the BMP deferrals; `BI_BITFIELDS`, 16 bpp and the V4/V5 headers
remain deferred to 0.5.2.

As the roadmap predicted, **the guards are the bulk of the work, not the
codec.** An RLE stream is a flat sequence of 2-byte opcodes — an encoded run,
or an escape for end-of-line, end-of-bitmap, absolute mode, or *delta*. Three
properties do the safety work:

1. **Termination is structural.** Every opcode consumes at least two bytes and
   the cursor only advances, so the loop cannot spin — there is no opcode that
   leaves the read position where it was.
2. **Every write is bounds-checked individually**, not per-run. A run whose
   count would carry it off the end of a row is **rejected, not clipped**:
   clipping would silently decode a different image than the file encodes.
3. **Delta is the sharp one.** It moves the write cursor by attacker-chosen
   `(dx, dy)` with no relation to what has been written, so it is checked
   against **both** dimensions at the jump rather than left to the per-write
   check — a delta far past the end followed by no writes should still be
   recognised as malformed, not silently accepted.

### Added

- `BI_RLE8` (8 bpp) and `BI_RLE4` (4 bpp) decode: encoded runs, absolute mode
  with its word-boundary padding, end-of-line, end-of-bitmap, and delta.
- `CHITRA_ERR_BMP_RLE` (32) — a corrupt RLE stream, distinct from
  `CHITRA_ERR_BMP_COMPRESSION`, which continues to mean "chitra does not
  implement this compression". A caller can now tell "your file is broken" from
  "chitra won't".
- **+561 test assertions** (`bmp.tcyr` 294 → 855). Coverage includes an
  **ImageMagick-encoded** RLE8 file, plus hand-built fixtures for RLE4 encoded
  runs, RLE8 absolute, RLE4 absolute and delta — every one cross-checked
  against ImageMagick's decode of the same bytes. The RLE4-encoded,
  RLE8-absolute and RLE4-absolute fixtures encode the **same image by three
  different opcode paths**, so they must decode identically; that is a check a
  single-fixture-per-feature suite would miss.
- **+200,000 fuzz cases** in `fuzz/fuzz_bmp.fcyr`: an RLE-stream-only mutation
  mode, and a **delta-splice** mode that deliberately injects escape-2 opcodes
  with random `(dx, dy)` rather than hoping random mutation produces one. BMP
  fuzz now runs 2,458,215 assertions, 0 failures.
- **A `bmp_rle8_256` benchmark** with a small run-length encoder in the harness.
  Its content is deliberately **blocky** rather than the gradient the other
  fixtures use: RLE exists for flat graphic content, and encoding a per-pixel
  gradient would produce almost entirely 1-length runs and measure a case
  nobody ships.

- **`scripts/check-anchors.sh`** — the docs cite code by `file.cyr:line`, and
  those numbers move whenever a guard is added above them. That rot had already
  needed hand-repair twice (the `png_chunks.cyr` anchors in 0.3.3, and the
  `png_filter.cyr` + `png_color.cyr` anchors in this cut, where three citations
  were pointing at a closing brace). The script prints every citation with the
  line it now points at and flags the ones landing on a brace or past
  end-of-file; it is wired into the closeout checklist rather than CI, because
  it cannot know what a line was *meant* to say. Dated `docs/audit/` reports are
  excluded — their anchors are a historical record, not a live claim.
- **Repaired 14 drifted code anchors** across `CLAUDE.md`, `SECURITY.md` and
  ADR 0002, found by the script above on its first run.

### Security

- A **top-down RLE DIB is rejected** (`CHITRA_ERR_BMP_HEADER`). Microsoft's
  own documentation says top-down DIBs cannot be compressed, and the reason is
  structural: the end-of-line escape counts rows from the bottom, so the two
  conventions have no consistent meaning together.
- **RLE is bit-depth specific** and a mismatch is rejected: `BI_RLE8` requires
  8 bpp, `BI_RLE4` requires 4 bpp. The run and absolute payloads mean different
  things at each depth, so decoding one as the other would silently produce a
  different image rather than fail.
- The compressed span cannot be computed in advance — that is the point of a
  run-length stream — so only its **start** is validated in the header. Every
  read the decode loop makes is bounds-checked individually, which is what
  makes the unbounded length safe rather than merely unchecked.

### Notes

- **Pixels no opcode reaches keep index 0.** An RLE stream is allowed to leave
  gaps: a delta jump skips pixels that are never written. chitra leaves them at
  index 0 rather than inventing a value, and **ImageMagick resolves them the
  same way** — which is what settled the semantics rather than assumption.
- Reference note: ImageMagick will not *write* `BI_RLE4` at all, so the RLE4
  fixtures are hand-built. They are still reference-*verified*, because
  ImageMagick reads them back correctly — the encoder gap does not compromise
  the check.

## [0.5.0] - 2026-08-24

**GIF decode — the fourth and last of the common raster formats.** chitra now
decodes PNG, JPEG, BMP and GIF, all to the same canonical RGBA8 `ChitraImage`,
behind one `chitra_image_decode` router.

**GIF decodes the FIRST FRAME only** — see
[ADR 0005](docs/adr/0005-gif-first-frame-only.md). GIF is the one format chitra
handles that describes a *sequence* rather than an image, and `ChitraImage` has
one `pixels` pointer, no frame count and no delay. Returning frame 1 keeps the
output contract every other format honours, so existing consumers gain GIF on a
re-pin with no code change. The cost is stated plainly rather than buried: an
*optimised* animation whose first frame is a background plate decodes to that
plate, not to what a viewer shows.

### Added

- **`src/gif_lzw.cyr`** — GIF's LZW decompressor: variable-width codes
  (`min_code_size + 1` up to 12 bits), LSB-first packing, mid-stream Clear
  handling, and the KwKwK self-referential case. This is the **only
  decompressor chitra implements itself** — PNG delegates DEFLATE to `sankoch`,
  and JPEG's entropy decode is Huffman, not dictionary-based. `sankoch` has no
  LZW, so there was nothing to delegate to.
- **`src/gif.cyr`** — the block walk and frame geometry:
  GIF87a/GIF89a headers, the Logical Screen Descriptor, global **and**
  per-image local color tables (the local table wins), the 4-pass row
  interlace, and transparency from a Graphic Control Extension. Unknown
  extension blocks are **skipped by their sub-block chain** rather than parsed,
  which is what makes an unrecognised extension harmless.
- New public surface, mirroring the existing formats:
  `chitra_gif_decode(src, len, err_out)`,
  `chitra_gif_decode_rgba8(src, len, w_out, h_out)`, and
  `chitra_gif_check_signature(src, len)`.
- **`chitra_image_decode` now sniffs four formats** — PNG magic, JPEG SOI,
  BMP `BM`, GIF `GIF8?a`, then `CHITRA_ERR_SIGNATURE`.
- `ChitraImage.src_ctype` gains the GIF sentinel **`0x300 | min_code_size`**,
  distinct from PNG's raw color_type, JPEG's `0x100 | ncomp` and BMP's
  `0x200 | bpp`.
- Four error codes (28–31): `CHITRA_ERR_GIF_HEADER`, `_GIF_LZW`,
  `_GIF_PALETTE`, `_GIF_NO_IMAGE`.
- **`tests/tcyr/gif.tcyr`** — 622 assertions, every pixel of every fixture
  asserted. Fixtures are **real GIFs produced by ImageMagick**, not hand-rolled
  by the same understanding that wrote the decoder.
- **`fuzz/fuzz_gif.fcyr`** — ~370,000 cases, **1,259,514 assertions**, 0
  failures, including an **LZW-stream-only** mutation mode that leaves the
  header intact so hostile bits land squarely in the decompressor.
- **A GIF benchmark** with a small greedy **LZW encoder** in the harness
  (`tests/bcyr/chitra.bcyr`). Writing an encoder was the honest option: a GIF
  benchmark built from literal codes alone would never make the decoder walk a
  dictionary chain, which is where GIF decode actually spends its time.
  Encoding happens outside the timed region. **43 ns/px** at 256×256 — the same
  ballpark as baseline JPEG, and 2× the cost of PNG RGBA8.

### Fixed

- **LZW KwKwK emitted the wrong bytes in the wrong order.** The
  self-referential case (`code == next_code`) must emit `string(prev)` followed
  by `first_char(prev)`. The expansion buffer is a reverse stack that the emit
  loop walks from the top down, so the trailing byte has to sit at the
  *bottom* — the first draft pushed it on top, and twice, producing one extra
  byte at the front of the run. Caught by the interlaced 8×8 fixture, where it
  shifted four pixels of one row; found and fixed before release. The trailing
  byte's value is not known until the chain walk reaches the root, so index 0
  is now reserved up front and filled afterwards.

### Security

- **The LZW decompressor is written against its three known attack shapes**,
  each documented at the point it is defended:
  - *Unbounded expansion* — output is capped at the frame's exact pixel count,
    so a few hundred bytes cannot expand past one screenful.
  - *Cyclic prefix chains* — dictionary entries are only ever added with
    `prefix < the index being written`, so chains strictly decrease and cannot
    cycle; the walk is **additionally** bounded by the dictionary size, because
    a guard you can reason about is worth less than one you cannot get past.
  - *Out-of-range codes* — a code above `next_code` has no entry and is
    rejected; the single legal exception (`code == next_code`) is handled
    explicitly.
- A truncated LZW stream **rejects** rather than zero-padding. JPEG zero-pads
  past end-of-data because a truncated scan still has a well-defined block to
  finish; LZW has no such notion, and padding would fabricate dictionary
  entries.
- The frame rect must lie inside the logical screen it claims to paint. A frame
  hanging off the canvas edge is rejected, not clamped — clamping would
  silently decode a different image than the file describes.
- Sub-block chains are walked with every length byte bounds-checked, and the
  gathered payload is capped at the input length, so a chain cannot make chitra
  hold more than the file itself.

### Notes

- **Uncovered canvas is transparent, not background-filled.** When the first
  frame is smaller than the logical screen, the area outside its rect is
  emitted as alpha 0. chitra did not decode those pixels; alpha 0 says exactly
  that, where a background fill would assert a color the frame never specified.
- Reference verification needed a tiebreak worth recording: ImageMagick's
  `-interlace line` GIF **writer** does not round-trip its own source, so
  agreement between two independent *readers* — ImageMagick's and a from-spec
  Python decoder — is what established the interlaced expectations rather than
  assuming the encoder preserved row order. The two agree pixel-for-pixel on
  every fixture.

## [0.4.0] - 2026-08-24

**BMP decode.** chitra gains its third format, normalizing Windows BMP to the
same canonical RGBA8 `ChitraImage` that PNG and JPEG already produce. This is
the format-agnostic name paying off: BMP joins on a plain `[deps.chitra]`
re-pin, with no rename and no change to the existing surface.

BMP is the simplest of the three decode paths — no entropy coding, no DEFLATE,
no DCT — and it benchmarks that way: **6 ns/px** at 24/32 bpp against PNG's
83 ns/px and JPEG's 43 ns/px for the equivalent 256×256 image. The difficulty
in BMP is not compression but framing, and four quirks drive the
implementation:

1. **Rows are stored bottom-up.** A positive header height means the file's
   first row is the image's *last* row. A negative height means top-down, and
   the magnitude is the height.
2. **Rows are padded to a 4-byte boundary**, so the stride is
   `((width * bpp + 31) / 32) * 4`, not `width * bytes-per-pixel`.
3. **Channels are B,G,R** — and the palette is B,G,R,reserved.
4. **The pixel data offset is a header field**, not "after the palette". It is
   authoritative, and there can be a gap.

Decoder output is verified **identical to ImageMagick** on all eight valid
fixtures — including the bottom-up/top-down pair, which must produce
byte-identical output from opposite storage orders.

### Added

- **`src/bmp.cyr`** — the BMP decoder. `BI_RGB` uncompressed at 1 / 4 / 8 bpp
  (palette-indexed, MSB-first packing), 24 bpp and 32 bpp; `BITMAPINFOHEADER`
  (40-byte) and `BITMAPCOREHEADER` (12-byte) DIB headers; both row orders; the
  BGRA palette.
- New public surface, mirroring the existing pairs exactly:
  `chitra_bmp_decode(src, len, err_out)`,
  `chitra_bmp_decode_rgba8(src, len, w_out, h_out)`, and
  `chitra_bmp_check_signature(src, len)`.
- **`chitra_image_decode` now sniffs three formats** — PNG magic, then JPEG
  SOI, then BMP `BM`, then `CHITRA_ERR_SIGNATURE`. Existing callers gain BMP
  support with no code change.
- `ChitraImage.src_ctype` gains the BMP sentinel **`0x200 | bpp`** — so `0x201`
  / `0x204` / `0x208` for the indexed depths, `0x218` for 24 bpp and `0x220`
  for 32 bpp. Distinct from PNG's raw color_type (0/2/3/4/6) and JPEG's
  `0x100 | ncomp`.
- Four error codes (24–27): `CHITRA_ERR_BMP_HEADER`, `_BMP_DEPTH`,
  `_BMP_COMPRESSION`, `_BMP_PALETTE`.
- **`tests/tcyr/bmp.tcyr`** — 294 assertions. Fixture pixel values are
  deliberately distinct per position, because a decoder that got the row order
  *or* the channel order wrong would still return the right *set* of pixels,
  just in the wrong places — only position-sensitive expectations catch that.
- **`fuzz/fuzz_bmp.fcyr`** — ~500,000 adversarial cases, **1,819,490
  assertions**, 0 failures. BMP has **no checksum of any kind**, so unlike PNG
  every mutation reaches the parser; the harness leans on that with a
  header-only mutation mode that keeps the file plausible so the header parser
  is always the thing under test. The hostile field that matters most is the
  pixel-data offset — it is the one header value that can point anywhere in or
  past the buffer.
- **Three BMP benchmarks** in `tests/bcyr/chitra.bcyr` (24 / 32 / palette-8 at
  256×256), fixtures generated and decode-verified before timing as with the
  other formats.

### Security

- Every BMP header field is validated **before** it is used to derive another,
  and every derived size is capped before anything is allocated: dimensions
  against `CHITRA_MAX_DIM` / `CHITRA_MAX_PIXELS`, `stride * height` against
  `CHITRA_MAX_RAW_BYTES`, the palette span and the whole pixel-data span
  against the input length. A lying pixel-data offset is a clean rejection,
  never an overread.
- **Palette indices are hard-rejected** against the declared entry count —
  the same posture as the PNG palette path, not a clamp.
- Deferred modes reject with distinct codes rather than half-decoding, per the
  posture [ADR 0004](docs/adr/0004-jpeg-decode-model.md) set for non-baseline
  JPEG: `BI_RLE8` / `BI_RLE4`, `BI_BITFIELDS`, 16 bpp, and the
  `BITMAPV4`/`BITMAPV5` header extensions. **`BI_JPEG` and `BI_PNG` are
  refused on their own merit** — honouring them would have a decoder re-enter
  itself, which is a recursion surface worth declining outright rather than
  bounding.
- `planes != 1` is treated as a malformed header, not a feature — there has
  never been a multi-plane BMP in the wild.

### Notes

- **32 bpp `BI_RGB` alpha is a documented heuristic.** The fourth byte is
  formally *undefined* for `BI_RGB` — alpha only becomes official with
  `BI_BITFIELDS` / V4 masks, which are deferred. Writers disagree in practice:
  some store real alpha, others leave it zero as padding. Trusting it blindly
  renders the padding-zero files fully invisible; ignoring it discards real
  alpha. chitra looks first: if *every* fourth byte is zero the field is
  padding and the image is opaque, otherwise it is alpha and is honoured.
  **ImageMagick makes the same call**, which is what settled it.
- 16 bpp is deferred rather than guessed: without `BI_BITFIELDS` the channel
  layout is 5-5-5 by convention only, and honouring a convention while
  refusing the header that declares it would be exactly the kind of guess this
  project rejects elsewhere.

## [0.3.3] - 2026-08-23

**P-1 audit, hardening and repair cut.** A ten-lens adversarial sweep of both
decode paths — each finding put to two independent skeptics before it was
accepted — plus the repair of everything confirmed, chitra's **first in-tree
fuzz harnesses**, and its **first benchmark harness**. Between them the cut
closes **both** remaining v1.0 hardening gates. Full report: [`docs/audit/2026-08-23-audit.md`](docs/audit/2026-08-23-audit.md).

**No memory-safety defect was found.** No OOB read, OOB write, or integer
overflow into an allocation. The entropy bounds, Adam7 geometry, plane-write
indices, signed-shift discipline and palette/span validation were all examined
closely and found correct — see § 2 of the report. Everything below is a
correctness, conformance, resource or defence-in-depth repair.

Every repair carries a regression test that was **verified to fail against the
pre-repair code**. **784 test assertions** (up from 728), and **3,464,838 fuzz
assertions over ~1,000,000 decode cases** in ~10 s, 0 failures — clearing the
roadmap's *10⁶ iterations clean* v1.0 criterion outright. First recorded
decode baseline (this host, 256×256): PNG rgba8 **83 ns/px**, gray8 and
palette8 **154 ns/px**, Adam7 rgba8 **128 ns/px**; JPEG grayscale
**43 ns/px**, 4:2:0 **91 ns/px**, 4:4:4 **145 ns/px**.

### Behaviour changes (no API change)

No public signature, struct offset or symbol changed — `dist/chitra.cyr` is
ABI-identical, so mabda and kii re-pin mechanically. But four input classes
that previously **decoded** now **reject**, deliberately. Each was producing
either wrong pixels or unbounded work, so rejection is the correction, not a
regression — listed here so consumers are not surprised:

- A single-component JPEG whose lone component has `H > 1` or `V > 1` →
  `CHITRA_ERR_UNSUPPORTED` (previously decoded to fabricated content).
- A JPEG whose declared RGBA output exceeds 4096× its file size →
  `CHITRA_ERR_DIMENSIONS` (previously decoded at unbounded, unreclaimable
  memory cost).
- A PNG carrying an unknown **critical** chunk → `CHITRA_ERR_UNSUPPORTED`
  (previously the chunk was skipped and the image rendered anyway, contrary
  to § 5.4). Unknown **ancillary** chunks are unaffected.
- A PNG with a duplicate tRNS, a post-IDAT tRNS, or a PLTE hidden behind a
  zero-length IDAT → `CHITRA_ERR_BAD_CHUNK`.

### Added

- **`fuzz/fuzz_png.fcyr` + `fuzz/fuzz_jpeg.fcyr`** — the first in-tree
  adversarial-input harnesses, run by `make fuzz` (= `cyrius fuzz`) and wired
  into `make test-all`. They assert **two** invariants, not one: *survival*
  (the decoder returns on any byte sequence) and *contract* (failure returns 0
  **and** sets `*err_out` to a non-zero `ChitraErr`; success leaves it 0). The
  second is what a crash-only fuzzer misses, and it matters because mabda maps
  `ChitraErr` straight onto `GpuErr`. Cases: random bytes, signature-prefixed
  garbage driving the chunk/marker walk, bit-flipped fixtures, full truncation
  sweeps, degenerate and negative lengths, and — for JPEG — **entropy-segment
  -only mutation** against both the hand-built 8×8 and the real ImageMagick
  16×16 gradient, so hostile bits reach the bit-reader and `DECODE` behind a
  valid header. `fuzz_jpeg` opens with a self-check asserting its fixtures
  decode and its entropy span is actually wide enough to mutate: the first
  draft silently exercised a 4-byte span, and a fuzz harness that no-ops is
  worse than none.
- **`tests/bcyr/chitra.bcyr`** — the first benchmark harness, run by
  `make bench`, closing the second v1.0 gate. It **generates its own fixtures
  at realistic sizes** rather than timing the in-tree test fixtures: those are
  2×2 to 16×16 by design, so benchmarking them would report fixed overhead
  (allocation, header parse, table build) and call it throughput. PNG fixtures
  are real scanlines run through sankoch's `zlib_compress`, so decode
  exercises the genuine inflate + unfilter path; Adam7 fixtures are
  interleaved with chitra's **own** pass-geometry helpers, so encoder and
  decoder cannot disagree about the layout. JPEG fixtures are assembled by an
  in-harness MSB-first bit writer (0xFF stuffing included) over the Annex K
  DC luminance table plus a compact AC table, emitting real DC **and** AC
  coefficients per block so `DECODE`/`RECEIVE`/`EXTEND` actually run.
  **Every generated fixture is decode-verified against the generator before
  it is timed** — a benchmark that silently measures a rejected input is
  reporting the cost of the error path. Sabotaging the generator was checked
  to abort the run and make `bench-csv.sh` refuse to record.
  Covers PNG gray8 / rgb8 / rgba8 / palette8 / rgba16 / Adam7 and JPEG
  grayscale / 4:4:4 / 4:2:2 / 4:2:0 at 256×256, plus a 16×16 fixed-cost pair.
- `scripts/bench-csv.sh` + `bench-history.csv` — stamps each result with
  timestamp / commit / branch and appends it, so the committed series is
  reproducible rather than hand-typed. `make bench-record` wraps it.
  Deliberately **not** part of `make test-all`: benchmark numbers are host-
  and load-dependent, and gating CI on them would be a flake source.
- `make fuzz` and `make bench` targets; `make lint` and `make fmt-check` now
  also cover `fuzz/*.fcyr` and `tests/bcyr/*.bcyr`.
- `CHITRA_MAX_JPEG_RATIO` (4096:1) — the JPEG analogue of the PNG path's
  `CHITRA_MAX_INFLATE_RATIO`. See *Security* below.

### Fixed

- **Depth-16 tRNS color key compared at the wrong width**
  ([`png_color.cyr`](src/png_color.cyr), color types 0 and 2). chitra reduces
  16-bit samples to their high byte, and the tRNS comparison was done at that
  reduced width — so a grayscale key of `0x1234` also keyed every sample from
  `0x1200` to `0x12FF` (and, for truecolor, 2^24 colors instead of one). The
  spec keys one exact value (§ 11.3.2). Key and sample are now both assembled
  at full 16-bit width. Depth 8 is unchanged, except that an out-of-range key
  now correctly matches nothing instead of aliasing onto its low byte.
- **Single-component JPEG scans decoded with interleaved MCU geometry**
  ([`jpeg.cyr`](src/jpeg.cyr)). T.81 § A.2 makes a one-component scan
  non-interleaved. chitra computed the interleaved geometry unconditionally;
  the two coincide only when the lone component has `H = V = 1` (what every
  real grayscale encoder emits, and what every existing fixture used). At
  `w=24, H=2` chitra pulled 4 blocks where T.81 wrote 3 — the surplus
  zero-padded by the bit reader into fabricated content, with no error raised.
  chitra does not implement the non-interleaved layout, so it now **rejects**
  with `CHITRA_ERR_UNSUPPORTED` rather than mis-rendering — the same
  defer-don't-half-implement posture as the non-baseline SOF modes.
- **`chitra_err_new` inverted its own contract on allocation failure**
  ([`error.cyr`](src/error.cyr)). The 16-byte allocation was unchecked, so on
  failure it stored through a **null pointer** and returned **0** — which every
  caller reads as *no error*, inverting the failure contract at the exact
  moment a failure must be reported, on every error path including OOM. It now
  falls back to a BSS-resident `ChitraErr` and never returns 0.
- **Entropy bit reader rejected valid files with 0xFF fill bytes**
  ([`jpeg_huffman.cyr`](src/jpeg_huffman.cyr)). T.81 § B.1.1.2 permits any
  number of `0xFF` fill bytes before a marker; the reader treated the second
  as a marker code, so a well-formed `FF FF D0` restart stream was rejected.
  The header marker walk already handled this correctly — only the entropy
  side was missing it. Both sides now collapse the run.
- **ZRL overrun reported a corrupt block as a clean decode**
  ([`jpeg_huffman.cyr`](src/jpeg_huffman.cyr)). A ZRL run past coefficient 63
  fell out of the AC loop as success, while the equivalent run overrun beside
  it was rejected. It now rejects with `CHITRA_ERR_JPEG_ENTROPY` too.
- **Marker classifier treated non-segment markers as length-bearing**
  ([`jpeg_markers.cyr`](src/jpeg_markers.cyr)). SOI, the `0x00` stuffing byte
  and the whole T.81 Table B.1 reserved range `0x02`–`0xBF` fell through to
  "skip by length", so the walk read the next two stream bytes as a segment
  length and skipped that far — a parser desync steered by attacker bytes.
  All three now reject with `CHITRA_ERR_JPEG_MARKER`.
- **PNG chunk-ordering guards were incomplete**
  ([`png_filter.cyr`](src/png_filter.cyr)): the PLTE-after-IDAT guard tested
  `idat_total > 0` and was therefore defeated by a spec-legal **zero-length
  IDAT**; and tRNS had no ordering or duplicate guard at all, so a second tRNS
  silently overwrote the first captured span and a post-IDAT tRNS was honoured
  against already-committed pixels. Both now use an explicit `seen_idat` flag
  and reject per § 5.6 / § 11.3.2.
- **Unknown critical chunks were silently skipped**
  ([`png_filter.cyr`](src/png_filter.cyr)). PNG § 5.4 requires a decoder that
  does not recognise a **critical** chunk to abort — such a chunk by definition
  changes how the image is to be interpreted. Now rejected via the ancillary
  bit with `CHITRA_ERR_UNSUPPORTED`. Unknown **ancillary** chunks stay
  skippable, and a dedicated control test asserts the image still decodes so
  this cannot silently become blanket rejection.

### Security

- **JPEG decompression-bomb cap.** The PNG path has always bounded inflate
  output against IDAT input at `CHITRA_MAX_INFLATE_RATIO`; the JPEG path had
  **no analogue**, and needs one *more* than PNG does — the entropy bit reader
  zero-pads past end-of-data, so a hostile file needs no scan payload at all
  and the declared SOF0 geometry alone drives the work. A ~150-byte file
  declaring 4096×4096 allocates ~67 MB of RGBA plus planes and runs hundreds
  of thousands of IDCT blocks; because the bump allocator never reclaims, this
  is **cumulative across decodes**, so a handful of such files exhausts a
  long-running consumer. Demonstrated empirically, not merely argued: with the
  cap disabled a 150-byte fixture decodes to a full 4096×4096 image. Now
  bounded by `CHITRA_MAX_JPEG_RATIO` (4096:1) before any plane is allocated —
  roughly 6× headroom over the most compressible real image, three orders of
  magnitude below the geometry-only bomb. A companion test asserts both real
  fixtures still decode, since a cap that rejects legitimate images would be
  worse than the bug.
- **Constant data no longer owns a failure mode.** The JPEG zig-zag map was
  built into an unchecked `alloc(512)` that wrote 64 values through a null
  pointer on failure; it now lives in BSS with no allocation at all
  ([`jpeg_idct.cyr`](src/jpeg_idct.cyr)).
- **Huffman table storage is zeroed**, matching the quant storage beside it
  ([`jpeg_markers.cyr`](src/jpeg_markers.cyr)). `JF_HUFF_PRESENT` already
  gated every selector against a table a DHT actually defined, so this closes
  an asymmetry rather than a live bug.

### Changed

- Removed the orphaned `_chitra_plte_entry_count` helper from
  [`png_color.cyr`](src/png_color.cyr) — defined, documented, and never called.
- `build/chitra_smoke` 551,320 → 559,656 bytes; `dist/chitra.cyr`
  124,651 → 133,286 bytes (3,075 lines).

## [0.3.2] - 2026-08-23

Toolchain catch-up release. No decode-path behaviour changes — the PNG and
JPEG matrices are byte-for-byte what 0.3.1 shipped; **728 assertions across
5 suites, 0 failures**.

### Changed

- cyrius pin 6.5.27 -> **6.5.35**. `lib/` re-vendored from the 6.5.35 stdlib
  snapshot (108 `.cyr` files), which clears the two drift warnings the 0.3.1
  build emitted: the shadow-lib mismatch (`patra` 1.13.0 vendored vs 1.13.8
  pinned) and the `pins 6.5.27 but cycc is 6.5.35` toolchain-drift note.
  `build/chitra_smoke` unchanged at 551,320 bytes — verified byte-identical
  when compiled by both the 6.5.27 and the 6.5.35 `cycc` against this tree.
  (The 555,416 figure the 0.3.1 entry records does not reproduce here; it
  was measured against that cut's `lib/` vendoring, not this one.)
  `dist/chitra.cyr` 124,630 -> 124,651 bytes (2,925 lines).
- Formatter reflow for 6.5.35's `cyrfmt`, which indents wrapped continuation
  lines +2 relative to the statement: `src/png_chunks.cyr`,
  `src/png_filter.cyr`, `tests/tcyr/error.tcyr`. **Whitespace only** — no
  token changed, and the suite is green before and after.

### Fixed

- `chitra_version()` returned **300** on 0.3.1 — the release bumped
  `VERSION`, `cyrius.cyml`, `CHANGELOG.md`, and `README.md` but left the
  hand-maintained packed literal in [`src/png.cyr`](src/png.cyr) at its
  0.3.0 value, so every consumer probing the version saw a release-behind
  number. Now returns **302**, and `tests/tcyr/error.tcyr` asserts it.

### Added

- `scripts/version-check.sh` (= `make version-check`) now gates
  `chitra_version()` against `VERSION`, packing `major*10000 + minor*100 +
  patch` and diffing it against the literal parsed out of `src/png.cyr`.
  This is the check that would have caught the 0.3.1 drift above; the OK
  line now names all five sources of truth. The check is pre-release-safe:
  it strips a `-rc.N` / `-beta.N` / `-alpha.N` suffix before packing (the
  release workflow's tag filter accepts those and requires `VERSION == tag`),
  and a malformed `VERSION` yields a clean `FAIL:` line rather than aborting
  the script under `set -euo pipefail`.

### Documentation

- Doc-drift sweep against the current tree. `docs/development/state.md`
  refreshed from measured numbers (it had been stuck at 0.3.0 / pin 6.2.44).
  Corrected: the `chitra_image_decode` router description, which claimed
  unrecognized bytes fall through to `chitra_png_decode` — the router
  actually tries PNG magic, then JPEG SOI, then rejects with
  `CHITRA_ERR_SIGNATURE` ([`jpeg.cyr:424`](src/jpeg.cyr)); the
  `getting-started` error-code table, which stopped at 12 and omitted every
  JPEG code 13-23, and named the success constant `CHITRA_ERR_OK` rather
  than `CHITRA_OK`; the `make test` suite list, which omitted `jpeg.tcyr`
  (203) so its counts summed to 525 rather than 728; the `[deps.chitra]`
  example, pinned at 0.3.0; two stale `src/png_chunks.cyr` line anchors in
  [`docs/adr/0002`](docs/adr/0002-security-model.md) and `SECURITY.md`
  (`:184` -> `:196`, `:210` -> `:222`); the architecture module-map include
  order, which predated the four JPEG modules; and CLAUDE.md's
  decompression-bomb checklist item, which conflated the IDAT *input*
  accumulator cap (-> `CHITRA_ERR_OOM`) with the IHDR-derived *output* size
  caps (-> `CHITRA_ERR_DIMENSIONS`).
- Stale `src/error.cyr` enum comments corrected — a drift item tracked open
  since 0.2.1. `CHITRA_ERR_INTERLACE` said "single-pass only" and
  `CHITRA_ERR_BIT_DEPTH` said "bit_depth != 8"; both are validity
  rejections, not capability limits (Adam7 and every spec-legal depth
  decode). Their `chitra_err_name` strings still read as capability limits;
  rewording them changes public output, so that is deferred to the v1.0 API
  freeze.

## [0.3.1] - 2026-08-17

### Changed

- cyrius pin 6.2.44 -> **6.5.27**, matching the rest of the AGNOS desktop stack. Build 370,776 -> 555,416 bytes; 5/5 green.

## [0.3.0] — 2026-06-27

**JFIF baseline JPEG decode.** chitra gains a full baseline JPEG decoder —
grayscale + YCbCr, 4:4:4 / 4:2:2 / 4:2:0 chroma subsampling, and restart
markers — normalizing to the same canonical RGBA8 surface PNG produces, plus a
format-sniffing `chitra_image_decode` entry. Decoder output is verified
**byte-identical to ImageMagick** on a real baseline JPEG with AC content.
Non-baseline modes (progressive, arithmetic, 12-bit, hierarchical/lossless,
CMYK) are cleanly rejected with distinct error codes. See
[`docs/proposals/jpeg-baseline-decoder.md`](docs/proposals/jpeg-baseline-decoder.md)
and [`docs/adr/0004-jpeg-decode-model.md`](docs/adr/0004-jpeg-decode-model.md).

### Added
- **JPEG marker framing (bite 1)** — `src/jpeg_markers.cyr`:
  `chitra_jpeg_check_signature` (SOI), `chitra_jpeg_scan_markers` (SOI →
  segment walk → SOS, parsing the SOF0 frame header), and a `_cur_u16_be`
  cursor helper. Non-baseline modes (progressive, arithmetic, 12-bit,
  hierarchical/lossless, 4-component CMYK) are rejected with distinct error
  codes — the defer-don't-half-implement posture. 11 new `CHITRA_ERR_JPEG_*`
  codes (13–23). `tests/tcyr/jpeg.tcyr`: +28 assertions (suite total 553).
- **JPEG SOF0 components + DQT (bite 2)** — the marker scan now parses the SOF0
  per-component sampling factors (Hi/Vi, quant-table selector, max H/V) and DQT
  quantization tables into `ChitraJpegFrame`, with the baseline security guards:
  sampling factors clamped to 1..4 (rejecting 0 — the CVE-2018-11212
  divide-by-zero), duplicate component ids rejected, and ΣHi·Vi ≤ 10 enforced
  before any MCU geometry is derived. `jpeg.tcyr`: +27 assertions (suite total 580).
- **JPEG Huffman tables (bite 3)** — new `src/jpeg_huffman.cyr`: the canonical
  Huffman decode-table representation (`mincode`/`maxcode`/`valptr`/`huffval`)
  and its construction from a DHT's BITS + HUFFVAL (ITU-T T.81 Annex C + F),
  with over-subscription rejection. `jpeg_markers.cyr` parses DHT segments
  (`Tc ∈ {0,1}`, `Th < 4`, Σcounts ≤ 256, in-bounds) and builds up to 4 DC + 4
  AC tables into frame storage. `jpeg.tcyr`: +24 assertions verifying the built
  table against the standard Annex K.3.3 DC-luminance codes (suite total 604).
- **JPEG entropy decode (bite 4)** — `jpeg_huffman.cyr` gains the entropy
  bit-reader (MSB-first, `0xFF00` byte-unstuffing, marker detection with
  zero-padding past a marker), the Annex F `DECODE` procedure, `RECEIVE`/`EXTEND`
  sign recovery, and `_jpeg_decode_block` decoding one 8×8 block's 64 zig-zag
  coefficients (DC differential + AC run/size with ZRL and EOB). `jpeg.tcyr`:
  +27 assertions including a full block decoded from a hand-encoded stream
  (suite total 631).
- **JPEG dequant + IDCT (bite 5)** — new `src/jpeg_idct.cyr`: the zig-zag→
  natural index map, dequantization, the committed libjpeg `jpeg_idct_islow`
  integer fixed-point 8×8 inverse DCT (ADR 0004), and the `+128` level-shift
  with `[0,255]` clamp. DESCALE uses signed round-to-nearest division (Cyrius
  `>>` is logical, not arithmetic). `jpeg.tcyr`: +18 assertions — zig-zag table,
  DC-only known-answers (`round(D/8)+128` with high/low clamps), and dequant
  scaling (suite total 649).
- **JPEG grayscale decode, end-to-end (bite 6a)** — new `src/jpeg.cyr` with the
  public `chitra_jpeg_decode(src, len, err_out) -> ChitraImage`. Parses the SOS
  scan header (component Td/Ta selectors; baseline Ss=0/Se=63/Ah=Al=0), runs the
  MCU loop for a single-component grayscale image (1 data unit per MCU), places
  IDCT'd 8×8 blocks into the component plane, crops to the image dimensions, and
  emits canonical RGBA8 (R=G=B=gray, A=255). `source_color_type` carries the
  JPEG sentinel `0x100 | num_components`. `jpeg.tcyr`: +17 assertions decoding a
  complete hand-built 8×8 (and cropped 5×5) grayscale JPEG to pixels (suite 666).
- **JPEG YCbCr 4:4:4 decode (bite 6b)** — `chitra_jpeg_decode` now handles
  3-component baseline JPEG with no chroma subsampling (all Hi=Vi=1): the MCU
  loop decodes Y/Cb/Cr planes (one data unit each per MCU, independent DC
  predictors), then a fixed-point full-range BT.601 YCbCr→RGB color pass
  (libjpeg jdcolor constants) emits RGBA8. `source_color_type` = `0x103`.
  `jpeg.tcyr`: +18 assertions — direct YCbCr→RGB known-answers (incl. clamp) and
  a complete hand-built 8×8 4:4:4 JPEG decoded to pixels (suite total 684).
- **JPEG chroma subsampling + restart markers (bite 7)** — the grayscale and
  4:4:4 paths are unified into one subsampling-aware `_jpeg_decode_scan` handling
  arbitrary per-component Hi/Vi: the MCU is max_h×max_v data units, each
  component decodes Hi×Vi blocks into its own subsampled plane, then box-upsamples
  to full resolution (so 4:2:2 / 4:2:0 / general sampling all work). DRI is parsed
  and RST0–7 restart intervals reset the DC predictors and byte-align the entropy
  stream (`_jpeg_br_restart`). `jpeg.tcyr`: +16 assertions — a 4:2:0 8×8 decode
  and a 16×8 restart-interval decode across two MCUs (suite total 700).
- **JPEG public API + format dispatch + real-image e2e (bite 8)** — public
  `chitra_jpeg_decode_rgba8` convenience wrapper and `chitra_image_decode`
  (signature-sniffing PNG-vs-JPEG router). `chitra_version()` → 300, `VERSION` →
  0.3.0, manifest description updated, and the JPEG `src_ctype` sentinel
  documented in `png.cyr`. `jpeg.tcyr`: +24 assertions including a real
  ImageMagick-encoded 16×16 baseline gradient decoded **byte-identical** to the
  reference (validates the real Annex K Huffman tables + AC entropy), the rgba8
  wrapper, and dispatch routing (suite total 724).
- **Hardening (bite 9)** — DC magnitude category bounded to 0..11 and AC size
  to 0..10 (8-bit baseline maxima); duplicate SOS component selector (`Cs`)
  rejected; source doc-drift comments corrected. `jpeg.tcyr`: +4 assertions
  (suite total 728).

### Security
- **First JPEG-decoder security audit**
  ([`docs/audit/2026-06-27-audit.md`](docs/audit/2026-06-27-audit.md)) —
  finder → adversarial-verify per module against the libjpeg / stb_image /
  jpeg-decoder CVE corpus. Verdict: the baseline decoder is **memory-safe**
  (no reachable out-of-bounds read/write, integer overflow, or
  divide-by-zero); all 81 guards confirmed present; the CVE-class checklist is
  fully covered (10 PRESENT, 2 N/A via baseline rejection). Two LOW
  spec-laxity items were fixed in this cut (see Hardening above); truncation
  detection and in-tree fuzz / benchmark harnesses are documented and deferred
  to v1.0.

## [0.2.1] — 2026-06-26

**Sub-byte bit depths 1/2/4 + Adam7 interlace** — completes the PNG
bit-depth/interlace matrix (a direct continuation of the 0.2.0 depth-16
work). chitra now decodes every depth × color-type × interlace combination
the PNG spec permits. The depth-8/16 non-interlaced path is unchanged
(byte-for-byte).

### Added
- **Sub-byte depths 1/2/4** for grayscale (ct0) and palette (ct3) — the
  only color types the spec permits below depth 8 (§ 11.2.2 Table 11.1).
  Samples are MSB-first packed with rows padded to a byte; grayscale scales
  to 8-bit (×255/85/17), palette indexes the PLTE. The IHDR gate now
  enforces the full validity table; ct2/4/6 at a sub-byte depth still
  reject as `CHITRA_ERR_BIT_DEPTH`.
- **Adam7 interlace** (§ 8) — the 7-pass reduced images are each filtered
  independently and deinterlaced into the same dense, byte-padded buffer
  the non-interlaced path produces, so the color pass is interlace-agnostic.
  Works for every color type/depth, including the sub-byte bit-scatter case.
- New unfilter stride is `ceil(channels*depth/8)` (≥1), and row size is
  `ceil(width*channels*depth/8)` — correct for sub-byte packing.
- Test suites split out: `tests/tcyr/subbyte.tcyr` (143 assertions —
  gray/palette at 1/2/4, multi-row padding, ct2-depth4 reject) and
  `tests/tcyr/interlace.tcyr` (35 — Adam7 cross-checked against the trusted
  non-interlaced decode for 7 color/depth/odd-dimension cases). Fixtures
  are ImageMagick-generated (independent reference codec) or python-packed
  and cross-checked against ImageMagick. Also folded in the deferred
  depth-16 ct4/ct6/ct0-tRNS fixtures from 0.2.0. Suite: **525 assertions**.

### Changed
- `chitra_version()` → 201. `ChitraPngRaw` widened 96→104B (internal —
  adds an interlace slot; not the public `ChitraImage`).
- `dist/chitra.cyr` regenerated.

### Hardened (adversarial-review follow-ups, all low-severity)
- IHDR **compression-method (byte 10) + filter-method (byte 11)** are now
  validated — anything other than method 0 (the only spec-legal value)
  rejects as `CHITRA_ERR_UNSUPPORTED` instead of silently mis-decoding.
- The color pass re-asserts the dimension caps (`MAX_DIM`/`MAX_PIXELS`)
  before its width×height multiplies — defense-in-depth so it is overflow-
  safe even on a hand-built raw (unreachable via `chitra_png_decode`, which
  caps in `parse_raw`).

### Removed
- The 0.1.0/0.2.0 `interlace`/`depth1` *rejection* tests (those inputs are
  now decoded, not rejected).

## [0.2.0] — 2026-06-26

**Bit depth 16 + kii guard-parity backport.** This is the release that
makes chitra a strict superset of kii's native PNG decoder, so kii can
adopt chitra (the "PNG re-fold") with zero capability loss. No change to
the depth-8 path — every existing decode is byte-for-byte identical.

### Added
- **16-bit decode** for color types 0/2/4/6. Each big-endian 16-bit
  sample truncates to its **high byte** on the way to canonical RGBA8 —
  the same lossy 16→8 reduction kii's terminal path used, so rendered
  output is unchanged. The IHDR gate now accepts `bit_depth ∈ {8,16}`;
  `bps = bit_depth/8` threads through the size math, the five unfilter
  predictors (`bpp = channels*bps`), and the color pass.
- `chitra_image_seen_iend(img)` — 1 if an IEND chunk closed the stream,
  0 for a tolerated clean IEND-less end (spec § 5.3). Lets a consumer
  warn while still using the pixels. Backed by a new `RAW_SEEN_IEND`
  slot on `ChitraPngRaw`.
- `chitra_image_source_color_type(img)` — the pre-normalization PNG
  color_type (0/2/3/4/6), so a consumer can report the original format
  even though pixels are normalized to RGBA8.
- `CHITRA_ERR_NO_IDAT` (12) — a structurally valid PNG with zero IDAT
  now reports this distinct code instead of collapsing into
  `CHITRA_ERR_DIMENSIONS`.
- Test fixtures + assertions for all of the above (depth-16 RGB None and
  Sub/Up-filtered, depth-16 grayscale, ct3+depth16 rejection, depth-1
  rejection, NO_IDAT, non-zero IEND, seen_iend both directions, source
  color_type). Suite: error 17→20, png 232→302.

### Changed / Hardened
- **IEND-must-be-zero-length** guard: an IEND chunk with a non-zero
  length is now rejected as `CHITRA_ERR_BAD_CHUNK` (spec § 11.2.5) —
  backported from kii (its M8 chunk-ordering FSM).
- `ChitraImage` widened 32B → 48B (seen_iend at +32, source color_type
  at +40). **ABI-additive**: width/height/pixels/channels keep their
  0.1.x offsets, so mabda's accessors are unaffected.
- `chitra_version()` re-based to `major*10000 + minor*100 + patch`
  (0.2.0 → 200); the prior comment's arithmetic was self-inconsistent.
- `dist/chitra.cyr` regenerated via `cyrius distlib`.

### Deferred (tracked)
- **0.2.1** — sub-byte depths 1/2/4 and Adam7 interlace (the remainder
  of the bit-depth matrix; a direct continuation of this depth-16 work).
  Both still reject loud today.
- **0.3+** — JPEG.

## [0.1.1] — 2026-06-26

Toolchain + dependency refresh. **No functional change to the decoder** —
the PNG → canonical RGBA8 path, security guards, and public API
(`chitra_png_decode` / `chitra_png_decode_rgba8`) are byte-for-byte the
same as 0.1.0; only the toolchain pin and vendored stdlib snapshot move.

### Changed
- Toolchain pin bumped `cyrius = "6.2.23"` → `"6.2.44"` in `cyrius.cyml`.
- `lib/` re-vendored from the 6.2.44 stdlib snapshot via `cyrius deps`.
  The snapshot is byte-identical to 6.2.23's for chitra's dep set, so
  `sankoch` stays at **2.4.4** (zlib inflate + CRC32) and `thread` is
  unchanged.
- `dist/chitra.cyr` regenerated via `cyrius distlib` (bundle header now
  reads Version 0.1.1).
- `VERSION`, `README.md`, and `CHANGELOG.md` synced to 0.1.1.
- All gates green: smoke link-check, the CPU test suites under
  `tests/tcyr/`, and `version-check`.

## [0.1.0] — 2026-06-19

First release. **chitra decodes PNG to canonical RGBA8** — a pure-Cyrius
CPU decoder with no GPU, no C shim, and no external binaries. PNG color
types 0/2/3/4/6 at bit depth 8 (grayscale, RGB, palette, grayscale+alpha,
RGBA) normalize to canonical RGBA8 via stdlib `sankoch` IDAT inflate
(RFC 1950/1951), the five unfilter predictors (None/Sub/Up/Average/Paeth),
and tRNS-driven alpha synthesis. The decoder is **security-hardened** —
every byte access is bounds-checked against the input span, CRC-32 is
verified per chunk, and the kii decompression-bomb / lying-IHDR /
dimension-ratio caps reject hostile inputs loud — and **fuzz-corpus-tested**
(the kii core it forks from is fuzz-hardened; chitra's adversarial test
fixtures cover bad-signature / truncated / CRC-mismatch / interlaced /
bomb / palette-index-OOB / out-of-bounds-tRNS rejections).

Consumed by **mabda** for `gpu_texture_load_png` (a plain `[deps.chitra]`
dist dep; `ChitraErr` is layout-compatible with mabda's `GpuErr`).

**Deferred to a later release (tracked, not silently dropped):**
- **0.2** — PNG bit depths 1 / 2 / 4 / 16, and Adam7 interlace
  (0.1.0 is single-pass, depth-8 only; all reject loud today).
- **0.3+** — **JPEG** (Huffman + IDCT + chroma upsample).

### Added
- Initial package scaffold (mabda v3.3 arc, bite **AL.P0a**). A minimal,
  green, link-checkable pure-Cyrius skeleton — **not** the PNG decoder
  yet (that lands in AL.P0b–AL.P0e):
  - `cyrius.cyml` — `name = "chitra"`, `cyrius = "6.2.23"`, GPL-3.0-only;
    `[deps].stdlib` carries the base set plus `sankoch` (zlib inflate +
    CRC32) and `thread` (sankoch's mutex pair); `[lib].modules` lists the
    include-order src chain.
  - `src/lib.cyr` — the single stdlib + domain include chain.
  - `src/error.cyr` — `ChitraErr` model: `CHITRA_OK` / `_ERR_SIGNATURE` /
    `_ERR_TRUNCATED` / `_ERR_BAD_CHUNK` / `_ERR_UNSUPPORTED` /
    `_ERR_INFLATE` / `_ERR_OOM` / `_ERR_OTHER` constants, a 16-byte
    `GpuErr`-compatible record (`chitra_err_new` / `chitra_err` /
    `chitra_err_code` / `chitra_err_detail`), and `chitra_err_name`.
  - `src/png.cyr` — stub: the planned PNG → RGBA8 API documented in the
    header, plus a live `chitra_version()` (returns 100 = 0.1.0 packed)
    so the module is non-empty and links.
  - `programs/smoke.cyr` — link-check entry proving the include chain
    (stdlib + sankoch + thread + domain modules) parses and links.
  - `tests/tcyr/error.tcyr` — CPU suite covering the error codes,
    `chitra_err_*` accessors, `chitra_err_name` round-trips, and
    `chitra_version()`.
  - `Makefile`, `scripts/version-check.sh`,
    `scripts/count-test-assertions.sh`, `.gitignore`, `README.md` —
    adapted from mabda's conventions.
- PNG byte-buffer framing + IDAT inflate + unfilter + security layer
  (mabda v3.3 arc, bite **AL.P0b**) — forked from kii's proven
  `png.cyr` core, re-shaped onto a byte-buffer cursor. Turns PNG bytes
  into inflated, unfiltered raw scanlines + the parsed IHDR (the
  AL.P0d color-pass handoff). **Not** the canonical-RGBA8 pass or the
  public `chitra_png_decode` yet (AL.P0d / AL.P0e):
  - `src/png_chunks.cyr` — a bounds-checked `(src, len)` cursor (every
    u8/u32-BE/skip validated against `len` before access), the 8-byte
    signature check, chunk-type predicates (IHDR/IDAT/IEND/PLTE/tRNS),
    color-type→channels, the kii security ceilings, and the
    `ChitraPngRaw` (96-byte) handoff struct + accessors.
  - `src/png_filter.cyr` — the five PNG unfilter predictors
    (None/Sub/Up/Average/Paeth) and `chitra_png_parse_raw`: a two-pass
    chunk walk (CRC-32 every chunk via sankoch, parse IHDR, capture
    PLTE/tRNS spans, concat IDAT, inflate with the bomb caps, unfilter
    into the scanline buffer). Every failure path returns a `ChitraErr`,
    never an OOB read.
  - `src/error.cyr` — new codes `CHITRA_ERR_CRC` / `_INTERLACE` /
    `_BIT_DEPTH` / `_DIMENSIONS` / `_FILTER` + names.
  - Security guards ported from kii: lying-IHDR / dimension caps,
    decompression-bomb ratio cap, CRC-mismatch + truncated-stream
    rejection. Adam7 interlace and bit depths != 8 reject loud
    (tracked: chitra 0.2 / AL.P0d).
  - `tests/tcyr/png.tcyr` — 95 CPU assertions: cursor bounds, signature,
    Paeth + all five unfilter predictors, three embedded-byte-array
    fixtures (rgba8 2x2 None, rgb8 2x2 Sub+Up, rgba8 1x1 Paeth — raw
    bytes asserted exactly), and five adversarial rejections
    (bad-signature, truncated, CRC-mismatch, interlaced, bomb).
- Canonical-RGBA8 color-normalization pass + the public PNG decoder
  (mabda v3.3 arc, bite **AL.P0d**) — completes chitra's PNG → RGBA8
  path for bit depth 8. Consumes a `ChitraPngRaw` and emits an owned
  RGBA8 `ChitraImage`:
  - `src/png_color.cyr` — `chitra_png_color_to_rgba8(raw, src, len,
    err_out)`: the genuinely new code over kii (kii emits native
    channels / palette indices for the terminal path; chitra normalizes
    to canonical RGBA8 + synthesizes alpha from tRNS). Handles all five
    color types at depth 8 — grayscale(0) → (g,g,g,255), RGB(2) →
    (r,g,b,255), palette(3) → PLTE RGB + per-entry tRNS alpha,
    grey+alpha(4) → (g,g,g,a), RGBA(6) passthrough — with tRNS keying
    for types 0/2 (matching gray / RGB → alpha 0). PLTE/tRNS are read
    from the original `src` via the (offset, length) spans the parse
    driver captured (no struct widening; documented in the module
    header), re-validated against `(src, len)` defensively.
  - `src/png.cyr` — replaces the stub with the public API:
    `chitra_png_decode(src, len, err_out)` → `ChitraImage*` (parse_raw +
    the color pass), `chitra_png_decode_rgba8(src, len, w_out, h_out)`
    convenience, `chitra_image_free` (documented bump-allocator no-op),
    plus the 32-byte `ChitraImage` struct (`width` / `height` / `pixels`
    (owned RGBA8 w*h*4) / `channels` = 4) + accessors. `chitra_version`
    retained.
  - `src/lib.cyr` + `cyrius.cyml` `[lib].modules` — wire `png_color.cyr`
    between `png_filter.cyr` and `png.cyr`.
  - New reject paths: palette index ≥ PLTE entry count → `BAD_CHUNK`;
    color_type 3 with no/short PLTE → `BAD_CHUNK`; tRNS span out of
    `(src, len)` bounds or wrong length for the color type → `BAD_CHUNK`.
    The AL.P0b rejects (interlace / bit-depth / bombs / CRC / truncation)
    stay intact.
  - `tests/tcyr/png.tcyr` — grows to 232 CPU assertions: one
    embedded-byte-array fixture per color type 0/2/3/4/6 at depth 8
    decoded end-to-end with pixel-exact RGBA8 (ground truth from a
    reference re-decode of the same bytes), a palette+tRNS fixture
    (per-entry alpha), grayscale+tRNS and RGB+tRNS keyed-color fixtures
    (keyed pixel → alpha 0), the `_rgba8` convenience wrapper, and a
    palette-index-out-of-range adversarial reject.

### Notes
- The four `### Added` blocks above are the per-bite (AL.P0a → AL.P0d)
  build provenance; the summary at the top of this entry is the shipped
  0.1.0 surface. Deferred work (bit depths 1/2/4/16 + Adam7 → 0.2; JPEG
  → 0.3+) is listed under the summary.
