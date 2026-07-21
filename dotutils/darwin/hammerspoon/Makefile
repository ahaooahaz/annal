SHELL := /bin/bash
MK_DIR := $(patsubst %/,%,$(dir $(abspath $(lastword $(MAKEFILE_LIST)))))

install:
	-mv ~/.hammerspoon ~/.hammerspoon.backup.$$(date +%s)
	ln -s $(MK_DIR)/config ~/.hammerspoon

uninstall: prune
	-rm -f ~/.hammerspoon

upgrade:
	echo "No upgrade steps for karabiner plugin."

prune:
	-rm -f ~/.hammerspoon.backup.*
