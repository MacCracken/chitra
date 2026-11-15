# Every decode's memory is lost for the life of the process; a long-running consumer cannot use chitra safely — RESOLVED

**Status:** 🟢 **FIXED in 1.4.0** — `chitra_image_decode_budget_via` takes an `Allocator`, frees every working
buffer, and `chitra_image_free` is real for its images ([ADR 0015](../../../adr/0015-the-decode-context.md)).
**Filed:** 2026-11-14, by **selah** (its Rust → Cyrius port, M3: `selah/docs/development/selah-port-plan.md` §6,
ledger L16).
**Affects:** any consumer that decodes more than a bounded number of images in one process: selah's MCP server (one
decode per tool call), aethersafta (compositing), any service.
**Severity:** High for those consumers. Memory grows without bound in normal use, not only under attack.

## Summary

architecture/003 states the fact: every decode allocates its output, its working planes and its records from the
global bump allocator, and none of it is ever returned. `chitra_image_decode_budget` bounds **one** decode; its own
comment says "a caller decoding untrusted input in a loop still needs its own accounting". A consumer has no way to do
that accounting: chitra calls the global `alloc()` directly, the stdlib offers no hook to redirect it, and
`alloc_reset()` would invalidate every pointer the rest of the process holds.

What that costs selah, measured from chitra's own figures:

- a 1920×1080 screenshot → 8.3 MB of RGBA output, plus the per-component planes and scratch, **per call**;
- a 3840×2160 one → 33 MB of output per call;
- an MCP server that annotates or redacts a 4K screenshot 100 times holds over 3 GB it can never use again.

selah's Rust 0.30.0 was audited leak-free for exactly this workload (its 2026-11 sweep), so the port regresses there.

## Proposed fix

1. **Take an allocator.** Add `chitra_image_decode_budget_via(alloc, src, len, max_bytes, err_out)` taking a stdlib
   `Allocator` (`alloc_via` / `free_via`, `lib/alloc.cyr`), and route every allocation of the decode through it.
   The existing names keep using the global allocator, so nothing breaks.
2. **Make `chitra_image_free` real** for images from the `_via` path: it frees the output and the record through
   the same allocator. A consumer can then put the output on `fl_alloc`, which returns blocks over 4 KiB to the OS,
   or in an arena it resets per request.
3. **Free the working buffers** (MCU planes, IDCT scratch, the inflated PNG stream, BMP index planes) before
   returning, so the peak is the output plus one decode's working set, not their sum.

The architecture/005 hazard (sankoch's one-time tables surviving an `alloc_reset`) is avoided by (1). Nothing is
reset; the consumer frees exactly what chitra handed back.

## Consumer-side workaround

None that is safe. selah's `SlImage` already records whether chitra owns its pixels and calls `chitra_image_free`
when it is freed (`selah/src/codec.cyr`), so the fix reaches selah without a code change in selah. Until then, selah
documents the growth in its README and `state.md`.

## Resolution (1.4.0)

All three proposals, as designed here:

1. `chitra_image_decode_budget_via(a, src, len, max_bytes, err_out)` takes a stdlib `Allocator`
   (`a = 0` is the global one). Every allocation of the decode goes through it — zeroed, because the
   decoders were written against the global allocator's zeroed memory.
2. `chitra_image_free` frees the pixels and the record of such an image (the record carries `a` in a
   new `alloc` field, +56; `ChitraImage` is 64 bytes). For every other image it stays the no-op a
   1.3.x consumer may rely on. selah's `SlImage` path needs no change.
3. Every working buffer is freed before the call returns — every block on a refusal.

The mechanism is a per-decode context on the entry point's stack, not a global, so concurrent decodes
with different allocators do not interact. Proved with a counting `Allocator` that hands out dirty
blocks: exactly two blocks live after a decode, none after `chitra_image_free`, none after a refusal —
for every format in `tests/tcyr/budget_via.tcyr`, for progressive and CMYK in their suites, and on
hostile input in two new `fuzz_jpeg` modes. What still leaks: the 16-byte `ChitraErr` of a refusal
(`chitra_err` has no allocator and no free) and sankoch's one-time tables.
