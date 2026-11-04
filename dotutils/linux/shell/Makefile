CONFIG_LINKS = \
	"$(MODULE_DIR)/config" "$(HOME)/.shell" \
	"$(MODULE_DIR)/config/rc.sh" "$(HOME)/.bashrc" \
	"$(MODULE_DIR)/config/rc.sh" "$(HOME)/.zshrc" \
	"$(MODULE_DIR)/config/logout.sh" "$(HOME)/.bash_logout" \
	"$(MODULE_DIR)/config/logout.sh" "$(HOME)/.zlogout"
# Previous installers also moved these login files, but never linked them.
EXTRA_BACKUPS = "$(HOME)/.profile" "$(HOME)/.zprofile"
include $(dir $(realpath $(lastword $(MAKEFILE_LIST))))../../../mk/common.mk
