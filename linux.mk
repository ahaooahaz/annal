SHELL = /bin/bash
REPO = $(shell git remote -v | grep '^origin\s.*(fetch)$$' | awk '{print $$2}' | sed -E 's/^.*(\/\/|@)//;s/\.git$$//' | sed 's/:/\//g')
TIMESTAMP = $(shell date +%s)
OS=$(shell uname -s)
MKFILE_PATH = $(shell pwd)
ANNALRC = $${HOME}/.annalrc
VERBOSE ?= 1

all: env

env: clones links

clones:
	mkdir -p plugins
	jq -r '.plugins[] | select(.repo != null) | [.name, .repo] | @tsv' config.json | \
	while read name repo; do \
		git clone https://github.com/$$repo.git plugins/$$name; \
		echo "cloned: $$repo -> plugins/$$name"; \
	done

links:
	set +x;\
	jq -r '.plugins[].links[] | [.dst, .link] | @tsv' config.json | \
	while read dst link; do \
		dst=$$(eval echo "$$dst"); \
		link=$$(eval echo "$$link"); \
		mkdir -p "$$(dirname "$$link")"; \
		mv $$link $${link}.backup.$$(date +%s) || :; \
		ln -sf "$$(realpath "$$dst")" "$$link"; \
		echo "linked: $$link → $$dst"; \
	done

rime:
	-git clone git@github.com:iDvel/rime-ice.git plugins/rime
	find $$(pwd)/configs/rime -mindepth 1 -maxdepth 1 | while read -r line; do \
		ln -sf "$${line}" "plugins/rime/$$(basename "$${line}")"; \
	done

upgrade:
	find plugins -maxdepth 1 -mindepth 1 -type d -exec git -C {} pull \;

prune:
	set +x;\
	jq -r '.plugins[].links[] | [.dst, .link] | @tsv' config.json | \
	while read dst link; do \
		dst=$$(eval echo "$$dst"); \
		link=$$(eval echo "$$link"); \
		find $$(dirname $$link) -maxdepth 1 -mindepth 1 -name "$$(basename $$link).backup.*" | xargs -I {} bash -c 'echo "cleaned: {}"; rm -rf {}'; \
	done

.PHONY: env clean
$(VERBOSE).SILENT:
