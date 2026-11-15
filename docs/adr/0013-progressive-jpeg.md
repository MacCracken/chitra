# 0013 — Progressive JPEG: coefficient buffering, and the progression as the work bound

**Status**: Accepted — answers [ADR 0004](0004-jpeg-decode-model.md)'s open decode-model question
**Date**: 2026-11-14

## Context

The roadmap kept progressive JPEG (SOF2) as the one genuine deferral, to be
revisited "when a consumer demonstrably needs it". selah — the AGNOS
screenshot / annotation library, whose Rust version opens these files — filed
that need on 2026-11-14: progressive JPEGs are common on the web, so in what
users screenshot and annotate.

A progressive scan codes a **band** of zig-zag positions (Ss..Se) to a **bit
position** (Ah → Al), and later scans refine what earlier ones left, so the
baseline pipeline (entropy decode → IDCT → plane, one block at a time) cannot
decode it. There is also a work question baseline never had: an AC scan can
cover every block with a few bytes (EOBRUN reaches 32,767), so a scan's cost is
not proportional to its entropy, and repeated scans could make a small file
arbitrarily slow.

## Decision

**chitra decodes progressive JPEG with a whole-image coefficient buffer per
component** (16-bit, natural order — libjpeg's `JCOEF`), each scan updating it,
and **one IDCT pass after the last scan** into the same planes baseline fills;
upsampling and colour are unchanged. Quantization tables are latched at each
component's first scan, as libjpeg latches them. The four scan kinds follow
libjpeg-turbo's `jdphuff.c` exactly. 16-bit quantization tables, which libjpeg
writes under SOF2 at low quality, are accepted for a progressive frame (and
still refused for a baseline one).

**The work bound is the progression, enforced** — where libjpeg only warns:
for every component and coefficient, the first scan must be `Ah = 0` on a
coefficient never coded and each subsequent one `Ah` = the previous `Al`, with
`Al = Ah − 1` and `Al ≤ 13`; an AC scan names one component and needs its DC
first. A coefficient is therefore visited by at most 14 scans, and an accepted
file's coefficient work is a constant multiple of one baseline decode. Because
each scan also walks every block it covers, **a file may carry at most 256
scans** (real encoders write 6–20), counted by the allocation-free structural
pre-pass and refused as `CHITRA_ERR_DIMENSIONS` before any buffer exists.
Malformed entropy (a run or ZRL leaving the band, a refinement symbol whose size
is not 1, a new refinement coefficient with nowhere to land) is refused rather
than guessed at.

A file that ends early still decodes, with `seen_iend = 0`, if every component
had its DC scan; a component with none is refused, as baseline refuses an
omitted one.

## Consequences

- **Positive** — progressive files decode byte-identically to `djpeg` (93
  files: every sampling, restart intervals, quality 1 and 5, `jpegtran`,
  ImageMagick's writer, four-level successive approximation). The fuzz harness
  gains a progressive mode whose cases also run through a counting allocator.
- **Negative** — a progressive decode holds the coefficient buffers (128 B per
  block, about 2× the planes) on top of the planes and output.
  `CHITRA_ERR_JPEG_PROGRESSIVE` (19) is now unreachable and stays defined,
  because the enum's values are frozen. Some files libjpeg decodes with a
  "bogus progression" warning are refused.
- **Neutral** — the decoder gained a module (`src/jpeg_prog.cyr`, after
  `jpeg.cyr` in `[lib].modules`).

## Alternatives considered

- **libjpeg's lenience on progression.** It decodes on with a warning, and so
  admits files whose cost is unbounded by their size. A strict rule refuses
  only files no conforming encoder writes.
- **No scan ceiling.** The progression alone bounds coefficient visits, but not
  per-scan block walks: a ~900-scan file costs seconds on 16.7 MP.
