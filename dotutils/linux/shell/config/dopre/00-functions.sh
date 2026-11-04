#!/usr/bin/env bash
# shellcheck shell=bash

function include() {
    case $1 in
    -f)
        # shellcheck source=/dev/null
        [[ -f "$2" ]] && source "$2"
        ;;
    -c)
        local output
        output=$(eval "$2" 2>/dev/null) && eval "$output"
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
        export all_proxy="${custom_proxy:-}" no_proxy=127.0.0.1,localhost
        export http_proxy=$all_proxy https_proxy=$all_proxy
        ;;
    off)
        unset all_proxy no_proxy http_proxy https_proxy
        ;;
    -h | --help)
        cat <<EOF
Usage: ${0##*/} [-h|--help]
    -h|--help   show help
    on          proxy enable
    off         proxy disable
EOF
        ;;
    *)
        proxy on
        "$@"
        local status=$?
        proxy off
        return "$status"
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
        cat <<EOF
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

    if ! [[ $1 =~ ^-?[0-9]+$ ]]; then
        return 1
    fi

    return 0
}

function ssht() {
    ssh -t "$@" "tmux attach || tmux new"
}

function condasetup() {
    if __conda_setup="$("$HOME/.miniconda3/bin/conda" "shell.${CURRSHELL}" hook 2>/dev/null)"; then
        eval "$__conda_setup"
    else
        if [ -f "$HOME/.miniconda3/etc/profile.d/conda.sh" ]; then
            # shellcheck source=/dev/null
            . "$HOME/.miniconda3/etc/profile.d/conda.sh"
        else
            environment_add PATH 0 "$HOME/.miniconda3/bin"
        fi
    fi
    unset __conda_setup
}

# Prepare lazy runtimes even when the caller bypasses their wrapper functions.
# Options such as -v/-V (lookup) and -p (default PATH) pass through unchanged.
# Keep Bash's native command: Bash 3.2's `builtin command` can mishandle errexit.
if [[ -n ${ZSH_VERSION-} ]]; then
    function command() {
        local _shell_command_name="${1-}"
        [[ $_shell_command_name != -- ]] || _shell_command_name="${2-}"
        case $_shell_command_name in
        node | npm | npx | corepack | yarn | yarnpkg | pnpm | pnpx)
            if [[ ${_shell_nvm_lazy_enabled-0} == 1 &&
                ${_shell_nvm_loaded-0} != 1 && ${_shell_nvm_loading-0} != 1 ]]; then
                nvmsetup || return
            fi
            ;;
        go | gofmt)
            if [[ ${_shell_gvm_lazy_enabled-0} == 1 &&
                ${_shell_gvm_loaded-0} != 1 && ${_shell_gvm_loading-0} != 1 ]]; then
                gvmsetup || return
            fi
            ;;
        esac
        builtin command "$@"
    }
fi

# Install one-shot wrappers. Only validated names enter eval; command arguments
# are forwarded unchanged after the loader succeeds in the current shell.
function _shell_lazy_register() {
    local _shell_lazy_loader="${1-}" _shell_lazy_command
    if [[ $# -lt 2 || ! $_shell_lazy_loader =~ ^[a-zA-Z_][a-zA-Z0-9_]*$ ]]; then
        printf 'Usage: _shell_lazy_register LOADER COMMAND...\n' >&2
        return 2
    fi
    shift
    for _shell_lazy_command in "$@"; do
        if [[ ! $_shell_lazy_command =~ ^[a-zA-Z_][a-zA-Z0-9_]*$ ]]; then
            printf 'Invalid lazy-load command: %s\n' "$_shell_lazy_command" >&2
            return 2
        fi
    done
    for _shell_lazy_command in "$@"; do
        eval "function $_shell_lazy_command() { \"$_shell_lazy_loader\" && \"$_shell_lazy_command\" \"\$@\"; }"
    done
}

# These can also be called explicitly before launching external scripts, whose
# node/go invocations cannot trigger functions in the parent shell.
function nvmsetup() {
    [[ ${_shell_nvm_loaded-0} == 1 ]] && return 0
    local _shell_nvm_script="${NVM_DIR:-$HOME/.nvm}/nvm.sh" _shell_nvm_result=0
    # Dynamic local scope lets command() recognize calls made during loading.
    local _shell_nvm_loading=1
    if [[ ! -s $_shell_nvm_script ]]; then
        printf 'NVM initialization script not found: %s\n' "$_shell_nvm_script" >&2
        return 1
    fi

    # Remove the whole group first: NVM itself may invoke node/npm while loading.
    unset -f nvm node npm npx corepack yarn yarnpkg pnpm pnpx 2>/dev/null || :
    set --
    # shellcheck source=/dev/null
    source "$_shell_nvm_script" || _shell_nvm_result=$?
    if [[ $_shell_nvm_result != 0 ]]; then
        _shell_lazy_register nvmsetup nvm node npm npx corepack yarn yarnpkg pnpm pnpx
        return "$_shell_nvm_result"
    fi
    _shell_nvm_loaded=1
}

function gvmsetup() {
    [[ ${_shell_gvm_loaded-0} == 1 ]] && return 0
    local _shell_gvm_script="$HOME/.gvm/scripts/gvm" _shell_gvm_result=0
    local _shell_gvm_cd _shell_gvm_loading=1
    if [[ ! -s $_shell_gvm_script ]]; then
        printf 'GVM initialization script not found: %s\n' "$_shell_gvm_script" >&2
        return 1
    fi

    # GVM installs a cd wrapper during initialization. Keep the previous behavior
    # of disabling it, but do not erase a cd function installed since startup.
    _shell_gvm_cd=$(declare -f cd) || _shell_gvm_cd=''
    unset -f gvm go gofmt 2>/dev/null || :
    set --
    # shellcheck source=/dev/null
    source "$_shell_gvm_script" || _shell_gvm_result=$?
    if [[ -n $_shell_gvm_cd ]]; then
        eval "$_shell_gvm_cd"
    else
        unset -f cd 2>/dev/null || :
    fi
    if [[ $_shell_gvm_result != 0 ]]; then
        _shell_lazy_register gvmsetup gvm go gofmt
        return "$_shell_gvm_result"
    fi
    _shell_gvm_loaded=1
}

# Register completion callbacks without running the CLI generators at startup.
# The generated Cobra callbacks have different names in Bash and Zsh.
function _shell_completion_register() {
    local _shell_completion_command="${1-}" _shell_completion_loaded
    case $_shell_completion_command in
    kubectl | helm) ;;
    *)
        printf 'Usage: _shell_completion_register kubectl|helm\n' >&2
        return 2
        ;;
    esac
    eval "_shell_completion_loaded=\${_shell_completion_${_shell_completion_command}_loaded-0}"
    [[ $_shell_completion_loaded != 1 ]] || return 0
    command -v "$_shell_completion_command" >/dev/null 2>&1 || return 0

    local _shell_completion_entry="_shell_lazy_complete_$_shell_completion_command"
    local _shell_completion_function
    if [[ -n ${ZSH_VERSION-} ]]; then
        # compinit may be skipped, e.g. with TERM=dumb. Do not initialize it here.
        declare -f compdef >/dev/null || return 0
        _shell_completion_function="_$_shell_completion_command"
    elif [[ -n ${BASH_VERSION-} ]]; then
        _shell_completion_function="__start_$_shell_completion_command"
    else
        return 0
    fi

    # Keep the entry callable even after registration changes: a completer may
    # have saved this function name while trying different matchers on one Tab.
    eval "function $_shell_completion_entry() { _shell_completion_load \"$_shell_completion_command\" && \"$_shell_completion_function\" \"\$@\"; }"
    if [[ -n ${ZSH_VERSION-} ]]; then
        compdef "$_shell_completion_entry" "$_shell_completion_command"
    elif [[ $(type -t compopt) == builtin ]]; then
        complete -o default -F "$_shell_completion_entry" "$_shell_completion_command"
    else
        # Match Cobra's options so the first completion is correct in Bash 3.2.
        complete -o default -o nospace -F "$_shell_completion_entry" "$_shell_completion_command"
    fi
}

function _shell_completion_load() {
    local _shell_completion_command="${1-}" _shell_completion_loaded
    case $_shell_completion_command in
    kubectl | helm) ;;
    *)
        printf 'Usage: _shell_completion_load kubectl|helm\n' >&2
        return 2
        ;;
    esac
    eval "_shell_completion_loaded=\${_shell_completion_${_shell_completion_command}_loaded-0}"
    [[ $_shell_completion_loaded != 1 ]] || return 0

    local _shell_completion_shell _shell_completion_function
    if [[ -n ${ZSH_VERSION-} ]]; then
        _shell_completion_shell=zsh
        _shell_completion_function="_$_shell_completion_command"
    else
        _shell_completion_shell=bash
        _shell_completion_function="__start_$_shell_completion_command"
    fi
    local _shell_completion_script _shell_completion_spec _shell_completion_result=0
    # Check the generator's status before sourcing any possibly partial output.
    _shell_completion_script=$(command "$_shell_completion_command" completion "$_shell_completion_shell") || return $?
    if [[ -z $_shell_completion_script ]]; then
        printf 'Empty completion script from %s\n' "$_shell_completion_command" >&2
        return 1
    fi

    set --
    # Sourcing (rather than eval) confines any top-level return to the script.
    # No generic local names such as words/cur shadow the completion context.
    # shellcheck source=/dev/null
    source /dev/stdin <<< "$_shell_completion_script" || _shell_completion_result=$?
    if [[ $_shell_completion_result == 0 ]] && declare -f "$_shell_completion_function" >/dev/null; then
        if [[ -n ${ZSH_VERSION-} ]]; then
            [[ ${_comps[$_shell_completion_command]-} == "$_shell_completion_function" ]] || _shell_completion_result=1
        else
            _shell_completion_spec=$(complete -p "$_shell_completion_command" 2>/dev/null) || _shell_completion_spec=''
            case " $_shell_completion_spec " in
            *" -F $_shell_completion_function "*) ;;
            *) _shell_completion_result=1 ;;
            esac
        fi
        if [[ $_shell_completion_result == 0 ]]; then
            eval "_shell_completion_${_shell_completion_command}_loaded=1"
            return 0
        fi
    elif [[ $_shell_completion_result == 0 ]]; then
        _shell_completion_result=1
    fi

    # A script may have changed registration before failing; restore the lazy
    # entry so the next Tab can retry rather than leaving a broken completer.
    _shell_completion_register "$_shell_completion_command" || :
    return "$_shell_completion_result"
}

# Usage: environment_add ENVNAME PRIORITY DIR...
# Higher priorities come first; new entries keep their first-added order on ties.
# Existing entries start at priority 0. Re-adding an entry moves it to the front
# of its (possibly new) priority group, silently replacing the old entry.
function environment_add() {
    local _add_to_envname="${1-}" _add_to_priority="${2-}"
    if [[ $# -lt 2 ]] ||
        [[ ! $_add_to_envname =~ ^[a-zA-Z_][a-zA-Z0-9_]*$ ]] ||
        [[ $_add_to_envname == _add_to_* || $_add_to_envname == __add_to_* ]] ||
        ! isnum "$_add_to_priority"; then
        printf 'Usage: environment_add ENVNAME PRIORITY DIR... (PRIORITY must be an integer)\n' >&2
        return 1
    fi
    # Interpret leading zeros as decimal, not octal.
    if [[ $_add_to_priority == -* ]]; then
        _add_to_priority=$((-10#${_add_to_priority#-}))
    else
        _add_to_priority=$((10#$_add_to_priority))
    fi
    shift 2

    local _add_to_current _add_to_cached _add_to_cache_set _add_to_changed=0
    local _add_to_remaining _add_to_dir _add_to_separator _add_to_key
    local _add_to_zsh=0
    local _add_to_base=0 _add_to_i _add_to_j _add_to_found
    local -a _add_to_entries=() _add_to_priorities=()
    local -a _add_to_kept_entries=() _add_to_kept_priorities=() _add_to_order=()
    local -a _add_to_promoted=() _add_to_moved=()
    if [[ -n ${ZSH_VERSION-} ]]; then
        _add_to_zsh=1
        local -A _add_to_index=() _add_to_groups=()
        [[ -o ksharrays ]] || _add_to_base=1
    fi
    # Only validated variable names enter eval; values are never evaluated as code.
    eval "_add_to_current=\${$_add_to_envname-}"
    eval "_add_to_cached=\${__add_to_${_add_to_envname}_last-}"
    eval "_add_to_cache_set=\${__add_to_${_add_to_envname}_last+x}"
    eval "_add_to_entries=(\${__add_to_${_add_to_envname}_entries[@]+\"\${__add_to_${_add_to_envname}_entries[@]}\"})"
    eval "_add_to_priorities=(\${__add_to_${_add_to_envname}_priorities[@]+\"\${__add_to_${_add_to_envname}_priorities[@]}\"})"

    # Reconcile only after an external edit, not on every startup call.
    if [[ -z $_add_to_cache_set || $_add_to_current != "$_add_to_cached" ]]; then
        _add_to_changed=1
        for ((_add_to_i = _add_to_base; _add_to_i < _add_to_base + ${#_add_to_entries[@]}; _add_to_i++)); do
            [[ -n $_add_to_current ]] || break
            case ":$_add_to_current:" in
            *":${_add_to_entries[_add_to_i]}:"*)
                _add_to_kept_entries+=("${_add_to_entries[_add_to_i]}")
                _add_to_kept_priorities+=("${_add_to_priorities[_add_to_i]}")
                ;;
            esac
        done
        _add_to_entries=(${_add_to_kept_entries[@]+"${_add_to_kept_entries[@]}"})
        _add_to_priorities=(${_add_to_kept_priorities[@]+"${_add_to_kept_priorities[@]}"})
    fi

    # Zsh uses O(1) lookups; Bash 3.2 falls back to indexed-array scans.
    # Prefix keys so intentional empty PATH entries are valid hash keys too.
    if ((_add_to_zsh)); then
        for ((_add_to_i = _add_to_base; _add_to_i < _add_to_base + ${#_add_to_entries[@]}; _add_to_i++)); do
            _add_to_key=":${_add_to_entries[_add_to_i]}"
            _add_to_index[$_add_to_key]=$_add_to_i
        done
    fi
    if ((_add_to_changed)); then
        _add_to_remaining=$_add_to_current
        while [[ -n $_add_to_current ]]; do
            _add_to_dir=${_add_to_remaining%%:*}
            _add_to_found=0
            if ((_add_to_zsh)); then
                _add_to_key=":$_add_to_dir"
                [[ -n ${_add_to_index[$_add_to_key]+set} ]] && _add_to_found=1
            else
                for ((_add_to_i = _add_to_base; _add_to_i < _add_to_base + ${#_add_to_entries[@]}; _add_to_i++)); do
                    if [[ ${_add_to_entries[_add_to_i]} == "$_add_to_dir" ]]; then
                        _add_to_found=1
                        break
                    fi
                done
            fi
            if [[ $_add_to_found == 0 ]]; then
                if ((_add_to_zsh)); then
                    _add_to_index[$_add_to_key]=$((_add_to_base + ${#_add_to_entries[@]}))
                fi
                _add_to_entries+=("$_add_to_dir")
                _add_to_priorities+=(0)
            fi
            [[ $_add_to_remaining == *:* ]] || break
            _add_to_remaining=${_add_to_remaining#*:}
        done
    fi

    for _add_to_dir in "$@"; do
        [[ -d $_add_to_dir ]] || continue
        _add_to_found=0
        if ((_add_to_zsh)); then
            _add_to_key=":$_add_to_dir"
            if [[ -n ${_add_to_index[$_add_to_key]+set} ]]; then
                _add_to_i=${_add_to_index[$_add_to_key]}
                _add_to_found=1
            fi
        else
            for ((_add_to_i = _add_to_base; _add_to_i < _add_to_base + ${#_add_to_entries[@]}; _add_to_i++)); do
                if [[ ${_add_to_entries[_add_to_i]} == "$_add_to_dir" ]]; then
                    _add_to_found=1
                    break
                fi
            done
        fi
        if [[ $_add_to_found == 1 ]]; then
            _add_to_priorities[_add_to_i]=$_add_to_priority
            _add_to_promoted+=("$_add_to_i")
            _add_to_changed=1
        else
            if ((_add_to_zsh)); then
                _add_to_index[$_add_to_key]=$((_add_to_base + ${#_add_to_entries[@]}))
            fi
            _add_to_entries+=("$_add_to_dir")
            _add_to_priorities+=("$_add_to_priority")
            _add_to_changed=1
        fi
    done

    # Reinsert repeated entries first, most recently processed first. Rebuild
    # once so Zsh keeps O(1) lookups without shifting the arrays on each repeat.
    if ((${#_add_to_promoted[@]})); then
        _add_to_kept_entries=() _add_to_kept_priorities=()
        for ((_add_to_j = _add_to_base + ${#_add_to_promoted[@]} - 1; _add_to_j >= _add_to_base; _add_to_j--)); do
            _add_to_i=${_add_to_promoted[_add_to_j]}
            [[ ${_add_to_moved[_add_to_i]-0} == 1 ]] && continue
            _add_to_moved[_add_to_i]=1
            _add_to_kept_entries+=("${_add_to_entries[_add_to_i]}")
            _add_to_kept_priorities+=("${_add_to_priorities[_add_to_i]}")
        done
        for ((_add_to_i = _add_to_base; _add_to_i < _add_to_base + ${#_add_to_entries[@]}; _add_to_i++)); do
            [[ ${_add_to_moved[_add_to_i]-0} == 1 ]] && continue
            _add_to_kept_entries+=("${_add_to_entries[_add_to_i]}")
            _add_to_kept_priorities+=("${_add_to_priorities[_add_to_i]}")
        done
        _add_to_entries=(${_add_to_kept_entries[@]+"${_add_to_kept_entries[@]}"})
        _add_to_priorities=(${_add_to_kept_priorities[@]+"${_add_to_kept_priorities[@]}"})
    fi

    # No additions or promotions: no sorting or cache rewrite needed.
    if [[ $_add_to_changed == 0 ]]; then
        export "$_add_to_envname=$_add_to_current"
        return
    fi
    _add_to_current='' _add_to_separator=''
    if ((_add_to_zsh)); then
        # Group in current tie order, then sort only the distinct priorities.
        for ((_add_to_i = _add_to_base; _add_to_i < _add_to_base + ${#_add_to_entries[@]}; _add_to_i++)); do
            _add_to_key=${_add_to_priorities[_add_to_i]}
            if [[ -n ${_add_to_groups[$_add_to_key]+set} ]]; then
                _add_to_groups[$_add_to_key]+=":${_add_to_entries[_add_to_i]}"
            else
                _add_to_groups[$_add_to_key]=${_add_to_entries[_add_to_i]}
            fi
        done
        # Zsh-only expansion stays inside eval so Bash can parse this shared file.
        # O-n sorts signed integers descending; k selects associative-array keys.
        eval '_add_to_order=("${(@O-nk)_add_to_groups[@]}")'
        for _add_to_key in "${_add_to_order[@]}"; do
            _add_to_current="$_add_to_current$_add_to_separator${_add_to_groups[$_add_to_key]}"
            _add_to_separator=:
        done
    else
        # Stable insertion sort for shells without associative arrays.
        for ((_add_to_i = _add_to_base; _add_to_i < _add_to_base + ${#_add_to_entries[@]}; _add_to_i++)); do
            _add_to_j=$((_add_to_base + ${#_add_to_order[@]}))
            while ((_add_to_j > _add_to_base)); do
                ((_add_to_priorities[_add_to_i] > _add_to_priorities[_add_to_order[_add_to_j - 1]])) || break
                _add_to_order[_add_to_j]=${_add_to_order[_add_to_j - 1]}
                _add_to_j=$((_add_to_j - 1))
            done
            _add_to_order[_add_to_j]=$_add_to_i
        done
        for ((_add_to_j = _add_to_base; _add_to_j < _add_to_base + ${#_add_to_order[@]}; _add_to_j++)); do
            _add_to_i=${_add_to_order[_add_to_j]}
            _add_to_current="$_add_to_current$_add_to_separator${_add_to_entries[_add_to_i]}"
            _add_to_separator=:
        done
    fi
    export "$_add_to_envname=$_add_to_current" || return
    eval "__add_to_${_add_to_envname}_entries=(\${_add_to_entries[@]+\"\${_add_to_entries[@]}\"})"
    eval "__add_to_${_add_to_envname}_priorities=(\${_add_to_priorities[@]+\"\${_add_to_priorities[@]}\"})"
    eval "__add_to_${_add_to_envname}_last=\$_add_to_current"
}
