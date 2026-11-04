PLUGINS := iDvel/rime-ice
CONFIG_LINKS = \
	$(foreach file,$(wildcard $(MODULE_DIR)/config/*.*),"$(file)" "$(MODULE_DIR)/plugins/rime-ice/$(notdir $(file))") \
	$(foreach file,$(wildcard $(MODULE_DIR)/config/mylua/*.lua),"$(file)" "$(MODULE_DIR)/plugins/rime-ice/lua/$(notdir $(file))")
include $(dir $(realpath $(lastword $(MAKEFILE_LIST))))../../../mk/common.mk

ifeq ($(PLATFORM),linux)
CONFIG_LINKS += \
	"$(MODULE_DIR)/plugins/rime-ice" "$(XDG_CONFIG_HOME)/ibus/rime" \
	"$(MODULE_DIR)/plugins/rime-ice" "$(XDG_DATA_HOME)/fcitx5/rime"
else ifeq ($(PLATFORM),darwin)
CONFIG_LINKS += "$(MODULE_DIR)/plugins/rime-ice" "$(HOME)/Library/Rime"
endif

# Clean up backups made by either input method/platform, including old installs.
EXTRA_BACKUPS = \
	"$(XDG_CONFIG_HOME)/ibus/rime" \
	"$(XDG_DATA_HOME)/fcitx5/rime" \
	"$(HOME)/Library/Rime"
