# 0010 — What v1.0 freezes, and the four calls made to get there

**Status**: Accepted
**Date**: 2026-08-24

## Context

v1.0 promises that the public surface will not change without a major bump. The
roadmap carried a list of things to settle first, on the grounds that each one
"changes the public surface, which is precisely what a freeze makes expensive to
do later". 0.9.0 settles them.

Two facts shaped every decision below, and both are measured rather than
assumed — they are what the consumers actually call:

- **mabda** uses two names: `chitra_png_decode_rgba8`,
  `chitra_jpeg_decode_rgba8`.
- **kii** uses ten: `chitra_image_decode`, `chitra_image_{width,height,pixels,
  seen_iend,source_color_type}`, `chitra_png_check_signature`,
  `chitra_jpeg_check_signature`, `chitra_err`, `chitra_err_code`.

A rename is cheap in the abstract and expensive against that list.

## Decision

**v1.0 freezes 29 names**, enumerated in
[`../development/public-surface.md`](../development/public-surface.md) and
machine-checked by `scripts/check-surface.sh`, plus the `ChitraImage` and
`ChitraErr` record layouts. The other **45** `chitra_`-prefixed functions in
`dist/chitra.cyr` are named there too, in an `INTERNAL_NAMES` block, and are
explicitly **not** covered.

### 1. `chitra_image_seen_iend` keeps its name

It is a PNG concept ("did an IEND chunk close the stream?") exposed on four
formats, and 0.7.0 generalised its *meaning* to "did the stream end the way its
format says it should" — which is honest but leaves the name odd. Nothing
outside PNG has an IEND.

**Kept anyway, because kii calls it.** A rename buys a better name and costs a
real consumer a real edit, at the exact moment the project is promising
stability. Renaming is also not free later: the alternative — shipping both
names and deprecating one — is worse, because a frozen surface with two names
for one field is a surface that has to explain itself forever.

The generalised meaning is documented on the accessor, per format. That is
where a consumer looks.

### 2. `ChitraImage` gains `src_depth` (+48), and the record grows to 56 bytes

The output is always 8 bits per channel, so a consumer could not tell that
precision had been discarded: a depth-16 PNG and a depth-8 one were
indistinguishable in the result, and § 13.13 rescaling is lossy by
construction.

**Added before the freeze, because adding it after is an ABI event.** The field
is append-only — `width`@0 through `src_ctype`@40 keep their offsets, so
mabda's accessors are unaffected — and `tests/tcyr/surface.tcyr` pins every
offset so a reordering that looks harmless in source fails a test.

It reports bits per **channel** in the source: the IHDR depth for PNG (1/2/4/8/
16), 8 for baseline JPEG and for GIF palette entries, and for BMP the widest
declared channel (8 for 24/32 bpp, 5 or 6 for the packed 16-bpp layouts) —
which is the number the RGBA8 output was bit-replicated *up from*.

### 3. `CHITRA_ERR_UNSUPPORTED` stays one code, fully documented

It covers several situations across two formats: an unrecognised PNG *critical*
chunk, a PNG compression or filter method other than 0, an unrecognised colour
type, and an Adobe APP14 colour transform chitra does not implement or does not
recognise.

**Splitting it would mint error codes immediately before a freeze**, which is
the opposite of settling the surface — and each new code is itself a permanent
name. The shared meaning is real and precise: *the file is valid; chitra
declines it*. What was wrong was the one-line enum comment describing one of
the cases as though it were all of them, which is how the drift went unnoticed.
The comment now enumerates them.

Note the set shrank on its own: 0.6.0 added a multi-scan meaning and **0.8.0
removed it** when multi-scan started decoding, and the non-baseline JPEG modes
never used this code — they carry their own (19..23).

### 4. The 45 internal names are not renamed

They are visible in the bundle because `cyrius distlib` strip-concatenates, not
because they are an API. The tidy answer is `_chitra_*` prefixes.

**Rejected.** It is ~45 renames across `src/` plus 75 call sites in the test
suites, immediately before a freeze, for zero runtime benefit and a real risk
that a typo silently disables a test rather than failing it. The deliverable
that actually matters is *saying which names are which*, and that is what
`public-surface.md` and its check script do. The rename can happen in any later
release without touching the frozen set — it is a non-breaking change by
construction, because nothing frozen is being renamed.

## Consequences

**Positive**

- "The surface is frozen" is now checkable. `scripts/check-surface.sh` fails
  both when the bundle exports a name the manifest does not classify (a promise
  made by accident) and when the manifest lists one the bundle no longer has (a
  removal that slipped through). It is wired into `make lint`, and both
  directions were proven to fire.
- The two error-name strings that misdescribed validity rejections as capability
  limits are fixed *before* the freeze makes them expensive.
- Both consumers stay entirely inside the frozen block.

**Negative**

- `chitra_err_name` output changed for two codes. Anything matching those
  strings must update — the strings were wrong, but this is still a change, and
  it is in the 0.9.0 CHANGELOG under *Behaviour changes* for that reason.
- `ChitraImage` grew 48 → 56 bytes. Append-only, so no offset moved, but a
  consumer that allocates the record itself (nothing in-tree does) must widen.
- Keeping `seen_iend` means shipping a v1.0 with a name that will read as a
  historical accident. That is the price of not charging kii for a rename.

**Neutral**

- The internal-name rename remains available and non-breaking whenever someone
  wants it.

## Status at 1.0.0

**In force.** 1.0.0 shipped the freeze with no code change beyond the version
literal — the diff is `VERSION`, `chitra_version()` → 10000, two test
assertions, and documentation. That property is why 0.9.0 and 1.0.0 are two
cuts rather than one: a release that promises the surface will stop moving
should not be the release that moves it.

The promise's edges are stated in
[`../development/public-surface.md`](../development/public-surface.md) and in
the 1.0.0 CHANGELOG entry, and one of them is worth repeating here because it
follows from a decision above rather than from convention. **Bit-exact output
across releases is deliberately not frozen.** The contract is *correct* RGBA8
held to external oracles, so a repair that moves bytes toward the oracle is a
bug fix. 0.7.1's § 13.13 depth-16 rescaling changed the output of every 16-bit
PNG and was one; freezing bit-exactness would have frozen the bug it fixed.

## References

- [`../development/public-surface.md`](../development/public-surface.md) — the
  list, and what each block promises.
- `scripts/check-surface.sh` — the gate.
- `tests/tcyr/surface.tcyr` — record offsets, error names, and the accessors,
  as assertions.
- [`0003-mabda-abi-compatibility.md`](0003-mabda-abi-compatibility.md) — why
  `ChitraErr` is the one record that cannot be widened.
