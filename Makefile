# Makefile for chitra
#
# Most commands delegate to the `cyrius` CLI, which reads cyrius.cyml.
# chitra is a pure-Cyrius CPU library — no GPU, no C shim, no external
# binaries — so every target is host-runnable.
#
# Quick reference:
#   make test           — CPU-only tests (globs tests/tcyr/*.tcyr domain suites)
#   make fuzz           — adversarial-input harnesses, poisoned (fuzz/*.fcyr)
#   make bench          — decode benchmarks (tests/bcyr/chitra.bcyr)
#   make bench-build    — compile the bench harness without running it
#   make bench-record   — bench + append to bench-history.csv
#   make build          — link-check the library (programs/smoke.cyr)
#   make dist           — regenerate dist/chitra.cyr via `cyrius distlib`
#   make lint / fmt-check / vet  — quality gates
#   make version-check  — VERSION / cyrius.cyml / CHANGELOG / README /
#                         chitra_version() agree
#   make check-surface  — dist exports vs docs/development/public-surface.md
#   make count-assertions — NUL-safe assertion total across suites
#   make consumer-shape — every suite in the stdlib-"sankoch" consumer shape
#   make test-all       — version-check + dist regen + CPU tests +
#                         consumer-shape + fuzz + bench-build
#   make clean          — scrub build/

CYRIUS ?= cyrius

# ---------------------------------------------------------------------------
# Lib-wiring guard — refuses to build if lib/ is a symlink to a cyrius
# checkout (causes cross-repo writes when an agent edits lib/*.cyr).
# lib/ must be a real directory populated by `cyrius deps`.
# ---------------------------------------------------------------------------
.PHONY: check-lib-wiring
check-lib-wiring:
	@if [ -L lib ]; then \
		echo "ERROR: lib/ is a symlink ($$(readlink lib))."; \
		echo "       chitra's lib/ must be a real directory populated by"; \
		echo "       'cyrius deps'. Fix: rm lib && mkdir lib && cyrius deps"; \
		exit 1; \
	fi

# ---------------------------------------------------------------------------
# Library gates
# ---------------------------------------------------------------------------

.PHONY: build
build: check-lib-wiring
	@mkdir -p build
	$(CYRIUS) build programs/smoke.cyr build/chitra_smoke
	@echo "smoke: $$(wc -c < build/chitra_smoke) bytes"

.PHONY: test
# Functionality-grouped CPU suites under tests/tcyr/. Globbed so new
# domain files are picked up automatically; each is a standalone suite
# with its own main().
test: check-lib-wiring
	@for f in tests/tcyr/*.tcyr; do $(CYRIUS) test "$$f" || exit 1; done

.PHONY: lint
# A `warn` line fails, and so does lint's OWN non-zero exit (gate-9, 1.1.1):
# `cyrius lint` exits 1 on a file it cannot compile WITHOUT running a single
# check, and this loop used to read only the `warn` lines — so a file that did
# not even parse was reported lint-clean. Same loop as ci.yml's Lint step.
# `--strict-deferrals` (gate-14, 1.1.1): an untracked deferral note ("not yet",
# "deferred", "later") now fails lint's own exit. Turned on only once every
# linted file had zero of them — the 13 that 6.7.9 reported were reworded, not
# silenced. Proven: a probe file reading "not yet implemented" exits 2.
lint: check-surface
	@fail=0; \
	for f in src/*.cyr programs/*.cyr tests/tcyr/*.tcyr tests/bcyr/*.bcyr fuzz/*.fcyr; do \
		[ -e "$$f" ] || continue; \
		out=$$($(CYRIUS) lint --strict-deferrals "$$f" 2>&1); rc=$$?; echo "$$out"; \
		if [ $$rc -ne 0 ]; then echo "lint: $$f exited $$rc — it was NOT linted"; fail=1; fi; \
		if echo "$$out" | grep -qE '^[[:space:]]*warn '; then echo "lint: warnings in $$f"; fail=1; fi; \
	done; \
	[ $$fail -eq 0 ] || { echo "lint: warnings or lint failures present"; exit 1; }

.PHONY: fmt-check
fmt-check:
	@# cyrius 6.x's `cyrfmt --check <file>` reports formatting via the EXIT
	@# CODE only (0 = clean, non-zero = needs fmt). The file goes BEFORE the
	@# --check flag.
	@fail=0; \
	for f in src/*.cyr programs/*.cyr tests/tcyr/*.tcyr tests/bcyr/*.bcyr fuzz/*.fcyr; do \
		if ! $(CYRIUS) fmt $$f --check > /dev/null 2>&1; then \
			echo "needs fmt: $$f"; fail=1; \
		fi; \
	done; \
	[ $$fail -eq 0 ] || { echo "fmt: drift detected"; exit 1; }

.PHONY: check-surface
# The public surface is a list, and this checks dist/chitra.cyr against it.
# Wired into `lint` so a new chitra_* export cannot appear unclassified — at
# v1.0 that would be a compatibility promise made by accident.
check-surface:
	@./scripts/check-surface.sh

.PHONY: vet
vet:
	$(CYRIUS) vet programs/smoke.cyr

.PHONY: dist
dist:
	$(CYRIUS) distlib

.PHONY: fuzz
# Adversarial-input harnesses under fuzz/. Each drives a public decode entry
# with random / signature-prefixed / bit-flipped / truncated / entropy-mutated
# input and asserts BOTH the survival invariant and the documented
# (0 + *err_out set) contract.
#
# This IS the CI fuzz step — ci.yml runs `make fuzz` — so there is one
# definition (gate-16, 1.1.1: bare `cyrius fuzz` also walks tests/, CI's own
# loop did not, and the two gates ran different harness sets). A harness
# outside fuzz/ is refused rather than silently skipped by both.
#
# `--poison` (gate-2, 1.1.1) arms allocator redzones and exits 86 on an
# overwrite. A plain run sees only crashes, and a small overflow into the next
# bump allocation does not crash: dropping GIF's frame-rect guard passed every
# plain harness and fails this one.
fuzz: check-lib-wiring
	@stray=$$(find . -name '*.fcyr' -not -path './fuzz/*' -not -path './lib/*' | sort); \
	if [ -n "$$stray" ]; then \
		echo "fuzz: harnesses outside fuzz/ would be skipped by this gate:"; \
		echo "$$stray"; exit 1; \
	fi
	@for f in fuzz/*.fcyr; do $(CYRIUS) fuzz --poison "$$f" || exit 1; done

.PHONY: bench
# Decode benchmarks (tests/bcyr/chitra.bcyr). The harness GENERATES its
# fixtures at realistic sizes — the in-tree test fixtures are 2x2..16x16 and
# would measure fixed overhead, not throughput — and decode-verifies each one
# before timing it. NOT part of `test-all`: benchmark numbers are host- and
# load-dependent, so gating CI on them would be a flake source.
bench: check-lib-wiring
	$(CYRIUS) bench tests/bcyr/chitra.bcyr

.PHONY: bench-build
# Compile the bench harness WITHOUT running it (gate-9, 1.1.1). Nothing else
# compiles tests/bcyr/chitra.bcyr, and lint passes a file it cannot compile,
# so this is the gate that keeps `make bench` / `make bench-record` working.
# CI runs it; timing numbers stay out of CI.
bench-build: check-lib-wiring
	@mkdir -p build
	$(CYRIUS) build tests/bcyr/chitra.bcyr build/chitra_bench

.PHONY: bench-record
# Run the benchmarks and append the results to bench-history.csv.
bench-record: check-lib-wiring
	@./scripts/bench-csv.sh

.PHONY: version-check
version-check:
	@./scripts/version-check.sh

.PHONY: count-assertions
count-assertions:
	@./scripts/count-test-assertions.sh

.PHONY: consumer-shape
# Every suite again, linked the way kii / mabda / aethersafha link chitra: the
# stdlib "sankoch" leaf (the FULL bundle from chitra's own pinned toolchain) in
# place of chitra's [deps.sankoch] zlib profile. Built in a temp copy; the tree is
# never touched. Fails if the pinned toolchain's stdlib sankoch is below the 2.8.6
# floor the consumer docs promise (png.tcyr's png-3 cells), 1.1.4.
consumer-shape: check-lib-wiring
	@./scripts/consumer-shape.sh

.PHONY: test-all
test-all: version-check dist test consumer-shape fuzz bench-build

.PHONY: clean
clean:
	rm -rf build/
