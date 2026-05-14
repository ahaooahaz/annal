SHELL := /bin/bash
MK_DIR := $(patsubst %/,%,$(dir $(abspath $(lastword $(MAKEFILE_LIST)))))
PLUGINS := \
	ahaooahaz/starter
include $(MK_DIR)/../../../mk/common.mk

install: download_plugins
	-mv ~/.config/nvim ~/.config/nvim.backup.$$(date +%s)
	ln -s $(MK_DIR)/plugins/starter ~/.config/nvim

uninstall: prune
	-rm -f ~/.config/nvim

upgrade: upgrade_plugins

prune:
	-rm -f ~/.config/nvim.backup.*
