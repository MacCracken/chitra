# 0008 — The byte-budget surface as shipped: one function, one code

**Status**: Accepted
**Date**: 2026-08-24
**Supersedes the deferral in**: [0007](0007-byte-budget-surface-deferred.md)

## Context

[ADR 0007](0007-byte-budget-surface-deferred.md) deferred the byte-budget entry
point out of 0.6.0 on a measurement: a 15-byte JPEG that is refused —
correctly, permanently — still spent **22,096 bytes**, because
`chitra_jpeg_scan_markers` allocated the quantization store and all eight
Huffman records before any check could refuse the file. A probe routed through
that function would make `decode_budget(src, len, 1, &err)` spend 22 KB and
*then* report "over budget": a memory-ceiling API that is itself an exhaustion
vector on its own refusal path, on an allocator that never frees.

That ADR named the prerequisite — lazy table allocation — and reserved a
surface of roughly eight names. 0.6.1 ships the prerequisite and a surface of
**two**.

Three corrections to 0007's numbers, all re-measured on this tree:

- The refusal cost was **22,160**, not 22,096. 0.6.1's own APP14 repair grew
  `CHITRA_JPEG_FRAME_SIZE` from 320 to 384 for `JF_ADOBE_TRANSFORM`.
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
> GIF, and **144** for BMP.

What it does **not** cover, named rather than glossed:

- **Working buffers during a decode that is begun.** Those are bounded by the
  format's own caps, not by `max_bytes`. Budgeting N bounds the *output* at N;
  peak working set is a small multiple of it.
- **sankoch's allocations**, which chitra does not route: ~41 KB of one-time
  table setup on the process's first PNG decode (16,384 for the CRC-32 table,
  ~25,000 for the inflate tables), plus **32 bytes per `zlib_decompress`
  call** thereafter.
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

1. **Lazy table allocation** (`_jpeg_alloc_quant` / `_jpeg_alloc_huff`). The
   stores are allocated when a DQT or DHT first defines something, guarded by
   `== 0` so it happens at most once per frame. A table-less refusal costs 400
   bytes instead of 22,160, for *every* caller — not only budgeted ones.

   The `== 0` guard is not tidiness, it is the whole thing. A single DHT
   segment may carry up to **3,854 table definitions** (`_jpeg_huff_build`
   accepts an all-zero BITS table, so each one counts), and allocating a
   2,464-byte record per *definition* rather than one block per *frame* would
   trade a flat 22 KB refusal cost for one that **scales with file size** —
   9,496,704 bytes from a 64 KB file. Measured: with the guard, that file costs
   20,112 bytes.

2. **A structural dimension read** (`_jpeg_declared_dims`). Reading SOF0's
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
reclaim at the arena boundary — is currently unsafe for PNG
([architecture/005](../architecture/005-alloc-reset-sankoch-hazard.md)), so
without this there is no way at all to bound decode memory.

## Consequences

**Positive**

- A caller can bound untrusted decode for the first time, and the refusal path
  is genuinely cheap rather than nominally cheap.
- The lazy-allocation half benefits every caller, budgeted or not: a hostile
  flood of malformed JPEGs now costs 400 bytes each instead of 22,160.
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
