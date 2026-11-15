# Progressive JPEG (SOF2) now has a consumer that needs it: selah — RESOLVED

**Status:** 🟢 **FIXED in 1.4.0** — progressive JPEG decodes ([ADR 0013](../../../adr/0013-progressive-jpeg.md)).
**Filed:** 2026-11-14, by **selah** (Rust → Cyrius port: `selah/docs/development/selah-port-plan.md`, ADR 0002 #2).
**Affects:** progressive JPEGs — common on the web (browsers and image optimisers write them), and so common in what
users screenshot, save and annotate.
**Severity:** Medium for selah: its Rust version opens these files, and the Cyrius port refuses them.

## Summary

selah (the AGNOS screenshot, annotation and redaction library) decodes user-supplied images for its MCP tools and
its facade (`annotate_image`, `redact_image`). Its Rust 0.30.0 decodes progressive JPEG; the Cyrius port, on chitra,
cannot. This is the demonstrated need the roadmap asks for.

The decode-model question the roadmap names (coefficient buffering across scans, ADR 0004) is the work: progressive
scans refine a whole-image coefficient buffer (spectral selection and successive approximation, T.81 Annex G), and
the IDCT runs once at the end.

## Reproduction

`selah/tests/golden/fixtures/jpeg-enc-progressive-64x64.jpg` (jpeg-encoder 0.6.1, 4:2:0, SOF2) and its source pixels
`jpeg-enc-progressive-64x64.jpg.source.rgba`. Rust's decoder reproduces it with mean / max error 1.808 / 54 against
the source — the same as the baseline 4:2:0 encoding of the same pixels, as it should be.

## Consumer-side workaround

None: selah refuses these files (ADR 0002 #2) until this lands.

## Resolution (1.4.0)

Per-component 16-bit coefficient buffers, quantization tables latched at a component's first scan, the
four Annex G scan kinds as libjpeg-turbo's `jdphuff.c`, and one IDCT pass at the end into the same planes
the baseline path fills. New module `src/jpeg_prog.cyr`.

- **Byte-identical to `djpeg` on 93 files**: cjpeg's default script at every sampling and odd / 1-pixel
  sizes, restart intervals, quality 1 and 5 (16-bit quantization tables under SOF2, now accepted),
  `jpegtran -progressive`, ImageMagick's progressive writer, and hand-written scripts down to four levels
  of successive approximation. 4:2:0 progressive like this report's fixture decodes with the same
  (interpolated) upsampling as baseline.
- The work bound is the progression, enforced (libjpeg only warns), plus at most 256 scans per file;
  each rule has a synthetic file only it refuses. A file that ends early decodes with `seen_iend = 0` if
  every component had its DC scan.
- `tests/tcyr/jpeg_progressive.tcyr` (118), and a progressive mode in `fuzz/fuzz_jpeg.fcyr`.
