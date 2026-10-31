SHELL := /bin/bash
MK_DIR := $(patsubst %/,%,$(dir $(abspath $(lastword $(MAKEFILE_LIST)))))

install: uninstall
	ln -s $(MK_DIR)/config ~/.config/hypr

uninstall:
	-mv ~/.config/hypr ~/.config/hypr.backup.$$(date +%s)

upgrade:
	echo "No upgrade steps for i3 plugin."

prune:
	-rm -f ~/.config/i3.backup.*
