#!/usr/bin/env bash
# shellcheck shell=bash

CURROS=$(uname -s)
export CURROS
export XDG_CONFIG_HOME=~/.config
export XDG_CACHE_HOME=~/.cache
export XDG_DATA_HOME=~/.local/share
export HISTSIZE=10000 # number of commands that are loaded
export SAVEHIST=10000 # number of commands that are stored

# Lua env.
export LUA_LOCAL_PATH=$HOME/.luarocks
export LUA_PATH="$LUA_LOCAL_PATH/share/lua/5.1/?.lua;$LUA_LOCAL_PATH/share/lua/5.1/?/?.lua;;"

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

# language env.
# Golang env.
ZGOPATH="$HOME/dev/go"
if [[ -s "$HOME/.gvm/scripts/gvm" ]]; then
    if [[ ${_shell_gvm_loaded-0} != 1 ]]; then
        _shell_lazy_register gvmsetup gvm go gofmt && _shell_gvm_lazy_enabled=1
    fi
else
    export GOPATH=$ZGOPATH
    environment_add PATH 0 "$HOME/.local/go/bin" "$GOPATH/bin"
fi

# nvm env.
NVM_DIR="$([ -z "${XDG_CONFIG_HOME-}" ] && printf %s "${HOME}/.nvm" || printf %s "${XDG_CONFIG_HOME}/nvm")"
if [[ -s "$NVM_DIR/nvm.sh" && ${_shell_nvm_loaded-0} != 1 ]]; then
    _shell_lazy_register nvmsetup nvm node npm npx corepack yarn yarnpkg pnpm pnpx && _shell_nvm_lazy_enabled=1
fi

# runtime env.
environment_add PATH 0 "$HOME/.local/bin" "$HOME/.local/scripts" "$HOME/.cargo/bin" "$HOME/.local/cmake/bin"
if [[ "${CURROS}" == "Darwin" ]]; then
    environment_add PATH 10 "/opt/homebrew/bin"
    environment_add DYLD_FALLBACK_LIBRARY_PATH 0 "/opt/homebrew/lib"
fi

if [[ -d "$HOME/.local/share/bob" ]]; then
    environment_add PATH 0 "$HOME/.local/share/bob/nvim-bin"
fi
