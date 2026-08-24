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

### Applied again in 0.3.3: non-interleaved scans

The 0.3.3 audit found that a scan carrying a **single** component is
non-interleaved per T.81 § A.2 — its MCU is one data unit over the
component's own dimensions — while chitra computed the interleaved geometry
unconditionally. The two coincide exactly when the lone component has
H = V = 1, which is what every real grayscale encoder emits and what every
in-tree fixture used; they diverge as soon as H > 1 or V > 1, and the
surplus data units are zero-padded by the bit-reader into fabricated image
content with no error raised.

This ADR's decision already settled the response: chitra does not implement
the non-interleaved layout, so it **rejects** (`CHITRA_ERR_UNSUPPORTED`)
rather than mis-rendering. No new decision was required — the case is
recorded here because it is the first time the posture was applied to a
*geometry* rather than to a coding mode, and because implementing the layout
properly remains open (see
[`../development/roadmap.md`](../development/roadmap.md)).

> The paragraph above is left as written in 0.3.3. **It is superseded for
> one-component frames by the next section**: 0.6.0 implemented the layout, so
> that class now decodes.


### Revised in 0.6.0: the one-component layout is now implemented

0.6.0 **reverses** the 0.3.3 rejection above for one-component frames, and
re-affirms it for everything else. The reversal is not a change of posture — it
is what the posture asks for once the layout is actually implemented.

The reason it turned out to be cheap: for a one-component frame the sampling
factors are **inert**, not merely unused. § A.1.1's `x_i = ceil(X · H_i / H_max)`
collapses to `x_1 = X` because the lone component *is* the maximum, so forcing
the effective geometry to `H = V = 1` makes the existing interleaved loop walk
the non-interleaved layout exactly. libjpeg-turbo confirms it from the outside:
four `cjpeg` files differing only in the SOF0 sampling nibble decode to the
identical image under `djpeg`.

Two related decisions ride with it:

- **ΣH·V ≤ 10 is conditioned on `Ns > 1`**, per T.81 § B.2.3's own wording. The
  cap is not removed and does not move — it stays at the SOF0 parse, once per
  file — but it no longer rejects `cjpeg -grayscale -sample 4x4`, a file libjpeg
  writes on request and djpeg reads back.
- **Multi-scan and partially-interleaved files (`Ns < Nf`) stay deferred**, and
  the posture applies to them unchanged. Their rejection code changes from
  `CHITRA_ERR_JPEG_SOS` to `CHITRA_ERR_UNSUPPORTED`, which is this ADR's own
  vocabulary: the file is valid and chitra declines it. The measured reason for
  deferring rather than relaxing — a naive relaxation *decodes* those files, to
  a wrong image, with no error — is in
  [`0006-defer-jpeg-multiscan-resumption.md`](0006-defer-jpeg-multiscan-resumption.md).

Unchanged: progressive, arithmetic, 12-bit precision, hierarchical / lossless /
differential and 4-component CMYK all still reject with their distinct codes.
The clean-rejection set as a security control is exactly as it was.

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
