SHELL := /bin/bash
MK_DIR := $(patsubst %/,%,$(dir $(abspath $(lastword $(MAKEFILE_LIST)))))

install:
	-mv ~/.profile ~/.profile.backup.$$(date +%s)
	-mv ~/.bashrc ~/.bashrc.backup.$$(date +%s)
	-mv ~/.zshrc ~/.zshrc.backup.$$(date +%s)
	-mv ~/.zprofile ~/.zprofile.backup.$$(date +%s)
	-mv ~/.zlogout ~/.zlogout.backup.$$(date +%s)
	-mv ~/.bash_logout ~/.bash_logout.backup.$$(date +%s)
	ln -s $(MK_DIR)/config/.profile ~/.profile
	ln -s $(MK_DIR)/config/.profile ~/.zprofile
	ln -s $(MK_DIR)/config/.shell ~/.bashrc
	ln -s $(MK_DIR)/config/.shell ~/.zshrc
	ln -s $(MK_DIR)/config/.logout ~/.zlogout
	ln -s $(MK_DIR)/config/.logout ~/.bash_logout


uninstall: prune
	-rm -f ~/.profile
	-rm -f ~/.zprofile
	-rm -f ~/.bashrc
	-rm -f ~/.zshrc
	-rm -f ~/.zlogout
	-rm -f ~/.bash_logout
upgrade:
	echo "No upgrade steps for shell plugin."

prune:
	-rm -f ~/.profile.backup.*
	-rm -f ~/.zprofile.backup.*
	-rm -f ~/.bashrc.backup.*
	-rm -f ~/.zshrc.backup.*
	-rm -f ~/.zlogout.backup.*
	-rm -f ~/.bash_logout.backup.*
