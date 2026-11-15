# 0014 — CMYK and YCCK JPEG: return the samples, not a colour guess

**Status**: Accepted — amends [ADR 0009](0009-jpeg-colour-transform.md); reverses the roadmap's "CMYK / YCCK out of scope"
**Date**: 2026-11-14

## Context

ADR 0009 made chitra refuse 4-component JPEG (`CHITRA_ERR_JPEG_COMPONENTS`),
because turning CMYK into RGB needs a colour-space choice the file does not
make. selah filed on 2026-11-14 that this left a consumer no way to get the
pixels at all, though the file determines its CMYK samples completely: the
JPEG gives the component values, and the Adobe APP14 transform says whether
they are CMYK (0) or YCCK (2).

## Decision

**A new entry, `chitra_jpeg_decode_cmyk(a, src, len, max_bytes, err_out)`,
returns the file's C, M, Y, K samples** in a `ChitraImage` (4 bytes per pixel,
not RGBA). YCCK is converted to CMYK exactly as libjpeg's `ycck_cmyk_convert`
does; no APP14 or transform 0 is returned as stored; any other transform is
`CHITRA_ERR_UNSUPPORTED`. `chitra_image_source_color_type` reports which —
`0x104` (no Adobe marker), `0x144` (Adobe CMYK), `0x164` (Adobe YCCK,
converted) — so a consumer knows the Adobe inverted-CMYK convention applies.
Baseline and progressive, any sampling. A 1- or 3-component file is refused
by this entry (`CHITRA_ERR_JPEG_COMPONENTS`), and **every RGBA entry still
refuses a 4-component file**: ADR 0009's no-guess rule for RGB stands.

The entry is new, so it is born in the long-running-consumer shape
([ADR 0015](0015-the-decode-context.md)): it takes the caller's `Allocator`
(0 for the global one) and a budget, with `chitra_image_decode_budget_via`'s
contract. One name, not a CMYK pair plus a `_via` variant.

## Consequences

- **Positive** — CMYK and YCCK files have a decode path that guesses nothing;
  it matches libjpeg's own `JCS_CMYK` output byte for byte on 124 files.
- **Negative** — the frozen surface grows by a name, and a `ChitraImage` can now
  hold CMYK: its meaning depends on which entry made it (and `source_color_type`
  says so). Converting to RGB — an ICC profile in APP2, or an uncalibrated
  formula — is the consumer's work.
- **Neutral** — reading an embedded ICC profile would be colour management,
  which chitra skips in every format; it stays out of scope.

## Alternatives considered

- **Return RGB through the uncalibrated `R = C·K/255`.** A guess dressed as a
  decode; selah wanted it *labelled* approximate, which only the consumer can.
- **Decode CMYK into the existing RGBA entries with a flag.** Every existing
  consumer would render CMYK bytes as RGBA without checking the flag.
