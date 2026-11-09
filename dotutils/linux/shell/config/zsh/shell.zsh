#!/usr/bin/env zsh
export CURRSHELL=zsh
#=====================#
#     Zsh config      #
#=====================#

# Plugins
if [[ ! -f ${ZDOTDIR:-${HOME}}/.zcomet/bin/zcomet.zsh ]]; then
    command git clone https://github.com/agkozak/zcomet.git ${ZDOTDIR:-${HOME}}/.zcomet/bin
fi
include -f "${HOME}/.zcomet/bin/zcomet.zsh"

# Initialize once at the first prompt, after all configuration has been sourced.
function after_init() {
    add-zsh-hook -d precmd after_init
    eval "$(starship init zsh)"
    starship_gitstatus_init

    autopair-init
    # Keep terminal shortcuts on the default emacs keymap.
    # Ctrl-S is reserved for Kitty's leader key.
    bindkey -M emacs '^D' delete-char
    bindkey -M emacs '^Z' undo
    bindkey -M emacs -r '^S'
    bindkey -M emacs '^[[A' history-substring-search-up
    bindkey -M emacs '^[[B' history-substring-search-down
    if command -v fzf >/dev/null 2>&1; then
        source <(fzf --zsh)
    fi

    # z.lua owns the directory history; fz owns z/zz's interactive completion.
    export _ZL_ZSH_NO_FZF=1
    export _ZL_NO_ALIASES=1
    export _ZL_HYPHEN=1
    FZ_HISTORY_CD_CMD=_zlua
    FZ_CMD=z
    FZ_SUBDIR_CMD=zz
    FZ_SUBDIR_TRAVERSAL=1
    FZ_CASE_INSENSITIVE=1
    zcomet load skywind3000/z.lua
    # Capture the existing Tab widget after fzf initializes.
    # fz handles z/zz and delegates other commands to the previous widget.
    zcomet load changyuheng/fz
    compdef _zlua_zsh_tab_completion _zlua _fz _fzz z zz
    bindkey -M emacs '^I' __fz_zsh_completion
}

# Use Zsh's native emacs editing instead of loading zsh-vi-mode.
bindkey -e
autoload -Uz add-zsh-hook
add-zsh-hook precmd after_init

zcomet load ohmyzsh lib {completion,clipboard,git}.zsh
#zcomet load ohmyzsh plugins/autojump
#zcomet load ohmyzsh plugins/z
# history
HISTORY_SUBSTRING_SEARCH_ENSURE_UNIQUE=1
zcomet load ohmyzsh plugins/history
zcomet load ohmyzsh plugins/history-substring-search
zcomet load ohmyzsh plugins/git
zcomet load tj/git-extras etc git-extras-completion.zsh

# Initialize in after_init, once plugin loading and environment setup are complete.
AUTOPAIR_INHIBIT_INIT=1
zcomet load hlissner/zsh-autopair

# zcomet load romkatv/powerlevel10k
zcomet load trapd00r/LS_COLORS

# Register before syntax highlighting wraps the shared ZLE hook dispatcher.
# Registering afterwards can make add-zle-hook-widget wrap its own dispatcher.
function starship_transient_prompt() {
    emulate -L zsh
    [[ $CONTEXT == start ]] || return 0
    local PROMPT='$(starship prompt --profile transient --status="${STARSHIP_CMD_STATUS:-0}" --keymap="${KEYMAP:-emacs}")'
    local RPROMPT=''
    zle .reset-prompt
    # Flush the redraw before the local prompts are restored on return.
    zle -R
}
autoload -Uz add-zle-hook-widget
add-zle-hook-widget line-finish starship_transient_prompt

zcomet load zdharma-continuum/fast-syntax-highlighting

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
if [ -d "$realpath" ]; then
    tree -N -C -- "$realpath" | head -500
elif file --mime -- "$realpath" | grep -q image; then
    mcat -- "$realpath" --ascii
else
    bat --style=numbers --color=always -- "$realpath" 2>/dev/null \
    || highlight -O ansi -l -- "$realpath" 2>/dev/null \
    || cat -- "$realpath" | head -500
fi
'

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

setopt nullglob
export GPG_TTY="${TTY:-$(tty)}"

if ! command -v mise >/dev/null 2>&1; then
    curl -fsSL https://mise.run | sh
fi
eval "$(mise activate zsh)"

#=====================#
#   Zsh config end    #
#=====================#
