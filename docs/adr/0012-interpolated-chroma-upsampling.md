# 0012 — Interpolated ("fancy") chroma upsampling, held to `djpeg`

**Status**: Accepted — reverses the roadmap's "Out of scope: interpolated chroma upsampling"
**Date**: 2026-11-14

## Context

Through 1.3.x chitra upsampled subsampled chroma by **box** replication and
held itself to `djpeg -nosmooth`; the roadmap listed interpolated upsampling as
out of scope, for two reasons: `-nosmooth` was the oracle, and
[architecture/004](../architecture/004-jpeg-decode-pipeline.md)'s exact-fit
plane property depended on box never reading `x + 1`.

selah measured chitra against the **source pixels** each JPEG was encoded from
— ground truth, not another decoder — and box left ~30 % more mean error at
4:2:0 than interpolation (2.345 vs 1.808 on a 64×64 gradient), with a worst
pixel 78 levels off instead of 54. The 4:4:4 and grey controls were equal, so
the whole gap is the upsampler: box puts each chroma sample at the corner of
its block, JFIF sites it at the centre, and interpolation reconstructs that
siting. libjpeg's own default, zune-jpeg, Rust's `image` and ImageMagick all
interpolate. Matching a reference decoder's *option* was never the same as
decoding accurately.

## Decision

**chitra upsamples with libjpeg-turbo's fancy filters, bit for bit, and its
oracle is `djpeg` without `-nosmooth`.** Per component, by its ratio to the
frame maximum, exactly as `jdsample.c` selects:

- 2×1 (real chroma width > 2): `h2v1_fancy_upsample` — 3:1 triangle, biases 1 / 2;
- 1×2: `h1v2_fancy_upsample`;
- 2×2 (width > 2): `h2v2_fancy_upsample` — 9:3:3:1 via column sums, biases 8 / 7;
- every other ratio, and 2×1 / 2×2 at a real chroma width of 2 or less: box
  (libjpeg's `int_upsample` / plain `h2v1` / `h2v2`).

An edge sample's missing neighbour is the sample itself, and the rows above the
first and below the last **real** row are those rows — libjpeg's context-row
wraparound. Every neighbour index is clamped into the component's real
`[0, dsw) × [0, dsh)`, which every scan writes in full, so the exact-fit
property holds: the filter never reads the plane's padding.

The same release made the IDCT and colour conversion round as libjpeg does
(ties up, via a biased logical shift), so chitra is **byte-identical to
`djpeg`** on a 180-file corpus where 13 files used to differ by 1 LSB.

## Consequences

- **Positive** — subsampled JPEGs decode closer to what was encoded; chitra is
  now exact against `djpeg` and agrees with ImageMagick on subsampled files too
  (it differed there by up to 40 per byte), so the JPEG "narrowing" in
  CLAUDE.md is gone.
- **Negative** — every subsampled JPEG's output changed (toward the oracle, so
  a repair, not a break, per [ADR 0010](0010-the-v1-surface.md)'s edges). A
  consumer that wanted `-nosmooth` output has no option for it; none asked.
- **Neutral** — the upsampler is per-row, so the colour pass now holds one
  row per component rather than reading planes directly.

## Alternatives considered

- **Keep box, add fancy as an option.** An option is a new frozen name, and no
  consumer needs `-nosmooth` output; the issue offered it only as a fallback.
- **IJG libjpeg 9's DCT-domain upsampling.** Different output from
  libjpeg-turbo's (what every platform ships as `djpeg`), so not the oracle.
