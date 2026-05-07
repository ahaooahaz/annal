SHELL := /bin/bash
MK_DIR := $(patsubst %/,%,$(dir $(abspath $(lastword $(MAKEFILE_LIST)))))

install:
	-mv ~/.gitconfig ~/.gitconfig.backup.$$(date +%s)
	ln -s $(MK_DIR)/config/.gitconfig ~/.gitconfig
	-mkdir -p ~/.gitconfig.d
	-touch ~/.gitconfig.d/user.personal
	-touch ~/.gitconfig.d/user.work

uninstall: prune
	-rm -f ~/.gitconfig

upgrade:
	echo "No upgrade steps for git plugin."

prune:
	-rm -f ~/.gitconfig.backup.*
