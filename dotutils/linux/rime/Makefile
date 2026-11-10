PLUGINS := iDvel/rime-ice
CONFIG_LINKS = \
	$(foreach file,$(wildcard $(MODULE_DIR)/config/*.*),"$(file)" "$(MODULE_DIR)/plugins/rime-ice/$(notdir $(file))") \
	$(foreach file,$(wildcard $(MODULE_DIR)/config/mylua/*.lua),"$(file)" "$(MODULE_DIR)/plugins/rime-ice/lua/$(notdir $(file))")
include $(dir $(realpath $(lastword $(MAKEFILE_LIST))))../../../mk/common.mk

ifeq ($(PLATFORM),linux)
CONFIG_LINKS += \
	"$(MODULE_DIR)/plugins/rime-ice" "$(XDG_CONFIG_HOME)/ibus/rime" \
	"$(MODULE_DIR)/plugins/rime-ice" "$(XDG_DATA_HOME)/fcitx5/rime" \
	$(foreach theme,$(wildcard $(MODULE_DIR)/config/fcitx5/themes/*),"$(theme)" "$(XDG_DATA_HOME)/fcitx5/themes/$(notdir $(theme))") \
	$(foreach file,$(wildcard $(MODULE_DIR)/config/fcitx5/conf/*.conf),"$(file)" "$(XDG_CONFIG_HOME)/fcitx5/conf/$(notdir $(file))")
else ifeq ($(PLATFORM),darwin)
CONFIG_LINKS += "$(MODULE_DIR)/plugins/rime-ice" "$(HOME)/Library/Rime"
endif

# Clean up backups made by either input method/platform, including old installs.
EXTRA_BACKUPS = \
	"$(XDG_CONFIG_HOME)/ibus/rime" \
	"$(XDG_DATA_HOME)/fcitx5/rime" \
	"$(HOME)/Library/Rime"

.PHONY: test
test:
	@$(SHELL) "$(MODULE_DIR)/tests/install_test.sh"
