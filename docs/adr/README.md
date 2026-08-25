# Architecture Decision Records

Decisions about chitra — what we chose, the context, and the consequences we accept. Use these when a future reader would reasonably ask *"why did we do it this way?"*

## Conventions

- **Filename**: `NNNN-kebab-case-title.md`, zero-padded to four digits. Never renumber.
- **One decision per ADR.** If a decision supersedes a prior one, add a new ADR and set the old one's status to `Superseded by NNNN`.
- **Status lifecycle**: `Proposed` → `Accepted` → (optionally) `Superseded` or `Deprecated`.
- Use [`template.md`](template.md) as the starting point.

## ADR vs. architecture note vs. guide

| Kind | Lives in | Answers |
|---|---|---|
| ADR | `docs/adr/` | *Why did we choose X over Y?* |
| Architecture note | [`docs/architecture/`](../architecture/README.md) | *What non-obvious constraint is true about the code?* |
| Guide | [`docs/guides/`](../guides/getting-started.md) | *How do I do X?* |

Durable rationale belongs in an ADR; non-obvious code invariants belong in an architecture note. Volatile state — versions, sizes, counts, in-flight work — lives only in [`docs/development/state.md`](../development/state.md), never here.

## Index

| ADR | Status | Subject |
|---|---|---|
| [0001](0001-fork-kii-png-decoder.md) | Accepted | Fork kii's PNG decoder into the chitra package (one-time fork, manual backports, no live dependency) |
| [0002](0002-security-model.md) | Accepted | Security model: untrusted-image input + library/no-emit posture |
| [0003](0003-mabda-abi-compatibility.md) | Accepted | mabda ABI compatibility: 16-byte GpuErr-compatible `ChitraErr` + append-only `ChitraImage` |
| [0004](0004-jpeg-decode-model.md) | Accepted | JPEG decode model: JFIF baseline sequential Huffman 8-bit only; integer fixed-point IDCT; non-baseline modes cleanly rejected |
| [0005](0005-gif-first-frame-only.md) | Accepted | GIF decodes the **first frame only** — `ChitraImage` keeps its one-image shape, so animation is not represented; a multi-frame surface would be a separate, additive entry point |
| [0006](0006-defer-jpeg-multiscan-resumption.md) | Accepted | T.81 § A.2: decode the **one-component** non-interleaved class via an effective-geometry collapse; defer multi-scan and partially-interleaved files (`Ns < Nf`) behind one guard, with `CHITRA_ERR_UNSUPPORTED` rather than a validity error |
| [0007](0007-byte-budget-surface-deferred.md) | Accepted | The byte-budget / streaming decode surface: **decision in 0.6.0, implementation in 0.6.1**, because a probe routed through the JPEG header parser spends 22,096 bytes before it can refuse — making a memory-ceiling API an exhaustion vector on its own refusal path |
| [0008](0008-byte-budget-as-shipped.md) | Accepted | The budget surface as shipped: **two names, not eight** — a published byte *count* gets consumed as a number, and 0.6.1 moved the JPEG figure by ~21 KB. Discharges 0007's prerequisite via lazy table allocation plus a structural dimension read |
| [0010](0010-the-v1-surface.md) | Accepted | **In force as of 1.0.0.** What v1.0 freezes: 29 names of 74 exports, both record layouts, and the four calls made to get there — `seen_iend` keeps its name because kii calls it, `src_depth` lands before the freeze rather than after, `CHITRA_ERR_UNSUPPORTED` is documented rather than split, and the 45 internal names are classified rather than renamed |
| [0009](0009-jpeg-colour-transform.md) | Accepted | A 3-component JPEG is not necessarily YCbCr: read the Adobe APP14 transform, else the SOF0 component ids, else YCbCr — after `cjpeg -rgb` output decoded hue-rotated with no error |
