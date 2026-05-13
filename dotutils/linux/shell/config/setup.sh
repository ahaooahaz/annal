#!/usr/bin/env bash
SHELL_ROOT_DIR=${SHELL_ROOT_DIR:-$HOME/.shell}

for f in "$SHELL_ROOT_DIR/dopre/"*; do
    [ -r "$f" ] && source "$f"
done

if [ -n "$BASH_VERSION" ]; then
    for f in "$SHELL_ROOT_DIR/bash/"*; do
        [ -r "$f" ] && source "$f"
    done
elif [ -n "$ZSH_VERSION" ]; then
    for f in "$SHELL_ROOT_DIR/zsh/"*; do
        [ -r "$f" ] && source "$f"
    done
fi

for f in "$SHELL_ROOT_DIR/dopost/"*; do
    [ -r "$f" ] && source "$f"
done
