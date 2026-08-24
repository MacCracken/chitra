# 0009 — A 3-component JPEG is not necessarily YCbCr

**Status**: Accepted
**Date**: 2026-08-24

## Context

Through 0.6.0 chitra treated every 3-component baseline JPEG as YCbCr and
applied the BT.601 inverse unconditionally. That is right for the overwhelming
majority of JPEGs and wrong for a class that a standard encoder produces on
request.

`cjpeg -rgb` (libjpeg-turbo ≥ 1.4) writes a baseline SOF0 file whose three
components **are RGB**: component ids `'R'`, `'G'`, `'B'` (0x52/0x47/0x42), an
Adobe APP14 segment declaring `transform = 0`, and no JFIF APP0. chitra skipped
every APPn marker, so it never saw the declaration, applied the colour
transform anyway, and returned a hue-rotated image **with no error raised**.

Measured on a 24×16 fixture: **1,149 of 1,536 bytes wrong, maximum delta 235**.
A pixel that should be `(20, 20, 200)` — blue — came back `(121, 6, 0)`, dark
red. `djpeg` and ImageMagick both read the file correctly.

This is the wrong-output class the [0.5.3 audit](../audit/2026-08-24-audit.md)
identified as the most serious kind of defect this project ships, and the one
its own principle says fuzzing cannot see: nothing crashes, nothing is
out of bounds, and every guard passes.

## Decision

**chitra determines the colour space of a 3-component frame, in this order:**

1. **An Adobe APP14 `transform` value, if the file carries one.** It is an
   explicit statement by the encoder, so nothing overrides it. `0` = RGB,
   `1` = YCbCr.
2. **Otherwise the SOF0 component ids.** `'R','G','B'` names the space
   outright. This is libjpeg's own fallback, and it is what still identifies an
   RGB file whose APP14 was stripped by a metadata tool.
3. **Otherwise YCbCr** — the JFIF default, and what component ids 1, 2, 3 mean.

**An Adobe `transform` other than 0 or 1 is declined**
(`CHITRA_ERR_UNSUPPORTED`), not guessed at. Value 2 is YCCK, which occurs only
on the 4-component frames chitra already refuses; anything above 2 is
undefined. Assuming YCbCr for an unrecognised value is *precisely* the guess
that produced the defect this parser exists to fix, so the parser does not
repeat it in a smaller form.

**The result reports which space it decoded**: `source_color_type` gains
`0x113` for RGB, alongside `0x101` grayscale and `0x103` YCbCr. Without it an
Adobe `transform=0` file would report `0x103` and a consumer would be told
"YCbCr" about an image chitra deliberately applied no transform to.

## Consequences

**Positive**

- A file class that decoded to garbage now decodes byte-identically to
  `djpeg -nosmooth`, with ImageMagick agreeing byte-for-byte as a second
  oracle. Measured: 1,149 differing bytes → **0**.
- APP14 is now parsed rather than skipped, which is a precondition for ever
  handling YCCK or Adobe CMYK deliberately instead of by omission.

**Negative**

- `source_color_type` returns a value no consumer has seen before. It is
  additive — `0x101` and `0x103` are unchanged — but a consumer switching
  exhaustively on it needs a case, and one switching on `0x103` to mean
  "3-component JPEG" must switch on the low nibble instead.
- chitra now rejects a file it previously decoded: an Adobe segment declaring
  `transform >= 2`. That file decoded to garbage before, so this is a
  correction rather than a regression, but it *is* a behaviour change.

**Neutral**

- The component-id fallback is a heuristic, not a spec rule — T.81 says nothing
  about colour spaces. It is libjpeg's heuristic, chosen for compatibility with
  the decoder ecosystem rather than derived from the standard, and the code
  says so.

## Alternatives considered

- **Reject Adobe `transform=0` instead of decoding it.** Rejected. The
  defer-don't-half-implement posture of [ADR 0004](0004-jpeg-decode-model.md)
  exists to stop chitra *mis-rendering*; it should not stop it rendering
  correctly. The transform to apply here is the identity — refusing a file
  whose correct decode costs three `store8` calls would be the posture applied
  one notch too far, exactly as ADR 0005 records for animated GIFs.
- **Trust the component ids alone and not parse APP14.** Rejected: it inverts
  the authority. An encoder that declares `transform=1` while using ids
  `'R','G','B'` is telling you the samples are YCbCr, and the ids are then a
  naming accident. A test pins that ordering.
- **Infer from the absence of JFIF APP0.** Rejected as too weak — plenty of
  ordinary YCbCr JPEGs carry no JFIF header (EXIF-only files, for one).
- **Add a new error code for an unsupported colour transform.** Rejected;
  `CHITRA_ERR_UNSUPPORTED` already means "valid file, feature chitra declines",
  which is exactly this.

## References

- Adobe Technical Note 5116, *Supporting the DCT Filters in PostScript Level 2*
  — the APP14 `Adobe` segment layout and the `transform` field.
- ITU-T T.81 § B.2.4.6 (APPn segments carry application data the decoder may
  skip) — which is why this is a convention question rather than a spec one.
- [`0004-jpeg-decode-model.md`](0004-jpeg-decode-model.md) — the posture this
  decision deliberately does not extend to a decodable file.
- [`../audit/2026-08-24-audit.md`](../audit/2026-08-24-audit.md) — the
  silent-wrong-output class this defect belongs to.
