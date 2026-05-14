SHELL := /bin/bash
MK_DIR := $(patsubst %/,%,$(dir $(abspath $(lastword $(MAKEFILE_LIST)))))
PLUGINS := \
	trygveaa/kitty-kitten-search \
	yurikhan/kitty_grab
include $(MK_DIR)/../../../mk/common.mk

install: download_plugins
	-mv ~/.config/kitty ~/.config/kitty.backup.$$(date +%s)
	ln -s $(MK_DIR)/config ~/.config/kitty

uninstall: prune
	-rm -f ~/.config/kitty

upgrade: upgrade_plugins

prune:
	-rm -f ~/.config/kitty.backup.*
