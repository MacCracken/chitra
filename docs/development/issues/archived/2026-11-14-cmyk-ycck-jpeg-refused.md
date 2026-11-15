# CMYK and YCCK JPEGs are refused; a consumer has no way to get their pixels — RESOLVED

**Status:** 🟢 **FIXED in 1.4.0** — `chitra_jpeg_decode_cmyk` returns the samples
([ADR 0014](../../../adr/0014-cmyk-samples-not-colours.md)).
**Filed:** 2026-11-14, by **selah** (Rust → Cyrius port, M0 decode baseline: `selah/docs/development/port-parity.md`
§2 F5).
**Affects:** Adobe CMYK / YCCK JPEGs (APP14).
**Severity:** Medium for selah: an image its Rust version opened is refused.

## Summary

ADR 0009 refuses 4-component JPEG because converting CMYK to RGB needs a colour-space choice chitra will not guess.
That rule is right about the *conversion*. It does not require refusing the *decode*: the file's CMYK (or YCCK)
samples are fully determined by the JPEG and the Adobe APP14 transform flag, with no guess at all.

## Proposed fix

1. **Decode without guessing:** a 4-channel entry point (e.g. `chitra_jpeg_decode_cmyk`) that returns the CMYK
   samples, YCCK already transformed to CMYK, and reports whether the Adobe marker says the values are inverted.
   Everything here is in the file; nothing is assumed.
2. **The accurate RGB path** is the file's embedded ICC profile (APP2), where present. That is colour management,
   which chitra skips everywhere today, so it is a later step — but it is the only conversion that is *right*.
3. Until then, the consumer chooses the conversion and documents it. selah would use the conventional uncalibrated
   one for inverted Adobe CMYK (`R = C·K / 255` on the stored values), labelled as approximate, rather than refuse.

## Reproduction

`selah/tests/golden/fixtures/jpeg-enc-cmyk-33x17.jpg` (jpeg-encoder 0.6.1, CMYK with Adobe APP14).

## Consumer-side workaround

None: chitra returns nothing for these files. selah refuses them, recorded as a temporary divergence until this
lands.

## Resolution (1.4.0)

Proposal 1, as a new frozen name: `chitra_jpeg_decode_cmyk(a, src, len, max_bytes, err_out)`.

- Returns a `ChitraImage` whose 4 bytes per pixel are **C, M, Y, K**: as stored for no APP14 or Adobe
  transform 0; YCCK (transform 2) converted to CMYK exactly as libjpeg's `ycck_cmyk_convert`; any
  other transform `CHITRA_ERR_UNSUPPORTED`. Baseline and progressive, every sampling.
- The Adobe question is answered by `source_color_type`: `0x104` no Adobe marker, `0x144` Adobe CMYK
  (inverted convention — chitra returns the values as stored), `0x164` Adobe YCCK, converted.
- Byte-identical to libjpeg's own `JCS_CMYK` output on 124 files (plain CMYK, no-Adobe CMYK and YCCK
  at four samplings, baseline and progressive, 1×1 to 64×40, plus ImageMagick's YCCK writer).
- It takes the caller's `Allocator` and a budget (`chitra_image_decode_budget_via`'s contract), so it
  needs no separate `_via` variant. The RGBA entries still refuse 4 components (ADR 0009), and the
  RGB conversion — proposal 3 — stays selah's.
- `tests/tcyr/jpeg_cmyk.tcyr` (57) and a CMYK mode in `fuzz/fuzz_jpeg.fcyr`.
