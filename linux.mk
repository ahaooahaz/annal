REPO = $(shell git remote -v | grep '^origin\s.*(fetch)$$' | awk '{print $$2}' | sed -E 's/^.*(\/\/|@)//;s/\.git$$//' | sed 's/:/\//g')
OS_RELEASE = $(shell awk -F= '/^NAME/{print $$2}' /etc/os-release | tr A-Z a-z)
TIMESTAMP = $(shell date +%s)
MKFILE_PATH = $(shell pwd)
RCS_DIR = appc
ANNALRC = $${HOME}/.annalrc
INSTALL_PATH = $${HOME}/.local/bin
SHELL = /bin/bash
VERBOSE ?= 1

PACKAGE_PLUGINS = sshpass base64 at xsel bat

ifneq ($(findstring "ubuntu", $(OS_RELEASE)),)
	PKG_MANAGER := apt
endif

ifneq ($(findstring "centos", $(OS_RELEASE)),)
	PKG_MANAGER := yum
endif

ifneq ($(USER), "root")
	SUDO := sudo
endif

all: env

env:
	python3 install.py

upgrade:
	find plugins -maxdepth 1 -mindepth 1 -type d -exec git -C {} pull \;

$(PACKAGE_PLUGINS):
	if ! type $@ 2>/dev/null; then $(SUDO) $(PKG_MANAGER) install $@ -y; fi

.PHONY: env clean
$(VERBOSE).SILENT:
