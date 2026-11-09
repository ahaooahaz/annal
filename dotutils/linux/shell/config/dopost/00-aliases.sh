#!/usr/bin/env bash
# shellcheck shell=bash

if [[ "${CURROS}" == "Darwin" ]]; then
    alias make='gmake'
    alias timeout='gtimeout'
fi

if command -v nvim &>/dev/null; then
    alias v=nvim
    alias vi=nvim
    alias vim=nvim
fi
