# 001 — `lib/` must be a real directory, never a symlink

Non-obvious invariant that a reader cannot derive from the code alone. This
note describes *how the world is*, not *what we chose* (decisions live in
[`../adr/`](../adr/)) and not *how to do something* (guides live in
[`../guides/`](../guides/)).

## The invariant

`lib/` holds the **resolved** dependency tree that `cyrius deps` writes after
reading the `[deps.*]` tables in [`../../cyrius.cyml`](../../cyrius.cyml): the
cyrius stdlib (`string`, `fmt`, `alloc`, `io`, `vec`, `str`, `syscalls`,
`assert`, `bench`, `args`, `flags`, `sankoch`, `thread`). It is a build
artifact — a local, repo-owned *copy* of those modules.

> **`lib/` must be a real directory populated by `cyrius deps`. It must never
> be a symlink.**

## Why a symlink is dangerous

It is tempting to point `lib/` at a cyrius toolchain checkout (e.g.
`ln -s ~/.cyrius/stdlib lib`) to "save a copy". Do not.

chitra is edited by agents and humans who treat everything under the repo root
as fair game. If `lib/` is a symlink into a toolchain checkout, then any edit to
`lib/*.cyr` — a debug `print`, a quick experiment in `sankoch`, an automated
refactor that globs the tree — **writes across repository boundaries** and
silently corrupts the shared toolchain. Every other project resolving the same
stdlib then inherits the corruption, and the blast radius is invisible from
inside chitra: the diff lands in a directory `git` here does not track.

A real `lib/` directory makes those edits land in chitra's own (gitignored)
artifact, where they are at worst discarded by the next `cyrius deps` and at
best obviously local.

This is also why stdlib includes are confined to
[`../../src/lib.cyr`](../../src/lib.cyr) (see
[`002-flat-modules-distlib-concatenation.md`](002-flat-modules-distlib-concatenation.md)):
the dependency surface is centralized, so `lib/` is the *only* place resolved
deps live and the only place this hazard exists.

## What enforces it

The [`../../Makefile`](../../Makefile) `check-lib-wiring` target is a prerequisite
of every build/test target (`build`, `test`, and transitively `test-all`). It
refuses to run if `lib` is a symlink:

```make
check-lib-wiring:
	@if [ -L lib ]; then \
		echo "ERROR: lib/ is a symlink ($$(readlink lib))."; \
		echo "       chitra's lib/ must be a real directory populated by"; \
		echo "       'cyrius deps'. Fix: rm lib && mkdir lib && cyrius deps"; \
		exit 1; \
	fi
```

Because `build` and `test` both depend on `check-lib-wiring`, a symlinked
`lib/` fails the build *before* any compilation — you cannot accidentally
produce `build/chitra_smoke` or run the `tests/tcyr/*.tcyr` suites against a
cross-linked dependency tree.

## What it affects

Every `make` target that touches the dependency tree. If the guard fires, no
build/test/dist work proceeds until `lib/` is a real directory again.

## The fix

If you find `lib/` is a symlink (the guard will tell you), replace it:

```sh
rm lib && mkdir lib && cyrius deps
```

`cyrius deps` re-resolves the `[deps.*]` tables in
[`../../cyrius.cyml`](../../cyrius.cyml) into the fresh real directory, and the
guard passes on the next `make`.

## See also

- [`002-flat-modules-distlib-concatenation.md`](002-flat-modules-distlib-concatenation.md)
  — why stdlib includes live only in `src/lib.cyr`.
- [`003-bump-allocator-no-free.md`](003-bump-allocator-no-free.md)
- [`../../CLAUDE.md`](../../CLAUDE.md) — project ground rules.
