# chitra — the public surface

> The list `scripts/check-surface.sh` checks `dist/chitra.cyr` against. Every
> `chitra_`-prefixed function in the bundle must appear in exactly one of the
> two blocks below, so a name cannot appear or vanish unnoticed. Note what the
> gate does and does not check: it compares the **union** of the two blocks
> against the bundle. *Which* block a name sits in — and therefore whether it
> is promised — is enforced by review, not by the script.
>
> This file is a **contract**, not documentation of one. Prose about what these
> functions do lives in [`../guides/getting-started.md`](../guides/getting-started.md)
> and in the source.

## Why this file exists

`dist/chitra.cyr` is a strip-concatenated bundle, so *every* `chitra_`-prefixed
function in it is callable by a consumer whether or not it was meant to be.
Before this file, "the surface is frozen" was an assertion with nothing behind
it: 45 of the 74 exported names are internal, and nothing distinguished them
from the 29 that are not.

The distinction matters most at v1.0, because the promise being made is about
the FROZEN block only, and it is now in force. A consumer reaching into the INTERNAL block is not
covered by it — and the names there are deliberately not `_`-prefixed only
because renaming 45 functions immediately before a freeze is a large churn
diff for zero runtime benefit, with a real risk of a typo silently disabling a
test.

## The promise, and its edges

**In force as of 1.0.0.** What it covers: the names in **FROZEN** below, the
`ChitraImage` and `ChitraErr` layouts under **Records**, and the *numeric
values* of `ChitraErrCode`. Changing a signature, removing a name, or changing
documented behaviour there is a **major bump plus an ADR**.

What it does **not** cover, stated because a promise with unstated edges is not
a promise:

- **The INTERNAL_NAMES block.** May change or disappear in any release.
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

## INTERNAL_NAMES

Visible in `dist/chitra.cyr` and **not frozen**. These exist because the bundle
is a flat concatenation, not because they are an API. They may change or
disappear in any release.

```
chitra_raw_bit_depth             chitra_raw_channels
chitra_raw_color_type            chitra_raw_free
chitra_raw_height                chitra_raw_interlace
chitra_raw_plte_len              chitra_raw_plte_off
chitra_raw_scanlines             chitra_raw_scanlines_len
chitra_raw_seen_iend             chitra_raw_trns_len
chitra_raw_trns_off              chitra_raw_width
chitra_png_parse_raw             chitra_png_color_to_rgba8
chitra_png_color_channels
chitra_bmp_hdr_bpp               chitra_bmp_hdr_height
chitra_bmp_hdr_width
chitra_jpeg_scan_markers         chitra_jpeg_frame_free
chitra_jpeg_frame_width          chitra_jpeg_frame_height
chitra_jpeg_frame_precision      chitra_jpeg_frame_num_components
chitra_jpeg_frame_seen_sof       chitra_jpeg_frame_max_h
chitra_jpeg_frame_max_v          chitra_jpeg_frame_restart_interval
chitra_jpeg_frame_quant          chitra_jpeg_frame_quant_present
chitra_jpeg_frame_huff           chitra_jpeg_frame_huff_present
chitra_jpeg_frame_sos_offset     chitra_jpeg_frame_comp_id
chitra_jpeg_frame_comp_h         chitra_jpeg_frame_comp_v
chitra_jpeg_frame_comp_tq        chitra_jpeg_frame_adobe_transform
chitra_jpeg_frame_scan_ns        chitra_jpeg_frame_covered
chitra_jpeg_scan_comp            chitra_jpeg_scan_td
chitra_jpeg_scan_ta
```

## Records

Not functions, but part of the same promise:

- **`ChitraImage`** — 56 bytes. Fields are **append-only**: `width`@0,
  `height`@8, `pixels`@16, `channels`@24, `seen_iend`@32, `src_ctype`@40,
  `src_depth`@48. mabda's accessors were compiled against the 0.1.x offsets and
  every field added since has gone on the end. `tests/tcyr/surface.tcyr` pins
  each offset.
- **`ChitraErr`** — 16 bytes, `+0` code, `+8` detail ptr, layout-compatible
  with mabda's `GpuErr` (ADR 0003). This is the one record that cannot be
  widened at all.

## Known consumers

Recorded because they decide what a rename actually costs:

- **mabda** — `chitra_png_decode_rgba8`, `chitra_jpeg_decode_rgba8`. Two names.
- **kii** — nine names: `chitra_image_decode`,
  `chitra_image_{width,height,pixels,seen_iend,source_color_type}`,
  `chitra_png_check_signature`, `chitra_jpeg_check_signature`,
  `chitra_err_code`. Counted by **call site**: `chitra_err` appears in kii only
  inside its own `_kii_map_chitra_err`, which is a kii function, not a call
  into chitra.

Both stay inside the FROZEN block.
