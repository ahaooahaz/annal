.DEFAULT_GOAL := install

ROOT_DIR := $(realpath $(dir $(lastword $(MAKEFILE_LIST))))
include $(ROOT_DIR)/mk/platform.mk

# Only directories with a Makefile are modules (including Darwin symlinks).
TARGETS ?= $(notdir $(patsubst %/Makefile,%,$(wildcard $(ROOT_DIR)/dotutils/$(PLATFORM)/*/Makefile)))

.PHONY: install uninstall prune upgrade test format
.NOTPARALLEL:

install uninstall prune:
	@set -e; for target in $(TARGETS); do \
		if [ ! -f "$(ROOT_DIR)/dotutils/$(PLATFORM)/$$target/Makefile" ]; then \
			printf 'Unknown module: %s/%s\n' "$(PLATFORM)" "$$target" >&2; exit 1; \
		fi; \
	done; \
	if [ -z "$(strip $(TARGETS))" ]; then \
		printf 'No modules with a Makefile for platform %s\n' "$(PLATFORM)"; \
	fi; \
	for target in $(TARGETS); do \
		printf '\n%s: %s/%s\n' "$@" "$(PLATFORM)" "$$target"; \
		$(MAKE) --no-print-directory -C "$(ROOT_DIR)/dotutils/$(PLATFORM)/$$target" PLATFORM="$(PLATFORM)" $@; \
	done

# One scan covers Annal, every platform, and undeclared/nested plugin repos.
# Do not dispatch this to modules: Darwin aliases would update repos twice.
upgrade:
	@/bin/bash "$(ROOT_DIR)/mk/dotutils.sh" upgrade "$(ROOT_DIR)"

test:
	@/bin/bash "$(ROOT_DIR)/tests/makefile_test.sh"

format:
	@cd "$(ROOT_DIR)" && git ls-files -z -- '*.sh' '*.bash' '*.zsh' | xargs -0 shfmt -w
