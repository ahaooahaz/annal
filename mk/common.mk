.DEFAULT_GOAL := install
SHELL := /bin/bash

# Resolve physical paths so Darwin's symlinked modules use the Linux sources.
MODULE_DIR := $(realpath $(dir $(firstword $(MAKEFILE_LIST))))
COMMON_DIR := $(realpath $(dir $(lastword $(MAKEFILE_LIST))))
DOTUTILS := $(COMMON_DIR)/dotutils.sh
include $(COMMON_DIR)/platform.mk

XDG_CONFIG_HOME ?= $(HOME)/.config
XDG_DATA_HOME ?= $(HOME)/.local/share

# CONFIG_LINKS is a shell-quoted list of source/destination pairs.
CONFIG_LINKS ?=
PLUGINS ?=
# Create these user-owned files on install; never overwrite or uninstall them.
EXTRA_FILES ?=
# Target paths whose legacy .backup.* files should also be pruned.
EXTRA_BACKUPS ?=

.PHONY: install uninstall prune upgrade download_plugins upgrade_plugins
.NOTPARALLEL:

install: download_plugins
	@$(SHELL) "$(DOTUTILS)" links install $(CONFIG_LINKS)
	@$(SHELL) "$(DOTUTILS)" init-files $(EXTRA_FILES)

uninstall:
	@$(SHELL) "$(DOTUTILS)" links uninstall $(CONFIG_LINKS)

prune:
	@$(SHELL) "$(DOTUTILS)" links prune $(CONFIG_LINKS)
	@$(SHELL) "$(DOTUTILS)" prune $(EXTRA_BACKUPS)

upgrade:
	@$(SHELL) "$(DOTUTILS)" upgrade "$(MODULE_DIR)"

download_plugins:
	@$(SHELL) "$(DOTUTILS)" clone "$(MODULE_DIR)/plugins" $(PLUGINS)

upgrade_plugins: upgrade
