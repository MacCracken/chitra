# Box chroma upsampling reproduces a subsampled JPEG less accurately than interpolated upsampling — RESOLVED

**Status:** 🟢 **FIXED in 1.4.0** — interpolated upsampling, libjpeg-turbo's filters bit for bit, held to
`djpeg` ([ADR 0012](../../../adr/0012-interpolated-chroma-upsampling.md)).
**Filed:** 2026-11-14, by **selah** (its Rust → Cyrius port, M0 decode baseline:
`selah/docs/development/port-parity.md` §2 F1).
**Affects:** every chroma-subsampled JPEG (4:2:0, 4:2:2, 4:4:0, any `Hi,Vi` > 1) — that is, most real-world JPEGs.
**Severity:** Medium. Nothing fails; the decoded image is measurably further from the image that was encoded.

## Summary

chitra upsamples chroma by replication (box) and matches `djpeg -nosmooth`; the roadmap lists interpolated ("fancy")
upsampling as a non-goal. Matching a reference decoder's *option* is not the same as decoding accurately. Measured
against the **source pixels each JPEG was encoded from** — ground truth, not another decoder — box upsampling leaves
substantially more error than the interpolated upsampling libjpeg uses by default (and zune-jpeg, Rust's `image`):

| Fixture (source → encoder → decoder) | box (chitra 1.3.1): mean / max abs error | interpolated: mean / max |
|---|---|---|
| 64×64 gradient, 4:2:0, q85 | **2.345 / 78** | 1.808 / 54 |
| 64×64 gradient, 4:2:0, q85, restart interval 2 | **2.345 / 78** | 1.808 / 54 |
| 33×17 gradient, 4:2:0 (partial MCUs) | **5.402 / 58** | 4.062 / 47 |
| 64×64 gradient, 4:2:2 | **1.873 / 51** | 1.578 / 51 |
| 64×64 gradient, 4:4:0 | **1.991 / 47** | 1.865 / 46 |
| *control* 64×64, 4:4:4 | 1.123 / 24 | 1.121 / 24 |
| *control* 64×64 grayscale | 0.281 / 1 | 0.296 / 1 |

(RGB channels, 0–255 scale. The controls show the IDCTs are equally accurate — chitra is marginally better on
grayscale — so the whole gap is the upsampler: about 30 % more mean error at 4:2:0 and a worst pixel 78 levels off
instead of 54.)

Box replication puts every chroma sample at the corner of its 2×2 block; JFIF sites chroma at the block's centre, and
interpolation reconstructs that siting. That is why it is closer to the source.

## Reproduction

The fixtures, their source pixels and the measurement are in selah (all generated deterministically):

- `selah/tests/golden/fixtures/jpeg-enc-*.jpg` — encoded by jpeg-encoder 0.6.1 from known pixels;
- `selah/tests/golden/fixtures/<fixture>.source.rgba` — those pixels (RGBA8);
- `selah/tests/parity.tcyr` — decodes each with `chitra_image_decode_budget` and prints
  `accuracy <fixture> vs source: chitra mean … max … | rust mean … max …` (`cyrius build tests/parity.tcyr
  build/parity && ./build/parity | grep accuracy`, from the selah root).

## Proposed fix

Interpolated upsampling as the default, verified against `djpeg` **without** `-nosmooth` (libjpeg-turbo's
`h2v1` / `h2v2` "fancy" filters: 3:1 triangle weights with the edge sample replicated) and, as above, against source
pixels. The edge replication answers the `architecture/004` concern: the filter reads `x+1` only inside the plane,
and the last column / row reuses itself, so the exact-fit plane property holds. Keep box as an explicit option if a
consumer needs `-nosmooth` output.

## Consumer-side workaround

None in selah: chitra returns only the final RGBA8, not the chroma planes, so a consumer cannot re-upsample.
selah's subsampled-JPEG rows sit on its known-defect list (ledger L12) until this lands; its accuracy gate (mean
and max error against the source, no worse than the reference decoder's) is what they fail.

## Resolution (1.4.0)

`_chitra_jpeg_upsample_row` implements libjpeg-turbo's `jdsample.c` selection and arithmetic exactly:
`h2v1` / `h1v2` / `h2v2` fancy (edge samples replicated, neighbour rows clamped to the real rows), box
for every other ratio and for a real chroma width of 2 or less. Every neighbour index is clamped into
the component's real samples, so architecture/004's exact-fit property holds.

- **Byte-identical to `djpeg` (no `-nosmooth`) on a 180-file corpus** — every sampling 1x1…4x4 and
  3x1/3x2/1x3, odd and 1-pixel sizes, restart intervals, `-optimize`, `-rgb`, greyscale — after the
  same release made the IDCT round ties up as libjpeg does (13 of those files had differed by 1 LSB).
  ImageMagick now agrees on subsampled files too.
- Against source pixels (cjpeg q85 gradients): 64×64 4:2:0 mean / max 1.418 / 7 → **1.019 / 5**,
  33×17 4:2:0 3.387 / 11 → **1.405 / 7**, 4:2:2 and 4:4:0 likewise better, 4:4:4 identical.
- `tests/tcyr/jpeg_upsample.tcyr` pins each filter and each box fallback byte for byte; three suites'
  pinned sums moved to the `djpeg` values. Box was not kept as an option: no consumer needs
  `-nosmooth` output, and an option would be a new frozen name.
