SHELL := /bin/bash
MK_DIR := $(patsubst %/,%,$(dir $(abspath $(lastword $(MAKEFILE_LIST)))))

install:
	mkdir -p ~/.ssh
	-mv ~/.ssh/config ~/.ssh/config.backup.$$(date +%s)
	ln -s $(MK_DIR)/config ~/.ssh/config

uninstall: prune
	-rm -f ~/.ssh/config

upgrade:
	echo "No upgrade steps for ssh plugin."

prune:
	-rm -f ~/.ssh/config.backup.*
