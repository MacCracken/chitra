# 0005 — GIF decodes the first frame only

**Status**: Accepted
**Date**: 2026-08-24

## Context

GIF is the fourth and last of the common raster formats chitra set out to
decode, and it is the first one that is not unambiguously *an image*. PNG,
JPEG and BMP each describe exactly one raster. A GIF file describes a
**sequence**: a logical screen, then one or more image descriptors, each
optionally preceded by a Graphic Control Extension carrying a delay and a
disposal method, and often followed by a Netscape application extension
declaring a loop count.

That forces a decision chitra has not had to make before, because every
public entry point since 0.1.0 has had the same shape:

```
encoded bytes  ->  one owned RGBA8 ChitraImage
```

`ChitraImage` is a 48-byte record with a single `pixels` pointer. It has no
frame count, no delay, no disposal method, and no way to express "and then
this". Supporting animation means changing that contract — either widening
`ChitraImage` (which is append-only for mabda's sake, so it *can* grow, but
every consumer accessor would need to learn the new shape) or adding a
parallel multi-frame surface next to the existing one.

Two facts about the actual consumers bear on this:

- **mabda** uses chitra for `gpu_texture_load_png` — it wants one raster to
  upload into one texture. A frame sequence is not a texture.
- **kii** renders images to a terminal as ANSI/ASCII. It consumes
  `chitra_image_decode` and draws the result once.

Neither consumer has asked for animation, and neither has a place to put it.

The counter-pressure is real, though: a GIF whose first frame is a blank or
partial canvas — common in optimised animations, where frame 1 is a
background and later frames patch regions of it — decodes to something that
does not look like what a viewer would show. A first-frame decoder is
**correct** for the frame it decodes and **incomplete** for the file.

## Decision

**`chitra_gif_decode` decodes the first image descriptor in the file and
returns it as a single `ChitraImage`, exactly like every other format.
Subsequent frames are not decoded. `ChitraImage` does not change.**

Specifically, in scope for 0.5.0:

- GIF87a and GIF89a headers.
- The Logical Screen Descriptor, its Global Color Table, and a per-image
  Local Color Table where present (the local table wins for that image).
- LZW decompression of the first image's data, including the interlaced
  4-pass row order.
- Transparency from a Graphic Control Extension that precedes the first
  image descriptor — a transparent index becomes alpha 0.
- Extension blocks before the first image (comment, plain text, application,
  and any unknown extension) are **skipped by their sub-block chain**, not
  parsed. Skipping is what lets an unknown extension be harmless.

Out of scope for 0.5.0, and *not* a silent omission — the surface says so:

- Frames after the first. The file is not rejected for having them; they are
  simply not decoded. A caller that needs them will get frame 1 and no error,
  which is the one place this decision is visibly lossy.
- Disposal methods, frame delays, loop counts. These only mean something
  across a sequence.

`chitra_image_decode` gains GIF to its sniff order, so an existing caller
handed an animated GIF gets its first frame rather than a `SIGNATURE` error.

## Consequences

**Positive**

- **The output contract is unchanged.** Four formats, one shape. Every
  existing consumer gains GIF support on a `[deps.chitra]` re-pin with no code
  change — the same property that made JPEG and BMP cheap to adopt.
- **GIF costs `ChitraImage` no new field** — it was 48 bytes before this decision and after it, and mabda's accessors stay valid. (It reached 56 bytes in 0.9.0 for `src_depth`, per [ADR 0010](0010-the-v1-surface.md) — unrelated to GIF.) The
  append-only field discipline is not spent on a feature no consumer wants.
- **The decode surface stays small.** Disposal methods are a compositing
  model — "restore to background", "restore to previous" — and implementing
  them means keeping a canvas, a previous-canvas, and per-frame rectangles.
  That is a meaningful amount of state to get wrong on untrusted input, and
  none of it is exercised by a first-frame decode.
- It matches what the other pure-decode libraries in this niche do by
  default, and what a texture loader actually needs.

**Negative**

- **An optimised animation's first frame may not be what a viewer shows.**
  If frame 1 is a background plate and the visible content arrives in later
  patches, chitra returns the plate. This is the real cost, it is not
  hypothetical, and it is why the limitation is documented on the public
  entry point rather than buried here.
- A caller cannot tell from the returned `ChitraImage` whether it decoded a
  still GIF or the first frame of a 300-frame animation. There is no frame
  count to inspect.

**Neutral**

- If a consumer later needs animation, the natural shape is a **separate**
  multi-frame entry point (`chitra_gif_decode_frames` or similar) returning a
  frame list, leaving `chitra_gif_decode` untouched. That keeps this decision
  additive rather than something to reverse, and is the path a future ADR
  should take.
- The LZW decompressor written for this cut is frame-agnostic. Adding frames
  later is block-walking and compositing work, not decompression work.

## Alternatives considered

- **Widen `ChitraImage` with a frame array.** Rejected. The record is
  append-only precisely so mabda's offsets stay valid; spending that budget
  on a field every current consumer would ignore is the wrong trade. It also
  makes the single-frame formats carry a frame concept they do not have.
- **A parallel multi-frame surface, now.** Rejected as premature, not as
  wrong — see *Neutral* above. Building a compositing model against untrusted
  input with no consumer to validate it against is how you ship a feature
  that is both unused and a liability. When a consumer needs it, the shape is
  already sketched.
- **Composite all frames down to one image and return that.** Rejected, and
  it is the most tempting option because it *looks* like it fixes the
  optimised-animation problem. It does not: compositing to a single raster
  requires choosing a moment in time, and there is no correct choice — the
  "right" answer is the last frame for some files, the first for others, and
  a mid-sequence frame for a file whose animation ends on a blank. Worse, it
  makes decode cost proportional to frame *count* rather than image size, so
  a small file with thousands of tiny frames becomes an amplification vector
  the size caps do not bound. Returning one honest frame beats guessing at a
  composite.
- **Reject animated GIFs outright** (decode only single-frame files).
  Rejected. It is the defer-don't-half-implement posture applied one notch
  too far: the first frame of an animated GIF is a real, correctly-decoded
  image, and refusing it would deny a consumer something chitra demonstrably
  has. The posture exists to stop chitra *mis-rendering* — it should not stop
  it rendering correctly.

## References

- CompuServe GIF89a specification —
  <https://www.w3.org/Graphics/GIF/spec-gif89a.txt>
- [`0004-jpeg-decode-model.md`](0004-jpeg-decode-model.md) — the
  defer-don't-half-implement posture this decision deliberately does *not*
  extend to animated files.
- [`0003-mabda-abi-compatibility.md`](0003-mabda-abi-compatibility.md) — why
  `ChitraImage` growth is expensive.
- [`../development/roadmap.md`](../development/roadmap.md) — the 0.5.x arc
  that gated this decision on an ADR before code.
