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
    export LS_COLORS="$(vivid generate lava)"

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
# zcomet load trapd00r/LS_COLORS

# gitstatusd -> GSD_* -> Starship env_var.
# Load the binding before defining and starting the integration.
zcomet load romkatv/gitstatus
function _starship_gsd_clear() {
    emulate -L zsh -o no_aliases
    unset GSD_REMOTE GSD_REPO GSD_BRANCH GSD_STATUS GSD_AHEAD_BEHIND GSD_ACTION
}

function _starship_gsd_publish() {
    emulate -L zsh -o no_aliases
    _starship_gsd_clear
    [[ $VCS_STATUS_RESULT == ok-* ]] || return 0

    local branch=$VCS_STATUS_LOCAL_BRANCH
    [[ -n $branch ]] || branch="${VCS_STATUS_COMMIT[1,7]}"
    local repo=${VCS_STATUS_REMOTE_URL:t}
    repo=${repo%.git}
    [[ -n $repo ]] || repo=${VCS_STATUS_WORKDIR:t}
    export GSD_REPO=$repo GSD_BRANCH=$branch

    case $VCS_STATUS_REMOTE_URL in
    *github.com*) export GSD_REMOTE='' ;;
    *gitlab.com*) export GSD_REMOTE='' ;;
    *) export GSD_REMOTE='' ;;
    esac

    # ASCII status markers, each one terminal cell wide.
    local ahead=">"
    local behind="<"
    local diverged="x"
    local conflicted="!"
    local up_to_date="="
    local untracked="?"
    local modified="*"
    local staged="+"
    local renamed="R" # Reserved: gitstatusd reports renames as deletion/addition.
    local deleted="-"

    local flags=''
    ((VCS_STATUS_HAS_CONFLICTED)) && flags+=$conflicted
    ((VCS_STATUS_STASHES)) && flags+='$'
    ((VCS_STATUS_NUM_STAGED_DELETED + VCS_STATUS_NUM_UNSTAGED_DELETED)) && flags+=$deleted
    ((VCS_STATUS_NUM_UNSTAGED > VCS_STATUS_NUM_UNSTAGED_DELETED)) && flags+=$modified
    ((VCS_STATUS_HAS_STAGED)) && flags+=$staged
    ((VCS_STATUS_HAS_UNTRACKED)) && flags+=$untracked
    [[ -z $flags ]] || export GSD_STATUS=$flags

    local ahead_behind
    if ((VCS_STATUS_COMMITS_AHEAD && VCS_STATUS_COMMITS_BEHIND)); then
        ahead_behind="${diverged}${VCS_STATUS_COMMITS_AHEAD}/${VCS_STATUS_COMMITS_BEHIND}"
    elif ((VCS_STATUS_COMMITS_AHEAD)); then
        ahead_behind="${ahead}${VCS_STATUS_COMMITS_AHEAD}"
    elif ((VCS_STATUS_COMMITS_BEHIND)); then
        ahead_behind="${behind}${VCS_STATUS_COMMITS_BEHIND}"
    else
        ahead_behind=$up_to_date
    fi
    export GSD_AHEAD_BEHIND=$ahead_behind
    [[ -z $VCS_STATUS_ACTION ]] || export GSD_ACTION=$VCS_STATUS_ACTION
    return 0
}

function _starship_gsd_result() {
    emulate -L zsh -o no_aliases
    _starship_gsd_pending=0

    # Do not display a result for a directory or Git context we have left.
    local context="$PWD:${GIT_DIR-}:${GIT_WORK_TREE-}"
    if [[ $context != $_starship_gsd_request_context ]]; then
        _starship_gsd_update
        return 0
    fi

    local old_remote=${GSD_REMOTE-} old_repo=${GSD_REPO-} old_branch=${GSD_BRANCH-}
    local old_status=${GSD_STATUS-} old_ahead=${GSD_AHEAD_BEHIND-} old_action=${GSD_ACTION-}
    _starship_gsd_publish

    # Re-render only if visible Git information changed, and only inside ZLE.
    if [[ $old_remote != ${GSD_REMOTE-} || $old_repo != ${GSD_REPO-} ||
        $old_branch != ${GSD_BRANCH-} || $old_status != ${GSD_STATUS-} ||
        $old_ahead != ${GSD_AHEAD_BEHIND-} || $old_action != ${GSD_ACTION-} ]] && zle; then
        zle .reset-prompt
        zle -R
    fi
    return 0
}

function _starship_gsd_update() {
    emulate -L zsh -o no_aliases
    local context="$PWD:${GIT_DIR-}:${GIT_WORK_TREE-}"
    if [[ $context != $_starship_gsd_context ]]; then
        _starship_gsd_clear
        _starship_gsd_context=$context
    fi

    if ! 'gitstatus_check' "$_starship_gsd_instance"; then
        _starship_gsd_pending=0
        _starship_gsd_clear
        return 0
    fi
    # gitstatusd forbids concurrent requests on the same instance.
    ((_starship_gsd_pending)) && return 0

    _starship_gsd_request_context=$context
    _starship_gsd_pending=1
    if ! 'gitstatus_query' -d "$PWD" -t 0 -c _starship_gsd_result "$_starship_gsd_instance"; then
        _starship_gsd_pending=0
        _starship_gsd_clear
    elif [[ $VCS_STATUS_RESULT != tout ]]; then
        # Handle immediate non-repository replies as well as async callbacks.
        _starship_gsd_result
    fi
    return 0
}

typeset -g _starship_gsd_instance=STARSHIP_GSD
typeset -gi _starship_gsd_pending=${_starship_gsd_pending:-0}
typeset -g _starship_gsd_context=${_starship_gsd_context-}
typeset -g _starship_gsd_request_context=${_starship_gsd_request_context-}

'gitstatus_start' -s -1 -u -1 -c -1 -d -1 "$_starship_gsd_instance" || return 1

# Start the first Git query before initializing Starship at the first prompt.
add-zsh-hook precmd _starship_gsd_update
add-zsh-hook precmd after_init
# gitstatusd end
#

function accept_line_nonempty() {
    emulate -L zsh

    if [[ $CONTEXT == start && -z ${BUFFER//[[:space:]]/} ]]; then
        return 0
    fi

    zle .accept-line
}

zle -N accept-line-nonempty accept_line_nonempty
bindkey -M emacs '^M' accept-line-nonempty

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
