PLUGINS := gpakosz/.tmux
CONFIG_LINKS = \
	"$(MODULE_DIR)/config/.tmux.conf.local" "$(HOME)/.tmux.conf.local" \
	"$(MODULE_DIR)/plugins/.tmux/.tmux.conf" "$(HOME)/.tmux.conf" \
	"$(MODULE_DIR)/plugins/.tmux" "$(HOME)/.tmux"
include $(dir $(realpath $(lastword $(MAKEFILE_LIST))))../../../mk/common.mk
