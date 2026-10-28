# chitra — Roadmap

> **Last Updated**: 2026-10-28 (1.3.0)
>
> **Forward only.** What ships next, in what order, against what gates. What
> already shipped is in [`../../CHANGELOG.md`](../../CHANGELOG.md), one entry
> per release; volatile state (version, sizes, counts) is in
> [`state.md`](state.md). Neither is repeated here.
>
> **Where things stand**: the public surface is frozen at 1.0.0 — the 29 names
> in [`public-surface.md`](public-surface.md) plus both record layouts, gated by
> `scripts/check-surface.sh`. PNG, JPEG (JFIF baseline, full T.81 § A.2 scan
> model), BMP and GIF (first frame) are feature-complete for their scope.

## How a release is sized

- **Patch (1.x.y)** — repairs, hardening, gates, docs. Nothing that decodes
  today may decode differently except to move *toward* the reference decoder.
- **Minor (1.x.0)** — widens what decodes or adds an entry point, or renames or
  removes names *outside* the frozen surface (1.2.0 renamed the 46 internal
  `chitra_*` functions). Nothing frozen is renamed, removed or re-laid-out. Each one gets
  an ADR (or an amendment) when it reverses a recorded decision.
- **Major (2.0.0)** — anything that changes a frozen name, signature, record
  layout or documented behaviour. **Nothing is planned for it.** The items that
  would need it are listed under [Needs a major](#needs-a-major) so they are not
  mistaken for minor work.

Every release runs the closeout pass in [`CLAUDE.md`](../../CLAUDE.md#closeout-pass-before-every-minormajor-bump);
the ones below name only what is specific to them.

## 1.3.x — maintenance

Patch-sized, independent, any order.

- **PNG's peak working set.** 1.3.0 decodes PNGs past 16 MiB of scanlines, and
  the worst case grew with it: a 4096×4096 RGBA16 file holds the IDAT copy, the
  inflated scanlines, the unfiltered scanlines and the RGBA8 output at once —
  416,391,288 B measured for an 80.8 MB file (SECURITY.md). Two cuts would shrink
  it with no output change:
  - **Unfilter non-interlaced rows in place**, compacting them inside the
    inflate buffer. The write cursor never overtakes the read cursor (row `y`
    writes at `y*rb`, reads from `y*(rb+1)+1`), so the separate scanline buffer
    goes: up to 134 MB. Adam7 still scatters into its own buffer.
  - **Inflate the IDAT chunks where they lie**, through sankoch's streaming
    decoder, instead of concatenating them first: the compressed size again.
  Measure before and after on the 4096×4096 RGBA16 file and the 1.3.0 corpus;
  both must stay byte-identical to ImageMagick.
- **Downstream consumers green on 1.3.x.** All five — mabda, kii, jalwa,
  aethersafha, crab — pin `1.0.3`. Re-pinning needs no manifest change: crab
  picks up the `zlib` profile transitively, kii / mabda / aethersafha keep the
  stdlib `sankoch` they declare, jalwa keeps its own `[deps.sankoch]`. ⚠ Four
  things to check while re-pinning: kii's error mapping (a second IHDR now
  arrives as `PNG_ERR_HEADER`, a sankoch OOM as `PNG_ERR_IDAT_TOO_LARGE`, and its
  `PNG_ERR_INFLATE_LIMIT` arm is dead from 1.3.0); the
  sankoch floor for the three stdlib-leaf consumers (cyrius ≥ 6.7.11, or their own
  `[deps.sankoch]` ≥ 2.8.6) — ⚠ **all three are below it today**: mabda pins
  cyrius 6.7.5 (stdlib sankoch 2.8.2), kii 6.7.9 (2.8.3), aethersafha 6.6.11
  (2.8.0); mabda's `gpu_texture_load_png` build, the one that matters most and
  is unverified from here; and the memory a consumer now needs for a large PNG
  (above). Every sankoch they link has `zlib_decompress_capped`, which 1.3.0
  calls. The 1.2.0 rename touches none of them: every name any of the five calls
  is frozen.

## 1.x — candidates, not scheduled

Each needs a trigger (a consumer case, or a measurement) before it is
sequenced. Recorded so the next cut starts from a list rather than from memory.

- **SOF1 extended-sequential JPEG, 8-bit Huffman.** It differs from baseline
  only by allowing 16-bit quant tables (Pq=1) and four DC/AC table pairs, and
  libjpeg decodes it; `cjpeg` emits it at very low quality. It refuses with
  `CHITRA_ERR_JPEG_MODE` (22) — reliably only since 1.1.1, which stopped
  reporting its 16-bit quant tables as malformed first. It looks cheap — but a sweep finding is a
  hypothesis: measure against `djpeg -nosmooth` before deciding. Amends ADR 0004.
- **Multi-frame GIF** — a *separate* entry point returning a frame list,
  leaving `chitra_gif_decode` untouched ([ADR 0005](../adr/0005-gif-first-frame-only.md)).
  Needs a design for disposal methods and the frame record before any code.
- **APNG** — the same shape and the same answer as multi-frame GIF; today APNG
  decodes to its default image.
- **Progressive JPEG (SOF2)** — the one non-baseline mode with a real-world
  consumer case, and the one deferral that is genuinely open. A decode-model
  question ([ADR 0004](../adr/0004-jpeg-decode-model.md)), not a surface one:
  it needs coefficient buffering across scans, which baseline never does.
  Revisit only when a consumer demonstrably needs it.

## Needs a major

Nothing here is planned. Listed so none of it is attempted as a minor.

- **Renaming `chitra_image_seen_iend`** to match its four-format meaning (0.9.0
  kept the name deliberately; kii calls it).
- **Splitting `CHITRA_ERR_UNSUPPORTED`** into per-cause codes (0.9.0 documented
  rather than split it). Adding a code is additive — 1.0.1 added 35 in a
  patch — but changing which code an existing file returns is documented
  behaviour.
- **Re-laying-out either record**, or widening `ChitraErr` at all (it is
  layout-compatible with mabda's `GpuErr`). Appending to `ChitraImage` is not
  on this list; it is additive.

## Lessons carried forward

Findings that generalise past the release that produced them and are recorded
nowhere else in the tree. Each changed how the next cut was done.

- **A sweep finding is a hypothesis** (0.7.2). Two of that cut's five items did
  not survive contact with a reference decoder — one was a rejection rather than
  the relocation the sweep read it as, the other was a spec argument ImageMagick
  simply does not follow. The cheapest time to learn that is *before* writing the
  repair. Investigate, then decide; a declined finding is a result, not a gap.
- **Every new fuzz mode needs its own no-op proof** (0.7.3). A harness that
  exercises nothing still reports hundreds of thousands of cases "survived". The
  first cut of the PNG scanline mode was measured by error-code distribution
  before it was believed — ~99% of CRC-repaired IDAT mutations fail inflate and
  only 0.6% reach the predictors, while scanline mutation puts 69% into the
  unfilter path. Neither number was predictable from the code. 1.3.0 found the same
  thing one level down, in a single keyed case: `k % 960 == 210` was meant to
  allocate once per 960 cases, but 960 is a multiple of the 15-cell period, so
  the key fixed the cell to 1-bit grey, which the pixel cap refuses from the
  header. It never once allocated. A rare-case key inherits every modulus
  the case number is already used for.
- **Ask what the denominator is** (0.5.3). A cap must be measured on what the
  attacker *spent*, not what they supplied. The first BMP amplification cap
  divided by file size, so appending padding raised the attacker's own
  allowance; JPEG repeated the identical mistake in 0.6.1, where 16 KB of
  skipped APPn segments bought a 117 MB decode. Ask it of every future ratio
  guard, before shipping it.
- **Reachability is part of what a regression test has to prove** (0.5.3). "A
  test verified to fail against the pre-repair code" is not enough on its own if
  the guard it covers could never fire: BMP's "at least one colour channel"
  check was unreachable from the day it shipped, because defaults injected
  upstream erased exactly the condition it tested — and the CHANGELOG advertised
  it anyway. Neuter the guard and confirm a test fails.
- **A change to how samples are reduced is never local to the reduction**
  (0.7.1). When depth-16 truncation became the § 13.13 rescale, the ct2 tRNS key
  comparison broke, because it reconstructed full-width samples from the
  *reduced* ones. Anything that reconstructs an input from an output is coupled
  to the reduction, however far away it lives.
- **Where a conformance argument cannot be confirmed, follow the reference**
  (0.7.2). chitra diverges from ImageMagick where the spec is prohibitive *and*
  the result is a wrong image (PNG § 5.6 in 0.7.1). It does not diverge on a
  reading the reference declines to share — the GIF Plain Text / GCE scoping
  question read like a defect on the spec and was declined on measurement.
- **Guards that cannot fire are left out, not written down** (0.8.0). Multi-scan
  needed no scan limit and no resume tripwire: coverage is the loop bound, since
  a component decodes exactly once, so the driver terminates on the bitmask
  itself rather than on a counter standing in for it. Neither proposed guard
  could fire before coverage did, so neither was added.
- **Link the narrowest dependency that carries what you call** (1.1.0). chitra
  linked every sankoch codec to call `zlib_decompress` and `crc32`, and read the
  resulting growth as sankoch's problem. A library growing as it gains features
  is the library working; the fix was chitra's — the `zlib` profile. And a
  library must not choose a bundle *for* its consumers: chitra's
  `[deps.sankoch]` is overridden by any consumer's own (closest-wins), because
  sankoch allows one bundle per program.

- **A verifier's proposed fix is a hypothesis too** (1.1.1). Two of the
  P(-1) sweep's verified fixes were wrong as written: the § 13.13 rescale proposed
  for BMP channels wider than 8 bits moved samples *further* from ImageMagick, and
  the GIF gather cap the verifier called unreachable turned out to be the only
  bound `--poison` could see on its write index. Confirmation of the defect is not
  confirmation of the repair — measure the repair against the reference, and
  against the poisoned fuzzers, before it lands.

## Out of scope (durable scope guards)

Boundaries on what chitra is. Not deferrals — nothing above will pull from this
list.

- **Encoding** — chitra is **decode-only**. Encoded bytes → RGBA8, never the
  reverse. No PNG/JPEG/GIF/BMP writer.
- **`BI_JPEG` / `BI_PNG` inside a BMP** — refused outright
  (`CHITRA_ERR_BMP_COMPRESSION`). Honouring it would have `chitra_bmp_decode`
  re-enter `chitra_jpeg_decode` / `chitra_png_decode`, and a decoder that can
  call itself through attacker-controlled data is a recursion surface better
  declined than bounded. A consumer that holds one can extract the inner stream
  and call the inner decoder directly, keeping the recursion decision on its own
  side.
- **Non-baseline JPEG other than progressive and SOF1** (both under *1.x
  candidates*). Each rejects loud with a distinct `CHITRA_ERR_JPEG_*` code
  rather than half-decoding ([ADR 0004](../adr/0004-jpeg-decode-model.md)).
  Reclassified from "deferred" to permanent by the 0.6.1 sweep:
  - **Arithmetic-coded JPEG** (SOF9/10/11 + DAC) — a second entropy coder for
    a mode almost nothing produces.
  - **Hierarchical / lossless / differential SOF frames** (SOF3/5/6/7/13/14/15)
    — a different codec that happens to share a container.
  - **4-component CMYK / YCCK** — decoding it to RGBA requires a colour-space
    guess chitra's own rules forbid it from making
    ([ADR 0009](../adr/0009-jpeg-colour-transform.md)).
  - **12-bit sample precision** — a validity rejection wearing a capability
    label.
  - **DNL-deferred height** (SOF0 with `Y = 0`). Spec-legal per T.81 § B.2.2,
    and refused: it would make the geometry that drives every allocation depend
    on a value read *after* the data.
- **Interpolated (fancy) chroma upsampling.** chitra uses box, and
  `djpeg -nosmooth` is the oracle it matches; ImageMagick differs by up to 40
  per byte on subsampled files for that reason alone. Not a drop-in either: the
  exact-fit plane property depends on box never reading `x+1`
  ([architecture/004](../architecture/004-jpeg-decode-pipeline.md)).
- **Colour management, in every format.** gAMA / sRGB / iCCP / cHRM / sBIT on
  PNG; V4/V5 colour space, CIEXYZ endpoints, gamma, rendering intent and
  embedded ICC on BMP; APP2 ICC on JPEG — all **skipped**, samples emitted
  as-is. chitra's RGBA8 output is untagged.
- **EXIF orientation** (APP1) is neither applied nor surfaced, so a camera JPEG
  decodes in its stored orientation. Applying it is a transform. *Surfacing* it
  would be additive — `ChitraImage` is append-only
  ([`public-surface.md`](public-surface.md)), so a new field plus accessor is a
  minor with an ADR — but nothing asks for it, so it stays out.
- **ICO / CUR containers**, and bare DIBs with no `BITMAPFILEHEADER`.
- **2 bpp (Windows CE) and 64 bpp BMP**, and the `BI_CMYK` compressions.
- **The GIF pixel aspect ratio byte** — non-square-pixel GIFs render unscaled,
  which is a transform question, not a decode one.
- **Image transforms** — no crop, rotate, resize, or colour adjustment. chitra
  emits canonical RGBA8 at the source dimensions; transforms are the
  consumer's job (or a sibling like hisab / ranga).
- **Filesystem / path I/O** — chitra takes in-memory bytes `(src, len)`. It
  never opens a file, walks a directory, or touches a path.
- **GPU work** — no upload, no texture handles, no shaders. chitra is the CPU
  decode boundary; mabda / soorat own everything GPU-side. (`ChitraErr` is
  layout-compatible with mabda's `GpuErr` so a decode failure maps onto
  `GPU_ERR_IMAGE_DECODE` — that is the seam, not GPU work in chitra.)

A deferral becomes an ADR when the decision crystallizes; see
[`../adr/README.md`](../adr/README.md) for the existing record.
