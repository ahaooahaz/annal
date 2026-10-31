SHELL := /bin/bash
MK_DIR := $(patsubst %/,%,$(dir $(abspath $(lastword $(MAKEFILE_LIST)))))

install: uninstall
	ln -s $(MK_DIR)/config ~/.config/caelestia

uninstall:
	-mv ~/.config/caelestia ~/.config/caelestia.backup.$$(date +%s)

upgrade:
	echo "No upgrade steps for caelestia plugin."

prune:
	-rm -f ~/.config/caelestia.backup.*
