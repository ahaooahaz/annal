#!/usr/bin/env bash
# shellcheck shell=bash

CURROS=$(uname -s)
export CURROS
export XDG_CONFIG_HOME=~/.config
export XDG_CACHE_HOME=~/.cache
export XDG_DATA_HOME=~/.local/share
export HISTSIZE=10000 # number of commands that are loaded
export SAVEHIST=10000 # number of commands that are stored

# input env.
export GIT_EDITOR=nvim
export EDITOR=nvim
export VISUAL=nvim

if [[ -n "$XDG_SESSION_TYPE" && "$XDG_SESSION_TYPE" != "tty" ]]; then
    if [[ "$XDG_CURRENT_DESKTOP" == "KDE" ]]; then
        export INPUT_METHOD=fcitx
        export GTK_IM_MODULE=fcitx
        export XMODIFIERS=@im=fcitx
        export QT_IM_MODULE=fcitx
        # ref: https://github.com/kovidgoyal/kitty/issues/469
        export GLFW_IM_MODULE=ibus
    else
        export INPUT_METHOD=ibus
        export GLFW_IM_MODULE=ibus
        export GTK_IM_MODULE=ibus
        export XMODIFIERS=@im=ibus
        export QT_IM_MODULE=ibus
    fi
fi

# private env.
include -f "${HOME}/.inti_envrc"

# runtime env.
environment_add PATH 0 "$HOME/.local/bin" "$HOME/.local/scripts" "$HOME/.cargo/bin" "$HOME/.local/cmake/bin"
if [[ "${CURROS}" == "Darwin" ]]; then
    environment_add PATH 10 "/opt/homebrew/bin"
    environment_add DYLD_FALLBACK_LIBRARY_PATH 0 "/opt/homebrew/lib"
    if [[ -d "/opt/homebrew/opt/binutils/bin" ]]; then
        environment_add PATH 0 "/opt/homebrew/opt/binutils/bin"
    fi
fi

if [[ -d "$HOME/.local/share/bob" ]]; then
    environment_add PATH 0 "$HOME/.local/share/bob/nvim-bin"
fi
