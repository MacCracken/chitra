# chitra — Roadmap

> **Last Updated**: 2026-10-15 (1.1.2)
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

- **Patch (1.1.x)** — repairs, hardening, gates, docs. Nothing that decodes
  today may decode differently except to move *toward* the reference decoder.
- **Minor (1.x.0)** — widens what decodes or adds an entry point. Additive by
  construction: nothing frozen is renamed, removed or re-laid-out. Each one gets
  an ADR (or an amendment) when it reverses a recorded decision.
- **Major (2.0.0)** — anything that changes a frozen name, signature, record
  layout or documented behaviour. **Nothing is planned for it.** The items that
  would need it are listed under [Needs a major](#needs-a-major) so they are not
  mistaken for minor work.

Every release runs the closeout pass in [`CLAUDE.md`](../../CLAUDE.md#closeout-pass-before-every-minormajor-bump);
the ones below name only what is specific to them.

## 1.1.x — maintenance

Patch-sized, independent, any order. The 1.1.1 P(-1) sweep
([audit](../audit/2026-10-15-audit.md)) closed the lock gate, the lint
deferrals and the anchor checker that used to be listed here.

- **Prefix the 84 unprefixed internal functions.** 1.1.2 closed cc-13 for
  globals; functions have the same exposure. `_jpeg_*`, `_bmp_*`, `_cur_*`,
  `_gif_*`, `_chunk_*`, `_adam7_*` and `_png_*` helpers are all in the bundle with
  no chitra prefix, and a consumer function of the same name **replaces**
  chitra's — measured at 1.1.2, a consumer `_jpeg_descale` made a JPEG decode to
  different pixels with only a "duplicate fn … last definition wins" warning.
  Rename them `_chitra_*`, extend `check-surface.sh`'s prefix gate to `^fn`, and
  extend `tests/tcyr/namespace.tcyr` with consumer functions of the old names.
  None is frozen. One patch, nothing else in it.
- **A CI consumer-shape leg for the sankoch floor.** chitra's own build links
  sankoch 2.8.7, but a consumer's bundle wins, and below 2.8.6 PNG inflate
  accepts streams zlib refuses (audit C-26). A job that builds `png.tcyr` in the
  stdlib-`sankoch` shape on the oldest toolchain the guide recommends would catch
  a floor that regresses. It would fail on 6.7.9's stdlib today, by design.
- **Three fuzz paths still unreached**: PNG's unknown-critical-chunk abort and
  `CHITRA_ERR_INFLATE_LIMIT`, and BMP's post-decode RLE amplification cap. Same
  method as 1.1.1's C-8: a fixture per path, proven by an exit-on-entry probe.
- **A `bench-history.csv` row per release.** The last row is 1.0.0's. Record
  1.1.1 from its commit (the script stamps `HEAD`), then keep one per tag.
- **Downstream consumers green on 1.1.x.** All five — mabda, kii, jalwa,
  aethersafha, crab — pin `1.0.3`. Re-pinning needs no manifest change: crab
  picks up the `zlib` profile transitively, kii / mabda / aethersafha keep the
  stdlib `sankoch` they declare, jalwa keeps its own `[deps.sankoch]`. ⚠ Three
  things to check while re-pinning: kii's error mapping (a second IHDR now
  arrives as `PNG_ERR_HEADER`, a sankoch OOM as `PNG_ERR_IDAT_TOO_LARGE`); the
  sankoch floor for the three stdlib-leaf consumers (cyrius ≥ 6.7.11, or their own
  `[deps.sankoch]` ≥ 2.8.6); and mabda's `gpu_texture_load_png` build, the one
  that matters most and is unverified from here.
- **Rename the 45 internal `chitra_*` functions to `_chitra_*`** — optional.
  Non-breaking by construction (none is frozen), but it touches every test call
  site and the surface manifest, so it is its own patch or nothing.

## 1.2.0 — PNG past 16 MiB inflated

A valid PNG whose scanlines inflate past sankoch's 16 MiB
`DECOMPRESS_MAX_OUTPUT` is refused today with `CHITRA_ERR_INFLATE_LIMIT` (35)
— cheaply, from the header, but refused. That is roughly 5.6 megapixels of RGB,
so an ordinary photo saved as PNG fails. The `zlib` profile ships
`zlib_decompress_capped(src, len, dst, cap, max_output)`, which accepts a
ceiling above 16 MiB. chitra already computes the exact inflated size from IHDR
and bounds it with `CHITRA_MAX_PIXELS` / `CHITRA_MAX_RAW_BYTES` and the
inflate-ratio cap, so it can name its own ceiling.

- **Widens acceptance** — files answering code 35 start decoding — so it is a
  minor with an entry, not a swap. Code 35 stays defined (frozen); it may
  become unreachable, and the docs must then say so.
- The memory story changes with it: the worst case for a valid PNG becomes the
  pixel cap (64 MB of RGBA), not 16 MiB of scanlines. SECURITY.md and the
  byte-budget ADR 0008 must be re-read against that.

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
  unfilter path. Neither number was predictable from the code.
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
