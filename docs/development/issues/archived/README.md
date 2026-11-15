# Archived issues (chitra)

Resolved issue reports, kept for history — so the next agent, or the next
person grepping a symptom, can find the fix version without re-investigating.

**Filing a new issue?** Put it in the parent `docs/development/issues/` folder;
this folder is history only.

**Convention** — the same as the sibling repos' (`mabda`, `sankoch`,
`aethersafha`, after `cyrius`):

- The title gains a `— RESOLVED` suffix, and the status paragraph at the top
  names the fix version; a `## Resolution` section at the end says what was done
  and how it was verified.
- The file name is unchanged, so a reference by name (a consumer's ledger, a PR
  description) still finds it.
- If a resolved issue returns in a new form, open a fresh issue in the parent
  folder and cross-reference this one. Don't resurrect an archived file in place.

## Index

| File | Brief | Resolved in |
|------|-------|-------------|
| [`2026-08-31-manifest-over-declares-unused-stdlib-leaves.md`](./2026-08-31-manifest-over-declares-unused-stdlib-leaves.md) | `src/lib.cyr` included `args`, `flags` and `vec`, used nowhere, and every consumer linked them because `dist/chitra.deps` is authoritative (filed by crab). | **1.0.1** — removed. Closed structurally at **1.0.4** (cyrius 6.6.20 derives the sidecar from what the bundle references), and the sidecar is one leaf since **1.1.0**. |
| [`2026-11-14-bmp-bi-rgb-32bpp-unused-byte-read-as-alpha.md`](./2026-11-14-bmp-bi-rgb-32bpp-unused-byte-read-as-alpha.md) | A 32-bpp `BI_RGB` BMP's unused fourth byte was read as alpha whenever any of it was non-zero, so opaque files with noise there decoded transparent (filed by selah). | **1.4.0** — opaque; alpha only where a mask declares it. [ADR 0011](../../../adr/0011-bmp-samples-mean-what-the-format-says.md). |
| [`2026-11-14-bmp-sub-8-bit-replication-is-not-the-nearest-value.md`](./2026-11-14-bmp-sub-8-bit-replication-is-not-the-nearest-value.md) | Channels narrower than 8 bits were bit-replicated, up to 0.714 of a level from the exact value (filed by selah). | **1.4.0** — rounded to the nearest level; 14 five- and six-bit levels move by 1. [ADR 0011](../../../adr/0011-bmp-samples-mean-what-the-format-says.md). |
| [`2026-11-14-box-chroma-upsampling-loses-accuracy.md`](./2026-11-14-box-chroma-upsampling-loses-accuracy.md) | Box chroma upsampling (matching `djpeg -nosmooth`) was ~30 % further from the source pixels than interpolation at 4:2:0 (filed by selah). | **1.4.0** — libjpeg-turbo's fancy filters; byte-identical to `djpeg` on a 180-file corpus. [ADR 0012](../../../adr/0012-interpolated-chroma-upsampling.md). |
| [`2026-11-14-cmyk-ycck-jpeg-refused.md`](./2026-11-14-cmyk-ycck-jpeg-refused.md) | 4-component JPEG was refused outright, leaving a consumer no way to get the samples (filed by selah). | **1.4.0** — `chitra_jpeg_decode_cmyk`; byte-identical to libjpeg's `JCS_CMYK` on 124 files. [ADR 0014](../../../adr/0014-cmyk-samples-not-colours.md). |
| [`2026-11-14-every-decode-leaks-in-a-long-running-consumer.md`](./2026-11-14-every-decode-leaks-in-a-long-running-consumer.md) | Every decode's memory was lost for the life of the process (filed by selah). | **1.4.0** — `chitra_image_decode_budget_via` takes an `Allocator`, frees every working buffer, and `chitra_image_free` is real for its images. [ADR 0015](../../../adr/0015-the-decode-context.md). |
| [`2026-11-14-fixed-16-mp-cap-refuses-screenshots.md`](./2026-11-14-fixed-16-mp-cap-refuses-screenshots.md) | The fixed 4096×4096 cap refused images the caller had budgeted for (filed by selah). | **1.4.0** — under a budget the budget governs size. [ADR 0015](../../../adr/0015-the-decode-context.md). |
| [`2026-11-14-progressive-jpeg-has-a-consumer.md`](./2026-11-14-progressive-jpeg-has-a-consumer.md) | Progressive JPEG (SOF2) was refused; selah's Rust version opens these files. | **1.4.0** — decoded, byte-identical to `djpeg` on 93 files. [ADR 0013](../../../adr/0013-progressive-jpeg.md). |
