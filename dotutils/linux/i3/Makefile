SHELL := /bin/bash
MK_DIR := $(patsubst %/,%,$(dir $(abspath $(lastword $(MAKEFILE_LIST)))))

install:
	-mv ~/.config/i3 ~/.config/i3.backup.$$(date +%s)
	ln -s $(MK_DIR)/config ~/.config/i3

uninstall: prune
	-rm -f ~/.config/i3

upgrade:
	echo "No upgrade steps for i3 plugin."

prune:
	-rm -f ~/.config/i3.backup.*
