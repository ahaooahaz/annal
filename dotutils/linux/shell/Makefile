SHELL := /bin/bash
MK_DIR := $(patsubst %/,%,$(dir $(abspath $(lastword $(MAKEFILE_LIST)))))

install:
	-mv ~/.profile ~/.profile.backup.$$(date +%s)
	-mv ~/.bashrc ~/.bashrc.backup.$$(date +%s)
	-mv ~/.zshrc ~/.zshrc.backup.$$(date +%s)
	-mv ~/.zprofile ~/.zprofile.backup.$$(date +%s)
	-mv ~/.zlogout ~/.zlogout.backup.$$(date +%s)
	-mv ~/.bash_logout ~/.bash_logout.backup.$$(date +%s)
	-mv ~/.shell ~/.shell.backup.$$(date +%s)
	ln -s $(MK_DIR)/config ~/.shell
	echo "source ~/.shell/setup.sh" > ~/.zshrc
	echo "source ~/.shell/setup.sh" > ~/.bashrc
	echo "source ~/.shell/logout.sh" > ~/.bash_logout
	echo "source ~/.shell/logout.sh" > ~/.zlogout


uninstall: prune
	-rm -rf ~/.shell

upgrade:
	echo "No upgrade steps for shell plugin."

prune:
	-rm -rf ~/.shell.backup.*
