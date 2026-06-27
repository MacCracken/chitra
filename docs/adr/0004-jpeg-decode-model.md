# 0004 — JPEG decode model: baseline-only, integer, defer-don't-half-implement

**Status**: Accepted
**Date**: 2026-06-26

## Context

chitra's PNG decode path is feature-complete and the format-agnostic name
(`chitra_image_decode`) was chosen precisely so a second format could join
without a rename. The roadmap's "JPEG via 0.3+" item
([`../development/roadmap.md`](../development/roadmap.md)) is now scoping,
and a decode model must be fixed *before* the bite sequence starts —
because JPEG, unlike PNG, has a dozen distinct coding modes (baseline,
extended sequential, progressive, lossless, hierarchical, differential,
arithmetic) crossed with sample precisions (8-bit, 12-bit) and component
layouts (grayscale, YCbCr, CMYK/YCCK). Deciding which of those chitra
decodes — and how it treats the rest — is the load-bearing choice the
whole 0.3.0 arc hangs on.

Three constraints shape the decision:

1. **chitra is all-integer, deterministic, and contract-bound to a
   canonical RGBA8 buffer.** The same posture that governs PNG
   ([`0002-security-model.md`](0002-security-model.md)): no floats (a
   float IDCT or float color transform risks cross-platform output drift
   against the byte-exact RGBA8 contract), bounded allocation, every byte
   validated at the perimeter before any allocation or loop bound depends
   on it.

2. **JPEG's most severe recent CVEs live in the non-baseline modes.**
   Progressive DC accumulation (CVE-2022-28041), 12-bit/lossless
   sample-range overflows (CVE-2023-2804), arithmetic-coding state
   machines, and Adobe APP14 CMYK color-transform overruns are precisely
   the surface chitra does not need for its texture-loader use case. Each
   mode chitra *doesn't* implement is an entire CVE class that never
   ships.

3. **chitra has a precedent for this exact call.** Before 0.2.1, chitra
   deferred Adam7 interlace rather than half-implement it, rejecting it
   cleanly with a distinct error until the full 7-pass path was ready.
   The same *defer-don't-half-implement* discipline is encoded in
   [`../../CLAUDE.md`](../../CLAUDE.md) and mirrors kii's ADR 0002. JPEG
   is where that discipline pays its largest dividend, because the
   deferred surface is both large and dangerous.

The full implementation plan — pipeline stages, four `src/jpeg_*.cyr`
modules, the eleven new error codes, the nine-bite sequence, the security
hardening checklist, the math summary, and the test plan — lives in the
proposal ([`../proposals/jpeg-baseline-decoder.md`](../proposals/jpeg-baseline-decoder.md)).
This ADR records only the model decision and the alternatives weighed.

## Decision

**0.3.0 implements JFIF baseline sequential DCT, Huffman entropy coding,
8-bit precision only — and nothing else.** Concretely:

- **Accepted**: SOF0 (baseline sequential DCT, Huffman, 8-bit), 1
  component (grayscale) or 3 components (YCbCr), chroma subsampling
  4:4:4 / 4:2:2 / 4:2:0 / general Hi×Vi, restart markers (DRI + RST0-7),
  and tolerate-and-skip handling of APPn / JFIF / EXIF / COM segments.
- **Reconstruction is integer fixed-point throughout**: a separable
  two-pass 8×8 inverse DCT with documented right-shift rounding and a
  fixed scaling (output bit-reproducible), level-shift +128 with clamp,
  and **full-range ITU-R BT.601** YCbCr→RGB in fixed-point with per-channel
  clamp. Alpha is hard-set to 255 (opaque-output contract).
- **Chroma upsampling is box/nearest replication first** — the
  conformant-simple choice; interpolated upsampling is explicitly *not*
  in 0.3.0 scope.
- **Everything else is cleanly rejected with a distinct error code**, at
  the SOF/marker dispatch, before any of its code paths exist:
  progressive (SOF2 → `CHITRA_ERR_JPEG_PROGRESSIVE`), arithmetic
  (SOF9/10/11 + DAC → `CHITRA_ERR_JPEG_ARITHMETIC`), 12-bit precision
  (→ `CHITRA_ERR_JPEG_PRECISION`), hierarchical/lossless/differential
  (SOF3/5/6/7/13/14/15 → `CHITRA_ERR_JPEG_MODE`), and 4-component
  CMYK/YCCK / Adobe APP14 (→ `CHITRA_ERR_JPEG_COMPONENTS`). SOF1
  (extended sequential, 8-bit Huffman) — although decodable on the
  baseline path — is also deferred (`CHITRA_ERR_JPEG_MODE`) to keep the
  scope a single committed mode; it is a documented upgrade candidate.

The output normalizes to the same canonical RGBA8 surface PNG emits,
reusing the 48-byte `ChitraImage` (`channels=4`), so downstream consumers
(mabda's `gpu_texture_load_png`, kii's re-fold) gain JPEG on a
`[deps.chitra]` re-pin with no API reshape. `chitra_version()` bumps
201 → 300.

The clean-rejection set is **not a feature gap — it is a primary security
control.** Rejecting these modes at dispatch removes the most severe JPEG
CVE classes from chitra before their code paths exist.

## Consequences

**Positive**:

- **Eliminated CVE classes by not decoding what it does not need.** The
  single SOF-dispatch decision forecloses progressive DC-accumulation
  (CVE-2022-28041), 12-bit/lossless sample-range (CVE-2023-2804),
  arithmetic-coding, and CMYK color-transform CVE classes — none of that
  code ships. This is the JPEG analog of the PNG model's
  "no ancillary-chunk parsing" win ([`0002-security-model.md`](0002-security-model.md)).
- **Bit-reproducible output.** Integer fixed-point IDCT + integer BT.601
  guarantee the same RGBA8 bytes on every platform, preserving the
  byte-exact decode contract that the whole AGNOS pixel pipeline relies
  on.
- **Covers the overwhelmingly common JPEG subset.** Baseline JFIF/EXIF
  with 4:2:0/4:2:2/4:4:4 is what cameras, the web, and asset pipelines
  emit in practice; the deferred modes are rare in the texture-loader use
  case.
- **No API reshape for consumers.** Same RGBA8 surface, same
  `ChitraImage`, same `ChitraErr` layout — JPEG joins via re-pin, exactly
  as the full PNG matrix did.

**Negative**:

- **Legitimate progressive / CMYK / 12-bit JPEGs are refused.** A genuine
  progressive JPEG (common for large web images) is rejected with
  `CHITRA_ERR_JPEG_PROGRESSIVE`, not decoded. For chitra's use case this
  is a deliberate, acceptable ceiling — but it is a real coverage gap a
  consumer must handle (re-encode upstream, or wait for a later arc).
- **New attack surface that PNG did not have.** chitra now owns an entropy
  bit-reader (no sankoch analog) and an attacker-controlled MCU/coefficient
  sizing path — the most fuzzer-reachable code in the crate. The proposal's
  hardening checklist and new caps
  ([`../proposals/jpeg-baseline-decoder.md`](../proposals/jpeg-baseline-decoder.md))
  are mandatory, not optional, and a fresh audit pass (bite 9) is required.
- **Box-only chroma upsampling is visibly blockier** than interpolated
  upsampling at sharp chroma edges. Accepted for 0.3.0; interpolation is a
  later refinement, not a regression.

**Neutral**:

- **SOF1 is a tracked upgrade candidate.** Extended sequential (8-bit
  Huffman) is decodable on the same path; accepting it later is a small
  follow-on, deferred now only to keep 0.3.0 a single committed mode.
- **EXIF orientation is not applied.** Output stays raw decoded RGBA8;
  surfacing orientation on `ChitraImage` is possible future work, marked
  uncertain in the proposal.
- **Each new format reopens the audit surface.** This is the JPEG
  instance of the PNG model's "new formats reopen the surface" note; the
  bite-9 audit mirrors [`../audit/2026-06-26-audit.md`](../audit/2026-06-26-audit.md).

## Alternatives considered

- **Float IDCT and/or float YCbCr→RGB.** Rejected. Simpler to write and a
  hair more accurate, but a float DCT produces platform-dependent rounding
  that breaks the byte-exact RGBA8 contract, and chitra is all-integer by
  posture ([`0002-security-model.md`](0002-security-model.md)). The
  integer separable IDCT with documented shift/rounding is deterministic
  and adequate (±1 vs a reference is the accepted tolerance).
- **Implement progressive now (single arc to "full JPEG").** Rejected.
  Progressive decode means multi-scan spectral-selection /
  successive-approximation with coefficient accumulation across scans — a
  large, stateful surface that is *also* where the most severe JPEG CVEs
  live (CVE-2022-28041). It violates smallest-first bite-discipline and
  multiplies the attack surface before the baseline path is even proven.
  Deferred with a distinct error; a candidate for a later arc.
- **C-FFI to libjpeg / libjpeg-turbo.** Rejected. It would decode every
  mode immediately and fast, but it breaks the all-Cyrius, no-C-shim,
  no-external-binary arc that defines chitra (and AGNOS), reintroduces the
  exact native-decoder CVE corpus chitra exists to avoid linking, and
  surrenders the bounded-allocation perimeter model. chitra's whole value
  is being the pure-Cyrius decode boundary.
- **Reject all chroma subsampling (4:4:4 only).** Considered to shrink the
  MCU/upsampling surface, rejected because 4:2:0 is the dominant
  real-world subsampling — refusing it would reject most camera/web JPEGs.
  The upsampling path is instead hard bounds-checked (proposal guard 14)
  rather than dropped.

## References

- [`../proposals/jpeg-baseline-decoder.md`](../proposals/jpeg-baseline-decoder.md) — full implementation plan: pipeline, modules, error codes, bite sequence, hardening checklist, math, test plan
- [`0002-security-model.md`](0002-security-model.md) — the defense-at-perimeter posture and all-integer / bounded-allocation discipline JPEG inherits
- [`../audit/2026-06-26-audit.md`](../audit/2026-06-26-audit.md) — the PNG audit whose shape the JPEG (bite-9) audit mirrors
- [`../sources.md`](../sources.md) — citation index: ITU-T T.81, integer IDCT, BT.601, zig-zag/quantization, JPEG CVE corpus
- [`0001-fork-kii-png-decoder.md`](0001-fork-kii-png-decoder.md) — the kii lineage whose defer-don't-half-implement discipline (kii ADR 0002) this mirrors
- [`../development/roadmap.md`](../development/roadmap.md) — the "JPEG via 0.3+" roadmap slot
- [`../../CLAUDE.md`](../../CLAUDE.md) — spec-only-feature-set / defer-don't-half-implement charter
- [ITU-T T.81 (JPEG)](https://www.w3.org/Graphics/JPEG/itu-t81.pdf) — baseline DCT, marker syntax, entropy decode
