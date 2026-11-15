# 0015 — The decode context: the budget governs size, and the caller can own the memory

**Status**: Accepted — amends [ADR 0008](0008-byte-budget-as-shipped.md) and [architecture/003](../architecture/003-bump-allocator-no-free.md)
**Date**: 2026-11-14

## Context

Two consumer issues filed by selah on 2026-11-14 had one cause — chitra had no
per-decode state:

- **The fixed caps fired under a budget.** `chitra_image_decode_budget(src, len,
  512 MiB, …)` still held every decode to `CHITRA_MAX_PIXELS` (4096 × 4096) and
  the 256 MB `CHITRA_MAX_RAW_BYTES`, so a 4100 × 4100 image — an 8K screenshot,
  three 4K monitors, a long page capture — was `CHITRA_ERR_DIMENSIONS` though
  its 67 MB output was far inside the budget. The caps came from kii's
  texture-loader use case.
- **Every decode's memory was lost for the life of the process.** chitra
  allocated through the global bump `alloc()` and `chitra_image_free` was a
  no-op. A server decoding one screenshot per request grows without bound:
  100 annotations of a 4K screenshot hold over 3 GB. selah's Rust version was
  audited leak-free for exactly that workload.

## Decision

**Every decode carries a context — its limits and its allocator — on the stack
of the entry point that owns it**, reached through the per-decode record each
format already threads (PNG's raw record, JPEG's frame, BMP's local, GIF's
parameter). A context of 0 is the 1.3.x defaults, and every pre-1.4.0 entry
passes 0, so nothing they decode or refuse moved.

- **Under a budget, the budget governs size**: pixels up to `max_bytes / 4`,
  single working buffers up to `~2 × max_bytes`, never below the fixed caps;
  `CHITRA_MAX_DIM` per side and every amplification ratio still apply.
- **`chitra_image_decode_budget_via(a, src, len, max_bytes, err_out)`** takes a
  stdlib `Allocator`: every allocation of the decode comes from it (zeroed, as
  the global allocator's are), every working buffer is returned before the call
  returns — all of them on a refusal — and the image record carries `a` in a new
  `alloc` field (+56; `ChitraImage` is 64 bytes), so **`chitra_image_free` frees
  the pixels and the record** for such an image. For every other image it
  remains the no-op it was. The 16-byte `ChitraErr` still comes from the global
  allocator: `chitra_err` has no allocator and no free.

## Consequences

- **Positive** — a long-running consumer can decode indefinitely in bounded
  memory, and a screenshot library can open screenshots. Concurrent decodes with
  different budgets or allocators do not interact, because nothing is global.
- **Negative** — a budgeted decode's working set scales with its budget (an
  Adam7 16-bit PNG peaks near 4× its output), so `max_bytes` must be a real
  bound, not "unlimited". A consumer must call `chitra_image_free` exactly once
  on a `_via` image, after its last use of the pixels.
- **Neutral** — a decode is limited to 64 tracked allocations (it makes ~16);
  a 65th is refused as `CHITRA_ERR_OOM` rather than leaked.

## Alternatives considered

- **A global "current allocator / current limits".** One line per entry point,
  and two concurrent decodes would corrupt each other — chitra has never shared
  mutable state between decodes.
- **Make `chitra_image_free` free every image.** A 1.3.x consumer that kept the
  pixels after calling the no-op would read freed memory.
- **Thread-local state.** A dependency with init-order constraints, for no gain
  over a stack context.
