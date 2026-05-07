PLUGINS ?=

download_plugins:
	for plugin in $(PLUGINS); do \
		repo_name=$$(basename $$plugin); \
		if [ ! -d plugins/$$repo_name ]; then \
			echo "Downloading $$plugin ..."; \
			git clone --depth 1 https://github.com/$$plugin.git plugins/$$repo_name; \
			echo "Downloaded $$repo_name plugin."; \
		else \
			echo "$$repo_name already exists, skipping"; \
		fi \
	done

upgrade_plugins:
	for plugin in $(PLUGINS); do \
		repo_name=$$(basename $$plugin); \
		if [ -d plugins/$$repo_name ]; then \
			echo "Upgrading $$plugin ..."; \
			cd plugins/$$repo_name && git pull && cd -; \
			echo "Upgraded $$repo_name plugin."; \
		else \
			echo "$$repo_name does not exist, skipping"; \
			ls plugins/$$repo_name; \
		fi \
	done

uninstall_plugins:
	-rm -rf plugins
