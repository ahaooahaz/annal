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

# Expand every glob up front, in load order: shared -> per-shell -> shared.
_shell_files=("$SHELL_ROOT_DIR/dopre/"*)
if [ -n "$BASH_VERSION" ]; then
    _shell_files+=("$SHELL_ROOT_DIR/bash/"*)
elif [ -n "$ZSH_VERSION" ]; then
    _shell_files+=("$SHELL_ROOT_DIR/zsh/"*)
fi
_shell_files+=("$SHELL_ROOT_DIR/dopost/"*)

# Restore the caller's original nullglob setting. This has to happen *before*
# sourcing, otherwise it would also revert options the sourced files set for
# themselves (e.g. `setopt nullglob` in zsh/shell.zsh).
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

for f in "${_shell_files[@]}"; do
    # shellcheck source=/dev/null
    [ -r "$f" ] && source "$f"
done
unset _shell_files f
