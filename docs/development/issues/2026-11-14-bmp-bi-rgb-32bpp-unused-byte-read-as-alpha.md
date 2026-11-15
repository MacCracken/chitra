# A 32-bpp BI_RGB BMP's unused fourth byte is read as alpha whenever any of it is non-zero — fixed in 1.4.0

**Status:** 🟢 **FIXED in 1.4.0** — 32-bpp `BI_RGB` is opaque; alpha is read only where a mask declares it
([ADR 0011](../../adr/0011-bmp-samples-mean-what-the-format-says.md)).
**Filed:** 2026-11-14, by **selah** (Rust → Cyrius port, M0 decode baseline: `selah/docs/development/port-parity.md`
§2 F4).
**Affects:** 32-bpp `BI_RGB` BMPs whose fourth byte is not all zero.
**Severity:** Medium. An opaque image can decode partly or wholly transparent.

## Summary

For `BI_RGB` at 32 bpp, Microsoft's `BITMAPINFOHEADER` reference says "the high byte in each DWORD is not used". The
format declares no alpha there; a file that wants alpha says so (`BI_BITFIELDS` with an alpha mask in a V3+ header,
or `BI_ALPHABITFIELDS`), and chitra already reads alpha correctly when it is declared.

For undeclared files chitra applies a heuristic (as ImageMagick does): if *any* fourth byte is non-zero, *all* of
them are alpha. So an opaque image from a writer that leaves anything but zeros in the unused byte — uninitialised
memory, a stride buffer reused from another surface — decodes with invented transparency. selah's fixture with noise
in that byte decodes with 559 of 561 pixels non-opaque.

The heuristic trades the spec's meaning for a guess about the writer. chitra's own ADR 0009 refuses exactly that kind
of guess for CMYK JPEG ("a colour-space guess chitra's own rules forbid it from making"); the same rule says an
undeclared alpha is not alpha.

## Reproduction

`selah/tests/golden/fixtures/bmp-32-rgb-33x17.bmp` (hand-written BI_RGB 32-bpp, noise in every byte): chitra's
alpha channel is the noise; per the format it is 255 everywhere. The V4 file with a declared alpha mask
(`bmp-32-v4-alpha-33x17.bmp`) decodes identically on both readings — the fix does not touch declared alpha.

## Proposed fix

At 32 bpp `BI_RGB`, ignore the fourth byte: the image is opaque. If chitra wants to keep the heuristic for files from
writers known to abuse the byte, make it an explicit opt-in (a flag, or a separate entry point), not the default
reading of a spec-conformant file.

## Consumer-side workaround

selah forces alpha to 255 after decoding when the header says `BI_RGB` / 32 bpp (its ledger row L11, from its M3),
so its output is right today. That patches the symptom in one consumer; every other chitra consumer still gets the
invented alpha, so the fix belongs here, and selah drops the guard when it lands.

## Resolution (1.4.0)

The heuristic is gone: `use_alpha` is set only by a declared alpha mask (`BI_BITFIELDS` with a V3+
header, or `BI_ALPHABITFIELDS`), so 32-bpp `BI_RGB` decodes opaque whatever its fourth byte holds.
No opt-in was added — no consumer asks for one, and it would be a new frozen name; the byte is in the
file for any consumer that wants the heuristic.

- `tests/tcyr/bmp.tcyr`: the 2×2 fixture whose fourth bytes are 255 / 128 / 64 / 0 now decodes all
  255, and a new 7×3 cell with noise in every fourth byte checks every pixel opaque and its R, G, B
  untouched. Both checked to fail against 1.3.1 (alpha came back as the byte). The V4 / V5
  declared-alpha cells are unchanged and still pass.
- This is a deliberate difference from ImageMagick, recorded in ADR 0011 and CLAUDE.md BMP rule 13.
  selah can drop its L11 guard on 1.4.0.
