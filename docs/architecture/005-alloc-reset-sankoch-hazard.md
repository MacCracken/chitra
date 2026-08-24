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

This is one of two reasons the byte-budget entry point in
[`../adr/0007-byte-budget-surface-deferred.md`](../adr/0007-byte-budget-surface-deferred.md)
matters: with the arena boundary unsafe for PNG, a caller has no way at all to
bound decode memory today.

## See also

- [`003-bump-allocator-no-free.md`](003-bump-allocator-no-free.md) — the
  allocation inventory and the lifetime model this note qualifies.
- [`../adr/0007-byte-budget-surface-deferred.md`](../adr/0007-byte-budget-surface-deferred.md)
  — the surface that would give consumers an alternative.
- [`../development/state.md`](../development/state.md) — tracked as a known
  upstream issue.
