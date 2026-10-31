SHELL := /bin/bash
MK_DIR := $(patsubst %/,%,$(dir $(abspath $(lastword $(MAKEFILE_LIST)))))

install: uninstall
	ln -s $(MK_DIR)/config ~/.config/omasnap

uninstall:
	-mv ~/.config/omasnap ~/.config/omasnap.backup.$$(date +%s)

upgrade:
	echo "No upgrade steps for omasnap plugin."

prune:
	-rm -f ~/.config/omasnap.backup.*
