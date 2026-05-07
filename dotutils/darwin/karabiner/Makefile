SHELL := /bin/bash
MK_DIR := $(patsubst %/,%,$(dir $(abspath $(lastword $(MAKEFILE_LIST)))))

install:
	-mv ~/.config/karabiner ~/.config/karabiner.backup.$$(date +%s)
	ln -s $(MK_DIR)/config ~/.config/karabiner

uninstall: prune
	-rm -f ~/.config/karabiner

upgrade:
	echo "No upgrade steps for karabiner plugin."

prune:
	-rm -f ~/.config/karabiner.backup.*
