# chitra — Current State

> **Last refresh**: 2026-10-15 (1.1.4) | **Refresh cadence**: every release.
> [`CLAUDE.md`](../../CLAUDE.md) is preferences / process / architecture
> (durable); this file is **state** (volatile) — it is the home for the
> version, sizes, and counts `CLAUDE.md` must not inline.

## Version

**1.1.4** — cut 2026-10-15. ⭐ **CI now builds chitra the way most of its consumers link it.** The
pin moves `6.7.9` → **`6.7.12`** for its stdlib, whose `sankoch.cyr` is 2.8.7 — at the 2.8.6 floor
the consumer docs promise (6.7.9's was 2.8.3). That lets `make consumer-shape` (CI + `test-all`)
rebuild the tree with the stdlib `"sankoch"` leaf in place of chitra's `zlib` profile — the shape
kii, mabda and aethersafha use — on chitra's own pin, and run every suite; on a 6.7.9 pin it fails at
exactly the png-3 floor cells. Fuzzing now also reaches the last three paths it never did (PNG's
unknown-critical-chunk abort, `CHITRA_ERR_INFLATE_LIMIT`, BMP's exact RLE cap), each probe-proven.
⛔ No decode code changed; the corpus is byte-identical to 1.1.3 across the compiler change.

**1.1.3** — cut 2026-10-15. ⭐ **The bundle's function namespace, closed the same way 1.1.2 closed its
globals.** 84 internal helpers (`_jpeg_*`, `_bmp_*`, `_cur_*`, `_gif_*`, `_chunk_*`, `_adam7_*`,
`_png_*`) were in `dist/chitra.cyr` with no chitra prefix, and a consumer function of the same name
**replaced** chitra's ("duplicate fn … last definition wins", a warning only). All 84 are now
`_chitra_*` (579 mechanical replacements; decode output byte-identical; smoke binary the same size).
`tests/tcyr/namespace.tcyr` now also declares a consumer function for every old name — against the
1.1.2 sources the suite raises 84 duplicate-fn warnings, fails PNG and JPEG and dies with SIGSEGV —
and `check-surface.sh` fails on any unprefixed top-level `fn`. ⇒ **Every global and every function
the bundle puts in a consumer's program is now chitra-prefixed, and gated.**

**1.1.2** — cut 2026-10-15. ⭐ **Closes cc-13, the one finding 1.1.1 deferred.** 128 top-level globals
in the bundle had no chitra prefix, and since `dist/chitra.cyr` is a strip-concatenation each was a
global in the consumer's program. Measured: a consumer global of the same name declared after chitra —
or simply assigned — rewrote what chitra decodes with; `CUR_POS_OFFSET` crashed the JPEG and PNG
decoders, `LZ_BIT` the GIF one, `HT_SIZE` broke every JPEG. All 128 are now `_CHITRA_*` /
`_chitra_*` (590 mechanical replacements; decode output byte-identical; smoke binary the same size),
`tests/tcyr/namespace.tcyr` plays that consumer (all four decodes fail against the 1.1.1 sources),
and `check-surface.sh` fails on any unprefixed top-level `var`. ⚠ The same exposure remains for 84
unprefixed internal **functions** — next on the roadmap.

**1.1.1** — cut 2026-10-15. ⭐ **The sixth security audit, and the first since the dependency
boundary moved** — [`docs/audit/2026-10-15-audit.md`](../audit/2026-10-15-audit.md). Five lenses, each
finding put to an independent verifier whose job was to refute it by reproduction: **65 filed, 57
confirmed, 8 refuted**, ~40 distinct defects (5 HIGH, 10 MEDIUM, no CRITICAL), all repaired with
mutation-checked tests except cc-13 (125 unprefixed globals), deferred to its own 1.1.x patch.
⛔ **No memory-safety defect in shipped code** — but the largest class was guards that work and that
**no test could see**: deleting the GIF frame-rect check, BMP's RLE `y >= h` write bounds or JPEG's
coefficient-index check left every suite and fuzzer green (C-3); a sweep of 171 guards found 106 such.
Two silent colour-space errors in JPEG (C-1, C-2), a padded JPEG still spending 50 MB to be refused
(C-4), and every `cjpeg` file at quality ≤ 23 reported as a bad quant table (C-5).
⭐ The gate stack: fuzzing now runs under `--poison` and reaches every path it claims (C-7, C-8); the
JPEG fuzz harness's peak RSS fell **16.3 GB → 54 MB**; all 37 error-code values are pinned (C-9);
`--strict-deferrals` is on; CI fails on a stale or rewritten `cyrius.lock`.
⚠ Outputs and codes that changed are listed in the audit's § 5 — every one toward the reference
decoders, and two land in kii's error mapping.

**1.1.0** — cut 2026-10-15. ⭐ **chitra links sankoch's `zlib` profile, not all of sankoch.** It
calls `zlib_decompress` and `crc32` and through 1.0.4 linked every codec sankoch has for them; it now
declares `[deps.sankoch]` tag `2.8.7`, `modules = ["dist/sankoch-zlib.cyr"]`, and drops `sankoch` and
`thread` from `[deps].stdlib`. Smoke **803,448 → 343,776 B** (DCE off), **184,952 → 36,576 B**
(DCE on); the sidecar is just `string`. sankoch reaches consumers through chitra's own
`[deps.sankoch]`, resolved transitively with **closest-wins**, so a consumer that already links a
sankoch keeps exactly that one — proved for all three consumer shapes, and against a scratch kii
(5 suites + 1 M-iteration fuzz green). The pin goes `6.6.20` → **`6.7.9`**. ⛔ **No decode code
changed**: the 53-file corpus is still byte-identical to 1.0.3. ⭐ PNG decode is **22–75 % faster**
from sankoch 2.8.5–2.8.6's CRC-32 fold and inflate rewrite; JPEG/BMP/GIF are flat.

**1.0.4** — cut 2026-10-15. ⭐ **A toolchain cut that also shrinks every consumer's link.** The pin
goes `6.6.2` → **`6.6.20`**, `lib/` is re-vendored (110 → **113** `.cyr` files) and sankoch moves
2.7.14 → **2.8.1**. ⛔ **No decode code changed** — `git diff dist/chitra.cyr` is the header stamp,
the `chitra_version()` literal, and the new `Requires` block; `check-surface` still reports 75
exports / 29 frozen, and a 53-file corpus decodes **byte-identically** on 1.0.3@6.6.2 and
1.0.4@6.6.20.
⭐ **`dist/chitra.deps` is 3 leaves, not 10** (`sankoch`, `alloc`, `string`): 6.6.20's distlib derives
the sidecar from what the fold *references*, not from the `src/lib.cyr` include list. That closes the
2026-08-31 issue's class for good — `assert`, `bench`, `fmt`, `io` and `str` were still in the
sidecar at 6.6.2 and are not now. A consumer measured **811,608 → 756,368 B** (DCE off).
⚠ One test was coupled to sankoch internals: sankoch 2.8.x arms its arena canary with a plain
`alloc(8)`, so the B-1 CRC-table injection moved from index 1 to 0. Re-pointed, made self-checking
(`crc32_table` asserted before and after), and mutation re-checked.

**1.0.3** — cut 2026-09-10. ⭐ **The fifth security audit, and the first since the freeze** —
[`docs/audit/2026-09-10-audit.md`](../audit/2026-09-10-audit.md). Eleven adversarial lenses, every
candidate put to two independent skeptics with opposing jobs: **41 confirmed, 5 split, 2 refuted**,
deduplicating to **19 distinct defects**, all repaired with mutation-checked regression tests.
⛔ **No memory-safety defect and no wrong-output defect on well-formed input.** With 10.7 M fuzz
assertions already saying this code does not fault easily, the sweep was weighted toward what
fuzzing cannot see, and that is what it returned: a **null dereference on a valid PNG under memory
pressure** (B-1, SIGSEGV); a **JFIF file whose colour space was overridable by its component ids**
(B-2, every colour byte wrong on a six-byte edit); a **truncated JPEG scan reporting a clean close**
(B-5); **every RLE BMP whose width is not a multiple of 4 refused** (B-6, 30 of 30 ImageMagick
files); **four refusal paths that allocated what they were refusing** (B-3/B-4/B-7 — 50 MB, 16.7 MB
and 69 KB per refusal, now 22 KB, 128 B and 416 B); and **seven gates that could not fire**,
including `check-surface.sh`, which ran in no CI workflow at all.
⚠ Two repairs change what a consumer observes, both narrowings toward the reference decoders:
`seen_iend` now reports 0 for a JPEG with an unexpected RSTn, and `source_color_type` 0x113 is
narrowed to libjpeg's file set. B-6 *widens* acceptance; nothing that decoded before decodes
differently.

**1.0.2** — cut 2026-09-10. ⭐ **A toolchain cut that turned out to carry a fix.** The pin goes
`6.5.35` → **`6.6.2`** and `lib/` is re-vendored (108 → **110** `.cyr` files; `boxed.cyr` and
`hashseed.cyr` are new, 40 carried-over files differ). ⛔ **No decode code changed** — `git diff
dist/chitra.cyr` against 1.0.1 is exactly two lines, the header stamp and the `chitra_version()`
literal, so the bundle's decode source is byte-identical and `check-surface` still reports 74
exports / 29 frozen.
⭐⭐ **What the pin actually bought**: sankoch **2.7.14**, past the 2.7.10 arena canary, which
retires [architecture/005](../architecture/005-alloc-reset-sankoch-hazard.md) — `alloc_reset()`
between PNG decodes is safe again. Measured before retiring the note: **200,000** decode + reset
cycles, 0 failures, 0 differing pixel bytes; and the negative control (canary neutered in a scratch
copy) returns `CHITRA_ERR_CRC` exactly as 005 records. Pinned in-tree by the new
`tests/tcyr/alloc_reset.tcyr` (**15** assertions), because the fix lives in gitignored `lib/` and a
future pin bump could withdraw it with no diff here.
⚠ **`cyrius deps` alone was not enough** — it refreshes only the 32-file declared-leaf closure, which
is why the shadow-lib warning survived 1.0.1 with 11 bundled libraries stale. `cyrius lib sync
--full` clears it.
⛔ **The 16 MiB ceiling is not raised** — `DECOMPRESS_MAX_OUTPUT` is still `16777216` at 2.7.14, so
1.0.1's `CHITRA_ERR_INFLATE_LIMIT` story is unchanged and that roadmap item stays open.

**1.0.1** — cut 2026-08-31. ⭐ **ABI-additive over 1.0.0**: no name added or removed, no offset
moved, one new **error code** (`CHITRA_ERR_INFLATE_LIMIT`, 35). A valid PNG past sankoch's 16 MiB
inflate ceiling is now refused **from the header, in under 64 KiB** — it used to spend
**26,617,512 bytes** to return a bare `CHITRA_ERR_INFLATE`. And `src/lib.cyr` drops three stdlib
includes (`args`, `flags`, `vec`) referenced nowhere in the repo, so the sidecar goes 13 leaves → 10
and every consumer stops linking them. Reported by **crab**.
⛔ **The ceiling is sankoch's and this release does not raise it** — no sankoch entry point emits
past 16 MiB, the streaming decoder included. Filed there. What changed is that the failure is now
cheap and correctly named.

**1.0.0** — cut 2026-08-24. **The freeze.** The 29 names in
[`public-surface.md`](public-surface.md), plus the `ChitraImage` and `ChitraErr`
record layouts, are now covered by a compatibility promise: changing a
signature, removing a name, or changing documented behaviour there is a **major
bump plus an ADR**. The other 45 `chitra_*` names the bundle exports are named
in the same file as internal and are explicitly not covered.

**No code changed in this cut except the version literal.** That is deliberate
and it is the point: 0.9.0 spent every prerequisite the roadmap had listed, so
the release that promises stability does not itself churn the thing it is
promising about. The diff is `VERSION`, the version literal (10000 at the
freeze), two test assertions, and documentation.

What v1.0 does **not** promise, stated because a promise with unstated edges is
not a promise:

- **The 45 internal names.** They may change or disappear in any release. They
  are visible because `cyrius distlib` strip-concatenates, not because they are
  an API ([ADR 0010](../adr/0010-the-v1-surface.md)).
- **Bit-exact output across releases.** The contract is *correct* RGBA8, held
  to external oracles — `djpeg -nosmooth` for JPEG, ImageMagick for PNG/BMP/GIF.
  A repair that moves bytes closer to the oracle is a bug fix, not a break; the
  depth-16 rescaling change in 0.7.x is the precedent.
- **Error *codes* are frozen; error *strings* are not.** `chitra_err_name`
  returns human-readable text. 0.9.0 changed two of those strings precisely so
  the freeze would not codify text that told consumers the wrong story about
  their own files. Match on `chitra_err_code`.
- **Memory behaviour.** The bump allocator never frees and `chitra_image_free`
  is a documented no-op ([architecture/003](../architecture/003-bump-allocator-no-free.md)).
  That is a current fact about the stdlib, not a frozen guarantee.

Coverage at the freeze: **PNG** every spec-legal bit depth × colour type plus
Adam7; **JPEG** JFIF baseline including the full T.81 § A.2 scan model;
**BMP** with an empty deferral list; **GIF** first frame ([ADR 0005](../adr/0005-gif-first-frame-only.md)).
Four security audits, every format line-by-line reviewed.

`chitra_version()` → **10104**. **3,978 test assertions** across **14 suites**,
**11,649,080 fuzz assertions** under `--poison`, 17 benchmarks — 0 failures throughout.

Released tags: 0.1.0, 0.2.0, 0.2.1, 0.3.0, 0.3.1, 0.3.2, 0.3.3, 0.4.0, 0.5.0,
0.5.1, 0.5.2, 0.5.3, 0.6.0, 0.6.1, 0.7.0, 0.7.1, 0.7.2, 0.7.3, 0.8.0, 0.9.0,
1.0.0, 1.0.1, 1.0.2, 1.0.3, 1.0.4, 1.1.0, 1.1.1, 1.1.2, 1.1.3 (1.1.4 is cut but not yet tagged)
(SemVer; **the public surface is frozen as of 1.0.0** — see
[`public-surface.md`](public-surface.md) for what that covers and
[ADR 0010](../adr/0010-the-v1-surface.md) for the calls made to get there).

## Toolchain

- **Cyrius pin**: `6.7.12` (in [`cyrius.cyml`](../../cyrius.cyml)
  `[package].cyrius`). This pin is the **only** source of truth — CI and the
  release workflow both read it; no toolchain version is hardcoded in YAML.
  Bumped from `6.5.35` at 1.0.2, from `6.6.2` at 1.0.4, from `6.6.20` at 1.1.0
  and from `6.7.9` at 1.1.4. ⭐ **The 1.1.4 bump was chosen for its stdlib, not
  its compiler**: 6.7.12's stdlib `sankoch.cyr` is 2.8.7, at the 2.8.6 floor the
  consumer docs promise, so CI can build chitra the way kii / mabda /
  aethersafha link it (the stdlib `"sankoch"` leaf) on chitra's own pin
  (`make consumer-shape`). 6.7.9's was 2.8.3, and that leg fails on it — proven.
  Nothing 6.7.10–6.7.12 changed reaches chitra's code: 14 suites green
  unchanged, the 26-file closure the same, `dist/` byte-identical.
- **sankoch is not from the pin any more (1.1.0).** It is `[deps.sankoch]`,
  tag **`2.8.7`**, `modules = ["dist/sankoch-zlib.cyr"]` — the zlib profile,
  cloned from sankoch's repo and commit-pinned in `cyrius.lock`. ⇒ A sankoch
  fix now arrives with a **tag bump in `cyrius.cyml`**, not a cyrius pin bump;
  the 6.7.9 snapshot's own `sankoch.cyr` (2.8.3) is not linked.
- **`lib/`** is the **26-file closure** `rm -rf lib && mkdir lib && cyrius deps`
  produces — the same tree CI builds, and since 1.1.0 the local convention
  too. It is a **real directory, never a symlink** —
  distlib concatenation depends on it (see
  [architecture/001](../architecture/001-lib-must-not-be-symlink.md)).
  `lib/` is gitignored: it is a build artifact, not source.
  ⚠ **Why the full snapshot stopped being the local convention (1.1.0).**
  Through 1.0.4 `lib/` was `cyrius lib sync --full` (113 files) locally and the
  closure (32 → 35 files) in CI. The snapshot existed to clear the
  `./lib/ shadows version-pinned …` warning, which comes from *stale*
  non-closure files left behind when only the closure is refreshed after a pin
  bump (1.0.2). A **wiped** `lib/` rebuilt by `cyrius deps` has no stale file,
  builds with no warning, and at 6.7.9 is the only shape that keeps the lock
  stable: `cyrius deps` over a full snapshot rewrites `cyrius.lock` to every
  vendored file (114), which 6.6.20 did not.
  ⛔ **Do not hand-edit anything under `lib/`** — `cyrius build` re-vendors it
  mid-invocation and the edit is gone with no diagnostic. Verified at 1.0.2: a
  marker written into `lib/sankoch.cyr` was absent after the next build. To test
  a modified stdlib file, copy it *outside* `lib/` and include it from there,
  and drop the leaf from `[deps].stdlib` so only one copy links (linking two
  leaves which definition wins ambiguous, and the experiment meaningless).
- **`cyrius.lock`** (new at 1.0.4): `cyrius deps` writes it whenever `lib/`
  gains a file it does not cover. It is the **26-file closure plus the sankoch
  2.8.7 commit pin**, and `cyrius deps --verify` passes 26/26 on it. ⚠ Never
  regenerate it over a full snapshot: a 113/114-entry lock fails `--verify`
  against CI's closure (78 of 113 at 1.0.4). At a pin or sankoch-tag bump:
  `rm -rf lib cyrius.lock && mkdir lib && cyrius deps`. Not gated: CI does not
  run `cyrius deps --verify`.
- **Toolchain notes (re-verified on 6.6.2 at the 1.0.2 cut; `fmt --check`
  re-verified on 6.6.20 at 1.0.4; lint and fmt gates green on 6.7.9 at
  1.1.0)**:
  - Canonical continuation indent is **2 spaces per open paren**, not a flat
    +2. Almost every wrapped line in the tree is at depth 1, which is why "+2"
    described it; the exception is `src/jpeg.cyr:1051`, a depth-2 continuation
    at +4 that the flat wording could not explain. This is what reflowed
    `src/png_chunks.cyr`, `src/png_filter.cyr` and `tests/tcyr/error.tcyr` at
    the 0.3.2 cut — whitespace only.
    ⚠ `--check` is **looser than the writer**: it accepts a file that is
    *consistently* 4-per-paren and rejects only one that **mixes** the two. A
    hand-written 4-space file passes `make fmt-check` and would still be
    rewritten by `cyrius fmt`.
  - Since 6.5.28 `cyrius fmt` **rewrites in place** (it was stdout-only
    before). The `make fmt-check` target relies on the exit code with the
    file argument *before* `--check`, and redirects stdout. ⭐ **Contract
    re-verified on 6.6.2, and again on 6.6.20**: `--check` still reports through
    the exit code, still does not rewrite, and still fires on real drift — the
    gate is not silently passing. Re-verify on any future pin bump.
  - ⭐ **`--strict-deferrals` is on (1.1.1).** Alongside `warn` lines `cyrlint`
    emits `deferral line N: untracked '<word>'` for prose such as "not yet",
    "deferred" or "later", which the `warn` grep never matched. 6.7.9 reported
    13; the sweep found they were *not* all false positives, and all 13 were
    reworded rather than silenced with `#skip-lint`, so the tree has none. Both
    lint loops now pass `--strict-deferrals` and fail on lint's own exit status,
    so a new deferral note fails the build. Proven: a probe comment reading
    "not yet implemented" in `src/gif.cyr` makes `make lint` exit 2.
    ⚠ The flag was **argument-order sensitive on 6.6.2** (`<file>
    --strict-deferrals` silently dropped it). On 6.7.9 it works in either
    position; both loops put it first anyway.
- **Cyrius note**: `>>` is a **logical** shift. The JPEG IDCT and the
  YCbCr→RGB color pass need signed round-to-nearest division, so they use the
  in-tree `_chitra_jpeg_descale` helper rather than `>>` (see
  [adr/0004](../adr/0004-jpeg-decode-model.md)).

## Surface

chitra is a **library** — encoded image bytes → canonical RGBA8, zero GPU,
no C shim, no external binaries, no CLI/stdout/ANSI surface (the one stderr
write is `chitra_err_print_name`, a fixed string). Consumers link
`dist/chitra.cyr`. DEFLATE is **sankoch's** job; JPEG entropy decode is
chitra's own (no sankoch on the JPEG path).

### Public API (`@public`)

PNG:

- `chitra_png_decode(src, len, err_out)` → `ChitraImage*` (0 on fail,
  `*err_out` set).
- `chitra_png_decode_rgba8(src, len, w_out, h_out)` → RGBA8 ptr (0 on fail) —
  convenience wrapper.
- `chitra_png_check_signature(src, len)` → 1 if the bytes open with the
  8-byte PNG signature.

JPEG (0.3.0):

- `chitra_jpeg_decode(src, len, err_out)` → `ChitraImage*` (0 on fail,
  `*err_out` set).
- `chitra_jpeg_decode_rgba8(src, len, w_out, h_out)` → RGBA8 ptr (0 on fail).
- `chitra_jpeg_check_signature(src, len)` → 1 if the bytes open with the
  JPEG SOI marker.

GIF (0.5.0, first frame only — [ADR 0005](../adr/0005-gif-first-frame-only.md)):

- `chitra_gif_decode(src, len, err_out)` → `ChitraImage*` (0 on fail,
  `*err_out` set). Sized to the **logical screen**; canvas the first frame does
  not paint is emitted transparent (alpha 0) rather than background-filled —
  chitra did not decode those pixels, and alpha 0 says exactly that.
- `chitra_gif_decode_rgba8(src, len, w_out, h_out)` → RGBA8 ptr (0 on fail).
- `chitra_gif_check_signature(src, len)` → 1 for `GIF87a` / `GIF89a`.

BMP (0.4.0):

- `chitra_bmp_decode(src, len, err_out)` → `ChitraImage*` (0 on fail,
  `*err_out` set).
- `chitra_bmp_decode_rgba8(src, len, w_out, h_out)` → RGBA8 ptr (0 on fail).
- `chitra_bmp_check_signature(src, len)` → 1 if the bytes open with `BM`.

Format-agnostic:

- `chitra_image_decode(src, len, err_out)` → `ChitraImage*` — the
  **signature-sniffing router** ([`jpeg.cyr:1311`](../../src/jpeg.cyr)): the
  8-byte PNG magic → `chitra_png_decode`; else the JPEG SOI marker →
  `chitra_jpeg_decode`; else the BMP `BM` magic → `chitra_bmp_decode`; else
  the `GIF87a`/`GIF89a` magic → `chitra_gif_decode`; else
  **`0` with `*err_out` = `CHITRA_ERR_SIGNATURE`**.
  It does *not* fall through to the PNG decoder for unrecognized bytes — an
  unknown format is rejected at the router. The single entry a consumer
  should reach for when it does not know the format up front.
- `chitra_image_decode_budget(src, len, max_bytes, err_out)` → `ChitraImage*`
  (0.6.1) — decodes unless the RGBA8 output would exceed `max_bytes`. A refusal
  sets `CHITRA_ERR_BUDGET` (34) and costs 16 bytes (128 for BMP; misquoted as 144 until 1.1.1). It is **never
  a validity opinion**: an unreadable header goes to the router so the real
  error is reported, not a budget refusal. It bounds the declared *output*, not
  the peak, and its own comment says what it does not cover
  ([ADR 0008](../adr/0008-byte-budget-as-shipped.md)).

Shared:

- `ChitraImage` accessors: `chitra_image_{width,height,pixels,channels,
  seen_iend,source_color_type,source_depth}`; `chitra_image_free` (a
  documented no-op under the bump allocator).
- The full frozen list — 29 names of the 75 the bundle exports — is
  [`public-surface.md`](public-surface.md), checked against `dist/chitra.cyr`
  by `scripts/check-surface.sh` on every `make lint`.
- `chitra_version()` → **`10104`** (`major*10000 + minor*100 + patch`).
- Error API: `chitra_err_new` / `chitra_err` / `chitra_err_code` /
  `chitra_err_detail` / `chitra_err_name` / `chitra_err_print_name` + enum
  `ChitraErrCode`.

> **Marker note**: `@public` is used two ways — a **file-level banner** on
> line 1 of `png.cyr` and `error.cyr` (covering that module's whole stable
> surface, which is how the `ChitraImage` accessors and the `chitra_err_*`
> family are marked) and a **per-function** marker elsewhere. The two
> signature predicates in `png_chunks.cyr` / `jpeg_markers.cyr` carried
> **neither** form through 0.8.0 — public by documentation and by kii's use,
> but not by marker; **0.9.0 gave them per-function markers.** The ambiguity
> in *how* the marker is carried is why `check-surface.sh` reads the bundle's
> exports against a hand-classified manifest instead of parsing markers.

`ChitraImage` is a **56-byte** record — `width`@0, `height`@8, `pixels`@16
(owned RGBA8, `w*h*4` bytes), `channels`@24 (=4), `seen_iend`@32 (1 = the
stream ended the way its format says it should), `src_ctype`@40,
`src_depth`@48 (0.9.0 — bits per channel in the SOURCE: the IHDR depth for
PNG, 8 for JPEG and GIF, the widest declared channel for BMP). For a
PNG, `src_ctype` is the pre-normalization PNG color_type (0/2/3/4/6); for a
JPEG it carries `0x100 | num_components`, with bit 4 set when the components
are RGB rather than YCbCr (so `0x101` grayscale, `0x103` YCbCr, **`0x113` RGB**
— 0.6.1); for a BMP, `0x200 | bpp` (so `0x201`/`0x204`/`0x208` indexed,
`0x210` for the packed 16-bpp layouts, `0x218` at 24 bpp, `0x220` at 32 bpp); for a GIF, `0x300 | min_code_size`.
The +32/+40/+48 fields are **append-only** — 0.1.x offsets preserved, so
mabda's accessors are unaffected. `tests/tcyr/surface.tcyr` pins each offset
individually, so a reordering that looks harmless in source fails a test.

`ChitraErr` is a **16-byte** record (+0 code, +8 detail ptr), **layout-
compatible with mabda's `GpuErr`** so a decode failure maps onto
`GPU_ERR_IMAGE_DECODE` (see [adr/0003](../adr/0003-mabda-abi-compatibility.md)).

### PNG decode matrix (feature-complete as of 0.2.1)

Signature + chunk parse (IHDR / IDAT-concat / IEND / PLTE / tRNS), all five
color types across every spec-legal bit depth, both scan orders:

| color type | 1 | 2 | 4 | 8 | 16 |
|---|---|---|---|---|---|
| 0 grayscale       | ✓ | ✓ | ✓ | ✓ | ✓ |
| 2 RGB             | — | — | — | ✓ | ✓ |
| 3 palette         | ✓ | ✓ | ✓ | ✓ | ✗ |
| 4 gray+alpha      | — | — | — | ✓ | ✓ |
| 6 RGBA            | — | — | — | ✓ | ✓ |

(— = not spec-legal per § 11.2.2 Table 11.1, rejected at the IHDR gate;
✗ = ct3+depth16 is the one illegal combo that survives the table and is
rejected.) **Adam7 interlace** is supported for every cell — the 7 reduced
passes are filtered independently and deinterlaced into the same dense,
byte-padded buffer the non-interlaced path produces, so the color pass is
interlace-agnostic. 16-bit samples **rescale** per § 13.13 (`(v*255 + 32767) / 65535`), matching ImageMagick byte-for-byte — they truncated to the high byte through 0.7.0; sub-byte
grayscale scales ×255/85/17; palette indexes PLTE; tRNS synthesizes alpha.

### JPEG decode scope (0.3.0)

JFIF **baseline** (SOF0) sequential Huffman, 8-bit precision only:

- **Grayscale** (1 component) and **YCbCr** (3 components).
- **Chroma subsampling**: 4:4:4 / 4:2:2 / 4:2:0 and **general per-component
  Hi,Vi** (box upsampling to full resolution).
- **T.81 § A.2 non-interleaved and multi-scan layouts** (0.6.0 for `Nf = 1`,
  **0.8.0 for the general case**): a scan carrying fewer components than the
  frame (`Ns < Nf`) decodes, driven by a per-component coverage bitmask. One
  § A.2 rule covers both layouts — 0.6.0's effective-geometry collapse was
  deleted, not extended, and `Nf = 1` now falls out of the general § A.1.1
  formula. `Σ Hj·Vj ≤ 10` applies only when `Ns > 1`, per § B.2.3
  ([ADR 0006](../adr/0006-defer-jpeg-multiscan-resumption.md), amended).
- **DRI / RST0–7** restart markers — restart intervals reset the DC
  predictors and byte-align the entropy stream.

Decode pipeline: `chitra_jpeg_scan_markers` (SOI..SOS marker walk —
DQT / DHT / SOF0 / DRI parse + reject non-baseline) → `_chitra_jpeg_parse_sos` →
`_chitra_jpeg_decode_scans` → `_chitra_jpeg_decode_one_scan` (per-component MCU loop: `_chitra_jpeg_decode_block`
[bit-reader + Annex F `DECODE` + `RECEIVE`/`EXTEND`, DC diff + AC run/size],
`_chitra_jpeg_idct_block` [dequant + zig-zag + libjpeg `islow` integer IDCT +
level-shift `+128` and `[0,255]` clamp], plane placement) → `_chitra_jpeg_build_image`
(box upsample + full-range BT.601 YCbCr→RGB, or a straight copy for RGB
components) → `ChitraImage`. **Non-baseline modes
(progressive, arithmetic, 12-bit precision, hierarchical/lossless/
differential, 4-component CMYK/YCCK) are rejected with distinct error
codes** — the defer-don't-half-implement posture. See
[adr/0004](../adr/0004-jpeg-decode-model.md) and
[proposals/jpeg-baseline-decoder.md](../proposals/jpeg-baseline-decoder.md).

### Decode rejection paths → `CHITRA_ERR_*`

PNG / generic: `OK`=0, `SIGNATURE`=1, `TRUNCATED`=2, `BAD_CHUNK`=3,
`UNSUPPORTED`=4, `INFLATE`=5, `OOM`=6, `CRC`=7, `INTERLACE`=8, `BIT_DEPTH`=9,
`DIMENSIONS`=10, `FILTER`=11, `NO_IDAT`=12, `INFLATE_LIMIT`=35 (1.0.1 — a valid
PNG whose scanlines inflate past sankoch's 16 MiB `DECOMPRESS_MAX_OUTPUT`,
refused from the header), `OTHER`=99.

JPEG (`src/error.cyr` enum, 13–23): `JPEG_MARKER`=13, `JPEG_SOF`=14,
`JPEG_DQT`=15, `JPEG_DHT`=16, `JPEG_SOS`=17, `JPEG_ENTROPY`=18,
`JPEG_PROGRESSIVE`=19, `JPEG_ARITHMETIC`=20, `JPEG_PRECISION`=21,
`JPEG_MODE`=22, `JPEG_COMPONENTS`=23. The JPEG path also reuses the generic
`SIGNATURE`=1, `TRUNCATED`=2, `OOM`=6, `DIMENSIONS`=10, `UNSUPPORTED`=4.
The last of those has a history worth keeping: 0.6.0 widened it to cover the
multi-scan deferral (it was `JPEG_SOS`=17 through 0.5.3, which said
"malformed" about a valid file), and **0.8.0 removed that meaning again** when
multi-scan started decoding. 0.9.0 settled the code itself — documented rather
than split, because minting error codes immediately before a freeze is the
opposite of settling the surface ([ADR 0010](../adr/0010-the-v1-surface.md)).
What it covers now: an unrecognised PNG *critical* chunk, a PNG compression or
filter method other than 0, an unrecognised colour type, and an Adobe APP14
transform chitra does not implement or does not recognise.

BMP: `BMP_HEADER`=24, `BMP_DEPTH`=25, `BMP_COMPRESSION`=26 (now **only**
`BI_JPEG` / `BI_PNG`, refused permanently), `BMP_PALETTE`=27, `BMP_RLE`=32
(0.5.1), `BMP_MASK`=33 (0.5.2). GIF: `GIF_HEADER`=28, `GIF_LZW`=29,
`GIF_PALETTE`=30, `GIF_NO_IMAGE`=31.

Caller policy (not a file defect): `BUDGET`=34 (0.6.1), set only by
`chitra_image_decode_budget` — neither a validity failure nor an OOM. Both paths reuse `TRUNCATED`=2, `OOM`=6
and `DIMENSIONS`=10 — the latter is what the 0.5.3 amplification caps raise.

For PNG every byte access is bounds-checked against the input span, CRC-32 is
verified per chunk, and the kii decompression-bomb / lying-IHDR /
dimension-ratio caps reject hostile inputs loud (see
[adr/0002](../adr/0002-security-model.md)).

Two codes are narrower than their names suggest, and the 0.3.2 cut corrected
their stale enum comments in [`src/error.cyr`](../../src/error.cyr):

- **`INTERLACE`=8** fires only when the IHDR interlace **method** is neither
  0 (none) nor 1 (Adam7) — [`png_filter.cyr:171`](../../src/png_filter.cyr).
  Both spec-legal methods decode, so this is an illegal-value rejection, not
  an unsupported-feature one.
- **`BIT_DEPTH`=9** fires only on a bit-depth × color-type combination that
  is not spec-legal per § 11.2.2 Table 11.1 (e.g. ct3+depth16, or ct2/4/6 at
  a sub-byte depth) — [`png_filter.cyr:185`](../../src/png_filter.cyr).

**0.9.0 reworded both strings** to match: "illegal interlace method" and
"illegal bit depth for color type". They previously read as capability limits
("interlace unsupported" / "bit depth unsupported"), which told a consumer the
wrong story about its own file. This changed public `chitra_err_name` output —
which is why it was held for the freeze prep rather than slipped into a patch
release, and why it is a *Behaviour change* in the 0.9.0 CHANGELOG.

## Module map

Source under `src/` — flat domain modules in `[lib].modules` dependency
order. Stdlib includes live **only** in `lib.cyr`.

PNG + shared:

- `error.cyr` (168 L) — the `ChitraErr` model: the `ChitraErrCode` enum
  (now incl. the 13–23 JPEG codes), the 16-byte `GpuErr`-compatible record,
  `chitra_err_*` constructors / accessors / `print_name`, and the
  error-name table. Dep-free.
- `png_chunks.cyr` (283 L) — the bounds-checked `(src, len)` cursor (every
  u8 / u32-BE / skip validated against `len` before access), the 8-byte
  signature check, chunk-type predicates (IHDR / IDAT / IEND / PLTE / tRNS),
  color-type→channels, the shared security ceilings (`MAX_PIXELS`=16777216,
  `MAX_RAW_BYTES`=268435456, `MAX_DIM`=65535) and PNG's own amplification
  ratio `MAX_INFLATE_RATIO`=1100. **The other three ratios live in the modules
  that use them, not here** — `MAX_JPEG_RATIO`=4096 in `jpeg_markers.cyr`,
  `MAX_BMP_RLE_RATIO`=4096 and `MAX_GIF_RATIO`=16384, the last two added in
  0.5.3), and the
  internal `ChitraPngRaw` handoff struct + accessors. The JPEG modules reuse
  this byte cursor.
- `png_filter.cyr` (671 L) — the five § 9 unfilter predictors
  (None / Sub / Up / Average / Paeth), the Adam7 7-pass deinterlace, and
  `chitra_png_parse_raw`: the two-pass chunk walk (CRC-32 each chunk via
  sankoch, parse IHDR, capture PLTE/tRNS spans, concat IDAT, inflate with
  the bomb caps, unfilter into the scanline buffer). Every failure returns
  a `ChitraErr`, never an OOB read.
- `png_color.cyr` (403 L) — `chitra_png_color_to_rgba8`: the canonical-RGBA8
  normalization pass — grayscale → (g,g,g,255), RGB → (r,g,b,255), palette →
  PLTE RGB + per-entry tRNS alpha, gray+alpha → (g,g,g,a), RGBA passthrough,
  with tRNS keying for types 0/2 and sub-byte / 16-bit sample handling.
  PLTE/tRNS are resolved from the original `src` via the captured
  (offset, length) spans, re-validated defensively.
- `png.cyr` (162 L) — the public PNG decode API (`chitra_png_decode` /
  `chitra_png_decode_rgba8`), the 56-byte `ChitraImage` + accessors,
  `chitra_image_free`, the JPEG `src_ctype` sentinel doc, and
  `chitra_version`.

JPEG (0.3.0):

- `jpeg_huffman.cyr` (344 L) — frame-independent Huffman machinery: the
  canonical decode-table representation (`mincode`/`maxcode`/`valptr`/
  `huffval`) built from DHT BITS + HUFFVAL (T.81 Annex C + F) with
  over-subscription rejection; the entropy bit-reader (MSB-first, `0xFF00`
  byte-unstuffing, marker detection + zero-pad past a marker,
  `_chitra_jpeg_br_restart`); the `DECODE` / `RECEIVE` / `EXTEND` procedures; and
  `_chitra_jpeg_decode_block` (one 8×8 block — DC differential + AC run/size with
  ZRL and EOB → 64 zig-zag coefficients).
- `jpeg_idct.cyr` (226 L) — the zig-zag→natural index map, dequantization,
  the libjpeg `jpeg_idct_islow` integer fixed-point 8×8 inverse DCT, the
  `+128` level-shift with `[0,255]` clamp, and `_chitra_jpeg_descale` (signed
  round-to-nearest division, since Cyrius `>>` is logical).
- `jpeg_markers.cyr` (553 L) — `chitra_jpeg_check_signature`,
  `chitra_jpeg_scan_markers` (SOI → segment walk → SOS, parsing SOF0 frame
  header / DQT / DHT / DRI and **rejecting** non-baseline modes), the
  `ChitraJpegFrame` storage, and the JPEG security guards: sampling factors
  clamped 1..4 (rejecting 0 — the CVE-2018-11212 divide-by-zero), duplicate
  component ids rejected, `MAX_DIM`/`MAX_PIXELS` re-checked, plus `MAX_COMPONENTS`=4,
  `MAX_SAMP_FACTOR`=4, `MAX_QUANT_TABLES`=4, `MAX_HUFF_TABLES`=4.
- `jpeg.cyr` (1,056 L) — the public JPEG decode API (`chitra_jpeg_decode` /
  `chitra_jpeg_decode_rgba8`) and the format-sniffing `chitra_image_decode`
  router; `_chitra_jpeg_parse_sos` (scan header — per-scan Td/Ta
  selectors, baseline Ss=0/Se=63/Ah=Al=0, and the § B.2.3 ΣHj·Vj ≤ 10 cap
  conditioned on `Ns > 1`, summed over the *scan's* components, ahead of that
  scan's plane allocation); then the three functions 0.8.0 split
  `_jpeg_decode_scan` into — `_chitra_jpeg_decode_scans` (the driver, terminating on
  the per-component coverage bitmask), `_chitra_jpeg_decode_one_scan` (the
  subsampling-aware MCU loop and plane placement) and `_chitra_jpeg_build_image` (box
  upsample, the BT.601-or-RGB colour pass, the `ChitraImage`) — plus
  `_chitra_jpeg_resume_to_next_scan` and the entropy-span walk. **0.8.0 deleted
  0.6.0's effective-geometry collapse** and replaced it with one general
  § A.1.1 rule: `Ns < Nf` (non-interleaved *and* partially interleaved) now
  **decodes**, and only `Ns < 1` and `Ns > Nf` remain validity failures.

BMP (0.4.0):

- `bmp.cyr` (1,014 L) — the whole BMP path in one module: `chitra_bmp_check_signature`,
  little-endian readers (BMP is LE where PNG and JPEG are BE), the
  `BITMAPFILEHEADER` + DIB header parse into `ChitraBmpHdr`, the deferred-mode
  rejections, the MSB-first index extractor, the `BI_RLE8`/`BI_RLE4` run-length
  decoder (0.5.1 — opcode loop, per-write bounds checks, delta validated at the
  jump), the `BI_BITFIELDS` channel-mask machinery (0.5.2 — shift/width
  extraction, contiguity and overlap validation, and bit-replication widening),
  and `chitra_bmp_decode` / `chitra_bmp_decode_rgba8`. 0.5.3 made the masks
  govern **both** packed depths unconditionally rather than only when an alpha
  mask was declared, gated mask reads on `BI_BITFIELDS` (Microsoft: the V4/V5
  masks are *"valid only if compression is BI_BITFIELDS"*), and added the
  RLE amplification cap — measured on bytes actually **consumed**, since
  padding defeated the first version of it. Depends on `error.cyr` for codes,
  `png_chunks.cyr` for the shared ceilings, and `png.cyr` for `ChitraImage`
  — which is why it comes last in the include order.

GIF (0.5.0):

- `gif_lzw.cyr` (285 L) — the LZW decompressor: LSB-first variable-width bit
  reader, dictionary build, chain expansion, Clear/End handling and the KwKwK
  case. Frame-independent, so it precedes `gif.cyr` in the include order for
  the same reason `jpeg_huffman.cyr` precedes `jpeg_markers.cyr`.
- `gif.cyr` (461 L) — `chitra_gif_check_signature`, the block walk (extensions
  skipped by their sub-block chain, GCE read for transparency), the image
  descriptor and frame geometry, global/local color tables, the 4-pass row
  interlace, and `chitra_gif_decode` / `_rgba8`. 0.5.3 validated the GCE block
  size (fixed at 4, and every field after it addressed by a fixed offset),
  made the transparent index **clear** when a later GCE revokes it, and put
  the amplification cap **before** the allocation it exists to prevent.

Include chain: `lib.cyr` (74 L) pulls the stdlib set then
`error.cyr` → `png_chunks.cyr` → `png_filter.cyr` → `png_color.cyr` →
`png.cyr` → `jpeg_huffman.cyr` → `jpeg_idct.cyr` → `jpeg_markers.cyr` →
`jpeg.cyr` → `bmp.cyr` → `gif_lzw.cyr` → `gif.cyr` (the order in
`[lib].modules`). Domain-module total: **6,300 L** across 12 files, plus
`lib.cyr` (87 L).

## Sizes

- `dist/chitra.cyr` — **~331 KB** (339,306 bytes / 7,034 lines; `cyrius
  distlib` reports 6,991 code lines — the 1.1.1 repairs and their comments, and
  the longer `_CHITRA_` / `_chitra_` names of 1.1.2 and 1.1.3), regenerated by `cyrius distlib`
  (= `make dist`). This is the artifact consumers link, and it **exports 75
  `chitra_*` names, of which 29 are frozen** — the split is
  [`public-surface.md`](public-surface.md), gated by `scripts/check-surface.sh`
  on every `make lint`.

  **Every cut has been ABI-additive.** 0.6.1 added two names
  (`chitra_image_decode_budget` and the internal
  `chitra_jpeg_frame_adobe_transform`) and one error code (`CHITRA_ERR_BUDGET`,
  34); 0.9.0 added exactly one (`chitra_image_source_depth`) and moved no
  offset; 1.0.0 added none — its bundle is name-identical to 0.9.0's; **1.0.1
  adds none either, and one error code** (`CHITRA_ERR_INFLATE_LIMIT`, 35);
  **1.0.2 adds neither** — its bundle differs from 1.0.1's by two lines, the
  header stamp and the `chitra_version()` literal; **1.0.3 adds one internal
  name** (`chitra_jpeg_frame_saw_jfif`) and no error code, so the bundle exports
  75 with the frozen 29 unchanged; **1.0.4 adds neither** — its bundle
  differs from 1.0.3's by the stamp, the `chitra_version()` literal and the
  five-line `Requires` header 6.6.20's distlib now writes.
  Consumers re-pin mechanically.
- `dist/chitra.deps` — the **1**-leaf stdlib sidecar consumers resolve against:
  `string`. ⭐ **3 → 1 at 1.1.0**: sankoch is a named dep now, so it is not a
  stdlib leaf, and the bundle no longer `include`s it — consumers get it from
  chitra's `[deps.sankoch]` transitively (closest-wins), so a consumer that has
  chosen its own sankoch bundle is never handed a second one. Measured on 6.7.9
  with a consumer that has no sankoch of its own: **811,544 → 280,112 B** (DCE
  off), **246,296 → 99,888 B** (DCE on), 36 → 18 stdlib files resolved.
  At 1.0.4 it was 3 (`sankoch`, `alloc`, `string`) — **10 → 3, with no change to
  `src/lib.cyr`**: cyrius 6.6.20's distlib derives the sidecar from the leaves
  the fold *references* and compile-verifies the bundle against exactly those
  (also written as `include` lines at the head of `dist/chitra.cyr`). Proved
  reference-derived by trimming `src/lib.cyr` to five includes and getting the
  identical sidecar. `thread` arrives through sankoch's own
  `include "lib/thread.cyr"`. A consumer with an empty `[deps].stdlib` resolves
  28 stdlib files instead of 35 and links **811,608 → 756,368 B** (DCE off),
  **246,360 → 244,368 B** (DCE on). ⚠ The rest of this bullet is the history
  that 6.6.20 made moot: **Was 13 until 1.0.1.** `args`, `flags` and `vec` were `include`d in
  `src/lib.cyr` and referenced nowhere in the repo — and since `cyrius deps`
  treats this sidecar as **authoritative**, every consumer linked them and could
  not decline. Measured by crab: `flags` alone cost **+8,320 B**, and
  `CYRIUS_DCE=1` reclaimed none of it **on 6.5.35** — that changed later in the
  6.5.x line, and at the `6.6.2` pin DCE does reclaim most of `flags`. ⚠ The
  trim still stands regardless: the sidecar is authoritative, a default build
  has DCE off, and a consumer that knew better could not decline.
  ⚠ Through 6.6.2, an unused include in `src/lib.cyr` was not free and not
  local. At 6.6.20 it costs only chitra's own builds — `assert`, `bench`,
  `fmt`, `io` and `str` are still included and called by nothing in `src/`.
- `build/chitra_smoke` — **~340 KB** (347,912 bytes at 1.1.1 on cyrius 6.7.9
  with the sankoch `zlib` profile; 343,776 at 1.1.0, 803,448 at 1.0.4 with the
  full bundle, 597,256 on 6.6.2, 601,408 on 6.5.35), built from
  `programs/smoke.cyr` (19 L) via `make build`; **36,616 B** with
  `CYRIUS_DCE=1`, as CI builds it (184,952 at 1.0.4, 44,296 on 6.6.2). It only proves the include chain compiles and links
  clean — chitra is a library, there is no real CLI behind it.
  ⚠ The 1.0.4 jump was chitra linking **every** sankoch codec to call two
  functions, as the bundle grew (37,224 → 172,336 B under DCE for a program
  that merely includes the full bundle). Fixed on chitra's side in 1.1.0 by
  linking the `zlib` profile — not a sankoch defect.

## Tests + bench

- `make test` (globs `tests/tcyr/*.tcyr`; each is a standalone `main()`) →
  **3,978 assertions, all pass** across 14 suites (3,086 at 1.1.0; the
  1.1.1 sweep added a cell for every guard a test could not previously see):
  - `alloc_reset.tcyr` — **22** (1.0.2). The
    [architecture/005](../architecture/005-alloc-reset-sankoch-hazard.md)
    reproduction as an assertion: decode → `alloc_reset()` → decode succeeds,
    all 16 RGBA8 bytes identical across the reset, 2,000 decode+reset cycles,
    and a check that `alloc_reset()` genuinely reclaims — without which the
    suite would pass just as well against a no-op. ⚠ Standalone precisely
    because it calls `alloc_reset()`: run inside another suite it would rewind
    an arena that suite's fixtures live in. BMP/JPEG/GIF are deliberately not
    covered — none touch sankoch, so none ever had the hazard.
  - `gif.tcyr` — **772** (signature, plain / interlaced 4×4 and 8×8 /
    transparent / animated-first-frame fixtures with **every pixel asserted**,
    the no-image and bad-min-code-size rejections, a truncation sweep, the
    four-format router, and the 0.5.3 amplification bomb — plain, padded, and
    a real GIF proving the cap does not reject valid input). Fixtures are real ImageMagick GIFs; expectations were
    corroborated by a second independent decoder, which is what caught the
    KwKwK bug.
  - `bmp.tcyr` — **1,265** (signature, 24/32 bpp, 1/4/8 bpp palette,
    `BITMAPCOREHEADER`, bottom-up **and** top-down producing identical output,
    the 32-bpp undefined-alpha heuristic, deferred-mode + malformed-header
    rejections, an out-of-range palette index, a full truncation sweep, the
    three-format router, and the `_rgba8` wrapper; plus the 0.5.1 run-length
    coverage — an ImageMagick-encoded RLE8 file, hand-built RLE4-encoded,
    RLE8-absolute, RLE4-absolute and delta fixtures all cross-checked against
    ImageMagick's decode, and the guard rejections for an out-of-bounds delta,
    an over-long run, a truncated absolute run, an unterminated stream, a
    depth mismatch and a top-down RLE DIB. The RLE4-encoded, RLE8-absolute and
    RLE4-absolute fixtures encode the **same image by three different opcode
    paths**, so they must decode identically. Plus the 0.5.2 mask coverage —
    16 bpp 5-5-5 and 5-6-5, V4 and V5 headers carrying an alpha mask, and the
    three mask rejections: non-contiguous, overlapping, and wider than the
    pixel word; and the 0.5.3 audit regressions — a 32-bpp bitfields file with
    **no** alpha mask whose channels must still be permuted by its masks, a V4
    `BI_RGB` file whose stale masks must be ignored, a bitfields file declaring
    no colour channel, and the RLE amplification bomb both plain and **padded**,
    with a real 1,082-byte RLE8 file proving the cap does not reject valid
    input). Fixture pixel values are
    distinct per position — a decoder with the row order *or* channel order
    wrong returns the right *set* of pixels in the wrong places, and only
    position-sensitive expectations catch that.
  - `error.tcyr` — **20** (error codes, `chitra_err_*` accessors, name
    round-trips, `chitra_version` → 10104).
  - `interlace.tcyr` — **35** (Adam7 cross-checked against the trusted
    non-interlaced decode for 7 color/depth/odd-dimension cases).
  - `jpeg.tcyr` — **462** (marker scan + non-baseline rejection, SOF0
    components + DQT, Huffman table build vs Annex K.3.3, entropy block
    decode, zig-zag + IDCT + dequant known-answers, end-to-end grayscale /
    YCbCr 4:4:4 / 4:2:0 / restart-interval decodes, and a real
    ImageMagick-encoded 16×16 baseline gradient decoded **byte-identical**,
    plus the 0.3.3 bomb-cap / non-segment-marker regressions, and the 0.3.3
    non-interleaved cell **converted in 0.6.0** from a rejection to a bounds /
    no-crash cell — its 2-byte entropy stream encodes one block where the
    corrected grid asks for three, so the reader zero-pads and it proves the
    guard is gone rather than proving conformance; the conformance weight lives
    in `jpeg_noninterleaved.tcyr` on real encoder output).
  - `png.tcyr` — **600** (cursor bounds, all five unfilter predictors, one
    embedded fixture per color type at depth 8/16, palette+tRNS / keyed-color
    fixtures, `_rgba8` wrapper, adversarial rejections, and the 0.3.3
    chunk-ordering / § 5.4 regressions incl. the unknown-ancillary control;
    plus the 0.5.3 tRNS repairs — a sub-byte grayscale key outside the sample
    range, and a palette tRNS placed **before** PLTE).
  - `subbyte.tcyr` — **151** (gray/palette at 1/2/4, multi-row padding,
    sub-byte ct2/4/6 reject).
  - `stream_end.tcyr` — **57** (0.7.0). `chitra_image_seen_iend` for every
    format, in both directions — a suite that only checked the truncated cases
    would pass with the field hardcoded the other way. Its GIF fixture is a
    *structurally valid* file whose LZW sub-block chain ends early, because
    plain truncation mostly rejects and would not reach this path.
  - `budget.tcyr` — **23** (0.6.1). Asserts allocation **costs** with numeric
    bounds, not just return values: the refusal price per format, the exact
    boundary at the output size, that a zero budget refuses, that an ample one
    changes nothing about the decode, and that a budget refusal is never a
    validity opinion. A budget suite that only checked error codes would pass
    with the exhaustion vector wide open.
  - `jpeg_multiscan.tcyr` — **127** (0.8.0). The three-way oracle: at each
    sampling ratio the same image encoded interleaved, as three `Ns=1` scans,
    and as `Ns=1` then `Ns=2`, all held to `djpeg -nosmooth` — nine
    byte-identical. Plus the coverage-bitmask rejections (a component named
    twice, a scan naming nothing new) and `Σ Hj·Vj = 18` decoding when every
    scan is non-interleaved.
  - `namespace.tcyr` — **29** (1.1.2, cc-13; functions 1.1.3). The consumer:
    declares 127 of the global names chitra used through 1.1.1 *after*
    `src/lib.cyr`, each set to 3, and a function for each of the 84 helper names
    chitra used through 1.1.2, each returning 7. It decodes one 7×5 file per
    format against ImageMagick / `djpeg -nosmooth` sums, then checks its globals
    still read 3 and its own functions still answer 7. Against the 1.1.1 sources
    all four decodes fail; against 1.1.2's, PNG and JPEG fail and it SIGSEGVs.
  - `surface.tcyr` — **177** (0.9.0). The frozen surface itself: every
    `ChitraImage` offset pinned individually so a reordering that looks
    harmless in source fails a test, `ChitraErr`'s GpuErr-compatible layout,
    the error-name strings, the four signature predicates accepting their own
    format and rejecting the other three, and `source_depth` across all four
    formats.
  - `jpeg_noninterleaved.tcyr` — **238** (0.6.0; T.81 § A.2). Built on real
    libjpeg-turbo 3.2.0 files, with the regeneration recipe in the suite header
    so the corpus is reproducible. Its source pattern varies in **both** axes
    and gives each 8×8 block a distinct DC level, so a block placed in the wrong
    grid cell moves an asserted pixel instead of hiding in an equal sum. Cells:
    the 1x1 control anchored to `djpeg -nosmooth`; 2x1 / 2x2 / 4x4 each asserted
    **byte-for-byte** against that control; an **exhaustive sweep of all 16
    legal (H,V) pairs**; a 2x1 file with `DRI = 1` (the collapse redefines what
    an MCU is, and Ri counts MCUs); the interleaved 4:2:0 control that must not
    move; the ΣHj·Vj = 24 interleaved rejection that proves the conditioned cap
    is still live; the multi-scan and partially-interleaved cells, **reversed
    in 0.8.0** from pinning a deferral to pinning a decode (the conformance
    weight moved to `jpeg_multiscan.tcyr`); and the `Ns = 0` / `Ns > Nf`
    validity rejections.
- Reference verification is **embedded in the suite**, not a side script:
  the ImageMagick-encoded fixtures live inside `jpeg.tcyr` / `png.tcyr`, so
  a green `make test` *is* the reference cross-check.
- `make fuzz` (every `fuzz/*.fcyr` under **`--poison`**, exactly what CI runs —
  1.1.1, C-7) → **11,649,080 assertions, 0 failures**: PNG 3,344,316, JPEG
  3,447,819, BMP 3,441,177, GIF 1,415,768, ~57 s. 1.1.4 added the last three
  paths no harness reached — PNG's unknown-critical-chunk abort (`fuzz_png`
  mode 9, a CRC-repaired chunk-type rewrite), `CHITRA_ERR_INFLATE_LIMIT`
  (`fuzz_png` mode 10, IHDR geometry against real zlib payloads) and BMP's
  exact RLE amplification cap (`fuzz_bmp` mode 9) — each proven reached by an
  exit-on-entry probe. ⭐ Each harness runs in **heap
  epochs** — every 1,024 cases it sweeps the poison redzones, `alloc_reset()`s
  and drops its memoized fixtures — so peak RSS is JPEG **54 MB** (was 16.3 GB,
  against a 16 GB CI runner), GIF 207 MB (8.7 GB), PNG 6.5 MB, BMP 4.4 MB. Since
  1.1.1 every harness carries a fixture per structurally distinct path, proven
  reached by an exit-on-entry probe (C-8), and a `decode_budget` mode (C-33).
  Before 1.1.1: 10,732,113 unpoisoned assertions over one fixture shape per
  harness. 0.6.0 added a **256-value sweep of the SOF0
  sampling byte** (every value of it is now a live input, including the illegal
  ones that must still reject) and 100,000 entropy-mutation cases behind a
  non-interleaved header — a shape whose entropy bytes never reached the
  bit-reader before 0.6.0, because that header rejected.
  `fuzz_gif.fcyr` carries an **LZW-stream-only**
  mutation mode that leaves the header intact so hostile bits reach the
  decompressor directly.
  This clears the roadmap's *10⁶ iterations clean* bar, not just the
  "a harness exists" bar.
  Each asserts **two** invariants: *survival* (the decoder returns on any
  byte sequence) and *contract* (failure returns 0 **and** sets `*err_out`;
  success leaves it 0) — the second being what a crash-only fuzzer misses,
  and what matters because mabda maps `ChitraErr` onto `GpuErr`.
  - `fuzz_png.fcyr` (559 L) — random bytes, **valid signature + random chunk
    stream**, bit-flipped fixture, full truncation sweep, degenerate lengths.
  - `fuzz_jpeg.fcyr` (1,803 L) — the same shapes plus **entropy-segment-only
    mutation** against the 8×8 and the real 16×16 gradient, so hostile bits
    reach the bit-reader / `DECODE` behind a valid header. Opens with a
    self-check asserting its fixtures decode and its entropy span is wide
    enough to mutate — the first draft silently exercised a 4-byte span, and
    a harness that no-ops is worse than none.
- `make bench` (= `cyrius bench tests/bcyr/chitra.bcyr`) → **17 benchmarks**,
  ~2 s (12 in 0.3.3, +3 BMP in 0.4.0, +1 BMP RLE in 0.5.1, +1 GIF in 0.5.0 — the GIF case carries a
  small greedy **LZW encoder**, because a benchmark built from literal codes
  alone would never make the decoder walk a dictionary chain). The harness **generates its
  fixtures at realistic sizes**
  (256×256) rather than timing the 2×2..16×16 test fixtures, which would
  measure fixed overhead rather than throughput: PNG scanlines go through
  sankoch's `zlib_compress` so the real inflate + unfilter path runs, Adam7
  fixtures are interleaved with chitra's own pass-geometry helpers, and JPEG
  scans are bit-written over the Annex K DC table plus a compact AC table
  with real DC **and** AC coefficients per block. **Every fixture is
  decode-verified before it is timed**, and a failed verification aborts the
  run rather than reporting the cost of the error path.
  `scripts/bench-csv.sh` (= `make bench-record`) stamps results with
  timestamp/commit/branch into [`bench-history.csv`](../../bench-history.csv).
  Deliberately **not** in `make test-all` — benchmark numbers are host- and
  load-dependent, so gating CI on them would be a flake source.
- **Both v1.0 hardening gates are CLOSED as of 0.3.3** — the fuzz harness at
  10⁶ iterations clean, and the benchmark harness with committed CSV history.

### Decode baseline (this host, 256×256 = 65,536 px, minimum of 20 rounds)

| benchmark | ns/px | total |
|---|---|---|
| `bmp_rgb24_256` | 7 | 0.48 ms |
| `bmp_palette8_256` | 11 | 0.71 ms |
| `bmp_rle8_256` | 19 | 1.23 ms |
| `bmp_rgba32_256` | 21 | 1.35 ms |
| `png_gray8_256` | 38 | 2.50 ms |
| `png_palette8_256` | 39 | 2.57 ms |
| `jpeg_gray_256` | 43 | 2.85 ms |
| `gif_lzw_256` | 44 | 2.86 ms |
| `png_rgb8_256` | 52 | 3.38 ms |
| `png_rgba8_256` | 54 | 3.55 ms |
| `png_rgba16_256` | 92 | 6.04 ms |
| `jpeg_ycbcr420_256` | 93 | 6.06 ms |
| `png_rgba8_adam7_256` | 99 | 6.51 ms |
| `jpeg_ycbcr422_256` | 111 | 7.25 ms |
| `jpeg_ycbcr444_256` | 148 | 9.68 ms |

⭐ **1.1.1, best of three runs** — every row within ±2 % of 1.1.0, so the
sweep's repairs (the JPEG structural pre-pass included) cost nothing
measurable. **1.1.0 (cyrius 6.7.9, sankoch 2.8.7 `zlib` profile):**
Every PNG row dropped 22–75 % against 1.0.3 (`png_gray8_256` 10.70 → 2.53 ms,
`png_palette8_256` 10.75 → 2.62 ms) while the JPEG, BMP and GIF rows — which
never call sankoch — stayed within ±3 %: the gain is sankoch 2.8.5's
PCLMULQDQ CRC-32 fold and 2.8.6's inflate decode rewrite, not chitra code.

Fixed cost at 16×16 (throughput-irrelevant — the icon case):
`png_rgba8` **55 µs**, `jpeg_gray` **18 µs** (52 / 17 µs at 1.0.3). ⭐ The PNG figure was **64 µs**
through 1.0.1; the 6.6.2 pin's sankoch 2.7.14 gave `crc32_init_table()` an
early return, so the 16 KB slice-by-8 table is no longer rebuilt on every
decode. This row exists to isolate exactly that kind of per-decode overhead,
and it is the only benchmark the 1.0.2 bump moved.

These are **host- and load-dependent**, and the per-pixel figure includes
inflate, whose cost depends on how the generated fixture compresses — compare
rows from the same host, not across hosts. Adam7 costs ~82 % over the
equivalent non-interlaced rgba8 decode (~54 % before 1.1.0 — the
non-interlaced path gained more from the faster inflate), and JPEG grayscale is the cheapest
path in the library (no chroma planes, no upsample, no color convert).

## Quality gates

All green at 1.1.4 on cyrius 6.7.12:

| gate | command | result |
|---|---|---|
| link check | `make build` | OK, 347,912 bytes (36,616 with `CYRIUS_DCE=1`), no warnings |
| tests | `make test` | 3,978/3,978, 0 failures, 14 suites |
| fuzz | `make fuzz` (`--poison`) | 11,649,080/11,649,080, 0 failures, ~57 s, peak RSS ≤ 207 MB |
| bench | `make bench` / `make bench-build` | 17 benchmarks, fixtures self-verified, ~2 s; CI compiles the harness (`bench-build`, 1.1.1) but does not run it |
| lint | `make lint` | 0 warnings and 0 untracked deferrals (`--strict-deferrals` on since 1.1.1); lint's own exit status is gated |
| fmt | `make fmt-check` | clean |
| vet | `make vet` | 1 dep, 0 untrusted, 0 missing |
| version | `make version-check` | consistent across VERSION, cyrius.cyml, CHANGELOG.md, README.md, `chitra_version()` and every `chitra_version()` claim in this file; fails closed on a missing or restyled README line (1.1.1) |
| dist | `make dist` + `cyrius check --with-deps dist/chitra.cyr` | compiles clean; sidecar 1 leaf (`string`) |
| lock | CI: `cyrius deps --locked`, then `git diff --exit-code cyrius.lock` | fails on a missing, stale, re-pointed or rewritten lock (1.1.1, C-28); `cyrius deps --verify` 26/26 locally |
| oracle | out-of-tree, 53-file corpus | 52/52 decodable files byte-identical to 1.1.0 (and so to 1.0.3@6.6.2); `jpg_q5.jpg` now refuses as `JPEG_MODE`. Exact vs `djpeg -nosmooth` / ImageMagick except BMP 565/555 bit replication (ffmpeg exact) |
| consumer shape | `make consumer-shape` (1.1.4) | every suite (14, 3,978 assertions) rebuilt with the stdlib `"sankoch"` leaf — the full 2.8.7 bundle of chitra's 6.7.12 pin — in place of the zlib profile; the shape kii / mabda / aethersafha link. Fails on a 6.7.9 pin (stdlib sankoch 2.8.3), at exactly the png-3 floor cells |
| downstream | scratch kii + three consumer shapes against this tree | kii builds; its 5 suites (599 assertions) and 1 M-iteration decode + `alloc_reset()` fuzz pass. No-sankoch, stdlib-`sankoch` and own-`[deps.sankoch]` consumers each link exactly one sankoch bundle and decode correctly |
| anchors | `./scripts/check-anchors.sh --suspect` | **96** anchors, 0 suspicious. Since 1.1.1 (C-36) it also flags a citation that lands on a comment-only line (COMMENT) or away from the backticked identifier it names (IDENT), and **exits 1** when anything is flagged; CHANGELOG.md is excluded alongside `docs/audit/`. ⚠ It still cannot know what an uncited line was meant to say — a citation to a real code line naming no identifier is only checked for landing on code |
| surface | `./scripts/check-surface.sh` | 75 exports, 29 frozen; 37 `ChitraErrCode` members, each named and value-pinned (1.1.1, C-9); 146 top-level globals (1.1.2, cc-13) and 171 functions (1.1.3), every one chitra-prefixed. Run by CI since 1.0.3 (B-9) |

`make version-check` gained a fifth check at 0.3.2: it now packs `VERSION`
as `major*10000 + minor*100 + patch` and diffs it against the literal parsed
out of `chitra_version()` in `src/png.cyr`. That literal is hand-maintained,
and it is exactly what drifted in 0.3.1.

## Dependencies

- **sankoch** — `[deps.sankoch]` tag `2.8.7`, **`zlib` profile**
  (`dist/sankoch-zlib.cyr`, 1.1.0): RFC 1950/1951 `zlib_decompress` +
  `crc32` + `adler32` (DEFLATE is sankoch's, not chitra's — it backs PNG IDAT
  inflate + chunk CRC), and no other codec. Brings its own `alloc` /
  `atomic` / `sync`; the API lock is a BSS cell since 2.8.6, so `thread` is
  gone. The JPEG path takes **no** sankoch — its entropy (Huffman) decode is
  chitra's own.
- **stdlib** (**8** leaves in `[deps].stdlib`; consumers get only the **1**
  in `dist/chitra.deps` — see *Sizes*): `string`, `fmt`, `alloc`, `io`, `str`,
  `syscalls`, `assert`, `bench`. `sankoch` and `thread` left at 1.1.0.
  ⚠ **Was 13 until 1.0.1**,
  which dropped `args`, `flags` and `vec` — declared and referenced nowhere,
  and billed to every consumer because `cyrius deps` treats the dist sidecar as
  authoritative. Resolved by `cyrius deps` into `lib/`.
- **Consumers** (external): ⚠ **five repos carry a `[deps.chitra]`**, not two —
  **mabda** (`gpu_texture_load_png` — a plain dist dep, no C shim;
  `ChitraErr` ⇒ `GpuErr`), **kii**, **jalwa**, **aethersafha** and **crab**.
  kii consumes chitra back: its v1.2.0 PNG re-fold deleted its own decoder and
  adopted `dist/chitra.cyr` (see kii's ADR 0006). Lineage is a one-time fork of
  kii's `src/png.cyr` with **no live dependency** — bugfixes are manual
  backports in both directions. Every name any of the five calls is inside the
  frozen 29.
- **Downstream pins** (chitra does not push, and no pin auto-follows): as of
  2026-10-15 all five — mabda, kii, jalwa, aethersafha, crab — pin
  `tag = "1.0.3"`, one behind 1.0.4. aethersafha's `path = "../chitra"` is now
  commented out, so its tag is live again.

  Every cut since 0.3.1 has been ABI-additive — nothing removed, no offset
  moved — so the bumps are mechanical. ⭐ Re-pinning to 1.1.0 needs no
  manifest change on the consumer side: crab (no sankoch of its own) picks up
  chitra's `zlib` profile transitively; kii, mabda and aethersafha keep the
  full stdlib `sankoch` they declare; jalwa keeps its own `[deps.sankoch]`.
  Error code 35 (`CHITRA_ERR_INFLATE_LIMIT`) is now mapped by kii
  (`PNG_ERR_INFLATE_LIMIT`, kii v1.6.0); crab's 4 MB per-thumbnail budget
  keeps it below the ceiling that produces code 35.

## Next

Per [`roadmap.md`](roadmap.md), which is forward-only (shipped work lives in
[`../../CHANGELOG.md`](../../CHANGELOG.md)). Six audits so far:
[2026-06-26](../audit/2026-06-26-audit.md) (PNG),
[2026-06-27](../audit/2026-06-27-audit.md) (JPEG),
[2026-08-23](../audit/2026-08-23-audit.md) (P-1, PNG + JPEG),
[2026-08-24](../audit/2026-08-24-audit.md) (P-1, BMP + GIF),
[2026-09-10](../audit/2026-09-10-audit.md) (P-1, all four + gate stack),
[2026-10-15](../audit/2026-10-15-audit.md) (P(-1), all four + sankoch boundary + gate stack).

- **1.1.x** — a CI
  consumer-shape leg for the sankoch ≥ 2.8.6 floor; the three fuzz paths still
  unreached; a `bench-history.csv` row per release; downstream consumers green
  on 1.1.x (with kii's error mapping and the sankoch floor checked).
- **1.2.0** — PNG past 16 MiB inflated via `zlib_decompress_capped`.
- **1.x candidates** — SOF1 8-bit JPEG, multi-frame GIF, APNG, progressive JPEG.
- **Accepted risk (PNG amplification), stated rather than quietly fixed**: a
  2,116-byte 1-bit PNG declaring 4096×4096 decodes to 64 MB, and
  `CHITRA_MAX_INFLATE_RATIO` does not catch it — that ratio bounds
  *inflated:IDAT*, while the final RGBA is 32× the inflated scanlines. It is
  **not** repaired, because that file is a complete, valid encoding of a solid
  image: the bomb and the legitimate image are the same file shape, and a ratio
  cap would reject valid PNGs. What distinguished the BMP/GIF cases is that
  those bombs supplied *nothing* — 2 and 4 bytes for 16.7 M pixels. The
  operative bound for PNG is `CHITRA_MAX_PIXELS`, and a caller decoding
  untrusted PNGs should treat 64 MB as the worst case rather than the file
  size.
