MAKEFLAGS += -s
ROOT_DIR := $(CURDIR)
COMMANDS = install uninstall upgrade prune

mk = linux
ifeq ($(OS),Windows_NT)
	mk := windows
else
UNAME_S := $(shell uname -s)
ifeq ($(UNAME_S),Linux)
    mk := linux
else ifeq ($(UNAME_S),Darwin)
    mk := darwin
endif
endif

TARGETS = $(notdir $(patsubst %/,%,$(wildcard dotutils/$(mk)/*/)))

$(COMMANDS):
	echo "$@ plugins: $(TARGETS)"
	@set -e; for target in $(TARGETS); do \
		echo "$@ing $$target..."; \
		$(MAKE) -C dotutils/$(mk)/$$target $@; \
	done
