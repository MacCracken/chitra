# `src/lib.cyr` included `args`, `flags` and `vec`, which are referenced nowhere — and consumers paid for them

**Status:** 🟢 **FIXED in 1.0.1.** Removed from `src/lib.cyr` (and from `[deps].stdlib`, kept in
step). `dist/chitra.deps` drops from 13 leaves to 10.
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
