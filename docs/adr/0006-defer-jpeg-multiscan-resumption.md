# 0006 — Non-interleaved JPEG: decode the one-component class, defer multi-scan

**Status**: Accepted
**Date**: 2026-08-24

## Context

T.81 § A.2 defines two orderings for a baseline scan's data units.
**Interleaved** (§ A.2.3) packs one MCU from every component in the scan;
**non-interleaved** (§ A.2.2) walks a single component's data units in raster
order, and its MCU is exactly one 8×8 data unit. chitra shipped 0.3.0 with only
the interleaved layout, and 0.3.3 made the gap explicit rather than silent: a
one-component frame declaring `H > 1` or `V > 1` was **rejected** with
`CHITRA_ERR_UNSUPPORTED` instead of mis-rendered, on the
defer-don't-half-implement posture of [ADR 0004](0004-jpeg-decode-model.md).

That rejection covered two very different things, and 0.6.0 separates them.

**The one-component frame (Nf = 1).** Its scan is non-interleaved by
definition, and the sampling factors it declares are not merely ignorable —
they are **inert**. § A.1.1 derives each component's own sample dimensions as
`x_i = ceil(X · H_i / H_max)` and `y_i = ceil(Y · V_i / V_max)`. With one
component that component *is* the maximum, so `H_1 ≡ H_max` and `V_1 ≡ V_max`
identically and both collapse to `x_1 = X`, `y_1 = Y` for **every** legal
`(H, V)` pair in 1..4. libjpeg-turbo 3.2.0 demonstrates this directly: four
`cjpeg -grayscale -sample {1x1,2x1,2x2,4x4}` files from one source image are
each 372 bytes, differ in **exactly one byte** — the SOF0 sampling nibble — and
`djpeg` decodes all four to the identical PGM.

**The multi-scan file (Ns < Nf).** Here the file really does carry several
scans, and decoding it needs machinery chitra does not have. This is not a
hypothetical class: `cjpeg -scans` and `jpegtran -scans` emit it as baseline
SOF0, and `djpeg` decodes it identically to the interleaved encoding of the
same image.

## Decision

**0.6.0 decodes the whole Nf = 1 class and defers Ns < Nf behind one named
guard.**

The Nf = 1 implementation is an **effective-geometry collapse**, not a second
decoder: `_jpeg_decode_scan` forces `max_h = max_v = 1` and `H_i = V_i = 1` for
a one-component frame, at which point the existing interleaved loop walks the
non-interleaved layout exactly — one block per MCU, raster order. Two
consequences are worth stating because they are what make the change small:

- `cpw = mcu_cols · 1 · 8 = ceil(w/8) · 8`, so the block grid covers the
  component plane **with no unwritten margin**. The last block write lands at
  offset `cpw·cph − 1` precisely. That is why this cut adds **no** plane
  zero-fill and **no** containment tripwire: with an exact fit neither could
  ever fire, and CLAUDE.md rates an unfireable guard worse than none.
- There is exactly **one** grid variable. An implementation that introduces a
  second (`grid_w` for the block count while `mcu_cols` still sizes the plane)
  has two names for one quantity, and placement silently diverges from
  count — the "bound the index, not a proxy for it" failure. The collapse
  cannot contain that bug because there is nothing to diverge.

The **ΣH·V ≤ 10 cap is conditioned on `Ns > 1`**, per T.81 § B.2.3's own
wording (*"If Ns > 1, the following restriction shall be placed on the image
components contained in the scan"*). It bounds an interleaved MCU, and a
one-component frame has none. It stays where it was — at the SOF0 parse, once
per file, before any geometry is derived from those factors. libjpeg agrees in
both directions: its encoder refuses `-sample 4x4,2x2,2x2` interleaved
("Sampling factors too large for interleaved scan") and accepts the same
factors with a non-interleaved scan script.

`Ns < Nf` rejects with **`CHITRA_ERR_UNSUPPORTED`** (4), not the
`CHITRA_ERR_JPEG_SOS` (17) it used through 0.5.3. Seventeen said *"your file is
malformed"* about a file libjpeg writes on request; four says *"chitra
declines"*, which is what is true and what the house already uses for
progressive, arithmetic, CMYK and `BI_JPEG`. No new error code: the existing
vocabulary describes this case precisely, and a cut immediately before an API
freeze should not mint codes it does not need.

## Why multi-scan is deferred rather than attempted

Not a guess — measured. With the `ns != ncomp` gate deleted and nothing else
changed, the real `cjpeg -scans` fixtures **decode**, returning a valid
`ChitraImage` with **no error** and roughly two thirds of its bytes wrong. That
is exactly the silent-mis-decode class the [0.5.3 audit](../audit/2026-08-24-audit.md)
found seven of, after four fuzz harnesses and ~2.2 M cases had passed over the
same code. A naive relaxation is strictly worse than the rejection it replaces.

What a correct implementation actually needs, all of it new:

1. **A resumable marker walk.** `chitra_jpeg_scan_markers` stops at the first
   SOS. Resumption would derive its restart offset from `_jpeg_br_pos`, which
   is a position inside *decoded content* rather than a bounds-checked header
   field — the first time in chitra's history a parser cursor is steered by
   what the entropy decoder consumed. The reader's position is unreliable in
   several states, at least three of them attacker-reachable: a planted `FF DA`
   inside entropy data latches `BR_MARKER` and freezes `BR_POS` there
   ([jpeg_huffman.cyr:157](../../src/jpeg_huffman.cyr)).
2. **Tables redefined between scans.** Real `cjpeg -scans` output declares DHT
   segments *between* scans, and its third scan carries none of its own,
   reusing the second scan's tables. So a collect-the-offsets-then-decode
   design is wrong by construction: each scan must be decoded with the table
   state in force *at that point in the file*. Huffman **pointers** must be
   re-resolved per scan while table **presence** is deliberately not reset.
3. **Per-component coverage tracking.** A file may cover a component twice or
   omit one entirely. An omitted component is **not neutral**: `Y = Cb = Cr = 0`
   through the BT.601 constants is RGB(0, 135, 0) — solid green, decoding
   cleanly and looking plausible. Full coverage must be required.
4. **A sound bound on total work.** `CHITRA_MAX_JPEG_RATIO`'s denominator is
   `len`, and scan headers are part of `len` — so more scans raise the
   attacker's own allowance. That is the same denominator defect the 0.5.3 BMP
   RLE cap had, and a per-component coverage bitmask (each component decoded at
   most once) is the honest bound.
5. **A monotonic resume offset.** `resume ≥ sos + 6 + 2·Ns ≥ sos + 8` follows
   from the SOS header's own length, so a violation is a *logic error in
   chitra*, not attacker input — the check belongs there as a tripwire, and the
   walk must reject at the resume point rather than searching forward for the
   next marker.
6. **SOF-once across resumes.** `chitra_jpeg_scan_markers` re-zeroes
   `JF_SEEN_SOF` on entry, so resumption must re-enter a walk on the *existing*
   frame or a post-scan SOF0 will redefine geometry after allocation.

That is a cut, not a bite. It should start from the verified non-interleaved
decoder 0.6.0 delivers, since a non-interleaved scan decoder handles `Ns = 1`
regardless of how many components the frame has.

## Amended 2026-08-24, before 0.8.0 implements this

A code sweep found the *Why multi-scan is deferred* list above to be incomplete
in five structural ways, and to contain one load-bearing claim that is simply
false. This ADR is the artifact 0.8.0 is built from, so the corrections go here
rather than into the release that discovers them the hard way.

**1. "It should start from the verified non-interleaved decoder 0.6.0
delivers" is FALSE.** That decoder is an *effective-geometry collapse* — it
forces `H = V = max_h = max_v = 1` — and it is correct only because with
`Nf = 1` the lone component **is** the maximum, so § A.1.1 gives `x_1 = X`. A
multi-scan file has `Nf = 3`. A non-interleaved scan there needs genuine
per-component § A.2.2 geometry: `x_i = ceil(X · H_i / H_max)`,
`y_i = ceil(Y · V_i / V_max)`, and a block grid of `ceil(x_i/8) × ceil(y_i/8)`
for that component alone. The 0.6.0 code is a special case that does not
generalise, and building on it would produce a decoder that is right for
grayscale and wrong for every subsampled colour file. **This is the biggest
correction.**

**2. Plane ownership is not addressed.** `planes[32]` is function-local to
`_jpeg_decode_scan`, and the `alloc(cpw * cph)` that fills it happens inside
that function. A per-scan driver that simply calls it once per scan would
re-allocate every plane per scan and discard the previous scan's samples. That
function currently owns **five** responsibilities that have to be separated —
geometry, table binding, plane allocation, the MCU loop, and the colour pass
plus `ChitraImage` build. The ADR's framing of the deferral as "isolated behind
ONE line" is true of the *rejection*; it is not true of the *implementation*.

**3. DRI between scans is not addressed.** The restart interval is read once
from the frame, but DRI is a table-specification marker legal in the misc
segment before **any** scan (§ B.2.4.4), so it can change per scan. The ADR
covers DHT between scans and stops there.

**4. EOI is rejected.** `_jpeg_marker_action` returns `CHITRA_ERR_JPEG_MARKER`
for `0xD9` unconditionally, because through 0.7.3 reaching EOI during the
header walk meant "no scan present". A resumed walk that reuses
`chitra_jpeg_scan_markers` would therefore reject the file's own end marker.

**5. The scan component list has nowhere to live.** `_jpeg_parse_sos` builds
its selector list locally and discards it; the frame has no scan-component
field; and the MCU loop iterates over **frame** components, though for a
partially-interleaved scan the MCU is composed in **scan** order. The ADR
declines to grow `CHITRA_JPEG_FRAME_SIZE` on the grounds that only a coverage
bitmask and a resume position are needed — that is 2 of the 3 free slots,
leaving one for what is really a four-entry ordered list. **Grow the record.**

**6. Td/Ta are frame-persistent.** `_jpeg_parse_sos` writes them into the frame
and nothing clears them, so a component not present in scan 2 retains scan 1's
selectors. Harmless *with* coverage tracking; a silent wrong-table decode
without it.

**And one thing this ADR gets right that a future implementer might "fix"
wrongly:** the DC predictors are correctly per-scan-local. § F.2.1.3.1 requires
them reset at each scan start, so they must **not** be hoisted to frame scope
alongside the planes.

## Two claims about this code that are FALSE, recorded so they are not repeated

Both were asserted confidently during design and both were tested.

- **"Removing `ns != ncomp` gives chitra a reachable stack overflow via
  `seencs`."** It does not. With the gate fully deleted and no replacement
  bound, `Ns = 200` — with cycling-valid selectors and with ascending-distinct
  ones — rejects cleanly. The write index advances only after a selector
  matches a *distinct* SOF component id, SOF rejects duplicate ids, and
  `ncomp ∈ {1,3}`, so the maximum index reached is 3: the last valid slot of a
  four-entry buffer. One slot from out of bounds, which is why 0.6.0 keeps
  `ns > ncomp` as a **direct** bound on that index (see below) — but not a live
  overflow, and it must not be sold as one.
- **"`_jpeg_br_restart` needs its RSTn sequence counter reset per scan."**
  There is no such counter — it accepts any of `D0..D7`. Writing that
  invariant into a doc would have a future hardening pass believe a reset
  already exists for an index it is only then starting to validate.

The genuinely reachable guard, once the equality is relaxed, is **`ns < 1`**:
an `Ns = 0` scan **decodes** to a wrong image with no error raised. It is a
wrong-output guard, not a memory-safety one, and 0.6.0 ships it because the
split into three branches makes it live today — neuter it and an `Ns = 0` file
comes back as code 4, chitra claiming it *declines* a file that is simply
broken.

`ns > ncomp` changes no error code today: with it removed such a scan reaches
the selector loop and the duplicate-Cs guard rejects it with the same 17. It is
kept anyway, and the comment says why — it is what bounds `seencs`'s write
index **directly** rather than through the proxy "distinct SOF ids run out".
Only the direct bound stays correct if `ncomp ∈ {1,3}` is ever widened.

## Consequences

**Positive**

- A spec-legal input class that chitra refused now decodes, verified
  byte-for-byte against `djpeg -nosmooth` — and, for grayscale, against
  ImageMagick as an independent second decoder.
- The change is confined to `if (ncomp == 1)` branches plus one conditioned
  cap, so a three-component file cannot reach any of it. The full suite
  confirms containment: every pre-existing assertion passes unchanged.
- The deferred class is isolated behind **one line**, which is precisely the
  line a future multi-scan cut replaces.

**Negative**

- `CHITRA_ERR_UNSUPPORTED` for `Ns < Nf` is a **behaviour change** a consumer
  could be switching on. It is the right code, but it is a change, and it is in
  the CHANGELOG's *Behaviour changes* section for that reason.
- chitra still refuses a file `djpeg` reads. The gap is now named, measured and
  scheduled instead of being folded into a validity error.

**Neutral**

- `CHITRA_JPEG_FRAME_SIZE` is deliberately **not** grown. The frame has 24
  bytes of slack and the per-component stride is full; multi-scan needs both a
  coverage bitmask and a resume position, so the slack is left for it.

## Alternatives considered

- **Relax `ns != ncomp` to `ns == 1 || ns == ncomp` without a resumable walk.**
  Rejected, and it is worse than no change: with a walk that stops at the first
  SOS, a three-scan file either rejects for an unrelated reason or decodes all
  three components out of scan 1's stream in interleaved MCU order — a fully
  decoding, plausible-looking, wrong image.
- **Implement the Nf = 1 layout with a second grid variable.** Rejected; see
  *Decision*. Two names for one quantity is how placement and count diverge.
- **Drop the ΣH·V conditioning and ship only the geometry.** Rejected: `H=4,V=4`
  is squarely inside "H > 1 or V > 1" and rejects at the SOF0 parse *before* the
  § A.2 path is reached, so the cut could not honestly claim the class. It is
  also the only fixture that discriminates in **both** grid axes at 24×16
  (non-interleaved 3×2 vs an interleaved reading of 4×4).
- **Move the ΣH·V cap into the scan header parse to make it Ns-aware.**
  Rejected: under any future multi-scan driver the planes are allocated before
  the first SOS is parsed, which would put the cap *after* the allocation it
  exists to bound — the shape of the 0.5.3 GIF finding.
- **Mint a new error code for the deferral.** Rejected; `CHITRA_ERR_UNSUPPORTED`
  already means exactly this.

## References

- ITU-T T.81 § A.1.1 (component sample dimensions), § A.2.2 (non-interleaved
  order), § A.2.3 (interleaved order), § B.2.3 (scan header, Ns and the
  ΣH·V ≤ 10 restriction), § B.2.4.4 (DRI).
- [`0004-jpeg-decode-model.md`](0004-jpeg-decode-model.md) — the
  defer-don't-half-implement posture, reversed here for Nf = 1 and re-affirmed
  for multi-scan.
- [`../architecture/004-jpeg-decode-pipeline.md`](../architecture/004-jpeg-decode-pipeline.md)
  — the pipeline and the exact-fit property.
- [`../audit/2026-08-24-audit.md`](../audit/2026-08-24-audit.md) — the
  silent-mis-decode class this deferral avoids joining.
- `tests/tcyr/jpeg_noninterleaved.tcyr` — the corpus, its provenance, and the
  regeneration recipe.
