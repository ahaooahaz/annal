#!/usr/bin/env bash
SHELL_ROOT_DIR=${SHELL_ROOT_DIR:-$HOME/.shell}

# Enable nullglob so an empty dir expands to nothing instead of a literal `*`.
if [ -n "$BASH_VERSION" ]; then
    _shell_nullglob_was_set=$(shopt -p nullglob)
    shopt -s nullglob
elif [ -n "$ZSH_VERSION" ]; then
    if [[ -o nullglob ]]; then
        _shell_nullglob_was_set=1
    else
        _shell_nullglob_was_set=0
    fi
    setopt nullglob
fi

for f in "$SHELL_ROOT_DIR/dopre/"*; do
    # shellcheck source=/dev/null
    [ -r "$f" ] && source "$f"
done

if [ -n "$BASH_VERSION" ]; then
    for f in "$SHELL_ROOT_DIR/bash/"*; do
        # shellcheck source=/dev/null
        [ -r "$f" ] && source "$f"
    done
elif [ -n "$ZSH_VERSION" ]; then
    for f in "$SHELL_ROOT_DIR/zsh/"*; do
        # shellcheck source=/dev/null
        [ -r "$f" ] && source "$f"
    done
fi

for f in "$SHELL_ROOT_DIR/dopost/"*; do
    # shellcheck source=/dev/null
    [ -r "$f" ] && source "$f"
done

# Restore the caller's original nullglob setting.
if [ -n "$BASH_VERSION" ]; then
    eval "$_shell_nullglob_was_set"
    unset _shell_nullglob_was_set
elif [ -n "$ZSH_VERSION" ]; then
    if [[ "$_shell_nullglob_was_set" == 1 ]]; then
        setopt nullglob
    else
        unsetopt nullglob
    fi
    unset _shell_nullglob_was_set
fi
