#############
# Functions #
#############
# wrapper for source and eval.
function include() {
    case $1 in
    -f)
        [[ -f $2 ]] && source $2
        ;;
    -c)
        local output=$($=2) &>/dev/null && eval $output
        ;;
    *)
        echo 'Unknown argument!' >&2
        return 1
        ;;
    esac
}

# Proxy utils is depend on polipo and protocol sock5.
function proxy() {
    case $1 in
    on)
        export all_proxy="${custom_proxy}" no_proxy=127.0.0.1,localhost
        export http_proxy=$all_proxy https_proxy=$all_proxy
    ;;
    off)
        unset no_proxy
        unset http_proxy
        unset https_proxy
    ;;
    -h|--help)
        cat << EOF
Usage: ${0##*/} [-h|--help]
    -h|--help   show help
    on          proxy enable
    off         proxy disable
EOF
    ;;
    *)
        proxy on
        $@
        proxy off
    ;;
    esac
}

# Skip git large storage files in go modules.
function skiplfs() {
    case $1 in
    on)
        export GIT_LFS_SKIP_SMUDGE=1
    ;;
    off)
        unset GIT_LFS_SKIP_SMUDGE
    ;;
    *)
        cat << EOF
Usage: ${0##*/} [-h|--help]
    on  "git modules skip lfs files"
    off "git modules not skip lfs files"
EOF
    ;;
    esac
}

function isnum() {
    if [ $# -ne 1 ]; then
        return 1
    fi

    expr $1 "+" 10 &> /dev/null
    if [ $? -ne 0 ];then
        return 1
    fi

    return 0
}

function ssht () {
    ssh -t "$@" "tmux attach || tmux new"
}

function condasetup() {
    __conda_setup="$('$HOME/.miniconda3/bin/conda' 'shell.zsh' 'hook' 2> /dev/null)"
    if [ $? -eq 0 ]; then
        eval "$__conda_setup"
    else
        if [ -f "$HOME/.miniconda3/etc/profile.d/conda.sh" ]; then
            . "$HOME/.miniconda3/etc/profile.d/conda.sh"
        else
            add_to PATH "$HOME/.miniconda3/bin"
        fi
    fi
    unset __conda_setup
}

function add_to() {
    local envname="$1"
    shift
    local current_val
    eval "current_val=\${$envname}"

    for dir in "$@" ; do
        case ":$current_val:" in
            *":$dir:"*) ;;
            *) current_val="$dir:$current_val" ;;
        esac
    done

    eval "export $envname=\"$current_val\""
}

#if [[ -z "$ANNAL_ENVRC_LOADED" ]]; then
#  export ANNAL_ENVRC_LOADED=1
#else
#    return 0
#fi

#######
# ENV #
#######

export XDG_CONFIG_HOME=~/.config
export XDG_CACHE_HOME=~/.cache
export XDG_DATA_HOME=~/.local/share

# Lua env.
export LUA_LOCAL_PATH=$HOME/.luarocks
export LUA_PATH="$LUA_LOCAL_PATH/share/lua/5.1/?.lua;$LUA_LOCAL_PATH/share/lua/5.1/?/?.lua;;"

# input env.
export GIT_EDITOR=nvim
export EDITOR=nvim
export VISUAL=nvim
export INPUT_METHOD=ibus
export GLFW_IM_MODULE=ibus
export GTK_IM_MODULE=ibus
export XMODIFIERS=@im=ibus
export QT_IM_MODULE=ibus

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

if [[ "${CURROS:-$(uname)}" == "Darwin" ]]; then
    export PYENV_ROOT="$HOME/.pyenv"
    export PATH="/opt/homebrew/sbin:/opt/homebrew/bin:$PATH"
    [[ -d ${PYENV_ROOT}/bin ]] && export PATH="$PYENV_ROOT/bin:$PATH"
    include -f ${HOME}/.venv/bin/activate
fi

case $- in
    *i*) ;;
      *) return;;
esac
if [[ "${CURRSHELL}" == "bash" ]]; then
    source ${HOME}/.${CURRSHELL}rc
fi
