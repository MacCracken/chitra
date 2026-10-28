# 0008 — The byte-budget surface as shipped: one function, one code

**Status**: Accepted
**Date**: 2026-08-24
**Supersedes the deferral in**: [0007](0007-byte-budget-surface-deferred.md)

## Context

[ADR 0007](0007-byte-budget-surface-deferred.md) deferred the byte-budget entry
point out of 0.6.0 on a measurement: a 15-byte JPEG that is refused —
correctly, permanently — still spent **22,096 bytes**, because
`_chitra_jpeg_scan_markers` allocated the quantization store and all eight
Huffman records before any check could refuse the file. A probe routed through
that function would make `decode_budget(src, len, 1, &err)` spend 22 KB and
*then* report "over budget": a memory-ceiling API that is itself an exhaustion
vector on its own refusal path, on an allocator that never frees.

That ADR named the prerequisite — lazy table allocation — and reserved a
surface of roughly eight names. 0.6.1 ships the prerequisite and a surface of
**two**.

Three corrections to 0007's numbers, all re-measured on this tree:

- The refusal cost was **22,160**, not 22,096. 0.6.1's own APP14 repair grew
  `CHITRA_JPEG_FRAME_SIZE` from 320 to 384 for `_CHITRA_JF_ADOBE_TRANSFORM`.
- Its "~336 byte" lazy floor is really **400** (frame 384 + `ChitraErr` 16).
- Its exclusion list omitted that **sankoch allocates 32 bytes per
  `zlib_decompress` call, permanently** — `br_init` at `lib/sankoch.cyr:715`,
  called unconditionally. So "the per-call sankoch cost after warm-up is zero"
  is false, and any budget that claims to cover a PNG decode exactly is wrong
  by 32 bytes a call. The contract below excludes it by name.

## Decision

**Two new public names, and no others:**

```
chitra_image_decode_budget(src, len, max_bytes, err_out) -> ChitraImage* | 0
CHITRA_ERR_BUDGET = 34
```

**The contract, stated exactly, because a memory guarantee that is not exact is
not a guarantee:**

> chitra will not **begin** a decode whose RGBA8 output would exceed
> `max_bytes`. A refusal returns `0` with `*err_out = CHITRA_ERR_BUDGET`,
> having allocated **16 bytes** — the `ChitraErr` itself — for PNG, JPEG and
> GIF, and **128** for BMP.
>
> ⚠ *Corrected at 1.1.1: this read **144** from 0.6.1 until the 2026-10-15
> sweep measured it. It has been 128 (`_CHITRA_BMP_HDR_SIZE` 112 + the 16-byte
> `ChitraErr`) since 0.5.2 — the figure was a misquote, not a regression.*

What it does **not** cover, named rather than glossed:

- **Working buffers during a decode that is begun.** Those are bounded by the
  format's own caps, not by `max_bytes`. Budgeting N bounds the *output* at N;
  peak working set is a small multiple of it.
  ⭐ *Amended 1.3.0*: "small multiple" now has a number. For PNG it is at most
  **~5× N plus the compressed size**: 16-bit RGBA holds inflated scanlines
  (2× N), unfiltered scanlines (2× N) and the output together, beside a copy of
  the IDAT data. Through 1.2.x sankoch's 16 MiB inflate default refused every
  such file above ~2 megapixels, so the multiple was never reached at size;
  1.3.0 decodes them, and a 4096×4096 RGBA16 file of 80.8 MB measured
  416,391,288 B against an N of 67,108,864. The decision stands — the budget
  is still the one bound a caller can apply from the header — but a caller
  sizing a process from N must apply the multiple.
  ⭐ *Amended 1.3.1*: ~5× N now holds only for Adam7. Non-interlaced rows are
  unfiltered in place inside the inflate buffer, so a non-interlaced PNG is at
  most ~3× N plus the compressed size: the same 80.8 MB file measures
  282,173,560 B. A 97.9 MB Adam7 RGBA16 file at 4096×4096 measures
  433,525,296 B. The compressed-size term is dropped for a file with a single
  IDAT chunk, which is inflated where it lies (201,405,384 B for the 80.8 MB
  file re-chunked that way).
- **sankoch's allocations**, which chitra does not route: ~41 KB of one-time
  table setup on the process's first PNG decode (16,384 for the CRC-32 table,
  ~25,000 for the inflate tables), plus **32 bytes per `zlib_decompress`
  call** thereafter.
  ⭐ *Amended 1.2.1*: sankoch 2.8.9, chitra's pin from 1.2.1, keeps that bit
  reader on the codec's stack, so with chitra's own sankoch a warm decode
  allocates nothing in sankoch (pinned by `png.tcyr`'s png-2 cell). The
  exclusion stays: a consumer's own sankoch wins (closest-wins) and may be older.
- **The cumulative total across calls.** The bump allocator never frees, so
  this bounds one decode, not a process.

`max_bytes <= 0` is a refusal, not "unlimited" — the reading that turns a typo
into an unbounded decode.

**A budget refusal is never a validity opinion.** A file whose header cannot be
read is *not* refused here; it is handed to the router, which reports the real
reason. This is the property that keeps the function from becoming a second
parser that can disagree with the decoder, and it is asserted by a test
(`test_budget_does_not_second_guess_validity`).

## How the refusal got cheap

Two changes, both of which stand on their own merits:

1. **Lazy table allocation** (`_chitra_jpeg_alloc_quant` / `_chitra_jpeg_alloc_huff`). The
   stores are allocated when a DQT or DHT first defines something, guarded by
   `== 0` so it happens at most once per frame. A table-less refusal costs 400
   bytes instead of 22,160, for *every* caller — not only budgeted ones.

   ⚠ *Corrected at 1.1.1: "when a DQT or DHT first defines something" was the
   intent, not the code, until the 2026-10-15 sweep.* Both parsers allocated on
   segment **entry**, ahead of every table header, so a segment that defined
   nothing (`Lq` / `Lh` = 2) or whose first header was malformed still paid the
   whole store — the 12-byte `FF D8 FF DB 00 02 FF C4 00 02 FF D9` spent all
   22,160 bytes, and the 7-byte `FF D8 FF C4 00 03 00` 20,112. The allocation now
   sits immediately before the first store, once that table's header has
   validated, so the sentence above is what the code does: an empty DQT or DHT
   costs nothing, and the guard still makes it at most once per frame.

   The `== 0` guard is not tidiness, it is the whole thing. A single DHT
   segment may carry up to **3,854 table definitions** (`_chitra_jpeg_huff_build`
   accepts an all-zero BITS table, so each one counts), and allocating a
   2,464-byte record per *definition* rather than one block per *frame* would
   trade a flat 22 KB refusal cost for one that **scales with file size** —
   9,496,704 bytes from a 64 KB file. Measured: with the guard, that file costs
   20,112 bytes.

2. **A structural dimension read** (`_chitra_jpeg_declared_dims`). Reading SOF0's
   geometry does not need the marker parser's allocations, so the budget check
   walks segments by length and reads two fields. It parses nothing, validates
   nothing, stores nothing, and allocates nothing. Without it a *well-formed*
   JPEG refused on budget would still cost 22 KB — the tables it legitimately
   defines — which is the same defect in a different disguise.

## Why two names and not eight

Every name is permanent, and this is the last patch before the v1.0 freeze.

- **`chitra_info_decode_bytes` and friends freeze *numbers*.** A number gets
  consumed *as* a number: someone sizes a pool with it. 0.6.1 itself moves the
  JPEG figure by ~21 KB. Publishing a number that the next release changes is
  worse than publishing none.
- **A `ChitraInfo` record would be a third permanent ABI object** beside
  `ChitraImage` and `ChitraErr`, under an allocator whose `free` is a
  documented no-op — so the canonical probe-then-decode pattern would leak a
  record per decode, and the record would need its own append-only rule.
- **`chitra_info_{width,height,format}` is an image-metadata query surface**
  smuggled in under a memory-ceiling ADR. Nothing in the tree needs dimensions
  before decode: mabda sizes its texture from `chitra_image_width` *after*
  decoding.
- **Per-format `_decode_budget` variants** are composable from the four
  signature predicates the caller already has.

And not zero names, because the alternative on offer — telling callers to
reclaim at the arena boundary — was, **at the time of this decision**, unsafe
for PNG ([architecture/005](../architecture/005-alloc-reset-sankoch-hazard.md)),
so without this there was no way at all to bound decode memory.

⭐ *Amended 1.0.2*: the arena boundary is safe again (sankoch 2.7.10's arena
canary, vendored at the `6.6.2` pin). That does **not** weaken this decision —
a reset bounds a loop, the budget bounds a single decode, and a caller
thumbnailing untrusted input wants both.

## Consequences

**Positive**

- A caller can bound untrusted decode for the first time, and the refusal path
  is genuinely cheap rather than nominally cheap.
- The lazy-allocation half benefits every caller, budgeted or not: a hostile
  flood of malformed JPEGs now costs 400 bytes each instead of 22,160 —
  including, since 1.1.1, malformed ones whose only tables are empty or broken.
- The surface added before the freeze is two names, both of which
  `chitra_image_decode_into` would subsume cleanly if it ever lands.

**Negative**

- The budget bounds the output, not the peak. A caller who needs a true
  high-water mark still does not have one, and the honest answer is that
  chitra cannot give one while sankoch allocates outside its accounting.
- `CHITRA_ERR_BUDGET` is the first error code that is not about the file. A
  consumer switching exhaustively on `ChitraErrCode` must add a case.

**Neutral**

- `chitra_image_decode_into` (decode into a caller-provided buffer) and an
  allocator-parameterised `chitra_image_decode_a` remain the real end states,
  and both subsume this. They stay post-freeze.

## References

- [`0007-byte-budget-surface-deferred.md`](0007-byte-budget-surface-deferred.md)
  — the deferral, its measurement, and the prerequisite this ADR discharges.
- [`../architecture/003-bump-allocator-no-free.md`](../architecture/003-bump-allocator-no-free.md)
  — why cost is cumulative, including on the rejection path.
- [`../architecture/005-alloc-reset-sankoch-hazard.md`](../architecture/005-alloc-reset-sankoch-hazard.md)
  — why the arena boundary is not the alternative.
- `tests/tcyr/budget.tcyr` — the contract as assertions, including the
  allocation-cost bounds.
