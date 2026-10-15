# `src/lib.cyr` included `args`, `flags` and `vec`, which are referenced nowhere — and consumers paid for them

**Status:** 🟢 **FIXED in 1.0.1.** Removed from `src/lib.cyr` (and from `[deps].stdlib`, kept in
step). `dist/chitra.deps` drops from 13 leaves to 10.
⭐ **CLOSED STRUCTURALLY in 1.0.4** (cyrius 6.6.20 pin) — see
[Re-review at 1.0.4](#re-review-at-104-the-toolchain-closed-the-class) below. The sidecar is now
**3** leaves, and it no longer depends on `src/lib.cyr` being kept tidy.
**Filed:** 2026-08-31, by **crab**, while measuring the cost of adopting chitra 1.0.0.
**Affects:** chitra **1.0.0** and earlier.
**Severity:** Low, but paid by every consumer and invisible at the consumption site.

## The finding

```
$ grep -rE '\bargs_|\bargc|\bargv' src/ programs/ tests/ fuzz/   ->  0 hits
$ grep -rE '\bflags_'             src/ programs/ tests/ fuzz/   ->  0 hits
$ grep -rE '\bvec_|\bVec'         src/ programs/ tests/ fuzz/   ->  0 hits
```

All three were `include`d in `src/lib.cyr`, which is what `cyrius distlib` derives
`dist/chitra.deps` from — and `cyrius deps` treats that sidecar as **authoritative**.

⛔ **A consumer cannot decline a leaf it knows it does not need.** crab deleted `flags`, `thread` and
`sankoch` from its own `[deps].stdlib` and rebuilt: `cyrius deps` re-created all of them from the
sidecar and the binary came out byte-identical.

## Measured cost

crab, adding leaves one at a time to a 453,304 B host binary:

| added | host bytes | delta |
|---|---:|---:|
| (baseline) | 453,304 | — |
| `flags` | 461,624 | **+8,320** |
| `thread` | 461,608 | +8,304 |
| `thread` + `sankoch` | 860,784 | +407,480 |

⛔ `CYRIUS_DCE=1` reclaims **none** of it — it NOPs the unreachable functions and the binary is
byte-for-byte the same size.

## ⚠ A correction to this report, recorded because it was filed wrongly first

The original version of this issue claimed `cyrius distlib` copies `[deps].stdlib` verbatim into the
sidecar, and a companion issue was filed against **cyrius** on that basis. **That was wrong.**
distlib derives the sidecar from the `include "lib/*.cyr"` lines in `src/lib.cyr` — which is a
sound design, and the reason trimming `[deps].stdlib` alone changed nothing. The cyrius issue has
been **withdrawn**; there is no cyrius defect here, only an over-inclusive `lib.cyr`.

⇒ The mechanism was assumed from the symptom instead of being read. The symptom — a consumer linking
leaves the fold never references — was real; the cause named was not.

## Not a complaint about the big number

`sankoch` really is required (PNG's IDAT is DEFLATE — `zlib_decompress` and `crc32` are called from
`png_filter.cyr`, unprefixed, which is why a `sankoch_`-prefixed grep finds nothing), and `thread` is
required transitively by sankoch's internal lock. Those two are ~407 KB of a consumer's cost and this
change does not touch them. That is PNG's price, not an over-declaration.

## Re-review at 1.0.4: the toolchain closed the class

The 1.0.1 fix removed the three leaves this report named. Re-run at the 1.0.4 cut, the report's own
method showed the class was **still open**: `src/lib.cyr` still included five leaves `src/` never
calls — `assert`, `bench`, `fmt`, `io` and `str` (0 call sites each across `src/*.cyr`, and none from
`sankoch` or `thread` either). Under 6.6.2 all five were in the sidecar, so every consumer still
linked a test-assertion library and a benchmark harness.

⭐ **cyrius 6.6.20 changed the mechanism this report described.** `cyrius distlib` no longer copies
the `include "lib/*.cyr"` lines of `src/lib.cyr` into the sidecar — it derives the leaves the fold
actually references, compile-verifies the bundle against exactly those, and writes them into the
head of `dist/chitra.cyr` as well:

```
# Requires (compile-verified; the leaves of dist/chitra.deps):
include "lib/sankoch.cyr"
include "lib/alloc.cyr"
include "lib/string.cyr"
```

Evidence that it is reference-derived and not include-derived: `src/lib.cyr` as shipped (10 includes)
and a scratch copy trimmed to 5 (`string`, `alloc`, `syscalls`, `thread`, `sankoch`) produce the
**identical** 3-leaf sidecar.

⚠ `thread` is not in the sidecar and does not need to be: `lib/sankoch.cyr` carries its own
`include "lib/thread.cyr"` (it always has — 2.7.14 too), so `cyrius deps` resolves it through
sankoch. Proved with a scratch consumer whose `[deps].stdlib` is **empty**: it resolves, links and
decodes a 3×2 PNG to the right RGBA8. A kii-shaped consumer that also declares `sankoch` and
`thread` itself links clean with no duplicate-definition warning.

### Measured at 1.0.4 (same consumer, cyrius 6.6.20)

| chitra sidecar | stdlib files resolved | consumer bytes (DCE off) | consumer bytes (`CYRIUS_DCE=1`) |
|---|---:|---:|---:|
| 1.0.3 (10 leaves) | 35 | 811,608 | 246,360 |
| 1.0.4 (3 leaves) | 28 | **756,368** (−55,240) | **244,368** (−1,992) |

⇒ The 1.0.1 lesson ("an unused include here is not free and is not local") no longer holds at this
pin: an unused include in `src/lib.cyr` now costs chitra's own build and nobody else's. The five
includes were left in place for that reason — removing them would change nothing a consumer links.
⚠ The CI dist-sync step diffs `dist/chitra.deps`, so if a future pin reverts to include-derived
sidecars the change shows up as a stale-dist failure rather than silently re-billing consumers.
