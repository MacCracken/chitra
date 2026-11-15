# 0011 — BMP samples mean what the format says, not what ImageMagick does

**Status**: Accepted
**Date**: 2026-11-14

## Context

chitra's BMP path has been held to ImageMagick since 0.4.0, and in two places
that made it reproduce ImageMagick's choices rather than the file's meaning.
Both were filed by selah (a Rust → Cyrius port measuring chitra against Rust's
`image` crate) on 2026-11-14:

1. **Sub-8-bit channels were widened by bit replication.** A `w`-bit value `v`
   stands for `v / (2^w − 1)` of full scale, so its exact 8-bit value is
   `v · 255 / (2^w − 1)` and the nearest sample is that rounded. Replication
   (shift left, refill the low bits from the high ones) is an approximation of
   it, and a worse one than rounding: up to 0.677 of a level off at 5 bits and
   0.714 at 6, where rounding is never more than 0.5 off. They disagree on 4 of
   the 32 five-bit levels and 10 of the 64 six-bit ones. chitra's own code
   comment called replication "what the hardware mapping actually is" and said
   "every reference decoder" agreed; Skia and Rust's `image` round.
2. **A 32-bpp `BI_RGB` image's fourth byte was alpha whenever any of it was
   non-zero.** Microsoft's `BITMAPINFOHEADER` reference: *"the high byte in each
   DWORD is not used"*. A file that wants alpha declares an alpha mask
   (`BI_BITFIELDS` with a V3+ header, or `BI_ALPHABITFIELDS`), and chitra reads
   declared alpha correctly. The heuristic — ImageMagick's — turned an opaque
   image from a writer that leaves uninitialised memory in the byte into one
   with invented transparency: 559 of 561 pixels non-opaque in selah's fixture.

The second is the same kind of guess [ADR 0009](0009-jpeg-colour-transform.md)
refuses for an undeclared JPEG colour space.

## Decision

**A BMP sample is decoded to what the format defines it to mean.**

- A channel narrower than 8 bits rounds to the nearest 8-bit level:
  `(v · 510 + max) / (2 · max)`, `max = 2^w − 1` — PNG § 13.13's "most
  accurate" rescale. (No exact tie exists: `max` is odd.) For 1–4 and 7 bits
  this equals replication on every level; it differs on the 14 levels above.
  Channels wider than 8 bits keep 1.1.1's rule (ImageMagick's placement at the
  top of a 16-bit sample, then `round(x / 257)`), which was already measured
  against every value of 9/10/11/12/16/24-bit fields.
- 32-bpp `BI_RGB` is opaque. The fourth byte is read only as a declared alpha
  mask's channel.

## Consequences

- **Positive** — output is the nearest representation of the stored value, and
  an opaque file is never decoded transparent. The BMP rules now agree with the
  JPEG colour rule: chitra decodes declarations, not guesses about the writer.
- **Negative** — chitra now differs from ImageMagick on BMP, by exactly one
  level on those 14 sub-8-bit levels, and on 32-bpp `BI_RGB` files that really
  did store alpha in the unused byte (some old writers did). Such a file now
  decodes opaque; a consumer that knows its source abused the byte can read it
  from the file itself. CLAUDE.md's BMP hardening rule 9 and the reference
  re-verify in the closeout pass are amended accordingly.
- **Neutral** — `source_depth` is unchanged (it reports the stored width, not
  the widening method).

## Alternatives considered

- **Keep replication for ImageMagick parity.** Rejected: parity with one
  decoder's approximation is not correctness, and the PNG path already rounds
  16-bit samples (§ 13.13) rather than truncating for exactly this reason.
- **Keep the alpha heuristic behind an opt-in.** The issue suggested it. No
  consumer asks for it, and an opt-in is a new frozen name; the file's own
  bytes are available to any consumer that wants the heuristic.
