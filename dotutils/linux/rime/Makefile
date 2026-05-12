SHELL := /bin/bash
MK_DIR := $(patsubst %/,%,$(dir $(abspath $(lastword $(MAKEFILE_LIST)))))
PLUGINS := \
	iDvel/rime-ice
include $(MK_DIR)/../common.mk
OS := $(shell uname -s)

ifeq ($(UNAME_S),Linux)
    mk := linux
else ifeq ($(UNAME_S),Darwin)
    mk := darwin
endif

install: download_plugins
	find $(MK_DIR)/config -mindepth 1 -maxdepth 1 -type f -exec ln -sf {} $(MK_DIR)/plugins/rime-ice/ \;
	if [[ "$(OS)" == "Linux" ]]; then \
		mv ~/.config/ibus/rime ~/.config/ibus/rime.backup.$(date +%Y%m%d%H%M%S) 2>/dev/null || true; \
		mv ~/.local/share/fcitx5/rime ~/.local/share/fcitx5/rime.backup.$(date +%Y%m%d%H%M%S) 2>/dev/null || true; \
		ln -sf $(MK_DIR)/plugins/rime-ice ~/.config/ibus/rime; \
		ln -sf $(MK_DIR)/plugins/rime-ice ~/.local/share/fcitx5/rime; \
	else \
		mv ~/Library/Rime ~/Library/Rime.backup.$(date +%Y%m%d%H%M%S) 2>/dev/null || true; \
		ln -sf $(MK_DIR)/plugins/rime-ice ~/Library/Rime; \
	fi

uninstall: prune

upgrade: upgrade_plugins

prune:
	rm -rf ~/.config/ibus/rime.backup.*
	rm -rf ~/.local/share/fcitx5/rime.backup.*
	rm -rf ~/Library/Rime.backup.*
