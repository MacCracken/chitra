# chitra — the public surface

> The list `scripts/check-surface.sh` checks `dist/chitra.cyr` against. Since
> 1.2.0 the rule is a single equality: **the `chitra_`-prefixed functions in the
> bundle are exactly the FROZEN names below** — nothing more, nothing less.
> Everything else chitra defines is `_chitra_*` / `_CHITRA_*`, and the same script
> fails on any top-level `fn` or `var` without a chitra prefix. So the public
> prefix *is* the promise: a new `chitra_*` function cannot appear without being
> added here, which is a decision, and a frozen one cannot vanish unnoticed. (Through
> 1.1.4 a second, INTERNAL_NAMES block listed 46 visible-but-unpromised
> `chitra_*` names, and which block a name sat in was enforced only by review.)
> Since 1.1.1 the same
> script also fails when a member of the bundle's `enum ChitraErrCode` has no
> `chitra_err_name` arm or no literal value pin in `tests/tcyr/surface.tcyr`,
> because the promise covers the enum's numeric values and a new member could
> otherwise ship unpinned.
>
> This file is a **contract**, not documentation of one. Prose about what these
> functions do lives in [`../guides/getting-started.md`](../guides/getting-started.md)
> and in the source.

## Why this file exists

`dist/chitra.cyr` is a strip-concatenated bundle, so *every* function in it is
callable by a consumer whether or not it was meant to be. Before this file, "the
surface is frozen" was an assertion with nothing behind it: 45 of the then-74
exported `chitra_*` names were internal, and nothing distinguished them from the
29 that are not.

At the 1.0.0 freeze the internal names were classified rather than renamed —
renaming 45 functions immediately before a freeze was a large churn diff for
zero runtime benefit. **1.2.0 did the rename**: the 46 internal `chitra_*` names
(the parsed-PNG `chitra_raw_*` accessors, `chitra_png_parse_raw` /
`chitra_png_color_to_rgba8` / `chitra_png_color_channels`, the
`chitra_bmp_hdr_*` and `chitra_jpeg_frame_*` / `chitra_jpeg_scan_*` accessors and
`chitra_jpeg_scan_markers`) are now `_chitra_*`, so the prefix itself says what
is promised. No consumer called any of them; the rename got a minor bump rather
than a patch because names that had been visible since 0.x went away.

## The promise, and its edges

**In force as of 1.0.0.** What it covers: the names in **FROZEN** below, the
`ChitraImage` and `ChitraErr` layouts under **Records**, and the *numeric
values* of `ChitraErrCode`. Changing a signature, removing a name, or changing
documented behaviour there is a **major bump plus an ADR**.

What it does **not** cover, stated because a promise with unstated edges is not
a promise:

- **Anything `_chitra_*` or `_CHITRA_*`.** Internal by name: it may change or
  disappear in any release. (Through 1.1.4 that was the INTERNAL_NAMES block.)
- **Bit-exact output across releases.** The contract is *correct* RGBA8, held
  to external oracles. A repair that moves bytes toward the oracle is a bug
  fix, not a break — 0.7.x's § 13.13 depth-16 rescaling changed the output of
  every 16-bit PNG and was one.
- **Error strings.** Codes are frozen; `chitra_err_name`'s text is not. Two
  strings changed in 0.9.0 for exactly this reason. Match on
  `chitra_err_code`.
- **Memory behaviour.** The never-free bump allocator and the no-op
  `chitra_image_free` are a current fact about the stdlib
  ([`../architecture/003-bump-allocator-no-free.md`](../architecture/003-bump-allocator-no-free.md)),
  not a guarantee.

## FROZEN

The 29 names covered by the promise above.

### Decode entry points

```
chitra_png_decode                chitra_png_decode_rgba8
chitra_jpeg_decode               chitra_jpeg_decode_rgba8
chitra_bmp_decode                chitra_bmp_decode_rgba8
chitra_gif_decode                chitra_gif_decode_rgba8
chitra_image_decode              chitra_image_decode_budget
```

### Signature predicates

```
chitra_png_check_signature       chitra_jpeg_check_signature
chitra_bmp_check_signature       chitra_gif_check_signature
```

### ChitraImage accessors

```
chitra_image_width               chitra_image_height
chitra_image_pixels              chitra_image_channels
chitra_image_seen_iend           chitra_image_source_color_type
chitra_image_source_depth        chitra_image_free
```

### Error API

```
chitra_err                       chitra_err_new
chitra_err_code                  chitra_err_detail
chitra_err_name                  chitra_err_print_name
```

### Version

```
chitra_version
```

## Internal names

There is no list: since 1.2.0 an internal function or global is one whose name
starts with `_chitra_` / `_CHITRA_`, and `check-surface.sh` fails on any
`chitra_*` function that is not in FROZEN above, and on any top-level `fn` or
`var` with no chitra prefix at all. 1.1.2 and 1.1.3 prefixed the 128 globals and
84 helpers that had none; 1.2.0 renamed the 46 that had the *public* prefix.

## Records

Not functions, but part of the same promise:

- **`ChitraImage`** — 56 bytes. Fields are **append-only**: `width`@0,
  `height`@8, `pixels`@16, `channels`@24, `seen_iend`@32, `src_ctype`@40,
  `src_depth`@48. Four consumers read the record through the accessors — kii,
  jalwa, aethersafha and crab — and mabda reaches the pixels through
  `chitra_png_decode_rgba8` without touching the record at all, so every field
  added since 0.1.x has gone on the end. `tests/tcyr/surface.tcyr` pins each
  offset.
- **`ChitraErr`** — 16 bytes, `+0` code, `+8` detail ptr, layout-compatible
  with mabda's `GpuErr` (ADR 0003). This is the one record that cannot be
  widened at all.

## Known consumers

Recorded because they decide what a rename actually costs:

⚠ **There are five, not two.** Counted by **call site** at the 1.0.2 cut:

- **mabda** — `chitra_png_decode_rgba8`, `chitra_jpeg_decode_rgba8`. Two names.
  It never touches `ChitraImage` or `ChitraErr`.
- **kii** — **eleven** names: `chitra_image_decode`,
  `chitra_image_{width,height,pixels,seen_iend,source_color_type}`, and all
  four signature predicates
  (`chitra_{png,jpeg,bmp,gif}_check_signature` — the BMP and GIF two arrived
  with kii v1.5.0), plus `chitra_err_code`. `chitra_err` appears in kii only
  inside its own `_kii_map_chitra_err`, which is a kii function, not a call
  into chitra.
- **crab** — six names: `chitra_image_decode_budget`, `chitra_err_code`,
  `chitra_image_{width,height,pixels}`, `chitra_image_free`, plus the enum
  value `CHITRA_ERR_BUDGET`.
- **aethersafha** — five: `chitra_image_decode`,
  `chitra_image_{width,height,pixels}`, `chitra_image_free`.
- **jalwa** — four: `chitra_image_decode`,
  `chitra_image_{width,height,pixels}`.

All five stay inside the FROZEN block.
