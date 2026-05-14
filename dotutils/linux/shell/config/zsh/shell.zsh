#!/usr/bin/env zsh
#=====================#
#     Zsh config      #
#=====================#
setopt nullglob
# P10k Instant Prompt
include -f "${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-${(%):-%n}.zsh"

# Plugins
if [[ ! -f ${ZDOTDIR:-${HOME}}/.zcomet/bin/zcomet.zsh ]]; then
    command git clone https://github.com/agkozak/zcomet.git ${ZDOTDIR:-${HOME}}/.zcomet/bin
fi
include -f "${HOME}/.zcomet/bin/zcomet.zsh"
zcomet load jeffreytse/zsh-vi-mode
ZVM_SYSTEM_CLIPBOARD_ENABLED=true

# NOTE: custom bindkeys.
bindkey -M vicmd -r '^D'          # unbind <Ctrl-D> in vicmd mode.
bindkey -M viins -r '^D'          # unbind <Ctrl-D> in viins mode.
bindkey -M viins '^D' delete-char # bind <Ctrl-D> in viins mode, delete-char.
bindkey -M viins '^Z' undo        # [Ctrl-Z]

zcomet load zdharma-continuum/fast-syntax-highlighting

zcomet load ohmyzsh lib {completion,clipboard,git}.zsh
#zcomet load ohmyzsh plugins/autojump
#zcomet load ohmyzsh plugins/z
zcomet load ohmyzsh plugins/history
zcomet load ohmyzsh plugins/history-substring-search
bindkey '^[[A' history-substring-search-up
bindkey '^[[B' history-substring-search-down
HISTORY_SUBSTRING_SEARCH_ENSURE_UNIQUE=1
zcomet load ohmyzsh plugins/zoxide # NOTE: need install zoxide first.
__zoxide_z_complete() {
    args=$(zoxide query -l)
    _arguments "1:profiles:($args)"
}

zcomet load ohmyzsh plugins/git
zcomet load tj/git-extras etc git-extras-completion.zsh
export AUTOPAIR_INIT_INHIBIT=1
zcomet load hlissner/zsh-autopair

zcomet load romkatv/powerlevel10k
zcomet load trapd00r/LS_COLORS
# see issue: https://github.com/jeffreytse/zsh-vi-mode/issues/4
function after_init() {
    autopair-init
    # unbind <C_s> for kitty leader key.
    bindkey -M vicmd -r '^S'
    bindkey -M viins -r '^S'
    if test fzf; then
        source <(fzf --zsh)
    fi
}
zvm_after_init_commands+=(after_init)

zcomet compinit

# NOTE: zstyle must behind compinit.
zcomet load Aloxaf/fzf-tab
zstyle ':fzf-tab:*' fzf-opts '--height 40% --layout=reverse --inline-info --ignore-case --extended'
zstyle ':fzf-tab:*' fzf-bindings-default 'tab:down,btab:up,change:top,ctrl-space:toggle,bspace:backward-delete-char,ctrl-h:backward-delete-char'
if [[ "${CURROS}" == "Linux" ]]; then
    zstyle ':fzf-tab:complete:kill:argument-rest' fzf-preview 'ps --pid=$word -o cmd --no-headers -w'
else
    zstyle ':fzf-tab:complete:kill:argument-rest' fzf-preview 'ps -p $word -o command= -ww'
fi
zstyle ':fzf-tab:complete:kill:argument-rest' fzf-flags '--preview-window=down:3:wrap'
zstyle ':fzf-tab:complete:kill:*' popup-pad 0 3
zstyle ':fzf-tab:complete:ls:*' fzf-preview '
if [ -d $realpath ]; then
    tree -N -C $realpath | head -500
elif file --mime $realpath | grep -q image; then
    mcat $realpath --ascii
else
    bat --style=numbers --color=always $realpath 2>/dev/null \
    || highlight -O ansi -l $realpath 2>/dev/null \
    || cat $realpath | head -500
fi
'
zstyle ':completion:*:__zoxide_z:*' sort false

# Configs
# zsh misc
setopt auto_cd           # simply type dir name to `cd`
setopt auto_pushd        # make `cd` behave like pushd
setopt pushd_ignore_dups # don't pushd duplicates
setopt pushd_minus       # exchange the meanings of `+` and `-` in pushd
setopt ksh_option_print  # make `setopt` output all options
setopt extended_glob     # extended globbing
setopt IGNORE_EOF

# time (zsh built-in)
TIMEFMT="\
    %J   %U  user %S system %P cpu %*E total
    avg shared (code):         %X KB
    avg unshared (data/stack): %D KB
    total (sum):               %K KB
    max memory:                %M MB
    page faults from disk:     %F
    other page faults:         %R"

# zsh history
export HISTFILE=~/.zsh_history
setopt hist_ignore_all_dups # no duplicates
setopt hist_save_no_dups    # don't save duplicates
setopt hist_ignore_space    # no commands starting with space
setopt hist_reduce_blanks   # remove all unneccesary spaces
setopt share_history        # share history between sessions
setopt EXTENDED_HISTORY

autoload -Uz colors && colors # provide color variables (see `which colors`)

# fix echo <fe0f> chars when rime input a emoji
# Ref: https://github.com/rime/rime-emoji/issues/8
setopt COMBINING_CHARS

include -f "${ZDOTDIR:-${HOME}}/.p10k.zsh"

#=====================#
#   Zsh config end    #
#=====================#
