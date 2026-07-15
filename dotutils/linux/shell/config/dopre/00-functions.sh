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

    for dir in "$@"; do
        [[ -d "$dir" ]] || continue
        case ":$current_val:" in
        *":$dir:"*) ;;
        *) current_val="$dir:$current_val" ;;
        esac
    done

    eval "export $envname=\"$current_val\""
}
