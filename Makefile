# Makefile for chitra
#
# Most commands delegate to the `cyrius` CLI, which reads cyrius.cyml.
# chitra is a pure-Cyrius CPU library — no GPU, no C shim, no external
# binaries — so every target is host-runnable.
#
# Quick reference:
#   make test           — CPU-only tests (globs tests/tcyr/*.tcyr domain suites)
#   make build          — link-check the library (programs/smoke.cyr)
#   make dist           — regenerate dist/chitra.cyr via `cyrius distlib`
#   make lint / fmt-check / vet  — quality gates
#   make version-check  — VERSION / cyrius.cyml / CHANGELOG / README agree
#   make test-all       — version-check + dist regen + CPU tests
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
lint:
	@fail=0; \
	for f in src/*.cyr programs/*.cyr tests/tcyr/*.tcyr; do \
		out=$$($(CYRIUS) lint $$f 2>&1); echo "$$out"; \
		echo "$$out" | grep -qE '^\s*warn ' && fail=1; \
	done; \
	[ $$fail -eq 0 ] || { echo "lint: warnings present"; exit 1; }

.PHONY: fmt-check
fmt-check:
	@# cyrius 6.x's `cyrfmt --check <file>` reports formatting via the EXIT
	@# CODE only (0 = clean, non-zero = needs fmt). The file goes BEFORE the
	@# --check flag.
	@fail=0; \
	for f in src/*.cyr programs/*.cyr tests/tcyr/*.tcyr; do \
		if ! $(CYRIUS) fmt $$f --check > /dev/null 2>&1; then \
			echo "needs fmt: $$f"; fail=1; \
		fi; \
	done; \
	[ $$fail -eq 0 ] || { echo "fmt: drift detected"; exit 1; }

.PHONY: vet
vet:
	$(CYRIUS) vet programs/smoke.cyr

.PHONY: dist
dist:
	$(CYRIUS) distlib

.PHONY: version-check
version-check:
	@./scripts/version-check.sh

.PHONY: count-assertions
count-assertions:
	@./scripts/count-test-assertions.sh

.PHONY: test-all
test-all: version-check dist test

.PHONY: clean
clean:
	rm -rf build/
