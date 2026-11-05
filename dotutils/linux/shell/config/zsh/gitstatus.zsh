# Feed asynchronous gitstatusd results to Starship's custom Git status module.
# This file is loaded before shell.zsh; initialization happens after Starship init.
function starship_gitstatus_context() {
    REPLY="$PWD:${GIT_DIR-}:${GIT_WORK_TREE-}"
}

function starship_gitstatus_format() {
    emulate -L zsh
    REPLY=''
    [[ $VCS_STATUS_RESULT == ok-* ]] || return 0
    ((VCS_STATUS_HAS_CONFLICTED)) && REPLY+='='
    ((VCS_STATUS_STASHES)) && REPLY+='$'
    ((VCS_STATUS_NUM_STAGED_DELETED + VCS_STATUS_NUM_UNSTAGED_DELETED)) && REPLY+='✘'
    # gitstatusd reports renames as deletion + addition, not a separate rename flag.
    ((VCS_STATUS_NUM_UNSTAGED > VCS_STATUS_NUM_UNSTAGED_DELETED)) && REPLY+='!'
    ((VCS_STATUS_HAS_STAGED)) && REPLY+='+'
    ((VCS_STATUS_HAS_UNTRACKED)) && REPLY+='?'
    if ((VCS_STATUS_COMMITS_AHEAD && VCS_STATUS_COMMITS_BEHIND)); then
        REPLY+='⇕'
    elif ((VCS_STATUS_COMMITS_AHEAD)); then
        REPLY+='⇡'
    elif ((VCS_STATUS_COMMITS_BEHIND)); then
        REPLY+='⇣'
    fi
    return 0
}

function starship_gitstatus_result() {
    emulate -L zsh
    _starship_gitstatus_pending=0
    starship_gitstatus_context
    if [[ $REPLY != $_starship_gitstatus_request_context ]]; then
        # A directory change happened while the previous request was in flight.
        # Discard its result and query the new directory, never show stale status.
        starship_gitstatus_update
        return 0
    fi
    local previous=$STARSHIP_GITSTATUS
    starship_gitstatus_format
    export STARSHIP_GITSTATUS=$REPLY STARSHIP_GITSTATUS_READY=1
    # Redraw only when the visible status changed, and only in the input editor.
    if [[ $previous != $STARSHIP_GITSTATUS ]] && zle; then
        zle .reset-prompt
        zle -R
    fi
    return 0
}

function starship_gitstatus_update() {
    emulate -L zsh
    starship_gitstatus_context
    if [[ $STARSHIP_GITSTATUS_CONTEXT != $REPLY ]]; then
        export STARSHIP_GITSTATUS='' STARSHIP_GITSTATUS_CONTEXT=$REPLY
    fi
    # The binding stops its instance when a daemon dies, without calling our callback.
    if ! gitstatus_check ANNAL_STARSHIP; then
        _starship_gitstatus_pending=0
        export STARSHIP_GITSTATUS_READY=0
        return 0
    fi
    # The binding forbids concurrent requests to the same daemon instance.
    ((_starship_gitstatus_pending)) && return 0
    _starship_gitstatus_request_context=$REPLY
    _starship_gitstatus_pending=1
    if ! gitstatus_query -d "$PWD" -t 0 -c starship_gitstatus_result ANNAL_STARSHIP; then
        _starship_gitstatus_pending=0
        # Let the custom module fall back to Starship's native status query.
        export STARSHIP_GITSTATUS_READY=0
    fi
    return 0
}

function starship_gitstatus_init() {
    emulate -L zsh
    export STARSHIP_GITSTATUS_READY=0 STARSHIP_GITSTATUS='' STARSHIP_GITSTATUS_CONTEXT=''
    # zsh -ic without a terminal cannot initialize gitstatusd's monitor option.
    [[ -o interactive && -t 0 && -t 1 ]] || return 0
    zcomet load romkatv/gitstatus || return 0
    (($+functions[gitstatus_start])) || return 0
    # Keep complete staged/unstaged counts to distinguish deletions from edits.
    # No index-size cutoff; untracked files and conflicts remain enabled.
    # Upstream gitstatusd checks submodule HEAD changes, not internal dirty files.
    gitstatus_start -s -1 -u -1 ANNAL_STARSHIP || return 0
    typeset -gi _starship_gitstatus_pending=0
    export STARSHIP_GITSTATUS_READY=1
    autoload -Uz add-zsh-hook
    add-zsh-hook precmd starship_gitstatus_update
}
