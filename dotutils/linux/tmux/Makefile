SHELL := /bin/bash
MK_DIR := $(patsubst %/,%,$(dir $(abspath $(lastword $(MAKEFILE_LIST)))))
PLUGINS := \
	gpakosz/.tmux
include $(MK_DIR)/../../../mk/common.mk

install: download_plugins
	-mv ~/.tmux.conf.local ~/.tmux.conf.local.backup.$$(date +%s)
	-mv ~/.tmux.conf ~/.tmux.conf.backup.$$(date +%s)
	-mv ~/.tmux ~/.tmux.backup.$$(date +%s)
	ln -s $(MK_DIR)/config/.tmux.conf.local ~/.tmux.conf.local
	ln -s $(MK_DIR)/plugins/.tmux/.tmux.conf ~/.tmux.conf
	ln -s $(MK_DIR)/plugins/.tmux ~/.tmux

uninstall: prune uninstall_plugins
	-rm -f ~/.tmux.conf.local
	-rm -f ~/.tmux.conf
	-rm -f ~/.tmux

upgrade: upgrade_plugins

prune:
	-rm -f ~/.tmux.conf.local.backup.*
	-rm -f ~/.tmux.conf.backup.*
	-rm -f ~/.tmux.backup.*
