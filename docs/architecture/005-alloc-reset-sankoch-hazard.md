# 005 — `alloc_reset()` breaks the next PNG decode (sankoch memoizes into the arena)

Non-obvious constraint a reader cannot derive from either library's API:
[`003-bump-allocator-no-free.md`](003-bump-allocator-no-free.md) tells a
long-running consumer to drive memory at the arena boundary — *"reset the
region between batches"* — and for PNG that advice is **currently unsafe**.
This note records the fact, its mechanism, and its exact scope. It is not a
decision (nothing here is chitra's to decide) and not a how-to.

## The fact

Calling the stdlib's `alloc_reset()` between decodes corrupts memory and breaks
**the next PNG decode**. Reproduced on this tree, decoding the same valid 8×8
PNG four times:

```
decode #1 (fresh arena)        DECODE ok
decode #2 (same arena)         DECODE ok
alloc_reset()
decode #3 (after alloc_reset)  FAILED code=7   (CHITRA_ERR_CRC)
decode #4 (after alloc_reset)  FAILED code=1   (CHITRA_ERR_SIGNATURE)
```

**Do not pin the error code.** Codes 7 and 1 were both observed on the same
run, from the same bytes; which one appears depends on what now occupies the
re-issued addresses. That variability is itself the diagnosis: the failure is a
wild write, and the decode error is only its most benign symptom. Note
especially decode #4 failing at the *signature* — the fixture's own bytes were
overwritten.

**BMP and JPEG are unaffected.** Both survive the same reset and decode
correctly afterwards. Neither touches sankoch.

## The mechanism

`sankoch` memoizes state into module-level globals that hold **raw pointers
into the bump arena**, and the arena reset is invisible to it:

- `lib/sankoch.cyr` declares `var crc32_table = 0;` and
  `fn crc32_init_table()` guards its allocation with `if (crc32_table == 0)`.
- chitra calls `crc32_init_table()` on **every** PNG decode
  ([`png_filter.cyr:365`](../../src/png_filter.cyr)) — correctly, since it
  cannot know whether some other caller has initialized it.
- After `alloc_reset()` the arena's bump pointer rewinds, but `crc32_table` is
  still non-zero. So the guard skips re-allocation and the function writes
  **16,384 bytes through a stale pointer** into memory the allocator has since
  handed to something else — in the reproduction above, to the freshly
  allocated copy of the PNG being decoded.

The same shape exists for sankoch's Huffman table memoization
(`_huff_tables_allocd`).

## Why this is not fixable on chitra's side

Both guards are internal to sankoch and invisible to callers: there is no
"forget your memoized state" entry point to call after a reset, and no way to
ask whether the pointers are still live. chitra cannot detect the reset either
— `alloc_reset()` is a stdlib function the consumer calls directly, with no
notification.

Editing `lib/` is forbidden: it is a build artifact vendored by `cyrius deps`,
and a change there would be silently reverted on the next resolve (see
[`001-lib-must-not-be-symlink.md`](001-lib-must-not-be-symlink.md)). The fix
belongs upstream — sankoch should either re-check liveness or expose a reset
hook — and is reported as such.

## Consequence for consumers

Until it is fixed upstream:

- A consumer that decodes **PNG** must not call `alloc_reset()` between
  decodes. The memory it reclaims is real, but the next PNG decode writes
  through a dangling pointer.
- A consumer that decodes only **BMP** or **JPEG** may reset safely today. That
  is an accident of which library each path depends on, not a guarantee — treat
  it as the current fact, not a contract.
- **mabda**'s pattern is unaffected in the shape described in 003 (decode →
  upload to a texture → reclaim the region wholesale) *only* if that region is
  a separate arena rather than the global one. A global `alloc_reset()` on a
  PNG-decoding path hits this.

This is one of two reasons the byte-budget entry point mattered — and it
**shipped in 0.6.1** as `chitra_image_decode_budget`, one of the 29 frozen names
at 1.0.0 ([`../adr/0008-byte-budget-as-shipped.md`](../adr/0008-byte-budget-as-shipped.md)
is the as-shipped record; 0007 decided the shape). But note precisely what it
does and does not solve: it bounds the **declared RGBA output of one decode**,
not cumulative arena growth. A caller decoding untrusted input in a loop still
has no way to reclaim, so the hazard this note documents is unresolved for PNG
regardless.

## Who is exercising this today

Not hypothetical. **kii's fuzz harness** (`tests/kii.fcyr`, `fuzz_png_iter`)
calls `kii_decode_png(...)` and then `alloc_reset()` on every iteration, at
10⁶ iterations per run — precisely the pattern above, and for exactly the
reason 003 gives: without the rewind, the never-free arena grows unbounded.
kii is right to do it. There is no other way to bound the heap over a million
decodes.

**And the harness cannot see the hazard.** Its stated contract is that
`kii_decode_png` "never crashes; returns `PNG_OK` or any `PNG_ERR_*`
cleanly" — which a *corrupted* decode returning `CHITRA_ERR_CRC` satisfies
perfectly. The inputs are random bytes expected to fail anyway, so the failure
this note documents is indistinguishable, from inside that harness, from the
harness working. It is the house rule in its purest form: **fuzzing does not
find wrong output.**

That is what makes the sankoch 2.7.10 pin bump a fix rather than housekeeping.

## Status

**Fixed upstream in sankoch 2.7.10; not yet vendored here.** The fix is an
arena canary — the reset zeroes the span it rewinds, so a magic-stamped
arena-allocated word reads back zero afterwards, which makes the detection
exact rather than heuristic. It is checked in `_sankoch_lock()` *before*
`_sankoch_mtx` is touched (the mutex pointer is itself a candidate for being
dangling) and again in `crc32_init_table()`, which consumers reach without the
lock — as chitra does, per PNG decode.

chitra cannot pick it up on its own: `lib/` is vendored by `cyrius deps` from
the toolchain snapshot, so it arrives with the next cyrius release and a bump
of `[package].cyrius` (`6.5.35` as of 1.0.0). **Re-run the reproduction above
against the new `lib/sankoch.cyr` before retiring this note** — a pin bump is
not by itself evidence that the bundled copy moved.

## See also

- [`003-bump-allocator-no-free.md`](003-bump-allocator-no-free.md) — the
  allocation inventory and the lifetime model this note qualifies.
- [`../adr/0007-byte-budget-surface-deferred.md`](../adr/0007-byte-budget-surface-deferred.md)
  — the surface that would give consumers an alternative.
- [`../development/state.md`](../development/state.md) — tracked as a known
  upstream issue.
