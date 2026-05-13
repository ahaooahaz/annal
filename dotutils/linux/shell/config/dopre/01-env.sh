export CURROS=$(uname -s)
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
include -f ${HOME}/.inti_envrc

# runtime env.
add_to PATH $HOME/.local/bin $HOME/.local/scripts $GOPATH/bin $HOME/.cargo/bin $HOME/.local/cmake/bin
# language env.
# Golang env.
ZGOPATH="$HOME/dev/go"
if [[ -s "$HOME/.gvm/scripts/gvm" ]]; then
    source "$HOME/.gvm/scripts/gvm" && unset -f cd
    function gouse() {
        gvm use $1 --default
    }
else
    export GOPATH=$ZGOPATH
    add_to PATH $HOME/.local/go/bin
fi

# nvm env.
NVM_DIR="$([ -z "${XDG_CONFIG_HOME-}" ] && printf %s "${HOME}/.nvm" || printf %s "${XDG_CONFIG_HOME}/nvm")"
[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"

if [[ "${CURROS:-$(uname -s)}" == "Darwin" ]]; then
    add_to PATH "/opt/homebrew/sbin" "/opt/homebrew/bin"
fi

if [[ -d "$HOME/.local/share/bob" ]]; then
    add_to PATH "$HOME/.local/share/bob/nvim-bin"
fi
