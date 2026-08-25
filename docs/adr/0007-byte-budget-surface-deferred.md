# 0007 — The byte-budget decode surface: decided in 0.6.0, shipped in 0.6.1

**Status**: Accepted
**Date**: 2026-08-24

## Context

The roadmap committed 0.6.0 to *"a chunked-input or bounded-allocation entry
point for consumers that cannot hand over the whole encoded buffer at once, or
that need a hard memory ceiling"*, and noted — correctly — that *"this is
additive surface, so it wants an ADR"*. This is that ADR.

The motivation is real and comes from chitra's own documented behaviour. The
bump allocator never reclaims ([architecture/003](../architecture/003-bump-allocator-no-free.md)),
so decode cost is cumulative for the process; and the 0.5.3 audit closed with
an **accepted risk** stating that a caller decoding untrusted PNGs should
budget 64 MB per decode as the worst case rather than the file size. A consumer
that could say *"decode this, but not if it costs more than N bytes"* would
turn that documented hazard into an enforced one.

The obvious shape — a `chitra_image_probe` that reads headers, a
`chitra_info_decode_bytes` that predicts the cost, and a
`chitra_image_decode_budget` that refuses over budget — is the one three
independent designs converged on. It is also the one that fails on measurement.

## The disqualifying measurement

**A 15-byte JPEG that is refused, permanently and correctly, spends 22,096
bytes.** Measured on this tree with `alloc_used()` deltas:

| input | outcome | bytes spent |
|---|---|---|
| 15 B, SOF0 declaring 12-bit precision | rejected, `JPEG_PRECISION` | **22,096** |
| 2 B, SOI only | rejected, `JPEG_MARKER` | **22,096** |
| 2 B, not a JPEG at all | rejected, `SIGNATURE` | 16 |
| 32 B, PNG signature + garbage, first call | rejected, `TRUNCATED` | 16,504 |
| the same PNG call again | rejected, `TRUNCATED` | 120 |

`chitra_jpeg_scan_markers` allocates the frame record (320 B), the quantization
table store (4 × 64 × 8 = 2,048 B) and **eight Huffman table records
(8 × 2,464 = 19,712 B)** up front — before the SOF0 precision check that
refuses the file. That is ~1,473:1 amplification **on the refusal path**, and
unlike the PNG figure it is not memoized: every call pays it again.

Any probe that reaches SOF0 through that function inherits the cost. So
`chitra_image_decode_budget(src, len, 1, &err)` would spend 22 KB and *then*
report "budget exceeded" — **the API whose entire purpose is a memory ceiling
becomes a memory-exhaustion vector reachable by an attacker who only ever gets
refused.** On the Windows backend's 16 MiB reservation, ~740 refused files
exhaust the process heap.

That is the 0.5.3 BMP-RLE lesson — *a cap measured on the wrong quantity* —
recurring inside the guard built to embody it. It is not a rider to fix during
implementation; it is the design problem.

## Decision

**0.6.0 ships this decision and no public surface. The implementation lands in
0.6.1, gated on a named prerequisite.**

No `chitra_image_probe`, no `chitra_info_*`, no `chitra_image_decode_budget`,
no `CHITRA_ERR_BUDGET`. Adding eight permanent names and an error code — on a
guarantee the measurement shows is false — in the last cut before the v1.0
surface freeze, while the same cut restructures JPEG geometry, fails the house
rule of one change at a time at release granularity.

**The 0.6.1 prerequisite: the JPEG header path must be able to reach SOF0
without allocating the table stores.** The right fix is *not* a second parser —
a duplicated header parser whose divergence from the real one is precisely the
"a probe that accepts a file the decoder then refuses is a lie" failure.
It is to make the existing allocations **lazy**: allocate the quantization
store on the first DQT and each Huffman record on the DHT that defines it.
That is a contained change to one function, it drops the refusal cost from
22,096 bytes to ~336 for every caller (not only budgeted ones), and it leaves
exactly one header parser. It carries its own risk — allocation timing inside
the parser every JPEG decode uses — which is why it is a cut of its own with
the full suite and the fuzz harnesses behind it.

## The intended shape reserved in 0.6.0 — **not** what shipped

> **Superseded by [`0008-byte-budget-as-shipped.md`](0008-byte-budget-as-shipped.md).**
> 0.6.1 did re-litigate this, deliberately, and shipped **two** names rather
> than eight: `chitra_image_decode_budget` and `CHITRA_ERR_BUDGET`. The probe /
> info surface below — `chitra_image_probe`, `chitra_info_decode_bytes`,
> `chitra_info_{width,height,format}` and a `ChitraInfo` record — was
> **rejected** and exists nowhere in the tree or in the frozen 1.0.0 surface.
> The short reason: a published byte *count* gets consumed as a number, someone
> sizes a pool with it, and that very release moved the JPEG figure by ~21 KB.
> The figures quoted in this section were also re-measured. Keep reading this
> as the reasoning that got to 0.6.1, not as an API description.

- `chitra_image_probe(src, len, err_out)` → a small owned record; header parse
  only, no decode buffers.
- `chitra_info_decode_bytes(info)` → the **predicted** peak decode cost, plus
  `chitra_info_{width,height,format}` accessors.
- `chitra_image_decode_budget(src, len, max_bytes, err_out)` → decode, or `0`
  with `*err_out` set if the prediction exceeds `max_bytes`. **Refuse before
  spending**, and AND with the existing amplification caps rather than
  replacing them: a budget is a caller policy, the caps are chitra's own.
- `CHITRA_ERR_BUDGET = 34` — the next free code after `BMP_MASK = 33`. A policy
  refusal is neither `OOM` (6, "the heap is gone") nor `DIMENSIONS` (10, "the
  file is implausible"); it is "you asked me not to".
- `budget <= 0` rejects rather than meaning "unlimited".
- The contract must **name** what the budget does not cover: sankoch's one-time
  ~16.5 KB of table setup on the first PNG decode of the process is outside
  chitra's accounting entirely (see below), and saying so is what keeps the
  guarantee honest.

## Rejected, with the reasons recorded

- **An internal accounting wrapper that fails mid-decode.** Two independent
  defects. It cannot see all the bytes: sankoch allocates through the bare
  global `alloc()` and its zlib entry points take no allocator parameter, so a
  chitra-side counter misses the PNG table setup entirely. And on an allocator
  that never frees, a decode aborted at 90 % of budget has already *permanently
  spent* 90 % — the caller is refused **and** charged. An under-count sold as a
  ceiling is a guard documenting a protection you do not have.
- **A budget built on `alloc_used()` deltas.** Rejected as the mechanism, kept
  as the eventual *test*. The macOS and Windows backends serve large objects
  from a dedicated mapping **without updating the counter**, so on Windows the
  counter saturates at the reservation and stops moving while memory keeps
  being consumed — exactly the case a ceiling exists for. A budget must be a
  **prediction chitra computes**, not a measurement it reads.
- **A chunked / push-style input API.** Rejected on arithmetic. It removes only
  PNG's accumulated IDAT buffer, because every format's cost is dominated by
  the *decoded* size, not the input: for a representative decode that is 744 of
  657,280 bytes, **0.11 %**. BMP is structurally unstreamable — `data_off` is
  an attacker-controlled absolute offset, and bottom-up rows put image row 0 at
  the *end* of the data — so a four-format streaming surface would be lying
  about one of them. A chunked JPEG entry has no `len` at SOF0 time and
  therefore **deletes `CHITRA_MAX_JPEG_RATIO`'s denominator**, trading a
  shipped bomb cap for 0.1 % of memory. And sankoch's push inflate holds a
  process-wide mutex from init to finish, so a feeder would hold a global lock
  across a socket read.

## Consequences

**Positive**

- The 22,096-byte figure is now a recorded number rather than something 0.6.1
  rediscovers after freezing names around it. It is also, independently, the
  sharpest illustration in the tree of "cost is cumulative, *including on the
  rejection path*" — worth acting on for its own sake.
- The v1.0 surface stays unchanged through 0.6.0, so the freeze prerequisites
  in the roadmap are the only open surface questions.

**Negative**

- The roadmap item is answered with a decision and a schedule, not an entry
  point. A consumer wanting a memory ceiling today still has only the arena
  boundary — and per [architecture/005](../architecture/005-alloc-reset-sankoch-hazard.md)
  that boundary is currently unsafe for PNG, which is a second reason 0.6.1
  matters.

**Neutral**

- Two post-freeze end states are named but not scheduled:
  `chitra_image_decode_into` (decode into a caller-provided buffer, removing
  the largest allocation from chitra's side) and an allocator-parameterised
  `chitra_image_decode_a` built on the stdlib `Allocator` / `arena_allocator`.
  Either subsumes the budget API; neither is reachable before the ABI freeze
  settles.

## References

- [`0008-byte-budget-as-shipped.md`](0008-byte-budget-as-shipped.md) — what
  actually shipped in 0.6.1, and why it is two names rather than eight.

- [`../architecture/003-bump-allocator-no-free.md`](../architecture/003-bump-allocator-no-free.md)
  — why cost is cumulative.
- [`../architecture/005-alloc-reset-sankoch-hazard.md`](../architecture/005-alloc-reset-sankoch-hazard.md)
  — why the arena boundary is not a workaround today.
- [`../audit/2026-08-24-audit.md`](../audit/2026-08-24-audit.md) — the accepted
  PNG amplification risk this surface would let a caller enforce against, and
  the denominator lesson the naive design repeats.
- [`../development/roadmap.md`](../development/roadmap.md) — the 0.6.1 entry.
